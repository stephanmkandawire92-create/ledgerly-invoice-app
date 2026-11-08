// Request logic for POST /functions/v1/paypal-create-subscription.

import {
  isConfigFailure,
  mergeFailures,
  readPayPalSettings,
  readSupabaseSettings,
  type EnvReader,
  type SupabaseSettings,
} from "./config.ts";
import {
  jsonResponse,
  preflightResponse,
  publicErrors,
  rejectDisallowedOrigin,
} from "./http.ts";
import {
  fetchPlan,
  getAccessToken,
  LEDGERLY_PRO_PLAN,
  PaypalApiError,
  verifyPlan,
  type PaypalFetch,
} from "./paypal.ts";
import type { CheckoutStore } from "./types.ts";

export const FUNCTION_NAME = "paypal-create-subscription";

export interface HandlerRuntime {
  env: EnvReader;
  fetch: PaypalFetch;
  now: () => Date;
  authenticate: (
    settings: SupabaseSettings,
    authorization: string,
  ) => Promise<{ userId: string } | null>;
  checkoutStore: (settings: SupabaseSettings) => CheckoutStore;
  log: (message: string, detail?: unknown) => void;
}

export function createCheckoutHandler(runtime: HandlerRuntime) {
  return async function handle(req: Request): Promise<Response> {
    const origin = req.headers.get("Origin");
    const paypalConfig = readPayPalSettings(runtime.env, { requireWebhookId: false });
    const supabaseConfig = readSupabaseSettings(runtime.env, { requireAnonKey: true });
    const allowedOrigin = paypalConfig.ok ? paypalConfig.value.allowedOrigin : null;
    const cors: Record<string, string> = allowedOrigin && origin === allowedOrigin
      ? { "Access-Control-Allow-Origin": allowedOrigin, Vary: "Origin" }
      : { Vary: "Origin" };

    if (isConfigFailure(paypalConfig) || isConfigFailure(supabaseConfig)) {
      const failure = mergeFailures([paypalConfig, supabaseConfig].filter(isConfigFailure));
      runtime.log(`${FUNCTION_NAME}: configuration incomplete`, {
        missing: failure.missing,
        invalid: failure.invalid,
      });
      return jsonResponse(
        { error: publicErrors.notConfigured.message, code: publicErrors.notConfigured.code },
        publicErrors.notConfigured.status,
        cors,
      );
    }

    if (req.method === "OPTIONS") return preflightResponse(origin, allowedOrigin);

    const blocked = rejectDisallowedOrigin(origin, allowedOrigin);
    if (blocked) return blocked;


    if (req.method !== "POST") {
      return jsonResponse(
        { error: publicErrors.methodNotAllowed.message, code: publicErrors.methodNotAllowed.code },
        publicErrors.methodNotAllowed.status,
        cors,
      );
    }

    const paypal = paypalConfig.value;
    const supabase = supabaseConfig.value;

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return jsonResponse(
        { error: publicErrors.signInRequired.message, code: publicErrors.signInRequired.code },
        publicErrors.signInRequired.status,
        cors,
      );
    }

    const account = await runtime.authenticate(supabase, authHeader);
    if (!account) {
      return jsonResponse(
        { error: publicErrors.sessionExpired.message, code: publicErrors.sessionExpired.code },
        publicErrors.sessionExpired.status,
        cors,
      );
    }

    const store = runtime.checkoutStore(supabase);

    try {
      const token = await getAccessToken(paypal, runtime.fetch);

      const plan = await fetchPlan(paypal.apiBase, paypal.planId, token, runtime.fetch);
      const planCheck = verifyPlan(plan, LEDGERLY_PRO_PLAN);
      if (!planCheck.ok) {
        runtime.log(`${FUNCTION_NAME}: PayPal plan rejected`, {
          reason: planCheck.reason,
          environment: paypal.environment,
        });
        return jsonResponse(
          { error: publicErrors.planMismatch.message, code: publicErrors.planMismatch.code },
          publicErrors.planMismatch.status,
          cors,
        );
      }

      const requestId = crypto.randomUUID();
      const claim = await store.claimCheckout(account.userId, requestId);
      if (!claim.ok) {
        runtime.log(`${FUNCTION_NAME}: checkout reservation failed`, claim.error);
        return jsonResponse(
          { error: publicErrors.checkoutFailed.message, code: "reservation_failed" },
          publicErrors.checkoutFailed.status,
          cors,
        );
      }
      const reservation = claim.reservation;

      if (reservation.disposition === "entitled") {
        return jsonResponse(
          { error: publicErrors.alreadyEntitled.message, code: publicErrors.alreadyEntitled.code },
          publicErrors.alreadyEntitled.status,
          cors,
        );
      }
      if (reservation.disposition === "payment_issue") {
        return jsonResponse(
          { error: publicErrors.paymentIssue.message, code: publicErrors.paymentIssue.code },
          publicErrors.paymentIssue.status,
          cors,
        );
      }
      if (reservation.approvalUrl && reservation.subscriptionId) {
        return jsonResponse(
          { approvalUrl: reservation.approvalUrl, subscriptionId: reservation.subscriptionId },
          200,
          cors,
        );
      }
      if (!reservation.requestId) {
        return jsonResponse(
          { error: publicErrors.checkoutFailed.message, code: "reservation_invalid" },
          publicErrors.checkoutFailed.status,
          cors,
        );
      }

      const providerRequestId = reservation.requestId;
      const created = await runtime.fetch(`${paypal.apiBase}/v1/billing/subscriptions`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
          Prefer: "return=representation",
          // Idempotent provider call: a retried request never creates a second
          // subscription or a second charge.
          "PayPal-Request-Id": providerRequestId,
        },
        body: JSON.stringify({
          plan_id: paypal.planId,
          custom_id: `${account.userId}:${providerRequestId}`,
          application_context: {
            brand_name: "Ledgerly",
            locale: "en-US",
            shipping_preference: "NO_SHIPPING",
            user_action: "SUBSCRIBE_NOW",
            return_url: paypal.returnUrl,
            cancel_url: paypal.cancelUrl,
          },
        }),
      });

      const result = await created.json().catch(() => ({})) as Record<string, unknown>;
      if (!created.ok) {
        if ([400, 401, 403, 404, 422].includes(created.status)) {
          await store.releaseRejectedCheckout(providerRequestId);
        }
        runtime.log(`${FUNCTION_NAME}: PayPal subscription creation failed`, {
          status: created.status,
          name: result.name,
        });
        return jsonResponse(
          { error: publicErrors.checkoutFailed.message, code: publicErrors.checkoutFailed.code },
          publicErrors.checkoutFailed.status,
          cors,
        );
      }

      const links = Array.isArray(result.links)
        ? result.links as Array<{ rel?: string; href?: string }>
        : [];
      const approval = links.find((link) => link.rel === "approve")?.href;
      const subscriptionId = result.id;
      if (typeof approval !== "string" || typeof subscriptionId !== "string") {
        runtime.log(`${FUNCTION_NAME}: incomplete PayPal response`);
        return jsonResponse(
          { error: publicErrors.checkoutFailed.message, code: "incomplete_provider_response" },
          publicErrors.checkoutFailed.status,
          cors,
        );
      }

      const saved = await store.saveApproval({
        requestId: providerRequestId,
        subscriptionId,
        approvalUrl: approval,
      });
      if (!saved.ok) {
        runtime.log(`${FUNCTION_NAME}: could not persist checkout`, saved.error);
        return jsonResponse(
          { error: publicErrors.checkoutFailed.message, code: "checkout_persist_failed" },
          publicErrors.checkoutFailed.status,
          cors,
        );
      }
      if (!saved.updated) {
        const attempt = await store.readAttempt(providerRequestId);
        const valid = attempt?.subscriptionId === subscriptionId &&
          typeof attempt?.approvalUrl === "string" &&
          ["pending", "active", "cancelled", "expired", "past_due", "suspended"].includes(attempt.status);
        if (!valid) {
          runtime.log(`${FUNCTION_NAME}: checkout finalization could not be confirmed`);
          return jsonResponse(
            { error: publicErrors.checkoutFailed.message, code: "checkout_finalize_failed" },
            publicErrors.checkoutFailed.status,
            cors,
          );
        }
      }

      // Approval is not payment: no entitlement is written here.
      return jsonResponse({ approvalUrl: approval, subscriptionId }, 200, cors);
    } catch (error) {
      if (error instanceof PaypalApiError) {
        runtime.log(`${FUNCTION_NAME}: PayPal API error`, {
          message: error.message,
          status: error.status,
        });
        return jsonResponse(
          {
            error: error.transient
              ? publicErrors.providerUnavailable.message
              : publicErrors.checkoutFailed.message,
            code: error.transient
              ? publicErrors.providerUnavailable.code
              : publicErrors.checkoutFailed.code,
          },
          error.transient
            ? publicErrors.providerUnavailable.status
            : publicErrors.checkoutFailed.status,
          cors,
        );
      }
      runtime.log(`${FUNCTION_NAME}: unexpected failure`, error);
      return jsonResponse(
        { error: publicErrors.internal.message, code: publicErrors.internal.code },
        publicErrors.internal.status,
        cors,
      );
    }
  };
}
