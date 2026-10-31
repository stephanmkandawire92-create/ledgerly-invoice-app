# Ledgerly Auth Callback

Static HTTPS return page for Ledgerly account confirmation links.

## Vercel deployment

Create a Vercel project from this repository and set its **Root Directory** to `auth-callback`. It is a static HTML site; no framework, install command, or build command is required.

The Vercel project must be deployed before its URL is added to Supabase. The free Vercel Hobby plan can host this static page on a `.vercel.app` hostname.

## Supabase configuration — do not change production URLs blindly

- Add the exact deployed callback URL to **Authentication → URL Configuration → Redirect URLs**.
- Do not replace the existing **Site URL** with this separate hostname until the Flutter signup and callback flow has been checked. Flutter web PKCE flows require the callback to run where the matching PKCE verifier is stored.
- The signup call must pass the intended `emailRedirectTo` / `redirectTo` URL, and that URL must be in the Supabase allow-list.
- Keep the confirmation email link as Supabase's `{{ .ConfirmationURL }}` in `supabase/templates/confirm-signup.html`. Supabase verifies the one-time link before redirecting to the requested destination.

## Important limitations

This is a confirmation-return page, not a replacement for Supabase Auth and not a native mobile deep-link handler. It does not create accounts, verify passwords, or independently validate confirmation tokens. It only presents the return/error state sent by Supabase.

The repository currently contains Flutter web and Windows host folders, but no Android or iOS host projects and no registered Ledgerly app URI scheme. Native app handoff requires native platform configuration and end-to-end testing.

A separate callback hostname cannot share browser PKCE storage with the Flutter web app. If the web app uses PKCE, use a same-origin callback or implement and test a server-side / same-origin confirmation flow before enabling the separate hostname.

## Verification checklist

1. Deploy the static page to Vercel and confirm the HTTPS URL loads.
2. Inspect the actual Flutter signup implementation and confirm its redirect behavior.
3. Add only the required exact callback URL to Supabase's Redirect URLs.
4. Test with a new dedicated email address: send signup, open the newest confirmation email, confirm the redirect, then sign in.
5. Confirm expired/reused links show an error and do not claim success.
