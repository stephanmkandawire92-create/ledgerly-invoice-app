# Ledgerly PayPal subscription integration — repair report

Date: 2026-11-08
Scope: `stephanmkandawire92-create/ledgerly-invoice-app` (branch `main`, working
tree clean at `7f3b5f5`), Supabase project `gcrzwkzithihyhyftfgn`, Vercel
project `ledgerly-invoice-app`.

**Nothing was committed, pushed, deployed or written to the production
database.** All changes are local working-tree edits: backend code, a migration
file, app code, tests, tooling and documentation. The production project still
runs the previous Edge Function versions.

---

## 1. Root causes

### RC-1 — The webhook cannot start: required settings are absent

Evidence (live, unauthenticated probe):

```
POST https://gcrzwkzithihyhyftfgn.supabase.co/functions/v1/paypal-webhook
-> 503 {"error":"Webhook not configured"}
```

`paypal-webhook` returns that response only when one of
`PAYPAL_WEBHOOK_ID`, `PAYPAL_CLIENT_ID`, `PAYPAL_CLIENT_SECRET`,
`PAYPAL_MONTHLY_PLAN_ID`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` is empty.
The platform injects the Supabase values, so the PayPal-side settings are
missing. The old handler never said *which* name was absent, which is why this
looked mysterious.

### RC-2 — Checkout CORS was configured with the literal string `null`

Evidence (live preflight):

```
OPTIONS .../paypal-create-subscription
-> 200, access-control-allow-origin: null
```

`APP_ALLOWED_ORIGIN` is unset, so `Deno.env.get(...) ?? "null"` emitted `null`
as an origin. Every browser call from the real app is therefore blocked, and a
configured deployment would have had no usable CORS origin.

### RC-3 — There is no public application URL to return to

| URL | Result |
|---|---|
| `https://ledgerly-invoice-4ch9n31ve-steve30.vercel.app/` | `302` → `https://vercel.com/sso-api?...` (Vercel team authentication) |
| `https://ledgerly-invoice-mcfuakwkk-steve30.vercel.app` (current production deployment) | `302` → Vercel SSO |
| `https://ledgerly-invoice-app-steve30.vercel.app` | `302` → Vercel SSO |
| `https://ledgerly-invoice-app-git-main-steve30.vercel.app` | `302` → Vercel SSO |
| `https://ledgerly-invoice-app.vercel.app` | `200`, but serves **only** the static email-confirmation page (`/auth-callback`), not the Flutter app |

Vercel project settings confirm the cause: `ssoProtection.enabled = true`,
`deploymentType = all_except_custom_domains`, `live = false`. The only
unprotected host is the confirmation page, which the brief explicitly forbids
using as the app origin.

The Flutter web build itself is fine: PR #8 (`fix/vercel-flutter-web`,
`vercel.json` + `scripts/vercel-build.sh`) produces a correct bundle —
`https://ledgerly-invoice-4ch9n31ve-steve30.vercel.app/` returns the real
`flutter_bootstrap.js` app HTML when fetched through an authorised channel. The
blocker is deployment protection and promotion to production, not the build.

### RC-4 — Return and cancel URLs were the application root

`paypal-create-subscription` used one variable, `APP_SITE_URL`, for both
`return_url` and `cancel_url`. A bare root cannot distinguish "payment
approved" from "checkout cancelled", so the app could not show the right
message, and the documented settings (`APP_ALLOWED_ORIGIN`,
`PAYPAL_RETURN_URL`, `PAYPAL_CANCEL_URL`) were never read.

### RC-5 — An entitlement could be rebound to another account

`apply_paypal_entitlement` had:

```sql
on conflict (provider, external_subscription_id) do update set
  user_id = excluded.user_id, ...
```

Any caller able to reach the RPC with an existing subscription id could move the
entitlement to a different Ledgerly account. The function is service-role only,
but an account-takeover primitive does not belong in a payment ledger.

### RC-6 — A failed renewal could be charged twice

`claim_paypal_checkout` treated only `active` and paid-through `cancelled`
subscriptions as blocking. A customer in `past_due` or `suspended` could start a
second PayPal subscription while the first was still collectable.

### RC-7 — A missed webhook locked a paying customer out permanently

Entitlements were written only by the webhook. There was no reconciliation path,
so a delayed or failed delivery meant the customer paid and stayed on Free with
no way to recover except waiting.

### RC-8 — Activation was not tied to a payment

Activation required `previous.status = 'active'`, so if `PAYMENT.SALE.COMPLETED`
arrived before `BILLING.SUBSCRIPTION.ACTIVATED` the account could stay `pending`
indefinitely. Conversely, event amounts were never checked against USD 3.00, and
`BILLING.SUBSCRIPTION.RE-ACTIVATED` was not handled at all.

