// Runs daily 17:00. Mechanical classification — Haiku 4.5, doesn't read agent_directives.
// Label IDs are looked up by display name at runtime (getLabelIdMap) rather than
// hardcoded, since Gmail's generated label IDs are account-specific.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAgentSecret, isDryRun } from '../_shared/auth.ts';
import { startRun, finishRun } from '../_shared/run-log.ts';
import { getGmailAccessToken, searchThreads, getThread, getLabelIdMap, addLabel, removeLabel } from '../_shared/gmail.ts';
import { runAgentLoop, MODEL_HAIKU, type ToolDefinition } from '../_shared/claude-agent.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const LABEL_NAMES = ['Support', 'Aiden', 'Finance', 'Business', 'Newsletters', 'Security', 'Personal'] as const;

const SYSTEM_PROMPT = `You are an email organizer for johnny@farlo.app (which also receives mail via the alias support@farlo.app). Classify each unlabeled thread you're given into exactly one label, or skip it if genuinely ambiguous.

Rules, in order:
- Any thread delivered TO support@farlo.app -> Support, regardless of content. Check this first.
- Any thread FROM aiden@farlo.app -> Aiden.
- Finance: bank statements, payment receipts, invoices, financial transactions (e.g. Bank of America, payment confirmations, Stripe payment notifications).
- Business: business setup/ops, DocuSign, legal filings, product onboarding, account activations (e.g. Stripe account setup, Odoo, ZenBusiness filings, Google Workspace/Play Console admin).
- Newsletters: marketing/promotional email, unsolicited pitches, "here's how to get started" tips content.
- Security: verification codes, OTP/2FA, login alerts, API key rotations — anything with a numeric code to enter.
- Personal: real human-to-human email that reads like a person wrote it, not a template or automated system.
- The same sender can send different categories of mail — classify by actual content, not just sender identity (e.g. a payment receipt from a vendor is Finance even if that vendor also sends Business-type mail elsewhere).
- If genuinely unsure, don't call the tool for that thread at all — leave it unlabeled rather than guess wrong.

Call apply_label once per thread you can confidently classify.`;

const TOOLS: ToolDefinition[] = [
  {
    name: 'apply_label',
    description: 'Applies one label to a thread and its category-specific follow-up action (Newsletters get archived out of the inbox; Support, Aiden, and Personal get marked Important).',
    input_schema: {
      type: 'object',
      properties: {
        thread_id: { type: 'string' },
        label: { type: 'string', enum: [...LABEL_NAMES] },
      },
      required: ['thread_id', 'label'],
    },
  },
];

Deno.serve(async (req: Request) => {
  const authError = requireAgentSecret(req);
  if (authError) return authError;
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const dryRun = isDryRun(req);
  const runId = await startRun(supabase, 'agent-email-labeler', dryRun ? 'dry_run' : undefined);

  try {
    const accessToken = await getGmailAccessToken('johnny@farlo.app');
    const labelIds = await getLabelIdMap(accessToken);

    const threads = await searchThreads(accessToken, 'in:inbox newer_than:2d has:nouserlabels', 50);

    // deno-lint-ignore no-explicit-any
    const candidates: any[] = [];
    for (const t of threads) {
      const full = await getThread(accessToken, t.id);
      // deno-lint-ignore no-explicit-any
      const messages: any[] = full.messages ?? [];
      if (messages.length === 0) continue;
      const first = messages[0];
      // deno-lint-ignore no-explicit-any
      const headers = Object.fromEntries((first.payload?.headers ?? []).map((h: any) => [h.name, h.value]));
      candidates.push({
        thread_id: t.id,
        to: headers['To'] ?? '',
        from: headers['From'] ?? '',
        subject: headers['Subject'] ?? '',
        snippet: first.snippet ?? '',
      });
    }

    if (candidates.length === 0) {
      await finishRun(supabase, runId, 'success', 'Inbox up to date — nothing new to label.');
      return new Response(JSON.stringify({ candidates: 0 }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // deno-lint-ignore no-explicit-any
    const handlers: Record<string, any> = {
      apply_label: async (input: { thread_id: string; label: string }) => {
        const labelId = labelIds[input.label];
        if (!labelId) return { error: `no label ID found for "${input.label}"` };
        if (dryRun) return { dry_run: true, would_apply: input };
        await addLabel(accessToken, input.thread_id, labelId);
        if (input.label === 'Newsletters' && labelIds['INBOX']) {
          await removeLabel(accessToken, input.thread_id, labelIds['INBOX']);
        }
        if ((input.label === 'Support' || input.label === 'Aiden' || input.label === 'Personal') && labelIds['IMPORTANT']) {
          await addLabel(accessToken, input.thread_id, labelIds['IMPORTANT']);
        }
        return { success: true };
      },
    };

    const userMessage = `Unlabeled threads from the last 2 days:\n${JSON.stringify(candidates, null, 2)}`;

    const result = await runAgentLoop({
      systemPrompt: SYSTEM_PROMPT,
      userMessage,
      tools: TOOLS,
      handlers,
      model: MODEL_HAIKU,
    });

    const supportCount = result.toolCallLog.filter(
      // deno-lint-ignore no-explicit-any
      (c: any) => c.name === 'apply_label' && c.input?.label === 'Support',
    ).length;

    const status = result.stoppedReason === 'done' ? 'success' : 'partial';
    await finishRun(
      supabase,
      runId,
      status,
      `${supportCount > 0 ? `⚠ ${supportCount} Support email(s). ` : ''}${result.finalText || `${result.toolCallLog.length} labeled`}`,
    );

    return new Response(
      JSON.stringify({ candidates: candidates.length, tool_calls: result.toolCallLog, dry_run: dryRun }),
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
