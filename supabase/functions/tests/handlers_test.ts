import { assertEquals, assert, assertFalse } from "jsr:@std/assert@1";
import { createCheckoutHandler } from "../_shared/checkout_handler.ts";
import { createWebhookHandler } from "../_shared/webhook_handler.ts";
import { createSyncHandler, isEntitled } from "../_shared/sync_handler.ts";
import { ACTIVE_PLAN } from "./support.ts";
import {
  APP_ORIGIN,
  FIXED_NOW,
  PLAN_ID,
  SUBSCRIPTION_ID,
  USER_ID,
  activeSubscription,
  env,
  fakePayPal,
  FakeCheckoutStore,
  FakeSyncStore,
  FakeWebhookStore,
  jsonRequest,
  signatureHeaders,
} from "./support.ts";
import type { EntitlementSnapshot } from "../_shared/types.ts";

const CHECKOUT_URL = "https://project.supabase.co/functions/v1/paypal-create-subscription";
const WEBHOOK_URL = "https://project.supabase.co/functions/v1/paypal-webhook";
const SYNC_URL = "https://project.supabase.co/functions/v1/paypal-sync-subscription";

function checkoutHarness(options: {
  envOverrides?: Record<string, string | undefined>;
  paypal?: ReturnType<typeof fakePayPal>;
  store?: FakeCheckoutStore;
  authenticated?: boolean;
} = {}) {
  const store = options.store ?? new FakeCheckoutStore();
  const paypal = options.paypal ?? fakePayPal();
  const logs: string[] = [];
  const handler = createCheckoutHandler({
    env: env(options.envOverrides),
    fetch: paypal.fetch,
    now: () => FIXED_NOW,
    authenticate: async () => (options.authenticated === false ? null : { userId: USER_ID }),
    checkoutStore: () => store,
    log: (message, detail) => logs.push(`${message} ${detail ? JSON.stringify(detail) : ""}`.trim()),
  });
  return { handler, store, paypal, logs };
}

function webhookHarness(options: {
  envOverrides?: Record<string, string | undefined>;
  paypal?: ReturnType<typeof fakePayPal>;
  store?: FakeWebhookStore;
  checkout?: FakeCheckoutStore;
} = {}) {
  const store = options.store ?? new FakeWebhookStore();
  const checkout = options.checkout ?? new FakeCheckoutStore();
  const paypal = options.paypal ?? fakePayPal({ subscription: activeSubscription() });
  const logs: string[] = [];
  const handler = createWebhookHandler({
    env: env(options.envOverrides),
    fetch: paypal.fetch,
    now: () => FIXED_NOW,
    webhookStore: () => store,
    checkoutStore: () => checkout,
    log: (message, detail) => logs.push(`${message} ${detail ? JSON.stringify(detail) : ""}`.trim()),
  });
  return { handler, store, checkout, paypal, logs };
}

function syncHarness(options: {
  store?: FakeSyncStore;
  paypal?: ReturnType<typeof fakePayPal>;
  envOverrides?: Record<string, string | undefined>;
  authenticated?: boolean;
} = {}) {
  const store = options.store ?? new FakeSyncStore();
  const paypal = options.paypal ?? fakePayPal({ subscription: activeSubscription() });
  const logs: string[] = [];
  const handler = createSyncHandler({
    env: env(options.envOverrides),
    fetch: paypal.fetch,
    now: () => FIXED_NOW,
    authenticate: async () => (options.authenticated === false ? null : { userId: USER_ID }),
    syncStore: () => store,
    log: (message, detail) => logs.push(`${message} ${detail ? JSON.stringify(detail) : ""}`.trim()),
  });
  return { handler, store, paypal, logs };
}

function event(eventType: string, overrides: Record<string, unknown> = {}) {
  return {
    id: `WH-EVT-${eventType}`,
    event_type: eventType,
    create_time: "2026-11-08T11:56:00.000Z",
    resource: { id: SUBSCRIPTION_ID, amount: { total: "3.00", currency: "USD" } },
    ...overrides,
  };
}

