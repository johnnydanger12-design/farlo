# Farlo Agent Automation — Runbook

_Replaces Claude Cowork's scheduled tasks with `pg_cron` + Supabase Edge Functions calling the
Anthropic API directly, so everything runs 24/7 regardless of whether any device is open. Built
Jul 2 2026. See `COWORK_AGENT_SETUP.md` for the system this replaces, and the git log for the
commit(s) that introduced this._

**Status as of Jul 2 2026: all 12 jobs are LIVE (`dry_run=false`), Cowork's matching tasks are
disabled.** Since going live, Sage, Aiden Inbox, and Aiden Supervisor have each completed at least
one real production cycle (real external test email → real drafted reply; real question to Aiden →
real sent reply; real weekly synthesis → real brief sent) and are confirmed working. Miles remains
correctly un-exercised live — see Known Gaps.

**Incident found and fixed during first live-fire testing (Jul 2):** Sage's first real draft threw
`InvalidCharacterError: Cannot encode string: string contains characters outside of the Latin1
range` — `gmail.ts`'s raw-message builder passed the message string straight through `btoa()`,
which only supports Latin1 and breaks on any en-dash, arrow, or curly quote (i.e. completely normal
LLM-written prose). The agent self-corrected by retrying with an ASCII-only version, so the draft
still got created, but relying on the model to guess an ASCII-safe retry every time isn't a real
fix. **Fixed:** the raw message is now UTF-8-byte-encoded via `TextEncoder` before base64, in
`_shared/gmail.ts` — deployed to every function that bundles it (Aiden Inbox, Aiden Supervisor,
Sage, Miles, Email Labeler, Newsletter Cleanup). If you see this error again, something regressed.

**Policy change (Jul 2): Sage no longer drafts support replies for review — it sends directly.**
This was a deliberate decision after Sage's judgment proved solid in live testing. Sage now has
exactly two paths per ticket, no draft-and-wait step:
- **`send_reply`** — only for questions clearly grounded in `support_kb`. Every auto-sent reply
  gets an AI-disclosure line appended in code (not left to the model to remember — see
  `AI_DISCLOSURE` in `agent-sage/index.ts`), and the ticket is marked `resolved` immediately.
- **`escalate_to_human`** — billing disputes, account deletions, explicit "let me talk to a
  person" requests, or anything Sage isn't confident about. This *sends* a warm human-handoff
  acknowledgment (not silence like the old system) and marks the ticket `in_progress` +
  `priority=urgent`, which plugs into the existing `agent-urgent-alert` fast path — you'll be
  notified within 15 minutes. Once you personally reply, Part 2 of `agent-sage` auto-resolves it.

Sage also now runs **every 5 minutes** (was 9 AM/3 PM) instead of a fixed schedule, since the
function is cheap to run when there's no unread mail — worst-case response latency dropped from up
to 18 hours to about 5 minutes. `agent-run-check`'s expected-window for `agent-sage` was tightened
to 30 minutes to match.

If Sage's judgment turns out to be miscalibrated in practice (wrong-but-confident answers slipping
through `send_reply`), the fix is either tightening the system prompt's confidence bar in
`agent-sage/index.ts`, or reintroducing a narrow draft-for-review path for specific ticket `type`s
— the `createDraft` Gmail helper is still there (Miles uses it), so that's a small change, not a
rebuild.

