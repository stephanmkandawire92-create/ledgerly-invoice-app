# Ledgerly — Flutter

A clean, professional, offline-first quote and invoice builder. The project starts with **no sample/demo records**.

## Included
- Responsive Material 3 dashboard and navigation
- Create, edit, search and delete quotes and invoices
- Line items, quantities, unit prices, discount, tax and calculated totals
- Document status, issue date, due date, client name and email, notes
- Local persistence on the device using `shared_preferences`
- Optional Supabase account and private cloud workspace for users who choose to sign up
- Explicit migration choice: upload local records, restore cloud records, or cancel; replacing an existing destination requires confirmation
- Print / save as PDF using the platform print dialog
- Share generated PDF
- Empty states rather than fabricated example data

## Run
1. Install Flutter and Android Studio (or another Flutter-supported IDE).
2. Extract this folder.
3. In the project folder, run:
   ```sh
   flutter pub get
   flutter run
   ```
4. To build Android:
   ```sh
   flutter build apk --release
   ```

## Important production limitations
- Local-only mode remains available without an account. Optional cloud backup/sync uses the Supabase table defined in `supabase/migrations/20261027201302_ledgerly_optional_cloud_storage.sql and `supabase/migrations/20261027201332_ledgerly_atomic_workspace_migration.sql``; apply the migration before enabling cloud mode.
- Payment provider buttons and subscription checkout have intentionally been removed rather than pretending to process payments. Real recurring billing requires a merchant account, secure server-side secrets, verified webhooks, and entitlement checks.
- Automated email/SMS reminders and live bank feeds are not included; reminder settings alone cannot send messages. These require a backend scheduler and provider integrations.
- This is a runnable Flutter MVP, not a claim that all business, tax, accounting, or payment-provider compliance requirements have been completed.


## Optional cloud backup and sync

Cloud storage is opt-in. A user can continue locally without creating an account. Cloud account sign-up and sign-in require the app to be built with the existing public Supabase configuration:

```sh
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_SUPABASE_PUBLISHABLE_KEY
```

Use the project's publishable key only. Never put the Supabase service-role key in a Flutter app.

Before testing cloud storage:
1. Apply `supabase/migrations/20261027201302_ledgerly_optional_cloud_storage.sql and `supabase/migrations/20261027201332_ledgerly_atomic_workspace_migration.sql`` to the intended Supabase project.
2. Enable email/password sign-up in Supabase Auth and configure email confirmation/reset URLs for your app.
3. Build with `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`.
4. Sign in, then choose **Upload local records**, **Restore cloud records**, or **Cancel**.
5. If the destination already has records, Ledgerly asks for explicit confirmation before replacing them.

Cloud data is partitioned by authenticated user and protected by row-level security. This implementation writes cloud changes to Supabase before updating the local cache. If cloud writes fail, the app reports an error rather than claiming the cloud copy was updated. Local-only mode does not require the network.
