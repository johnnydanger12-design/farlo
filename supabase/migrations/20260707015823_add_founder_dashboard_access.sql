-- Founder dashboard (dash.farlo.app): read-only visibility into the agent
-- fleet + all-rows business metrics, plus the one write the dashboard needs
-- (editing non-locked agent_directives, exactly what Aiden itself can do).
--
-- is_founder() is email-based (not a hardcoded auth.uid()) so it keeps
-- working if this account is ever recreated — matches the ALLOWED_SENDERS
-- pattern already used to identify the founder in supabase/functions/
-- agent-aiden-inbox/index.ts, just expressed as SQL instead of a Deno regex.
--
-- Every table below is currently "service role only" (USING (false)) or
-- scoped to each user's own rows — confirmed live before writing this, not
-- assumed. These are additive SELECT/UPDATE policies; Postgres OR's
-- permissive policies together, so nothing existing is narrowed.

CREATE OR REPLACE FUNCTION public.is_founder() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT auth.jwt() ->> 'email' = 'johnny.danger12@gmail.com';
$$;

-- Agent fleet tables — currently zero non-service-role access at all.
CREATE POLICY "founder can read" ON public.agent_run_log FOR SELECT USING (is_founder());
CREATE POLICY "founder can read" ON public.agent_tool_call_log FOR SELECT USING (is_founder());
CREATE POLICY "founder can read" ON public.agent_directives FOR SELECT USING (is_founder());
CREATE POLICY "founder can read" ON public.sales_prospects FOR SELECT USING (is_founder());
CREATE POLICY "founder can read" ON public.supervisor_reports FOR SELECT USING (is_founder());
CREATE POLICY "founder can read" ON public.content_queue FOR SELECT USING (is_founder());
CREATE POLICY "founder can read" ON public.support_tickets FOR SELECT USING (is_founder());

-- The one write the dashboard needs: editing a directive, same constraint
-- update_directive already enforces in _shared/aiden-persona.ts.
CREATE POLICY "founder can update unlocked directives" ON public.agent_directives
  FOR UPDATE USING (is_founder() AND locked = false)
  WITH CHECK (is_founder() AND locked = false);

-- Business metrics — these tables already have RLS scoped to each user's own
-- rows; the founder needs an all-rows read for aggregate counts/charts.
CREATE POLICY "founder can read all" ON public.profiles FOR SELECT USING (is_founder());
CREATE POLICY "founder can read all" ON public.subscriptions FOR SELECT USING (is_founder());
CREATE POLICY "founder can read all" ON public.food_trucks FOR SELECT USING (is_founder());