// ===========================================================================
// Checkout
// ===========================================================================

Deno.test("checkout: missing configuration returns 503 without leaking names", async () => {
  const { handler, logs } = checkoutHarness({ envOverrides: { PAYPAL_CLIENT_ID: undefined } });
  const response = await handler(jsonRequest(CHECKOUT_URL));
  assertEquals(response.status, 503);
  const body = await response.json();
  assertEquals(body.code, "billing_not_configured");
  assert(!body.error.includes("PAYPAL_CLIENT_ID"));
  assert(logs.some((entry) => entry.includes("PAYPAL_CLIENT_ID")));
});

Deno.test("checkout: contradictory URLs are a configuration error", async () => {
  const { handler } = checkoutHarness({
    envOverrides: { PAYPAL_CANCEL_URL: "https://elsewhere.example.com/cancel" },
  });
  const response = await handler(jsonRequest(CHECKOUT_URL));
  assertEquals(response.status, 503);
  assertEquals((await response.json()).code, "billing_not_configured");
});

Deno.test("checkout: OPTIONS from the app origin answers with the exact origin", async () => {
  const { handler } = checkoutHarness();
  const response = await handler(jsonRequest(CHECKOUT_URL, {
    method: "OPTIONS",
    origin: APP_ORIGIN,
    authorization: null,
  }));
  assertEquals(response.status, 204);
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), APP_ORIGIN);
  await response.body?.cancel();
});

Deno.test("checkout: OPTIONS from a foreign origin is refused", async () => {
  const { handler } = checkoutHarness();
  const response = await handler(jsonRequest(CHECKOUT_URL, {
    method: "OPTIONS",
    origin: "https://evil.example.com",
    authorization: null,
  }));
  assertEquals(response.status, 403);
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), null);
  await response.body?.cancel();
});

Deno.test("checkout: POST from a foreign origin is refused before any work", async () => {
  const { handler, paypal } = checkoutHarness();
  const response = await handler(jsonRequest(CHECKOUT_URL, { origin: "https://evil.example.com" }));
  assertEquals(response.status, 403);
  assertEquals((await response.json()).code, "origin_not_allowed");
  assertEquals(paypal.calls.length, 0);
});

Deno.test("checkout: a missing bearer token is rejected", async () => {
  const { handler } = checkoutHarness();
  const response = await handler(jsonRequest(CHECKOUT_URL, { authorization: null }));
  assertEquals(response.status, 401);
  assertEquals((await response.json()).code, "sign_in_required");
});

Deno.test("checkout: an invalid session is rejected", async () => {
  const { handler } = checkoutHarness({ authenticated: false });
  const response = await handler(jsonRequest(CHECKOUT_URL));
  assertEquals(response.status, 401);
  assertEquals((await response.json()).code, "session_expired");
});

Deno.test("checkout: a plan that is not the $3 monthly plan blocks checkout", async () => {
  const paypal = fakePayPal({ plan: { ...ACTIVE_PLAN, status: "INACTIVE" } });
  const { handler, store } = checkoutHarness({ paypal });
  const response = await handler(jsonRequest(CHECKOUT_URL));
  assertEquals(response.status, 503);
  assertEquals((await response.json()).code, "plan_misconfigured");
  assertEquals(store.reservations.length, 0);
});

Deno.test("checkout: a PayPal plan lookup failure does not create a subscription", async () => {
  const paypal = fakePayPal({ planStatus: 404 });
  const { handler } = checkoutHarness({ paypal });
  const response = await handler(jsonRequest(CHECKOUT_URL));
  assertEquals(response.status, 502);
  assertEquals(paypal.count("POST", "/v1/billing/subscriptions"), 0);
});

