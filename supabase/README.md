# Ledgerly subscription backend setup

These files are a subscription backend scaffold. They are **not live until configured and tested end-to-end**.

## Server secrets (never commit these)
- `PAYPAL_CLIENT_ID`
- `PAYPAL_CLIENT_SECRET`
- `PAYPAL_MONTHLY_PLAN_ID` — active PayPal Billing Plan for USD 3.00/month
- `PAYPAL_WEBHOOK_ID` — webhook ID for the matching PayPal REST app
- `PAYPAL_ENV` — `sandbox` first; `live` only after acceptance testing
- `APP_SITE_URL` — trusted HTTPS origin hosting `/billing/paypal-return` and `/billing/paypal-cancel`
- `APP_ALLOWED_ORIGIN` — exact trusted origin for CORS
- `REVENUECAT_WEBHOOK_AUTH` — long random secret; use the same value in RevenueCat's webhook Authorization header

Supabase provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` in the Edge Function environment. Never put service-role keys or PayPal secrets in Flutter code.

## Setup and deployment
1. Use a development Supabase project first. Review `subscription-schema.sql` and apply it in that project's SQL editor.
2. Deploy `paypal-create-subscription`, `paypal-webhook`, and `revenuecat-webhook`.
3. Keep JWT verification enabled for `paypal-create-subscription`. Provider webhooks authenticate inside their handlers; configure their endpoints to accept provider callbacks while retaining signature/authorization checks.
4. Create a PayPal product named **Ledgerly Pro** and an active monthly plan priced at **USD 3.00/month**. Configure webhook events for subscription activation/update/cancel/expire/suspend/payment-failed and payment completed/refunded/reversed.
5. Configure RevenueCat entitlement exactly as `ledgerly_pro`, map the iOS/Google Play products to it, and set the webhook Authorization header. Ensure the real store product prices are also USD 3.00/month or your intended local-currency equivalent.
6. RevenueCat `app_user_id` must be the signed-in Supabase user's UUID for cross-platform account linking.
7. Test purchase, renewal, cancellation, expiry, duplicate events, forged webhooks, wrong account, failed payment and refund. Only then switch to live credentials.

## Important limitations before enabling payments
- PayPal checkout must use the active USD 3.00 monthly plan ID. Updating the app's expected amount does not create or modify a PayPal plan automatically.
- The Flutter app's displayed paywall price must match the provider's configured price.
- RevenueCat's Flutter SDK supports eligible app-store purchases on mobile; do not assume native in-app billing on Windows. Windows and web should use the server-created PayPal approval URL.
- Returning from PayPal is not proof of payment. Only a verified webhook can update subscription status.
- The SQL grants signed-in users read-only access to their own entitlement rows. Client writes are revoked; only Edge Functions using the service-role key may write.
