import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Closes the silent-failure gap: every agent function writes a row here on every
// invocation. A separate agent-run-check function alerts if an agent hasn't logged a
// successful run within its expected window.
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

export async function finishRun(
  supabase: SupabaseClient,
  runId: string,
  status: 'success' | 'partial' | 'failed',
  summary?: string,
  errorDetail?: string,
): Promise<void> {
  await supabase
    .from('agent_run_log')
    .update({
      finished_at: new Date().toISOString(),
      status,
      summary: summary ?? null,
      error_detail: errorDetail ?? null,
    })
    .eq('id', runId);
}