Deno.test("checkout: an already entitled account is refused with 409", async () => {
  const store = new FakeCheckoutStore();
  store.existing = { disposition: "entitled", requestId: null, approvalUrl: null, subscriptionId: null };
  const { handler, paypal } = checkoutHarness({ store });
  const response = await handler(jsonRequest(CHECKOUT_URL));
  assertEquals(response.status, 409);
  assertEquals((await response.json()).code, "already_subscribed");
  assertEquals(paypal.count("POST", "/v1/billing/subscriptions"), 0);
});

Deno.test("checkout: an unresolved payment issue is refused instead of double-charging", async () => {
  const store = new FakeCheckoutStore();
  store.existing = { disposition: "payment_issue", requestId: null, approvalUrl: null, subscriptionId: null };
  const { handler, paypal } = checkoutHarness({ store });
  const response = await handler(jsonRequest(CHECKOUT_URL));
  assertEquals(response.status, 409);
  assertEquals((await response.json()).code, "payment_issue");
  assertEquals(paypal.count("POST", "/v1/billing/subscriptions"), 0);
});

Deno.test("checkout: an in-flight attempt is resumed without a second PayPal subscription", async () => {
  const store = new FakeCheckoutStore();
  store.existing = {
    disposition: "existing",
    requestId: "8f14e45f-ceea-467f-a3bd-1a2b3c4d5e6f",
    approvalUrl: "https://www.sandbox.paypal.com/checkoutnow?token=I-EXISTING",
    subscriptionId: "I-EXISTING",
  };
  const { handler, paypal } = checkoutHarness({ store });
  const response = await handler(jsonRequest(CHECKOUT_URL));
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.subscriptionId, "I-EXISTING");
  assertEquals(paypal.count("POST", "/v1/billing/subscriptions"), 0);
});

Deno.test("checkout: a provider rejection releases the reservation", async () => {
  const paypal = fakePayPal({ createdStatus: 422, created: { name: "UNPROCESSABLE_ENTITY" } });
  const { handler, store } = checkoutHarness({ paypal });
  const response = await handler(jsonRequest(CHECKOUT_URL));
  assertEquals(response.status, 502);
  assertEquals((await response.json()).code, "checkout_failed");
  assertEquals(store.released.length, 1);
});

Deno.test("checkout: a successful creation returns only the approval URL and id", async () => {
  const { handler, store, paypal } = checkoutHarness();
  const response = await handler(jsonRequest(CHECKOUT_URL));
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), APP_ORIGIN);
  const body = await response.json();
  assertEquals(body.subscriptionId, SUBSCRIPTION_ID);
  assert(body.approvalUrl.startsWith("https://www.sandbox.paypal.com/"));
  assertEquals(store.saved.length, 1);

  const createCall = paypal.calls.find(
    (call) => call.method === "POST" && call.url.endsWith("/v1/billing/subscriptions"),
  );
  assert(createCall);
  const payload = createCall!.body as Record<string, unknown>;
  assertEquals(payload.plan_id, PLAN_ID);
  assert(String(payload.custom_id).startsWith(`${USER_ID}:`));
  assertEquals((payload.application_context as Record<string, unknown>).return_url, `${APP_ORIGIN}/billing/paypal/return`);
  assertEquals((payload.application_context as Record<string, unknown>).cancel_url, `${APP_ORIGIN}/billing/paypal/cancel`);
  assertEquals((payload.application_context as Record<string, unknown>).shipping_preference, "NO_SHIPPING");
  assert(typeof createCall!.body === "object");
});

Deno.test("checkout: an incomplete PayPal response is not treated as success", async () => {
  const paypal = fakePayPal({ created: { id: SUBSCRIPTION_ID, links: [] } });
  const { handler, store } = checkoutHarness({ paypal });
  const response = await handler(jsonRequest(CHECKOUT_URL));
  assertEquals(response.status, 502);
  assertEquals((await response.json()).code, "incomplete_provider_response");
  assertEquals(store.saved.length, 0);
});

