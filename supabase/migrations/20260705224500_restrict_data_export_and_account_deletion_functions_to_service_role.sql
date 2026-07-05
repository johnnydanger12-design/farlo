-- Critical finding, caught by this iteration's full non-sampled
-- re-verification pass (get_advisors flagged 21 SECURITY DEFINER functions
-- as anon/authenticated-executable; most are safe by design — they check
-- auth.uid() internally, or are trigger-only functions not meaningfully
-- RPC-callable — but these two are not: neither checks the caller's
-- identity against the p_user_id it operates on, because both are only
-- ever meant to be invoked by their Edge Functions using the service role
-- key (delete-account/index.ts, process-data-exports/index.ts).
--
-- Live-verified on the isolated remediation branch before this fix: an
-- unauthenticated request using only the public anon key —
--   POST /rest/v1/rpc/compile_user_data_export {"p_user_id": "<any uuid>"}
-- — returned that user's full profile, email, and account data with zero
-- authentication. This is what the fix below closes.
-- Both anon and authenticated turned out to hold EXPLICIT, direct EXECUTE
-- grants (not just inherited via PUBLIC membership) — confirmed live via
-- has_function_privilege() after an initial REVOKE ... FROM PUBLIC alone
-- left both still genuinely callable. Revoking each role individually is
-- what's actually required to close this.
REVOKE EXECUTE ON FUNCTION public.compile_user_data_export(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.delete_account_data(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.compile_user_data_export(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.delete_account_data(uuid) TO service_role;
