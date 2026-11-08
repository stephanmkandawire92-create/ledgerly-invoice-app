import { assertEquals, assert } from "jsr:@std/assert@1";
import {
  isConfirmationCallbackPath,
  mergeFailures,
  normaliseOrigin,
  parseHttpsUrl,
  readPayPalSettings,
  readSupabaseSettings,
} from "../_shared/config.ts";
import { preflightResponse, rejectDisallowedOrigin, resolveOrigin } from "../_shared/http.ts";
import { APP_ORIGIN, env } from "./support.ts";

Deno.test("returns the full settings when every value is present and consistent", () => {
  const result = readPayPalSettings(env(), { requireWebhookId: true });
  assert(result.ok);
  assertEquals(result.value.environment, "sandbox");
  assertEquals(result.value.apiBase, "https://api-m.sandbox.paypal.com");
  assertEquals(result.value.allowedOrigin, APP_ORIGIN);
  assertEquals(result.value.returnUrl, `${APP_ORIGIN}/billing/paypal/return`);
});

Deno.test("live environment uses the live PayPal host", () => {
  const result = readPayPalSettings(env({ PAYPAL_ENV: "live" }), { requireWebhookId: true });
  assert(result.ok);
  assertEquals(result.value.apiBase, "https://api-m.paypal.com");
});

Deno.test("an unknown PAYPAL_ENV is rejected instead of defaulting to sandbox", () => {
  const result = readPayPalSettings(env({ PAYPAL_ENV: "production" }), { requireWebhookId: true });
  assert(!result.ok);
  assert(result.invalid.some((entry) => entry.includes("PAYPAL_ENV")));
});

Deno.test("missing settings are reported by name only", () => {
  const result = readPayPalSettings(
    env({ PAYPAL_CLIENT_SECRET: undefined, PAYPAL_WEBHOOK_ID: undefined }),
    { requireWebhookId: true },
  );
  assert(!result.ok);
  assertEquals(result.missing.sort(), ["PAYPAL_CLIENT_SECRET", "PAYPAL_WEBHOOK_ID"]);
});

Deno.test("the webhook id is optional for checkout but required for the webhook", () => {
  const reader = env({ PAYPAL_WEBHOOK_ID: undefined });
  assert(readPayPalSettings(reader, { requireWebhookId: false }).ok);
  assert(!readPayPalSettings(reader, { requireWebhookId: true }).ok);
});

Deno.test("an origin is normalised, but a path or non-HTTPS origin is rejected", () => {
  assertEquals(normaliseOrigin("https://app.example.com/"), "https://app.example.com");
  assertEquals(normaliseOrigin("https://app.example.com/path"), null);
  assertEquals(normaliseOrigin("https://app.example.com?x=1"), null);
  assertEquals(normaliseOrigin("https://app.example.com"), "https://app.example.com");
  assertEquals(normaliseOrigin("http://app.example.com"), null);
});

Deno.test("return and cancel URLs must share the CORS origin", () => {
  const result = readPayPalSettings(
    env({ PAYPAL_RETURN_URL: "https://other.example.com/return" }),
    { requireWebhookId: false },
  );
  assert(!result.ok);
  assert(result.invalid.some((entry) => entry.includes("PAYPAL_RETURN_URL")));
});

Deno.test("the email confirmation callback page is rejected as a checkout target", () => {
  const result = readPayPalSettings(
    env({ PAYPAL_RETURN_URL: `${APP_ORIGIN}/auth-callback/` }),
    { requireWebhookId: false },
  );
  assert(!result.ok);
  assert(result.invalid.some((entry) => entry.includes("email-confirmation")));
});

Deno.test("URL parsing rejects credentials, fragments and non-HTTPS schemes", () => {
  assertEquals(parseHttpsUrl("https://user:pass@example.com/"), null);
  assertEquals(parseHttpsUrl("https://example.com/#frag"), null);
  assertEquals(parseHttpsUrl("http://example.com/"), null);
  assert(parseHttpsUrl("https://example.com/return?state=1"));
});

Deno.test("confirmation callback detection", () => {
  assert(isConfirmationCallbackPath(new URL(`${APP_ORIGIN}/auth-callback`)));
  assert(isConfirmationCallbackPath(new URL(`${APP_ORIGIN}/auth-callback/index.html`)));
  assert(!isConfirmationCallbackPath(new URL(`${APP_ORIGIN}/auth-callback-page`)));
});

Deno.test("a secret key in the publishable slot is a configuration error", () => {
  const result = readSupabaseSettings(env({ SUPABASE_ANON_KEY: "sb_secret_abc" }), {
    requireAnonKey: true,
  });
  assert(!result.ok);
  assert(result.invalid.length > 0);
});

Deno.test("mergeFailures deduplicates names across sources", () => {
  const merged = mergeFailures([
    { ok: false, missing: ["A", "B"], invalid: [] },
    { ok: false, missing: ["B", "C"], invalid: ["X"] },
  ]);
  assertEquals(merged.missing, ["A", "B", "C"]);
  assertEquals(merged.invalid, ["X"]);
});

Deno.test("CORS: exact origin is echoed, wildcard is never used", () => {
  const exact = resolveOrigin(APP_ORIGIN, APP_ORIGIN);
  assert(exact.allowed);
  assertEquals(exact.headers["Access-Control-Allow-Origin"], APP_ORIGIN);
  assertEquals(exact.headers["Access-Control-Allow-Methods"], "POST, OPTIONS");

  const other = resolveOrigin("https://evil.example.com", APP_ORIGIN);
  assert(!other.allowed);
  assert(!("Access-Control-Allow-Origin" in other.headers));
});

Deno.test("CORS: unconfigured origin never emits the literal 'null'", () => {
  const decision = resolveOrigin(APP_ORIGIN, null);
  assert(!decision.allowed);
  assert(!("Access-Control-Allow-Origin" in decision.headers));
});

Deno.test("CORS: native clients without an Origin header are not blocked", () => {
  assert(resolveOrigin(null, APP_ORIGIN).allowed);
});

Deno.test("preflight from the allowed origin returns 204 with exact headers", async () => {
  const response = preflightResponse(APP_ORIGIN, APP_ORIGIN);
  assertEquals(response.status, 204);
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), APP_ORIGIN);
  assertEquals(
    response.headers.get("Access-Control-Allow-Headers"),
    "authorization, x-client-info, apikey, content-type",
  );
  await response.body?.cancel();
});

Deno.test("preflight from another origin is refused without CORS headers", async () => {
  const response = preflightResponse("https://evil.example.com", APP_ORIGIN);
  assertEquals(response.status, 403);
  assertEquals(response.headers.get("Access-Control-Allow-Origin"), null);
  await response.body?.cancel();
});

Deno.test("rejectDisallowedOrigin produces a 403 JSON error", async () => {
  const response = rejectDisallowedOrigin("https://evil.example.com", APP_ORIGIN);
  assert(response);
  assertEquals(response!.status, 403);
  const body = await response!.json();
  assertEquals(body.code, "origin_not_allowed");
});
