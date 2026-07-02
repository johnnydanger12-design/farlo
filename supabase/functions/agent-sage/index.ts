// Runs every 5 minutes. Ticket bookkeeping (new vs. reopened thread, appending to the
// conversation history) is deterministic and handled in code before Claude ever runs —
// Claude's only job is the judgment call per ticket: send a real answer, or loop in a
// human. There is no more draft-for-review step for support tickets — see
// AGENT_AUTOMATION_RUNBOOK.md for the reasoning. Every auto-sent answer gets an
// AI-disclosure line appended in code (not left to the model to remember), and every
// escalation sends the customer a real acknowledgment rather than going silent. Part 2
// (closing resolved tickets) is pure mechanical checking and doesn't need a model call.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAgentSecret, isDryRun } from '../_shared/auth.ts';
import { startRun, finishRun } from '../_shared/run-log.ts';
import { getGmailAccessToken, searchThreads, getThread, extractPlainTextBody, extractEmailAddress, looksAutomated, sendMessage } from '../_shared/gmail.ts';
import { runAgentLoop, MODEL_SONNET, type ToolDefinition } from '../_shared/claude-agent.ts';
import type { UsageTotals } from '../_shared/pricing.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const FARLO_SENDER = /@farlo\.app$/i;

// Hard cost/loop cap, independent of looksAutomated() ever missing something: once a
// single correspondent has messaged this many times on one ticket, stop replying
// entirely and just flag it for Johnny. Catches any runaway back-and-forth (an
// auto-responder ping-ponging with Sage, or anything else) regardless of the cause.
const MAX_CUSTOMER_MESSAGES_BEFORE_ESCALATION = 3;

const AI_DISCLOSURE = '\n\n—\nHeads up: this reply was written by an AI assistant and can occasionally get things wrong. Just reply to this email anytime if you\'d like a real person to take a look.';

const SYSTEM_PROMPT = `You are Sage, the Farlo Support Agent. Voice: warm, personal, direct. Every reply you write is signed "Sage | Farlo Support" — never "The Farlo Team".

For each open ticket you're given, decide one of two things:

1. SEND_REPLY — if it's a normal question you can answer using the support_kb context you were given, call send_reply with the full reply text. Never invent an answer not grounded in support_kb, brand_guidelines, or product_flows context. This actually sends to the customer — there is no review step, so only use this when you're genuinely confident, not when you're guessing.

2. ESCALATE_TO_HUMAN — use this instead of send_reply whenever any of these apply:
   - It's a billing dispute, refund request, or account deletion request.
   - The customer explicitly asks to speak with a person, or asks for escalation.
   - You don't actually know the answer, or the question needs judgment you don't have.
   Call escalate_to_human with a short internal reason (for Johnny) AND a customer-facing acknowledgment_body — a brief, warm message letting them know a real person from the team will follow up directly. Do NOT use corporate phrasing like "escalating to level 2 support" — write it the way Sage actually talks. Something like "I'm looping in a real person from our team on this — they'll follow up with you directly soon." is the right tone, but write your own, don't just copy that verbatim every time.

Call exactly one tool per ticket_id you were given. If you were given zero open tickets, say so and don't call any tools.`;

const TOOLS: ToolDefinition[] = [
  {
    name: 'send_reply',
    description: 'Sends a real answer directly to the customer. No review step — only call this when confident and grounded in support_kb.',
    input_schema: {
      type: 'object',
      properties: {
        ticket_id: { type: 'string' },
        reply_body: { type: 'string' },
        type: { type: 'string', enum: ['technical', 'billing', 'account', 'feature_request', 'other'] },
      },
      required: ['ticket_id', 'reply_body'],
    },
  },
  {
    name: 'escalate_to_human',
    description: 'Sends the customer a brief human-handoff acknowledgment and flags the ticket urgent for Johnny to personally handle.',
    input_schema: {
      type: 'object',
      properties: {
        ticket_id: { type: 'string' },
        reason: { type: 'string', description: 'Internal note for Johnny — why this was escalated.' },
        acknowledgment_body: { type: 'string', description: 'Customer-facing message letting them know a human will follow up.' },
        type: { type: 'string', enum: ['technical', 'billing', 'account', 'feature_request', 'other'] },
      },
      required: ['ticket_id', 'reason', 'acknowledgment_body'],
    },
  },
];

