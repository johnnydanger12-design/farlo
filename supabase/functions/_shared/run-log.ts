import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import type { ToolCallEntry } from './claude-agent.ts';
import type { UsageTotals } from './pricing.ts';

// Closes the silent-failure gap: every agent function writes a row here on every
// invocation. A separate agent-run-check function alerts if an agent hasn't logged a
// successful run within its expected window. Token usage (when the run called Claude)
// is stored too, so cost can be estimated later — see _shared/pricing.ts and
// agent-aiden-supervisor's weekly cost summary.
export async function startRun(
  supabase: SupabaseClient,
  agentName: string,
  runMode?: string,
): Promise<string> {
  const { data, error } = await supabase
    .from('agent_run_log')
    .insert({ agent_name: agentName, run_mode: runMode ?? null, status: 'running' })
    .select('id')
    .single();
  if (error) throw new Error(`Failed to start run log: ${error.message}`);
  return data.id as string;
}

// Observability beyond agent_run_log's one-row-per-run summary
// (ai-agents.md §7 Recommendation #6, agent_architecture_decision.md's Option A
// sub-item #3). runAgentLoop()'s toolCallLog was previously only returned in
// the HTTP response body — invisible for cron-triggered runs nobody is
// watching. Persists one row per tool call, linked to the parent run.

export interface ToolCallLogRow {
  run_id: string;
  sequence: number;
  tool_name: string;
  input: unknown;
  result: unknown;
}

// Pure — unit-testable without a Supabase client (see run-log.test.ts).
export function toToolCallLogRows(
  runId: string,
  toolCallLog: ToolCallEntry[],
): ToolCallLogRow[] {
  return toolCallLog.map((call, i) => ({
    run_id: runId,
    sequence: i,
    tool_name: call.name,
    input: call.input,
    result: call.result,
  }));
}

export async function logToolCalls(
  supabase: SupabaseClient,
  runId: string,
  toolCallLog: ToolCallEntry[],
): Promise<void> {
  const rows = toToolCallLogRows(runId, toolCallLog);
  if (rows.length === 0) return;
  const { error } = await supabase.from('agent_tool_call_log').insert(rows);
  if (error) {
    // Best-effort — never let observability logging itself fail the run.
    console.error(`Failed to log tool calls for run ${runId}: ${error.message}`);
  }
}

export async function finishRun(
  supabase: SupabaseClient,
  runId: string,
  status: 'success' | 'partial' | 'failed',
  summary?: string,
  errorDetail?: string,
  usage?: UsageTotals,
  model?: string,
): Promise<void> {
  await supabase
    .from('agent_run_log')
    .update({
      finished_at: new Date().toISOString(),
      status,
      summary: summary ?? null,
      error_detail: errorDetail ?? null,
      input_tokens: usage?.inputTokens ?? null,
      output_tokens: usage?.outputTokens ?? null,
      cache_creation_tokens: usage?.cacheCreationTokens ?? null,
      cache_read_tokens: usage?.cacheReadTokens ?? null,
      web_search_requests: usage?.webSearchRequests ?? null,
      model: model ?? null,
    })
    .eq('id', runId);
}
