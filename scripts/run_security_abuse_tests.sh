#!/usr/bin/env bash
# Runs supabase/tests/security_abuse_scenarios.sql against the isolated
# `remediation` Supabase preview branch — never production. The whole SQL
# file runs inside one transaction that is always ROLLBACK'd at the end, so
# it's safe to re-run repeatedly without leaving fixture data behind.
#
# Requires: supabase CLI linked to the project, and psql/pg_dump available
# (this repo installs them via `brew install libpq`, which doesn't symlink
# onto PATH by default — this script adds it locally rather than requiring
# a permanent shell config change).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

BRANCH_NAME="${1:-remediation}"

echo "Resolving connection string for branch '$BRANCH_NAME'..."
PGURL_POOL="$(supabase branches get "$BRANCH_NAME" -o env | grep '^POSTGRES_URL=' | cut -d= -f2- | tr -d '"')"
if [ -z "$PGURL_POOL" ]; then
  echo "Could not resolve a connection string for branch '$BRANCH_NAME'. Is it created and healthy?" >&2
  exit 1
fi
# Session-mode port (5432), not the transaction-mode pooler (6543) — the
# transaction pooler doesn't support the prepared statements some of this
# script's tooling uses and will fail with "prepared statement already exists".
PGURL_SESSION="${PGURL_POOL/:6543/:5432}"

echo "Running security abuse scenario tests against branch '$BRANCH_NAME'..."
psql "$PGURL_SESSION" -v ON_ERROR_STOP=1 -f "$REPO_ROOT/supabase/tests/security_abuse_scenarios.sql"
