#!/usr/bin/env bash
# Runs the Ledgerly billing SQL tests against a disposable PostgreSQL database.
#
#   ./supabase/tests/run_sql_tests.sh                 # uses the local cluster
#   PGHOST=... PGUSER=... ./supabase/tests/run_sql_tests.sh
#
# The script never touches a Supabase project: it builds a throwaway database
# from supabase/subscription-schema.sql, the migrations, and the test fixtures.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"
DB_NAME="${LEDGERLY_TEST_DB:-ledgerly_sql_tests}"

psql_admin() {
  if [ -n "${PGHOST:-}" ]; then
    psql "$@"
  else
    sudo -u "${PGSUPERUSER:-postgres}" psql "$@"
  fi
}

echo "==> Recreating database ${DB_NAME}"
psql_admin -q -c "drop database if exists ${DB_NAME};" >/dev/null
psql_admin -q -c "create database ${DB_NAME};" >/dev/null

run_sql() {
  # Stream the file through stdin: the file lives in the developer's home
  # directory, which the postgres OS user cannot read directly.
  psql_admin -q -v ON_ERROR_STOP=1 -d "${DB_NAME}" < "$1"
}

echo "==> Applying Supabase shim"
run_sql "${HERE}/sql/00_supabase_shim.sql"

echo "==> Applying subscription schema"
run_sql "${ROOT}/supabase/subscription-schema.sql"

echo "==> Applying migrations"
for migration in "${ROOT}"/supabase/migrations/*.sql; do
  echo "    - $(basename "${migration}")"
  run_sql "${migration}"
done

echo "==> Applying migrations again (idempotency check)"
for migration in "${ROOT}"/supabase/migrations/*.sql; do
  run_sql "${migration}"
done

echo "==> Running behavioural tests"
LOG="$(mktemp)"
set +e
psql_admin -d "${DB_NAME}" -v ON_ERROR_STOP=1 < "${HERE}/sql/10_entitlement_test.sql" >"${LOG}" 2>&1
STATUS=$?
set -e
grep -E "PASS|FAIL|ERROR" "${LOG}" || true
if [ "${STATUS}" -ne 0 ]; then
  echo "==> SQL tests FAILED (psql exit ${STATUS})"
  rm -f "${LOG}"
  exit "${STATUS}"
fi
rm -f "${LOG}"
echo "==> SQL tests completed without assertion failures"
