import { assertEquals, assert, assertFalse } from "jsr:@std/assert@1";
import {
  addOneMonth,
  amountMatches,
  decideEntitlement,
  decideFromCanonicalSubscription,
  extractSubscriptionId,
  parseCheckoutReference,
  paymentEvidence,
  verifyPlan,
  LEDGERLY_PRO_PLAN,
  type PaypalSubscription,
} from "../_shared/paypal.ts";
import { ACTIVE_PLAN, FIXED_NOW, PLAN_ID, SUBSCRIPTION_ID, USER_ID, activeSubscription } from "./support.ts";

const context = {
  previousStatus: null as string | null,
  previousPeriodEnd: null as string | null,
  previousVersionTime: null as string | null,
};

function decide(
  overrides: {
    eventType: string;
    subscription?: PaypalSubscription;
    eventTime?: string | null;
    saleAmount?: { currency_code?: string; value?: string } | null;
    context?: typeof context;
  },
) {
  return decideEntitlement({
    eventType: overrides.eventType,
    subscription: overrides.subscription ?? (activeSubscription() as PaypalSubscription),
    eventTime: overrides.eventTime === undefined ? "2026-11-08T11:56:00.000Z" : overrides.eventTime,
    saleAmount: overrides.saleAmount,
    context: overrides.context ?? context,
    now: FIXED_NOW,
  });
}

Deno.test("addOneMonth clamps end-of-month dates", () => {
  assertEquals(addOneMonth(new Date("2026-01-31T00:00:00Z")).toISOString(), "2026-02-28T00:00:00.000Z");
  assertEquals(addOneMonth(new Date("2024-01-31T00:00:00Z")).toISOString(), "2024-02-29T00:00:00.000Z");
  assertEquals(addOneMonth(new Date("2026-03-15T10:00:00Z")).toISOString(), "2026-04-15T10:00:00.000Z");
});

Deno.test("verifyPlan accepts an ACTIVE USD 3.00 monthly plan", () => {
  const check = verifyPlan(ACTIVE_PLAN);
  assert(check.ok);
  assertEquals(check.price, { currency: "USD", value: "3.00" });
});

Deno.test("verifyPlan rejects a suspended plan", () => {
  const check = verifyPlan({ ...ACTIVE_PLAN, status: "INACTIVE" });
  assertFalse(check.ok);
  assert(check.reason?.includes("ACTIVE"));
});

Deno.test("verifyPlan rejects the wrong price", () => {
  const plan = JSON.parse(JSON.stringify(ACTIVE_PLAN));
  plan.billing_cycles[0].pricing_scheme.fixed_price.value = "9.99";
  assertFalse(verifyPlan(plan).ok);
});

Deno.test("verifyPlan rejects the wrong currency and interval", () => {
  const eur = JSON.parse(JSON.stringify(ACTIVE_PLAN));
  eur.billing_cycles[0].pricing_scheme.fixed_price.currency_code = "EUR";
  assertFalse(verifyPlan(eur).ok);

  const yearly = JSON.parse(JSON.stringify(ACTIVE_PLAN));
  yearly.billing_cycles[0].frequency.interval_unit = "YEAR";
  assertFalse(verifyPlan(yearly).ok);

  const everyTwoMonths = JSON.parse(JSON.stringify(ACTIVE_PLAN));
  everyTwoMonths.billing_cycles[0].frequency.interval_count = 2;
  assertFalse(verifyPlan(everyTwoMonths).ok);
});

Deno.test("amountMatches tolerates formatting differences but not a different price", () => {
  assert(amountMatches({ currency_code: "USD", value: "3" }));
  assert(amountMatches({ currency_code: "usd", value: "3.00" }));
  assertFalse(amountMatches({ currency_code: "USD", value: "3.01" }));
  assertFalse(amountMatches({ currency_code: "EUR", value: "3.00" }));
  assertFalse(amountMatches(null));
});

Deno.test("paymentEvidence requires a matching payment and no newer failure", () => {
  assertEquals(paymentEvidence(activeSubscription() as PaypalSubscription).paid, true);

  const noPayment = activeSubscription({ billing_info: { next_billing_time: "2026-12-08T11:55:00.000Z" } });
  assertFalse(paymentEvidence(noPayment as PaypalSubscription).paid);

  const newerFailure = activeSubscription({
    billing_info: {
      next_billing_time: "2026-12-08T11:55:00.000Z",
      last_payment: { amount: { currency_code: "USD", value: "3.00" }, time: "2026-11-08T11:00:00.000Z" },
      last_failed_payment: { amount: { currency_code: "USD", value: "3.00" }, time: "2026-12-08T11:00:00.000Z" },
    },
  });
  assertFalse(paymentEvidence(newerFailure as PaypalSubscription).paid);

  const wrongAmount = activeSubscription({
    billing_info: {
      last_payment: { amount: { currency_code: "USD", value: "1.00" }, time: "2026-11-08T11:00:00.000Z" },
    },
  });
  assertFalse(paymentEvidence(wrongAmount as PaypalSubscription).paid);
});

