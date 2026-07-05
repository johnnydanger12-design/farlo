# Farlo — Agent Architecture Decision Doc (Phase 6, P6-3 / Phase 5, ARCH-7)

**Status: decided, as of iteration 8.** No near-term plans for an agent whose inputs would overlap an existing one, so the doc's own default recommendation (§4) applies as-is: **Option A — formalize the current model, don't build a dispatcher now.** Revisit Option B specifically if/when a consumer-engagement or review-response agent (`ai-agents.md` §5 #3/#4) actually gets built. Kept in `audit/` for the reasoning, not as an open question anymore.

**Source:** `audit/ai-agents.md` §4 (Orchestration Topology), §5 (Missing Agents), §7 (Future Architecture Recommendations #4), §8 (Cross-Agent Comparison Matrix); `FARLO_FINAL_AUDIT.md`'s Top 20 #19 equivalent and its own framing ("Decide, deliberately, whether the agent fleet needs a real supervisor/dispatcher or should formalize its current... model").

---

## 1. What actually exists today (not what the naming implies)

Farlo runs 10 `pg_cron`-scheduled Edge Functions branded as an "agent fleet" (Sage/support, Miles/sales, Piper/marketing, Aiden-Inbox and Aiden-Supervisor, plus 5 mechanical/ops functions). `ai-agents.md` §4 confirmed, by reading every tool handler in every function, that **there is no runtime agent-to-agent invocation anywhere in the codebase** — no agent calls another agent's Edge Function, no agent passes live conversational context to another agent synchronously. The only cross-function HTTP call in the entire system is `agent-miles` calling the stateless (non-LLM) `prospect-businesses` data-fetch tool.

What actually coordinates the fleet is **shared Postgres state** — `agent_directives`, `supervisor_reports`, `agent_run_log`, and the various `support_tickets`/`sales_prospects`/`content_queue` tables each agent reads and writes on its own cron schedule. Aiden-Inbox and Aiden-Supervisor are the closest thing to a "supervisor" in that they're the only functions with write access to `agent_directives`, but that's asynchronous directive-editing (steering *future* runs), not live routing of a specific inbound signal to a specific agent in real time. "Routing" today is 100% structural: an email to `support@farlo.app` goes to Sage because of the mailbox it lands in, not because anything decided that.

**This is a real, working system today** — it's not broken, and `ai-agents.md`'s scores (6.5/10 average across Sage/Miles/Piper, the two Aiden functions at 4/10 driven mostly by the sender-trust gaps already fixed in this remediation pass's Phase 1) reflect a functioning if architecturally informal setup. The question is whether it stays informal as the fleet grows, or gets a real coordinating layer.

## 2. The actual decision

**Option A — Formalize the current model.** Keep "independent cron jobs + shared Postgres config" as the deliberate, chosen architecture (not an accident of implementation, which is how it reads today) and invest instead in:
- A shared prompt/persona template module (`ai-agents.md` §7 Recommendation #3) — closes the "two independently-drifting Aiden voices" maintainability risk from §6.
- An explicit trust-boundary convention for untrusted text entering any prompt (§7 Recommendation #2) — this is largely done already via this remediation pass's sender-allowlist fixes, but a reusable `<untrusted-input>` framing convention would generalize it.
- Better observability (§7 Recommendation #6) — per-tool-call tracing beyond today's one-row-per-run `agent_run_log`.
- A unified tool registry (§7 Recommendation #7) so least-privilege auditing doesn't require a full manual read of every function (which is what producing `ai-agents.md` itself required).

**Option B — Build a real dispatcher/router.** A genuine routing layer that can look at an ambiguous inbound signal and decide which agent (or human) should handle it, rather than routing being hardcoded by mailbox/table. This becomes necessary, not optional, the moment Farlo adds an agent whose candidate inputs overlap with an existing one — `ai-agents.md` §5 names two concrete candidates already missing today (a consumer-engagement agent, a review-response agent) that would create exactly this overlap if built under the current structural-routing model.

## 3. What should actually drive this choice

This isn't a question with a universally correct answer — it depends on near-term product plans this remediation pass has no visibility into:

- **If the plan is to add more agents with overlapping inputs soon** (e.g., a review-response agent that might also want to draft the same kind of message a support agent drafts, or a consumer-engagement agent whose signals could plausibly also matter to the sales/marketing agents) — Option B's routing problem is coming regardless, and it's cheaper to build the routing layer before adding the 2nd/3rd overlapping agent than to retrofit it after.
- **If the near-term plan is "keep the current four+ov-op agents, maybe add one more narrowly-scoped one" (e.g., just the churn/re-engagement agent from §5, which has a clean non-overlapping trigger — `owner hasn't opened in N days` — same shape as the existing cron-triggered agents)** — Option A is very likely the right call. Building a dispatcher for a system where routing is still unambiguous is premature infrastructure.
- **Either way, Option A's four sub-items (shared prompts, trust-boundary convention, observability, tool registry) are worth doing regardless of which path is chosen** — they're not in tension with Option B, they're prerequisites for it being safe to build (a dispatcher routing into agents that don't share a trust-boundary convention or a tool registry is arguably worse than no dispatcher, since it adds a new component with the same undifferentiated-trust problem `ai-agents.md`'s Top Risks already flagged).

## 4. Decision (settled iteration 8)

**Option A — formalize the current independent-cron model, don't build a dispatcher now.** Confirmed directly: no near-term plans for an agent whose inputs would overlap an existing one. This is the lower-commitment path: it doesn't foreclose Option B later, and its four sub-items (shared prompt/persona layer, trust-boundary convention, observability beyond `agent_run_log`, unified tool registry) are worth doing regardless of the dispatcher question — they're real, already-identified maintainability/trust gaps, not busywork.

**Revisit Option B specifically if/when a consumer-engagement or review-response agent (`ai-agents.md` §5 items #3/#4) actually gets built** — that's the concrete trigger condition, not a vague "someday." Until then, building a dispatcher would be solving a routing problem Farlo doesn't have yet, at the cost of engineering time the cold-start plan (see the companion GTM memo) more urgently needs.

**Update (iteration 10, A+ pass): all four sub-items are now actually implemented, not just documented as backlog.**
1. Shared prompt/persona layer — `_shared/aiden-persona.ts` (iteration 9).
2. Trust-boundary convention for untrusted text — `_shared/prompt-boundaries.ts`'s `wrapUntrusted()` (iteration 9).
3. **Observability beyond `agent_run_log`** — new `agent_tool_call_log` table (migration `20260705045851_create_agent_tool_call_log.sql`) gives every individual tool call its own row (tool name, input, result, sequence), linked to its parent run. `runAgentLoop()`'s in-memory `toolCallLog` was previously only returned in the HTTP response body, invisible for any cron-triggered run nobody is watching live. Wired into all 7 agent functions that use the shared tool-use loop (`agent-sage`, `agent-miles`, `agent-piper`, `agent-aiden-inbox`, `agent-aiden-supervisor`, `agent-email-labeler`, `agent-stripe-weekly`) via a new `logToolCalls()` helper in `_shared/run-log.ts`. Verified live: deployed all 7, confirmed `verify_jwt` stayed `false` on every one, ran a live dry-run smoke test against `agent-sage`.
4. **Unified tool registry** — new `_shared/tool-registry.ts` catalogs every tool across every agent (name, owning agent(s), real-world effect, write scope) in one place, closing the "would make future audits tractable" gap directly — a future audit or security review can read this one file instead of every agent's handler code to get a least-privilege overview. Deliberately a catalog, not a forced shared-import of tool definitions themselves (no two agents currently implement the same tool except `update_directive`, which already lives in `aiden-persona.ts` — forcing artificial sharing elsewhere would add coupling with no real benefit).

All four are covered by permanent Deno tests (2 for the tool-call-log row mapping, 2 for the registry's structural integrity) — see `REMEDIATION_LOG.md` iteration 10.

## 5. What doesn't wait on this decision

Independent of Option A vs. B, `ai-agents.md` §7's recommendation #5 (per-function credentials instead of one shared bearer + one shared Gmail identity, already flagged in `AGENT_AUTOMATION_RUNBOOK.md` as a known, accepted gap) and #8 (watch the watchdog — nothing currently alerts if `agent-run-check` itself stops running) are both real, scoped, non-architectural fixes that don't depend on this decision at all and could be picked up as their own Fix-Protocol items whenever there's capacity, the same way MFR-6 (Ad Boost payment-model guardrail) sits as a watch item today.