Deno.test("checkout: a database failure while saving the approval fails closed", async () => {
  const store = new FakeCheckoutStore();
  store.saveError = "write failed";
  const { handler } = checkoutHarness({ store });
  const response = await handler(jsonRequest(CHECKOUT_URL));
  assertEquals(response.status, 502);
  assertEquals((await response.json()).code, "checkout_persist_failed");
});

// ===========================================================================
// Webhook
// ===========================================================================

Deno.test("webhook: non-POST methods are rejected", async () => {
  const { handler } = webhookHarness();
  const response = await handler(jsonRequest(WEBHOOK_URL, { method: "GET", authorization: null }));
  assertEquals(response.status, 405);
});

Deno.test("webhook: malformed JSON is rejected", async () => {
  const { handler } = webhookHarness();
  const response = await handler(new Request(WEBHOOK_URL, {
    method: "POST",
    headers: signatureHeaders(),
    body: "{not json",
  }));
  assertEquals(response.status, 400);
});

Deno.test("webhook: missing configuration returns 503 and logs the names", async () => {
  const { handler, logs } = webhookHarness({ envOverrides: { PAYPAL_WEBHOOK_ID: undefined } });
  const response = await handler(jsonRequest(WEBHOOK_URL, { body: event("BILLING.SUBSCRIPTION.ACTIVATED"), headers: signatureHeaders() }));
  assertEquals(response.status, 503);
  const body = await response.json();
  assertEquals(body.code, "webhook_not_configured");
  assert(logs.some((entry) => entry.includes("PAYPAL_WEBHOOK_ID")));
});

Deno.test("webhook: absent signature headers are rejected", async () => {
  const { handler, store } = webhookHarness();
  const response = await handler(jsonRequest(WEBHOOK_URL, { body: event("BILLING.SUBSCRIPTION.ACTIVATED") }));
  assertEquals(response.status, 401);
  assertEquals(store.applied.length, 0);
});

Deno.test("webhook: a failed signature verification changes nothing", async () => {
  const paypal = fakePayPal({
    subscription: activeSubscription(),
    verification: { verification_status: "FAILURE" },
  });
  const { handler, store } = webhookHarness({ paypal });
  const response = await handler(jsonRequest(WEBHOOK_URL, {
    body: event("BILLING.SUBSCRIPTION.ACTIVATED"),
    headers: signatureHeaders(),
  }));
  assertEquals(response.status, 401);
  assertEquals(store.applied.length, 0);
  assertEquals(store.recorded.length, 0);
});

Deno.test("webhook: a duplicate event is acknowledged and does nothing", async () => {
  const store = new FakeWebhookStore();
  store.events.add("WH-EVT-BILLING.SUBSCRIPTION.ACTIVATED");
  const { handler, paypal } = webhookHarness({ store });
  const response = await handler(jsonRequest(WEBHOOK_URL, {
    body: event("BILLING.SUBSCRIPTION.ACTIVATED"),
    headers: signatureHeaders(),
  }));
  assertEquals(response.status, 200);
  assertEquals((await response.json()).duplicate, true);
  assertEquals(store.applied.length, 0);
  // Signature verification still runs, but no subscription is fetched and no
  // entitlement is written for an event that was already processed.
  assertEquals(paypal.count("GET", "/v1/billing/subscriptions/"), 0);
});

Deno.test("webhook: an unsupported event is recorded and ignored", async () => {
  const { handler, store, paypal } = webhookHarness();
  const response = await handler(jsonRequest(WEBHOOK_URL, {
    body: event("CATALOG.PRODUCT.CREATED"),
    headers: signatureHeaders(),
  }));
  assertEquals(response.status, 200);
  assertEquals((await response.json()).ignored, true);
  assertEquals(store.recorded.length, 1);
  assertEquals(paypal.count("GET", "/v1/billing/subscriptions/"), 0);
});

