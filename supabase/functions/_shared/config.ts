// Central configuration for the Ledgerly PayPal integration.
//
// Every value is read from Edge Function secrets. Nothing in this file may be
// imported by Flutter code: it describes server-only configuration.
//
// Design rules:
//  * Fail closed. A missing or contradictory setting is a configuration error,
//    never a silent fallback to another environment.
//  * Never echo secret values. Only setting *names* are ever reported.
//  * The application origin used for CORS must be the same origin PayPal
//    returns the customer to, otherwise checkout works in one place and the
//    browser silently blocks the next request.

export type PayPalEnv = "sandbox" | "live";

export const REQUIRED_CHECKOUT_SETTINGS = [
  "PAYPAL_ENV",
  "PAYPAL_CLIENT_ID",
  "PAYPAL_CLIENT_SECRET",
  "PAYPAL_MONTHLY_PLAN_ID",
  "APP_ALLOWED_ORIGIN",
  "PAYPAL_RETURN_URL",
  "PAYPAL_CANCEL_URL",
] as const;

export const REQUIRED_WEBHOOK_SETTINGS = [
  "PAYPAL_ENV",
  "PAYPAL_CLIENT_ID",
  "PAYPAL_CLIENT_SECRET",
  "PAYPAL_MONTHLY_PLAN_ID",
  "PAYPAL_WEBHOOK_ID",
  "SUPABASE_URL",
  "SUPABASE_SERVICE_ROLE_KEY",
] as const;

export const SUPABASE_SETTINGS = [
  "SUPABASE_URL",
  "SUPABASE_ANON_KEY",
  "SUPABASE_SERVICE_ROLE_KEY",
] as const;

export type EnvReader = (name: string) => string | undefined;

export interface PayPalSettings {
  environment: PayPalEnv;
  apiBase: string;
  clientId: string;
  clientSecret: string;
  planId: string;
  webhookId: string | null;
  allowedOrigin: string;
  returnUrl: string;
  cancelUrl: string;
}

export interface SupabaseSettings {
  url: string;
  anonKey: string;
  serviceRoleKey: string;
}

export interface Settings {
  paypal: PayPalSettings;
  supabase: SupabaseSettings;
}

export interface ConfigFailure {
  ok: false;
  missing: string[];
  invalid: string[];
}

export type ConfigResult<T> = { ok: true; value: T } | ConfigFailure;

/** PayPal's REST hosts for each environment. Anything else is a bug. */
export function paypalApiBase(environment: PayPalEnv): string {
  return environment === "live"
    ? "https://api-m.paypal.com"
    : "https://api-m.sandbox.paypal.com";
}

function readString(env: EnvReader, name: string): string {
  return (env(name) ?? "").trim();
}

/**
 * Parses an absolute HTTPS URL and rejects anything that could not be used
 * verbatim as a PayPal redirect target (credentials, fragments, non-HTTPS).
 */
export function parseHttpsUrl(value: string): URL | null {
  if (!value) return null;
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return null;
  }
  if (url.protocol !== "https:") return null;
  if (!url.hostname || url.hostname.includes(" ")) return null;
  if (url.username || url.password) return null;
  if (url.hash) return null;
  return url;
}

/**
 * Normalises an origin to exactly `scheme://host[:port]`. A single trailing
 * slash is tolerated (it is a common copy/paste artefact and does not change
 * the origin). A configured origin that carries a path, query or fragment is
 * rejected rather than truncated, because truncating it could accidentally
 * widen CORS to a different deployment.
 */
export function normaliseOrigin(value: string): string | null {
  const url = parseHttpsUrl(value);
  if (!url) return null;
  const origin = url.origin;
  if (origin === "null") return null;
  const withoutTrailingSlash = value.endsWith("/") ? value.slice(0, -1) : value;
  if (withoutTrailingSlash !== origin) return null;
  return origin;
}

/** The same origin means identical scheme, host and port. */
export function isSameOrigin(a: string, b: string): boolean {
  const left = parseHttpsUrl(a);
  const right = parseHttpsUrl(b);
  if (!left || !right) return false;
  return left.origin === right.origin;
}

/**
 * The static auth/email-confirmation page must never be used as a checkout
 * landing page: it does not host the Flutter app and cannot complete a PKCE
 * session. Callers validate their own configured URLs through this helper.
 */
export function isConfirmationCallbackPath(url: URL): boolean {
  return /^\/auth-callback(\/|$)/i.test(url.pathname);
}

