// Shared fragments for the two Aiden functions (agent-aiden-inbox,
// agent-aiden-supervisor) — both are "Aiden," both independently defined
// what a locked directive means and the exact directive_key enum, with zero
// shared prompt fragment (ai-agents.md §6/§7 Recommendation #3: a future
// change to "how Aiden talks" or a new directive key required editing two
// independently-drifting prompts). Centralizing here means a new directive
// key or a locked-row change only needs updating in one place.
import type { ToolDefinition } from './claude-agent.ts';

// Directive keys any Aiden function may write to via update_directive.
export const OPERATIONAL_DIRECTIVE_KEYS = [
  'company_direction',
  'farlo_context',
  'marketing_focus',
  'sales_targets',
  'support_kb',
  'website_content',
] as const;

// Directive keys that are permanent and Johnny-only — never touched via
// update_directive regardless of what a run's data suggests.
export const LOCKED_DIRECTIVE_KEYS = [
  'brand_guidelines',
  'company_story',
  'product_flows_owner',
  'product_flows_consumer',
] as const;

export const AIDEN_LOCKED_DIRECTIVES_NOTE =
  `Never touch a locked row (${LOCKED_DIRECTIVE_KEYS.join(', ')}) — these are permanent and Johnny-only.`;

export function updateDirectiveTool(description: string): ToolDefinition {
  return {
    name: 'update_directive',
    description,
    input_schema: {
      type: 'object',
      properties: {
        directive_key: { type: 'string', enum: [...OPERATIONAL_DIRECTIVE_KEYS] },
        content: { type: 'string', description: 'The full new content for this directive (replaces the existing value).' },
      },
      required: ['directive_key', 'content'],
    },
  };
}
