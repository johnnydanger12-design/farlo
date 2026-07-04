# Farlo — Cold-Start Go-To-Market Memo (Phase 6, P6-1)

**Status: a synthesis + recommendation memo, not a decision record.** The choices below (which city, what pricing change, what verification bar) are business calls that belong to you, not something this remediation pass can or should decide unilaterally. This memo exists to turn `product-review.md`'s findings into one concrete, sequenced plan you can approve, edit, or reject — consistent with how every other Phase 6 item in this pass is a document, not a code change.

**Source:** `audit/product-review.md` §2.1, §3, §5, §6 (Prioritized Product Punch List #1, #4). Re-read in full while writing this; nothing here contradicts it — this is that report's recommendation section made concrete and sequenced.

---

## 1. The problem, restated plainly

Today, a first-time user in almost any real city opens Farlo to an empty or near-empty map. The three trucks in production are all in Cupertino, CA — the founder's own test data. Every other finding in the product review (trust, retention, differentiation, even how severely the map-pin-overlap bug reads) is downstream of this one fact: **the two-sided marketplace has no supply-side density anywhere except one test city**, and no product mechanism (waitlist, "coming soon," seeded listings) softens that for a user who opens the app somewhere else.

This is not a code defect. It cannot be fixed by an engineering pass, and no amount of further remediation on the Phases already closed (1-4) moves this number. It is why `product-review.md` calls it "arguably a bigger risk to the business than any individual code defect."

## 2. Why this doesn't block the technical launch decision

`FARLO_FINAL_AUDIT.md` is explicit that the cold-start problem is a go-to-market problem to solve in parallel with the security/technical work, not a gate on it (see that report's own line: "Do not gate the launch decision on ... the product-level cold-start fix"). This memo assumes that stance holds: nothing here should delay a technically-ready App Store resubmission once Phases 1-2 close. It's presented now, alongside the technical remediation, because product-review.md flagged it as highest business-impact and because a launch-city plan takes real lead time (recruiting truck owners doesn't happen overnight) — starting that clock in parallel with the remaining technical work is the actual reason to look at it now rather than after resubmission.

## 3. Recommended plan (yours to approve or amend)

### 3.1 Pick 1-3 launch cities and treat them as the actual product

Rather than opening consumer signups everywhere the app is technically available, constrain the "real" product to a small number of cities where supply has actually been built. Concretely:

- Pick 1 city first (not 3) — a single city where you can personally recruit truck owners is easier to reach a critical mass in than three cities at once, and gives a cleaner signal on whether the core loop works before spreading effort. Expand to 2-3 once the first city has a working loop (consumers ordering, owners renewing past trial).
- "Critical mass" for a food-truck map realistically means enough trucks that a consumer opening the map on a random weekday sees multiple live options, not one. There's no universal number — it depends on the city's food-truck scene size — but the visible failure mode to avoid is the current one (3 trucks, visibly a test dataset). A rough starting target: enough trucks that at least 3-5 are reliably "live" (toggled open) during typical lunch/dinner hours, which likely means recruiting more than that in total to account for trucks that aren't live every day.
- This is a recruiting/sales problem, not a code problem — outside this remediation pass's scope to execute, but worth noting the app already has the mechanics to support it (owner signup → truck listing → Go Live toggle all work end-to-end per `product-review.md` §2.6's "owner critical path: complete").

### 3.2 Add a waitlist / "not live in your city yet" state

This is the one piece of this memo with a real, scoped code component, and it's the highest-leverage single addition: it converts "empty map, user churns silently" into "user leaves their email, becomes a lead for city #2/#3."

**What it needs, concretely** (a real implementation task, not yet done — flagging for a future Phase 3/4-style pass once you approve the city plan):
- Detect "no active trucks within N miles of the user's current map view" (the map screen already has the truck list and the user's location — this is a client-side check against data already being fetched, not a new query).
- Show a lightweight, non-blocking state (a banner or bottom sheet, not a full-screen blocker — the map should still be explorable) offering an email capture: "Farlo isn't in your city yet — want to know when we launch here?"
- Store captured emails somewhere queryable (a new `waitlist_signups` table, or even routing through the existing `sales_prospects`-style table if the schema fits) — this is the only new backend surface this item needs, and it's additive/low-risk (an insert-only table, no RLS complexity beyond "anyone can insert their own email, only you can read the list").
- This is intentionally scoped small: no geofencing product, no "notify me" push infrastructure, just a capture mechanism. Resist scope creep here — the goal is a lead list per unserved city, not a feature.

### 3.3 Reconsider the subscribe-first sequencing for a new city's first owner cohort

`product-review.md` §3's business-model sanity check is worth taking seriously: an owner in an unproven city tries the 14-day trial, sees near-zero order volume (because there's no consumer density yet — the exact chicken-and-egg problem this whole memo is about), and churns before ever paying, independent of whether the product works. Options, in rough order of how much they change the existing pricing model (least to most):

1. **Do nothing differently, but extend the trial for first-cohort owners in a launch city** (e.g., 30-60 days instead of 14) — smallest change, buys time for consumer density to build before the trial clock matters. Likely implementable as a per-user override on the existing subscription/trial logic rather than a schema change.
2. **A free "basic listing" tier, pay only to unlock ordering/boost** — closer to what `product-review.md` recommends directly. Bigger product/pricing change: requires deciding what's gated behind payment (today, `food_trucks`' public visibility itself is gated on active subscription per Phase 1's #15 fix) and reworking that gate to distinguish "listed" from "orders enabled."
3. **A city-launch cohort discount** (e.g., 50% off for the first N owners in a new city) — a RevenueCat/App Store Connect pricing configuration, not a code change, and the fastest to execute if you want to try it before committing to option 2's bigger rework.

**This memo does not pick one of these three for you.** Option 1 is the cheapest to try and reversible; options 2-3 are real product/pricing decisions with App Store Connect and Stripe implications that deserve your explicit sign-off before any code changes — this is squarely a "business/product-strategy decision" in the sense the remediation protocol treats as a hard stop, not something to decide autonomously.

### 3.4 Sequencing relative to the technical remediation

Recommended order, given the technical remediation (Phases 1-4) is essentially done as of this writing:

1. **Now, in parallel with wrapping up Phase 2's process items (MFR-2, MFR-6) and the App Store resubmission prep:** decide on the first launch city and start owner recruiting — this has the longest lead time of anything in this memo and doesn't depend on any further code work.
2. **Before or shortly after resubmission:** decide on §3.3's pricing approach for that city's first cohort (or explicitly decide to defer this and launch with the existing model, accepting the churn risk `product-review.md` flags).
3. **A short, scoped implementation pass** (comparable in size to one of the Phase 3/4 items already closed in this session) for §3.2's waitlist state, timed to land before the launch city goes live to real consumer marketing.

## 4. What this memo is explicitly not

- Not a decision that any specific city is chosen — that requires knowledge of where real food-truck-owner relationships/recruiting access already exists, which this pass has no visibility into.
- Not an authorization to build the waitlist feature yet — it's scoped and ready to pick up once you confirm the city plan, since building it before knowing the geofencing radius/copy you want risks rework.
- Not a pricing decision — §3.3 lays out options, not a chosen path.

Bring back whichever of §3.1-§3.3's open questions you want to settle, and the next remediation pass can turn §3.2 into an actual Fix-Protocol item (relocate → red → fix → green → log) the same way every closed item in `REMEDIATION_LOG.md` was handled.
