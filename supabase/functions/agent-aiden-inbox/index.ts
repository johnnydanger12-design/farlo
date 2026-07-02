// Runs 7:00 & 16:00 daily. Reads mail sent to aiden@farlo.app (an alias of the single
// johnny@farlo.app Workspace mailbox), interprets instructions, updates agent_directives,
// and — the one place in this whole system an email sends with no human click — replies
// to Johnny directly when he asked a question.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAgentSecret, isDryRun } from '../_shared/auth.ts';
import { startRun, finishRun } from '../_shared/run-log.ts';
import { sendEmail } from '../_shared/notify.ts';
import { getGmailAccessToken, searchThreads, getThread, extractPlainTextBody } from '../_shared/gmail.ts';
import { runAgentLoop, MODEL_SONNET, type ToolDefinition } from '../_shared/claude-agent.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const ALLOWED_SENDERS = /johnny@farlo\.app|johnny\.danger12@gmail\.com/i;

const SYSTEM_PROMPT = `You are Aiden, the Farlo Supervisor Agent. Your job is to read emails Johnny (the founder) sent to aiden@farlo.app and act on any instructions or questions in them.

What counts as an instruction:
- Launch updates: "Apple approved", "app is live", "we hit 8 businesses"
- Agent directives: "pause Miles", "have Piper shift to X", "tell Sage to watch for Y"
- Business updates: new city priority, pricing change, product decision
- Questions: anything requiring a reply from you

How to act:
- Update the relevant agent_directives row via the update_directive tool. NEVER attempt to
  update a row where locked=true — brand_guidelines, company_story, product_flows_owner,
  product_flows_consumer are permanent and Johnny-only.
- "Apple approved" / "app is live" -> update company_direction to reflect LAUNCHED status.
- An instruction naming Miles, Piper, or Sage -> update that agent's operational directive
  (sales_targets, marketing_focus, support_kb respectively).
- A general product/business update -> update company_direction or farlo_context.
- If Johnny asked a question or a reply is clearly warranted, use send_reply_to_johnny.
  Only ever reply to Johnny — never anyone else, under any circumstance.
- For every directive-level change you make, call log_inbox_action with a one-line summary
  of what changed. This is how future runs (and the weekly Supervisor brief) know what's
  already been handled — do not repeat an action already present in the recent
  supervisor_reports history you were given.
- If there is nothing new or actionable, just say so in your final summary — do not call
  any tools.

You do not send content, contact prospects, or act on behalf of Sage, Miles, or Piper
directly — you only update their directives and report back to Johnny.`;

const TOOLS: ToolDefinition[] = [
  {
    name: 'update_directive',
    description: 'Update an operational agent_directives row (locked=false only). Fails if the key does not exist or is locked.',
    input_schema: {
      type: 'object',
      properties: {
        directive_key: { type: 'string', enum: ['company_direction', 'farlo_context', 'marketing_focus', 'sales_targets', 'support_kb', 'website_content'] },
        content: { type: 'string', description: 'The full new content for this directive (replaces the existing value).' },
      },
      required: ['directive_key', 'content'],
    },
  },
  {
    name: 'send_reply_to_johnny',
    description: 'Sends a real email to johnny@farlo.app (no human review — use only when Johnny asked a direct question or a reply is clearly warranted).',
    input_schema: {
      type: 'object',
      properties: {
        subject: { type: 'string' },
        body: { type: 'string' },
      },
      required: ['subject', 'body'],
    },
  },
  {
    name: 'log_inbox_action',
    description: 'Logs a one-line summary of a directive change you made, so future runs know it is already handled.',
    input_schema: {
      type: 'object',
      properties: { summary: { type: 'string' } },
      required: ['summary'],
    },
  },
];

