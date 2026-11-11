import { assertEquals, assert } from "jsr:@std/assert@1";
import {
  decideRevenueCatEntitlement,
  isLedgerlyAccountId,
} from "../_shared/revenuecat.ts";

const NOW = new Date("2026-11-11T12:00:00.000Z");
const FUTURE = Date.parse("2026-12-11T12:00:00.000Z");

Deno.test("RevenueCat purchase grants only a bounded future entitlement", () => {
  assertEquals(
    decideRevenueCatEntitlement({
      type: "INITIAL_PURCHASE",
      eventTimestampMs: NOW.getTime(),
      expirationAtMs: FUTURE,
    }, NOW),
    { status: "active", periodEnd: "2026-12-11T12:00:00.000Z" },
  );
});

Deno.test("refund reversal without a future expiry never creates open-ended Pro", () => {
  assertEquals(
    decideRevenueCatEntitlement({
      type: "REFUND_REVERSED",
      eventTimestampMs: NOW.getTime(),
      expirationAtMs: null,
    }, NOW),
    { status: "expired", periodEnd: null },
  );
});

Deno.test("renewal without an expiry cannot grant Pro", () => {
  assertEquals(
    decideRevenueCatEntitlement({
      type: "RENEWAL",
      eventTimestampMs: NOW.getTime(),
      expirationAtMs: null,
    }, NOW),
    { status: "expired", periodEnd: null },
  );
});

Deno.test("cancellation retains only the provider-confirmed paid-through date", () => {
  assertEquals(
    decideRevenueCatEntitlement({
      type: "CANCELLATION",
      eventTimestampMs: NOW.getTime(),
      expirationAtMs: FUTURE,
    }, NOW),
    { status: "cancelled", periodEnd: "2026-12-11T12:00:00.000Z" },
  );
  assertEquals(
    decideRevenueCatEntitlement({
      type: "CANCELLATION",
      eventTimestampMs: NOW.getTime(),
      expirationAtMs: null,
    }, NOW),
    { status: "cancelled", periodEnd: null },
  );
});

Deno.test("billing issue grants only through a future provider grace period", () => {
  assertEquals(
    decideRevenueCatEntitlement({
      type: "BILLING_ISSUE",
      eventTimestampMs: NOW.getTime(),
      expirationAtMs: FUTURE,
      gracePeriodExpirationAtMs: FUTURE,
    }, NOW),
    { status: "active", periodEnd: "2026-12-11T12:00:00.000Z" },
  );
  assertEquals(
    decideRevenueCatEntitlement({
      type: "BILLING_ISSUE",
      eventTimestampMs: NOW.getTime(),
      expirationAtMs: FUTURE,
      gracePeriodExpirationAtMs: null,
    }, NOW),
    { status: "past_due", periodEnd: "2026-12-11T12:00:00.000Z" },
  );
});

Deno.test("unknown event types are ignored rather than treated as purchases", () => {
  assertEquals(
    decideRevenueCatEntitlement({
      type: "UNRECOGNIZED_EVENT",
      eventTimestampMs: NOW.getTime(),
      expirationAtMs: FUTURE,
    }, NOW),
    null,
  );
});

Deno.test("malformed event times are rejected", () => {
  let rejected = false;
  try {
    decideRevenueCatEntitlement({
      type: "INITIAL_PURCHASE",
      eventTimestampMs: Number.NaN,
      expirationAtMs: FUTURE,
    }, NOW);
  } catch {
    rejected = true;
  }
  assert(rejected);
});

Deno.test("RevenueCat account reference must be a canonical UUID", () => {
  assert(isLedgerlyAccountId("9f1d4a3e-6c2b-4f8a-9d1e-2b3c4d5e6f70"));
  assert(!isLedgerlyAccountId("anonymous-user"));
  assert(!isLedgerlyAccountId("9f1d4a3e-6c2b-4f8a-9d1e-2b3c4d5e6f7"));
});
