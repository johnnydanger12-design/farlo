import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Card, ErrorNote, Loading, Modal, Pill } from './ui';

interface RunRow {
  id: string;
  agent_name: string;
  run_mode: string | null;
  started_at: string;
  finished_at: string | null;
  status: 'running' | 'success' | 'partial' | 'failed';
  summary: string | null;
  error_detail: string | null;
}

// Expected cadence per agent, used only to flag a job that's gone quiet — not an
// exact cron parser, just enough slack to catch a genuinely stuck job.
const EXPECTED_INTERVAL_MINUTES: Record<string, number> = {
  'agent-sage': 10,
  'agent-run-check': 15,
  'agent-miles': 60 * 24 * 3,
  'agent-piper': 60 * 24 * 3,
  'agent-aiden-supervisor': 60 * 24 * 8,
  'agent-newsletter-cleanup': 60 * 24 * 8,
  'agent-stripe-weekly': 60 * 24 * 8,
  'agent-urgent-alert': 20,
  'agent-email-labeler': 20,
};

function statusTone(status: RunRow['status']) {
  if (status === 'success') return 'good' as const;
  if (status === 'running') return 'muted' as const;
  if (status === 'partial') return 'warn' as const;
  return 'bad' as const;
}

function timeAgo(iso: string) {
  const ms = Date.now() - new Date(iso).getTime();
  const mins = Math.floor(ms / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 48) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

export function FleetOverview() {
  const [runs, setRuns] = useState<RunRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [openRunId, setOpenRunId] = useState<string | null>(null);
  const [toolCalls, setToolCalls] = useState<Record<string, unknown>[] | null>(null);

  useEffect(() => {
    let cancelled = false;
    supabase
      .from('agent_run_log')
      .select('id, agent_name, run_mode, started_at, finished_at, status, summary, error_detail')
      .order('started_at', { ascending: false })
      .limit(60)
      .then(({ data, error }) => {
        if (cancelled) return;
        if (error) setError(error.message);
        else setRuns(data as RunRow[]);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  async function openRun(runId: string) {
    setOpenRunId(runId);
    setToolCalls(null);
    const { data } = await supabase
      .from('agent_tool_call_log')
      .select('sequence, tool_name, input, result, created_at')
      .eq('run_id', runId)
      .order('sequence', { ascending: true });
    setToolCalls(data ?? []);
  }

  if (error) return <Card title="Fleet"><ErrorNote message={error} /></Card>;
  if (!runs) return <Card title="Fleet"><Loading /></Card>;

  const latestByAgent = new Map<string, RunRow>();
  for (const r of runs) {
    if (!latestByAgent.has(r.agent_name)) latestByAgent.set(r.agent_name, r);
  }

  const openRunRow = runs.find((r) => r.id === openRunId) ?? null;

  return (
    <div className="flex min-w-0 flex-col gap-6">
      <Card title="Fleet health">
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
          {[...latestByAgent.entries()]
            .sort(([a], [b]) => a.localeCompare(b))
            .map(([agent, run]) => {
              const expectedMins = EXPECTED_INTERVAL_MINUTES[agent] ?? 60 * 24 * 8;
              const staleMs = Date.now() - new Date(run.started_at).getTime();
              const stale = staleMs > expectedMins * 60 * 1000 * 1.5;
              return (
                <div key={agent} className="min-w-0 rounded-lg border border-[var(--border)] p-3">
                  <div className="mb-1 flex min-w-0 items-center justify-between gap-2">
                    <span className="min-w-0 truncate text-sm font-medium">{agent}</span>
                    <Pill tone={stale ? 'bad' : statusTone(run.status)}>
                      {stale ? 'stale' : run.status}
                    </Pill>
                  </div>
                  <p className="text-xs text-[var(--muted)]">{timeAgo(run.started_at)}</p>
                </div>
              );
            })}
        </div>
      </Card>

      <Card title="Activity feed">
        <div className="flex flex-col gap-2">
          {runs.slice(0, 30).map((run) => (
            <button
              key={run.id}
              onClick={() => openRun(run.id)}
              className="flex min-w-0 items-center justify-between gap-3 rounded-lg border border-[var(--border)] p-3 text-left hover:border-[var(--accent)]"
            >
              <div className="min-w-0">
                <div className="flex min-w-0 items-center gap-2">
                  <span className="min-w-0 truncate text-sm font-medium">{run.agent_name}</span>
                  <Pill tone={statusTone(run.status)}>{run.status}</Pill>
                  {run.run_mode === 'dry_run' && <Pill tone="muted">dry run</Pill>}
                </div>
                <p className="mt-1 truncate text-sm text-[var(--muted)]">
                  {run.summary ?? run.error_detail ?? '—'}
                </p>
              </div>
              <span className="shrink-0 text-xs text-[var(--muted)]">{timeAgo(run.started_at)}</span>
            </button>
          ))}
        </div>
      </Card>

      <Modal
        open={openRunRow !== null}
        onClose={() => setOpenRunId(null)}
        title={openRunRow ? `${openRunRow.agent_name} — ${timeAgo(openRunRow.started_at)}` : ''}
      >
        {openRunRow && (
          <div>
            <div className="mb-3 flex items-center gap-2">
              <Pill tone={statusTone(openRunRow.status)}>{openRunRow.status}</Pill>
              {openRunRow.run_mode === 'dry_run' && <Pill tone="muted">dry run</Pill>}
            </div>
            <p className="whitespace-pre-wrap break-words text-sm text-[var(--muted)]">
              {openRunRow.summary ?? openRunRow.error_detail ?? '—'}
            </p>
            <div className="mt-4 border-t border-[var(--border)] pt-3">
              <p className="mb-2 text-xs uppercase tracking-wide text-[var(--muted)]">Tool calls</p>
              {toolCalls === null ? (
                <Loading />
              ) : toolCalls.length === 0 ? (
                <p className="text-xs text-[var(--muted)]">No tool calls recorded for this run.</p>
              ) : (
                <div className="flex flex-col gap-2">
                  {toolCalls.map((tc, i) => (
                    <pre
                      key={i}
                      className="min-w-0 overflow-x-auto whitespace-pre-wrap break-words rounded bg-black/30 p-2 text-xs"
                    >
                      {JSON.stringify(tc, null, 2)}
                    </pre>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}
      </Modal>
    </div>
  );
}
