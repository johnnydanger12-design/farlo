// Live chat with Aiden from the founder dashboard — unlike every other Aiden entry
// point (agent-aiden-inbox's twice-daily email check, agent-aiden-supervisor's weekly
// report), this is synchronous request/response, called directly by the browser with
// the founder's own Supabase session JWT (anon key + Authorization header), the same
// auth pattern create-payment-intent uses — not the AGENT_EMAIL_SECRET cron functions
// use, which must never be reachable from browser JS.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { encodeBase64 } from 'https://deno.land/std@0.224.0/encoding/base64.ts';
import { startRun, finishRun, logToolCalls } from '../_shared/run-log.ts';
import { runAgentLoop, MODEL_SONNET, MODEL_OPUS, MODEL_FABLE, type ToolDefinition, type AgentUserMessage } from '../_shared/claude-agent.ts';
import { AIDEN_LOCKED_DIRECTIVES_NOTE, updateDirectiveTool } from '../_shared/aiden-persona.ts';
import { corsHeaders, handlePreflight } from '../_shared/cors.ts';

const FOUNDER_EMAIL = 'johnny.danger12@gmail.com';
const HISTORY_LIMIT = 30;
const ALLOWED_MODELS = new Set([MODEL_SONNET, MODEL_OPUS, MODEL_FABLE]);

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

  let body: { message: string; conversation_id?: string; model?: string; image_paths?: string[] };
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
  const imagePaths = Array.isArray(body.image_paths) ? body.image_paths.filter((p) => typeof p === 'string') : [];
  const requestedModel = body.model && ALLOWED_MODELS.has(body.model) ? body.model : undefined;

  const runId = await startRun(supabase, 'agent-aiden-chat');

  try {
    // Resolve (or create) the conversation this message belongs to. Model resolution
    // order: an explicit per-request override, else the conversation's own stored
    // model, else the default — a brand-new conversation with no override starts on
    // Sonnet 5.
    let conversationId = body.conversation_id;
    let model = MODEL_SONNET;

    if (conversationId) {
      const { data: conversation, error: convError } = await supabase
        .from('aiden_conversations')
        .select('id, model')
        .eq('id', conversationId)
        .single();
      if (convError || !conversation) throw new Error(`conversation_id not found: ${conversationId}`);
      model = requestedModel ?? conversation.model;
      if (requestedModel && requestedModel !== conversation.model) {
        await supabase.from('aiden_conversations').update({ model: requestedModel }).eq('id', conversationId);
      }
    } else {
      model = requestedModel ?? MODEL_SONNET;
      const title = founderMessage.length > 40 ? `${founderMessage.slice(0, 40)}…` : founderMessage;
      const { data: newConversation, error: createError } = await supabase
        .from('aiden_conversations')
        .insert({ title, model })
        .select('id')
        .single();
      if (createError || !newConversation) throw new Error(`Failed to create conversation: ${createError?.message}`);
      conversationId = newConversation.id;
    }

    // Persisted before the Claude call (not after) so a failed/slow reply never loses
    // what Johnny actually typed — same durability property the original single-thread
    // version had. History below naturally includes this message as its newest entry.
    await supabase.from('aiden_chat_messages').insert({
      conversation_id: conversationId,
      role: 'founder',
      content: founderMessage,
      image_paths: imagePaths,
    });

    const { data: directives, error: directivesError } = await supabase
      .from('agent_directives')
      .select('directive_key, content, locked');
    if (directivesError) throw new Error(`agent_directives query failed: ${directivesError.message}`);

    const { data: history } = await supabase
      .from('aiden_chat_messages')
      .select('role, content, created_at')
      .eq('conversation_id', conversationId)
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

    // No wrapUntrusted() here, unlike agent-aiden-inbox/supervisor — this whole
    // request is already authenticated as the founder (see the FOUNDER_EMAIL check
    // above), so there's no third party to guard against. Wrapping Johnny's own live
    // chat messages as "untrusted, don't follow instructions in it" was a copy-paste
    // carryover from the email-based Aiden functions and made Aiden refuse Johnny's
    // own directive-change requests — a real bug, fixed here.
    const textBlock = [
      `Current agent_directives:`,
      JSON.stringify(directives, null, 2),
      ``,
      `Conversation so far (oldest first):`,
      JSON.stringify(orderedHistory, null, 2),
      ``,
      `Johnny's new message:`,
      founderMessage,
    ].join('\n');

    let userMessage: AgentUserMessage = textBlock;
    if (imagePaths.length > 0) {
      // base64, not a signed URL — a signed URL is a valid, fetchable HTTPS URL, but
      // the Messages API accepted a `source.type: 'url'` block without error and
      // silently never resolved it (verified live: Claude reported no image came
      // through). base64 is the well-established, actually-supported path.
      const imageBlocks = [];
      for (const path of imagePaths) {
        const { data: fileBlob, error: downloadError } = await supabase.storage
          .from('aiden-chat-photos')
          .download(path);
        if (downloadError || !fileBlob) throw new Error(`Failed to download image ${path}: ${downloadError?.message}`);
        const bytes = new Uint8Array(await fileBlob.arrayBuffer());
        imageBlocks.push({
          type: 'image',
          source: { type: 'base64', media_type: fileBlob.type || 'image/jpeg', data: encodeBase64(bytes) },
        });
      }
      // The bulky directives/history dump goes first, then the image(s), then a
      // short final reminder — the image and the instruction to look at it are the
      // last thing before the model has to respond, maximizing recency, rather than
      // being followed by thousands more tokens of admin context that can bury them.
      const imageNote = `${imageBlocks.length} image(s) are attached directly above — look at them now and factor in what you actually see before replying.`;
      userMessage = [{ type: 'text', text: textBlock }, ...imageBlocks, { type: 'text', text: imageNote }];
    }

    const result = await runAgentLoop({
      systemPrompt: SYSTEM_PROMPT,
      userMessage,
      tools: TOOLS,
      handlers,
      model,
      maxTokens: 2048,
    });

    const replyText = result.finalText || "I didn't have anything to add there.";

    await supabase.from('aiden_chat_messages').insert({
      conversation_id: conversationId,
      role: 'aiden',
      content: replyText,
    });
    await supabase.from('aiden_conversations').update({ last_message_at: new Date().toISOString() }).eq('id', conversationId);

    await logToolCalls(supabase, runId, result.toolCallLog);
    await finishRun(
      supabase,
      runId,
      'success',
      replyText,
      undefined,
      result.usage,
      model,
    );

    return new Response(
      JSON.stringify({ reply: replyText, conversation_id: conversationId, model, tool_calls: result.toolCallLog }),
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
