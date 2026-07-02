// Minimal Claude tool-use loop shared by every agent function. Raw fetch against the
// Messages API rather than the SDK, matching this codebase's existing no-heavy-dependency
// convention (see send-agent-email, send-truck-announcement).

export interface ToolDefinition {
  name: string;
  description: string;
  // deno-lint-ignore no-explicit-any
  input_schema: Record<string, any>;
}

// deno-lint-ignore no-explicit-any
export type ToolHandler = (input: Record<string, any>) => Promise<unknown>;

export interface AgentRunResult {
  finalText: string;
  toolCallLog: { name: string; input: unknown; result: unknown }[];
  iterations: number;
  stoppedReason: 'done' | 'time_budget' | 'max_iterations';
}

const ANTHROPIC_API_URL = 'https://api.anthropic.com/v1/messages';
const ANTHROPIC_VERSION = '2023-06-01';
export const MODEL_SONNET = 'claude-sonnet-5';
export const MODEL_HAIKU = 'claude-haiku-4-5-20251001';

const MAX_ITERATIONS = 30;
const MAX_MS = 8 * 60 * 1000; // safety budget within Edge Function wall-clock limits

export async function runAgentLoop(opts: {
  systemPrompt: string;
  userMessage: string;
  tools: ToolDefinition[];
  handlers: Record<string, ToolHandler>;
  model?: string;
  // Anthropic-hosted server-side tools (e.g. web_search) — passed through as-is.
  // deno-lint-ignore no-explicit-any
  hostedTools?: Record<string, any>[];
  maxTokens?: number;
}): Promise<AgentRunResult> {
  const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
  if (!apiKey) throw new Error('ANTHROPIC_API_KEY not configured');

  const model = opts.model ?? MODEL_SONNET;
  // deno-lint-ignore no-explicit-any
  const messages: Record<string, any>[] = [{ role: 'user', content: opts.userMessage }];
  const toolCallLog: { name: string; input: unknown; result: unknown }[] = [];
  const allTools = [...opts.tools, ...(opts.hostedTools ?? [])];
  const startedAt = Date.now();

  for (let iteration = 0; iteration < MAX_ITERATIONS; iteration++) {
    if (Date.now() - startedAt > MAX_MS) {
      return { finalText: '', toolCallLog, iterations: iteration, stoppedReason: 'time_budget' };
    }

    const res = await fetch(ANTHROPIC_API_URL, {
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': ANTHROPIC_VERSION,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model,
        max_tokens: opts.maxTokens ?? 4096,
        system: opts.systemPrompt,
        tools: allTools,
        messages,
      }),
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`Anthropic API error (${res.status}): ${errText}`);
    }

    // deno-lint-ignore no-explicit-any
    const data: any = await res.json();
    messages.push({ role: 'assistant', content: data.content });

    // deno-lint-ignore no-explicit-any
    const toolUseBlocks = (data.content ?? []).filter((b: any) => b.type === 'tool_use');

    if (toolUseBlocks.length === 0) {
      // deno-lint-ignore no-explicit-any
      const textBlock = (data.content ?? []).find((b: any) => b.type === 'text');
      return {
        finalText: textBlock?.text ?? '',
        toolCallLog,
        iterations: iteration + 1,
        stoppedReason: 'done',
      };
    }

    // deno-lint-ignore no-explicit-any
    const toolResults: Record<string, any>[] = [];
    for (const block of toolUseBlocks) {
      const handler = opts.handlers[block.name];
      let result: unknown;
      try {
        result = handler ? await handler(block.input) : { error: `no handler registered for tool ${block.name}` };
      } catch (err) {
        result = { error: String(err) };
      }
      toolCallLog.push({ name: block.name, input: block.input, result });
      toolResults.push({
        type: 'tool_result',
        tool_use_id: block.id,
        content: JSON.stringify(result),
      });
    }
    messages.push({ role: 'user', content: toolResults });
  }

  return { finalText: '', toolCallLog, iterations: MAX_ITERATIONS, stoppedReason: 'max_iterations' };
}
