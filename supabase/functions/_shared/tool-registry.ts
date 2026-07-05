// Unified tool registry — ai-agents.md §7 Recommendation #7, agent_architecture_decision.md's
// Option A sub-item #4. Previously each agent defined its own `TOOLS` array inline with no
// central place to see, in one pass, every capability any agent in the fleet has. The audit's
// own framing: this "would make future audits tractable," not a security fix on its own — the
// actual trust boundaries (sender allowlists, wrapUntrusted(), least-privilege RPCs) are enforced
// where each tool's handler is implemented, not here. This registry is a catalog, not a runtime
// dependency — each agent still owns its own TOOLS array and handlers (moving the actual
// definitions here would mean every agent importing every other agent's tool schemas, which adds
// coupling for no real benefit, since no two agents currently share a tool implementation except
// update_directive, which already lives in aiden-persona.ts). Keep this file in sync whenever a
// tool is added, removed, or its write scope changes — a stale registry is worse than none.

export interface RegisteredTool {
  /** Tool name, exactly as it appears in the agent's TOOLS array / Claude's tool_use blocks. */
  name: string;
  /** Which agent function(s) define and can invoke this tool. */
  agents: string[];
  /** One line: what real-world effect calling this tool has. */
  effect: string;
  /** What this tool can write/send, for a quick least-privilege scan without reading every handler. */
  writeScope: string;
}

export const TOOL_REGISTRY: RegisteredTool[] = [
  {
    name: 'send_reply',
    agents: ['agent-sage'],
    effect: 'Sends a real, unreviewed reply directly to a support customer.',
    writeScope: 'Gmail send (support@farlo.app) + support_tickets row update.',
  },
  {
    name: 'escalate_to_human',
    agents: ['agent-sage'],
    effect: 'Sends a human-handoff acknowledgment and flags a ticket urgent for Johnny.',
    writeScope: 'Gmail send (support@farlo.app) + support_tickets row update + urgent alert.',
  },
  {
    name: 'fetch_new_prospects',
    agents: ['agent-miles'],
    effect: 'Pulls fresh prospect businesses for a city via the prospect-businesses tool (paid Google Places calls).',
    writeScope: 'sales_prospects inserts (service-role, via prospect-businesses).',
  },
  {
    name: 'mark_no_email_found',
    agents: ['agent-miles'],
    effect: 'Marks a prospect as needing manual/in-person outreach instead of email.',
    writeScope: 'sales_prospects row update (notes/status only).',
  },
  {
    name: 'draft_outreach',
    agents: ['agent-miles'],
    effect: 'Creates a Gmail draft — never sends. Johnny reviews and sends manually.',
    writeScope: 'Gmail draft creation (outreach@farlo.app) — no send capability.',
  },
  {
    name: 'queue_content',
    agents: ['agent-piper'],
    effect: 'Queues one piece of marketing content for Johnny to review and post manually.',
    writeScope: 'content_queue insert only — no posting/publishing capability of any kind.',
  },
  {
    name: 'send_reply_to_johnny',
    agents: ['agent-aiden-inbox'],
    effect: 'Sends an unreviewed reply to johnny@farlo.app only (never any other address).',
    writeScope: 'Gmail send (aiden@farlo.app, to johnny@farlo.app only) + agent_inbox_replies row.',
  },
  {
    name: 'log_inbox_action',
    agents: ['agent-aiden-inbox'],
    effect: 'Logs a one-line note that a directive change was already handled.',
    writeScope: 'In-memory/log only — no persisted write beyond the run itself.',
  },
  {
    name: 'update_directive',
    agents: ['agent-aiden-inbox', 'agent-aiden-supervisor'],
    effect: "Edits Aiden's own persistent directives (steers future runs). Locked directive keys are rejected — see aiden-persona.ts's LOCKED_DIRECTIVE_KEYS.",
    writeScope: 'agent_directives row update, restricted to OPERATIONAL_DIRECTIVE_KEYS (shared schema in aiden-persona.ts, not duplicated per agent).',
  },
  {
    name: 'write_weekly_brief',
    agents: ['agent-aiden-supervisor'],
    effect: "Writes the week's summary/top-actions/critical-flags.",
    writeScope: 'supervisor_reports insert.',
  },
  {
    name: 'send_weekly_brief_email',
    agents: ['agent-aiden-supervisor'],
    effect: 'Emails the weekly brief to johnny@farlo.app only.',
    writeScope: 'Gmail send (aiden@farlo.app, to johnny@farlo.app only) — no other recipient possible.',
  },
  {
    name: 'apply_label',
    agents: ['agent-email-labeler'],
    effect: "Applies exactly one label to a Gmail thread and its category-specific follow-up (archive for Newsletters; mark-important for Support/Aiden/Personal).",
    writeScope: 'Gmail label/archive/importance-flag on the caller\'s own inbox — no send, no delete.',
  },
];

// Non-tool-loop functions worth listing here for the same auditability reason, even though
// they don't go through runAgentLoop()'s tool_use mechanism at all:
export const NON_LOOP_AGENT_FUNCTIONS = [
  { name: 'agent-stripe-weekly', effect: 'LLM summary only (tools: []) — emails a Stripe weekly digest to johnny@farlo.app.' },
  { name: 'agent-newsletter-cleanup', effect: 'Mechanical Gmail cleanup, no LLM call.' },
  { name: 'agent-urgent-alert', effect: 'Mechanical push/email alert dispatch, no LLM call.' },
  { name: 'agent-run-check', effect: "Watchdog — alerts if an agent hasn't logged a successful run within its expected window." },
];
