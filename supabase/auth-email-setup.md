# Ledgerly authentication email and signup-return setup

Use this checklist before enabling public account creation. Keep SMTP credentials and all server-side payment secrets in Supabase; never place them in Flutter source, client build arguments, or Git.

## Configure branded signup email

1. Choose an SMTP sender provider. Verify a domain you control and configure the provider's SPF and DKIM records; publish a DMARC policy for the domain.
2. In Supabase Dashboard, open **Authentication → Emails → SMTP Settings**. Enable custom SMTP and enter the provider's documented host, port, username, password, a verified sender address (for example, `no-reply@auth.your-domain.example`), and sender name `Ledgerly`.
3. Open **Authentication → Emails → Templates → Confirm sign up**. Set the subject to `Confirm your Ledgerly account` and use the HTML in [`templates/confirm-signup.html`](templates/confirm-signup.html). Preserve both `{{ .ConfirmationURL }}` occurrences.
4. Open **Authentication → URL Configuration**. Set **Site URL** to the stable HTTPS origin of the deployed Ledgerly confirmation-return page. Add the exact production return URL and any deliberate development origins to **Redirect URLs**. Do not use `localhost` for production signups.
5. For web, the app passes its current HTTPS origin as `emailRedirectTo` during signup. For Windows, build with `--dart-define=SUPABASE_AUTH_REDIRECT_URL=<registered-return-url>`; use a registered HTTPS page unless a Windows deep-link scheme has been implemented and registered.
6. Test with a dedicated account and inbox on the deployed origin. Confirm that the message arrives from the Ledgerly sender, the confirmation link opens the expected return page, and the user can sign in afterward. Do not disable email confirmation as a workaround.

The template uses Supabase's `{{ .ConfirmationURL }}` confirmation URL variable. See the official [email-template documentation](https://supabase.com/docs/guides/auth/auth-email-templates) and [custom SMTP setup guide](https://supabase.com/docs/guides/auth/auth-smtp).

## Configure subscription services

Before enabling paid checkout, deploy the schema/RPC changes and Edge Functions, then add the required server-side secrets in Supabase Edge Function settings. At minimum, PayPal requires its REST app credentials, an active monthly plan ID, the PayPal webhook ID, and a trusted application/CORS origin. RevenueCat webhook processing requires the configured webhook authorization secret. Keep these values in Supabase only and test checkout, renewals, cancellation, refunds, and retry behavior in the provider sandbox before using live billing.
