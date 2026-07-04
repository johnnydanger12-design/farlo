# FARLO — Final Executive Audit

**Synthesis of Phases 1–10.** Source reports: `architecture.md`, `supabase-audit.md`, `ai-agents.md`, `code-quality.md`, `app-store-review.md`, `ux-review.md`, `security.md`, `performance.md`, `bugs.md`, `product-review.md` (all in `audit/`). This document does not re-derive findings — every claim below cites the phase and file:line where the underlying evidence lives. Read the cited report for full detail; this document exists to rank, weigh, and connect what ten independent passes found.

App state at time of audit: version `1.0.0+5`, rejected by Apple three times, currently awaiting a fourth review decision on a metadata-only resubmission (`app-store-review.md` §1–2). Live user base is pre-launch test data (14 `auth.users` rows, 9 trucks — `supabase-audit.md` §1).

---

## Executive Summary

Farlo is a real, ambitiously-scoped two-sided marketplace — Stripe Connect payouts, RevenueCat subscriptions, a full private-event booking negotiation pipeline, employee shift management, and a 10-function AI-agent back office — built by what all evidence indicates is a single founder moving fast under real deadline pressure (three App Store rejections, live users, live agents). That pace shows up as a consistent pattern across every phase: **the parts of this system built once and left alone are disciplined; the parts that grew iteratively — RLS policies, error handling, provider lifetimes, agent trust boundaries — have accumulated real, launch-relevant gaps.**

The single fact that should dominate a launch decision: **this system currently has no defense-in-depth.** `security.md` §2.2 states it plainly — every repository method trusts a client-supplied ID and relies on Postgres RLS as the *only* authorization boundary, with zero client-side ownership pre-checks anywhere. That's a defensible architecture only if RLS is airtight. It is not: `supabase-audit.md` found a `SECURITY DEFINER` RPC with no ownership check at all (Critical Finding #2) and a payment function that trusts a client-supplied dollar amount (Critical Finding #1), and `security.md` independently found a billed, secret-grade API key compiled into the shipped binary (N1) and two RLS policies letting an employee falsify their own timesheet (N3/N4). None of these require an attacker to be sophisticated — `security.md` §3 turns each into a concrete abuse scenario a scriptable curl command executes today.

Layered on top of that: the AI agent system that now runs the business's support/sales/marketing/founder-communication loop unattended has a Supervisor agent (`agent-aiden-supervisor`) with **zero sender filtering** on inbound email that's fed to a tool-enabled LLM with standing write access to every other agent's operating instructions (`ai-agents.md` Top Risk #1), and a sibling function (`agent-aiden-inbox`) with the exact spoofable-regex bug already fixed once elsewhere in the same codebase, left unpatched (`ai-agents.md` Top Risk #2).

None of this is visible in the product experience today, which has its own, unrelated problem: `product-review.md` and `ux-review.md` both independently confirm — one from live device screenshots — that the app's default launch screen shows three test trucks in one city with the pins rendered stacked on top of each other, and that the product's core go-to-market gap (zero cold-start strategy for a two-sided marketplace) is arguably a bigger threat to the business than any of the code-level findings.

**Bottom line:** this is not a hobby project pretending to be a startup — it's a startup MVP that over-invested in payment/booking/staff plumbing and under-invested in authorization hardening, error handling, and go-to-market sequencing. Every gap below is fixable, most are cheap, but several are launch blockers, not polish items.

---

## Grades

Numeric scores are holistic judgments synthesizing each phase's own findings, not a mechanical average. Security is weighted most heavily in the Overall Grade because unauthorized-access and payment-integrity findings are the category most likely to cause irreversible harm (fraud, data breach) versus every other category's harm being recoverable (a bad screen, a slow query, a support ticket).

