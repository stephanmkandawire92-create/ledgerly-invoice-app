import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "Content-Type": "application/json" },
});

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const webhookId = Deno.env.get("PAYPAL_WEBHOOK_ID");
  const clientId = Deno.env.get("PAYPAL_CLIENT_ID");
  const clientSecret = Deno.env.get("PAYPAL_CLIENT_SECRET");
  const planId = Deno.env.get("PAYPAL_MONTHLY_PLAN_ID");
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!webhookId || !clientId || !clientSecret || !planId || !url || !serviceKey) {
    return json({ error: "Webhook not configured" }, 503);
  }

  try {
    const event = await req.json();
    const header = (name: string) => req.headers.get(name);
    const base = Deno.env.get("PAYPAL_ENV") === "live"
      ? "https://api-m.paypal.com"
      : "https://api-m.sandbox.paypal.com";
    const oauth = await fetch(base + "/v1/oauth2/token", {
      method: "POST",
      headers: {
        Authorization: "Basic " + btoa(clientId + ":" + clientSecret),
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: "grant_type=client_credentials",
    });
    if (!oauth.ok) return json({ error: "PayPal verification unavailable" }, 502);
    const token = (await oauth.json()).access_token as string;
    const verificationResponse = await fetch(
      base + "/v1/notifications/verify-webhook-signature",
      {
        method: "POST",
        headers: {
          Authorization: "Bearer " + token,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          auth_algo: header("paypal-auth-algo"),
          cert_url: header("paypal-cert-url"),
          transmission_id: header("paypal-transmission-id"),
          transmission_sig: header("paypal-transmission-sig"),
          transmission_time: header("paypal-transmission-time"),
          webhook_id: webhookId,
          webhook_event: event,
        }),
      },
    );
    const verification = await verificationResponse.json();
    if (!verificationResponse.ok || verification.verification_status !== "SUCCESS") {
      return json({ error: "Invalid webhook signature" }, 401);
    }

    const eventId = event?.id;
    const type = event?.event_type;
    if (typeof eventId !== "string" || typeof type !== "string") {
      return json({ error: "Invalid event" }, 400);
    }
    const resource = event.resource ?? {};
    const subscriptionId = resource.id && type.startsWith("BILLING.SUBSCRIPTION.")
      ? resource.id
      : resource.billing_agreement_id ??
        resource.supplementary_data?.related_ids?.subscription_id ??
        resource.subscription_id;
    if (typeof subscriptionId !== "string") {
      return json({ received: true, ignored: true });
    }

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
    const { data: existing, error: duplicateCheckError } = await admin
      .from("billing_webhook_events")
      .select("event_id")
      .eq("provider", "paypal")
      .eq("event_id", eventId)
      .maybeSingle();
    if (duplicateCheckError) {
      console.error("PayPal webhook duplicate check failed", duplicateCheckError);
      return json({ error: "Could not check webhook idempotency" }, 500);
    }
    if (existing) return json({ received: true, duplicate: true });

    // Always use PayPal's canonical subscription record, not event-supplied state.
    const subResponse = await fetch(
      base + "/v1/billing/subscriptions/" + encodeURIComponent(subscriptionId),
      { headers: { Authorization: "Bearer " + token } },
    );
    if (!subResponse.ok) {
      console.error("Could not retrieve PayPal subscription", subResponse.status);
      return json({ error: "Could not verify subscription status" }, 502);
    }
    const sub = await subResponse.json();

    // Never grant Ledgerly Pro for a subscription created against another plan.
    if (sub.plan_id !== planId) {
      const { error } = await admin.from("billing_webhook_events").insert({
        provider: "paypal",
        event_id: eventId,
      });
      if (error && error.code !== "23505") {
        return json({ error: "Could not record ignored event" }, 500);
      }
      return json({ received: true, ignored: true });
    }

    // The release checkout function stores both the signed-in account UUID and
    // its idempotency request ID. Accept legacy bare UUIDs without a request ID.
    const [userId, checkoutRequestId] = String(sub.custom_id ?? "").split(":", 2);
    if (!/^[0-9a-f]{8}-[0-9a-f-]{27,}$/i.test(userId ?? "")) {
      return json({ error: "Subscription has no valid Ledgerly account reference" }, 400);
    }

    const { data: previous, error: previousError } = await admin
      .from("subscription_entitlements")
      .select("status,provider_status_updated_at")
      .eq("provider", "paypal")
      .eq("external_subscription_id", subscriptionId)
      .maybeSingle();
    if (previousError) {
      console.error("Could not read existing PayPal entitlement", previousError);
      return json({ error: "Could not verify existing subscription state" }, 500);
    }

    const providerStatusTime = Date.parse(String(sub.status_update_time ?? ""));
    if (!Number.isFinite(providerStatusTime)) {
      return json({ error: "PayPal subscription has no valid status version" }, 502);
    }
    const eventTime = Date.parse(String(event.create_time ?? ""));
    const previousVersionTime = Date.parse(
      String(previous?.provider_status_updated_at ?? ""),
    );
    const eventIsStale = Number.isFinite(eventTime) && (
      eventTime < providerStatusTime ||
      (Number.isFinite(previousVersionTime) && eventTime < previousVersionTime)
    );
    const canonicalStatuses: Record<string, string> = {
      ACTIVE: "active",
      CANCELLED: "cancelled",
      EXPIRED: "expired",
      SUSPENDED: "suspended",
      APPROVAL_PENDING: "pending",
      APPROVED: "pending",
    };
    const canonicalStatus = canonicalStatuses[String(sub.status ?? "")];
    const activeOrPending = () =>
      canonicalStatus === "active" && previous?.status === "active"
        ? "active"
        : "pending";

    let status: string;
    switch (type) {
      case "BILLING.SUBSCRIPTION.ACTIVATED":
        // Approval/activation alone is not proof that the first payment succeeded.
        status = canonicalStatus === "active" ? activeOrPending() : canonicalStatus ?? "pending";
        break;
      case "BILLING.SUBSCRIPTION.UPDATED":
        status = canonicalStatus === "active"
          ? previous && ["active", "cancelled"].includes(previous.status)
            ? previous.status
            : "pending"
          : canonicalStatus ?? "pending";
        break;
      case "BILLING.SUBSCRIPTION.CANCELLED":
        status = canonicalStatus === "active"
          ? activeOrPending()
          : canonicalStatus ?? "cancelled";
        break;
      case "BILLING.SUBSCRIPTION.EXPIRED":
        status = canonicalStatus === "active"
          ? activeOrPending()
          : canonicalStatus ?? "expired";
        break;
      case "BILLING.SUBSCRIPTION.SUSPENDED":
        status = canonicalStatus === "active"
          ? activeOrPending()
          : canonicalStatus ?? "suspended";
        break;
      case "BILLING.SUBSCRIPTION.PAYMENT.FAILED":
        status = "past_due";
        break;
      case "PAYMENT.SALE.COMPLETED":
        status = sub.status === "CANCELLED"
          ? "cancelled"
          : sub.status === "ACTIVE"
          ? "active"
          : sub.status === "EXPIRED"
          ? "expired"
          : "past_due";
        break;
      case "PAYMENT.SALE.REFUNDED":
      case "PAYMENT.SALE.REVERSED":
        status = "past_due";
        break;
      default: {
        const { error } = await admin.from("billing_webhook_events").insert({
          provider: "paypal",
          event_id: eventId,
        });
        if (error && error.code !== "23505") {
          return json({ error: "Could not record ignored event" }, 500);
        }
        return json({ received: true, ignored: true });
      }
    }

    // A delayed non-payment event must not replace a newer canonical provider
    // state. A completed sale remains explicit evidence of a successful payment.
    if (eventIsStale && type !== "PAYMENT.SALE.COMPLETED") {
      status = canonicalStatus === "active"
        ? activeOrPending()
        : canonicalStatus ?? status;
    }
    const versionTime = Number.isFinite(eventTime)
      ? Math.max(providerStatusTime, eventTime)
      : providerStatusTime;
    const nextBilling = sub.billing_info?.next_billing_time;
    const endDate = typeof nextBilling === "string" ? new Date(nextBilling) : null;
    if (endDate && !Number.isFinite(endDate.getTime())) {
      return json({ error: "PayPal subscription has an invalid billing period end" }, 502);
    }

    const { data: applied, error: upsertError } = await admin.rpc(
      "apply_paypal_entitlement",
      {
        p_user_id: userId,
        p_subscription_id: subscriptionId,
        p_product_id: planId,
        p_status: status,
        p_period_end: endDate?.toISOString() ?? null,
        p_event_id: eventId,
        p_status_updated_at: new Date(versionTime).toISOString(),
      },
    );
    if (upsertError) {
      console.error("PayPal entitlement update failed", upsertError);
      return json({ error: "Could not update subscription status" }, 500);
    }

    if (applied && checkoutRequestId && /^[0-9a-f-]{36}$/i.test(checkoutRequestId)) {
      const { error: checkoutError } = await admin
        .from("paypal_checkout_attempts")
        .update({
          subscription_id: subscriptionId,
          status,
          updated_at: new Date().toISOString(),
        })
        .eq("request_id", checkoutRequestId)
        .eq("user_id", userId);
      if (checkoutError) {
        console.error("PayPal checkout reservation update failed", checkoutError);
        return json({ error: "Could not update checkout state" }, 500);
      }
    }

    // Record only after the entitlement write succeeds so provider retries can recover.
    const { error: recordError } = await admin.from("billing_webhook_events").insert({
      provider: "paypal",
      event_id: eventId,
    });
    if (recordError && recordError.code !== "23505") {
      return json({ error: "Could not record event" }, 500);
    }
    return json({ received: true });
  } catch (error) {
    console.error("PayPal webhook error", error);
    return json({ error: "Webhook processing failed" }, 500);
  }
});
