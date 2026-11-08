# Ledgerly subscription backend

Server-side subscription handling for Ledgerly Pro (USD $3.00 per month).

**Supabase project:** `gcrzwkzithihyhyftfgn`
(`https://gcrzwkzithihyhyftfgn.supabase.co`)

The Flutter app never grants Pro. It reads `subscription_entitlements` through
row level security, and can ask the backend to reconcile an outstanding PayPal
checkout. Access is granted only after PayPal confirms a payment.

For signup email branding, SMTP, confirmation redirects and the production Auth
findings, see [`auth-email-setup.md`](auth-email-setup.md).

---

## 1. Edge Functions

| Function | JWT | Purpose |
|---|---|---|
| `paypal-create-subscription` | required | Creates or safely resumes a PayPal subscription for the signed-in account and returns the approval URL. Never writes an entitlement. |
| `paypal-sync-subscription` | required | Reconciles the caller's outstanding checkout against PayPal's canonical subscription record and returns the verified entitlement. Used when the customer returns from PayPal and by "Check payment status". |
| `paypal-webhook` | disabled | PayPal's webhook receiver. Verifies every signature with PayPal, then applies the canonical subscription state. |
| `revenuecat-webhook` | disabled | App Store / Google Play purchases via RevenueCat. |

Webhook endpoint to register in PayPal:

```
https://gcrzwkzithihyhyftfgn.supabase.co/functions/v1/paypal-webhook
```

Subscribe the webhook to:

```
BILLING.SUBSCRIPTION.ACTIVATED
BILLING.SUBSCRIPTION.UPDATED
BILLING.SUBSCRIPTION.RE-ACTIVATED
BILLING.SUBSCRIPTION.SUSPENDED
BILLING.SUBSCRIPTION.CANCELLED
BILLING.SUBSCRIPTION.EXPIRED
BILLING.SUBSCRIPTION.PAYMENT.FAILED
PAYMENT.SALE.COMPLETED
PAYMENT.SALE.REFUNDED
PAYMENT.SALE.REVERSED
```

---

## 2. Required server secrets

Set these as Supabase Edge Function secrets. Never commit them and never put
them in Flutter build arguments.

| Name | Purpose | Required by |
|---|---|---|
| `PAYPAL_ENV` | `sandbox` or `live`. Anything else is rejected, so a typo can never silently charge the wrong environment. | all |
| `PAYPAL_CLIENT_ID` | REST app client id. | all |
| `PAYPAL_CLIENT_SECRET` | REST app secret. | all |
| `PAYPAL_MONTHLY_PLAN_ID` | Active Ledgerly Pro plan, verified at checkout time to be USD 3.00/month. The plan supplied for Ledgerly Pro is `P-3WT24403GG2655600NLQM6EA`; confirm it exists in the environment you are configuring. | all |
| `PAYPAL_WEBHOOK_ID` | Webhook id belonging to the **same** REST app. | webhook |
| `APP_ALLOWED_ORIGIN` | Exact public HTTPS origin of the app, for example `https://app.ledgerly.com`. No path, no trailing slash. | checkout, sync |
| `PAYPAL_RETURN_URL` | Absolute HTTPS URL PayPal returns to after approval, on the same origin as `APP_ALLOWED_ORIGIN`. | checkout |
| `PAYPAL_CANCEL_URL` | Absolute HTTPS URL PayPal returns to after cancellation, on the same origin. | checkout |
| `REVENUECAT_WEBHOOK_AUTH` | Long random secret shared with RevenueCat's webhook Authorization header. | revenuecat |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are provided
by the platform.

`APP_SITE_URL` is **no longer read**. It pointed both PayPal redirects at the
application root, which made the return destination ambiguous; use the three
explicit settings above.

### Why the origin must match

Checkout is a browser request. If `APP_ALLOWED_ORIGIN` and the PayPal return URL
disagree, the customer lands on an origin the function refuses to answer and the
app reports a network failure after the payment. The functions reject that
combination as a configuration error instead of failing in front of a customer.

The static email-confirmation page (`/auth-callback`, today
`https://ledgerly-invoice-app.vercel.app`) is refused as a checkout target: it
does not host the Flutter app.

---

## 3. Applying the schema

1. Review `subscription-schema.sql` (tables, RLS, RPCs).
2. Apply `migrations/20261108120000_paypal_entitlement_hardening.sql`. It is
   additive and idempotent. It hardens two things:
   * an entitlement row can never be re-bound to a different account;
   * a customer with a failed renewal (`past_due`/`suspended`) cannot start a
     second subscription and be charged twice.
3. Only then deploy the functions.

---

## 4. Entitlement policy