Deno.test("extractSubscriptionId handles subscription and sale events", () => {
  assertEquals(
    extractSubscriptionId({ event_type: "BILLING.SUBSCRIPTION.ACTIVATED", resource: { id: SUBSCRIPTION_ID } }),
    SUBSCRIPTION_ID,
  );
  assertEquals(
    extractSubscriptionId({ event_type: "PAYMENT.SALE.COMPLETED", resource: { billing_agreement_id: SUBSCRIPTION_ID } }),
    SUBSCRIPTION_ID,
  );
  assertEquals(
    extractSubscriptionId({
      event_type: "PAYMENT.SALE.REFUNDED",
      resource: { supplementary_data: { related_ids: { subscription_id: SUBSCRIPTION_ID } } },
    }),
    SUBSCRIPTION_ID,
  );
  assertEquals(extractSubscriptionId({ event_type: "PAYMENT.SALE.COMPLETED", resource: {} }), null);
});

Deno.test("parseCheckoutReference accepts the account:id pair and legacy uuid", () => {
  const paired = parseCheckoutReference(`${USER_ID}:8f14e45f-ceea-467f-a3bd-1a2b3c4d5e6f`);
  assertEquals(paired?.userId, USER_ID);
  assertEquals(paired?.requestId, "8f14e45f-ceea-467f-a3bd-1a2b3c4d5e6f");

  const legacy = parseCheckoutReference(USER_ID);
  assertEquals(legacy?.userId, USER_ID);
  assertEquals(legacy?.requestId, null);

  assertEquals(parseCheckoutReference("not-a-uuid"), null);
  assertEquals(parseCheckoutReference(""), null);
});

Deno.test("activation without a verified payment stays pending", () => {
  const subscription = activeSubscription({
    billing_info: { next_billing_time: "2026-12-08T11:55:00.000Z" },
  });
  const decision = decide({ eventType: "BILLING.SUBSCRIPTION.ACTIVATED", subscription: subscription as PaypalSubscription });
  assertEquals(decision.action, "apply");
  if (decision.action === "apply") assertEquals(decision.status, "pending");
});

Deno.test("activation with a verified payment grants Pro through the next billing date", () => {
  const decision = decide({ eventType: "BILLING.SUBSCRIPTION.ACTIVATED" });
  assertEquals(decision.action, "apply");
  if (decision.action === "apply") {
    assertEquals(decision.status, "active");
    assertEquals(decision.periodEnd, "2026-12-08T11:55:00.000Z");
  }
});

Deno.test("re-activation with a verified payment restores Pro", () => {
  const decision = decide({
    eventType: "BILLING.SUBSCRIPTION.RE-ACTIVATED",
    context: { previousStatus: "suspended", previousPeriodEnd: null, previousVersionTime: null },
  });
  assertEquals(decision.action, "apply");
  if (decision.action === "apply") assertEquals(decision.status, "active");
});

Deno.test("an update keeps an already-active subscription active", () => {
  const decision = decide({
    eventType: "BILLING.SUBSCRIPTION.UPDATED",
    context: { previousStatus: "active", previousPeriodEnd: "2026-12-08T11:55:00.000Z", previousVersionTime: null },
  });
  assertEquals(decision.action, "apply");
  if (decision.action === "apply") assertEquals(decision.status, "active");
});

Deno.test("a completed sale with the right amount activates Pro", () => {
  const decision = decide({
    eventType: "PAYMENT.SALE.COMPLETED",
    saleAmount: { currency_code: "USD", value: "3.00" },
  });
  assertEquals(decision.action, "apply");
  if (decision.action === "apply") assertEquals(decision.status, "active");
});

Deno.test("a completed sale for a different amount is ignored", () => {
  const decision = decide({
    eventType: "PAYMENT.SALE.COMPLETED",
    saleAmount: { currency_code: "USD", value: "0.01" },
  });
  assertEquals(decision.action, "ignore");
});

Deno.test("a payment event without an amount is ignored", () => {
  assertEquals(decide({ eventType: "PAYMENT.SALE.COMPLETED" }).action, "ignore");
});

Deno.test("a refund revokes access immediately", () => {
  const decision = decide({ eventType: "PAYMENT.SALE.REFUNDED" });
  assertEquals(decision.action, "apply");
  if (decision.action === "apply") {
    assertEquals(decision.status, "cancelled");
    assertEquals(decision.periodEnd, FIXED_NOW.toISOString());
  }
});

Deno.test("a reversal revokes access immediately", () => {
  const decision = decide({ eventType: "PAYMENT.SALE.REVERSED" });
  if (decision.action === "apply") assertEquals(decision.status, "cancelled");
  else assert(false);
});

Deno.test("cancellation keeps access until the paid-through date", () => {
  const subscription = activeSubscription({ status: "CANCELLED", status_update_time: "2026-11-08T11:58:00.000Z" });
  const decision = decide({
    eventType: "BILLING.SUBSCRIPTION.CANCELLED",
    subscription: subscription as PaypalSubscription,
    eventTime: "2026-11-08T11:59:00.000Z",
    context: { previousStatus: "active", previousPeriodEnd: "2026-12-08T11:55:00.000Z", previousVersionTime: null },
  });
  assertEquals(decision.action, "apply");
  if (decision.action === "apply") {
    assertEquals(decision.status, "cancelled");
    assertEquals(decision.periodEnd, "2026-12-08T11:55:00.000Z");
  }
});

