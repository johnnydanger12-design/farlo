// ai-agents.md §7 Recommendation #7 — unified tool registry.
// Run with: deno test supabase/functions/_shared/tool-registry.test.ts
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { TOOL_REGISTRY } from './tool-registry.ts';

Deno.test('every registered tool has a non-empty name, at least one owning agent, and a write scope', () => {
  for (const tool of TOOL_REGISTRY) {
    assert(tool.name.length > 0, `tool missing a name: ${JSON.stringify(tool)}`);
    assert(tool.agents.length > 0, `${tool.name} has no owning agent listed`);
    assert(tool.effect.length > 0, `${tool.name} has no effect description`);
    assert(tool.writeScope.length > 0, `${tool.name} has no write-scope description`);
  }
});

Deno.test('no duplicate tool names in the registry', () => {
  const names = TOOL_REGISTRY.map((t) => t.name);
  assertEquals(new Set(names).size, names.length);
});
