# Ledgerly subscription backend setup

These files are a subscription backend scaffold. They are **not live until configured and tested end-to-end**. The PayPal plan ID is an identifier, not a credential; PayPal client secrets and webhook verification details must remain server-side.

For signup email branding, SMTP, confirmation redirects, and the current production Auth findings, see [`auth-email-setup.md`](auth-email-setup.md).

## Server secrets (never commit these)
- `PAYPAL_CLIENT_ID`
- `PAYPAL_CLIENT_SECRET`
- `PAYPAL_MONTHLY_PLAN_ID` — active PayPal Billing Plan for USD 3.00/month; set this to `P-3WT24403GG2655600NLQM6EA` for the plan supplied for Ledgerly Pro
- `PAYPAL_WEBHOOK_ID` — webhook ID for the matching PayPal REST app
- `PAYPAL_ENV` — `sandbox` first; `live` only after acceptance testing
- `APP_SITE_URL` — trusted HTTPS origin of the deployed Ledgerly app; PayPal returns and cancellations go to this app root
- `APP_ALLOWED_ORIGIN` — exact trusted origin for CORS
- `REVENUECAT_WEBHOOK_AUTH` — long random secret; use the same value in RevenueCat's webhook Authorization header

Supabase provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` in the Edge Function environment. Never put service-role keys or PayPal secrets in Flutter code.

## Setup and deployment
1. Use a development Supabase project first. Review `subscription-schema.sql` and apply it in that project's SQL editor. The script adds private PayPal checkout-attempt storage plus `claim_paypal_checkout`, `apply_paypal_entitlement`, and `apply_revenuecat_entitlement` RPCs; rerun it when updating an existing deployment.
2. Deploy `paypal-create-subscription`, `paypal-webhook`, and `revenuecat-webhook`.
3. Keep JWT verification enabled for `paypal-create-subscription`. Provider webhooks authenticate inside their handlers; configure their endpoints to accept provider callbacks while retaining signature/authorization checks.
4. Use PayPal plan ID `P-3WT24403GG2655600NLQM6EA` as `PAYPAL_MONTHLY_PLAN_ID`. Verify in the same PayPal environment (sandbox vs live) that this plan is **ACTIVE**, USD 3.00, and monthly before checkout. Configure webhook events for subscription activation/update/cancel/expire/suspend/payment-failed and payment completed/refunded/reversed.
5. Configure RevenueCat entitlement exactly as `ledgerly_pro`, map the iOS/Google Play products to it, and set the webhook Authorization header. Ensure the real store product prices are also USD 3.00/month or your intended local-currency equivalent.
6. RevenueCat `app_user_id` must be the signed-in Supabase user's UUID for cross-platform account linking.
7. Test purchase, renewal, cancellation, expiry, duplicate events, forged webhooks, wrong account, failed payment and refund. Only then switch to live credentials.

## Important limitations before enabling payments
- PayPal checkout must use the active USD 3.00 monthly plan ID. Updating the app's expected amount does not create or modify a PayPal plan automatically.
- The Flutter app's displayed paywall price must match the provider's configured price.
- RevenueCat's Flutter SDK supports eligible app-store purchases on mobile; do not assume native in-app billing on Windows. Windows and web should use the server-created PayPal approval URL.
- Returning from PayPal is not proof of payment. Only a verified webhook can update subscription status.
- PayPal checkout reservation requires `SUPABASE_SERVICE_ROLE_KEY` in the Edge Function environment. The service-role key is server-only; never include it in Flutter build arguments or client code. The reservation reuses a provider idempotency key for retries, rejects definite provider errors so users can retry, and blocks an account with an active or known paid-through entitlement from creating another checkout. Ambiguous network failures remain reserved and retry with the same provider key to avoid a duplicate charge.
- PayPal and RevenueCat entitlement RPCs compare provider event/status timestamps atomically, so delayed webhook deliveries cannot roll the stored state back. Test timestamp fields against real sandbox payloads before enabling live billing.
- The SQL grants signed-in users read-only access to their own entitlement rows. Client writes are revoked; only Edge Functions using the service-role key may write.