Deno.test("expiry revokes access now", () => {
  const subscription = activeSubscription({ status: "EXPIRED", billing_info: {} });
  const decision = decide({
    eventType: "BILLING.SUBSCRIPTION.EXPIRED",
    subscription: subscription as PaypalSubscription,
  });
  if (decision.action === "apply") {
    assertEquals(decision.status, "expired");
    assertEquals(decision.periodEnd, FIXED_NOW.toISOString());
  } else assert(false);
});

Deno.test("suspension and failed payment never grant Pro", () => {
  const suspended = decide({ eventType: "BILLING.SUBSCRIPTION.SUSPENDED", subscription: activeSubscription({ status: "SUSPENDED" }) as PaypalSubscription });
  if (suspended.action === "apply") assertEquals(suspended.status, "suspended");

  const failed = decide({ eventType: "BILLING.SUBSCRIPTION.PAYMENT.FAILED" });
  if (failed.action === "apply") assertEquals(failed.status, "past_due");
  else assert(false);
});

Deno.test("a stale activation cannot overwrite newer provider state", () => {
  const decision = decide({
    eventType: "BILLING.SUBSCRIPTION.ACTIVATED",
    eventTime: "2026-11-08T10:00:00.000Z", // older than status_update_time 11:55
  });
  assertEquals(decision.action, "ignore");
});

Deno.test("a stale event cannot resurrect an expired subscription", () => {
  const decision = decide({
    eventType: "BILLING.SUBSCRIPTION.UPDATED",
    eventTime: "2026-11-08T09:00:00.000Z",
    context: { previousStatus: "expired", previousPeriodEnd: "2026-11-01T00:00:00.000Z", previousVersionTime: "2026-11-01T00:00:00.000Z" },
  });
  assertEquals(decision.action, "ignore");
});

Deno.test("a cancelled subscription with a past paid-through date does not reactivate", () => {
  const decision = decide({
    eventType: "BILLING.SUBSCRIPTION.UPDATED",
    subscription: activeSubscription({ billing_info: {} }) as PaypalSubscription,
    context: { previousStatus: "cancelled", previousPeriodEnd: "2026-10-01T00:00:00.000Z", previousVersionTime: null },
  });
  if (decision.action === "apply") assertEquals(decision.status, "cancelled");
  else assert(false);
});

Deno.test("unsupported events are ignored", () => {
  assertEquals(decide({ eventType: "CATALOG.PRODUCT.CREATED" }).action, "ignore");
});

Deno.test("reconciliation grants Pro only with payment evidence", () => {
  const paid = decideFromCanonicalSubscription(activeSubscription() as PaypalSubscription, context, FIXED_NOW);
  assertEquals(paid.action, "apply");
  if (paid.action === "apply") assertEquals(paid.status, "active");

  const unpaid = decideFromCanonicalSubscription(
    activeSubscription({ billing_info: { next_billing_time: "2026-12-08T11:55:00.000Z" } }) as PaypalSubscription,
    context,
    FIXED_NOW,
  );
  if (unpaid.action === "apply") assertEquals(unpaid.status, "pending");
  else assert(false);
});

Deno.test("reconciliation ignores a stored state newer than PayPal's", () => {
  const decision = decideFromCanonicalSubscription(
    activeSubscription({ status: "CANCELLED" }) as PaypalSubscription,
    { previousStatus: "active", previousPeriodEnd: "2026-12-08T11:55:00.000Z", previousVersionTime: "2026-11-09T00:00:00.000Z" },
    FIXED_NOW,
  );
  assertEquals(decision.action, "ignore");
});

Deno.test("reconciliation maps PayPal terminal states", () => {
  const expired = decideFromCanonicalSubscription(
    activeSubscription({ status: "EXPIRED", billing_info: {} }) as PaypalSubscription,
    context,
    FIXED_NOW,
  );
  if (expired.action === "apply") assertEquals(expired.status, "expired");

  const suspended = decideFromCanonicalSubscription(
    activeSubscription({ status: "SUSPENDED" }) as PaypalSubscription,
    context,
    FIXED_NOW,
  );
  if (suspended.action === "apply") assertEquals(suspended.status, "suspended");

  const pending = decideFromCanonicalSubscription(
    activeSubscription({ status: "APPROVAL_PENDING", billing_info: {} }) as PaypalSubscription,
    context,
    FIXED_NOW,
  );
  if (pending.action === "apply") assertEquals(pending.status, "pending");
});

Deno.test("the Ledgerly plan expectation is exactly USD 3.00 monthly", () => {
  assertEquals(LEDGERLY_PRO_PLAN, {
    currency: "USD",
    amount: "3.00",
    intervalUnit: "MONTH",
    intervalCount: 1,
  });
  assertEquals(PLAN_ID, "P-LEDGERLY-PRO");
});
