// Test doubles for the billing handlers. No network, no database.

import type { EnvReader, SupabaseSettings } from "../_shared/config.ts";
import type {
  ApplyEntitlementArgs,
  CheckoutAttemptSnapshot,
  CheckoutStore,
  EntitlementSnapshot,
  Reservation,
  SyncStore,
  WebhookStore,
} from "../_shared/types.ts";

export const APP_ORIGIN = "https://app.ledgerly.test";
export const PLAN_ID = "P-LEDGERLY-PRO";
export const SUBSCRIPTION_ID = "I-BW452GLLEP1G";
export const USER_ID = "9f1d4a3e-6c2b-4f8a-9d1e-2b3c4d5e6f70";

export const baseEnv: Record<string, string> = {
  PAYPAL_ENV: "sandbox",
  PAYPAL_CLIENT_ID: "client-id",
  PAYPAL_CLIENT_SECRET: "client-secret",
  PAYPAL_MONTHLY_PLAN_ID: PLAN_ID,
  PAYPAL_WEBHOOK_ID: "WH-TEST-1",
  APP_ALLOWED_ORIGIN: APP_ORIGIN,
  PAYPAL_RETURN_URL: `${APP_ORIGIN}/billing/paypal/return`,
  PAYPAL_CANCEL_URL: `${APP_ORIGIN}/billing/paypal/cancel`,
  SUPABASE_URL: "https://project.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_test",
  SUPABASE_SERVICE_ROLE_KEY: "service-role-key",
};

export function env(overrides: Record<string, string | undefined> = {}): EnvReader {
  const values = { ...baseEnv, ...overrides };
  return (name: string) => {
    const value = values[name];
    return value === undefined ? undefined : value;
  };
}

export const supabaseSettings: SupabaseSettings = {
  url: "https://project.supabase.co",
  anonKey: "sb_publishable_test",
  serviceRoleKey: "service-role-key",
};

export const ACTIVE_PLAN = {
  id: PLAN_ID,
  status: "ACTIVE",
  billing_cycles: [
    {
      tenure_type: "REGULAR",
      sequence: 1,
      frequency: { interval_unit: "MONTH", interval_count: 1 },
      pricing_scheme: { fixed_price: { currency_code: "USD", value: "3.00" } },
    },
  ],
};

export interface RecordedCall {
  method: string;
  url: string;
  body: unknown;
}

export interface FakePayPalOptions {
  plan?: unknown;
  planStatus?: number;
  subscription?: unknown;
  subscriptionStatus?: number;
  created?: unknown;
  createdStatus?: number;
  verification?: { verification_status?: string };
  verificationStatus?: number;
  tokenStatus?: number;
}

export interface FakePayPal {
  fetch: typeof fetch;
  calls: RecordedCall[];
  count(method: string, fragment: string): number;
}

/** A scripted PayPal transport keyed by method + URL path. */
export function fakePayPal(options: FakePayPalOptions = {}): FakePayPal {
  const calls: RecordedCall[] = [];
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json" },
    });

  const transport = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    const method = (init?.method ?? "GET").toUpperCase();
    let body: unknown = init?.body;
    if (typeof body === "string") {
      try {
        body = JSON.parse(body);
      } catch {
        // form-encoded body stays a string
      }
    }
    calls.push({ method, url, body });

    const path = new URL(url).pathname;
    if (path === "/v1/oauth2/token") {
      return options.tokenStatus && options.tokenStatus >= 400
        ? json({ error: "invalid_client" }, options.tokenStatus)
        : json({ access_token: "test-token" });
    }
    if (path.startsWith("/v1/billing/plans/")) {
      return json(options.plan ?? ACTIVE_PLAN, options.planStatus ?? 200);
    }
    if (path === "/v1/billing/subscriptions" && method === "POST") {
      return json(
        options.created ?? {
          id: SUBSCRIPTION_ID,
          status: "APPROVAL_PENDING",
          links: [
            { rel: "approve", href: `https://www.sandbox.paypal.com/checkoutnow?token=${SUBSCRIPTION_ID}` },
          ],
        },
        options.createdStatus ?? 201,
      );
    }
    if (path.startsWith("/v1/billing/subscriptions/")) {
      return json(options.subscription ?? {}, options.subscriptionStatus ?? 200);
    }
    if (path === "/v1/notifications/verify-webhook-signature") {
      return json(
        options.verification ?? { verification_status: "SUCCESS" },
        options.verificationStatus ?? 200,
      );
    }
    return json({ error: "unexpected call", path }, 500);
  };

  return {
    fetch: transport as unknown as typeof fetch,
    calls,
    count(method, fragment) {
      return calls.filter((call) => call.method === method && call.url.includes(fragment)).length;
    },
  };
}

// ---------------------------------------------------------------------------
// Store doubles
// ---------------------------------------------------------------------------

export class FakeCheckoutStore implements CheckoutStore {
  reservations: Reservation[] = [];
  released: string[] = [];
  saved: Array<{ requestId: string; subscriptionId: string; approvalUrl: string }> = [];
  attempts = new Map<string, CheckoutAttemptSnapshot>();
  existing: Reservation | null = null;
  claimError: string | null = null;
  saveError: string | null = null;
  saveUpdated = true;

