-- Observability beyond agent_run_log's one-row-per-run summary
-- (ai-agents.md §7 Recommendation #6, agent_architecture_decision.md's Option A
-- sub-item #3). runAgentLoop() (_shared/claude-agent.ts) already builds a
-- per-tool-call toolCallLog array in memory, but it was only ever returned in
-- the HTTP response body — never persisted, so it was invisible for any
-- cron-triggered run (no one is watching the response). This table gives
-- every individual tool call its own row, linked to the parent run.
CREATE TABLE public.agent_tool_call_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id uuid NOT NULL REFERENCES public.agent_run_log(id) ON DELETE CASCADE,
  sequence integer NOT NULL,
  tool_name text NOT NULL,
  input jsonb,
  result jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX agent_tool_call_log_run_id_idx ON public.agent_tool_call_log(run_id);
ALTER TABLE public.agent_tool_call_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service role only" ON public.agent_tool_call_log FOR ALL USING (false);