Deno.serve(async (req: Request) => {
  const authError = requireAgentSecret(req);
  if (authError) return authError;
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const dryRun = isDryRun(req);
  const runId = await startRun(supabase, 'agent-aiden-inbox', dryRun ? 'dry_run' : undefined);

  try {
    const accessToken = await getGmailAccessToken('johnny@farlo.app');
    const threads = await searchThreads(accessToken, 'to:aiden@farlo.app newer_than:2d', 25);

    // deno-lint-ignore no-explicit-any
    const threadContents: any[] = [];
    for (const t of threads) {
      const full = await getThread(accessToken, t.id);
      // deno-lint-ignore no-explicit-any
      const messages: any[] = full.messages ?? [];
      if (messages.length === 0) continue;
      const last = messages[messages.length - 1];
      // deno-lint-ignore no-explicit-any
      const headers = Object.fromEntries((last.payload?.headers ?? []).map((h: any) => [h.name, h.value]));
      const from: string = headers['From'] ?? '';
      if (!ALLOWED_SENDERS.test(from)) continue;
      threadContents.push({
        threadId: t.id,
        from,
        subject: headers['Subject'] ?? '',
        date: headers['Date'] ?? '',
        body: extractPlainTextBody(last.payload),
      });
    }

    if (threadContents.length === 0) {
      await finishRun(supabase, runId, 'success', 'Inbox clear — nothing new.');
      return new Response(JSON.stringify({ new_emails: 0 }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const { data: directives, error: directivesError } = await supabase
      .from('agent_directives')
      .select('directive_key, content, locked');
    if (directivesError) throw new Error(`agent_directives query failed: ${directivesError.message}`);

    const { data: recentReports } = await supabase
      .from('supervisor_reports')
      .select('report_content, created_at')
      .order('created_at', { ascending: false })
      .limit(10);

    const lockedKeys = new Set((directives ?? []).filter((d) => d.locked).map((d) => d.directive_key));

    // deno-lint-ignore no-explicit-any
    const handlers: Record<string, any> = {
      update_directive: async (input: { directive_key: string; content: string }) => {
        if (lockedKeys.has(input.directive_key)) {
          return { error: `${input.directive_key} is locked — cannot update` };
        }
        if (dryRun) return { dry_run: true, would_update: input.directive_key };
        const { error } = await supabase
          .from('agent_directives')
          .update({ content: input.content, updated_by: 'aiden', updated_at: new Date().toISOString() })
          .eq('directive_key', input.directive_key);
        return error ? { error: error.message } : { success: true };
      },
      send_reply_to_johnny: async (input: { subject: string; body: string }) => {
        if (dryRun) return { dry_run: true, would_send: input };
        await sendEmail({
          to: 'johnny@farlo.app',
          subject: input.subject.startsWith('Re:') ? input.subject : `Re: ${input.subject}`,
          text: input.body,
          from: 'Aiden <aiden@farlo.app>',
        });
        return { success: true };
      },
      log_inbox_action: async (input: { summary: string }) => {
        if (dryRun) return { dry_run: true, would_log: input.summary };
        const { error } = await supabase.from('supervisor_reports').insert({
          week_of: new Date().toISOString().slice(0, 10),
          report_content: `INBOX ACTION — ${input.summary}`,
        });
        return error ? { error: error.message } : { success: true };
      },
    };

    const userMessage = [
      `Current agent_directives (locked rows are permanent, never call update_directive on them):`,
      JSON.stringify(directives, null, 2),
      ``,
      `Last 10 supervisor_reports rows (check for INBOX ACTION entries already covering these emails):`,
      JSON.stringify(recentReports, null, 2),
      ``,
      `New emails to aiden@farlo.app in the last 2 days:`,
      JSON.stringify(threadContents, null, 2),
    ].join('\n');

    const result = await runAgentLoop({
      systemPrompt: SYSTEM_PROMPT,
      userMessage,
      tools: TOOLS,
      handlers,
      model: MODEL_SONNET,
    });

    const status = result.stoppedReason === 'done' ? 'success' : 'partial';
    await finishRun(
      supabase,
      runId,
      status,
      result.finalText || `${result.toolCallLog.length} tool call(s), stopped: ${result.stoppedReason}`,
    );

    return new Response(
      JSON.stringify({
        new_emails: threadContents.length,
        summary: result.finalText,
        tool_calls: result.toolCallLog,
        dry_run: dryRun,
      }),
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
