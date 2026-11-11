# Ledgerly release-candidate TODO

Every item below is an acceptance criterion, not a claim of completion.

## Baseline
- [ ] Record Flutter/Dart/Deno/PostgreSQL versions and run all requested baseline commands before source changes in a real checkout.
- [ ] Preserve baseline logs and distinguish pre-existing failures from regressions.
- [ ] Confirm CI workflows run on the release-candidate branch.

## Configuration and billing
- [ ] No production Supabase URL, publishable key, PayPal secret or RevenueCat secret is embedded as a source-code default.
- [ ] Without explicit Supabase public configuration, local workspace features still start and billing/account actions fail closed with clear copy.
- [ ] Pro cannot be granted by client-side flags, browser redirects, local storage, or unverified RevenueCat customer data.
- [ ] PayPal and RevenueCat webhook signatures, account binding, idempotency and stale-event protection have tests.
- [ ] Public Edge Function names and request/response contracts remain compatible.

## Workspace integrity
- [ ] Snapshot corruption/partial snapshots produce a recoverable error and never overwrite data with an empty workspace.
- [ ] Legacy storage migration is tested and repeatable.
- [ ] Duplicate IDs and duplicate document numbers are rejected or safely resolved without silent data loss.
- [ ] Invalid dates/currencies, negative values and NaN/infinity are rejected or safely normalized with documented rules.
- [ ] Payments require an existing invoice, positive cent-rounded amounts and no overpayment.
- [ ] Failed writes/imports leave the previous workspace intact.
- [ ] Repeated imports have an explicit, tested duplicate policy.
- [ ] Backup export/import round trips preserve all supported fields.

## UX, accessibility and localization
- [ ] Home screen is decomposed into focused widgets without changing core flows.
- [ ] Visible UI strings are localized for every supported language.
- [ ] Keyboard navigation and visible focus work for all primary controls.
- [ ] Interactive controls expose semantic labels and tooltips where appropriate.
- [ ] Loading, disabled, save-progress, error and retry states are clear.
- [ ] Destructive actions require confirmation.
- [ ] Layouts are checked at 375x812, 768x1024, 1280x720 and 1440x900.
- [ ] Long names, invoice numbers, notes, large monetary values, large lists and no-results states remain usable.
- [ ] Dialogs and navigation remain accessible at narrow widths.

## PDF
- [ ] PDF shows accurate business identity/contact/tax data, customer data, document metadata, line items, discounts, tax and totals.
- [ ] Paid and balance-due values agree with valid invoice-linked payments and cannot exceed totals.
- [ ] Currency and selected language are correct.
- [ ] Long text wraps, multiple pages paginate, optional fields/logo can be absent, and zero/part-paid documents render honestly.
- [ ] PDF regression tests cover realistic fixtures.

## Documentation and hygiene
- [ ] README lists only platform targets actually present and release-tested.
- [ ] SDK/toolchain requirements and setup/build commands match repository configuration.
- [ ] README explains local-only data storage, no cloud sync, backup limits, privacy-sensitive fields and subscription terms.
- [ ] Production checklist and known limitations are explicit.
- [ ] Generated build outputs are ignored and no generated artifacts remain tracked.
- [ ] No accidental credentials, dead code, stale assets or unused dependencies remain without justification.

## Final verification (must be executed, not inferred)
- [ ] flutter pub get
- [ ] flutter analyze
- [ ] flutter test --reporter expanded
- [ ] flutter build web --release
- [ ] cd supabase/functions && deno lint
- [ ] cd supabase/functions && deno test tests/
- [ ] ./supabase/tests/run_sql_tests.sh
- [ ] CI green on the release-candidate branch.
- [ ] Manual sandbox payment, restore, PDF and responsive checks completed without production data.

## Release decision
- [ ] Every changed file listed in final report.
- [ ] Every executed command and result listed in final report.
- [ ] Remaining limitations and manual sign-offs listed.
- [ ] No production-ready claim until all mandatory gates above pass.
