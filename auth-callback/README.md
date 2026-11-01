# Ledgerly Auth Callback

Static HTTPS return page for Ledgerly account confirmation links.

## Vercel deployment

This is a static HTML site. The Ledgerly Vercel project is configured with **Root Directory** `auth-callback`; no framework, install command, or build command is required. Open the deployed project domain at `/` (not `/auth-callback`).

The preview deployment may require Vercel team authentication. The verified project domain is the public return-page address after the callback branch is merged and the production deployment completes. The free Vercel Hobby plan can host this static page on a `.vercel.app` hostname.

## Supabase configuration — do not change production URLs blindly

- Add the exact deployed callback URL to **Authentication → URL Configuration → Redirect URLs**.
- Do not replace the existing **Site URL** with this separate hostname until the Flutter signup and callback flow has been checked. Flutter web PKCE flows require the callback to run where the matching PKCE verifier is stored.
- The signup call must pass the intended `emailRedirectTo` / `redirectTo` URL, and that URL must be in the Supabase allow-list.
- Keep the confirmation email link as Supabase's `{{ .ConfirmationURL }}` in `supabase/templates/confirm-signup.html`. Supabase verifies the one-time link before redirecting to the requested destination.

## Important limitations

This page supports the informational email-confirmation return only. It is not a password-recovery handler, a replacement for Supabase Auth, or a native mobile deep-link handler. It does not exchange the returned authorization code, establish a Ledgerly session, create accounts, verify passwords, or independently validate confirmation tokens. After a successful confirmation redirect, the user must return to Ledgerly and sign in. Password-reset emails must redirect to the Flutter app's own origin and use the app's password-reset flow; do not route recovery links to this static page. The page only presents the return/error state sent by Supabase.

The repository currently contains Flutter web and Windows host folders, but no Android or iOS host projects and no registered Ledgerly app URI scheme. Native app handoff requires native platform configuration and end-to-end testing.

A separate callback hostname cannot share browser PKCE storage with the Flutter web app. The Flutter web signup currently defaults its redirect to the app's own origin, which keeps the PKCE verifier available to the app. Do not override that with this separate Vercel hostname for web signups. Keep this static page for informational/manual sign-in flows only; it does not complete the PKCE code exchange. If you want a separate hostname to handle web signups, implement and end-to-end test a supported same-origin or server-side flow first.

## Verification checklist

1. Deploy the static page to Vercel and confirm the HTTPS URL loads.
2. Inspect the actual Flutter signup implementation and confirm its redirect behavior.
3. Add only the required exact callback URL to Supabase's Redirect URLs.
4. Test with a new dedicated email address: send signup, open the newest confirmation email, confirm the redirect, then sign in.
5. Confirm expired/reused links show an error and do not claim success.
