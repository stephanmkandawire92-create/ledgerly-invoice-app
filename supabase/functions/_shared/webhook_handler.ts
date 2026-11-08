// Request logic for POST /functions/v1/paypal-webhook.

import {
  isConfigFailure,
  mergeFailures,
  readPayPalSettings,
  readSupabaseSettings,
  type EnvReader,
  type SupabaseSettings,
} from "./config.ts";
import { jsonResponse, publicErrors } from "./http.ts";
import {
  decideEntitlement,
  extractSaleAmount,
  extractSubscriptionId,
  fetchSubscription,
  getAccessToken,
  isSupportedEvent,
  parseCheckoutReference,
  PaypalApiError,
  readSignatureHeaders,
  subscriptionMatchesPlan,
  verifyWebhookSignature,
  type PaypalEvent,
  type PaypalFetch,
} from "./paypal.ts";
import type { CheckoutStore, WebhookStore } from "./types.ts";

export const FUNCTION_NAME = "paypal-webhook";

export interface WebhookRuntime {
  env: EnvReader;
  fetch: PaypalFetch;
  now: () => Date;
  webhookStore: (settings: SupabaseSettings) => WebhookStore;
  checkoutStore: (settings: SupabaseSettings) => CheckoutStore;
  log: (message: string, detail?: unknown) => void;
}

export function createWebhookHandler(runtime: WebhookRuntime) {
  return async function handle(req: Request): Promise<Response> {
    if (req.method !== "POST") {
      return jsonResponse(
        { error: publicErrors.methodNotAllowed.message, code: publicErrors.methodNotAllowed.code },
        publicErrors.methodNotAllowed.status,
      );
    }

    const rawBody = await req.text();
    if (!rawBody) {
      return jsonResponse({ error: "Empty request body", code: "empty_body" }, 400);
    }

    let event: PaypalEvent;
    try {
      event = JSON.parse(rawBody) as PaypalEvent;
    } catch {
      return jsonResponse({ error: "Malformed event body", code: "malformed_body" }, 400);
    }

    const paypalConfig = readPayPalSettings(runtime.env, { requireWebhookId: true });
    const supabaseConfig = readSupabaseSettings(runtime.env, { requireAnonKey: false });
    if (isConfigFailure(paypalConfig) || isConfigFailure(supabaseConfig)) {
      const failure = mergeFailures([paypalConfig, supabaseConfig].filter(isConfigFailure));
      runtime.log(`${FUNCTION_NAME}: configuration incomplete`, {
        missing: failure.missing,
        invalid: failure.invalid,
      });
      return jsonResponse({ error: "Webhook not configured", code: "webhook_not_configured" }, 503);
    }

    const paypal = paypalConfig.value;
    const supabase = supabaseConfig.value;
    const store = runtime.webhookStore(supabase);

    try {
      const token = await getAccessToken(paypal, runtime.fetch);
      const signature = readSignatureHeaders(req.headers);
      const verified = await verifyWebhookSignature(paypal, token, signature, event, runtime.fetch);
      if (!verified) {
        runtime.log(`${FUNCTION_NAME}: signature verification failed`);
        return jsonResponse({ error: "Invalid webhook signature", code: "invalid_signature" }, 401);
      }

      const eventId = typeof event.id === "string" ? event.id : null;
      const eventType = typeof event.event_type === "string" ? event.event_type : null;
      if (!eventId || !eventType) {
        return jsonResponse({ error: "Invalid event", code: "invalid_event" }, 400);
      }

      const recordAndAcknowledge = async (extra: Record<string, unknown> = {}) => {
        const recorded = await store.recordEvent(eventId);
        if (!recorded.ok) {
          runtime.log(`${FUNCTION_NAME}: could not record event`, recorded.error);
          return jsonResponse({ error: "Could not record event", code: "record_failed" }, 500);
        }
        return jsonResponse({ received: true, ...extra }, 200);
      };

      if (await store.hasEvent(eventId)) {
        return jsonResponse({ received: true, duplicate: true }, 200);
      }

      const subscriptionId = extractSubscriptionId(event);
      if (!subscriptionId || !isSupportedEvent(eventType)) {
        return await recordAndAcknowledge({ ignored: true });
      }

      const subscription = await fetchSubscription(
        paypal.apiBase,
        subscriptionId,
        token,
        runtime.fetch,
      );

      if (!subscriptionMatchesPlan(subscription, paypal.planId)) {
        runtime.log(`${FUNCTION_NAME}: subscription is not on the Ledgerly plan`, { eventType });
        return await recordAndAcknowledge({ ignored: true });
      }

      const reference = parseCheckoutReference(subscription.custom_id);
      if (!reference) {
        runtime.log(`${FUNCTION_NAME}: subscription has no valid account reference`, { eventType });
        return await recordAndAcknowledge({ ignored: true });
      }

      if (reference.requestId) {
        const owner = await store.getCheckoutOwner(reference.requestId);
        if (owner && owner.userId !== reference.userId) {
          runtime.log(`${FUNCTION_NAME}: checkout reservation belongs to another account`);
          return jsonResponse({ error: "Subscription account mismatch", code: "account_mismatch" }, 400);
        }
      }

      const previous = await store.getEntitlement(subscriptionId);
      if (previous && previous.userId !== reference.userId) {
        runtime.log(`${FUNCTION_NAME}: subscription is already bound to another account`);
        return jsonResponse({ error: "Subscription account mismatch", code: "account_mismatch" }, 400);
      }

      const decision = decideEntitlement({
        eventType,
        subscription,
        eventTime: typeof event.create_time === "string" ? event.create_time : null,
        saleAmount: extractSaleAmount(event),
        context: {
          previousStatus: previous?.status ?? null,
          previousPeriodEnd: previous?.currentPeriodEnd ?? null,
          previousVersionTime: previous?.providerStatusUpdatedAt ?? null,
        },
        now: runtime.now(),
      });

      if (decision.action === "ignore") {
        return await recordAndAcknowledge({ ignored: true, reason: decision.reason });
      }

      const applied = await store.applyEntitlement({
        userId: reference.userId,
        subscriptionId,
        productId: paypal.planId,
        status: decision.status,
        periodEnd: decision.periodEnd,
        eventId,
        statusUpdatedAt: decision.versionTime,
      });
      if (!applied.ok) {
        runtime.log(`${FUNCTION_NAME}: entitlement write failed`, applied.error);
        return jsonResponse(
          { error: "Could not update subscription", code: "entitlement_write_failed" },
          500,
        );
      }

      // The reservation is only a mirror of the entitlement; a failure here is
      // logged but must not fail the webhook after the entitlement succeeded.
      if (applied.applied && reference.requestId) {
        const updated = await store.updateCheckout({
          requestId: reference.requestId,
          userId: reference.userId,
          subscriptionId,
          status: decision.status,
        });
        if (!updated.ok) {
          runtime.log(`${FUNCTION_NAME}: could not update checkout reservation`, updated.error);
        }
      }

      return await recordAndAcknowledge();
    } catch (error) {
      if (error instanceof PaypalApiError) {
        runtime.log(`${FUNCTION_NAME}: PayPal API error`, {
          message: error.message,
          status: error.status,
        });
        if (error.status === 404) {
          return jsonResponse({ received: true, ignored: true }, 200);
        }
        return jsonResponse(
          { error: "PayPal verification unavailable", code: "provider_unavailable" },
          502,
        );
      }
      runtime.log(`${FUNCTION_NAME}: unexpected failure`, error);
      return jsonResponse({ error: "Webhook processing failed", code: "internal_error" }, 500);
    }
  };
}