**Two more real bugs found and fixed (Jul 2, same day, found while answering "are we sure Sage
won't double-respond"):**
1. `escalate_to_human` tried to write a `response_notes` column to `support_tickets` — that column
   only exists on `sales_prospects` (copy-paste mistake). The customer-facing acknowledgment still
   sent fine (that happens first), but the `priority='urgent'` write silently failed after it,
   meaning **escalated tickets never reached `agent-urgent-alert`'s 15-minute notification.** Fixed
   by adding a real `support_tickets.escalation_reason` column and using it instead — also now
   surfaced in the urgent-alert email itself so you see *why* something was escalated.
2. The "don't re-process our own reply" check (`FARLO_SENDER.test(fromHeader)` in both Part 1 and
   Part 2) tested the *raw* `From` header, which looks like `"Sage | Farlo Support"
   <support@farlo.app>` — the regex was anchored to end in `@farlo.app`, but the header actually
   ends in `@farlo.app>`, so it silently never matched. Net effect: **Part 2 (auto-resolving a
   ticket once you reply) never actually worked**, for any ticket, since the very first live run.
   Fixed with a proper `extractEmailAddress()` helper in `_shared/gmail.ts` that pulls the address
   out of the header before testing it, used everywhere a From/To header needs comparing — this is
   the more robust pattern going forward; don't test raw headers with anchored regexes.

Both were live-verified after the fix (a genuinely stuck ticket from before the fix correctly
auto-resolved on the next run).

**Reply-loop / cost protection added (Jul 2).** Nothing previously stopped Sage from replying to a
no-reply address, a vacation auto-responder, or a bounce message — worst case, an infinite loop
with another automated system, each round costing a real Claude API call. Two layers now guard
against this in `agent-sage/index.ts` and `_shared/gmail.ts`:
- `looksAutomated()` checks the standard signals (RFC 3834 `Auto-Submitted`, `Precedence: bulk`,
  common no-reply/mailer-daemon address patterns, bounce/out-of-office subject lines) and skips
  ingesting the thread entirely — no ticket created, nothing sent, no Claude call.
- A hard circuit breaker independent of that detection: once a single sender has messaged the same
  ticket `MAX_CUSTOMER_MESSAGES_BEFORE_ESCALATION` (3) times, Sage stops replying entirely and just
  flags it urgent for a human — this catches any runaway loop regardless of what's causing it, not
  just the patterns `looksAutomated()` happens to recognize.

`looksAutomated()` was unit-tested against 7 cases (real questions, vacation responders, bounces,
bulk mail, and a deliberate false-positive check — an address containing "auto" with a genuine
question) before deploying; all passed.

---

## What's running

12 `pg_cron` jobs, all **live** (every scheduled call omits `dry_run`, meaning real Gmail
drafts/labels/sends and real database writes to `support_tickets`/`sales_prospects`/`content_queue`
happen). See "Flipping a job from dry-run to live" below if you ever need to roll one back to
dry-run temporarily (e.g. while debugging something).

| Job name | Schedule | Function |
|---|---|---|
| `agent-aiden-supervisor` | Mon 6:00 AM | Weekly synthesis + brief |
| `agent-aiden-inbox-morning` | daily 7:00 AM | Reads aiden@ instructions |
| `agent-aiden-inbox-afternoon` | daily 4:00 PM | Same, 2nd check |
| `agent-sage` | every 5 min | Support ticket triage — sends directly, see Policy Change above |
| `agent-miles` | Mon/Wed/Fri 8:00 AM | Sales prospecting |
| `agent-piper` | Tue/Thu 9:00 AM | Marketing content (copy-only — see Known Gaps) |
| `agent-email-labeler` | daily 5:00 PM | Gmail labeling |
| `agent-newsletter-cleanup` | 1st of month 5:00 PM | Trashes old Newsletters |
| `agent-stripe-weekly` | Fri 4:00 PM | Stripe activity report |
| `agent-urgent-alert` | every 15 min | **New** — urgent ticket fast-path |
| `agent-run-check` | every 4 hours | **New** — missed-run alerting |

---

## Disabling Cowork

Now that all 12 jobs above are live, disable these Cowork scheduled tasks to stop getting
duplicate drafts/emails/directive updates from both systems:

- Aiden (Inbox) — both the 7:00 AM and 4:00 PM runs
- Aiden (Supervisor) — weekly Monday run
- Sage (Support) — both daily runs
- Miles (Sales)
- Piper (Marketing)
- Daily Email Labeler
- Monthly Newsletter Cleanup
- Stripe Weekly Check

Leave the already-retired "Monday Morning Brief" alone (it's disabled, not deleted, per
`COWORK_AGENT_SETUP.md` — no change needed there). This has to be done in the Cowork UI directly —
there's no API access from here to Cowork's own scheduler.

If anything looks off in the first week of the new system (check `agent_run_log` daily for a
while), you can re-enable the matching Cowork task as an immediate fallback while you debug —
Cowork itself hasn't been touched, only paused.

---

## Checking logs

```sql
-- Recent runs, all agents
select agent_name, run_mode, status, started_at, finished_at, summary
from agent_run_log order by started_at desc limit 30;

-- Just failures
select * from agent_run_log where status = 'failed' order by started_at desc limit 10;
```

Edge function-level logs (stack traces, console output) are in the Supabase Dashboard →
Edge Functions → [function name] → Logs, or via `mcp__supabase__get_logs` with
`service: "edge-function"`.

---

## Pausing a single agent

```sql
select cron.unschedule('agent-miles');   -- stops it
select cron.schedule('agent-miles', '0 8 * * 1,3,5', $$select public.agent_cron_call('agent-miles', true)$$);  -- restarts it (dry_run=true)
```

Or leave it scheduled but toggle `active`:
```sql
update cron.job set active = false where jobname = 'agent-miles';
```

---

## Flipping a job from dry-run to live

Once you've validated an agent (see next section), re-schedule it with `dry_run` set to `false`:

```sql
select cron.unschedule('agent-miles');
select cron.schedule('agent-miles', '0 8 * * 1,3,5', $$select public.agent_cron_call('agent-miles', false)$$);
```

Do this per-job, not all at once — that's the point of the parallel-run period.

---

## Validating an agent against Cowork's output

1. Let a job run in dry-run for at least one full cycle (a day for daily jobs, a week for
   Miles/Piper/Supervisor).
2. `select * from agent_run_log where agent_name = 'agent-sage' order by started_at desc;` —
   read the `summary` field and, for jobs with `tool_calls` in their HTTP response, the actual
   drafted content.
3. Compare against what Cowork produced for the same period (Cowork's own run history, or the
   emails/drafts it left behind).
4. Only once you trust it: flip that job to `dry_run=false` (above), then disable the matching
   Cowork scheduled task so you're not getting duplicate drafts from both systems.

---

## Rotating a credential

All secrets are Supabase project secrets (`supabase secrets set KEY=value --project-ref weflrxyerxpsafcdetya`)
except the cron bearer token, which lives in Supabase Vault.

| Credential | How to rotate |
|---|---|
| `ANTHROPIC_API_KEY` | New key at console.anthropic.com → `supabase secrets set` |
| `GMAIL_SERVICE_ACCOUNT_JSON` | New key from the service account's Keys tab in Google Cloud Console → `supabase secrets set GMAIL_SERVICE_ACCOUNT_JSON="$(cat newkey.json)"` |
| Cron bearer token (`agent_cron_bearer`) | `select vault.update_secret(id, 'new-value') from vault.decrypted_secrets where name = 'agent_cron_bearer';` — no code change needed, `agent_cron_call()` reads it fresh every invocation. **This also gates `send-agent-email`, which Cowork's Aiden prompts still use** — if you rotate it, update the `Authorization: Bearer ...` line in both Cowork Aiden prompts too. |
| `RESEND_API_KEY`, `STRIPE_SECRET_KEY`, `GOOGLE_PLACES_API_KEY` | Same `supabase secrets set` pattern — no code changes, all read via `Deno.env.get()` at request time. |

---

## Known gaps / follow-ups

- **Canva is not integrated.** Piper ships complete copy-ready content with `needs_asset: true`
  flagged on Instagram/TikTok pieces. Canva's Connect API requires per-user OAuth (not a
  service-account model like Gmail/Firebase) with single-use rotating refresh tokens and an
  undocumented expiry — real ongoing maintenance risk for something unattended. Worth a dedicated
  follow-up project if you want it, not a quick addition to this one.
- **Miles's non-HOLD path is untested against live behavior** — the current `sales_targets`
  directive has outreach on HOLD (pending Apple approval), and Miles correctly refused to call any
  tools during testing, which is exactly right but means the actual prospecting/drafting path
  hasn't been exercised end-to-end. The underlying pieces (Gmail draft creation, `web_search` tool
  availability, the tool-use loop pattern) are independently validated via Sage and Aiden. Once the
  HOLD lifts, watch the first live Miles run's `agent_run_log` entry and the actual Gmail drafts it
  produces before fully trusting it unattended.
- **`agent-run-check`'s expected-window thresholds** (in `agent-run-check/index.ts`) are estimates
  sized to each schedule with headroom — tune them if you get false-positive "stuck" alerts, or if
  a real outage doesn't get caught fast enough.
- **All new functions share one bearer secret** (`agent_cron_bearer`, reusing the rotated
  `AGENT_EMAIL_SECRET`). This is fine for now; if this grows into a larger system later, consider
  per-function secrets so a single leak has a smaller blast radius.