Deno.test("webhook: a subscription on another plan never grants Pro", async () => {
  const paypal = fakePayPal({ subscription: activeSubscription({ plan_id: "P-SOMEONE-ELSE" }) });
  const { handler, store } = webhookHarness({ paypal });
  const response = await handler(jsonRequest(WEBHOOK_URL, {
    body: event("BILLING.SUBSCRIPTION.ACTIVATED"),
    headers: signatureHeaders(),
  }));
  assertEquals(response.status, 200);
  assertEquals((await response.json()).ignored, true);
  assertEquals(store.applied.length, 0);
});

Deno.test("webhook: a subscription without an account reference never grants Pro", async () => {
  const paypal = fakePayPal({ subscription: activeSubscription({ custom_id: "" }) });
  const { handler, store } = webhookHarness({ paypal });
  await handler(jsonRequest(WEBHOOK_URL, {
    body: event("BILLING.SUBSCRIPTION.ACTIVATED"),
    headers: signatureHeaders(),
  }));
  assertEquals(store.applied.length, 0);
});

Deno.test("webhook: a checkout reserved by another account is refused", async () => {
  const checkout = new FakeCheckoutStore();
  const store = new FakeWebhookStore();
  store.checkoutOwner = { userId: "11111111-1111-4111-8111-111111111111" };
  const { handler } = webhookHarness({ checkout, store });
  const response = await handler(jsonRequest(WEBHOOK_URL, {
    body: event("BILLING.SUBSCRIPTION.ACTIVATED"),
    headers: signatureHeaders(),
  }));
  assertEquals(response.status, 400);
  assertEquals((await response.json()).code, "account_mismatch");
  assertEquals(store.applied.length, 0);
});

Deno.test("webhook: a subscription already bound to another account is refused", async () => {
  const store = new FakeWebhookStore();
  store.entitlement = {
    userId: "22222222-2222-4222-8222-222222222222",
    status: "active",
    currentPeriodEnd: "2026-12-01T00:00:00.000Z",
    providerStatusUpdatedAt: "2026-11-01T00:00:00.000Z",
    updatedAt: "2026-11-01T00:00:00.000Z",
    subscriptionId: SUBSCRIPTION_ID,
  };
  const { handler } = webhookHarness({ store });
  const response = await handler(jsonRequest(WEBHOOK_URL, {
    body: event("BILLING.SUBSCRIPTION.ACTIVATED"),
    headers: signatureHeaders(),
  }));
  assertEquals(response.status, 400);
  assertEquals((await response.json()).code, "account_mismatch");
});

Deno.test("webhook: activation with a verified payment grants Pro", async () => {
  const { handler, store } = webhookHarness();
  const response = await handler(jsonRequest(WEBHOOK_URL, {
    body: event("BILLING.SUBSCRIPTION.ACTIVATED"),
    headers: signatureHeaders(),
  }));
  assertEquals(response.status, 200);
  assertEquals(store.applied.length, 1);
  assertEquals(store.applied[0].status, "active");
  assertEquals(store.applied[0].userId, USER_ID);
  assertEquals(store.applied[0].periodEnd, "2026-12-08T11:55:00.000Z");
  assertEquals(store.recorded.length, 1);
});

Deno.test("webhook: activation without payment stays pending", async () => {
  const paypal = fakePayPal({
    subscription: activeSubscription({ billing_info: { next_billing_time: "2026-12-08T11:55:00.000Z" } }),
  });
  const { handler, store } = webhookHarness({ paypal });
  await handler(jsonRequest(WEBHOOK_URL, {
    body: event("BILLING.SUBSCRIPTION.ACTIVATED"),
    headers: signatureHeaders(),
  }));
  assertEquals(store.applied[0].status, "pending");
});

Deno.test("webhook: a sale for the wrong amount is ignored", async () => {
  const { handler, store } = webhookHarness();
  const response = await handler(jsonRequest(WEBHOOK_URL, {
    body: event("PAYMENT.SALE.COMPLETED", {
      resource: {
        id: "SALE-1",
        billing_agreement_id: SUBSCRIPTION_ID,
        amount: { total: "0.50", currency: "USD" },
      },
    }),
    headers: signatureHeaders(),
  }));
  assertEquals(response.status, 200);
  assertEquals((await response.json()).ignored, true);
  assertEquals(store.applied.length, 0);
});

