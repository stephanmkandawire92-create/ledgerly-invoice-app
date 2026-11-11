// PayPal Billing Subscriptions client + entitlement rules.
//
// The functions in this module are deliberately free of Deno globals so they
// can be unit tested with an injected `fetch` and a fixed clock. `Deno.env` is
// only read in the function entry points via `config.ts`.

import type { PayPalSettings, PayPalEnv } from "./config.ts";

export type PaypalFetch = typeof fetch;

export type EntitlementStatus =
  | "active"
  | "cancelled"
  | "expired"
  | "past_due"
  | "suspended"
  | "pending";

export interface Money {
  currency_code?: string;
  value?: string;
}

export interface PaypalPlan {
  id?: string;
  status?: string;
  billing_cycles?: Array<{
    tenure_type?: string;
    sequence?: number;
    frequency?: { interval_unit?: string; interval_count?: number };
    pricing_scheme?: { fixed_price?: Money };
  }>;
}

export interface PaypalSubscription {
  id?: string;
  plan_id?: string;
  status?: string;
  status_update_time?: string;
  create_time?: string;
  custom_id?: string;
  billing_info?: {
    next_billing_time?: string;
    last_payment?: { amount?: Money; time?: string };
    last_failed_payment?: { amount?: Money; time?: string };
    failed_payments_count?: number;
  };
}

export interface PaypalEvent {
  id?: string;
  event_type?: string;
  create_time?: string;
  resource?: Record<string, unknown>;
}

export interface PlanExpectation {
  currency: string;
  amount: string;
  intervalUnit: string;
  intervalCount: number;
}

/** Ledgerly Pro: USD 3.00 per month. */
export const LEDGERLY_PRO_PLAN: PlanExpectation = {
  currency: "USD",
  amount: "3.00",
  intervalUnit: "MONTH",
  intervalCount: 1,
};

// ---------------------------------------------------------------------------
// HTTP plumbing
// ---------------------------------------------------------------------------

async function readJson(response: Response): Promise<Record<string, unknown>> {
  try {
    const parsed = await response.json();
    return parsed && typeof parsed === "object" ? parsed as Record<string, unknown> : {};
  } catch {
    return {};
  }
}

export class PaypalApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly transient: boolean,
  ) {
    super(message);
    this.name = "PaypalApiError";
  }
}

