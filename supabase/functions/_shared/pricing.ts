// Estimated cost calculation from token usage, using published rates from
// platform.claude.com/docs/en/about-claude/pricing (Sonnet 5/Haiku 4.5 checked Jul 2
// 2026; Opus 4.8/Fable 5 added checked Jul 8 2026). This is an estimate reconstructed
// from token counts we log ourselves, not a reconciliation against Anthropic's actual
// invoice — good enough for "roughly what is this costing me" in a weekly brief, not
// precise to the cent.
//
// Sonnet 5 has scheduled introductory pricing through Aug 31 2026, then a real price
// increase — this file needs no further updates for that since it's date-gated below,
// but if pricing changes again after that, update SONNET_5_STANDARD (and re-check the
// other models below, none of which have an announced future change as of this
// writing).

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
const OPUS_4_8: Rates = { input: 5 / 1_000_000, output: 25 / 1_000_000, cacheRead: 0.50 / 1_000_000 };
const FABLE_5: Rates = { input: 10 / 1_000_000, output: 50 / 1_000_000, cacheRead: 1.00 / 1_000_000 };

const WEB_SEARCH_COST_PER_SEARCH = 10 / 1000;

function ratesFor(model: string, asOf: Date): Rates {
  if (model.includes('haiku')) return HAIKU_4_5;
  if (model.includes('opus')) return OPUS_4_8;
  if (model.includes('fable')) return FABLE_5;
  // Everything else in this system is Sonnet 5.
  return asOf >= SONNET_5_PRICE_CHANGE ? SONNET_5_STANDARD : SONNET_5_INTRO;
}

export function estimateCostUsd(model: string, usage: UsageTotals, asOf: Date = new Date()): number {
  const rates = ratesFor(model, asOf);
  const tokenCost =
    usage.inputTokens * rates.input +
    usage.outputTokens * rates.output +
    usage.cacheReadTokens * rates.cacheRead;
  // Cache writes aren't tracked separately here (we don't set cache_control on
  // requests today, so cache_creation_tokens should be 0 in practice) — if that
  // changes, add a cache-write rate the same way cacheRead is handled above.
  const searchCost = usage.webSearchRequests * WEB_SEARCH_COST_PER_SEARCH;
  return tokenCost + searchCost;
}
