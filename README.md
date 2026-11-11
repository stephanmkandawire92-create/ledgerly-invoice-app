# Ledgerly

Ledgerly is an offline-first quotes and invoicing application for small businesses. A new workspace starts empty; the app does not seed demo customers or invoices.

## Current release status

**Status: release candidate under engineering review — not approved for production launch.**

This repository currently contains Flutter Web and Windows host projects. Android and iOS host projects are not present, so Android/iOS are not supported release targets in this repository. A successful Web compilation alone does not establish production readiness.

## Features

- Create, edit, search, share, print and delete invoices and quotes.
- Line items, quantities, unit prices, discounts, tax and calculated totals.
- Customer and item catalogues, payment tracking and basic analytics.
- Business profile, invoice/quote numbering, currency/language settings and company logo.
- Local workspace persistence and JSON backup/restore.
- Optional Supabase authentication and server-verified subscription flows using PayPal and RevenueCat where the relevant platform/provider configuration exists.

## Supported and unsupported platforms

| Platform | Repository support | Release caveat |
|---|---|---|
| Web | Host project present | Run the release build and test in supported browsers before publishing. Browser storage is local to the browser/origin and can be cleared by the user or browser policy. |
| Windows desktop | Host project present | Requires Windows and Visual Studio with the **Desktop development with C++** workload. Store/MSIX packaging and signing are separate release tasks. |
| Android | **Not supported** | No `android/` host project is included. Do not publish an APK/AAB from this repository. |
| iOS | **Not supported** | No `ios/` host project is included. Do not submit an iOS build from this repository. |
| Linux/macOS | **Not supported** | No corresponding Flutter host projects are included. |

### SDK and toolchain requirements

- Dart constraint declared by `pubspec.yaml`: `>=3.3.0 <4.0.0`.
- Use a current stable Flutter SDK compatible with that Dart constraint and the dependency versions resolved by `flutter pub get`.
- The repository does not pin an exact Flutter SDK version or declare a minimum browser version.
- Windows builds require the Windows desktop toolchain described above. The Windows CMake project declares CMake 3.14 as its minimum.
- No Android minSdk/targetSdk or iOS deployment target is declared because those platform projects are absent.

## Local development

1. Install Flutter stable and verify the toolchain:
   ```sh
   flutter doctor -v
   ```
2. From the repository root:
   ```sh
   flutter pub get
   flutter analyze
   flutter test --reporter expanded
   ```
3. Run Web locally:
   ```sh
   flutter run -d web-server --web-port 8080
   ```
4. Run Windows locally from a Windows machine with the required Visual Studio workload:
   ```powershell
   flutter run -d windows
   ```

## Release builds

Web:
```sh
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter build web --release
```

Windows (on Windows with Visual Studio C++ desktop workload):
```powershell
flutter build windows --release
```

Do not treat a local build as a release sign-off. Review CI, test backup recovery with disposable fixtures, test realistic PDFs, verify PayPal in sandbox, and complete viewport/device checks before release.

## Local storage, backups and privacy

**The current workspace is local-only. Ledgerly does not provide cloud workspace sync or cross-device restoration in this release.** Supabase authentication/subscription support does not mean that invoices, customers, items, payments or business-profile data are synced to Supabase.

- Workspace records are persisted on the current device/browser using the app's local preferences storage.
- Browser users can lose local workspace data if browser/site data is cleared, storage is evicted, the browser profile is removed, or the device is lost.
- Export backups regularly and keep copies in a secure location separate from the device.
- JSON backups are not encrypted by Ledgerly. They can contain customer names, emails, phone numbers, billing/shipping addresses, tax numbers, invoice history, business contact details and bank/payment instructions. Treat the exported file as confidential business data.
- Business profile bank details, customer contact details, addresses and tax numbers are stored locally with the workspace and may be included in generated PDFs or backups.
- Do not store passwords, card numbers, bank login credentials, API secrets or other authentication credentials in customer notes, invoice notes, or business-profile fields.
- Ledgerly does not silently migrate local records to a cloud workspace. There is no cloud workspace migration feature in this release.

