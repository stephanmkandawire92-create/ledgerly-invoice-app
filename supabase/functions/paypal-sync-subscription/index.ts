// POST /functions/v1/paypal-sync-subscription
//
// Entry point only: request logic lives in ../_shared/sync_handler.ts.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.118.0";
import { createSyncHandler } from "../_shared/sync_handler.ts";
import { createSyncStore } from "../_shared/store.ts";

Deno.serve(createSyncHandler({
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
  syncStore: (settings) => createSyncStore(
    createClient(settings.url, settings.serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    }),
  ),
  log: (message, detail) => {
    if (detail === undefined) console.error(message);
    else console.error(message, detail);
  },
}));
