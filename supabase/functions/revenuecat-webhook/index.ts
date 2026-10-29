import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json" },
});

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const expected = Deno.env.get("REVENUECAT_WEBHOOK_AUTH");
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!expected || !url || !serviceKey) return json({ error: "Webhook not configured" }, 503);
  if (req.headers.get("Authorization") !== expected) return json({ error: "Unauthorized" }, 401);

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
    if (!/^[0-9a-f]{8}-[0-9a-f-]{27,}$/i.test(userId)) {
      return json({ error: "Unknown Ledgerly account reference" }, 400);
    }

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
    const { data: existing } = await admin.from("billing_webhook_events")
      .select("event_id").eq("provider", "revenuecat").eq("event_id", eventId).maybeSingle();
    if (existing) return json({ received: true, duplicate: true });

    const terminal = type === "EXPIRATION" || type === "REFUND";
    const entitlementIds = Array.isArray(event.entitlement_ids) ? event.entitlement_ids : [];
    if (!entitlementIds.includes("ledgerly_pro") && !terminal) {
      await admin.from("billing_webhook_events").insert({ provider: "revenuecat", event_id: eventId });
      return json({ received: true, ignored: true });
    }

    const status = terminal ? "expired"
      : type === "BILLING_ISSUE" ? "past_due"
      : type === "CANCELLATION" ? "cancelled"
      : ["REFUND_REVERSED", "PRODUCT_CHANGE"].includes(type) ? "active"
      : "active";
    const originalId = event.original_transaction_id ?? event.transaction_id ?? eventId;
    const externalId = String(originalId);
    const eventTimestamp = Number(event.event_timestamp_ms);
    if (!Number.isFinite(eventTimestamp)) {
      return json({ error: "RevenueCat event has no valid timestamp" }, 400);
    }
    const expiryMs = event.expiration_at_ms;
    const expiryTimestamp = expiryMs == null ? null : Number(expiryMs);
    if (expiryTimestamp != null && !Number.isFinite(expiryTimestamp)) {
      return json({ error: "RevenueCat event has an invalid expiration" }, 400);
    }
    const { error } = await admin.rpc("apply_revenuecat_entitlement", {
      p_user_id: userId,
      p_subscription_id: externalId,
      p_product_id: typeof event.product_id === "string" ? event.product_id : null,
      p_status: status,
      p_period_end: expiryTimestamp == null ? null : new Date(expiryTimestamp).toISOString(),
      p_event_id: eventId,
      p_status_updated_at: new Date(eventTimestamp).toISOString(),
    });
    if (error) {
      console.error("RevenueCat entitlement update failed", error);
      return json({ error: "Could not update subscription status" }, 500);
    }
    const { error: recordError } = await admin.from("billing_webhook_events")
      .insert({ provider: "revenuecat", event_id: eventId });
    if (recordError && recordError.code !== "23505") return json({ error: "Could not record event" }, 500);
    return json({ received: true });
  } catch (error) {
    console.error("RevenueCat webhook error", error);
    return json({ error: "Webhook processing failed" }, 500);
  }
});