### RC-9 — The app could present misleading results

`PaywallScreen._run` wrote "Request completed. Ledgerly Pro appears after the
subscription is verified." after any successful call, including a refresh that
found nothing. Errors were surfaced with `error.toString()`, exposing internal
exception text. There was no pending/cancelled state and no server-side status
check after returning from PayPal.

---

## 2. Files inspected

Repository:

```
.git state, branch history, PR #3/#4/#8
lib/main.dart
lib/services/subscription_service.dart
lib/screens/paywall_screen.dart
lib/screens/paypal_config_screen.dart
lib/screens/home_screen.dart (subscription gates)
lib/screens/analytics_screen.dart, business_profile_screen.dart (isPro usage)
supabase/functions/paypal-create-subscription/index.ts
supabase/functions/paypal-webhook/index.ts
supabase/functions/revenuecat-webhook/index.ts
supabase/subscription-schema.sql
supabase/config.toml
supabase/README.md, supabase/auth-email-setup.md
.github/workflows/flutter-ci.yml
web/index.html, auth-callback/index.html
pubspec.yaml, analysis_options.yaml
test/*.dart
```

Infrastructure (read-only):

* Supabase: `list_projects`, `list_edge_functions`, `get_edge_function`
  (byte-identical to the repository for both PayPal functions), `list_tables`,
  `list_migrations`, `query_logs` (log analytics not enabled on this plan).
* Vercel: `list_projects`, `get_project`, `list_deployments`,
  `list_project_domains`, `filter_project_envs` (no env vars set),
  `web_fetch_vercel_url`.
* Live HTTP probes of every candidate origin, plus `OPTIONS`/`POST` against the
  deployed functions.

`supabase/configure-paypal-live.ps1` did **not** exist in the repository on any
branch, so it was created rather than modified.

---

## 3. Files modified

Backend (new):

```
supabase/functions/_shared/config.ts
supabase/functions/_shared/http.ts
supabase/functions/_shared/paypal.ts
supabase/functions/_shared/types.ts
supabase/functions/_shared/store.ts
supabase/functions/_shared/checkout_handler.ts
supabase/functions/_shared/webhook_handler.ts
supabase/functions/_shared/sync_handler.ts
supabase/functions/paypal-sync-subscription/index.ts
supabase/migrations/20261108120000_paypal_entitlement_hardening.sql
supabase/configure-paypal-live.ps1
supabase/tests/run_sql_tests.sh
supabase/tests/sql/00_supabase_shim.sql
supabase/tests/sql/10_entitlement_test.sql
supabase/functions/tests/support.ts
supabase/functions/tests/config_test.ts
supabase/functions/tests/paypal_test.ts
supabase/functions/tests/handlers_test.ts
```

Backend (rewritten in place, same public URL and same config keys):

```
supabase/functions/paypal-create-subscription/index.ts
supabase/functions/paypal-webhook/index.ts
supabase/config.toml
supabase/README.md
```

App:

```
lib/services/subscription_service.dart      (rewritten)
lib/services/entitlement_evaluator.dart     (new)
lib/screens/paywall_screen.dart             (targeted edits, UI preserved)
test/subscription_service_test.dart         (extended)
test/entitlement_evaluator_test.dart        (new)
test/paywall_screen_test.dart               (new)
```

Documentation: this file.

`paypal_config_screen.dart`, the RevenueCat function, the schema's table
definitions, the paywall's visual design and all unrelated features were left
untouched.

---

## 4. What changed

### 4.1 Configuration (`_shared/config.ts`)

* `PAYPAL_ENV` must be exactly `sandbox` or `live`; a typo is an error, never a
  silent fallback.
* `APP_ALLOWED_ORIGIN` must be a bare HTTPS origin. A trailing slash is
  normalised; a path, query or fragment is rejected.
* `PAYPAL_RETURN_URL` and `PAYPAL_CANCEL_URL` are required, must be absolute
  HTTPS, must share the CORS origin, and may not be the `/auth-callback` page.
* Failures report setting **names** only, for logging and the setup script.

### 4.2 CORS (`_shared/http.ts`)

* Exact origin echoed only on a byte-for-byte match; never `*`, never `null`.
* `OPTIONS` returns `204` with the exact origin, or `403` with no CORS headers.
* `Vary: Origin` on every response; `Cache-Control: no-store`.
* A missing configuration returns `503` before any origin decision, so the
  failure is diagnosable instead of looking like a CORS problem.
* Stable machine codes (`billing_not_configured`, `sign_in_required`,
  `already_subscribed`, `payment_issue`, `provider_unavailable`, …) with
  customer-safe copy.

### 4.3 Checkout (`paypal-create-subscription`)

