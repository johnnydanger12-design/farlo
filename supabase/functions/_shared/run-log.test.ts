// agent_architecture_decision.md's Option A, sub-item #3 (observability beyond
// agent_run_log). Run with: deno test supabase/functions/_shared/run-log.test.ts
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { toToolCallLogRows } from './run-log.ts';

Deno.test('maps each tool call to a row with a sequence number and the parent run id', () => {
  const rows = toToolCallLogRows('run-1', [
    { name: 'search_tickets', input: { status: 'open' }, result: { count: 3 } },
    { name: 'reply_ticket', input: { id: 't1' }, result: { sent: true } },
  ]);
  assertEquals(rows, [
    { run_id: 'run-1', sequence: 0, tool_name: 'search_tickets', input: { status: 'open' }, result: { count: 3 } },
    { run_id: 'run-1', sequence: 1, tool_name: 'reply_ticket', input: { id: 't1' }, result: { sent: true } },
  ]);
});

Deno.test('returns an empty array for a run with no tool calls', () => {
  assertEquals(toToolCallLogRows('run-1', []), []);
});
