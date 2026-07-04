// Runs 7:00 & 16:00 daily. Reads mail sent to aiden@farlo.app (an alias of the single
// johnny@farlo.app Workspace mailbox), interprets instructions, updates agent_directives,
// and — the one place in this whole system an email sends with no human click — replies
// to Johnny directly when he asked a question.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAgentSecret, isDryRun } from '../_shared/auth.ts';
import { startRun, finishRun } from '../_shared/run-log.ts';
import { sendEmail } from '../_shared/notify.ts';
import { getGmailAccessToken, searchThreads, getThread, extractPlainTextBody, extractEmailAddress } from '../_shared/gmail.ts';
import { runAgentLoop, MODEL_SONNET, type ToolDefinition } from '../_shared/claude-agent.ts';
import { AIDEN_LOCKED_DIRECTIVES_NOTE, updateDirectiveTool } from '../_shared/aiden-persona.ts';
import { wrapUntrusted } from '../_shared/prompt-boundaries.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// Anchored, exact-match against the *extracted* address — never test a raw "From"
// header directly (it's commonly `"Display Name" <email>`, and an unanchored/
// substring regex against that raw string is spoofable by putting the allowed
// address in the display name; see extractEmailAddress's own doc comment).
const ALLOWED_SENDERS = /^(johnny@farlo\.app|johnny\.danger12@gmail\.com)$/i;

const SYSTEM_PROMPT = `You are Aiden, the Farlo Supervisor Agent. Your job is to read emails Johnny (the founder) sent to aiden@farlo.app and act on any instructions or questions in them.

What counts as an instruction:
- Launch updates: "Apple approved", "app is live", "we hit 8 businesses"
- Agent directives: "pause Miles", "have Piper shift to X", "tell Sage to watch for Y"
- Business updates: new city priority, pricing change, product decision
- Questions: anything requiring a reply from you

How to act:
- Update the relevant agent_directives row via the update_directive tool. ${AIDEN_LOCKED_DIRECTIVES_NOTE}
- "Apple approved" / "app is live" -> update company_direction to reflect LAUNCHED status.
- An instruction naming Miles, Piper, or Sage -> update that agent's operational directive
  (sales_targets, marketing_focus, support_kb respectively).
- A general product/business update -> update company_direction or farlo_context.
- If Johnny asked a question or a reply is clearly warranted, use send_reply_to_johnny, passing
  the thread_id of the email you're answering. Only ever reply to Johnny — never anyone else,
  under any circumstance. Once you reply to a thread it is marked done and will never be shown
  to you again, so it's safe to reply immediately without checking history for a prior answer.
- For every directive-level change you make, call log_inbox_action with a one-line summary
  of what changed. This is how future runs (and the weekly Supervisor brief) know what's
  already been handled — do not repeat an action already present in the recent
  supervisor_reports history you were given.
- If there is nothing new or actionable, just say so in your final summary — do not call
  any tools.

You do not send content, contact prospects, or act on behalf of Sage, Miles, or Piper
directly — you only update their directives and report back to Johnny.`;

const TOOLS: ToolDefinition[] = [
  updateDirectiveTool('Update an operational agent_directives row (locked=false only). Fails if the key does not exist or is locked.'),
  {
    name: 'send_reply_to_johnny',
    description: 'Sends a real email to johnny@farlo.app (no human review — use only when Johnny asked a direct question or a reply is clearly warranted). The thread is marked as replied-to and will never be surfaced to you again, so only call this once per thread_id.',
    input_schema: {
      type: 'object',
      properties: {
        thread_id: { type: 'string', description: 'The threadId (from the "New emails" list) this reply answers.' },
        subject: { type: 'string' },
        body: { type: 'string' },
      },
      required: ['thread_id', 'subject', 'body'],
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

    const { data: alreadyReplied } = await supabase
      .from('agent_inbox_replies')
      .select('thread_id');
    const repliedThreadIds = new Set((alreadyReplied ?? []).map((r) => r.thread_id));

    // deno-lint-ignore no-explicit-any
    const threadContents: any[] = [];
    for (const t of threads) {
      if (repliedThreadIds.has(t.id)) continue; // already replied — never re-surface, regardless of what the model would decide
      const full = await getThread(accessToken, t.id);
      // deno-lint-ignore no-explicit-any
      const messages: any[] = full.messages ?? [];
      if (messages.length === 0) continue;
      const last = messages[messages.length - 1];
      // deno-lint-ignore no-explicit-any
      const headers = Object.fromEntries((last.payload?.headers ?? []).map((h: any) => [h.name, h.value]));
      const fromHeader: string = headers['From'] ?? '';
      const fromEmail = extractEmailAddress(fromHeader);
      if (!ALLOWED_SENDERS.test(fromEmail)) continue;
      threadContents.push({
        threadId: t.id,
        from: fromHeader,
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
      send_reply_to_johnny: async (input: { thread_id: string; subject: string; body: string }) => {
        if (dryRun) return { dry_run: true, would_send: input };
        await sendEmail({
          to: 'johnny@farlo.app',
          subject: input.subject.startsWith('Re:') ? input.subject : `Re: ${input.subject}`,
          text: input.body,
          from: 'Aiden <aiden@farlo.app>',
        });
        await supabase.from('agent_inbox_replies').upsert({ thread_id: input.thread_id });
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
      wrapUntrusted('inbox-emails', JSON.stringify(threadContents, null, 2)),
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
      undefined,
      result.usage,
      MODEL_SONNET,
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