* Plan verified against PayPal on every checkout: `ACTIVE`, `USD`, `3.00`,
  `every 1 MONTH`.
* Explicit `return_url` / `cancel_url`, `shipping_preference: NO_SHIPPING`,
  `custom_id = "<user uuid>:<request id>"`, `PayPal-Request-Id` idempotency.
* Still never writes an entitlement; approval is not payment.

### 4.4 Webhook (`paypal-webhook`)

* Reads the raw body, verifies the signature with PayPal before parsing any
  claim, and rejects non-`SUCCESS` verification with `401`.
* Always derives state from `GET /v1/billing/subscriptions/{id}`.
* Requires the Ledgerly plan and a valid account UUID in `custom_id`; a
  mismatched checkout reservation or an already-bound subscription is refused
  (`account_mismatch`), never reassigned.
* Handles `PAYMENT.SALE.COMPLETED` amounts (must equal USD 3.00), refunds and
  reversals (immediate revocation), `RE-ACTIVATED`, expiry, suspension and
  failed payments.
* Idempotent: duplicates acknowledged, event ids unique, version-guarded writes,
  and the event is recorded only after the entitlement write succeeds so PayPal's
  retry can recover a failure.

### 4.5 Reconciliation (`paypal-sync-subscription`, new)

* Authenticated; takes the subscription id from the server's own checkout record
  (never from the client), fetches PayPal's canonical record, applies the same
  rules, and returns `{status, isPro, currentPeriodEnd}`.
* Grants Pro only when a verified payment is on record; otherwise reports
  `pending`.
* Ten-second cooldown per account to avoid hammering PayPal on refresh taps.

### 4.6 Database hardening (migration)

* `apply_paypal_entitlement`/`apply_revenuecat_entitlement`: refuse to rebind a
  subscription to another account, validate the status set, never update
  `user_id` on conflict.
* `claim_paypal_checkout`: adds the `payment_issue` disposition for
  `past_due`/`suspended` subscriptions with a future period end.
* Adds the indexes used by reconciliation. Idempotent; proven by applying it
  twice in the test run.

### 4.7 App

* `SubscriptionService`: server-verified `syncPayPalSubscription()`,
  `awaitVerifiedSubscription()` polling, `hasPendingApproval`, typed
  `SubscriptionException` with customer-safe copy, and no raw exception text in
  the UI.
* `EntitlementEvaluator` (new, pure): access rules extracted from the service,
  including the important detail that an `active` row with a **corrupt** period
  end does not grant indefinite access.
* `PaywallScreen`: recognises `PAYPAL_RETURN_URL`/`PAYPAL_CANCEL_URL` landings on
  web, shows "Payment verification pending", adds an explicit "Check payment
  status" action with honest outcomes (pending / past due / cancelled / expired /
  user error), and keeps the App Store/Google Play flow unchanged on mobile.

### 4.8 Tooling

* `supabase/configure-paypal-live.ps1`: read-only verification by default,
  sandbox/live separation, rejects Vercel SSO redirects and the confirmation
  host, requires explicit return/cancel URLs, verifies the plan and webhook via
  the PayPal API, lists Supabase secret *names*, and only writes secrets with
  `-Apply` plus a typed confirmation.

---

## 5. Tests executed

| Suite | Command | Result |
|---|---|---|
| Edge Functions | `cd supabase/functions && deno test tests/` | **89 passed, 0 failed** |
| Database | `./supabase/tests/run_sql_tests.sh` | **17 assertions passed**, migrations idempotent |
| Flutter tests | `flutter test` | **52 passed** |
| Flutter analyzer | `flutter analyze` | **No issues found** |
| PowerShell syntax | `[Parser]::ParseFile(...)` on PowerShell 7.4.6 | **SYNTAX OK** |
| PowerShell behaviour | dry run against 3 origins | SSO redirect, confirmation host and insecure origin all rejected |

Baseline before any change: `flutter analyze` clean, 27 tests passed.

The Edge Function suite covers missing/invalid configuration, exact and foreign
CORS origins, preflight, missing/invalid sessions, plan mismatch, entitlement
and payment-issue blocking, resumption without a second subscription, provider
rejection and release, incomplete provider responses, signature failure, absent
signature headers, duplicates, wrong plan, missing account reference, account
mismatch on both the reservation and the entitlement, activation with and
without payment evidence, wrong payment amount, refund revocation, entitlement
write failure, `404` handling, PayPal outage, reconciliation of paid/pending/
foreign subscriptions, cooldown, and the paid-through rule.

---

## 6. Status against the acceptance criteria

