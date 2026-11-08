// supabase-js implementations of the store interfaces used by the handlers.
//
// Every SQL statement the billing flow depends on lives here so it can be
// reviewed in one place.

import type {
  CheckoutStore,
  EntitlementSnapshot,
  Reservation,
  SyncStore,
  WebhookStore,
} from "./types.ts";

export type {
  ApplyEntitlementArgs,
  CheckoutStore,
  EntitlementSnapshot,
  Reservation,
  SyncStore,
  WebhookStore,
} from "./types.ts";

// ---------------------------------------------------------------------------
// supabase-js implementations
// ---------------------------------------------------------------------------

// This project has no generated `Database` type, so supabase-js resolves its
// table generics to `never`. The stores below are a thin, reviewed adapter and
// the handler layer is fully typed, so the client is intentionally loose here
// rather than pretending generated types exist.
// deno-lint-ignore no-explicit-any
type AdminClient = any;

function reservationFromRow(row: Record<string, unknown> | null): Reservation | null {
  if (!row || typeof row.disposition !== "string") return null;
  return {
    disposition: row.disposition,
    requestId: typeof row.request_id === "string" ? row.request_id : null,
    approvalUrl: typeof row.approval_url === "string" ? row.approval_url : null,
    subscriptionId: typeof row.subscription_id === "string" ? row.subscription_id : null,
  };
}

export function createCheckoutStore(admin: AdminClient): CheckoutStore {
  return {
    async claimCheckout(userId, requestId) {
      const { data, error } = await admin.rpc("claim_paypal_checkout", {
        p_user_id: userId,
        p_request_id: requestId,
      });
      if (error) return { ok: false, error: error.message };
      const row = (Array.isArray(data) ? data[0] : data) as Record<string, unknown> | null;
      const reservation = reservationFromRow(row);
      if (!reservation) return { ok: false, error: "reservation row missing" };
      return { ok: true, reservation };
    },

    async releaseRejectedCheckout(requestId) {
      const { error } = await admin
        .from("paypal_checkout_attempts")
        .update({ status: "failed", updated_at: new Date().toISOString() })
        .eq("request_id", requestId)
        .eq("status", "creating");
      if (error) console.error("releaseRejectedCheckout failed", error.message);
    },

    async saveApproval({ requestId, subscriptionId, approvalUrl }) {
      const { data, error } = await admin
        .from("paypal_checkout_attempts")
        .update({
          subscription_id: subscriptionId,
          approval_url: approvalUrl,
          status: "pending",
          updated_at: new Date().toISOString(),
        })
        .eq("request_id", requestId)
        .eq("status", "creating")
        .select("id");
      if (error) return { ok: false, error: error.message };
      return { ok: true, updated: Array.isArray(data) && data.length > 0 };
    },

    async readAttempt(requestId) {
      const { data, error } = await admin
        .from("paypal_checkout_attempts")
        .select("user_id,request_id,subscription_id,approval_url,status,updated_at")
        .eq("request_id", requestId)
        .maybeSingle();
      if (error || !data) return null;
      return {
        userId: String(data.user_id),
        requestId: String(data.request_id),
        subscriptionId: typeof data.subscription_id === "string" ? data.subscription_id : null,
        approvalUrl: typeof data.approval_url === "string" ? data.approval_url : null,
        status: String(data.status),
        updatedAt: String(data.updated_at),
      };
    },
  };
}

