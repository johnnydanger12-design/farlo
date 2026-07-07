import { useEffect, useState } from 'react';
import {
  Bar,
  BarChart,
  CartesianGrid,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { supabase } from '../lib/supabase';
import { estimateCostUsd } from '../lib/pricing';
import { Card, ErrorNote, Loading, Stat } from './ui';

interface UsageRow {
  agent_name: string;
  started_at: string;
  model: string | null;
  input_tokens: number | null;
  output_tokens: number | null;
  cache_creation_tokens: number | null;
  cache_read_tokens: number | null;
  web_search_requests: number | null;
}

const DAY_MS = 24 * 60 * 60 * 1000;

function costOf(row: UsageRow): number {
  return estimateCostUsd(
    row.model ?? 'sonnet',
    {
      inputTokens: row.input_tokens ?? 0,
      outputTokens: row.output_tokens ?? 0,
      cacheCreationTokens: row.cache_creation_tokens ?? 0,
      cacheReadTokens: row.cache_read_tokens ?? 0,
      webSearchRequests: row.web_search_requests ?? 0,
    },
    new Date(row.started_at),
  );
}

export function CostSection() {
  const [rows, setRows] = useState<UsageRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    const since = new Date(Date.now() - 14 * DAY_MS).toISOString();
    supabase
      .from('agent_run_log')
      .select(
        'agent_name, started_at, model, input_tokens, output_tokens, cache_creation_tokens, cache_read_tokens, web_search_requests',
      )
      .gte('started_at', since)
      .then(({ data, error }) => {
        if (cancelled) return;
        if (error) setError(error.message);
        else setRows(data as UsageRow[]);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  if (error) return <Card title="Cost"><ErrorNote message={error} /></Card>;
  if (!rows) return <Card title="Cost"><Loading /></Card>;

  const now = Date.now();
  const thisWeekStart = now - 7 * DAY_MS;
  const lastWeekStart = now - 14 * DAY_MS;

  const byAgent = new Map<string, { thisWeek: number; lastWeek: number }>();
  let thisWeekTotal = 0;
  let lastWeekTotal = 0;

  for (const row of rows) {
    const t = new Date(row.started_at).getTime();
    const cost = costOf(row);
    const bucket = byAgent.get(row.agent_name) ?? { thisWeek: 0, lastWeek: 0 };
    if (t >= thisWeekStart) {
      bucket.thisWeek += cost;
      thisWeekTotal += cost;
    } else if (t >= lastWeekStart) {
      bucket.lastWeek += cost;
      lastWeekTotal += cost;
    }
    byAgent.set(row.agent_name, bucket);
  }

  const chartData = [...byAgent.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([agent, v]) => ({
      agent: agent.replace(/^agent-/, ''),
      'Last week': Number(v.lastWeek.toFixed(2)),
      'This week': Number(v.thisWeek.toFixed(2)),
    }));

  const delta = lastWeekTotal === 0 ? null : ((thisWeekTotal - lastWeekTotal) / lastWeekTotal) * 100;

  return (
    <Card title="Cost — estimated Claude API spend">
      <div className="mb-6 flex flex-wrap gap-8">
        <Stat label="This week" value={`$${thisWeekTotal.toFixed(2)}`} />
        <Stat label="Last week" value={`$${lastWeekTotal.toFixed(2)}`} />
        <Stat
          label="Change"
          value={delta === null ? '—' : `${delta > 0 ? '+' : ''}${delta.toFixed(0)}%`}
        />
      </div>
      <div className="h-64 w-full">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={chartData}>
            <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
            <XAxis dataKey="agent" stroke="var(--muted)" fontSize={12} />
            <YAxis stroke="var(--muted)" fontSize={12} tickFormatter={(v) => `$${v}`} />
            <Tooltip
              contentStyle={{ background: 'var(--panel)', border: '1px solid var(--border)' }}
              formatter={(v) => `$${Number(v).toFixed(2)}`}
            />
            <Legend />
            <Bar dataKey="Last week" fill="var(--muted)" radius={[4, 4, 0, 0]} />
            <Bar dataKey="This week" fill="var(--accent)" radius={[4, 4, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </div>
      <p className="mt-3 text-xs text-[var(--muted)]">
        Estimated from logged token usage using published Anthropic rates — not a
        reconciliation against the actual invoice.
      </p>
    </Card>
  );
}
