// Ported from supabase/functions/_shared/pricing.ts (Deno can't be imported directly
// from a browser bundle) — keep these two files in sync if rates or the price-change
// date ever move. Published rates from platform.claude.com/docs/en/about-claude/pricing
// (checked Jul 2 2026), reconstructed from token counts logged by the agents
// themselves — an estimate, not a reconciliation against Anthropic's actual invoice.

export interface UsageTotals {
  inputTokens: number;
  outputTokens: number;
  cacheCreationTokens: number;
  cacheReadTokens: number;
  webSearchRequests: number;
}

interface Rates {
  input: number; // $ per token
  output: number;
  cacheRead: number;
}

const SONNET_5_INTRO: Rates = { input: 2 / 1_000_000, output: 10 / 1_000_000, cacheRead: 0.20 / 1_000_000 };
const SONNET_5_STANDARD: Rates = { input: 3 / 1_000_000, output: 15 / 1_000_000, cacheRead: 0.30 / 1_000_000 };
const SONNET_5_PRICE_CHANGE = new Date('2026-09-01T00:00:00Z');

const HAIKU_4_5: Rates = { input: 1 / 1_000_000, output: 5 / 1_000_000, cacheRead: 0.10 / 1_000_000 };

const WEB_SEARCH_COST_PER_SEARCH = 10 / 1000;

function ratesFor(model: string, asOf: Date): Rates {
  if (model.includes('haiku')) return HAIKU_4_5;
  return asOf >= SONNET_5_PRICE_CHANGE ? SONNET_5_STANDARD : SONNET_5_INTRO;
}

export function estimateCostUsd(model: string, usage: UsageTotals, asOf: Date = new Date()): number {
  const rates = ratesFor(model, asOf);
  const tokenCost =
    usage.inputTokens * rates.input +
    usage.outputTokens * rates.output +
    usage.cacheReadTokens * rates.cacheRead;
  const searchCost = usage.webSearchRequests * WEB_SEARCH_COST_PER_SEARCH;
  return tokenCost + searchCost;
}
