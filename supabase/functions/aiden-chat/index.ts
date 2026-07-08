// Live chat with Aiden from the founder dashboard — unlike every other Aiden entry
// point (agent-aiden-inbox's twice-daily email check, agent-aiden-supervisor's weekly
// report), this is synchronous request/response, called directly by the browser with
// the founder's own Supabase session JWT (anon key + Authorization header), the same
// auth pattern create-payment-intent uses — not the AGENT_EMAIL_SECRET cron functions
// use, which must never be reachable from browser JS.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { startRun, finishRun, logToolCalls } from '../_shared/run-log.ts';
import { runAgentLoop, MODEL_SONNET, type ToolDefinition } from '../_shared/claude-agent.ts';
import { AIDEN_LOCKED_DIRECTIVES_NOTE, updateDirectiveTool } from '../_shared/aiden-persona.ts';
import { wrapUntrusted } from '../_shared/prompt-boundaries.ts';
import { corsHeaders, handlePreflight } from '../_shared/cors.ts';

const FOUNDER_EMAIL = 'johnny.danger12@gmail.com';
const HISTORY_LIMIT = 30;

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const SYSTEM_PROMPT = `You are Aiden, Farlo's Supervisor Agent, chatting live with Johnny (the founder) through his dashboard. This is a real-time conversation, not an email — be direct and conversational, no "Hi Johnny," no email-style sign-offs, no unnecessary preamble.

You have live access to the current agent_directives (given below) and can update any operational one via update_directive if Johnny asks you to change direction, priorities, or instructions for Sage, Miles, Piper, or yourself. ${AIDEN_LOCKED_DIRECTIVES_NOTE}

If Johnny asks a question about the business, the app, or what the agents are doing, answer from the context you're given below. If something isn't in your context, say so plainly rather than guessing. Keep replies focused — this is a chat, not a report.`;

const TOOLS: ToolDefinition[] = [
  updateDirectiveTool('Update an operational agent_directives row (locked=false only). Fails if the key does not exist or is locked.'),
];

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;

  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: corsHeaders(req) });

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return new Response('Unauthorized', { status: 401, headers: corsHeaders(req) });

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user || user.email !== FOUNDER_EMAIL) {
    return new Response('Unauthorized', { status: 401, headers: corsHeaders(req) });
  }

  let body: { message: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
      status: 400,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
  if (!body.message || typeof body.message !== 'string' || !body.message.trim()) {
    return new Response(JSON.stringify({ error: 'message is required' }), {
      status: 400,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
  const founderMessage = body.message.trim();

  const runId = await startRun(supabase, 'agent-aiden-chat');

  try {
    await supabase.from('aiden_chat_messages').insert({ role: 'founder', content: founderMessage });

    const { data: directives, error: directivesError } = await supabase
      .from('agent_directives')
      .select('directive_key, content, locked');
    if (directivesError) throw new Error(`agent_directives query failed: ${directivesError.message}`);

    const { data: history } = await supabase
      .from('aiden_chat_messages')
      .select('role, content, created_at')
      .order('created_at', { ascending: false })
      .limit(HISTORY_LIMIT);
    const orderedHistory = (history ?? []).slice().reverse();

    const lockedKeys = new Set((directives ?? []).filter((d) => d.locked).map((d) => d.directive_key));

    // deno-lint-ignore no-explicit-any
    const handlers: Record<string, any> = {
      update_directive: async (input: { directive_key: string; content: string }) => {
        if (lockedKeys.has(input.directive_key)) {
          return { error: `${input.directive_key} is locked — cannot update` };
        }
        const { error } = await supabase
          .from('agent_directives')
          .update({ content: input.content, updated_by: 'aiden', updated_at: new Date().toISOString() })
          .eq('directive_key', input.directive_key);
        return error ? { error: error.message } : { success: true };
      },
    };

    const userMessage = [
      `Current agent_directives:`,
      JSON.stringify(directives, null, 2),
      ``,
      `Conversation so far (oldest first):`,
      wrapUntrusted('chat-history', JSON.stringify(orderedHistory, null, 2)),
      ``,
      `Johnny's new message:`,
      wrapUntrusted('chat-new-message', founderMessage),
    ].join('\n');

    const result = await runAgentLoop({
      systemPrompt: SYSTEM_PROMPT,
      userMessage,
      tools: TOOLS,
      handlers,
      model: MODEL_SONNET,
      maxTokens: 2048,
    });

    const replyText = result.finalText || "I didn't have anything to add there.";
    await supabase.from('aiden_chat_messages').insert({ role: 'aiden', content: replyText });

    await logToolCalls(supabase, runId, result.toolCallLog);
    await finishRun(
      supabase,
      runId,
      'success',
      replyText,
      undefined,
      result.usage,
      MODEL_SONNET,
    );

    return new Response(
      JSON.stringify({ reply: replyText, tool_calls: result.toolCallLog }),
      { status: 200, headers: { ...corsHeaders(req), 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    await finishRun(supabase, runId, 'failed', undefined, String(err));
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
});