Deno.test("webhook: a refund revokes access", async () => {
  const { handler, store } = webhookHarness();
  const response = await handler(jsonRequest(WEBHOOK_URL, {
    body: event("PAYMENT.SALE.REFUNDED", {
      resource: {
        id: "SALE-1",
        billing_agreement_id: SUBSCRIPTION_ID,
        amount: { total: "3.00", currency: "USD" },
      },
    }),
    headers: signatureHeaders(),
  }));
  assertEquals(response.status, 200);
  assertEquals(store.applied[0].status, "cancelled");
  assertEquals(store.applied[0].periodEnd, FIXED_NOW.toISOString());
});

Deno.test("webhook: an entitlement write failure is retried, not acknowledged as done", async () => {
  const store = new FakeWebhookStore();
  store.applyResult = { ok: false, error: "rpc failed" };
  const { handler } = webhookHarness({ store });
  const response = await handler(jsonRequest(WEBHOOK_URL, {
    body: event("BILLING.SUBSCRIPTION.ACTIVATED"),
    headers: signatureHeaders(),
  }));
  assertEquals(response.status, 500);
  assertEquals(store.recorded.length, 0);
});

Deno.test("webhook: a deleted subscription is acknowledged without an entitlement", async () => {
  const paypal = fakePayPal({ subscriptionStatus: 404 });
  const { handler, store } = webhookHarness({ paypal });
  const response = await handler(jsonRequest(WEBHOOK_URL, {
    body: event("BILLING.SUBSCRIPTION.ACTIVATED"),
    headers: signatureHeaders(),
  }));
  assertEquals(response.status, 200);
  assertEquals(store.applied.length, 0);
});

Deno.test("webhook: PayPal verification outage returns 502 so PayPal retries", async () => {
  const paypal = fakePayPal({ subscriptionStatus: 503 });
  const { handler } = webhookHarness({ paypal });
  const response = await handler(jsonRequest(WEBHOOK_URL, {
    body: event("BILLING.SUBSCRIPTION.ACTIVATED"),
    headers: signatureHeaders(),
  }));
  assertEquals(response.status, 502);
});

// ===========================================================================
// Reconciliation
// ===========================================================================

Deno.test("sync: requires authentication", async () => {
  const { handler } = syncHarness();
  const response = await handler(jsonRequest(SYNC_URL, { authorization: null }));
  assertEquals(response.status, 401);
});

Deno.test("sync: reports none when there is no subscription", async () => {
  const { handler } = syncHarness();
  const response = await handler(jsonRequest(SYNC_URL));
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.status, "none");
  assertEquals(body.isPro, false);
});

Deno.test("sync: reconciles a paid, active subscription to Pro", async () => {
  const store = new FakeSyncStore();
  store.attempt = {
    userId: USER_ID,
    requestId: "8f14e45f-ceea-467f-a3bd-1a2b3c4d5e6f",
    subscriptionId: SUBSCRIPTION_ID,
    approvalUrl: "https://www.sandbox.paypal.com/checkoutnow?token=I-1",
    status: "pending",
    updatedAt: "2026-11-08T11:50:00.000Z",
  };
  const { handler, paypal } = syncHarness({ store });
  const response = await handler(jsonRequest(SYNC_URL));
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.isPro, true);
  assertEquals(body.status, "active");
  assertEquals(body.provider, "paypal");
  assertEquals(paypal.count("GET", `/v1/billing/subscriptions/${SUBSCRIPTION_ID}`), 1);
});

