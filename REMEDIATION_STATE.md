# Farlo Remediation — Current State

Working branch: `remediation/farlo-a-grade`. Supabase test branch: `remediation` (project ref `iwufrgjtlikkongopheu`, parent `weflrxyerxpsafcdetya`) — schema-only, replayed clean from committed migrations as of iteration 10 (see LOG), no seed data (previous test rows were wiped by the `reset_branch` used to verify migration reproducibility — reusable for future red/green tests, just re-insert what a given test needs). Get credentials via `supabase branches get remediation` when needed; never commit them. Migration replay now works cleanly via `supabase db push --db-url <pooler-url, port 5432> --yes` (the CLI's own `--linked` path needs Docker, unavailable in this environment; the pooler's transaction-mode port 6543 hits a `prepared statement already exists` Supavisor incompatibility — use session-mode port 5432 instead).

**Iteration:** 10 (iterations 1-9 = prior A-grade pass, reconciled in LOG; iteration 10 = this session, operating under a revised A+ mission with a materially higher bar — see Goal below).

**Goal, revised (iteration 10):** bring every in-scope category to **A+**, a materially higher bar than the ≥90 "A" iterations 1-9 targeted. Per-category A+ definitions are in the operating prompt that started this iteration (not duplicated here in full — see: zero Medium+ security findings with permanent committed tests; migrations verified-reproducible (not just present); domain layer + god-screen decomposition + image pipeline rebuild for Engineering; full-app `Semantics` for UI/UX; the agent architecture decision actually implemented, not just documented; App Store checklist actually re-run this session). **Product stays out of scope** by standing agreement (unchanged from iteration 9's discussion — graded on real-world Hartsville traction, not engineering work). Before any category is reported as A+, a full re-verification pass (not sampling) is required, plus an explicit question to the founder about an independent outside audit — no exceptions, per the operating prompt.

**An independent verification pass (immediately prior to this iteration) re-checked iterations 1-9's claims against live code/remote state.** Its corrected scorecard is this iteration's starting point (below), not the prior self-estimate — it found one concrete gap (migrations materialization was a stale snapshot, not current) and confirmed everything else it sampled. That gap is now closed as of this iteration — see LOG.

---

## Scorecard (last updated: iteration 10, after ARCH-4 partial + clean analyze + broader accessibility labeling)

| Area | Verified start-of-iteration-10 | Now (est.) | A+ target | Weight |
|---|---|---|---|---|
| **Overall** | ~85 (pre-iteration-10 verified) | **~89** | ≥97, Product excluded, per-category criteria | — |
| Security | 86 | **~92** | ≥97 + zero Medium+ findings + permanent tests | 25% |
| Backend/Supabase | 83 | **~90** | ≥97 + verified-reproducible migrations | 15% |
| Engineering | 88 | **~90** | ≥97 + domain layer + god-screens + image pipeline + fully clean analyze | 20% |
| UI/UX | 86 | **~88** | ≥97 + full-app Semantics + Tooltip-vs-Semantics decision | 12% |
| AI Agent System | 80 | 80 | ≥97 + architecture decision actually implemented | 10% |
| App Store Readiness | 85 (not independently re-verified before this iteration) | 85 | ≥97 + checklist actually re-run this session | 8% |
| Product | out of scope | out of scope | out of scope, standing agreement | 10% |

**Milestone: Engineering's "flutter analyze fully clean" A+ criterion is now met** (0 issues, was 2 pre-existing info-level lints). `dashboard_screen.dart` decomposed (1519 → 258 lines, 1 of 6 god screens — see ARCH-4 checklist below for the 5 still open). UI/UX's Tooltip-vs-`Semantics()` deviation formally resolved (ratified as an accepted equivalent, documented in `accessibility_roadmap.md`), plus ~20 more icon-only controls given accessible labels beyond the original 20-item roadmap — still not "full-app" coverage (116 Dart files per `ux-review.md`'s own framing), but meaningfully broader.

**Milestone: 5 of 6 Medium+ findings surfaced by this iteration's full pass through `security.md` §4 are now closed** — `revenuecat-webhook`'s fail-open behavior on a missing secret, 4 storage buckets' missing file-size/MIME limits, signup's account-enumeration oracle, and `send-employee-invite`'s complete lack of authorization (its source wasn't even in git — recovered via `supabase functions download`, since it's deployed and live). Each has a permanent test and live deployment/smoke-test evidence in LOG. The one remaining item (Low-Medium GDPR data-export gap) is a bigger, product-shaped feature, not a quick fix — tracked below, not attempted this iteration.

**Milestone: 7 of 8 `security.md` §3 abuse scenarios now have permanent, committed, re-runnable regression tests** (up from 0 — every prior iteration's evidence for these was live-deployment verification only, per the "Observed, not yet triaged" note below). New `supabase/tests/security_abuse_scenarios.sql` (scenarios #3/#4/#5/#6, plus a 9th non-named Medium finding, run via `scripts/run_security_abuse_tests.sh`), new Deno unit tests for scenario #1 (both payment Edge Functions' amount logic extracted into testable pure functions), a new Flutter test for scenario #2 (no embedded Google Places key), and a new Flutter test for scenario #7 (`signOut()` now explicitly invalidates every non-auth-reactive per-user/per-truck provider — a real, previously-unfixed gap this iteration found and closed, not just tested). Scenario #8 is formally out of scope (a capability descope, not a vulnerable/fixed code state — documented in LOG rather than silently skipped). Every one of these tests was verified to actually fail against the pre-fix/vulnerable code before being trusted (see LOG for each). Also closed one new Medium finding from `security.md` §4 not previously tracked under any QW-/MED- item: `orders.payment_status` could be flipped to `'paid'` by the owner/employee with no real Stripe charge — closed via a `BEFORE UPDATE` trigger, service_role (Stripe webhook) path confirmed unaffected.

**Milestone: ARCH-2 (3/4 targets) + ARCH-3 (limits + timeouts across all 13 repositories) + the truck-logos/truck-photos storage gap all closed this iteration**, driving Security ~81→~85, Engineering ~86→~88, Backend ~89→~91 (first category to cross the ≥90 bar, pending the founder's independent re-audit).

**Milestone: the full accessibility roadmap (all 20 items + the bonus swipe-to-delete alternative) closed this iteration**, driving UI/UX 68→~87 — the single largest jump of any category, closing `ux-review.md`'s F/30 accessibility grade. Not calling this a full "A" yet: `ux-review.md`'s other findings (motion/haptics, 116+27 raw color literals bypassing the theme system, remaining touch-target-adjacent polish) weren't in scope for this pass and would need their own item to fully close the category.

**Milestone: 2 of `ai-agents.md` §7's 6 recommendations closed this iteration** — untrusted-input framing (#2, closing a real prompt-injection surface across 5 agent functions) and a shared Aiden prompt/persona layer (#3). Driving both Security (~85→~87, the injection-framing fix) and AI Agent System (~70→~80, both fixes). **Narrowed scope, honestly flagged:** #5 (per-function credentials — only the shared-bearer-token half is in scope without external GCP/Workspace action; not yet done, see Phase 5 checklist), #6 (observability/tracing beyond `agent_run_log`), #7 (unified tool registry), and #8 (watch-the-watchdog, needs an external monitoring service) remain open. AI Agent System is closer to the bar but not confirmed at 90 yet.

**Milestone: Phase 1 (Immediate Risks) is fully closed — all 15 items.** This is the biggest single driver of the Security/Backend jumps this iteration (payment tampering, the order-race, subscription-lapse, stranded-charge, and account-deletion findings all closed with real red/green evidence against the isolated Supabase branch — see LOG). Still not calling Security or Backend an "A": several Low findings remain open and none of these fixes have formal automated regression tests yet, only live red/green verification done during this pass (see Observed section).

**Milestone: Phase 2 (Must-Fix-if-Apple-Rejects-Again) is now fully closed — all 6 items.** MFR-5 (privacy manifest), MFR-4 (Crashlytics), MFR-3 (background-location descope), MFR-1 (pre-upload checklist script) closed in earlier iterations with real builds; MFR-2 closed this iteration on your direct confirmation that App Store Connect's App Review Notes has the tap-by-tap paywall path; MFR-6 closed this iteration as "correctly scoped, no action needed" — building Ad Boost now would be unscoped net-new feature work, not remediation, so the explicit call was not to build it. **This resolves the Hard Stop #5 ambiguity — Phase 5 is now unblocked.**

**Milestone: Phase 3 (Quick Wins) is fully closed.** QW-3 (fail-open `SubscriptionStatus` default — a real security-relevant client-side gap, fixed alongside Phase 1's server-side subscription work), QW-4 (`.autoDispose` on all 19 flagged providers, including `pendingBookingCountProvider` — the single highest-leverage fix in the whole audit), QW-5 (2 dead files + 4 unused packages removed), QW-6 (`onboarding.png` recompressed 1.8MB→512KB, `icon.png` removed from the shipped bundle entirely) all closed this iteration.

**Milestone: Phase 4 (Medium Improvements) is now fully closed** (with 2 items' scope honestly narrowed, not silently claimed — see checklist notes). MED-8 (session tokens now in Keychain/Keystore via `flutter_secure_storage`, closing security.md's last remaining Medium-High client-side finding), MED-9 (shared error/snackbar helper — all 64 raw call sites migrated, not just a sample), MED-11 (2 of `truck_profile_screen.dart`'s 5 fan-out providers combined into 1 round trip), MED-12 (map clustering memoized + debounced, also fixing a live-observed stacked-pin bug) all closed this iteration. This is the driver of the Engineering jump (~82→~85) and the Security jump (~76→~80).

**Milestone: Phase 5 (Major Architecture) started, iteration 9.** Ahead of Phase 5's own items, closed 3 concrete bugs from `code-quality.md`'s own prioritized recommendation list that had never been picked up under any tracked QW-/MED- item: the `booking_chat_screen.dart:118` message-loss bug (the audit's own "single clearest error-handling bug"), and the 2 missing-`mounted`-check bugs in `my_orders_screen.dart`/`order_queue_screen.dart` and `calendar_screen.dart`/`shift_week_card.dart`. Then closed 3 of ARCH-2's 4 highest-value testing targets — see Phase 5 checklist below.

These are rough re-estimates, not a formal re-audit — treat with the same skepticism the rest of this doc asks you to apply to the original citations.

---

## Open items, by phase

Canonical IDs follow `FARLO_FINAL_AUDIT.md`'s Top 20 numbering where an item appears there; `QW-`/`MED-`/`ARCH-`/`MFR-`/`P6-` prefix items that only appear in Quick Wins / Medium / Major Architecture / Must-Fix-if-Rejects / Phase 6 respectively. Duplicates across lists are cross-referenced, not repeated.

### Phase 1 — Immediate Risks — ✅ ALL 15 CLOSED
- [x] #1 Payment amount tampering — closed iteration 1. **Caveat: introduced a client/server contract break on `create-payment-intent` (no secure backward-compat possible) — see "Known blocker" below. This is why the build was pulled from App Store review, per your decision.**
- [x] #2 `invite_employee_by_email` no ownership check — closed iteration 1
- [x] #3 `GOOGLE_PLACES_API_KEY` embedded client-side — closed iteration 1 (proxied). **Key itself never rotated — Hard Stop #1, awaiting sign-off below.**
- [x] #4 `agent-aiden-supervisor` zero sender filtering — closed iteration 1
- [x] #5 `agent-aiden-inbox` spoofable sender allowlist — closed iteration 1
- [x] #6 `profiles` readable by every authenticated user — closed iteration 1
- [x] #7 Account deletion FK-violation "zombie" accounts — closed iteration 4, see LOG
- [x] #8 `employee_shifts_update_own`/`scheduled_shifts` no `WITH CHECK` — closed iteration 1
- [x] #9 `menu-item-photos` storage bucket over-permissive — closed iteration 3, see LOG
- [x] #10 `prospect-businesses` zero auth — closed iteration 1
- [x] #11 `searchTrucks()` null-coordinate crash — closed iteration 2, see LOG
- [x] #12 Unescaped search input breaking PostgREST filter — closed iteration 2, see LOG (same fix as #11)
- [x] #13 Consumer-cancel vs. owner-accept order race — closed iteration 4, see LOG
- [x] #14 Stranded Stripe charges / no idempotency key (= MED-6) — closed iteration 4, see LOG (Idempotency-Key header not tested against real/test Stripe — see Observed)
- [x] #15 Subscription lapse never rechecked (= MED-7) — closed iteration 4, see LOG

### Phase 2 — Must-Fix-if-Apple-Rejects-Again — ✅ ALL 6 CLOSED
- [x] MFR-1 Pre-upload checklist automation (dart-define/demo-account script) — closed iteration 5, see LOG
- [x] MFR-2 Paywall App Review Notes — closed iteration 8, user-confirmed: App Store Connect's App Review Notes field has the tap-by-tap path to the paywall.
- [x] MFR-3 iOS background-location authorization gap — closed iteration 3, see LOG
- [x] MFR-4 Crash reporting SDK (= MED-9 partial) — closed iteration 3, see LOG
- [x] MFR-5 App-level `PrivacyInfo.xcprivacy` — closed iteration 3, see LOG
- [x] MFR-6 Ad Boost payment-model guardrail — closed iteration 8 as "correctly scoped, no action needed": Ad Boost has no code and building it now would be unscoped net-new feature work, not remediation. Explicit call: do not build Ad Boost as part of this pass. Revisit only if/when Ad Boost work actually starts.

### Phase 3 — Quick Wins — ✅ ALL CLOSED
- [x] QW searchTrucks + unescaped filter — see #11/#12 above
- [x] QW-3 `SubscriptionStatus.fromString` fail-open default — closed iteration 6, see LOG
- [x] QW-4 `.autoDispose` on 19 flagged providers (= #16) — closed iteration 6, see LOG
- [x] QW-5 Delete 2 dead files + 4 unused packages — closed iteration 6, see LOG
- [x] QW-6 Recompress `onboarding.png`/`icon.png` — closed iteration 6, see LOG
- [x] QW `requireAgentSecret` on `prospect-businesses` — see #10 above
- [x] QW Google Places key — see #3 above
- [x] QW-9 Remove `RESEND_API_KEY` from client `.env.json` — closed iteration 1
- [x] QW `PrivacyInfo.xcprivacy` — see MFR-5 above

### Phase 4 — Medium Improvements — ✅ ALL CLOSED (2 with narrowed scope, see notes)
- [x] MED server-side amount recomputation — see #1 above
- [x] MED ownership/`WITH CHECK` fixes — see #2/#8 above
- [x] MED-3 `menu-item-photos` storage policy scoping — see #9 above
- [x] MED tighten `profiles` SELECT — see #6 above
- [x] MED agent sender-check fixes — see #4/#5 above
- [x] MED-6 Idempotency key + order-cancel precondition — see #13/#14 above. **Not fully done: "compensating refund/alert" half of this item (auto-refund if placeOrder fails after charge) was not implemented — the fix instead makes retry safe via idempotency, which resolves the same user-facing harm via a different mechanism. Note this explicitly rather than silently claim the original sub-item.**
- [x] MED-7 Subscription-status check in payment functions + `fetchActiveTrucks` filter — see #15 above
- [x] MED-8 `flutter_secure_storage` wiring — closed iteration 7, see LOG
- [x] MED-9 Crash reporting (see MFR-4 above) + shared error/snackbar helper — closed iteration 7, see LOG. All 64 raw call sites migrated (full scope, not a partial sample).
- [x] MED-10 `delete-account` transactional fix — see #7 above. **Storage-object cleanup (avatar/truck photos) still not done — separate gap, needs Storage API calls from the Edge Function, noted in LOG.**
- [x] MED-11 Batch `truck_profile_screen.dart`'s 6 round-trips — closed iteration 7, see LOG. **Narrowed scope: only 2 of 5 fan-out providers (reviews + myReview) combined into 1 round trip — `truckFollowerCountProvider`/`announcementPrefProvider` deliberately left separate (isolated widgets with independent graceful-loading UX; combining would regress that), `foodTruckProvider` left separate (primary data + its own realtime subscription). A full server-side RPC/view remains the more complete fix, not done.**
- [x] MED-12 Memoize map screen clustering (= #18) — closed iteration 7, see LOG. Also fixed the live-observed stacked-pin bug (same root cause).
- [x] MED-13 Materialize migrations into git — closed iteration 1

### Phase 5 — Major Architecture Improvements (unblocked as of iteration 8 — Phase 2 fully closed)
- [ ] ARCH-1 Domain/data-model layer separation — not started. Will likely be scoped down to "repository interfaces for the 2 repositories that block ARCH-2's 4th test target" rather than a full rewrite across every repository — proportionality call, will flag if that scoping turns out wrong. **Required for Engineering A+.**
- [x] ARCH-2 Testing seam/mocking infrastructure — **3 of 4 highest-value targets closed iteration 9**, see LOG. Added `mocktail`/`fake_async`, 19 real passing tests (router redirect logic — extracted into a new pure `computeRedirect()` function — AuthNotifier timeout/rollback, OwnerTruckNotifier optimistic-rollback). 4th target (OrdersRepository/BookingsRepository quote/deposit flows) deliberately deferred — needs a repository-interface seam (ARCH-1) to be practically mockable, not attempted with a fragile mock-heavy workaround.
- [x] ARCH-3 Codebase-wide pagination + timeout pattern (= #17) — closed iteration 9, see LOG. `.limit(200)` added to the 4 originally-unbounded queries; new shared `withNetworkTimeout` extension applied across all 13 repository files (~90 call sites). **Narrowed scope: the 4 confirmed eager `ListView(children:)` sites (dashboard/order_queue/my_orders/booking_requests screens) were not converted to `.builder()`** — each mixes static headers/empty-states with mapped content, a real per-screen restructuring job, and at today's data volumes the audit itself frames this as "latent-until-scale, not today's problem." Flagged as remaining backlog, not attempted.
- [ ] ARCH-4 Decompose six god screens — **1 of 6 done** (`dashboard_screen.dart`, 1519→258 lines, see LOG). Remaining, confirmed still oversized as of this iteration: `calendar_screen.dart` (1445 lines), `map_screen.dart` (1106), `account_screen.dart` (1449), `truck_profile_screen.dart` (1425), `booking_requests_screen.dart` (1372). Same file-splitting pattern applies directly to each — read the file's class boundaries, move each private widget class to its own file under a `widgets/` subdirectory, share any module-level providers via a small shared providers file, verify with `flutter analyze`/`flutter test`/a real build. **Required for Engineering A+ — not yet met.**
- [ ] ARCH-5 Rebuild image pipeline — not started. **Required for Engineering A+.**
- [x] ARCH-6 AI agent trust-boundary shared library — **2 of 6 sub-items closed iteration 9**, see LOG (`_shared/prompt-boundaries.ts` untrusted-input wrapping across 5 functions, `_shared/aiden-persona.ts` shared directive/persona layer). Remaining, explicitly deferred: per-function bearer secrets (partially external-action-free, not attempted yet), a real observability/tracing layer, a unified tool registry, and watch-the-watchdog (needs an external monitoring service, similar in kind to Hard Stop #1).
- [x] ARCH-7 Agent dispatcher-vs-cron decision doc (= P6-3) — closed iteration 7, see LOG
- [x] MED-13 (Backend Critical: migrations materialized) — **re-closed for real, iteration 10.** A prior verification pass found the original iteration-1 closure was a stale mid-pass snapshot excluding the `storage` schema entirely and missing 6 later migrations. Iteration 10 committed all 8 previously remote-only migrations verbatim plus a new storage-schema baseline, then verified reproducibility by resetting the `remediation` branch, replaying all local migrations from empty, and diffing the result against live production across tables/columns/RLS policies/functions/triggers — zero drift confirmed. See LOG.

### A+-specific gaps (iteration 10, not tracked under any prior Phase — new mission bar)
- [x] **Security A+, abuse-scenario half:** 7 of 8 `security.md` §3 abuse scenarios now have permanent committed tests (see Milestone above); #8 formally out of scope.
- [x] **Security A+, Medium+ findings — 5 of 6 closed:**
  - [x] `revenuecat-webhook` now fails closed if `REVENUECAT_WEBHOOK_SECRET` is unset — `isAuthorizedWebhookRequest()`, 4 tests, deployed live.
  - [x] All 5 public storage buckets now have file-size/MIME-type limits (`truck-logos`/`truck-photos`/`avatars` at 5MB image, `truck-menus` at 10MB PDF, matching `menu-item-photos`'s existing pattern) — applied to production, materialized as a migration, branch/prod parity confirmed.
  - [x] Account enumeration on signup closed — `registerFriendlyError()` now shows the same generic message for "already registered" as any other failure; 3 tests. **Honest limit:** Supabase Auth's own signup API still distinguishes this case for direct API callers — a full close needs a custom signup proxy, disproportionate to a Medium finding.
  - [x] `send-employee-invite`'s source recovered (`supabase functions download`) and its zero-authorization gap closed — now verifies the caller owns the truck (`callerOwnsTruck()`, 3 tests) and derives email content server-side instead of trusting client strings. Deployed live, client call site updated.
  - [ ] **Still open:** Low-Medium data-export/GDPR-style download mechanism — bigger product-shaped item needing scoping (what data, what format, self-serve vs. support-ticket), not a quick fix. Not attempted this iteration; flagging as the one remaining item before Security's "zero Medium+ findings" bar is fully met.
  - Confirmed already resolved as side effects of prior fixes (no new work needed, just noting): `prospect-businesses` reachable via the embedded client Places key (moot — client no longer holds any Places key), `agent-miles`' `business_name` prompt-injection surface and the `agent_directives`-vs-untrusted-text delimiting gap (both closed by iteration 9's `wrapUntrusted()` rollout), `RESEND_API_KEY` in client `.env.json` (removed iteration 1).
- [x] **UI/UX A+, Tooltip-vs-Semantics decision:** resolved — `Tooltip` ratified as an accepted equivalent to explicit `Semantics(label:)` for simple icon-only buttons, documented in `accessibility_roadmap.md`.
- [ ] **UI/UX A+, full-app Semantics coverage:** ~20 more icon-only controls labeled this iteration (password-visibility toggles, back buttons, add/close/edit/delete icons across auth, calendar, employees, notifications, bookings, dashboard screens — see LOG). Still not "full-app" (`ux-review.md`: 116 Dart files at audit time) — untouched controls likely remain outside the files scanned this pass. **Not yet met.**
- [ ] **AI Agent System A+:** implement `agent_architecture_decision.md`'s Option A formalization for real — build the shared prompt/persona layer's remaining pieces (already partially done via `_shared/aiden-persona.ts`), observability beyond `agent_run_log`, unified tool registry.
- [ ] **App Store Readiness A+:** actually re-run `scripts/pre_upload_checklist.sh` against a current build artifact this session, not carry forward the prior "no red flags found."
- [x] **Engineering A+, flutter analyze:** now 0 issues project-wide (was 2 pre-existing info-level lints) — met.
- [x] **Engineering A+, test coverage for business logic touched this pass:** `signOut()` invalidation (4 tests), all new Edge Function pure functions (20 Deno tests across 4 functions), account-enumeration message (3 tests) — all covered as each fix landed, not deferred.

### Phase 6 — Non-code deliverables — ✅ ALL CLOSED
- [x] P6-1 Cold-start GTM memo — closed iteration 7, see `audit/cold_start_gtm_memo.md`
- [x] P6-2 Accessibility roadmap (15-20 highest-traffic controls, priority order) — closed iteration 7, see `audit/accessibility_roadmap.md`
- [x] P6-3 Agent architecture decision doc — closed iteration 7, see `audit/agent_architecture_decision.md`

---

## Awaiting sign-off (Hard Stops)

- ~~Hard Stop #1~~ — **closed iteration 8.** User rotated `GOOGLE_PLACES_API_KEY` in Google Cloud Console and set the new value via `supabase secrets set` directly in their own terminal (the plaintext value never passed through this session at any point — verified only via the secret's digest hash changing and `updated_at` timestamp updating to today). End-to-end verified: called the live `places-autocomplete` Edge Function with a real autocomplete query and got back real Google Places predictions (`"status":"OK"`), confirming the new key is both set and actually working.
- **Hard Stop #6 (App Store submission):** current build was pulled from review per your decision last session — resubmission stays yours to trigger once Ship-Readiness Gate (§12) passes. Not close yet — working through the remaining punch list first (see Next action).

## Blocked-technical

(none yet)

## Known blocker (not a Hard Stop, but blocks Ship-Readiness Gate)

`create-payment-intent`'s new required-`items` contract breaks order placement on any binary built before today's fix (including whatever was pulled from App Store review). The matching client code is committed but not shipped. This must close before Ship-Readiness Gate can pass — resolved automatically once a new build ships; no further action needed beyond eventually cutting that build.

## Observed, not yet triaged

- Every item closed in this pass (iterations 2-4: #7, #9, #11, #12, #13, #14, #15) was verified via **live red/green testing against the isolated Supabase branch** — a real step up from iteration 1's live-deployment-only verification, but still not the same as a permanent, automated, runnable regression test living in the codebase. Once ARCH-2 (testing infrastructure) exists, backfill real test files for all of these before certifying Security-A or Backend-A. The branch-based verification transcripts are preserved in `REMEDIATION_LOG.md` and should transfer directly into real test cases.
- Iteration 1's original nine items (#1, #2, #3, #4, #5, #6, #8, #10, MED-13) still only have live-deployment + direct-re-query verification, no red/green branch testing was done for those (the branch didn't exist yet in iteration 1). Same backfill note applies.
- `create-booking-payment-intent`'s accidental backward-compatibility (old client already sends what the new server needs) should get an explicit regression test once ARCH-2 lands, so it doesn't silently regress later.
- ~~`truck-logos`/`truck-photos` storage gap~~ — **closed iteration 9**, see LOG.
- Stripe `Idempotency-Key` header behavior (#14) was not exercised against a real/test Stripe account — no Stripe test credentials configured on the branch. Standard, well-documented Stripe behavior, but flagged as lower-confidence than this pass's other items.
- MED-6's "compensating refund/alert" sub-item and MED-10's storage-object-cleanup sub-item were each explicitly *not* done as part of closing their parent items — see the Phase 4 checklist notes above. Don't let the parent checkbox imply full scope was covered.

## Judgment call — resolved iteration 8

Hard Stop #5's literal wording is "merging Phase 5 before Phases 1-2 close." As of iteration 7 this was ambiguous (Phase 2 code-complete but 2 process items open) and was surfaced rather than assumed. Resolved this iteration: you confirmed MFR-2 directly (App Review Notes has the paywall path), and MFR-6 was assessed as correctly scoped with nothing to do until Ad Boost work actually starts (explicit call: not building Ad Boost now, since that would be unscoped net-new feature work, not remediation). Phase 2 is therefore genuinely closed, not just code-complete. **Phase 5 is unblocked.**

## Next action

Punch list items 1-4 all resolved (iteration 8). Hard Stop #6 (resubmission) is explicitly deferred by the founder until every category except Product hits A (iteration 9) — see Goal note at the top of this file. Currently executing Phase 5 + remaining findings toward that bar. Order, roughly by leverage/risk:

1. ~~3 concrete bugs from code-quality.md's recommendation list~~ (chat message-loss, 2 missing-mounted-checks) — **closed iteration 9**, see LOG.
2. ~~ARCH-2 (testing infrastructure)~~ — **3 of 4 targets closed iteration 9**, see LOG and Phase 5 checklist.
3. **Next up:** batch `manage_hours_screen.dart`'s 7-call write loop (small, contained, already identified in code-quality.md §2.8/§2.15), then the `truck-logos`/`truck-photos` storage-policy gap (mirrors the already-fixed `menu-item-photos` pattern from Phase 1, so low-risk/fast).
4. Then the larger items: ARCH-3 (pagination/timeouts), the accessibility roadmap's 20 items, ai-agents.md §7's remaining recommendations, ARCH-1 (scoped down, see Phase 5 checklist note), ARCH-4 (decompose god screens).
5. Hard Stop #6 stays the founder's own action once the above closes and a fresh audit confirms the grade.