export function createWebhookStore(admin: AdminClient): WebhookStore {
  return {
    async hasEvent(eventId) {
      const { data, error } = await admin
        .from("billing_webhook_events")
        .select("event_id")
        .eq("provider", "paypal")
        .eq("event_id", eventId)
        .maybeSingle();
      if (error) throw new Error(`idempotency check failed: ${error.message}`);
      return Boolean(data);
    },

    async recordEvent(eventId) {
      const { error } = await admin
        .from("billing_webhook_events")
        .insert({ provider: "paypal", event_id: eventId });
      if (error && error.code !== "23505") return { ok: false, error: error.message };
      return { ok: true };
    },

    async getEntitlement(subscriptionId) {
      const { data, error } = await admin
        .from("subscription_entitlements")
        .select("user_id,status,current_period_end,provider_status_updated_at,updated_at,external_subscription_id")
        .eq("provider", "paypal")
        .eq("external_subscription_id", subscriptionId)
        .maybeSingle();
      if (error) throw new Error(`entitlement read failed: ${error.message}`);
      if (!data) return null;
      return {
        userId: String(data.user_id),
        status: String(data.status),
        currentPeriodEnd: (data.current_period_end as string | null) ?? null,
        providerStatusUpdatedAt: (data.provider_status_updated_at as string | null) ?? null,
        updatedAt: String(data.updated_at),
        subscriptionId: String(data.external_subscription_id),
      };
    },

    async getCheckoutOwner(requestId) {
      const { data, error } = await admin
        .from("paypal_checkout_attempts")
        .select("user_id")
        .eq("request_id", requestId)
        .maybeSingle();
      if (error) throw new Error(`checkout read failed: ${error.message}`);
      return data ? { userId: String(data.user_id) } : null;
    },

    async applyEntitlement(args) {
      const { data, error } = await admin.rpc("apply_paypal_entitlement", {
        p_user_id: args.userId,
        p_subscription_id: args.subscriptionId,
        p_product_id: args.productId,
        p_status: args.status,
        p_period_end: args.periodEnd,
        p_event_id: args.eventId,
        p_status_updated_at: args.statusUpdatedAt,
      });
      if (error) return { ok: false, error: error.message };
      return { ok: true, applied: data === true };
    },

    async updateCheckout({ requestId, userId, subscriptionId, status }) {
      const { error } = await admin
        .from("paypal_checkout_attempts")
        .update({ subscription_id: subscriptionId, status, updated_at: new Date().toISOString() })
        .eq("request_id", requestId)
        .eq("user_id", userId);
      if (error) return { ok: false, error: error.message };
      return { ok: true };
    },
  };
}

export function createSyncStore(admin: AdminClient): SyncStore {
  const selectEntitlement = async (column: "user_id", value: string) => {
    const { data, error } = await admin
      .from("subscription_entitlements")
      .select("user_id,status,current_period_end,provider_status_updated_at,updated_at,external_subscription_id")
      .eq(column, value)
      .eq("provider", "paypal")
      .order("updated_at", { ascending: false })
      .limit(1);
    if (error) throw new Error(`entitlement read failed: ${error.message}`);
    const row = (data ?? [])[0];
    if (!row) return null;
    return {
      userId: String(row.user_id),
      status: String(row.status),
      currentPeriodEnd: (row.current_period_end as string | null) ?? null,
      providerStatusUpdatedAt: (row.provider_status_updated_at as string | null) ?? null,
      updatedAt: String(row.updated_at),
      subscriptionId: String(row.external_subscription_id),
    } satisfies EntitlementSnapshot;
  };

  return {
    getEntitlement: (userId) => selectEntitlement("user_id", userId),

    async getLatestAttempt(userId) {
      const { data, error } = await admin
        .from("paypal_checkout_attempts")
        .select("user_id,request_id,subscription_id,approval_url,status,updated_at")
        .eq("user_id", userId)
        .not("subscription_id", "is", null)
        .order("updated_at", { ascending: false })
        .limit(1);
      if (error) throw new Error(`checkout read failed: ${error.message}`);
      const row = (data ?? [])[0];
      if (!row) return null;
      return {
        userId: String(row.user_id),
        requestId: String(row.request_id),
        subscriptionId: typeof row.subscription_id === "string" ? row.subscription_id : null,
        approvalUrl: typeof row.approval_url === "string" ? row.approval_url : null,
        status: String(row.status),
        updatedAt: String(row.updated_at),
      };
    },

    async applyEntitlement(args) {
      const { error } = await admin.rpc("apply_paypal_entitlement", {
        p_user_id: args.userId,
        p_subscription_id: args.subscriptionId,
        p_product_id: args.productId,
        p_status: args.status,
        p_period_end: args.periodEnd,
        p_event_id: args.eventId,
        p_status_updated_at: args.statusUpdatedAt,
      });
      if (error) return { ok: false, error: error.message };
      return { ok: true };
    },
  };
}
