// POST /functions/v1/paypal-create-subscription
//
// Entry point only: request logic lives in ../_shared/checkout_handler.ts so it
// can be unit tested without a network or database.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { createCheckoutHandler } from "../_shared/checkout_handler.ts";
import { createCheckoutStore } from "../_shared/store.ts";

Deno.serve(createCheckoutHandler({
  env: (name) => Deno.env.get(name),
  fetch,
  now: () => new Date(),
  authenticate: async (settings, authorization) => {
    const client = createClient(settings.url, settings.anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await client.auth.getUser();
    if (error || !data?.user) return null;
    return { userId: data.user.id };
  },
  checkoutStore: (settings) => createCheckoutStore(
    createClient(settings.url, settings.serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    }),
  ),
  log: (message, detail) => {
    if (detail === undefined) console.error(message);
    else console.error(message, detail);
  },
}));
