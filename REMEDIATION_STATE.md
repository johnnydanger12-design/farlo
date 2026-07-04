# Farlo Remediation — Current State

Working branch: `remediation/farlo-a-grade`. Supabase test branch: `remediation` (project ref `iwufrgjtlikkongopheu`, parent `weflrxyerxpsafcdetya`) — schema-only, no seed data except what a given test inserts (owners 1-3, trucks 1-3, a pending order, an event booking with a message, a canceled and an active subscription — all reusable for future tests). Get credentials via `supabase branches get remediation` when needed; never commit them. Note: this branch's own migration replay is broken (`MIGRATIONS_FAILED`) — it's usable only because the baseline schema dump was loaded directly via `psql`. If recreated, repeat that load step.

**Iteration:** 8 (iteration 1 = last session's pre-protocol pass, reconciled below; iterations 2-8 = this protocol, same session).

---

## Scorecard (last updated: iteration 8)

| Area | Baseline | Now (est.) | Target | Weight |
|---|---|---|---|---|
| **Overall** | 64 (D+) | **~83** | ≥90 (A) | — |
| Security | 46 (F) | ~80 | ≥90 | 25% |
| Engineering | 74 (C) | ~85 | ≥90 | 20% |
| Backend/Supabase | 66 (D+) | ~89 | ≥90 | 15% |
| UI/UX | 68 (C-) | 68 | ≥90 | 12% |
| Product | 73 (C+) | 73 | ≥90 | 10% |
| AI Agent System | 58 (D-) | ~70 | ≥90 | 10% |
| App Store Readiness | 70 (C-) | ~85 | ≥90 | 8% |

**Milestone: Phase 1 (Immediate Risks) is fully closed — all 15 items.** This is the biggest single driver of the Security/Backend jumps this iteration (payment tampering, the order-race, subscription-lapse, stranded-charge, and account-deletion findings all closed with real red/green evidence against the isolated Supabase branch — see LOG). Still not calling Security or Backend an "A": several Low findings remain open and none of these fixes have formal automated regression tests yet, only live red/green verification done during this pass (see Observed section).

**Milestone: Phase 2 (Must-Fix-if-Apple-Rejects-Again) is now fully closed — all 6 items.** MFR-5 (privacy manifest), MFR-4 (Crashlytics), MFR-3 (background-location descope), MFR-1 (pre-upload checklist script) closed in earlier iterations with real builds; MFR-2 closed this iteration on your direct confirmation that App Store Connect's App Review Notes has the tap-by-tap paywall path; MFR-6 closed this iteration as "correctly scoped, no action needed" — building Ad Boost now would be unscoped net-new feature work, not remediation, so the explicit call was not to build it. **This resolves the Hard Stop #5 ambiguity — Phase 5 is now unblocked.**

**Milestone: Phase 3 (Quick Wins) is fully closed.** QW-3 (fail-open `SubscriptionStatus` default — a real security-relevant client-side gap, fixed alongside Phase 1's server-side subscription work), QW-4 (`.autoDispose` on all 19 flagged providers, including `pendingBookingCountProvider` — the single highest-leverage fix in the whole audit), QW-5 (2 dead files + 4 unused packages removed), QW-6 (`onboarding.png` recompressed 1.8MB→512KB, `icon.png` removed from the shipped bundle entirely) all closed this iteration.

**Milestone: Phase 4 (Medium Improvements) is now fully closed** (with 2 items' scope honestly narrowed, not silently claimed — see checklist notes). MED-8 (session tokens now in Keychain/Keystore via `flutter_secure_storage`, closing security.md's last remaining Medium-High client-side finding), MED-9 (shared error/snackbar helper — all 64 raw call sites migrated, not just a sample), MED-11 (2 of `truck_profile_screen.dart`'s 5 fan-out providers combined into 1 round trip), MED-12 (map clustering memoized + debounced, also fixing a live-observed stacked-pin bug) all closed this iteration. This is the driver of the Engineering jump (~82→~85) and the Security jump (~76→~80).

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
- [ ] ARCH-1 Domain/data-model layer separation — not started
- [ ] ARCH-2 Testing seam/mocking infrastructure — not started (prerequisite for rigorous automated regression tests on every item closed via live/branch verification so far — see Observed section)
- [ ] ARCH-3 Codebase-wide pagination + timeout pattern (= #17) — not started
- [ ] ARCH-4 Decompose six god screens — not started
- [ ] ARCH-5 Rebuild image pipeline — not started
- [ ] ARCH-6 AI agent trust-boundary shared library — not started
- [x] ARCH-7 Agent dispatcher-vs-cron decision doc (= P6-3) — closed iteration 7, see LOG

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
- `truck-logos`/`truck-photos` storage buckets have the same class of gap `menu-item-photos` had on INSERT — checks only `auth.role() = 'authenticated'`, no path/truck-ownership scoping (`supabase-audit.md` §4). Not yet triaged as its own item; good Phase 4 candidate.
- Stripe `Idempotency-Key` header behavior (#14) was not exercised against a real/test Stripe account — no Stripe test credentials configured on the branch. Standard, well-documented Stripe behavior, but flagged as lower-confidence than this pass's other items.
- MED-6's "compensating refund/alert" sub-item and MED-10's storage-object-cleanup sub-item were each explicitly *not* done as part of closing their parent items — see the Phase 4 checklist notes above. Don't let the parent checkbox imply full scope was covered.

## Judgment call — resolved iteration 8

Hard Stop #5's literal wording is "merging Phase 5 before Phases 1-2 close." As of iteration 7 this was ambiguous (Phase 2 code-complete but 2 process items open) and was surfaced rather than assumed. Resolved this iteration: you confirmed MFR-2 directly (App Review Notes has the paywall path), and MFR-6 was assessed as correctly scoped with nothing to do until Ad Boost work actually starts (explicit call: not building Ad Boost now, since that would be unscoped net-new feature work, not remediation). Phase 2 is therefore genuinely closed, not just code-complete. **Phase 5 is unblocked.**

## Next action

Working through the remaining punch list with you directly, one item at a time, per your request (iteration 8):

1. ~~Phase 5 judgment call~~ — **resolved**, see above. Phase 5 unblocked.
2. ~~Hard Stop #1~~ — **resolved**, see above. Key rotated, set, and end-to-end verified.
3. ~~MFR-2/MFR-6~~ — **resolved**, see Phase 2 milestone above.
4. **The `cold_start_gtm_memo.md` open questions** (launch city, pricing-sequencing option) and **`agent_architecture_decision.md`'s recommendation** (formalize vs. build a dispatcher) — next up.
5. **Hard Stop #6** — App Store resubmission, once the above are settled.

Once all 5 are worked through, proceed into Phase 5 scoping/sequencing per item 1's resolution.
