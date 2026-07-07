-- Follow-up to 20260707021420_lock_down_agent_cron_call.sql: revoking EXECUTE from
-- anon/authenticated alone was insufficient. pg_proc.proacl showed a lingering
-- "=X/postgres" entry — the PUBLIC pseudo-grant Postgres attaches to every function
-- by default at creation time — which still let anon (and anyone) through regardless
-- of the per-role revokes. Confirmed live before and after this fix via
-- has_function_privilege('anon', 'public.agent_cron_call(text, boolean)', 'EXECUTE').
REVOKE EXECUTE ON FUNCTION "public"."agent_cron_call"("fn_name" "text", "dry_run" boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."agent_cron_call"("fn_name" "text", "dry_run" boolean) TO "service_role";
