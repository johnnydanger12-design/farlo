// Runs Mon/Wed/Fri 8:00. Batches to 5 uncontacted prospects per invocation to stay
// comfortably inside the tool-call/time budget (each prospect needs several web_search
// round trips) — the sales_prospects.status column is the natural work queue, so any
// prospect not reached this run just waits for the next one. Newly-fetched prospects
// from fetch_new_prospects land as 'uncontacted' and are picked up on a LATER run, not
// immediately — keeps each run's context bounded to prospects it already has full
// detail on.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAgentSecret, isDryRun } from '../_shared/auth.ts';
import { startRun, finishRun } from '../_shared/run-log.ts';
import { getGmailAccessToken, createDraft } from '../_shared/gmail.ts';
import { runAgentLoop, MODEL_SONNET, type ToolDefinition } from '../_shared/claude-agent.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const BATCH_SIZE = 5;

const SYSTEM_PROMPT = `You are Miles, the Farlo Sales Agent.

HARD RULE, CHECK FIRST: if the sales_targets directive says outreach is on HOLD, call no tools at all this run. Just explain why in your final text and stop — do not fetch prospects, do not research, do not draft anything, even if that seems conservative. A HOLD means fully stop, not "hold on sending but keep prepping."

If outreach is NOT on hold, do this in order:
1. Call fetch_new_prospects with the current primary target city per the sales_targets directive.
2. You'll be given up to ${BATCH_SIZE} uncontacted prospects with full detail to work through this run. For each, use web_search to research their website, social media, and Google listing for a contact email.
3. No email found -> call mark_no_email_found with a short note. Never guess or invent an email address.
4. Email found -> write a bespoke, under-100-word cold email that references something specific and real about that business (never a generic template). Pitch: Farlo puts local food businesses on a discovery map, flat $29.99/mo, no 30% commission like delivery apps. Then call draft_outreach. Do not send anything — draft_outreach only creates a Gmail draft for Johnny to review.

You will be given a list of business names that are already Farlo customers (via the food_trucks table) — never draft outreach to any of them, even if they appear in your prospect batch by mistake.`;

const TOOLS: ToolDefinition[] = [
  {
    name: 'fetch_new_prospects',
    description: 'Pulls fresh prospect businesses for a city from Google Places into sales_prospects. New rows land as uncontacted for a future run, not this one.',
    input_schema: {
      type: 'object',
      properties: { city: { type: 'string', description: 'e.g. "Florence, SC"' } },
      required: ['city'],
    },
  },
  {
    name: 'mark_no_email_found',
    description: 'Leaves a prospect uncontacted with a note that it is worth manual/in-person outreach.',
    input_schema: {
      type: 'object',
      properties: {
        prospect_id: { type: 'string' },
        note: { type: 'string' },
      },
      required: ['prospect_id', 'note'],
    },
  },
  {
    name: 'draft_outreach',
    description: 'Creates a Gmail draft cold email from outreach@farlo.app. Never sends — Johnny reviews and sends.',
    input_schema: {
      type: 'object',
      properties: {
        prospect_id: { type: 'string' },
        email: { type: 'string' },
        subject: { type: 'string' },
        body: { type: 'string' },
      },
      required: ['prospect_id', 'email', 'subject', 'body'],
    },
  },
];

const HOSTED_TOOLS = [{ type: 'web_search_20250305', name: 'web_search' }];

Deno.serve(async (req: Request) => {
  const authError = requireAgentSecret(req);
  if (authError) return authError;
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const dryRun = isDryRun(req);
  const runId = await startRun(supabase, 'agent-miles', dryRun ? 'dry_run' : undefined);

  try {
    const { data: directives } = await supabase
      .from('agent_directives')
      .select('directive_key, content')
      .in('directive_key', ['sales_targets', 'brand_guidelines', 'farlo_context', 'company_direction']);

    const { data: existingTrucks } = await supabase.from('food_trucks').select('name');
    const existingNames = new Set((existingTrucks ?? []).map((t) => t.name.toLowerCase().trim()));

    const { data: uncontacted } = await supabase
      .from('sales_prospects')
      .select('id, business_name, business_type, address, city, state, phone, website')
      .eq('status', 'uncontacted')
      .limit(50);

    const eligible = (uncontacted ?? [])
      .filter((p) => !existingNames.has(p.business_name.toLowerCase().trim()))
      .slice(0, BATCH_SIZE);

    const accessToken = await getGmailAccessToken('johnny@farlo.app');

    // deno-lint-ignore no-explicit-any
    const handlers: Record<string, any> = {
      fetch_new_prospects: async (input: { city: string }) => {
        if (dryRun) return { dry_run: true, would_fetch: input.city };
        const res = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/prospect-businesses`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ city: input.city }),
        });
        return await res.json();
      },
      mark_no_email_found: async (input: { prospect_id: string; note: string }) => {
        const prospect = eligible.find((p) => p.id === input.prospect_id);
        if (!prospect) return { error: `unknown prospect_id ${input.prospect_id}` };
        if (dryRun) return { dry_run: true, would_note: input };
        const { error } = await supabase
          .from('sales_prospects')
          .update({ response_notes: input.note, updated_at: new Date().toISOString() })
          .eq('id', input.prospect_id);
        return error ? { error: error.message } : { success: true };
      },
      draft_outreach: async (input: { prospect_id: string; email: string; subject: string; body: string }) => {
        const prospect = eligible.find((p) => p.id === input.prospect_id);
        if (!prospect) return { error: `unknown prospect_id ${input.prospect_id}` };
        if (existingNames.has(prospect.business_name.toLowerCase().trim())) {
          return { error: `${prospect.business_name} is already a Farlo customer — refusing to draft outreach` };
        }
        if (dryRun) return { dry_run: true, would_draft: input };
        await createDraft(accessToken, {
          from: 'Miles | Farlo <outreach@farlo.app>',
          to: input.email,
          subject: input.subject,
          bodyText: input.body,
        });
        const { error } = await supabase
          .from('sales_prospects')
          .update({
            status: 'contacted',
            outreach_email: input.email,
            last_contacted_at: new Date().toISOString(),
            response_notes: 'Draft saved - not yet sent',
          })
          .eq('id', input.prospect_id);
        return error ? { error: error.message } : { success: true };
      },
    };

    const userMessage = [
      `Directives:`,
      JSON.stringify(directives, null, 2),
      ``,
      `Business names already on Farlo (never contact these):`,
      JSON.stringify([...existingNames]),
      ``,
      `Uncontacted prospects available this run (up to ${BATCH_SIZE}):`,
      JSON.stringify(eligible, null, 2),
    ].join('\n');

    const result = await runAgentLoop({
      systemPrompt: SYSTEM_PROMPT,
      userMessage,
      tools: TOOLS,
      handlers,
      hostedTools: HOSTED_TOOLS,
      model: MODEL_SONNET,
      maxTokens: 8192,
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
        eligible_this_run: eligible.length,
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
