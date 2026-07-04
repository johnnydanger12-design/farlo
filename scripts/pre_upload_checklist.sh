#!/usr/bin/env bash
set -euo pipefail

# Farlo pre-upload checklist — turns HANDOFF.md's documented manual
# verification steps into a runnable script instead of "remember to do
# this." Two of Farlo's three App Store rejections (1.0.0+4's empty
# SUPABASE_URL, 1.0.0+5's demo-account subscription state) trace to exactly
# these two checks being skipped once, not a code defect either time.
#
# Run this before uploading any new iOS build.
#
# Usage:
#   scripts/pre_upload_checklist.sh [path/to/Farlo.ipa]
#
# If no IPA path is given, only the demo-account check runs (a quick
# pre-flight before you've even started a build). Pass the built IPA's path
# to also run the dart-define embedding check, e.g. after:
#   flutter build ipa --dart-define-from-file=.env.json
#   scripts/pre_upload_checklist.sh build/ios/ipa/Farlo.ipa

cd "$(dirname "$0")/.."

FAIL=0

echo "== Farlo pre-upload checklist =="
echo

# --- Locate psql (not always on PATH — e.g. Homebrew's libpq is keg-only) ---
PSQL_BIN="$(command -v psql || true)"
if [ -z "$PSQL_BIN" ] && [ -x /opt/homebrew/opt/libpq/bin/psql ]; then
  PSQL_BIN="/opt/homebrew/opt/libpq/bin/psql"
fi

# --- Check 1: dart-define embedding (HANDOFF.md Traps/Dead Ends) ---
IPA_PATH="${1:-}"
if [ -n "$IPA_PATH" ]; then
  if [ ! -f "$IPA_PATH" ]; then
    echo "[FAIL] IPA not found at $IPA_PATH"
    FAIL=1
  else
    echo "-- Checking dart-define embedding in $IPA_PATH --"
    TMPDIR_IPA=$(mktemp -d)
    unzip -oq "$IPA_PATH" -d "$TMPDIR_IPA"
    APP_BINARY="$TMPDIR_IPA/Payload/Runner.app/Frameworks/App.framework/App"
    if [ ! -f "$APP_BINARY" ]; then
      echo "[FAIL] Could not find App.framework/App inside the IPA — unexpected IPA structure, investigate before uploading."
      FAIL=1
    else
      PROJECT_REF=""
      if [ -f .env.json ]; then
        PROJECT_REF=$(grep -o '"SUPABASE_URL"[^,}]*' .env.json | grep -o '[a-z0-9]\{20\}' | head -1 || true)
      fi
      if [ -z "$PROJECT_REF" ]; then
        echo "[WARN] Could not extract the Supabase project ref from .env.json — skipping this sub-check. Confirm .env.json has a real SUPABASE_URL."
      elif strings "$APP_BINARY" | grep -q "$PROJECT_REF"; then
        echo "[PASS] Supabase project ref ($PROJECT_REF) found embedded in the compiled binary."
      else
        echo "[FAIL] Supabase project ref ($PROJECT_REF) NOT found in the compiled binary — the dart-defines were dropped."
        echo "       DO NOT UPLOAD. Rebuild with: flutter build ipa --dart-define-from-file=.env.json"
        FAIL=1
      fi
    fi
    rm -rf "$TMPDIR_IPA"
  fi
else
  echo "-- Skipping dart-define embedding check (no IPA path given) --"
  echo "   Re-run with the built IPA path to check it, e.g.:"
  echo "   scripts/pre_upload_checklist.sh build/ios/ipa/Farlo.ipa"
fi
echo

# --- Check 2: demo account subscription status (HANDOFF.md Traps/Dead Ends) ---
# Uses the REST API with a service-role key rather than a direct Postgres
# connection: the Supabase CLI's own ephemeral login role (used above for
# other checks) turns out to be RLS-subject, not a superuser — it can't read
# auth.users or evaluate policies that call auth.uid(), so a direct psql
# query hits a wall of "permission denied for schema auth" errors. The
# service role key correctly bypasses RLS by design and is the right tool
# for an ops script like this one.
echo "-- Checking apple.review@farlo.app subscription status --"
SUPABASE_URL_VAL=""
if [ -f .env.json ]; then
  SUPABASE_URL_VAL=$(grep -o '"SUPABASE_URL"[^,}]*' .env.json | sed -E 's/.*"(https:\/\/[^"]+)".*/\1/' || true)
fi
if [ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]; then
  echo "[WARN] SUPABASE_SERVICE_ROLE_KEY not set in your shell — skipping this check."
  echo "       Export it (from the Supabase dashboard's API settings) and re-run, or verify manually:"
  echo "       SELECT status FROM subscriptions WHERE owner_id = (SELECT id FROM auth.users WHERE email = 'apple.review@farlo.app');"
elif [ -z "$SUPABASE_URL_VAL" ]; then
  echo "[WARN] Could not read SUPABASE_URL from .env.json — skipping this check."
else
  PROFILE_RESPONSE=$(curl -s -G "${SUPABASE_URL_VAL}/rest/v1/profiles" \
    --data-urlencode "select=id" \
    --data-urlencode "email=eq.apple.review@farlo.app" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}")
  OWNER_ID=$(echo "$PROFILE_RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['id'] if d else '')" 2>/dev/null || echo "")

  if [ -z "$OWNER_ID" ]; then
    echo "[WARN] No profile found for apple.review@farlo.app — if this account no longer exists (e.g. after the post-launch data wipe), this check no longer applies."
  else
    SUB_RESPONSE=$(curl -s -G "${SUPABASE_URL_VAL}/rest/v1/subscriptions" \
      --data-urlencode "select=status" \
      --data-urlencode "owner_id=eq.${OWNER_ID}" \
      -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}")
    STATUS=$(echo "$SUB_RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['status'] if d else '')" 2>/dev/null || echo "")

    if [ -z "$STATUS" ]; then
      echo "[WARN] No subscription row found for apple.review@farlo.app's profile — this check no longer applies."
    elif [ "$STATUS" = "active" ]; then
      echo "[FAIL] apple.review@farlo.app subscription status is 'active'."
      echo "       A reviewer using this account sees 'Active / Renews', not a purchase button — this caused the 2.1(b) rejection."
      echo "       Fix: UPDATE subscriptions SET status='trialing' WHERE owner_id = '${OWNER_ID}';"
      FAIL=1
    else
      echo "[PASS] apple.review@farlo.app subscription status is '$STATUS' (not 'active') — the real paywall will be visible."
    fi
  fi
fi
echo

# --- Check 3: reminder, not automatable ---
echo "-- Reminder (not automatable): App Review Notes --"
echo "   Confirm the App Store Connect 'App Review Notes' field still has the"
echo "   explicit tap-by-tap path to the Subscription screen (Login -> \"Have a"
echo "   business? Get listed\" -> create owner account -> Account tab ->"
echo "   Subscription). This is the only mitigation for the owner-gated paywall"
echo "   (see FARLO_FINAL_AUDIT.md's Must-Fix-if-Apple-Rejects-Again list)."
echo

if [ "$FAIL" -eq 1 ]; then
  echo "== RESULT: FAIL — do not upload until the above is resolved. =="
  exit 1
else
  echo "== RESULT: PASS =="
  exit 0
fi
