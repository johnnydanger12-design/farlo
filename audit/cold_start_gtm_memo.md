# Farlo — Cold-Start Go-To-Market Memo (Phase 6, P6-1)

**Status: decided, as of iteration 8.** Originally written as an open recommendation memo; the open questions in §3 were resolved directly with the founder and are recorded below as decisions, not options. Kept in `audit/` rather than deleted so the reasoning behind each call stays attached to the audit finding that prompted it.

**Source:** `audit/product-review.md` §2.1, §3, §5, §6 (Prioritized Product Punch List #1, #4). Re-read in full while writing this; nothing here contradicts it — this is that report's recommendation section made concrete and sequenced.

---

## 1. The problem, restated plainly

Today, a first-time user in almost any real city opens Farlo to an empty or near-empty map. The three trucks in production are all in Cupertino, CA — the founder's own test data. Every other finding in the product review (trust, retention, differentiation, even how severely the map-pin-overlap bug reads) is downstream of this one fact: **the two-sided marketplace has no supply-side density anywhere except one test city**, and no product mechanism (waitlist, "coming soon," seeded listings) softens that for a user who opens the app somewhere else.

This is not a code defect. It cannot be fixed by an engineering pass, and no amount of further remediation on the Phases already closed (1-4) moves this number. It is why `product-review.md` calls it "arguably a bigger risk to the business than any individual code defect."

## 2. Why this doesn't block the technical launch decision

`FARLO_FINAL_AUDIT.md` is explicit that the cold-start problem is a go-to-market problem to solve in parallel with the security/technical work, not a gate on it (see that report's own line: "Do not gate the launch decision on ... the product-level cold-start fix"). This memo assumes that stance holds: nothing here should delay a technically-ready App Store resubmission once Phases 1-2 close. It's presented now, alongside the technical remediation, because product-review.md flagged it as highest business-impact and because a launch-city plan takes real lead time (recruiting truck owners doesn't happen overnight) — starting that clock in parallel with the remaining technical work is the actual reason to look at it now rather than after resubmission.

## 3. Decisions (settled iteration 8)

### 3.1 Launch city: Hartsville, SC

Decided. Marketing spend is focused exclusively on Hartsville — the app itself stays available worldwide (see §3.2), so growth outside Hartsville is deliberately organic rather than gated. This is a different (and reasonable) strategy than the memo originally assumed ("gate unserved cities behind a waitlist") — the founder's actual goal is "let it spread on its own; don't make me launch city-by-city."

### 3.2 No waitlist/gating feature — the existing empty state already fits this strategy

**Not building the waitlist feature originally scoped here.** It doesn't match the decided strategy (worldwide availability, organic spread) — a blocking email-capture wall would actively work against a curious user in another city exploring or favoriting a truck in case one shows up there later.

Checked the current code (`map_screen.dart:543-548`): a non-blocking empty-state chip already exists — **"No active businesses in this area"** — shown when the map has zero trucks in view. This already does the right thing for the decided strategy: honest, non-blocking, no gating. No new code needed.

**Backlog idea, not yet scoped or built:** a referral/word-of-mouth nudge — something like "invite your favorite trucks to Farlo" — surfaced to consumers, fitting the organic-growth strategy. Good direction, but needs real product definition before it's buildable (where does the prompt live, share-sheet vs. copy-link, any incentive attached). Noted here for a future pass, not implemented.

### 3.3 Pricing: keep the existing model, with one manual per-business lever

**Decided: keep the existing subscribe-first, 14-day-trial, no-free-tier model** for the general public. For hand-picked early Hartsville owners specifically, the founder plans to **manually grant an additional 30 days on top of the standard 14-day trial (44 days total)** via a direct operational grant — this is a RevenueCat dashboard action (RevenueCat supports granting a free promotional entitlement period per user), not a code change, done business-by-business as owners are recruited.

Worth recording as a data point, not a directive: the industry-standard model for two-sided marketplaces (DoorDash, Uber Eats) is commission-per-order rather than a flat merchant subscription — a merchant with zero orders pays zero, removing this exact churn-risk category entirely. Flagged for awareness; **not recommended as a change right now** — it would be a major backend/Stripe Connect redesign, disproportionate to the actual risk given the 44-day manual extension already mitigates the worst case for the cohort that matters most (Hartsville's first owners).

## 4. What's left open

- The referral-nudge idea (§3.2) needs product definition before it becomes a real Fix-Protocol item — revisit when there's bandwidth for new-feature work, not urgent.
- Everything else in this memo is decided. No further open questions.