| Requirement | Status | Note |
|---|---|---|
| Public application URL loads without Vercel login | **BLOCKED** | Every deployment URL redirects to `vercel.com/sso-api`; only the confirmation page is public. |
| CORS returns the exact application origin | **FIXED BUT NOT YET VERIFIED** | Code emits the exact origin; nothing is deployed, and there is no verified origin to configure yet. |
| Checkout rejects unauthorized requests | **VERIFIED (current deployment)** | Live probe returns `401 UNAUTHORIZED_NO_AUTH_HEADER`. Repaired code covered by tests. |
| PayPal plan is active USD 3.00 monthly | **BLOCKED** | No PayPal REST credentials in the environment; the PayPal connector available here is a merchant/invoicing tool, not the Billing Plans API. |
| Checkout reaches the correct approval page | **BLOCKED** | Requires the plan verification above plus a public origin. |
| Return URL returns to Ledgerly | **BLOCKED** | Depends on the public origin. |
| Webhook returns no configuration 503 | **BLOCKED** | Secrets must be set; code now logs the missing names. |
| Signature verification validated | **FIXED BUT NOT YET VERIFIED** | Requires a real PayPal delivery; negative path verified by tests. |
| Duplicate events safely ignored | **FIXED BUT NOT YET VERIFIED** | Verified by unit and SQL tests, not by a live duplicate delivery. |
| Entitlement only after verified payment | **FIXED BUT NOT YET VERIFIED** | Rules and tests complete; no end-to-end purchase yet. |
| Cancellation updates Pro | **FIXED BUT NOT YET VERIFIED** | Paid-through semantics tested at unit/SQL level. |
| Renewal synchronised | **FIXED BUT NOT YET VERIFIED** | Requires a sandbox renewal or reconciliation call. |
| Flutter web checkout verified | **BLOCKED** | No public web origin. |
| Windows checkout verified | **NOT STARTED** | Requires a Windows host; the client logic is shared with web and is covered by tests. |
| Mobile subscription behaviour preserved | **VERIFIED** | RevenueCat path untouched; mobile widget tests show the store flow and no PayPal button. |

---

## 7. Remaining blockers and the exact next actions

Ordered, smallest first. Steps 1–3 are required before any live traffic.

1. **Choose and publish a public application origin.** Recommended: a second
   Vercel project (for example `ledgerly-app`) whose production domain is not
   behind Deployment Protection, deploying the `main` branch with PR #8's
   `vercel.json`. Alternative: add a custom domain to the existing project and
   disable Vercel Authentication for production. Do not reuse
   `ledgerly-invoice-app.vercel.app`; it is the confirmation page.
2. **Merge PR #8** (Vercel Flutter web build) and promote that commit to
   production. It is currently an open PR; its latest preview deployment serves a
   correct Flutter bundle.
3. **Set the secrets** for the chosen origin:

   ```powershell
   .\supabase\configure-paypal-live.ps1 -Environment sandbox `
       -AppOrigin https://<public-origin> `
       -PlanId P-3WT24403GG2655600NLQM6EA `
       -WebhookId <sandbox webhook id>
   ```

   Add `-Apply` once the dry run is clean. This is the step that removes the
   `503 Webhook not configured` and the `Origin: null` CORS header.
4. **Apply the migration** `20261108120000_paypal_entitlement_hardening.sql`
   (Supabase SQL editor or `supabase db push`), then deploy the three functions:

   ```
   supabase functions deploy paypal-create-subscription paypal-webhook paypal-sync-subscription --project-ref gcrzwkzithihyhyftfgn
   ```
5. **Register the webhook** for
   `https://gcrzwkzithihyhyftfgn.supabase.co/functions/v1/paypal-webhook` with the
   ten events listed in `supabase/README.md`, then copy its id into
   `PAYPAL_WEBHOOK_ID`.
6. **Run one sandbox purchase** with a sandbox buyer account, confirm
   `subscription_entitlements` gains one row with `status = active` and a future
   `current_period_end`, and confirm the app shows Pro only after that. Then
   repeat for cancel-at-period-end, failed renewal and refund.

What I could not do without credentials or authorisation: verify the PayPal plan
through the Billing Plans API, register or inspect the webhook, read Supabase
secret names in the dashboard, apply the migration to production, deploy the
functions, and complete a sandbox purchase. Each of those changes production
state and the brief requires confirmation.

---

## 8. Security posture after the repair

* Pro is never granted from a browser redirect, a client-supplied id, a client
  tick, or store-side data alone.
* Webhook authenticity is proven by PayPal on every delivery; the body is not
  trusted before verification.
* Entitlements cannot be re-bound between accounts, and the RPC is not callable
  by signed-in customers.
* Row level security remains read-only for customers, scoped to their own rows.
* A failed renewal cannot produce a second chargeable subscription.
* Configuration errors fail closed and reveal setting names, never values.
* Customer-facing errors carry no status codes, stack traces or provider
  internals.
