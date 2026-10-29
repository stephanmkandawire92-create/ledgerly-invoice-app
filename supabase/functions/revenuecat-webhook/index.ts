import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "Content-Type": "application/json" },
});

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const expected = Deno.env.get("REVENUECAT_WEBHOOK_AUTH");
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
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
    if (!/^[0-9a-f]{8}-[0-9a-f-]{27,}$/i.test(userId)) {
      return json({ error: "Unknown Ledgerly account reference" }, 400);
    }

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
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

    const eventTimestamp = Number(event.event_timestamp_ms);
    const eventDate = new Date(eventTimestamp);
    if (!Number.isFinite(eventTimestamp) || !Number.isFinite(eventDate.getTime())) {
      return json({ error: "RevenueCat event has no valid timestamp" }, 400);
    }

    const expiryValue = event.expiration_at_ms;
    const expiryTimestamp = expiryValue == null ? null : Number(expiryValue);
    if (expiryTimestamp != null && !Number.isFinite(new Date(expiryTimestamp).getTime())) {
      return json({ error: "RevenueCat event has an invalid expiration" }, 400);
    }
    const graceValue = event.grace_period_expiration_at_ms;
    const graceTimestamp = graceValue == null ? null : Number(graceValue);
    if (graceTimestamp != null && !Number.isFinite(new Date(graceTimestamp).getTime())) {
      return json({ error: "RevenueCat event has an invalid grace-period expiration" }, 400);
    }

    let status: string;
    let effectiveExpiryMs = expiryTimestamp;
    if (type === "EXPIRATION" || type === "REFUND") {
      status = "expired";
    } else if (type === "BILLING_ISSUE") {
      // Preserve access only through a provider-confirmed, future grace period.
      if (graceTimestamp !== null && graceTimestamp > Date.now()) {
        status = "active";
        effectiveExpiryMs = graceTimestamp;
      } else {
        status = "past_due";
      }
    } else if (type === "CANCELLATION") {
      status = "cancelled";
    } else if (type === "REFUND_REVERSED" || type === "PRODUCT_CHANGE") {
      status = "active";
    } else {
      // Purchases and renewals are active only with a provider-supplied future expiry.
      status = effectiveExpiryMs !== null && effectiveExpiryMs > Date.now()
        ? "active"
        : "expired";
    }

    const originalId = event.original_transaction_id ?? event.transaction_id ?? eventId;
    const externalId = String(originalId);
    const periodEnd = effectiveExpiryMs === null
      ? null
      : new Date(effectiveExpiryMs).toISOString();
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
});
