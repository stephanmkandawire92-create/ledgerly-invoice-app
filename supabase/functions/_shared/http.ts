// Shared HTTP helpers for the Ledgerly billing Edge Functions.
//
// CORS policy: authenticated checkout must never answer with a wildcard. The
// browser is only told the request is allowed when the request's Origin is
// byte-for-byte the configured application origin. Requests from any other
// origin get an explicit 403 without CORS headers, so a hostile page cannot
// read the response.

export const ALLOWED_REQUEST_HEADERS =
  "authorization, x-client-info, apikey, content-type";

export interface OriginDecision {
  allowed: boolean;
  headers: Record<string, string>;
}

/**
 * Computes the CORS response headers for a request.
 *
 * A missing Origin (native Windows/mobile clients, server-to-server calls) is
 * not a CORS request and is allowed to proceed without CORS headers.
 */
export function resolveOrigin(
  requestOrigin: string | null,
  allowedOrigin: string | null,
): OriginDecision {
  const headers: Record<string, string> = { Vary: "Origin" };
  if (!allowedOrigin) return { allowed: requestOrigin === null, headers };
  if (!requestOrigin) return { allowed: true, headers };
  if (requestOrigin !== allowedOrigin) return { allowed: false, headers };
  return {
    allowed: true,
    headers: {
      ...headers,
      "Access-Control-Allow-Origin": allowedOrigin,
      "Access-Control-Allow-Headers": ALLOWED_REQUEST_HEADERS,
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Max-Age": "600",
    },
  };
}

export function jsonResponse(
  body: unknown,
  status: number,
  headers: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...headers,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

export function preflightResponse(
  requestOrigin: string | null,
  allowedOrigin: string | null,
): Response {
  const decision = resolveOrigin(requestOrigin, allowedOrigin);
  if (!decision.allowed) {
    // No Access-Control-Allow-Origin: the browser blocks the real request.
    return new Response(null, { status: 403, headers: decision.headers });
  }
  return new Response(null, { status: 204, headers: decision.headers });
}

/**
 * Rejects a cross-origin browser request before any work is done.
 * Returns null when the request may continue.
 */
export function rejectDisallowedOrigin(
  requestOrigin: string | null,
  allowedOrigin: string | null,
): Response | null {
  const decision = resolveOrigin(requestOrigin, allowedOrigin);
  if (decision.allowed) return null;
  return jsonResponse(
    { error: publicErrors.originNotAllowed.message, code: publicErrors.originNotAllowed.code },
    403,
    decision.headers,
  );
}

/**
 * A stable, non-sensitive error code plus a customer-safe message. Internal
 * detail stays in the function log; the browser only receives this.
 */
export interface PublicError {
  code: string;
  message: string;
  status: number;
}

export const publicErrors = {
  methodNotAllowed: {
    code: "method_not_allowed",
    message: "This action is not supported.",
    status: 405,
  },
  originNotAllowed: {
    code: "origin_not_allowed",
    message: "This application origin is not authorised for checkout.",
    status: 403,
  },
  notConfigured: {
    code: "billing_not_configured",
    message: "Subscription checkout is temporarily unavailable. Please try again later.",
    status: 503,
  },
  signInRequired: {
    code: "sign_in_required",
    message: "Sign in to your Ledgerly account before subscribing.",
    status: 401,
  },
  sessionExpired: {
    code: "session_expired",
    message: "Your session has expired. Please sign in again.",
    status: 401,
  },
  alreadyEntitled: {
    code: "already_subscribed",
    message: "Your account already has an active Ledgerly Pro subscription.",
    status: 409,
  },
  paymentIssue: {
    code: "payment_issue",
    message:
      "Your Ledgerly Pro subscription has an unresolved payment problem. Update your payment method in PayPal, then refresh your subscription status here.",
    status: 409,
  },
  planMismatch: {
    code: "plan_misconfigured",
    message: "Subscription checkout is temporarily unavailable. Please try again later.",
    status: 503,
  },
  providerUnavailable: {
    code: "provider_unavailable",
    message: "PayPal is temporarily unavailable. Please try again in a moment.",
    status: 502,
  },
  checkoutFailed: {
    code: "checkout_failed",
    message: "PayPal could not start this subscription. No payment was taken.",
    status: 502,
  },
  internal: {
    code: "internal_error",
    message: "Something went wrong. No payment was taken. Please try again.",
    status: 500,
  },
} as const satisfies Record<string, PublicError>;

export type PublicErrorName = keyof typeof publicErrors;