export function readPayPalSettings(
  env: EnvReader,
  options: { requireWebhookId: boolean },
): ConfigResult<PayPalSettings> {
  const missing: string[] = [];
  const invalid: string[] = [];

  const environment = readString(env, "PAYPAL_ENV").toLowerCase();
  const clientId = readString(env, "PAYPAL_CLIENT_ID");
  const clientSecret = readString(env, "PAYPAL_CLIENT_SECRET");
  const planId = readString(env, "PAYPAL_MONTHLY_PLAN_ID");
  const webhookId = readString(env, "PAYPAL_WEBHOOK_ID");
  const allowedOriginRaw = readString(env, "APP_ALLOWED_ORIGIN");
  const returnUrlRaw = readString(env, "PAYPAL_RETURN_URL");
  const cancelUrlRaw = readString(env, "PAYPAL_CANCEL_URL");

  for (const [name, value] of [
    ["PAYPAL_ENV", environment],
    ["PAYPAL_CLIENT_ID", clientId],
    ["PAYPAL_CLIENT_SECRET", clientSecret],
    ["PAYPAL_MONTHLY_PLAN_ID", planId],
    ["APP_ALLOWED_ORIGIN", allowedOriginRaw],
    ["PAYPAL_RETURN_URL", returnUrlRaw],
    ["PAYPAL_CANCEL_URL", cancelUrlRaw],
  ] as const) {
    if (!value) missing.push(name);
  }
  if (options.requireWebhookId && !webhookId) missing.push("PAYPAL_WEBHOOK_ID");

  if (environment && environment !== "sandbox" && environment !== "live") {
    invalid.push("PAYPAL_ENV must be exactly 'sandbox' or 'live'");
  }

  const allowedOrigin = allowedOriginRaw ? normaliseOrigin(allowedOriginRaw) : null;
  if (allowedOriginRaw && !allowedOrigin) {
    invalid.push("APP_ALLOWED_ORIGIN must be an exact https origin with no path, query or trailing slash");
  }

  const returnUrl = returnUrlRaw ? parseHttpsUrl(returnUrlRaw) : null;
  if (returnUrlRaw && !returnUrl) {
    invalid.push("PAYPAL_RETURN_URL must be an absolute https URL");
  }
  const cancelUrl = cancelUrlRaw ? parseHttpsUrl(cancelUrlRaw) : null;
  if (cancelUrlRaw && !cancelUrl) {
    invalid.push("PAYPAL_CANCEL_URL must be an absolute https URL");
  }

  if (allowedOrigin && returnUrl && returnUrl.origin !== allowedOrigin) {
    invalid.push("PAYPAL_RETURN_URL must use the same origin as APP_ALLOWED_ORIGIN");
  }
  if (allowedOrigin && cancelUrl && cancelUrl.origin !== allowedOrigin) {
    invalid.push("PAYPAL_CANCEL_URL must use the same origin as APP_ALLOWED_ORIGIN");
  }
  if (returnUrl && isConfirmationCallbackPath(returnUrl)) {
    invalid.push("PAYPAL_RETURN_URL must not be the email-confirmation callback page");
  }
  if (cancelUrl && isConfirmationCallbackPath(cancelUrl)) {
    invalid.push("PAYPAL_CANCEL_URL must not be the email-confirmation callback page");
  }

  if (missing.length || invalid.length) return { ok: false, missing, invalid };

  return {
    ok: true,
    value: {
      environment: environment as PayPalEnv,
      apiBase: paypalApiBase(environment as PayPalEnv),
      clientId,
      clientSecret,
      planId,
      webhookId: webhookId || null,
      allowedOrigin: allowedOrigin as string,
      returnUrl: (returnUrl as URL).toString(),
      cancelUrl: (cancelUrl as URL).toString(),
    },
  };
}

export function readSupabaseSettings(
  env: EnvReader,
  options: { requireAnonKey: boolean },
): ConfigResult<SupabaseSettings> {
  const missing: string[] = [];
  const invalid: string[] = [];
  const url = readString(env, "SUPABASE_URL");
  const anonKey = readString(env, "SUPABASE_ANON_KEY");
  const serviceRoleKey = readString(env, "SUPABASE_SERVICE_ROLE_KEY");

  if (!url) missing.push("SUPABASE_URL");
  if (!serviceRoleKey) missing.push("SUPABASE_SERVICE_ROLE_KEY");
  if (options.requireAnonKey && !anonKey) missing.push("SUPABASE_ANON_KEY");

  // Guard against pasting the service-role key into the anon slot (or worse,
  // into the Flutter build): the publishable key is never a secret key.
  if (anonKey && anonKey.startsWith("sb_secret_")) {
    invalid.push("SUPABASE_ANON_KEY must be a publishable key, not a secret key");
  }

  if (missing.length || invalid.length) return { ok: false, missing, invalid };

  return {
    ok: true,
    value: {
      url,
      anonKey,
      serviceRoleKey,
    },
  };
}

/** Combines two config results so a single response reports every problem. */
export function mergeFailures(failures: ConfigFailure[]): ConfigFailure {
  return {
    ok: false,
    missing: [...new Set(failures.flatMap((failure) => failure.missing))],
    invalid: [...new Set(failures.flatMap((failure) => failure.invalid))],
  };
}

export function isConfigFailure(
  result: ConfigResult<unknown>,
): result is ConfigFailure {
  return result.ok === false;
}
