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
    const expiryMs = event.expiration_at_ms;
    const periodEnd = typeof expiryMs === "number" ? new Date(expiryMs).toISOString() : null;
    const { error } = await admin.from("subscription_entitlements").upsert({
      user_id: userId,
      provider: "revenuecat",
      external_subscription_id: externalId,
      product_id: typeof event.product_id === "string" ? event.product_id : null,
      status,
      current_period_end: periodEnd,
      last_event_id: eventId,
      updated_at: new Date().toISOString(),
    }, { onConflict: "provider,external_subscription_id" });
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
