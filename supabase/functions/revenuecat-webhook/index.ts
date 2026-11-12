import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { decideRevenueCatEntitlement, isLedgerlyAccountId } from "../_shared/revenuecat.ts";

type RevenueCatEventQuery = {
  eq: (column: string, value: string) => RevenueCatEventQuery;
  maybeSingle: () => Promise<{ data: { event_id: string } | null; error: { message?: string } | null }>;
};

type RevenueCatAdmin = {
  from: (table: string) => {
    select: (columns: string) => RevenueCatEventQuery;
    insert: (row: Record<string, unknown>) => Promise<{ error: { code?: string; message?: string } | null }>;
  };
  rpc: (name: string, args: Record<string, unknown>) => Promise<{ error: { message?: string } | null }>;
};

type RevenueCatWebhookDependencies = {
  env: (name: string) => string | undefined;
  createAdmin: (url: string, serviceKey: string) => RevenueCatAdmin;
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "Content-Type": "application/json" },
});

export async function handleRevenueCatWebhook(
  req: Request,
  dependencies: RevenueCatWebhookDependencies,
): Promise<Response> {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const expected = dependencies.env("REVENUECAT_WEBHOOK_AUTH");
  const url = dependencies.env("SUPABASE_URL");
  const serviceKey = dependencies.env("SUPABASE_SERVICE_ROLE_KEY");
  if (!expected || !url || !serviceKey) {
    return json({ error: "Webhook not configured" }, 503);
  }
  if (req.headers.get("Authorization") !== expected) {
    return json({ error: "Unauthorized" }, 401);
  }

  try {
    const payload = await req.json();
    const event = payload?.event;
    const eventId = event?.id;
    const userId = event?.app_user_id;
    const type = event?.type;
    if (typeof eventId !== "string" || typeof userId !== "string" || typeof type !== "string") {
      return json({ error: "Invalid RevenueCat event" }, 400);
    }
    // Purchases must be tied to a signed-in Ledgerly account, never an anonymous RC ID.
    if (!isLedgerlyAccountId(userId)) {
      return json({ error: "Unknown Ledgerly account reference" }, 400);
    }

    const admin = dependencies.createAdmin(url, serviceKey);
    const { data: existing, error: duplicateCheckError } = await admin
      .from("billing_webhook_events")
      .select("event_id")
      .eq("provider", "revenuecat")
      .eq("event_id", eventId)
      .maybeSingle();
    if (duplicateCheckError) {
      console.error("RevenueCat webhook duplicate check failed", duplicateCheckError);
      return json({ error: "Could not check webhook idempotency" }, 500);
    }
    if (existing) return json({ received: true, duplicate: true });

    const terminal = type === "EXPIRATION" || type === "REFUND";
    const entitlementIds = Array.isArray(event.entitlement_ids) ? event.entitlement_ids : [];
    if (!entitlementIds.includes("ledgerly_pro") && !terminal) {
      const { error } = await admin.from("billing_webhook_events").insert({
        provider: "revenuecat",
        event_id: eventId,
      });
      if (error && error.code !== "23505") {
        return json({ error: "Could not record ignored event" }, 500);
      }
      return json({ received: true, ignored: true });
    }

    const eventTimestampMs = Number(event.event_timestamp_ms);
    let decision: ReturnType<typeof decideRevenueCatEntitlement>;
    try {
      decision = decideRevenueCatEntitlement({
        type,
        eventTimestampMs,
        expirationAtMs: event.expiration_at_ms == null
          ? null
          : Number(event.expiration_at_ms),
        gracePeriodExpirationAtMs: event.grace_period_expiration_at_ms == null
          ? null
          : Number(event.grace_period_expiration_at_ms),
      }, new Date());
    } catch (error) {
      return json({
        error: error instanceof Error ? error.message : "Invalid RevenueCat event",
      }, 400);
    }
    if (!decision) {
      const { error } = await admin.from("billing_webhook_events").insert({
        provider: "revenuecat",
        event_id: eventId,
      });
      if (error && error.code !== "23505") {
        return json({ error: "Could not record ignored event" }, 500);
      }
      return json({ received: true, ignored: true });
    }
    const status = decision.status;
    const periodEnd = decision.periodEnd;
    const eventDate = new Date(eventTimestampMs);

    const originalId = event.original_transaction_id ?? event.transaction_id ?? eventId;
    const externalId = String(originalId);
    const { error } = await admin.rpc("apply_revenuecat_entitlement", {
      p_user_id: userId,
      p_subscription_id: externalId,
      p_product_id: typeof event.product_id === "string" ? event.product_id : null,
      p_status: status,
      p_period_end: periodEnd,
      p_event_id: eventId,
      p_status_updated_at: eventDate.toISOString(),
    });
    if (error) {
      console.error("RevenueCat entitlement update failed", error);
      return json({ error: "Could not update subscription status" }, 500);
    }

    const { error: recordError } = await admin.from("billing_webhook_events").insert({
      provider: "revenuecat",
      event_id: eventId,
    });
    if (recordError && recordError.code !== "23505") {
      return json({ error: "Could not record event" }, 500);
    }
    return json({ received: true });
  } catch (error) {
    console.error("RevenueCat webhook error", error);
    return json({ error: "Webhook processing failed" }, 500);
  }
}

if (import.meta.main) {
  Deno.serve((req) => handleRevenueCatWebhook(req, {
    env: (name) => Deno.env.get(name),
    createAdmin: (url, serviceKey) => createClient(url, serviceKey, {
      auth: { persistSession: false },
    }) as unknown as RevenueCatAdmin,
  }));
}