Deno.test("sync: an approved but unpaid subscription stays pending", async () => {
  const store = new FakeSyncStore();
  store.attempt = {
    userId: USER_ID,
    requestId: "8f14e45f-ceea-467f-a3bd-1a2b3c4d5e6f",
    subscriptionId: SUBSCRIPTION_ID,
    approvalUrl: null,
    status: "pending",
    updatedAt: "2026-11-08T11:50:00.000Z",
  };
  const paypal = fakePayPal({
    subscription: activeSubscription({ billing_info: { next_billing_time: "2026-12-08T11:55:00.000Z" } }),
  });
  const { handler } = syncHarness({ store, paypal });
  const body = await (await handler(jsonRequest(SYNC_URL))).json();
  assertEquals(body.isPro, false);
  assertEquals(body.status, "pending");
});

Deno.test("sync: a subscription belonging to another account is refused", async () => {
  const store = new FakeSyncStore();
  store.attempt = {
    userId: USER_ID,
    requestId: "8f14e45f-ceea-467f-a3bd-1a2b3c4d5e6f",
    subscriptionId: SUBSCRIPTION_ID,
    approvalUrl: null,
    status: "pending",
    updatedAt: "2026-11-08T11:50:00.000Z",
  };
  const paypal = fakePayPal({
    subscription: activeSubscription({ custom_id: "11111111-1111-4111-8111-111111111111" }),
  });
  const { handler } = syncHarness({ store, paypal });
  const response = await handler(jsonRequest(SYNC_URL));
  assertEquals(response.status, 403);
  assertEquals((await response.json()).code, "account_mismatch");
  assertEquals(store.applied.length, 0);
});

Deno.test("sync: a recent check is served from the database without calling PayPal", async () => {
  const store = new FakeSyncStore();
  store.entitlement = {
    userId: USER_ID,
    status: "active",
    currentPeriodEnd: "2026-12-08T11:55:00.000Z",
    providerStatusUpdatedAt: "2026-11-08T11:55:00.000Z",
    updatedAt: FIXED_NOW.toISOString(),
    subscriptionId: SUBSCRIPTION_ID,
  };
  const { handler, paypal } = syncHarness({ store });
  const body = await (await handler(jsonRequest(SYNC_URL))).json();
  assertEquals(body.isPro, true);
  assertEquals(paypal.calls.length, 0);
});

Deno.test("sync: a PayPal outage returns 502 and leaves access unchanged", async () => {
  const store = new FakeSyncStore();
  store.attempt = {
    userId: USER_ID,
    requestId: "8f14e45f-ceea-467f-a3bd-1a2b3c4d5e6f",
    subscriptionId: SUBSCRIPTION_ID,
    approvalUrl: null,
    status: "pending",
    updatedAt: "2026-11-08T11:50:00.000Z",
  };
  const paypal = fakePayPal({ subscriptionStatus: 503 });
  const { handler } = syncHarness({ store, paypal });
  const response = await handler(jsonRequest(SYNC_URL));
  assertEquals(response.status, 502);
  assertEquals(store.applied.length, 0);
});

Deno.test("isEntitled: only active, or cancelled within the paid-through window", () => {
  const now = FIXED_NOW;
  const base: EntitlementSnapshot = {
    userId: USER_ID,
    status: "active",
    currentPeriodEnd: "2026-12-08T11:55:00.000Z",
    providerStatusUpdatedAt: null,
    updatedAt: "2026-11-08T11:00:00.000Z",
    subscriptionId: SUBSCRIPTION_ID,
  };
  assert(isEntitled(base, now));
  assert(isEntitled({ ...base, status: "cancelled" }, now));
  assertFalse(isEntitled({ ...base, status: "cancelled", currentPeriodEnd: "2026-10-08T11:55:00.000Z" }, now));
  assertFalse(isEntitled({ ...base, status: "past_due" }, now));
  assertFalse(isEntitled({ ...base, status: "expired" }, now));
  assertFalse(isEntitled({ ...base, status: "pending" }, now));
  assertFalse(isEntitled({ ...base, status: "active", currentPeriodEnd: "2026-10-08T11:55:00.000Z" }, now));
  assertFalse(isEntitled(null, now));
});