| PayPal event | Canonical state | Ledgerly Pro |
|---|---|---|
| `BILLING.SUBSCRIPTION.ACTIVATED` / `RE-ACTIVATED` | ACTIVE + a matching `last_payment` | granted until `next_billing_time` |
| `BILLING.SUBSCRIPTION.ACTIVATED` | ACTIVE but no payment on record | `pending` — not granted |
| `PAYMENT.SALE.COMPLETED` | amount = USD 3.00 | granted / renewed |
| `BILLING.SUBSCRIPTION.CANCELLED` | CANCELLED | kept until the paid-through date |
| `BILLING.SUBSCRIPTION.EXPIRED` | EXPIRED | revoked immediately |
| `BILLING.SUBSCRIPTION.SUSPENDED` | SUSPENDED | revoked |
| `BILLING.SUBSCRIPTION.PAYMENT.FAILED` | — | `past_due`, not Pro |
| `PAYMENT.SALE.REFUNDED` / `REVERSED` | — | revoked immediately |
| any event older than the stored provider version | — | ignored |

Additional guarantees:

* Every webhook delivery is verified through
  `POST /v1/notifications/verify-webhook-signature`. An unverified delivery is
  rejected with `401` and changes nothing.
* The entitlement is always derived from `GET /v1/billing/subscriptions/{id}`,
  never from the event body's claims.
* The subscription must be on `PAYPAL_MONTHLY_PLAN_ID` and must carry a valid
  Ledgerly account UUID in `custom_id`, otherwise the event is acknowledged and
  ignored.
* Duplicate deliveries are acknowledged and ignored. Provider event ids are
  unique per `(provider, event_id)`, and the RPC refuses to move an entitlement
  backwards in time.
* A refund or reversal is a full revocation. Partial-refund arrangements are a
  commercial decision handled by support.

---

## 5. Verifying a configuration

On Windows PowerShell, from the repository root:

```powershell
.\supabase\configure-paypal-live.ps1 `
    -Environment sandbox `
    -AppOrigin https://<public-app-origin> `
    -PlanId P-XXXXXXXXXXXX `
    -WebhookId WH-XXXXXXXXXXXX
```

The script is read-only by default. It checks that:

* the origin is a bare HTTPS origin;
* the origin does **not** redirect to `vercel.com/sso-api` (Vercel team
  authentication) and is not the confirmation-only host;
* the return and cancel URLs are explicit and on that origin;
* the plan is `ACTIVE`, `USD 3.00`, `every 1 MONTH`, in the requested
  environment;
* the webhook id exists in the same PayPal app and subscribes to the events
  above;
* the required Supabase secret **names** exist.

It prints names and statuses only. Values are never read back. `-Apply` writes
the secrets after an explicit confirmation and does not deploy anything.

Set credentials for the check in the current PowerShell session only:

```powershell
$env:PAYPAL_CLIENT_ID = '...'
$env:PAYPAL_CLIENT_SECRET = '...'
```

---

## 6. RevenueCat (App Store / Google Play)

Unchanged by this PayPal repair, but it shares the entitlement table:

1. Create the `ledgerly_pro` entitlement and map the monthly iOS and Google Play
   products to it.
2. Set `REVENUECAT_WEBHOOK_AUTH` and use the same value as the Authorization
   header in RevenueCat's webhook.
3. `app_user_id` must be the signed-in Supabase user's UUID so a purchase links
   to the right account across platforms.
4. Store prices should match USD 3.00/month (or the intended local equivalent).

Mobile purchases keep working exactly as before: Supabase remains the authority
and the client never unlocks Pro from store data alone.

---

## 7. Tests

```bash
# Edge Function unit and handler tests (Deno, no network)
cd supabase/functions && deno test tests/

# Database RPC, RLS and idempotency tests (local PostgreSQL)
./supabase/tests/run_sql_tests.sh

# Flutter
flutter analyze
flutter test
```

The SQL runner creates a throwaway database, applies the schema and migrations
(twice, to prove idempotency), and asserts the security properties: no
entitlement rebinding, no client writes, no duplicate charges, no rollback of
newer provider state.

---

## 8. Deployment order

1. Apply the migration.
2. Set the secrets (section 2) with the verification script.
3. Deploy `paypal-create-subscription`, `paypal-webhook` and
   `paypal-sync-subscription`.
4. Register or update the PayPal webhook and copy its id into
   `PAYPAL_WEBHOOK_ID`.
5. Run one sandbox purchase end to end and confirm both the entitlement row and
   the app's Pro state. A redirect to PayPal is not proof of a subscription, and
   a `200` webhook response is not proof that the right account was credited.

---

## 9. Known limitations

* PayPal checkout requires a **public** HTTPS origin. A Vercel deployment behind
  team authentication cannot be used: customers would be asked to log in to
  Vercel before they can pay.
* PayPal does not update a plan's price. Changing the price in the app does not
  change `PAYPAL_MONTHLY_PLAN_ID`; create a new plan and update the setting.
* Windows and web use the server-created PayPal approval URL. Do not assume
  native in-app billing on Windows.
* No tax, accounting or payment-provider compliance claim is made. Validate
  local legal and business requirements before commercial launch.
