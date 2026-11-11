# Ledgerly release-candidate TODO

Every item below is an acceptance criterion, not a claim of completion.

## Baseline
- [ ] Record Flutter/Dart/Deno/PostgreSQL versions and run all requested baseline commands before source changes in a real checkout.
- [ ] Preserve baseline logs and distinguish pre-existing failures from regressions.
- [ ] Confirm CI workflows run on the release-candidate branch.

## Configuration and billing
- [x] Removed the hardcoded production Supabase URL and publishable-key defaults from `lib/main.dart`; a repository-wide secret scan is still required.
- [ ] Without explicit Supabase public configuration, local workspace features still start and billing/account actions fail closed with clear copy.
- [ ] Pro cannot be granted by client-side flags, browser redirects, local storage, or unverified RevenueCat customer data.
- [ ] PayPal and RevenueCat webhook signatures, account binding, idempotency and stale-event protection have tests.
- [ ] Public Edge Function names and request/response contracts remain compatible.

## Workspace integrity
- [x] Snapshot corruption and incomplete snapshots now fail closed; tests cover a partial snapshot and assert its stored bytes are not overwritten (CI verification pending).
- [x] Legacy-key migration preservation is covered by an isolated SharedPreferences test (CI verification pending).
- [x] Normal document writes now reject duplicate document IDs and duplicate numbers; backup imports already reject duplicate IDs/numbers (CI verification pending).
- [~] Added document/profile currency checks, due-before-issue rejection, non-finite/negative line-value checks and backup date/amount checks. Strict malformed legacy-date decoding and full customer/item validation still need review.
- [x] Document/payment snapshot writes now reject orphan, duplicate, non-positive, non-cent and over-total payments (CI verification pending).
- [ ] Failed writes/imports leave the previous workspace intact.
- [ ] Repeated imports have an explicit, tested duplicate policy.
- [ ] Backup export/import round trips preserve all supported fields.

## UX, accessibility and localization
- [ ] `home_screen.dart` remains oversized (about 2,775 lines); widget/PDF service extraction remains outstanding.
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
- [x] PDF generation now refuses invalid, non-cent or over-total payment records and only includes invoice-linked payments (PDF fixture validation still pending).
- [ ] Currency and selected language are correct.
- [ ] Long text wraps, multiple pages paginate, optional fields/logo can be absent, and zero/part-paid documents render honestly.
- [ ] PDF regression tests cover realistic fixtures.

## Documentation and hygiene
- [x] README accurately identifies Web and Windows host projects and explicitly marks Android/iOS unsupported; actual release testing remains pending.
- [ ] SDK/toolchain requirements and setup/build commands match repository configuration.
- [x] README and the seven-language overview notice explain local-only storage, no cloud sync, unencrypted JSON backups and sensitive business/customer fields.
- [ ] Production checklist and known limitations are explicit.
- [x] Removed the tracked `build/` tree (41 entries) and tracked `.idea/` project files; existing ignore rules already exclude these paths.
- [ ] No accidental credentials, dead code, stale assets or unused dependencies remain without justification.

## Final verification (must be executed, not inferred)
- [ ] flutter pub get
- [ ] flutter analyze
- [ ] flutter test --reporter expanded
- [ ] flutter build web --release
- [x] `cd supabase/functions && deno lint` — passed in GitHub Actions run 43103817287.
- [x] `cd supabase/functions && deno test tests/` — passed in GitHub Actions run 43103817287, including new RevenueCat and PayPal payment-evidence tests.
- [ ] ./supabase/tests/run_sql_tests.sh
- [ ] Flutter CI and PostgreSQL SQL tests are currently running on the latest PR commit; final success must be verified before merge.
- [ ] Manual sandbox payment, restore, PDF and responsive checks completed without production data.

## Release decision
- [ ] Every changed file listed in final report.
- [ ] Every executed command and result listed in final report.
- [ ] Remaining limitations and manual sign-offs listed.
- [ ] No production-ready claim until all mandatory gates above pass.
