# Ledgerly — Flutter

A clean, professional, offline-first quote and invoice builder. The project starts with **no sample/demo records**.

## Included
- Responsive Material 3 dashboard and navigation
- Create, edit, search and delete quotes and invoices
- Line items, quantities, unit prices, discount, tax and calculated totals
- Document status, issue date, due date, client name and email, notes
- Local persistence on the device using `shared_preferences`
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
- Documents are stored locally on the current device. There is no cloud account, cross-device sync, or backup service yet.
- Payment provider buttons and subscription checkout have intentionally been removed rather than pretending to process payments. Real recurring billing requires a merchant account, secure server-side secrets, verified webhooks, and entitlement checks.
- Automated email/SMS reminders and live bank feeds are not included; reminder settings alone cannot send messages. These require a backend scheduler and provider integrations.
- This is a runnable Flutter MVP, not a claim that all business, tax, accounting, or payment-provider compliance requirements have been completed.
