export type RevenueCatEntitlementStatus =
  | "active"
  | "cancelled"
  | "expired"
  | "past_due";

export interface RevenueCatEntitlementEvent {
  type: string;
  eventTimestampMs: number;
  expirationAtMs?: number | null;
  gracePeriodExpirationAtMs?: number | null;
}

export interface RevenueCatEntitlementDecision {
  status: RevenueCatEntitlementStatus;
  periodEnd: string | null;
}

const ACTIVE_EVENTS = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "PRODUCT_CHANGE",
  "UNCANCELLATION",
  "NON_RENEWING_PURCHASE",
  "REFUND_REVERSED",
  "TEMPORARY_ENTITLEMENT_GRANT",
]);

const TERMINAL_EVENTS = new Set(["EXPIRATION", "REFUND"]);
const SUPPORTED_EVENTS = new Set([
  ...ACTIVE_EVENTS,
  ...TERMINAL_EVENTS,
  "CANCELLATION",
  "BILLING_ISSUE",
]);

/**
 * Converts only known RevenueCat entitlement events into a server-side
 * entitlement decision. Unknown event types are ignored, never treated as
 * purchases. Active access always has an explicit future expiry.
 */
export function decideRevenueCatEntitlement(
  event: RevenueCatEntitlementEvent,
  now: Date,
): RevenueCatEntitlementDecision | null {
  if (!SUPPORTED_EVENTS.has(event.type)) return null;

  if (!Number.isFinite(event.eventTimestampMs) ||
      !Number.isFinite(new Date(event.eventTimestampMs).getTime())) {
    throw new Error("RevenueCat event has no valid timestamp");
  }

  const expiry = event.expirationAtMs ?? null;
  const grace = event.gracePeriodExpirationAtMs ?? null;
  if (expiry !== null &&
      (!Number.isFinite(expiry) || !Number.isFinite(new Date(expiry).getTime()))) {
    throw new Error("RevenueCat event has an invalid expiration");
  }
  if (grace !== null &&
      (!Number.isFinite(grace) || !Number.isFinite(new Date(grace).getTime()))) {
    throw new Error("RevenueCat event has an invalid grace-period expiration");
  }

  const iso = (timestamp: number | null) =>
    timestamp === null ? null : new Date(timestamp).toISOString();

  if (TERMINAL_EVENTS.has(event.type)) {
    return { status: "expired", periodEnd: iso(expiry) };
  }

  if (event.type === "CANCELLATION") {
    return { status: "cancelled", periodEnd: iso(expiry) };
  }

  if (event.type === "BILLING_ISSUE") {
    if (grace !== null && grace > now.getTime()) {
      return { status: "active", periodEnd: iso(grace) };
    }
    return { status: "past_due", periodEnd: iso(expiry) };
  }

  // Purchases, renewals, uncancellations and refund reversals must carry a
  // provider-confirmed future expiry. Never create an open-ended active row.
  if (ACTIVE_EVENTS.has(event.type) && expiry !== null && expiry > now.getTime()) {
    return { status: "active", periodEnd: iso(expiry) };
  }

  return { status: "expired", periodEnd: iso(expiry) };
}

/** RevenueCat app_user_id must be a canonical signed-in Supabase UUID. */
export function isLedgerlyAccountId(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}
