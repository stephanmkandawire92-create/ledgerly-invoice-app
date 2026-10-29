import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";

const headers = {
  "Access-Control-Allow-Origin": Deno.env.get("APP_ALLOWED_ORIGIN") ?? "null",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...headers, "Content-Type": "application/json" },
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const clientId = Deno.env.get("PAYPAL_CLIENT_ID");
  const clientSecret = Deno.env.get("PAYPAL_CLIENT_SECRET");
  const planId = Deno.env.get("PAYPAL_MONTHLY_PLAN_ID");
  const siteUrl = Deno.env.get("APP_SITE_URL");
  if (!supabaseUrl || !anonKey || !serviceKey || !clientId || !clientSecret || !planId || !siteUrl) {
    return json({ error: "Subscription checkout is not configured on the server." }, 503);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return json({ error: "Sign-in required." }, 401);
  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError || !user) return json({ error: "Invalid or expired session." }, 401);

  const base = Deno.env.get("PAYPAL_ENV") === "live"
    ? "https://api-m.paypal.com" : "https://api-m.sandbox.paypal.com";
  try {
    const oauth = await fetch(base + "/v1/oauth2/token", {
      method: "POST",
      headers: {
        Authorization: "Basic " + btoa(clientId + ":" + clientSecret),
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: "grant_type=client_credentials",
    });
    if (!oauth.ok) {
      console.error("PayPal OAuth failed:", oauth.status);
      return json({ error: "Could not start PayPal checkout." }, 502);
    }
    const token = (await oauth.json()).access_token as string;
    const planResponse = await fetch(base + "/v1/billing/plans/" + encodeURIComponent(planId), {
      headers: { Authorization: "Bearer " + token },
    });
    if (!planResponse.ok) return json({ error: "The configured PayPal plan could not be verified." }, 503);
    const plan = await planResponse.json();
    const cycle = Array.isArray(plan.billing_cycles)
      ? plan.billing_cycles.find((item: { tenure_type?: string }) => item.tenure_type === "REGULAR")
      : undefined;
    const price = cycle?.pricing_scheme?.fixed_price;
    if (plan.status !== "ACTIVE" || price?.currency_code !== "USD" || price?.value !== "3.00" ||
        cycle?.frequency?.interval_unit !== "MONTH" || cycle?.frequency?.interval_count !== 1) {
      console.error("Configured PayPal plan must be active and exactly USD 3.00/month.");
      return json({ error: "The PayPal plan is not configured as USD 3.00 per month." }, 503);
    }

    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });
    const { data: reservations, error: reservationError } = await admin.rpc(
      "claim_paypal_checkout",
      { p_user_id: user.id, p_request_id: crypto.randomUUID() },
    );
    if (reservationError) {
      console.error("PayPal checkout reservation failed:", reservationError.message);
      return json({ error: "Could not safely reserve this checkout. Please retry." }, 503);
    }
    const reservation = (Array.isArray(reservations) ? reservations[0] : reservations) as
      | { disposition?: string; request_id?: string; approval_url?: string | null; subscription_id?: string | null }
      | null;
    if (!reservation?.disposition) {
      return json({ error: "Could not safely reserve this checkout. Please retry." }, 503);
    }
    if (reservation.disposition === "entitled") {
      return json({ error: "An active or paid-through subscription already exists." }, 409);
    }
    if (reservation.approval_url) {
      return json({
        approvalUrl: reservation.approval_url,
        subscriptionId: reservation.subscription_id,
      });
    }
    if (typeof reservation.request_id !== "string") {
      return json({ error: "Could not safely resume this checkout. Please retry." }, 503);
    }
    const requestId = reservation.request_id;

    const root = siteUrl.replace(/\/$/, "");
    const created = await fetch(base + "/v1/billing/subscriptions", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "application/json",
        Prefer: "return=representation",
        "PayPal-Request-Id": requestId,
      },
      body: JSON.stringify({
        plan_id: planId,
        custom_id: `${user.id}:${requestId}`,
        application_context: {
          brand_name: "Ledgerly",
          user_action: "SUBSCRIBE_NOW",
          return_url: root,
          cancel_url: root,
        },
      }),
    });
    const result = await created.json();
    if (!created.ok) {
      if ([400, 401, 403, 404, 422].includes(created.status)) {
        const { error: releaseError } = await admin
          .from("paypal_checkout_attempts")
          .update({ status: "failed", updated_at: new Date().toISOString() })
          .eq("request_id", requestId)
          .eq("status", "creating");
        if (releaseError) console.error("Could not release rejected PayPal checkout:", releaseError.message);
      }
      console.error("PayPal subscription creation failed:", created.status);
      return json({ error: "PayPal could not create the subscription." }, 502);
    }
    const links = Array.isArray(result.links) ? result.links : [];
    const approval = links.find((item: { rel?: string }) => item.rel === "approve")?.href;
    if (typeof approval !== "string" || typeof result.id !== "string") {
      return json({ error: "PayPal returned an incomplete checkout response." }, 502);
    }
    const { data: savedAttempts, error: saveError } = await admin
      .from("paypal_checkout_attempts")
      .update({
        subscription_id: result.id,
        approval_url: approval,
        status: "pending",
        updated_at: new Date().toISOString(),
      })
      .eq("request_id", requestId)
      .eq("status", "creating")
      .select("id");
    if (saveError) {
      console.error("Could not persist PayPal checkout attempt:", saveError.message);
      return json({ error: "PayPal checkout was created but could not be finalized. Please retry." }, 503);
    }
    if (!savedAttempts?.length) {
      const { data: finalized, error: finalizationError } = await admin
        .from("paypal_checkout_attempts")
        .select("subscription_id,status")
        .eq("request_id", requestId)
        .maybeSingle();
      const finalizedStatus = finalized?.status;
      const validFinalization = finalized?.subscription_id === result.id &&
        typeof finalizedStatus === "string" &&
        ["pending", "active", "cancelled", "expired", "past_due", "suspended"].includes(finalizedStatus);
      if (finalizationError || !validFinalization) {
        return json({ error: "PayPal checkout was created but could not be finalized. Please retry." }, 503);
      }
    }
    // Checkout return is not proof of payment. A verified webhook grants access.
    return json({ approvalUrl: approval, subscriptionId: result.id });
  } catch (error) {
    console.error("PayPal checkout error:", error);
    return json({ error: "Checkout is temporarily unavailable." }, 502);
  }
});
