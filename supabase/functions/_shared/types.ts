// Dependency-free interfaces shared by the billing handlers and their tests.
// Keeping these free of imports means handlers can be tested without loading
// supabase-js or touching the network.

export interface Reservation {
  disposition: string;
  requestId: string | null;
  approvalUrl: string | null;
  subscriptionId: string | null;
}

export interface EntitlementSnapshot {
  userId: string;
  status: string;
  currentPeriodEnd: string | null;
  providerStatusUpdatedAt: string | null;
  updatedAt: string;
  subscriptionId: string;
}

export interface CheckoutAttemptSnapshot {
  userId: string;
  requestId: string;
  subscriptionId: string | null;
  approvalUrl: string | null;
  status: string;
  updatedAt: string;
}

export interface ApplyEntitlementArgs {
  userId: string;
  subscriptionId: string;
  productId: string;
  status: string;
  periodEnd: string | null;
  eventId: string;
  statusUpdatedAt: string;
}

export interface CheckoutStore {
  claimCheckout(
    userId: string,
    requestId: string,
  ): Promise<{ ok: true; reservation: Reservation } | { ok: false; error: string }>;
  releaseRejectedCheckout(requestId: string): Promise<void>;
  saveApproval(args: {
    requestId: string;
    subscriptionId: string;
    approvalUrl: string;
  }): Promise<{ ok: true; updated: boolean } | { ok: false; error: string }>;
  readAttempt(requestId: string): Promise<CheckoutAttemptSnapshot | null>;
}

export interface WebhookStore {
  hasEvent(eventId: string): Promise<boolean>;
  recordEvent(eventId: string): Promise<{ ok: boolean; error?: string }>;
  getEntitlement(subscriptionId: string): Promise<EntitlementSnapshot | null>;
  getCheckoutOwner(requestId: string): Promise<{ userId: string } | null>;
  applyEntitlement(
    args: ApplyEntitlementArgs,
  ): Promise<{ ok: true; applied: boolean } | { ok: false; error: string }>;
  updateCheckout(args: {
    requestId: string;
    userId: string;
    subscriptionId: string;
    status: string;
  }): Promise<{ ok: boolean; error?: string }>;
}

export interface SyncStore {
  getEntitlement(userId: string): Promise<EntitlementSnapshot | null>;
  getLatestAttempt(userId: string): Promise<CheckoutAttemptSnapshot | null>;
  applyEntitlement(
    args: ApplyEntitlementArgs,
  ): Promise<{ ok: boolean; error?: string }>;
}
