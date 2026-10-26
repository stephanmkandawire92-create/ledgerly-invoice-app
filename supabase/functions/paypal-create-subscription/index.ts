import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
  const clientId = Deno.env.get("PAYPAL_CLIENT_ID");
  const clientSecret = Deno.env.get("PAYPAL_CLIENT_SECRET");
  const planId = Deno.env.get("PAYPAL_MONTHLY_PLAN_ID");
  const siteUrl = Deno.env.get("APP_SITE_URL");
  if (!supabaseUrl || !anonKey || !clientId || !clientSecret || !planId || !siteUrl) {
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
    const root = siteUrl.replace(/\/$/, "");
    const created = await fetch(base + "/v1/billing/subscriptions", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "application/json",
        Prefer: "return=representation",
      },
      body: JSON.stringify({
        plan_id: planId,
        custom_id: user.id,
        application_context: {
          brand_name: "Ledgerly",
          user_action: "SUBSCRIBE_NOW",
          return_url: root + "/billing/paypal-return",
          cancel_url: root + "/billing/paypal-cancel",
        },
      }),
    });
    const result = await created.json();
    if (!created.ok) {
      console.error("PayPal subscription creation failed:", created.status, result);
      return json({ error: "PayPal could not create the subscription." }, 502);
    }
    const links = Array.isArray(result.links) ? result.links : [];
    const approval = links.find((item: { rel?: string }) => item.rel === "approve")?.href;
    if (typeof approval !== "string" || typeof result.id !== "string") {
      return json({ error: "PayPal returned an incomplete checkout response." }, 502);
    }
    // Checkout return is not proof of payment. A verified webhook grants access.
    return json({ approvalUrl: approval, subscriptionId: result.id });
  } catch (error) {
    console.error("PayPal checkout error:", error);
    return json({ error: "Checkout is temporarily unavailable." }, 502);
  }
});
