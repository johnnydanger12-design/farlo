// Runs Monday 6:00 AM. Weekly synthesis across all four agents — reads a week of data,
// writes and sends the brief, refreshes website_content, and nudges operational
// directives based on what the week's data actually showed.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAgentSecret, isDryRun } from '../_shared/auth.ts';
import { startRun, finishRun } from '../_shared/run-log.ts';
import { sendEmail } from '../_shared/notify.ts';
import { getGmailAccessToken, searchThreads, getThread, extractPlainTextBody } from '../_shared/gmail.ts';
import { runAgentLoop, MODEL_SONNET, type ToolDefinition } from '../_shared/claude-agent.ts';
import { estimateCostUsd } from '../_shared/pricing.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

function stripHtml(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 6000);
}

async function fetchPageText(url: string): Promise<string> {
  try {
    const res = await fetch(url);
    if (!res.ok) return `[fetch failed: ${res.status}]`;
    return stripHtml(await res.text());
  } catch (err) {
    return `[fetch error: ${err}]`;
  }
}

const SYSTEM_PROMPT = `You are Aiden, the Farlo Supervisor Agent, running your weekly synthesis. You are the connective tissue between Sage (Support), Miles (Sales), and Piper (Marketing), and you report directly to Johnny (founder) on the state of the business.

You've been given, as context, everything you need for this run — the week's aiden@farlo.app email activity (for context only; the twice-daily inbox check already acted on anything actionable from it, do not re-act), all current agent_directives, your last 10 supervisor_reports, freshly fetched text from farlo.app/terms/privacy, and this week's support_tickets, sales_prospects, and content_queue data.

Do this, in order:
1. Compare the freshly fetched website text against the current website_content directive. If anything meaningfully changed (pricing, features, legal terms), call update_directive on website_content with a structured summary of the current copy. If nothing changed, skip this.
2. Analyze the week: support ticket volume and themes — flag any issue that came up 3+ times as a product problem, not a one-off user issue. Sales: how many prospects got drafts saved but not yet sent, how many responded, any conversions. Marketing: what Piper produced, posted vs queued vs skipped, and whether the queue is backing up.
3. Call write_weekly_brief with the full report content plus at most 3 top actions — Johnny is solo, keep it short and concrete.
4. Call send_weekly_brief_email with a concise version of the same brief.
5. If the week's data suggests an operational directive should change (a city's prospects exhausted, a new question came up 2+ times not yet in support_kb, marketing focus should shift), call update_directive. Never touch a locked row (brand_guidelines, company_story, product_flows_owner, product_flows_consumer).

You do not send customer-facing email, post content, or act directly on behalf of Sage, Miles, or Piper — you observe, update directives, and report to Johnny.`;

const TOOLS: ToolDefinition[] = [
  {
    name: 'update_directive',
    description: 'Update an operational agent_directives row (locked=false only).',
    input_schema: {
      type: 'object',
      properties: {
        directive_key: { type: 'string', enum: ['company_direction', 'farlo_context', 'marketing_focus', 'sales_targets', 'support_kb', 'website_content'] },
        content: { type: 'string' },
      },
      required: ['directive_key', 'content'],
    },
  },
  {
    name: 'write_weekly_brief',
    description: 'Writes the weekly brief as a new supervisor_reports row.',
    input_schema: {
      type: 'object',
      properties: {
        report_content: { type: 'string' },
        critical_flags: { type: 'array', items: { type: 'string' } },
        top_actions: { type: 'array', items: { type: 'string' }, description: 'At most 3 items.' },
      },
      required: ['report_content', 'top_actions'],
    },
  },
  {
    name: 'send_weekly_brief_email',
    description: 'Sends the weekly brief to johnny@farlo.app.',
    input_schema: {
      type: 'object',
      properties: {
        subject: { type: 'string' },
        body: { type: 'string' },
      },
      required: ['subject', 'body'],
    },
  },
];

