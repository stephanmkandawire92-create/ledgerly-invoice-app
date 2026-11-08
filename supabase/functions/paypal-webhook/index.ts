// POST /functions/v1/paypal-webhook
//
// Entry point only: request logic lives in ../_shared/webhook_handler.ts.
// verify_jwt must stay disabled for this function (supabase/config.toml);
// authenticity comes from PayPal's signature verification, not a Supabase JWT.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { createWebhookHandler } from "../_shared/webhook_handler.ts";
import { createCheckoutStore, createWebhookStore } from "../_shared/store.ts";

const adminFor = (settings: { url: string; serviceRoleKey: string }) =>
  createClient(settings.url, settings.serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

Deno.serve(createWebhookHandler({
  env: (name) => Deno.env.get(name),
  fetch,
  now: () => new Date(),
  webhookStore: (settings) => createWebhookStore(adminFor(settings)),
  checkoutStore: (settings) => createCheckoutStore(adminFor(settings)),
  log: (message, detail) => {
    if (detail === undefined) console.error(message);
    else console.error(message, detail);
  },
}));
