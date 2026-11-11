# Ledgerly production-readiness implementation plan

## Scope and invariants

Bring the existing Flutter app to a release-candidate standard without replacing its product or changing public Supabase function names, webhook contracts, persisted workspace formats, invoice calculation semantics, or backup compatibility unless a proven defect requires it.

Preserve:
- Offline-first local workspace behavior and legacy-key migration.
- Existing document numbering, tax/discount calculation and currency behavior.
- JSON backup/restore compatibility and safe failure semantics.
- Server-authoritative PayPal/RevenueCat entitlement verification.
- Existing public Edge Function URLs, request/response contracts and CI entry points.

## Repository baseline and inspection

- Default branch inspected: `main`.
- Flutter package: `ledgerly`; Dart constraint `>=3.3.0 <4.0.0`.
- Present platform folders are documented as Web and Windows; Android/iOS host projects are not included.
- Existing CI workflows: `.github/workflows/flutter-ci.yml` (Flutter analyze, expanded tests, Web release build) and `.github/workflows/billing-checks.yml` (Deno lint/tests and PostgreSQL SQL tests).
- Existing Supabase guidance identifies local Deno and SQL test commands.
- Baseline commands requested: `flutter pub get`, `flutter analyze`, `flutter test --reporter expanded`, `flutter build web --release`, `deno lint`, `deno test tests/`, and `supabase/tests/run_sql_tests.sh`.
- **Execution limitation:** this GitHub-connected workspace can inspect and edit repository files but does not expose a local checkout or Flutter/Deno/PostgreSQL execution environment. Therefore no current baseline command result can honestly be reported here. CI results must be captured on the branch before merge. Historical test counts in prior documentation are not treated as the current baseline.

## Architecture map (confirmed from inspected files)

- App entry/theme: `lib/main.dart`.
- Main workspace UI and document/PDF flows: `lib/screens/home_screen.dart` (large stateful screen; includes PDF generation and primary navigation).
- Local persistence and snapshot/legacy storage: `lib/services/document_store.dart`.
- Billing state and provider integration: `lib/services/subscription_service.dart`, `lib/services/entitlement_evaluator.dart`, `lib/screens/paywall_screen.dart`.
- Invoice data/calculation model: `lib/models/business_document.dart`.
- Backend: `supabase/functions/**`, SQL schema/migrations/tests under `supabase/`.
- Validation pipelines: the two workflows listed above.

## Implementation phases

### Phase 1 — Fail-closed configuration and baseline
1. Remove production Supabase URL/key defaults from the Flutter entry point. Optional account/billing services must be unavailable unless explicit public build configuration is supplied.
2. Keep local document functionality available when Supabase is not configured.
3. Capture actual baseline command results in CI; do not invent local results.

### Phase 2 — Data integrity and backup safety
1. Audit snapshot and legacy-key migration, import validation, repeated imports, partial snapshots and write failure behavior.
2. Add/adjust tests for duplicate IDs/numbers, invalid dates/currencies, non-finite and negative values, overpayments, orphan payments and missing invoices.
3. Preserve valid legacy data and never convert decode failures into an empty workspace.
4. Keep destructive tests isolated to in-memory preferences or temporary database fixtures.

### Phase 3 — Billing security
1. Trace all paths that can set Pro and verify only server-validated entitlement records can grant it.
2. Verify no client-side preference, redirect, local cache or RevenueCat customer info independently grants access.
3. Verify fail-closed behavior when backend configuration, webhook, schema or Edge Functions are absent.
4. Preserve PayPal webhook signature verification, idempotency, account binding and public API contracts.

### Phase 4 — UI, accessibility and decomposition
1. Decompose the oversized home screen into focused navigation, top-bar, metrics, document-row, empty-state, status and responsive-field widgets where existing equivalents do not already exist.
2. Review mobile/tablet/desktop layouts at 375x812, 768x1024, 1280x720 and 1440x900.
3. Add accessible labels, keyboard/focus behavior, tooltips, clear loading/disabled/saving states and safe confirmations.
4. Verify long names/numbers/notes, large values, large lists, no-result states and dialog constraints.
5. Localize all visible user-facing strings using the existing translation mechanism; do not claim completeness until a string audit is done.

### Phase 5 — PDF correctness
1. Extract PDF composition from the home screen into a dedicated service without changing document totals.
2. Verify all business/customer/document/payment fields, currency and language.
3. Exercise long text, missing logo, empty optional fields, zero totals, partial payments and multi-page documents.
4. Add byte-level or structural PDF tests where practical; never label an amount paid or balance due incorrectly.

### Phase 6 — Documentation and repository hygiene
1. Document supported/unsupported targets and actual minimum SDK/toolchain requirements from project files.
2. Explain local-only workspace storage, no cloud sync, backup limitations, privacy-sensitive fields and subscription terms.
3. Remove tracked generated artifacts only after confirming they are generated and not source assets; retain ignore rules.
4. Scan for credentials, stale docs, unused dependencies/imports and debug-only behavior.
5. Keep CI commands and workflow permissions valid.

### Phase 7 — Release verification
Run all Flutter, Deno and SQL commands on the release-candidate branch. Record exact versions, commands, exit codes, test counts and any environment blockers. Complete manual visual/device checks at all four viewport sizes and sandbox billing checks before release.

## Risks and gates

- Do not deploy migrations, Edge Functions, secrets or live billing changes as part of a source-only release-candidate branch.
- Do not claim Android/iOS support without platform host projects and release automation/signing.
- Do not enable billing by silently falling back to a hardcoded production Supabase project.
- Do not remove user data, change backup schemas, or weaken payment checks to make tests pass.
- A release candidate is not production-approved until branch CI is green and the manual gates are signed off.
