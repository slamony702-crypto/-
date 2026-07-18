#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
# Cloud Staging — Automated Application
# ═══════════════════════════════════════════════════════════
# يقرأ .env.staging.local، يتصل بـSupabase Cloud Staging،
# يطبق baseline + migrations، يشغل tests.
# ⚠️ يرفض التشغيل إذا STAGING_IS_PRODUCTION=true أو Ref يشبه Production
# ═══════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$REPO_DIR/.env.staging.local"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Missing $ENV_FILE — انسخ .env.example واملأ القيم"
  exit 1
fi

# Source env safely — لا نطبع أي قيم
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# ─── Safety Gates ──────────────────────────────────────────
[ -z "${STAGING_PROJECT_REF:-}" ] && { echo "❌ STAGING_PROJECT_REF not set"; exit 1; }
[ -z "${STAGING_URL:-}" ] && { echo "❌ STAGING_URL not set"; exit 1; }
[ -z "${STAGING_DB_HOST:-}" ] && { echo "❌ STAGING_DB_HOST not set"; exit 1; }
[ -z "${STAGING_DB_PASSWORD:-}" ] && { echo "❌ STAGING_DB_PASSWORD not set (in .env.staging.local only)"; exit 1; }

if [ "${STAGING_IS_PRODUCTION:-true}" != "false" ]; then
  echo "❌ STAGING_IS_PRODUCTION must be exactly 'false' — refusing to run"
  exit 1
fi

# Production Ref (from .vercel/repo.json) — never touch this project
PROD_VERCEL_PRJ="prj_zHeDQheJ904Mh82GY6mbkHlxSQRh"
if [[ "$STAGING_PROJECT_REF" == "$PROD_VERCEL_PRJ" ]] || [[ "$STAGING_URL" == *"prj_zHeDQheJ904Mh82GY6mbkHlxSQRh"* ]]; then
  echo "❌ Project ref matches Production — REFUSING"
  exit 1
fi

if [[ "$STAGING_URL" != *"staging"* ]] && [[ "$STAGING_PROJECT_REF" != *"staging"* ]]; then
  echo "⚠️  Neither URL nor Ref contains 'staging' — pausing for confirmation"
  echo "    URL: $STAGING_URL"
  echo "    Ref: $STAGING_PROJECT_REF"
  echo "    Set STAGING_CONFIRMED=yes in env if this really is a staging project"
  [ "${STAGING_CONFIRMED:-no}" != "yes" ] && exit 1
fi

echo "✅ Safety gates passed."
echo "   Ref: $STAGING_PROJECT_REF"
echo "   URL: $STAGING_URL"
echo "   Host: $STAGING_DB_HOST"

# ─── psql binary detection ─────────────────────────────────
PG_BIN=""
for candidate in "/c/Program Files/PostgreSQL/16/bin/psql.exe" \
                 "/c/Program Files/PostgreSQL/15/bin/psql.exe" \
                 "$(which psql 2>/dev/null || true)"; do
  if [ -x "$candidate" ]; then PG_BIN="$candidate"; break; fi
done
[ -z "$PG_BIN" ] && { echo "❌ psql not found"; exit 1; }
echo "✅ psql: $PG_BIN"

# ─── Connection string (never echoed) ─────────────────────
# Use PGPASSWORD env, don't print password
export PGPASSWORD="$STAGING_DB_PASSWORD"
export PGCLIENTENCODING=UTF8
CONN=(-h "$STAGING_DB_HOST" -p "${STAGING_DB_PORT:-5432}" -U "${STAGING_DB_USER:-postgres}" -d "${STAGING_DB_NAME:-postgres}")

echo "─── Testing connection ───"
if ! "$PG_BIN" "${CONN[@]}" -c "SELECT current_database() AS db, version();" 2>&1 | grep -v "^PGPASSWORD"; then
  echo "❌ Connection failed"
  exit 1
fi

echo ""
echo "─── Preflight ───"
"$PG_BIN" "${CONN[@]}" -f "$REPO_DIR/proc-approval-preflight.sql" 2>&1 | tail -30

echo ""
echo "─── Applying migrations 1→6 ───"
for f in proc-approval-1.sql \
         proc-approval-2-hardening.sql \
         proc-approval-3-matching-priority.sql \
         proc-approval-4-snapshot.sql \
         proc-approval-5-notifications-audit.sql \
         proc-approval-6-trigger-invoker.sql; do
  echo "  → $f"
  "$PG_BIN" "${CONN[@]}" -v ON_ERROR_STOP=1 -f "$REPO_DIR/$f" 2>&1 | grep -E "^ERROR|^psql:.*ERROR" | head -3 || echo "    OK"
done

echo ""
echo "─── Seeding Auth users (creates auth.users + linked users) ───"
"$PG_BIN" "${CONN[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/proc-approval-auth-seed.sql" 2>&1 | tail -15

echo ""
echo "─── Running tests ───"
"$PG_BIN" "${CONN[@]}" -f "$REPO_DIR/proc-approval-tests.sql" 2>&1 | grep -E "PASS|FAIL|SKIPPED" > "$SCRIPT_DIR/tests_output.txt"
cat "$SCRIPT_DIR/tests_output.txt"

echo ""
echo "─── Summary ───"
PASS=$(grep -c "PASS" "$SCRIPT_DIR/tests_output.txt" || echo 0)
FAIL=$(grep -c "FAIL" "$SCRIPT_DIR/tests_output.txt" || echo 0)
SKIP=$(grep -c "SKIPPED" "$SCRIPT_DIR/tests_output.txt" || echo 0)
echo "PASS: $PASS | FAIL: $FAIL | SKIPPED: $SKIP"

# Clear password
unset PGPASSWORD

if [ "$FAIL" -gt 0 ]; then
  echo "❌ Some tests failed — check output"
  exit 2
fi
echo "✅ Cloud staging apply complete."