| Area | Score /100 | Grade | Primary source |
|---|---|---|---|
| **Overall** | **64** | **D+** | weighted synthesis, see below |
| Engineering (architecture + code quality + performance) | 74 | C | `architecture.md`, `code-quality.md`, `performance.md` |
| Backend / Supabase | 66 | D+ | `supabase-audit.md` |
| Security | 46 | F | `security.md`, cross-ref `supabase-audit.md`, `ai-agents.md` |
| AI Agent System | 58 | D- | `ai-agents.md` |
| UI/UX | 68 | C- | `ux-review.md` |
| Product | 73 | C+ | `product-review.md` |
| App Store Readiness (current submission) | 70 | C- | `app-store-review.md` |

**Weighting used for Overall (64/100):** Security 25%, Engineering 20%, Backend 15%, UI/UX 12%, Product 10%, AI Agents 10%, App Store 8%. Security's independent score (46) and the fact that three of the six Critical findings across the whole audit are unauthorized-access/payment-integrity bugs pull the overall grade down from where Engineering/Product alone would put it (high 60s/low 70s).

### Why each score is what it is

- **Engineering — C (74).** Real repository pattern, consistent feature-first layout, genuinely strong memory-leak hygiene (74/75 disposable resources correctly cleaned up, `code-quality.md` §2.9), clean async/await style with zero `Future.wait` misuse (`code-quality.md` §2.13). Held back by: zero automated test coverage (`code-quality.md` §2.14), 19 non-`.autoDispose` Riverpod family providers that leak Realtime channels for a session's lifetime (`code-quality.md` §2.7 — the single largest recurring citation across the entire audit, independently load-bearing in Phase 8's performance findings and Phase 9's scale modeling), and six 1,000+ line "god screens" with 40-60 branches each (`code-quality.md` §2.6, `architecture.md` §11).
- **Backend/Supabase — D+ (66).** RLS is universally enabled with no fully-open or fully-locked-out tables (`supabase-audit.md` §3 intro) — a genuinely sound starting posture. But two Critical/High-severity gaps sit inside that otherwise-sound posture (payment amount trust, employee-invite privilege escalation), plus a `profiles` table readable by every authenticated user (`supabase-audit.md` Critical #3), and **74 live migrations exist only on the remote project with zero local source** (`supabase-audit.md` §13) — a disaster-recovery gap, not a security one, but a real operational risk.
- **Security — F (46).** Three Critical-severity findings exist across the codebase when Phase 2, 3, and 7 are combined (payment tampering, RPC privilege escalation, client-embedded billing key), plus seven-plus High-severity findings with concrete, scripted abuse paths (`security.md` §3 lists eight). A codebase with zero client-side defense-in-depth and this many gaps in its one real authorization layer earns a failing grade regardless of how clean the rest of the security posture is (and much of it — secrets handling, injection surface, payment tokenization — genuinely is clean, per `security.md` §3/§8/§12).
- **AI Agent System — D- (58).** Genuinely excellent instrumentation for its scale (per-run cost tracking, a staleness watchdog, reply-loop circuit breakers — `ai-agents.md` §1 "what's working well") undercut by the single most severe *structural* finding in the whole audit: a tool-enabled LLM with standing write access to the entire fleet's operating instructions, reachable by anyone who can send an email to a public address, with zero code-level filtering (`ai-agents.md` Top Risk #1). A system this well-instrumented losing points specifically on trust boundaries is a "fix the two specific things" problem, not a rebuild — reflected in the fact several individual agents (`agent-sage`, `agent-email-labeler`) scored 6.5-7/10 on their own.
- **UI/UX — C- (68), Product — C+ (73).** Both already graded by their own phases with full rationale; not re-derived here. See `ux-review.md` §1/§4 and `product-review.md` §1/§2.
- **App Store Readiness — C- (70).** The currently-pending resubmission's specific fix is correct and complete (`app-store-review.md` §2 row 3), but two of the three historical rejections trace to *process* gaps (a manual pre-upload checklist, not a code defect) that can recur on any future build, and this audit found new, real risk for the *next* submission — no crash reporting, no app-level privacy manifest, and an iOS background-location feature that cannot function as coded (`app-store-review.md` §3 Findings 8.1, 2.1, 5.1).

---

## Top 20 Issues (ranked by severity × exploitability/impact, deduplicated across phases)

1. **Payment amount tampering** — `create-payment-intent`/`create-booking-payment-intent` trust a client-supplied `amount_cents` with no server-side recomputation; traced end-to-end to `order_cart_sheet.dart:47` computing the charge amount entirely from client cart state. A user can pay $0.50 for any order. *Critical.* (`supabase-audit.md` Critical #1; `security.md` Abuse Scenario #1; `bugs.md` §1 Executive Summary #3 for the related stranded-charge variant.)
2. **`invite_employee_by_email` RPC has no ownership check** — any authenticated user can add themselves as an active employee of any truck via a single RPC call, gaining order/shift/live-status access with the owner never approving or knowing. *Critical.* (`supabase-audit.md` Critical #2; `employees_repository.dart:30`; `security.md` Abuse Scenario #3.)
3. **`GOOGLE_PLACES_API_KEY` compiled into the shipped Flutter binary** — a billed, secret-grade Google API key extractable via `strings` on the APK/IPA, independent of and not fixed by any server-side auth fix, with a modeled cost of ~$1,100-2,100/hour of uncontrolled billing exposure. *Critical.* (`security.md` N1/Abuse Scenario #2; `places_autocomplete_field.dart:6`.)
4. **`agent-aiden-supervisor` applies zero sender filtering** to inbound email fed to a tool-enabled LLM with standing write access to every agent's operating directives — a crafted email to a discoverable public address is a plausible path to silently steering Support/Sales/Marketing behavior. *Critical (structural).* (`ai-agents.md` Top Risk #1, `index.ts:102-119,212-213`.)
5. **`agent-aiden-inbox`'s sender allowlist is spoofable** — an unanchored regex tested against the raw `From:` header, the identical bug class already fixed once in `agent-sage`, left unpatched here. *High.* (`ai-agents.md` Top Risk #2, `index.ts:17,115`.)
6. **`profiles` table readable by every authenticated user** (`USING (true)`), exposing every user's email and Stripe Connect account ID, and realtime-broadcast to the entire user base on every change. *High.* (`supabase-audit.md` Critical #3; `security.md` §11.)
7. **Account deletion provably fails**, not just incompletely, for any user who ever used booking chat or filed a support ticket — two `NO ACTION` foreign keys cause the delete function to throw partway through, leaving a "zombie" account (data half-gone, login still works). *High, GDPR/CCPA-adjacent.* (`security.md` N2/Abuse Scenario #5.)
8. **`employee_shifts_update_own` RLS has no `WITH CHECK`** — any employee can PATCH their own shift's clock-in/out times directly via the API, bypassing every UI control, invisible to the owner. *High.* (`security.md` N3/Abuse Scenario #4.)
9. **`menu-item-photos` storage bucket allows any authenticated user to overwrite or delete any truck's menu photos** — INSERT/DELETE policies check only `bucket_id`, no ownership scoping. *High.* (`supabase-audit.md` Critical #4; `security.md` Abuse Scenario #6.)
10. **`prospect-businesses` Edge Function has zero authentication**, driving unlimited paid Google Places API calls and service-role writes with no rate limit — modeled at ~$1,100-2,100/hour of exposure, a second independent path to the same billing risk as #3. *High.* (`supabase-audit.md` Critical #12; `security.md` §13.)
11. **`searchTrucks()` crashes the app** for any truck that has never gone live — a force-unwrap on nullable lat/lng fed by a query missing the null-location filter its sibling query has. Near-certain within day one of real signups, on the app's default screen. *Critical (crash).* (`bugs.md` Executive Summary #1, `map_repository.dart:57-67`, `map_screen.dart:876-882`.)
12. **Ordinary search text with a comma or parenthesis breaks truck search entirely** — the raw query string is spliced unescaped into a PostgREST `.or()` filter. The highest-frequency bug found across the whole audit; fires on natural text like "mac, cheese." *High.* (`bugs.md` §2.7.1.)
13. **Consumer-cancel vs. owner-accept race with no optimistic-concurrency guard** — a fast owner-accept can be silently overwritten by a stale cancel, producing a wrongful refund after food is already being prepared. Modeled at dozens-to-hundreds of occurrences per day at scale. *Critical (financial + data corruption).* (`bugs.md` Executive Summary #2, `orders_repository.dart:91-98`.)
14. **Stranded Stripe charges with no idempotency key** — a failure between a successful charge and the order-insert never triggers a refund and never clears the cart, inviting an immediate double-charge retry. *Critical (financial, trust).* (`bugs.md` Executive Summary #3, `order_cart_sheet.dart:32-89`.)
15. **Lapsed/canceled subscriptions are never rechecked** once a truck is already live — no realtime listener, no router guard, no server-side check in the payment functions or the public map query. A continuous, certain revenue-leak window. *High.* (`bugs.md` Executive Summary #4, `security.md` cross-ref.)
16. **19 Riverpod family providers are never `.autoDispose`**, leaking a Postgres Realtime channel per truck/booking ID ever viewed. Modeled at ~200,000 concurrently-leaked channels from one provider alone at just 1% concurrent-user overlap at 1M users — a systemic infrastructure risk that degrades service for every user, not just the ones who caused it. *High (systemic).* (`code-quality.md` §2.7; `performance.md` §9; `bugs.md` §2.10.3.)
17. **Zero pagination anywhere in the codebase** (`.range()` used 0 times) feeding non-lazy `ListView(children:)` widgets, combined with zero network timeouts anywhere except one RevenueCat call. A hung request blocks the UI forever; an unbounded query will eventually load a truck/user's entire history into memory on every screen open. *High.* (`code-quality.md` §2.15; `performance.md` §3/§5.)
18. **Map screen recomputes marker clustering/sort on every single pan/zoom frame** with no memoization or debounce — the confirmed root cause of a live-observed bug where truck pins render fully stacked on the app's default launch screen, and a quantified performance cliff (certain multi-second freeze at ~5,000 simultaneously-visible trucks). *High.* (`performance.md` §2/Top 5 #3; `ux-review.md` live finding; `bugs.md` §2.10.2.)
19. **Zero accessibility infrastructure** — `Semantics`/`semanticLabel` usage is confirmed at zero across all 116 Dart files, plus multiple deliberately-shrunk touch targets, including a "Cancel Event" button on a paid booking flow with its tap target explicitly zeroed out. *Medium-High.* (`ux-review.md` §1 weakness #1/#3; `app-store-review.md` §14.1.)
20. **Product-level: zero cold-start strategy for a two-sided marketplace** — no seeded content, no waitlist, no "coming soon" state, live-confirmed via screenshots showing exactly three trucks in one city. Judged by the product review as a bigger risk to the business than any individual code defect. *High (business, not technical).* (`product-review.md` §2.1, §5.)

---

## Top 10 Strengths

1. **A real, non-cargo-culted repository pattern** covering the majority of data access, with clean typed methods and no leaked query-builders into UI code (`architecture.md` §10).
2. **Genuinely strong memory-leak hygiene** for the classic Flutter leak sources — 74 of 75 checked disposable resources (subscriptions, timers, controllers) are correctly disposed (`code-quality.md` §2.9). The one *real* leak mechanism (non-autoDispose providers) is a different, larger-blast-radius issue the classic dispose-check wouldn't catch — but the classic hygiene itself is real.
3. **RLS is universally enabled** across all 29 tables with no fully-open or fully-locked-out tables, and the backend-only agent tables are correctly locked to service-role-only access (`supabase-audit.md` §3).
4. **Deliberate, documented defensive engineering learned from real production incidents** — the fail-loud Supabase config check (added after a silent `assert()`-stripping caused a real App Store rejection), the auth timeout/rollback discipline, and the cold-start push-notification race fix are all real, reasoned fixes with in-code rationale (`architecture.md` §10).
5. **The AI agent system's cost/reliability instrumentation is unusually mature for its scale** — per-run Anthropic cost tracking, a dedicated staleness watchdog (`agent-run-check`), and unit-tested reply-loop circuit breakers that most solo-founder-scale agent systems skip entirely (`ai-agents.md` §1).
6. **Sales and Marketing agents correctly keep a human-review checkpoint** (Gmail draft / content-queue row) rather than auto-sending, and the Sales agent's kill-switch was live-verified to work (`ai-agents.md` §3.2).
7. **A genuinely complete two-sided critical path** — both the consumer path (discover → order → pay → receive) and the owner path (signup → list → manage → fulfill → pay staff) trace end-to-end with no dead ends found (`product-review.md` §2.6).
8. **Real differentiation over the actual status quo** (Google Maps + Instagram) via direct in-app ordering with real payment, a complete private-event booking negotiation pipeline, and employee shift/clock-in management — scope a funded team would typically defer to v2 (`product-review.md` §2.4, §4).
9. **A working design-token system** (spacing grid, 8-step type scale, reusable button/field/error components) that most pre-launch apps skip entirely, plus consistently specific, situationally-aware microcopy (`ux-review.md` §1 strengths #1-2).
10. **No PCI scope, no XSS surface, no SQL/command injection anywhere, and no `service_role` key ever found in client code** — the parts of the security posture that are clean are clean by design, not by luck (`security.md` §8, §12, Consolidated Risk Register "Clean/positive" row).

---

## Immediate Risks (must act on before any real user traffic, regardless of Apple's decision)

These are the items where the cost of waiting compounds daily, independent of App Store timing:

1. Payment amount tampering (#1) and the missing idempotency/stranded-charge protection (#14) — every day live, this is a direct financial-loss and chargeback exposure.
2. `invite_employee_by_email` privilege escalation (#2) — zero precondition, callable by anyone, right now.
3. `GOOGLE_PLACES_API_KEY` embedded client-side (#3) and `prospect-businesses`'s missing auth (#10) — both are live, uncapped, third-party billing exposures with no alerting.
4. `agent-aiden-supervisor`'s zero sender filtering (#4) and `agent-aiden-inbox`'s spoofable allowlist (#5) — these agents are running unattended right now against a real inbox.
5. `searchTrucks()`'s crash (#11) and the unescaped search filter (#12) — both fire on ordinary use, not attacker behavior, and will generate real crash reports/support tickets the moment there's real usage.
6. The consumer-cancel/owner-accept race (#13) and the un-rechecked subscription lapse (#15) — both are silent, continuous financial-integrity gaps, not one-time bugs.

---

## Must Fix if Apple Rejects Again

`app-store-review.md` documents that two of the app's three prior rejections were **process failures**, not code defects — the code was fine, the submitted artifact or reviewer's path through the app wasn't. If a fourth rejection happens, or before the next submission regardless:

1. **Re-run the documented pre-upload checklist every time** — the `strings`-on-`App.framework` dart-define verification and resetting the demo account's subscription status to `trialing` (`app-store-review.md` §2 row 1/2, Punch List #1). This is process, not code, but it has already caused two rejections.
2. **Keep "explicit paywall navigation steps" in App Review Notes as a permanent checklist item** — the Subscription screen's owner-only gating is correct product behavior, not a bug, but it has already triggered one rejection when a reviewer didn't find it (`app-store-review.md` Finding 1.2, Punch List #6).
3. **Fix the iOS background-location authorization gap before it's ever exercised by a reviewer** — the app currently cannot obtain "Always" authorization on iOS at all (`NSLocationWhenInUseUsageDescription` blocks it), so a truck's live location silently stops updating the moment the app backgrounds, despite the app declaring and depending on this feature. If a reviewer backgrounds the app mid-review and checks the map from a second account, the truck vanishes — reads as a functional bug (`app-store-review.md` Finding 5.1, the single most consequential *new* finding of that phase).
4. **Add crash reporting (Sentry or Firebase Crashlytics) before the next build** — two of three rejections were only diagnosable because Apple happened to attach screenshots; there is currently zero server-side crash visibility (`app-store-review.md` Finding 8.1).
5. **Add a Runner-level `PrivacyInfo.xcprivacy`** — all 21 existing privacy manifests are third-party (Pods); none exists at the app level despite `shared_preferences` usage, a real gap in Apple's Spring-2024-onward enforcement (`app-store-review.md` Finding 2.1).
6. **Do not build the planned Ad Boost feature with external web checkout** — routing a purely digital, in-app-consumed feature through a web checkout specifically to avoid Apple's cut is squarely a 3.1.1 violation; route through RevenueCat/StoreKit like the existing owner subscription (`app-store-review.md` Finding 1.1).

---

## Recommended V2 Roadmap

Framed as what should change once the Immediate Risks and App Store items above are closed — not a re-statement of them:

- **Testing foundation.** Zero meaningful test coverage today (`code-quality.md` §2.14); start with `AuthNotifier` state transitions, router redirect logic, and the optimistic-update rollback logic in `OwnerTruckNotifier` — the three highest-leverage, currently-untested pieces of business logic in the app.
- **Transactional integrity for multi-step writes.** Owner signup (auth → profile → truck → subscription), order placement (order → order_items), and account deletion are all non-transactional client-sequenced writes with no compensating rollback (`architecture.md` §11, `security.md` N2). Move these to real Postgres functions/transactions.
- **God-screen decomposition.** Six screens over 1,000 lines each, some with 300+ line `build()` methods and zero widget-level rebuild scoping (`code-quality.md` §2.6, `performance.md` §2). Sequence this *after* the tactical fixes above, per Phase 5/8's own recommendation — re-touching these files while higher-value bugs are still live wastes effort.
- **Real pagination and request timeouts, codebase-wide.** Not a partial gap — `.range()` is used zero times anywhere (`performance.md` §5). This is a ticking-clock item: harmless today at near-zero data volume, a certain multi-week-onset performance cliff once order/booking volume grows (`bugs.md` §2.10.5's 3-6 month degradation timeline).
- **AI agent orchestration, honestly framed.** There is no real dispatcher today — independent cron jobs coordinated only through shared Postgres directive rows (`ai-agents.md` §4). Once the sender-trust fixes above land, the next architectural question is whether to build a real supervisor/routing layer or to consciously keep the current "environmental steering" model and invest instead in shared prompt templates and a unified trust-boundary library (`ai-agents.md` §3, dimension 13's cross-agent duplication finding).
- **Product: solve the cold-start problem as its own initiative**, not a code task — seed real trucks in 1-3 launch cities before opening consumer signups broadly, add an explicit waitlist state for unserved areas, and reconsider the subscribe-first-prove-value-later pricing sequence for a new city's first owner cohort (`product-review.md` §5, §3).
- **Trust infrastructure for a real-time-location product** — a "report this listing / truck wasn't here" mechanism and a lightweight verified-business badge, both currently entirely absent (`product-review.md` §2.3, Punch List #3/#7).
- **Owner-facing analytics** — no revenue trend, repeat-customer, or busiest-hours view exists anywhere for a recurring $30/month product (`product-review.md` §2.6).
- **Accessibility pass** — zero `Semantics` usage app-wide; start with the ~15-20 highest-traffic icon-only controls (`ux-review.md` Punch List #5).

---

## Quick Wins

Cheap, low-risk, high-signal fixes — mechanical or near-mechanical, no architecture change required:

- Add `.limit()`/`.not(..., 'is', null)` fix to `searchTrucks()` to close the crash (#11) — a one-line change mirroring its sibling query (`bugs.md` Fix-before-launch #1).
- Escape or restructure the search query construction to fix the PostgREST `.or()` injection-of-punctuation bug (#12) (`bugs.md` Fix-before-launch #2).
- Change `SubscriptionStatus.fromString`'s fail-open default from `trialing` to a new `unknown`/`expired` value that `hasAccess` treats as `false` — a one-line change removing a systemic landmine (`bugs.md` §2.1.1, Fix-before-launch #6).
- Add `.autoDispose` to the 19 flagged family providers, starting with `pendingBookingCountProvider` — the single highest-leverage one-line-per-provider fix in the whole audit (`code-quality.md` Remediation #1).
- Delete the two confirmed dead files (`shift_calendar_widget.dart`, 774 lines; `loading_overlay.dart`, 17 lines) and remove the four confirmed-unused packages (`cupertino_icons`, `riverpod_annotation`, `riverpod_generator`, `build_runner`) (`code-quality.md` §2.3-2.4).
- Recompress `onboarding.png` (1.8 MB) and confirm/remove `icon.png` (1.6 MB, apparently unreferenced at runtime) — 87% of the entire asset bundle in two files, zero code risk (`performance.md` Punch List #1).
- Add `requireAgentSecret()` to `prospect-businesses`, matching its 10 already-protected sibling functions — closes both the billing-exposure and stored-injection paths in one gate (`supabase-audit.md` Critical #12; `ai-agents.md` Top Risk #3).
- Rotate/restrict `GOOGLE_PLACES_API_KEY` by referrer/bundle ID, or proxy the autocomplete feature through a Farlo-controlled Edge Function instead of calling Google directly from the client (`security.md` §13).
- Remove `RESEND_API_KEY` from the client's `.env.json` — a server-only secret with no functional reason to sit in the Flutter build config (`security.md` §3.3).
- Add an app-level `PrivacyInfo.xcprivacy` — config-only, no rebuild-logic changes needed (`app-store-review.md` Finding 2.1).

---

## Medium Improvements

Real fixes requiring a small-to-moderate, contained change:

- Add server-side amount recomputation to `create-payment-intent`/`create-booking-payment-intent` from the actual order/quote/deposit record instead of trusting the client (#1) (`supabase-audit.md` Critical #1).
- Add an ownership check to `invite_employee_by_email` (#2) and a `WITH CHECK` to `employee_shifts_update_own`/`scheduled_shifts_employee_update_status` (#8) (`supabase-audit.md` Critical #2; `security.md` N3/N4).
- Scope `menu-item-photos` storage INSERT/DELETE policies to the uploading truck's own path, not just `bucket_id` (#9) (`supabase-audit.md` Critical #4).
- Tighten `profiles`' SELECT policy away from `USING (true)` to only the columns/rows that genuinely need cross-user visibility (#6) (`supabase-audit.md` Critical #3).
- Fix `agent-aiden-inbox`'s sender check to use the existing `extractEmailAddress()` helper instead of a raw-header regex, and add an equivalent allowlist gate to `agent-aiden-supervisor` (#4/#5) (`ai-agents.md` Top Risks #1-2).
- Add a Stripe idempotency key and a compensating-refund/alert path for the stranded-charge scenario (#14), and add `.eq('status','pending')` preconditions to the order-cancel and booking-accept/decline update paths (#13) (`bugs.md` Fix-before-launch #3-4).
- Add a subscription-status check inside the payment Edge Functions and filter `fetchActiveTrucks()` on active subscription status (#15) (`bugs.md` Fix-before-launch #5).
- Wire `flutter_secure_storage` into `Supabase.initialize`'s `authOptions` so session tokens live in Keychain/Keystore instead of `SharedPreferences` (`security.md` §1.1).
- Add a crash-reporting SDK (`app-store-review.md` Finding 8.1) and a shared error/snackbar helper to replace the 63 raw `ScaffoldMessenger` call sites and standardize the currently-inconsistent raw-exception-text-shown-to-users pattern (`code-quality.md` §2.12, §2.16; `ux-review.md` Punch List #4).
- Fix `delete-account`'s non-transactional design so it no longer fails partway through for users with booking-chat/support-ticket history (#7), and confirm/add storage-object cleanup (`security.md` N2).
- Batch `truck_profile_screen.dart`'s six independent round-trips into one call or `Future.wait`-coordinate them (`performance.md` §3).
- Memoize the map screen's clustering/sort computation against the truck list and rounded viewport bounds instead of recomputing on every pan/zoom frame (#18) (`performance.md` §2).
- Materialize the 74 live-only Supabase migrations into `supabase/migrations/*.sql` in git (`supabase-audit.md` §13).

---

## Major Architecture Improvements

Larger-effort, structural changes — sequence after the above, not instead of it:

- **Introduce a real domain/data-model layer** separate from wire-format DTOs, so a backend column rename doesn't require touching UI-adjacent code (`architecture.md` §11).
- **Build the testing seam this codebase currently lacks** — every repository takes a concrete `SupabaseClient`, not an interface, and no mocking library is even declared; unit-testing business logic today requires a live Supabase instance (`code-quality.md` §2.14).
- **Implement a codebase-wide `.range()`-based pagination pattern** and a centralized request-timeout/retry wrapper, replacing the current "pagination doesn't exist as a concept" and "zero timeouts except one RevenueCat call" state (`performance.md` §3, §5).
- **Decompose the six god screens** into extracted widgets/controllers with scoped `Consumer`/`.select()` watches, starting with `dashboard_screen.dart`'s 307-line `build()` (`code-quality.md` §2.2/§2.6; `performance.md` §2).
- **Rebuild the image pipeline**: resolution-capped uploads app-wide (only the avatar picker does this correctly today), consistent `CachedNetworkImage` usage (currently 2 files vs. 17 raw `Image.network` sites), and Supabase Storage image-transform URLs for map pins/thumbnails instead of always fetching full-resolution originals (`performance.md` §4/§6/§9).
- **Give the AI agent system a real trust-boundary library** — shared, tested sender-verification and untrusted-content delimiting used by every agent, replacing the current pattern where each agent independently (and inconsistently) concatenates trusted directives and untrusted external text into one undifferentiated prompt blob (`ai-agents.md` §1 Top Risk #4, dimension 3 findings across every agent).
- **Decide, deliberately, whether the agent fleet needs a real supervisor/dispatcher** or should formalize its current "independent cron jobs + shared config" model with better observability — right now it's an accident of implementation, not a chosen architecture (`ai-agents.md` §4).

---

## Overall Recommendation

Do not treat this as a binary "rewrite vs. ship as-is" choice. The engineering foundation, the product scope, and the AI-agent instrumentation are all genuinely above the bar for a solo-founder pre-launch app — this audit's harshest grades come from a small number of *specific*, *fixable* gaps concentrated in authorization boundaries (client and RLS both assume the other one is the real gate; neither fully is) and in trust boundaries in the agent system (a well-built fleet with two unfiltered doors into it). Fix the ~10 items in **Immediate Risks** and the App Store checklist items, and this app's actual risk profile changes substantially without needing any of the Major Architecture Improvements first.

The product-level risk (cold-start, zero trust infrastructure) is real and, per `product-review.md`, arguably the larger threat to the business's success — but it is a go-to-market problem, not a reason to delay a technically-ready launch, and it should be solved in parallel with, not blocking, the security fixes above.

## Would you approve this product for launch?

**Not yet, as currently configured — but the path to "yes" is short and specific, not a rewrite.**

Approve launch once, at minimum: (1) the payment-amount-tampering and idempotency gaps are closed, (2) `invite_employee_by_email` has an ownership check, (3) the `GOOGLE_PLACES_API_KEY`/`prospect-businesses` billing-exposure paths are closed, (4) `agent-aiden-supervisor`/`agent-aiden-inbox` have real sender verification, and (5) the `searchTrucks()` crash and the unescaped-search bug are fixed. These five items are collectively addressable in days, not months, touch a small, well-identified set of files, and are the difference between "an app with real but contained pre-launch gaps" and "an app that will generate fraud, data-exposure, or crash reports within its first real week of usage."

Do not gate the launch decision on the Major Architecture Improvements, the accessibility pass, or the product-level cold-start fix — those are real, worth prioritizing immediately after launch, but withholding launch for them would trade a known, sequenceable roadmap for indefinite delay on a product whose core two-sided transaction loop already works end-to-end (`product-review.md` §2.6).
