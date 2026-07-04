# Farlo — Agent Architecture Decision Doc (Phase 6, P6-3 / Phase 5, ARCH-7)

**Status: a decision doc, not a decision.** This lays out the actual question `ai-agents.md` and `FARLO_FINAL_AUDIT.md` raise — whether to build a real agent dispatcher/supervisor or formalize the current "independent cron jobs + shared config" model — with the tradeoffs made concrete, so you can make the call rather than have it made for you. This is exactly the kind of architecture decision the remediation protocol treats as needing your sign-off before code gets written, not something to decide autonomously.

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

## 4. Recommendation, if a default is needed

**Option A, for now, with the four sub-items as real backlog items** (not urgent, but real) **— revisit Option B specifically if/when either of the two "missing agents" most likely to create routing overlap (`ai-agents.md` §5 items #3 consumer-engagement, #4 review-response) actually gets built.** This is the lower-commitment path: it doesn't foreclose Option B later, and it fixes real, already-identified maintainability/trust gaps (§6's prompt-drift risk, the trust-boundary convention) that are worth doing independent of the dispatcher question. Building a dispatcher today, before there's a second agent that actually needs routing, would be solving a problem Farlo doesn't have yet at the cost of real engineering time that the cold-start problem (see the companion GTM memo) more urgently needs.

**This recommendation is not a decision on your behalf** — it's a default to make explicit and either confirm or override. If there are near-term plans for the consumer-engagement or review-response agents that this remediation pass doesn't know about, that changes the calculus toward Option B sooner.

## 5. What doesn't wait on this decision

Independent of Option A vs. B, `ai-agents.md` §7's recommendation #5 (per-function credentials instead of one shared bearer + one shared Gmail identity, already flagged in `AGENT_AUTOMATION_RUNBOOK.md` as a known, accepted gap) and #8 (watch the watchdog — nothing currently alerts if `agent-run-check` itself stops running) are both real, scoped, non-architectural fixes that don't depend on this decision at all and could be picked up as their own Fix-Protocol items whenever there's capacity, the same way MFR-6 (Ad Boost payment-model guardrail) sits as a watch item today.