Deno.serve(async (req: Request) => {
  const authError = requireAgentSecret(req);
  if (authError) return authError;
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const dryRun = isDryRun(req);
  const runId = await startRun(supabase, 'agent-aiden-supervisor', dryRun ? 'dry_run' : undefined);

  try {
    // Step 0: inbox context only, last 7 days
    const accessToken = await getGmailAccessToken('johnny@farlo.app');
    const threads = await searchThreads(accessToken, 'to:aiden@farlo.app OR from:aiden@farlo.app newer_than:7d', 30);
    // deno-lint-ignore no-explicit-any
    const inboxContext: any[] = [];
    for (const t of threads) {
      const full = await getThread(accessToken, t.id);
      // deno-lint-ignore no-explicit-any
      const messages: any[] = full.messages ?? [];
      for (const m of messages) {
        // deno-lint-ignore no-explicit-any
        const headers = Object.fromEntries((m.payload?.headers ?? []).map((h: any) => [h.name, h.value]));
        inboxContext.push({
          from: headers['From'] ?? '',
          subject: headers['Subject'] ?? '',
          date: headers['Date'] ?? '',
          snippet: extractPlainTextBody(m.payload).slice(0, 500),
        });
      }
    }

    const [homeText, termsText, privacyText] = await Promise.all([
      fetchPageText('https://farlo.app'),
      fetchPageText('https://farlo.app/terms'),
      fetchPageText('https://farlo.app/privacy'),
    ]);

    const { data: directives } = await supabase.from('agent_directives').select('directive_key, content, locked');
    const { data: recentReports } = await supabase
      .from('supervisor_reports')
      .select('week_of, report_content, top_actions, created_at')
      .order('created_at', { ascending: false })
      .limit(10);

    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    const { data: tickets } = await supabase
      .from('support_tickets')
      .select('subject, type, priority, status, created_at')
      .gte('created_at', sevenDaysAgo);
    const { data: prospects } = await supabase
      .from('sales_prospects')
      .select('status, response_notes, last_contacted_at')
      .gte('updated_at', sevenDaysAgo);
    const { data: content } = await supabase
      .from('content_queue')
      .select('platform, status, notes, created_at')
      .gte('created_at', sevenDaysAgo);

    // Deterministic cost estimate — computed in code, not left to the model to
    // remember or calculate, then appended verbatim to whatever Claude writes.
    const { data: runLogs } = await supabase
      .from('agent_run_log')
      .select('agent_name, model, input_tokens, output_tokens, cache_read_tokens, web_search_requests')
      .gte('started_at', sevenDaysAgo)
      .not('model', 'is', null);

    let totalCostUsd = 0;
    const costByAgent: Record<string, number> = {};
    for (const row of runLogs ?? []) {
      if (!row.model) continue;
      const cost = estimateCostUsd(row.model, {
        inputTokens: row.input_tokens ?? 0,
        outputTokens: row.output_tokens ?? 0,
        cacheCreationTokens: 0,
        cacheReadTokens: row.cache_read_tokens ?? 0,
        webSearchRequests: row.web_search_requests ?? 0,
      });
      totalCostUsd += cost;
      costByAgent[row.agent_name] = (costByAgent[row.agent_name] ?? 0) + cost;
    }
    const costBreakdown = Object.entries(costByAgent)
      .sort((a, b) => b[1] - a[1])
      .map(([agent, cost]) => `  - ${agent}: $${cost.toFixed(2)}`)
      .join('\n');
    const costSummary = [
      ``,
      `Estimated Anthropic API cost this week: $${totalCostUsd.toFixed(2)}`,
      costBreakdown || '  (no usage logged)',
      `(Estimate from token counts we log ourselves — not a reconciliation against your actual Anthropic invoice.)`,
    ].join('\n');

    const lockedKeys = new Set((directives ?? []).filter((d) => d.locked).map((d) => d.directive_key));

    // deno-lint-ignore no-explicit-any
    const handlers: Record<string, any> = {
      update_directive: async (input: { directive_key: string; content: string }) => {
        if (lockedKeys.has(input.directive_key)) return { error: `${input.directive_key} is locked` };
        if (dryRun) return { dry_run: true, would_update: input.directive_key };
        const { error } = await supabase
          .from('agent_directives')
          .update({ content: input.content, updated_by: 'aiden', updated_at: new Date().toISOString() })
          .eq('directive_key', input.directive_key);
        return error ? { error: error.message } : { success: true };
      },
      write_weekly_brief: async (input: { report_content: string; critical_flags?: string[]; top_actions: string[] }) => {
        if (dryRun) return { dry_run: true, would_write: input };
        const { error } = await supabase.from('supervisor_reports').insert({
          week_of: new Date().toISOString().slice(0, 10),
          report_content: input.report_content + costSummary,
          critical_flags: input.critical_flags ?? [],
          top_actions: input.top_actions,
        });
        return error ? { error: error.message } : { success: true };
      },
      send_weekly_brief_email: async (input: { subject: string; body: string }) => {
        if (dryRun) return { dry_run: true, would_send: input };
        await sendEmail({ to: 'johnny@farlo.app', subject: input.subject, text: input.body + costSummary, from: 'Aiden <aiden@farlo.app>' });
        return { success: true };
      },
    };

    const userMessage = [
      `This week's aiden@ email activity (context only, already acted on):`,
      JSON.stringify(inboxContext, null, 2),
      ``,
      `Current agent_directives:`,
      JSON.stringify(directives, null, 2),
      ``,
      `Last 10 supervisor_reports:`,
      JSON.stringify(recentReports, null, 2),
      ``,
      `Freshly fetched farlo.app text:`,
      homeText,
      ``,
      `Freshly fetched /terms text:`,
      termsText,
      ``,
      `Freshly fetched /privacy text:`,
      privacyText,
      ``,
      `Support tickets (last 7 days):`,
      JSON.stringify(tickets, null, 2),
      ``,
      `Sales prospects touched (last 7 days):`,
      JSON.stringify(prospects, null, 2),
      ``,
      `Content queue activity (last 7 days):`,
      JSON.stringify(content, null, 2),
    ].join('\n');

    const result = await runAgentLoop({
      systemPrompt: SYSTEM_PROMPT,
      userMessage,
      tools: TOOLS,
      handlers,
      model: MODEL_SONNET,
      maxTokens: 8192,
    });

    const status = result.stoppedReason === 'done' ? 'success' : 'partial';
    await finishRun(
      supabase,
      runId,
      status,
      result.finalText || `${result.toolCallLog.length} tool call(s), stopped: ${result.stoppedReason}`,
      undefined,
      result.usage,
      MODEL_SONNET,
    );

    return new Response(
      JSON.stringify({ summary: result.finalText, tool_calls: result.toolCallLog, dry_run: dryRun }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    await finishRun(supabase, runId, 'failed', undefined, String(err));
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
