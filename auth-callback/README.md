# Ledgerly Auth Callback

Static HTTPS return page for Supabase Auth confirmation and recovery links.

Deploy this directory as a separate Vercel project with this repository as its Git source and Root Directory set to `auth-callback`. No build command is required; output is static HTML.

After deployment, configure Supabase Authentication → URL Configuration:
- Site URL: the production callback URL (origin).
- Redirect URLs: the exact production callback URL, plus deliberate preview/test callback URLs only.

This is a confirmation landing page, not a native deep-link handler. The repository currently has Flutter web and Windows host folders, but no Android or iOS host projects and no registered Ledgerly app URI scheme. Native app handoff requires native platform configuration and testing.

The page does not collect passwords, tokens or payment details. Supabase verifies the email link before redirecting here. Users can then open Ledgerly and sign in.

Important: a separate callback hostname cannot share browser PKCE storage with the Flutter web app. If web sign-in needs PKCE code exchange, host the Flutter web app on this same origin or implement a verified same-origin callback flow.