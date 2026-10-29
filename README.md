# Ledgerly — Flutter

Ledgerly is an offline-first quotes and invoicing app. A new workspace starts without sample or demo records.

## Included

- Responsive Material 3 dashboard and navigation
- Create, edit, search, export/share, and delete quotes and invoices
- Line items, quantities, unit prices, discounts, tax, and calculated totals
- Customer and item catalogues, payment tracking, and basic analytics
- Business profile, invoice numbering, currency/language settings, and company logo
- Local persistence and JSON workspace backup/restore
- Optional account and subscription flows using Supabase, PayPal, and RevenueCat scaffolding

## Run and validate

1. Install Flutter and the SDK/toolchain for the platform you intend to run.
2. Flutter web and Windows host folders are included. Android and iOS host folders are not currently included. Windows desktop builds require Windows and Visual Studio with the **Desktop development with C++** workload; Visual Studio Code alone is not sufficient.
3. In the project folder, run:
   ```sh
   flutter pub get
   flutter analyze
   flutter test
   ```
4. Run or build the browser version with:
   ```sh
   flutter run -d web-server --web-port 8080
   flutter build web --release
   ```
   For Windows, after installing the Windows toolchain, run:
   ```powershell
   flutter run -d windows
   flutter build windows --release
   ```
   For Android, first install the Android SDK and add the correct platform project/ID, then:
   ```sh
   flutter run
   flutter build apk --release
   ```

## Supabase configuration

Supabase-backed sign-in and subscription features are optional at build time. To enable them, provide `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` with `--dart-define`; these values are public client configuration, not server secrets. Never include a Supabase service-role key, SMTP credential, PayPal secret, or RevenueCat webhook secret in a Flutter build or Git. Web signup uses the current HTTPS origin as its confirmation return URL. Windows signup must also provide `SUPABASE_AUTH_REDIRECT_URL`, set to a return URL registered in Supabase Authentication URL Configuration. See [`supabase/auth-email-setup.md`](supabase/auth-email-setup.md) for SMTP, branded email, and redirect setup.

Example Windows release build (replace the placeholders with your own public project values and registered HTTPS return URL):

```powershell
flutter build windows --release `
  --dart-define=SUPABASE_URL=https://your-project-ref.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key `
  --dart-define=SUPABASE_AUTH_REDIRECT_URL=https://app.example.com/
```

## Microsoft Store (Windows)

- The Windows runner and a draft Ledgerly icon/square-logo set are present, but this source does not yet contain a Store-ready MSIX. The package manifest must use the exact **Package/Identity Name** and **Publisher** reserved for Ledgerly in Partner Center. Do not replace those values with guessed identifiers. Store listing screenshots and metadata are also required.
- Build the Windows Release executable on a Windows machine with Visual Studio and its Desktop development with C++ workload. Microsoft documents MSIX distribution and the Microsoft Store signing flow in the [Flutter Windows build guide](https://docs.flutter.dev/platform-integration/windows/building); Microsoft also documents package identity/MSIX setup using the `winapp` CLI, which is currently in public preview, in its [Flutter guide](https://learn.microsoft.com/en-us/windows/apps/dev-tools/winapp-cli/guides/flutter).
- Partner Center submission also requires a reserved product name, package, store listing, and screenshots. Add a privacy-policy URL if the app collects or transmits personal information. See Microsoft's [MSIX submission checklist](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/create-app-submission).
- Ledgerly is a non-game PC app and currently offers PayPal for Windows subscriptions. Microsoft Store policy allows secure third-party subscription billing for non-game PC apps, but the Store submission must disclose the provider; the app and listing must clearly state subscription pricing/terms and the provider, and transactions must authenticate the user and obtain confirmation. Review [Microsoft Store policy 10.8](https://learn.microsoft.com/en-us/windows/apps/publish/store-policies#108-financial-transactions) before submission.
- The paywall currently displays **USD 3/month**; verify this matches the live PayPal plan before release. The business profile currently requires bank details. Microsoft policy 10.8.3 says apps that require financial-account information for primary functionality must be submitted under a company developer account; confirm the Partner Center account type, or make those fields optional if appropriate before Store submission.
- RevenueCat's Flutter purchase SDK does not support Windows. Windows subscription checkout uses PayPal; native Microsoft Store billing is not implemented.

## Production limitations

- Documents, customers, items, and payments are stored locally on the device. There is no cloud sync or cross-device workspace backup in this release.
- Subscription checkout requires configured Supabase and provider credentials, an active product/plan, deployed Edge Functions, the schema in `supabase/subscription-schema.sql`, and end-to-end sandbox testing. A PayPal return alone never grants Pro access.
- The free document cap and premium feature gates are evaluated in the client. Because workspace data is local/offline, the cap is a user-experience limit rather than tamper-resistant server enforcement.
- PayPal checkout reserves one in-progress attempt per account and reuses a PayPal idempotency key on retries. PayPal and RevenueCat entitlement updates use provider event/status timestamps to ignore stale webhook deliveries. Apply the schema/RPC changes to Supabase before deploying the Edge Functions; sandbox checkout, refund, cancellation, and retry flows still require end-to-end testing before live billing.
- No tax, accounting, or payment-provider compliance claim is made. Validate local legal and business requirements before commercial launch.
