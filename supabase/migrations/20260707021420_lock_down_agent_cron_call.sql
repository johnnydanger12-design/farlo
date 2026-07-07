-- Critical fix: agent_cron_call(fn_name, dry_run) was granted EXECUTE to anon and
-- authenticated in the original baseline migration (20260704000000_baseline_schema.sql
-- line 2106-2107) — meaning any fully unauthenticated caller with only the public anon
-- key could invoke it directly via PostgREST RPC and trigger a real, non-dry-run agent
-- run (real Gmail sends from Sage, real outreach from Miles, real writes to
-- content_queue/sales_prospects/support_tickets) an unlimited number of times, for
-- free. Found while building the founder dashboard's "Run now" button — this table
-- should never have been reachable by anything but pg_cron (which runs as postgres)
-- and the new founder-gated wrapper below.
--
-- Same fix pattern as Scenario 12 in supabase/tests/security_abuse_scenarios.sql
-- (compile_user_data_export / delete_account_data): REVOKE EXECUTE from anon and
-- authenticated, leaving only postgres/service_role.

REVOKE EXECUTE ON FUNCTION "public"."agent_cron_call"("fn_name" "text", "dry_run" boolean) FROM "anon";
REVOKE EXECUTE ON FUNCTION "public"."agent_cron_call"("fn_name" "text", "dry_run" boolean) FROM "authenticated";

-- Founder-only wrapper for the dashboard's "Run now" button — calls the same
-- underlying agent_cron_call() (so it reuses the existing Vault-backed bearer secret
-- and pg_net dispatch, no new secret or edge function needed) but scoped to only the
-- founder, and with the jitter removed since a human explicitly clicking "Run now"
-- wants it to actually run now.
CREATE OR REPLACE FUNCTION "public"."founder_trigger_agent"("fn_name" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  bearer text;
begin
  if not public.is_founder() then
    raise exception insufficient_privilege using message = 'Only the founder can trigger an agent run';
  end if;

  select decrypted_secret into bearer from vault.decrypted_secrets where name = 'agent_cron_bearer';

  perform net.http_post(
    url := 'https://weflrxyerxpsafcdetya.supabase.co/functions/v1/' || fn_name,
    headers := jsonb_build_object('Authorization', 'Bearer ' || bearer, 'Content-Type', 'application/json'),
    body := '{}'::jsonb
  );
end;
$$;

ALTER FUNCTION "public"."founder_trigger_agent"("fn_name" "text") OWNER TO "postgres";

REVOKE EXECUTE ON FUNCTION "public"."founder_trigger_agent"("fn_name" "text") FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."founder_trigger_agent"("fn_name" "text") TO "authenticated";