Deno.serve(async (req: Request) => {
  const authError = requireAgentSecret(req);
  if (authError) return authError;
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const dryRun = isDryRun(req);
  const runId = await startRun(supabase, 'agent-sage', dryRun ? 'dry_run' : undefined);

  try {
    const accessToken = await getGmailAccessToken('johnny@farlo.app');

    // --- PART 1: ingest unread support threads (deterministic bookkeeping) ---
    const unread = await searchThreads(accessToken, 'to:support@farlo.app is:unread', 25);
    const openTicketIds: string[] = [];

    for (const t of unread) {
      const full = await getThread(accessToken, t.id);
      // deno-lint-ignore no-explicit-any
      const messages: any[] = full.messages ?? [];
      if (messages.length === 0) continue;
      const last = messages[messages.length - 1];
      // deno-lint-ignore no-explicit-any
      const headers = Object.fromEntries((last.payload?.headers ?? []).map((h: any) => [h.name, h.value]));
      const fromHeader: string = headers['From'] ?? '';
      const fromEmail = extractEmailAddress(fromHeader);
      if (FARLO_SENDER.test(fromEmail)) continue; // our own reply landing back in the thread, not a customer message
      if (looksAutomated(headers, fromEmail)) continue; // no-reply address, auto-responder, or bounce — not a real inquiry

      const fromName = fromHeader.replace(/<.+>/, '').replace(/"/g, '').trim() || null;
      const subject = headers['Subject'] ?? '(no subject)';
      const body = extractPlainTextBody(last.payload);
      const messageId = headers['Message-ID'] ?? headers['Message-Id'] ?? '';
      const references = [headers['References'], messageId].filter(Boolean).join(' ');

      const { data: existing } = await supabase
        .from('support_tickets')
        .select('id, conversation, priority')
        .eq('gmail_thread_id', t.id)
        .maybeSingle();

      if (!existing) {
        if (dryRun) {
          openTicketIds.push(`dry-run-new-${t.id}`);
          continue;
        }
        const { data: created, error } = await supabase
          .from('support_tickets')
          .insert({
            from_email: fromEmail,
            from_name: fromName,
            subject,
            body,
            gmail_thread_id: t.id,
            status: 'open',
            conversation: [{ role: 'customer', content: body, timestamp: new Date().toISOString() }],
          })
          .select('id')
          .single();
        if (error) throw new Error(`Failed to create ticket for thread ${t.id}: ${error.message}`);
        openTicketIds.push(created.id);
      } else {
        const priorCount = (Array.isArray(existing.conversation) ? existing.conversation : []).length;

        if (priorCount >= MAX_CUSTOMER_MESSAGES_BEFORE_ESCALATION) {
          // Circuit breaker: this correspondent has messaged this many times on one
          // ticket already — stop replying entirely (no further send, so no chance of
          // extending a loop) and just flag it for Johnny to look at directly.
          if (!dryRun && existing.priority !== 'urgent') {
            await supabase
              .from('support_tickets')
              .update({
                status: 'in_progress',
                priority: 'urgent',
                escalation_reason: `${priorCount + 1} messages from this sender on one ticket — stopped auto-replying to avoid a runaway loop. Needs a human look.`,
                updated_at: new Date().toISOString(),
              })
              .eq('id', existing.id);
          }
          continue; // never pushed to openTicketIds — Claude never sees it, nothing sent
        }

        if (dryRun) {
          openTicketIds.push(existing.id);
          continue;
        }
        const conversation = Array.isArray(existing.conversation) ? existing.conversation : [];
        conversation.push({ role: 'customer', content: body, timestamp: new Date().toISOString() });
        const { error } = await supabase
          .from('support_tickets')
          .update({ conversation, status: 'open', updated_at: new Date().toISOString() })
          .eq('id', existing.id);
        if (error) throw new Error(`Failed to update ticket ${existing.id}: ${error.message}`);
        openTicketIds.push(existing.id);
      }
      void references; // kept for future threading refinement, not currently sent to Gmail
    }

    let toolCallLog: unknown[] = [];
    let finalText = 'No open tickets this run.';
    let usage: UsageTotals | undefined;

    if (openTicketIds.length > 0 && !dryRun) {
      const { data: openTickets, error: ticketsError } = await supabase
        .from('support_tickets')
        .select('id, ticket_number, from_name, from_email, subject, body, conversation, gmail_thread_id')
        .in('id', openTicketIds);
      if (ticketsError) throw new Error(`Failed to load open tickets: ${ticketsError.message}`);

      const { data: directives } = await supabase
        .from('agent_directives')
        .select('directive_key, content')
        .in('directive_key', ['brand_guidelines', 'company_story', 'product_flows_owner', 'product_flows_consumer', 'farlo_context', 'support_kb']);

      // deno-lint-ignore no-explicit-any
      const replySubject = (ticket: any): string => {
        const base = ticket.subject.startsWith('Re:') ? ticket.subject : `Re: ${ticket.subject}`;
        return ticket.ticket_number ? `${base} (Ticket #${ticket.ticket_number})` : base;
      };

      // deno-lint-ignore no-explicit-any
      const handlers: Record<string, any> = {
        send_reply: async (input: { ticket_id: string; reply_body: string; type?: string }) => {
          const ticket = (openTickets ?? []).find((tk) => tk.id === input.ticket_id);
          if (!ticket) return { error: `unknown ticket_id ${input.ticket_id}` };
          await sendMessage(accessToken, {
            from: 'Sage | Farlo Support <support@farlo.app>',
            to: ticket.from_email,
            subject: replySubject(ticket),
            bodyText: input.reply_body + AI_DISCLOSURE,
            threadId: ticket.gmail_thread_id,
          });
          const { error } = await supabase
            .from('support_tickets')
            .update({
              status: 'resolved',
              resolved_at: new Date().toISOString(),
              type: input.type ?? null,
              updated_at: new Date().toISOString(),
            })
            .eq('id', input.ticket_id);
          return error ? { error: error.message } : { success: true };
        },
        escalate_to_human: async (input: { ticket_id: string; reason: string; acknowledgment_body: string; type?: string }) => {
          const ticket = (openTickets ?? []).find((tk) => tk.id === input.ticket_id);
          if (!ticket) return { error: `unknown ticket_id ${input.ticket_id}` };
          await sendMessage(accessToken, {
            from: 'Sage | Farlo Support <support@farlo.app>',
            to: ticket.from_email,
            subject: replySubject(ticket),
            bodyText: input.acknowledgment_body,
            threadId: ticket.gmail_thread_id,
          });
          // status='in_progress' (not 'resolved') so Part 2 below picks it up once
          // Johnny's own reply lands and auto-resolves it.
          const { error } = await supabase
            .from('support_tickets')
            .update({
              status: 'in_progress',
              priority: 'urgent',
              type: input.type ?? null,
              escalation_reason: input.reason,
              updated_at: new Date().toISOString(),
            })
            .eq('id', input.ticket_id);
          return error ? { error: error.message } : { success: true };
        },
      };

      const userMessage = [
        `Foundation + support context:`,
        JSON.stringify(directives, null, 2),
        ``,
        `Open tickets this run (call exactly one tool per ticket_id):`,
        JSON.stringify(openTickets, null, 2),
      ].join('\n');

      const result = await runAgentLoop({
        systemPrompt: SYSTEM_PROMPT,
        userMessage,
        tools: TOOLS,
        handlers,
        model: MODEL_SONNET,
      });
      toolCallLog = result.toolCallLog;
      finalText = result.finalText;
      usage = result.usage;
    } else if (dryRun && openTicketIds.length > 0) {
      finalText = `[dry run] would have processed ${openTicketIds.length} open ticket(s), no sends/writes made.`;
    }

    // --- PART 2: close escalated tickets once Johnny personally replies (mechanical) ---
    const { data: inProgress } = await supabase
      .from('support_tickets')
      .select('id, gmail_thread_id')
      .eq('status', 'in_progress');

    let closedCount = 0;
    for (const ticket of inProgress ?? []) {
      if (!ticket.gmail_thread_id) continue;
      const full = await getThread(accessToken, ticket.gmail_thread_id);
      // deno-lint-ignore no-explicit-any
      const messages: any[] = full.messages ?? [];
      if (messages.length === 0) continue;
      const last = messages[messages.length - 1];
      // deno-lint-ignore no-explicit-any
      const headers = Object.fromEntries((last.payload?.headers ?? []).map((h: any) => [h.name, h.value]));
      const fromHeader: string = headers['From'] ?? '';
      if (FARLO_SENDER.test(extractEmailAddress(fromHeader))) {
        if (!dryRun) {
          await supabase
            .from('support_tickets')
            .update({ status: 'resolved', resolved_at: new Date().toISOString() })
            .eq('id', ticket.id);
        }
        closedCount++;
      }
    }

    await finishRun(
      supabase,
      runId,
      'success',
      `${finalText} Closed ${closedCount} resolved ticket(s) in Part 2.`,
      undefined,
      usage,
      MODEL_SONNET,
    );

    return new Response(
      JSON.stringify({
        open_tickets_processed: openTicketIds.length,
        tool_calls: toolCallLog,
        closed_count: closedCount,
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