## Supabase configuration

Supabase account and subscription features are optional. The Flutter app contains no built-in production project URL or public key. If either required value is missing, account and billing features remain unavailable while local workspace features can still be used.

Supply public client configuration at build time only when you intend to enable the account features:

```sh
flutter build web --release \
  --dart-define=SUPABASE_URL=https://your-project-ref.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

For Windows signup, also set `SUPABASE_AUTH_REDIRECT_URL` to a registered HTTPS return URL:

```powershell
flutter build windows --release `
  --dart-define=SUPABASE_URL=https://your-project-ref.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key `
  --dart-define=SUPABASE_AUTH_REDIRECT_URL=https://app.example.com/
```

These are public client settings. Never put a Supabase service-role key, PayPal client secret, webhook secret, SMTP password, or RevenueCat webhook authorization secret in Flutter build arguments, source control, or a client application.

See [Supabase subscription backend setup](supabase/README.md) and [auth email setup](supabase/auth-email-setup.md). Do not copy production credentials into local development environments.

## Subscription and billing terms

- The current paywall is configured to describe Ledgerly Pro as **USD $3.00 per month**. Confirm the actual PayPal plan, currency, tax treatment, renewal terms and cancellation process in the provider environment before enabling live checkout.
- PayPal checkout requires configured Supabase Edge Functions, the subscription schema/migrations, server-side PayPal credentials, webhook signature verification and a public HTTPS app origin.
- A PayPal approval redirect is not proof of payment. Pro access must be granted only from the server-verified entitlement state.
- RevenueCat is used only where supported by its SDK and configured for the target store. Windows uses the PayPal web approval flow; native Microsoft Store billing is not implemented.
- The five-document Free limit is enforced in the client because workspace records are local. It is a product limit, not tamper-resistant server enforcement.
- Subscription purchases, cancellations, renewals, refunds, reversals and account-binding must be tested in sandbox before any live launch.
- Subscription availability, billing disclosures and cancellation terms must be checked against the laws and platform rules applicable to the business and customer.

## Known limitations before production launch

- No cloud sync, server-side workspace backup or cross-device document migration.
- No Android or iOS host projects in this repository.
- No Microsoft Store-ready signed MSIX package or completed Partner Center listing is included.
- The app's translations cover selected interface strings; not every screen and PDF label is fully localized yet.
- The PDF generator is currently implemented in the large home-screen module; dedicated PDF service extraction and comprehensive PDF regression fixtures remain release-candidate work.
- Minimum browser versions and exact Flutter SDK version are not pinned.
- No tax, accounting, legal or payment-provider compliance certification is claimed.

## Production launch checklist

- [ ] `flutter pub get` succeeds.
- [ ] `flutter analyze` reports no issues.
- [ ] `flutter test --reporter expanded` passes.
- [ ] `flutter build web --release` succeeds.
- [ ] Deno lint and Edge Function tests pass.
- [ ] PostgreSQL schema/RPC/RLS tests pass on a disposable database.
- [ ] Backup export/import round trips and failure cases are verified without production data.
- [ ] Payment records cannot be orphaned, duplicated or overpaid; invalid invoice data is rejected before persistence.
- [ ] PayPal sandbox checkout, webhook verification, renewal, cancellation, refund and reversal are tested end to end.
- [ ] PDF output is checked for long text, multiple pages, missing logo, partial payments, tax, currency and localized labels.
- [ ] Responsive and keyboard/screen-reader checks are completed at 375x812, 768x1024, 1280x720 and 1440x900.
- [ ] Privacy policy, backup handling, subscription disclosures, support contact and platform store requirements are reviewed.
- [ ] Release artifacts are signed, reproducible and built from a reviewed commit.
