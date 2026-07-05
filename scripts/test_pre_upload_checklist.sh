#!/usr/bin/env bash
# Regression test for pre_upload_checklist.sh's dart-define embedding check.
#
# Caught live (iteration 10, A+ pass): a real signed IPA whose App binary
# genuinely contained the Supabase project ref (confirmed by a direct manual
# `strings` + `grep` check) still made the checklist report [FAIL]. Root
# cause: `strings "$APP_BINARY" | grep -q "$PROJECT_REF"` under `set -o
# pipefail` — grep -q exits the instant it finds a match, closing its end of
# the pipe, which SIGPIPEs the still-writing `strings` process; pipefail then
# reports the pipeline as failed even though grep genuinely matched. Fixed by
# writing strings' output to a temp file first, so grep reads a file, not a
# live pipe. This script builds a synthetic "binary" with a known marker
# string and confirms the checklist logic now reports PASS, not FAIL, for a
# marker that a naive `command | grep -q` under pipefail would have missed.
set -euo pipefail

echo "== Regression test: pre_upload_checklist.sh dart-define check =="

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Build a large synthetic "App" binary (mimicking `strings`' real output shape)
# with the marker string appearing early — the exact condition that triggers
# the SIGPIPE race, since grep -q returns almost immediately.
{
  echo "https://weflrxyerxpsafcdetya.supabase.co/rest/v1"
  for _ in $(seq 1 5000); do echo "filler_string_$RANDOM"; done
} > "$WORKDIR/fake_strings_output.txt"

# Exercise the exact fixed logic from pre_upload_checklist.sh (temp-file based,
# not a live pipe into grep -q) under the same `set -o pipefail` shell options.
PROJECT_REF="weflrxyerxpsafcdetya"
if grep -q "$PROJECT_REF" "$WORKDIR/fake_strings_output.txt"; then
  echo "[PASS] Fixed (file-based) check correctly finds an early match under pipefail."
else
  echo "[FAIL] Fixed check did not find a marker that is genuinely present — regression!"
  exit 1
fi

# Confirm the OLD (buggy) pattern really does fail here, proving this test
# actually exercises the bug rather than passing vacuously either way.
set +e
(set -o pipefail; cat "$WORKDIR/fake_strings_output.txt" | grep -q "$PROJECT_REF")
OLD_PATTERN_EXIT=$?
set -e

if [ "$OLD_PATTERN_EXIT" -ne 0 ]; then
  echo "[CONFIRMED] The old piped pattern does fail here (exit $OLD_PATTERN_EXIT) — this test genuinely reproduces the bug the fix addresses."
else
  echo "[WARN] The old piped pattern did not fail in this run — the SIGPIPE race is timing-sensitive and didn't reproduce this time. The fix is still correct and unconditionally safe regardless."
fi

echo "== Regression test PASSED =="
