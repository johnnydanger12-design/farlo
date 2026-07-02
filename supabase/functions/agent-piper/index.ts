// Runs Tue/Thu 9:00. Copy-only for now — Canva visual generation is a separate,
// riskier integration (per-user OAuth, not a service-account model) attempted after this
// is proven working. Every piece ships queue-ready with needs_asset flagged for
// Instagram/TikTok pieces so Johnny (or a later Canva pass) knows a visual is still
// needed; nothing here is blocked on that working.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAgentSecret, isDryRun } from '../_shared/auth.ts';
import { startRun, finishRun } from '../_shared/run-log.ts';
import { runAgentLoop, MODEL_SONNET, type ToolDefinition } from '../_shared/claude-agent.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const BACKLOG_LIMIT = 6;

const SYSTEM_PROMPT = `You are Piper, the Farlo Marketing Agent. Every piece of content you produce must match brand_guidelines exactly — check it before writing anything.

This run, generate exactly 3 new pieces of content, chosen from: instagram, tiktok, x, facebook, email. Follow the channel priority in the marketing_focus directive. Never duplicate a caption/idea already in the queue you were given.

At least one of the 3 pieces must highlight a real use case — reference one of the real businesses you were given by name (an owner story, a menu highlight, an app-demo moment), not generic marketing copy.

For each piece, call queue_content once. Set needs_asset=true for instagram and tiktok pieces (no visual is generated yet — Johnny or a future pass adds one), false for x/facebook/email (text-only is fine for those).`;

const TOOLS: ToolDefinition[] = [
  {
    name: 'queue_content',
    description: 'Adds one piece of content to content_queue for Johnny to review and post manually.',
    input_schema: {
      type: 'object',
      properties: {
        platform: { type: 'string', enum: ['instagram', 'tiktok', 'x', 'facebook', 'email'] },
        caption: { type: 'string' },
        hashtags: { type: 'string' },
        visual_description: { type: 'string', description: 'For instagram/tiktok: a description of the visual concept, even though no asset is generated yet.' },
        needs_asset: { type: 'boolean' },
      },
      required: ['platform', 'caption'],
    },
  },
];

Deno.serve(async (req: Request) => {
  const authError = requireAgentSecret(req);
  if (authError) return authError;
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const dryRun = isDryRun(req);
  const runId = await startRun(supabase, 'agent-piper', dryRun ? 'dry_run' : undefined);

  try {
    const { data: queued, error: queuedError } = await supabase
      .from('content_queue')
      .select('id, platform, caption, created_at')
      .eq('status', 'queued')
      .order('created_at', { ascending: false });
    if (queuedError) throw new Error(`content_queue query failed: ${queuedError.message}`);

    if ((queued ?? []).length >= BACKLOG_LIMIT) {
      if (!dryRun) {
        await supabase
          .from('content_queue')
          .update({ notes: `Piper skipped ${new Date().toISOString().slice(0, 10)} — queue backlog.` })
          .eq('id', queued![0].id);
      }
      await finishRun(supabase, runId, 'success', `Skipped — queue has ${queued!.length} items, backlog limit is ${BACKLOG_LIMIT}.`);
      return new Response(JSON.stringify({ skipped: true, queue_size: queued!.length }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const { data: directives } = await supabase
      .from('agent_directives')
      .select('directive_key, content')
      .in('directive_key', ['brand_guidelines', 'company_story', 'farlo_context', 'company_direction', 'marketing_focus']);

    const { data: trucks } = await supabase
      .from('food_trucks')
      .select('name, cuisine_type, description')
      .eq('is_active', true)
      .limit(20);

    // deno-lint-ignore no-explicit-any
    const handlers: Record<string, any> = {
      queue_content: async (input: {
        platform: string;
        caption: string;
        hashtags?: string;
        visual_description?: string;
        needs_asset?: boolean;
      }) => {
        if (dryRun) return { dry_run: true, would_queue: input };
        const { error } = await supabase.from('content_queue').insert({
          platform: input.platform,
          caption: input.caption,
          hashtags: input.hashtags ?? null,
          visual_description: input.visual_description ?? null,
          needs_asset: input.needs_asset ?? false,
          status: 'queued',
        });
        return error ? { error: error.message } : { success: true };
      },
    };

    const userMessage = [
      `Directives:`,
      JSON.stringify(directives, null, 2),
      ``,
      `Real active businesses on Farlo (use for the real-use-case piece):`,
      JSON.stringify(trucks, null, 2),
      ``,
      `Already queued content this run must not duplicate:`,
      JSON.stringify(queued, null, 2),
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
      result.finalText || `${result.toolCallLog.length} piece(s) queued`,
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