export async function getAccessToken(
  settings: Pick<PayPalSettings, "apiBase" | "clientId" | "clientSecret">,
  fetchImpl: PaypalFetch,
): Promise<string> {
  const response = await fetchImpl(`${settings.apiBase}/v1/oauth2/token`, {
    method: "POST",
    headers: {
      // btoa is available in Deno and in browsers; the credentials never leave
      // the server process.
      Authorization: `Basic ${btoa(`${settings.clientId}:${settings.clientSecret}`)}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });
  if (!response.ok) {
    throw new PaypalApiError("PayPal OAuth failed", response.status, response.status >= 500);
  }
  const body = await readJson(response);
  const token = body.access_token;
  if (typeof token !== "string" || !token) {
    throw new PaypalApiError("PayPal OAuth returned no access token", 502, true);
  }
  return token;
}

export async function fetchPlan(
  apiBase: string,
  planId: string,
  token: string,
  fetchImpl: PaypalFetch,
): Promise<PaypalPlan> {
  const response = await fetchImpl(
    `${apiBase}/v1/billing/plans/${encodeURIComponent(planId)}`,
    { headers: { Authorization: `Bearer ${token}` } },
  );
  if (!response.ok) {
    throw new PaypalApiError(
      `PayPal plan lookup failed (${response.status})`,
      response.status,
      response.status >= 500,
    );
  }
  return await readJson(response) as PaypalPlan;
}

export async function fetchSubscription(
  apiBase: string,
  subscriptionId: string,
  token: string,
  fetchImpl: PaypalFetch,
): Promise<PaypalSubscription> {
  const response = await fetchImpl(
    `${apiBase}/v1/billing/subscriptions/${encodeURIComponent(subscriptionId)}`,
    { headers: { Authorization: `Bearer ${token}` } },
  );
  if (!response.ok) {
    throw new PaypalApiError(
      `PayPal subscription lookup failed (${response.status})`,
      response.status,
      response.status >= 500,
    );
  }
  return await readJson(response) as PaypalSubscription;
}

export interface WebhookSignatureHeaders {
  authAlgo: string | null;
  certUrl: string | null;
  transmissionId: string | null;
  transmissionSig: string | null;
  transmissionTime: string | null;
}

export function readSignatureHeaders(headers: Headers): WebhookSignatureHeaders {
  return {
    authAlgo: headers.get("paypal-auth-algo"),
    certUrl: headers.get("paypal-cert-url"),
    transmissionId: headers.get("paypal-transmission-id"),
    transmissionSig: headers.get("paypal-transmission-sig"),
    transmissionTime: headers.get("paypal-transmission-time"),
  };
}

export function hasAllSignatureHeaders(headers: WebhookSignatureHeaders): boolean {
  return Boolean(
    headers.authAlgo &&
      headers.certUrl &&
      headers.transmissionId &&
      headers.transmissionSig &&
      headers.transmissionTime,
  );
}

/**
 * Server-side verification against PayPal's own endpoint. This is the only
 * accepted proof that a webhook delivery came from PayPal; the request body
 * is never trusted on its own.
 */
export async function verifyWebhookSignature(
  settings: Pick<PayPalSettings, "apiBase" | "webhookId">,
  token: string,
  headers: WebhookSignatureHeaders,
  event: unknown,
  fetchImpl: PaypalFetch,
): Promise<boolean> {
  if (!settings.webhookId || !hasAllSignatureHeaders(headers)) return false;
  const response = await fetchImpl(`${settings.apiBase}/v1/notifications/verify-webhook-signature`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      auth_algo: headers.authAlgo,
      cert_url: headers.certUrl,
      transmission_id: headers.transmissionId,
      transmission_sig: headers.transmissionSig,
      transmission_time: headers.transmissionTime,
      webhook_id: settings.webhookId,
      webhook_event: event,
    }),
  });
  if (!response.ok) return false;
  const body = await readJson(response);
  return body.verification_status === "SUCCESS";
}

// ---------------------------------------------------------------------------
// Plan verification
// ---------------------------------------------------------------------------

export interface PlanCheck {
  ok: boolean;
  reason?: string;
  price?: { currency: string; value: string };
}

function moneyMatches(money: Money | undefined, expected: PlanExpectation): boolean {
  if (!money) return false;
  if ((money.currency_code ?? "").toUpperCase() !== expected.currency) return false;
  const value = Number(money.value);
  return Number.isFinite(value) && Math.abs(value - Number(expected.amount)) < 0.005;
}

/** Exposed for tests and for validating individual payment events. */
export function amountMatches(money: Money | null | undefined, expected: PlanExpectation = LEDGERLY_PRO_PLAN): boolean {
  return moneyMatches(money ?? undefined, expected);
}

/** Confirms the plan is ACTIVE and priced exactly as the product advertises. */
export function verifyPlan(plan: PaypalPlan, expected: PlanExpectation = LEDGERLY_PRO_PLAN): PlanCheck {
  if (plan.status !== "ACTIVE") {
    return { ok: false, reason: `plan status is ${plan.status ?? "missing"}, expected ACTIVE` };
  }
  const cycles = Array.isArray(plan.billing_cycles) ? plan.billing_cycles : [];
  const regular = cycles.find((cycle) => cycle.tenure_type === "REGULAR");
  if (!regular) return { ok: false, reason: "plan has no REGULAR billing cycle" };
  if (!moneyMatches(regular.pricing_scheme?.fixed_price, expected)) {
    return { ok: false, reason: `plan price is not ${expected.currency} ${expected.amount}` };
  }
  if (regular.frequency?.interval_unit !== expected.intervalUnit) {
    return { ok: false, reason: "plan interval unit is not MONTH" };
  }
  if (regular.frequency?.interval_count !== expected.intervalCount) {
    return { ok: false, reason: "plan interval count is not 1" };
  }
  const price = regular.pricing_scheme?.fixed_price as Money;
  return { ok: true, price: { currency: price.currency_code as string, value: price.value as string } };
}

// ---------------------------------------------------------------------------
// Event classification and entitlement decisions
// ---------------------------------------------------------------------------

export const SUBSCRIPTION_EVENTS = new Set([
  "BILLING.SUBSCRIPTION.ACTIVATED",
  "BILLING.SUBSCRIPTION.UPDATED",
  "BILLING.SUBSCRIPTION.RE-ACTIVATED",
  "BILLING.SUBSCRIPTION.SUSPENDED",
  "BILLING.SUBSCRIPTION.CANCELLED",
  "BILLING.SUBSCRIPTION.EXPIRED",
  "BILLING.SUBSCRIPTION.PAYMENT.FAILED",
  "PAYMENT.SALE.COMPLETED",
  "PAYMENT.SALE.REFUNDED",
  "PAYMENT.SALE.REVERSED",
]);

const PAYMENT_EVENTS = new Set([
  "PAYMENT.SALE.COMPLETED",
  "PAYMENT.SALE.REFUNDED",
  "PAYMENT.SALE.REVERSED",
]);

export function isSupportedEvent(eventType: string): boolean {
  return SUBSCRIPTION_EVENTS.has(eventType);
}

/**
 * Extracts the PayPal subscription id from an event without trusting arbitrary
 * fields. Subscription events carry the id in `resource.id`; payment events
 * carry it in `billing_agreement_id` (or the supplementary related ids).
 */
export function extractSubscriptionId(event: PaypalEvent): string | null {
  const resource = event.resource ?? {};
  const type = event.event_type ?? "";
  if (type.startsWith("BILLING.SUBSCRIPTION.")) {
    return typeof resource.id === "string" && resource.id ? resource.id : null;
  }
  const direct = resource.billing_agreement_id ?? resource.subscription_id;
  if (typeof direct === "string" && direct) return direct;
  const supplementary = resource.supplementary_data as
    | { related_ids?: { subscription_id?: string } }
    | undefined;
  const related = supplementary?.related_ids?.subscription_id;
  return typeof related === "string" && related ? related : null;
}

export function extractRefundAmount(event: PaypalEvent): Money | null {
  const resource = event.resource ?? {};
  const amount = resource.amount as Money | undefined;
  return amount ?? null;
}

export function extractSaleAmount(event: PaypalEvent): Money | null {
  return extractRefundAmount(event);
}

export function canonicalStatus(paypalStatus: string | undefined): EntitlementStatus {
  switch ((paypalStatus ?? "").toUpperCase()) {
    case "ACTIVE":
      return "active";
    case "CANCELLED":
      return "cancelled";
    case "EXPIRED":
      return "expired";
    case "SUSPENDED":
      return "suspended";
    default:
      // APPROVAL_PENDING, APPROVED, or anything new PayPal introduces.
      return "pending";
  }
}

/** Adds one calendar month, clamping end-of-month dates (Jan 31 -> Feb 28/29). */
export function addOneMonth(from: Date): Date {
  const result = new Date(from.getTime());
  const day = result.getUTCDate();
  result.setUTCDate(1);
  result.setUTCMonth(result.getUTCMonth() + 1);
  const lastDay = new Date(Date.UTC(result.getUTCFullYear(), result.getUTCMonth() + 1, 0)).getUTCDate();
  result.setUTCDate(Math.min(day, lastDay));
  return result;
}

function parseTime(value: string | undefined | null): number | null {
  if (!value) return null;
  const time = Date.parse(value);
  return Number.isFinite(time) ? time : null;
}

export interface PaymentEvidence {
  paid: boolean;
  lastPaymentAt: string | null;
  reason: string;
}

/**
 * A successful payment is the only thing that may activate Ledgerly Pro.
 * `last_payment` must match the Ledgerly Pro price and must not be superseded
 * by a more recent failed payment.
 */
export function paymentEvidence(
  subscription: PaypalSubscription,
  expected: PlanExpectation = LEDGERLY_PRO_PLAN,
): PaymentEvidence {
  const lastPayment = subscription.billing_info?.last_payment;
  const lastFailed = subscription.billing_info?.last_failed_payment;
  const lastPaymentTime = parseTime(lastPayment?.time);
  if (!lastPayment) return { paid: false, lastPaymentAt: null, reason: "no recorded payment" };
  if (lastPaymentTime === null) {
    return { paid: false, lastPaymentAt: null, reason: "last payment has no valid provider timestamp" };
  }
  if (!moneyMatches(lastPayment.amount, expected)) {
    return { paid: false, lastPaymentAt: lastPayment?.time ?? null, reason: "last payment amount does not match the plan price" };
  }
  const lastFailedTime = parseTime(lastFailed?.time);
  if (lastFailedTime !== null && lastPaymentTime !== null && lastFailedTime > lastPaymentTime) {
    return { paid: false, lastPaymentAt: lastPayment.time ?? null, reason: "a newer payment attempt failed" };
  }
  if (
    subscription.billing_info?.failed_payments_count !== undefined &&
    subscription.billing_info.failed_payments_count > 0 &&
    lastFailedTime !== null
  ) {
    return { paid: false, lastPaymentAt: lastPayment.time ?? null, reason: "subscription reports failed payments" };
  }
  return { paid: true, lastPaymentAt: lastPayment?.time ?? null, reason: "verified payment on record" };
}

export interface EntitlementContext {
  previousStatus: string | null;
  previousPeriodEnd: string | null;
  previousVersionTime: string | null;
}

export interface EntitlementInput {
  eventType: string;
  subscription: PaypalSubscription;
  eventTime: string | null;
  /** Amount reported by a PAYMENT.SALE.* event, when the event has one. */
  saleAmount?: Money | null;
  context: EntitlementContext;
  now: Date;
  expected?: PlanExpectation;
}

export type EntitlementDecision =
  | { action: "ignore"; reason: string }
  | {
    action: "apply";
    status: EntitlementStatus;
    periodEnd: string | null;
    versionTime: string;
    reason: string;
  };

function activePeriodEnd(subscription: PaypalSubscription): string | null {
  const nextBilling = parseTime(subscription.billing_info?.next_billing_time);
  if (nextBilling !== null) return new Date(nextBilling).toISOString();
  // A subscription that is ACTIVE but has no next billing time is mid-cycle:
  // derive the paid-through date from the verified payment instead of leaving
  // the entitlement open-ended.
  const lastPayment = parseTime(subscription.billing_info?.last_payment?.time);
  if (lastPayment !== null) return addOneMonth(new Date(lastPayment)).toISOString();
  return null;
}

function keepPaidThrough(
  subscription: PaypalSubscription,
  ctx: EntitlementContext,
  now: Date,
): string | null {
  const nextBilling = parseTime(subscription.billing_info?.next_billing_time);
  if (nextBilling !== null && nextBilling > now.getTime()) {
    return new Date(nextBilling).toISOString();
  }
  const previous = parseTime(ctx.previousPeriodEnd);
  if (previous !== null && previous > now.getTime()) {
    return new Date(previous).toISOString();
  }
  return null;
}

/**
 * Decides the entitlement row for a verified event.
 *
 * Entitlement policy (documented in supabase/README.md):
 *  * Pro is granted only for `active`, and only with verified payment evidence.
 *  * Cancellation keeps access until the paid-through date (`cancelled`).
 *  * Expiry and a full refund or reversal revoke access immediately.
 *  * A failed renewal (`past_due`) never grants Pro.
 *  * A stale event never overwrites a newer provider state, and never
 *    resurrects an expired or refunded subscription.
 */
export function decideEntitlement(input: EntitlementInput): EntitlementDecision {
  const { eventType, subscription, context, now } = input;
  const expected = input.expected ?? LEDGERLY_PRO_PLAN;
  const canonical = canonicalStatus(subscription.status);

  const providerVersion = parseTime(subscription.status_update_time);
  const eventTime = parseTime(input.eventTime);
  const versionTime = providerVersion ?? eventTime;
  if (versionTime === null) {
    return { action: "ignore", reason: "PayPal subscription has no status version" };
  }

  if (!isSupportedEvent(eventType)) {
    return { action: "ignore", reason: `unsupported event ${eventType}` };
  }

  const previousVersion = parseTime(context.previousVersionTime);
  const isStale = eventTime !== null &&
    ((providerVersion !== null && eventTime < providerVersion) ||
      (previousVersion !== null && eventTime < previousVersion));

  if (isStale && !PAYMENT_EVENTS.has(eventType)) {
    return { action: "ignore", reason: "stale event; a newer provider state is already applied" };
  }

  const evidence = paymentEvidence(subscription, expected);
  const paidThrough = keepPaidThrough(subscription, context, now);
  const apply = (
    status: EntitlementStatus,
    periodEnd: string | null,
    reason: string,
  ): EntitlementDecision => ({
    action: "apply",
    status,
    periodEnd,
    versionTime: new Date(versionTime).toISOString(),
    reason,
  });

  switch (eventType) {
    case "PAYMENT.SALE.REFUNDED":
    case "PAYMENT.SALE.REVERSED": {
      // Policy: money returned means access ends now. A partial refund is a
      // commercial decision, so the strict rule is applied and the customer is
      // expected to contact support for a pro-rata arrangement.
      return apply("cancelled", now.toISOString(), "refund or reversal revokes access immediately");
    }
    case "PAYMENT.SALE.COMPLETED": {
      if (input.saleAmount && !amountMatches(input.saleAmount, expected)) {
        return { action: "ignore", reason: "payment amount does not match the Ledgerly Pro price" };
      }
      if (!input.saleAmount) {
        return { action: "ignore", reason: "payment event has no amount to verify" };
      }
      const paymentPeriodEnd = activePeriodEnd(subscription) ??
        (eventTime === null ? null : addOneMonth(new Date(eventTime)).toISOString());
      if (canonical === "active" && paymentPeriodEnd === null) {
        return { action: "ignore", reason: "payment event has no usable paid-through date" };
      }
      return apply(
        canonical === "active" ? "active" : canonical,
        canonical === "active" ? paymentPeriodEnd : paidThrough,
        canonical === "active" ? "verified payment completed" : `payment completed for ${canonical} subscription`,
      );
    }
    case "BILLING.SUBSCRIPTION.PAYMENT.FAILED":
      return apply("past_due", paidThrough, "renewal payment failed");
    case "BILLING.SUBSCRIPTION.EXPIRED":
      return apply("expired", now.toISOString(), "subscription expired");
    case "BILLING.SUBSCRIPTION.SUSPENDED":
      return apply("suspended", paidThrough, "subscription suspended");
    case "BILLING.SUBSCRIPTION.CANCELLED":
      if (canonical === "active") {
        return apply("active", activePeriodEnd(subscription), "cancellation requested but PayPal still reports ACTIVE");
      }
      return apply("cancelled", paidThrough, "subscription cancelled; access continues to the paid-through date");
    case "BILLING.SUBSCRIPTION.ACTIVATED":
    case "BILLING.SUBSCRIPTION.RE-ACTIVATED":
    case "BILLING.SUBSCRIPTION.UPDATED": {
      if (canonical !== "active") {
        return apply(canonical, paidThrough, `canonical status is ${canonical}`);
      }
      if (context.previousStatus === "cancelled" && paidThrough === null) {
        return apply("cancelled", null, "cancelled subscription has no paid-through date");
      }
      if (!evidence.paid && context.previousStatus !== "active") {
        return apply("pending", paidThrough, `awaiting verified payment (${evidence.reason})`);
      }
      return apply("active", activePeriodEnd(subscription), "verified payment on record");
    }
    default:
      return { action: "ignore", reason: `unsupported event ${eventType}` };
  }
}

/**
 * Reconciliation used when the customer returns from PayPal. It applies the
 * same rules as the webhook to PayPal's canonical subscription record, so a
 * delayed or missed webhook cannot leave a paying customer locked out.
 */
export function decideFromCanonicalSubscription(
  subscription: PaypalSubscription,
  context: EntitlementContext,
  now: Date,
  expected: PlanExpectation = LEDGERLY_PRO_PLAN,
): EntitlementDecision {
  const canonical = canonicalStatus(subscription.status);
  const versionTime = parseTime(subscription.status_update_time);
  if (versionTime === null) {
    return { action: "ignore", reason: "PayPal subscription has no status version" };
  }
  const evidence = paymentEvidence(subscription, expected);
  const paidThrough = keepPaidThrough(subscription, context, now);
  const base = {
    action: "apply" as const,
    versionTime: new Date(versionTime).toISOString(),
  };

  if (context.previousVersionTime) {
    const previousVersion = parseTime(context.previousVersionTime);
    if (previousVersion !== null && versionTime < previousVersion) {
      return { action: "ignore", reason: "stored entitlement is newer than PayPal state" };
    }
  }

  switch (canonical) {
    case "active":
      if (!evidence.paid) {
        return { ...base, status: "pending", periodEnd: paidThrough, reason: `awaiting verified payment (${evidence.reason})` };
      }
      return { ...base, status: "active", periodEnd: activePeriodEnd(subscription), reason: "verified payment on record" };
    case "cancelled":
      return { ...base, status: "cancelled", periodEnd: paidThrough, reason: "subscription cancelled" };
    case "expired":
      return { ...base, status: "expired", periodEnd: now.toISOString(), reason: "subscription expired" };
    case "suspended":
      return { ...base, status: "suspended", periodEnd: paidThrough, reason: "subscription suspended" };
    default:
      return { ...base, status: "pending", periodEnd: paidThrough, reason: "subscription is not yet approved" };
  }
}

// ---------------------------------------------------------------------------
// Helpers shared by the entry points
// ---------------------------------------------------------------------------

export interface CheckoutReference {
  userId: string;
  requestId: string | null;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(value: string | null | undefined): boolean {
  return typeof value === "string" && UUID.test(value);
}

/**
 * PayPal echoes the Ledgerly account id back in `custom_id` as
 * `<user uuid>:<checkout request id>`. A bare UUID is accepted for
 * subscriptions created before the request-id was introduced.
 */
export function parseCheckoutReference(customId: string | undefined | null): CheckoutReference | null {
  const raw = (customId ?? "").trim();
  if (!raw) return null;
  const [userId, requestId] = raw.split(":", 2);
  if (!isUuid(userId)) return null;
  return { userId, requestId: isUuid(requestId) ? requestId : null };
}

export function subscriptionMatchesPlan(
  subscription: PaypalSubscription,
  planId: string,
): boolean {
  return Boolean(subscription.plan_id && subscription.plan_id === planId);
}

export function describeEnvironment(environment: PayPalEnv): string {
  return environment === "live" ? "live" : "sandbox";
}
