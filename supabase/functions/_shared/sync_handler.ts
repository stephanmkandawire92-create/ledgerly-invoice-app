// Request logic for POST /functions/v1/paypal-sync-subscription.
//
// The app calls this after returning from PayPal and whenever the customer
// taps "Check payment status". It returns the server's entitlement and, when a
// checkout is outstanding, reconciles it with PayPal's canonical record.
// A browser redirect alone never grants Pro.

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
  decideFromCanonicalSubscription,
  fetchSubscription,
  getAccessToken,
  LEDGERLY_PRO_PLAN,
  parseCheckoutReference,
  PaypalApiError,
  subscriptionMatchesPlan,
  type PaypalFetch,
} from "./paypal.ts";
import type { EntitlementSnapshot, SyncStore } from "./types.ts";

export const FUNCTION_NAME = "paypal-sync-subscription";

/** Minimum interval between PayPal round-trips for one account. */
export const RECONCILE_COOLDOWN_MS = 10_000;

export function isEntitled(row: EntitlementSnapshot | null, now: Date): boolean {
  if (!row) return false;
  if (row.status === "active") {
    return row.currentPeriodEnd === null || Date.parse(row.currentPeriodEnd) > now.getTime();
  }
  if (row.status === "cancelled") {
    return row.currentPeriodEnd !== null && Date.parse(row.currentPeriodEnd) > now.getTime();
  }
  return false;
}

export interface SyncRuntime {
  env: EnvReader;
  fetch: PaypalFetch;
  now: () => Date;
  authenticate: (
    settings: SupabaseSettings,
    authorization: string,
  ) => Promise<{ userId: string } | null>;
  syncStore: (settings: SupabaseSettings) => SyncStore;
  log: (message: string, detail?: unknown) => void;
}

export function createSyncHandler(runtime: SyncRuntime) {
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

    const store = runtime.syncStore(supabase);
    const now = runtime.now();

    const respond = (
      row: EntitlementSnapshot | null,
      subscriptionId: string | null,
      extra: Record<string, unknown> = {},
    ) => jsonResponse(
      {
        status: row?.status ?? "none",
        isPro: isEntitled(row, now),
        provider: row ? "paypal" : null,
        subscriptionId: row?.subscriptionId ?? subscriptionId,
        currentPeriodEnd: row?.currentPeriodEnd ?? null,
        checkedAt: now.toISOString(),
        ...extra,
      },
      200,
      cors,
    );

    try {
      const entitlement = await store.getEntitlement(account.userId);
      const attempt = await store.getLatestAttempt(account.userId);
      const subscriptionId = attempt?.subscriptionId ?? entitlement?.subscriptionId ?? null;

      if (!subscriptionId) return respond(entitlement, null);

      const lastWrite = Date.parse(entitlement?.updatedAt ?? attempt?.updatedAt ?? "");
      const recentlyChecked = Number.isFinite(lastWrite) &&
        now.getTime() - lastWrite < RECONCILE_COOLDOWN_MS;
      if (recentlyChecked && entitlement) return respond(entitlement, subscriptionId);

      const token = await getAccessToken(paypal, runtime.fetch);
      const subscription = await fetchSubscription(paypal.apiBase, subscriptionId, token, runtime.fetch);

      if (!subscriptionMatchesPlan(subscription, paypal.planId)) {
        runtime.log(`${FUNCTION_NAME}: subscription is not on the Ledgerly plan`);
        return jsonResponse(
          { error: publicErrors.planMismatch.message, code: publicErrors.planMismatch.code },
          publicErrors.planMismatch.status,
          cors,
        );
      }

      const reference = parseCheckoutReference(subscription.custom_id);
      if (!reference || reference.userId !== account.userId) {
        runtime.log(`${FUNCTION_NAME}: subscription account mismatch`);
        return jsonResponse(
          { error: "Subscription does not belong to this account.", code: "account_mismatch" },
          403,
          cors,
        );
      }

      const decision = decideFromCanonicalSubscription(
        subscription,
        {
          previousStatus: entitlement?.status ?? null,
          previousPeriodEnd: entitlement?.currentPeriodEnd ?? null,
          previousVersionTime: entitlement?.providerStatusUpdatedAt ?? null,
        },
        now,
        LEDGERLY_PRO_PLAN,
      );

      if (decision.action === "apply") {
        const applied = await store.applyEntitlement({
          userId: account.userId,
          subscriptionId,
          productId: paypal.planId,
          status: decision.status,
          periodEnd: decision.periodEnd,
          eventId: `sync:${now.toISOString()}`,
          statusUpdatedAt: decision.versionTime,
        });
        if (!applied.ok) {
          runtime.log(`${FUNCTION_NAME}: entitlement write failed`, applied.error);
          return jsonResponse(
            { error: publicErrors.internal.message, code: "entitlement_write_failed" },
            500,
            cors,
          );
        }
      }

      const refreshed = await store.getEntitlement(account.userId);
      return respond(refreshed, subscriptionId);
    } catch (error) {
      if (error instanceof PaypalApiError) {
        runtime.log(`${FUNCTION_NAME}: PayPal API error`, {
          message: error.message,
          status: error.status,
        });
        if (error.status === 404) {
          return respond(await store.getEntitlement(account.userId), null);
        }
        return jsonResponse(
          { error: publicErrors.providerUnavailable.message, code: publicErrors.providerUnavailable.code },
          publicErrors.providerUnavailable.status,
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
