import { assertEquals, assertMatch } from "jsr:@std/assert@1";
import { handleRevenueCatWebhook } from "../revenuecat-webhook/index.ts";
import { USER_ID } from "./support.ts";

type RecordedRpc = { name: string; args: Record<string, unknown> };
type EventQuery = {
  eq: (column: string, value: string) => EventQuery;
  maybeSingle: () => Promise<{ data: { event_id: string } | null; error: null }>;
};

function webhookHarness() {
  const recordedRpc: RecordedRpc[] = [];
  const recordedEvents: Record<string, unknown>[] = [];

  const admin = {
    from(table: string) {
      assertEquals(table, "billing_webhook_events");
      return {
        select(_columns: string) {
          let query: EventQuery;
          query = {
            eq: (_column: string, _value: string) => query,
            maybeSingle: async () => ({ data: null, error: null }),
          };
          return query;
        },
        insert(row: Record<string, unknown>) {
          recordedEvents.push(row);
          return Promise.resolve({ error: null });
        },
      };
    },
    rpc(name: string, args: Record<string, unknown>) {
      recordedRpc.push({ name, args });
      return Promise.resolve({ error: null });
    },
  };

  const dependencies = {
    env(name: string) {
      return {
        REVENUECAT_WEBHOOK_AUTH: "revenuecat-test-secret",
        SUPABASE_URL: "https://project.supabase.co",
        SUPABASE_SERVICE_ROLE_KEY: "service-role-key",
      }[name];
    },
    createAdmin() {
      return admin;
    },
  };

  return { dependencies, recordedRpc, recordedEvents };
}

Deno.test("RevenueCat endpoint applies an entitlement with the event timestamp", async () => {
  const { dependencies, recordedRpc, recordedEvents } = webhookHarness();
  const eventTimestampMs = Date.parse("2026-11-08T11:00:00.000Z");
  const response = await handleRevenueCatWebhook(
    new Request("https://project.supabase.co/functions/v1/revenuecat-webhook", {
      method: "POST",
      headers: {
        Authorization: "revenuecat-test-secret",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        event: {
          id: "rc-event-1",
          app_user_id: USER_ID,
          type: "INITIAL_PURCHASE",
          event_timestamp_ms: eventTimestampMs,
          expiration_at_ms: Date.parse("2026-12-08T11:00:00.000Z"),
          entitlement_ids: ["ledgerly_pro"],
          product_id: "ledgerly_pro_monthly",
          original_transaction_id: "rc-transaction-1",
        },
      }),
    }),
    dependencies,
  );

  assertEquals(response.status, 200);
  assertEquals(recordedRpc.length, 1);
  assertEquals(recordedRpc[0].name, "apply_revenuecat_entitlement");
  assertEquals(recordedRpc[0].args.p_user_id, USER_ID);
  assertEquals(recordedRpc[0].args.p_status, "active");
  assertEquals(recordedRpc[0].args.p_status_updated_at, "2026-11-08T11:00:00.000Z");
  assertEquals(recordedRpc[0].args.p_subscription_id, "rc-transaction-1");
  assertMatch(String(recordedRpc[0].args.p_status_updated_at), /^\d{4}-\d{2}-\d{2}T/);
  assertEquals(recordedEvents, [{ provider: "revenuecat", event_id: "rc-event-1" }]);
});