  async claimCheckout(_userId: string, requestId: string) {
    if (this.claimError) return { ok: false as const, error: this.claimError };
    if (this.existing) {
      this.reservations.push(this.existing);
      return { ok: true as const, reservation: this.existing };
    }
    const reservation: Reservation = {
      disposition: "claimed",
      requestId,
      approvalUrl: null,
      subscriptionId: null,
    };
    this.reservations.push(reservation);
    return { ok: true as const, reservation };
  }

  async releaseRejectedCheckout(requestId: string) {
    this.released.push(requestId);
  }

  async saveApproval(args: { requestId: string; subscriptionId: string; approvalUrl: string }) {
    if (this.saveError) return { ok: false as const, error: this.saveError };
    this.saved.push(args);
    return { ok: true as const, updated: this.saveUpdated };
  }

  async readAttempt(requestId: string) {
    return this.attempts.get(requestId) ?? null;
  }
}

export class FakeWebhookStore implements WebhookStore {
  events = new Set<string>();
  recorded: string[] = [];
  entitlement: EntitlementSnapshot | null = null;
  checkoutOwner: { userId: string } | null = null;
  applied: ApplyEntitlementArgs[] = [];
  applyResult: { ok: true; applied: boolean } | { ok: false; error: string } = { ok: true, applied: true };
  recordFails = false;
  checkoutUpdates: Array<{ requestId: string; status: string }> = [];

  async hasEvent(eventId: string) {
    return this.events.has(eventId);
  }
  async recordEvent(eventId: string) {
    if (this.recordFails) return { ok: false, error: "insert failed" };
    this.events.add(eventId);
    this.recorded.push(eventId);
    return { ok: true };
  }
  async getEntitlement() {
    return this.entitlement;
  }
  async getCheckoutOwner() {
    return this.checkoutOwner;
  }
  async applyEntitlement(args: ApplyEntitlementArgs) {
    if (!this.applyResult.ok) return this.applyResult;
    this.applied.push(args);
    this.entitlement = {
      userId: args.userId,
      status: args.status,
      currentPeriodEnd: args.periodEnd,
      providerStatusUpdatedAt: args.statusUpdatedAt,
      updatedAt: args.statusUpdatedAt,
      subscriptionId: args.subscriptionId,
    };
    return this.applyResult;
  }
  async updateCheckout(args: { requestId: string; userId: string; subscriptionId: string; status: string }) {
    this.checkoutUpdates.push({ requestId: args.requestId, status: args.status });
    return { ok: true };
  }
}

export class FakeSyncStore implements SyncStore {
  entitlement: EntitlementSnapshot | null = null;
  attempt: CheckoutAttemptSnapshot | null = null;
  applied: ApplyEntitlementArgs[] = [];
  applyError: string | null = null;

  async getEntitlement() {
    return this.entitlement;
  }
  async getLatestAttempt() {
    return this.attempt;
  }
  async applyEntitlement(args: ApplyEntitlementArgs) {
    if (this.applyError) return { ok: false, error: this.applyError };
    this.applied.push(args);
    this.entitlement = {
      userId: args.userId,
      status: args.status,
      currentPeriodEnd: args.periodEnd,
      providerStatusUpdatedAt: args.statusUpdatedAt,
      updatedAt: args.statusUpdatedAt,
      subscriptionId: args.subscriptionId,
    };
    return { ok: true };
  }
}

export function jsonRequest(
  url: string,
  init: { method?: string; origin?: string | null; body?: unknown; authorization?: string | null; headers?: Record<string, string> } = {},
): Request {
  const headers = new Headers(init.headers ?? {});
  if (init.origin !== null) headers.set("Origin", init.origin ?? APP_ORIGIN);
  if (init.authorization !== null) headers.set("Authorization", init.authorization ?? "Bearer user-jwt");
  if (init.body !== undefined) headers.set("Content-Type", "application/json");
  return new Request(url, {
    method: init.method ?? "POST",
    headers,
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
}

export function signatureHeaders(): Record<string, string> {
  return {
    "paypal-auth-algo": "SHA256withRSA",
    "paypal-cert-url": "https://api.sandbox.paypal.com/cert.pem",
    "paypal-transmission-id": "transmission-1",
    "paypal-transmission-sig": "signature",
    "paypal-transmission-time": "2026-11-08T10:00:00Z",
  };
}

export const FIXED_NOW = new Date("2026-11-08T12:00:00.000Z");

export function activeSubscription(overrides: Record<string, unknown> = {}) {
  return {
    id: SUBSCRIPTION_ID,
    plan_id: PLAN_ID,
    status: "ACTIVE",
    status_update_time: "2026-11-08T11:55:00.000Z",
    custom_id: `${USER_ID}:8f14e45f-ceea-467f-a3bd-1a2b3c4d5e6f`,
    billing_info: {
      next_billing_time: "2026-12-08T11:55:00.000Z",
      last_payment: {
        amount: { currency_code: "USD", value: "3.00" },
        time: "2026-11-08T11:54:30.000Z",
      },
    },
    ...overrides,
  };
}
