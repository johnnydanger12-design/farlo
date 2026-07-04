# Farlo Remediation — Current State

Working branch: `remediation/farlo-a-grade`. Supabase test branch: `remediation` (project ref `iwufrgjtlikkongopheu`, parent `weflrxyerxpsafcdetya`) — schema-only, no seed data except what a given test inserts (owners 1-3, trucks 1-3, a pending order, an event booking with a message, a canceled and an active subscription — all reusable for future tests). Get credentials via `supabase branches get remediation` when needed; never commit them. Note: this branch's own migration replay is broken (`MIGRATIONS_FAILED`) — it's usable only because the baseline schema dump was loaded directly via `psql`. If recreated, repeat that load step.

**Iteration:** 6 (iteration 1 = last session's pre-protocol pass, reconciled below; iterations 2-6 = this protocol, same session).

---

## Scorecard (last updated: iteration 6)

| Area | Baseline | Now (est.) | Target | Weight |
|---|---|---|---|---|
| **Overall** | 64 (D+) | **~80** | ≥90 (A) | — |
| Security | 46 (F) | ~76 | ≥90 | 25% |
| Engineering | 74 (C) | ~82 | ≥90 | 20% |
| Backend/Supabase | 66 (D+) | ~89 | ≥90 | 15% |
| UI/UX | 68 (C-) | 68 | ≥90 | 12% |
| Product | 73 (C+) | 73 | ≥90 | 10% |
| AI Agent System | 58 (D-) | ~70 | ≥90 | 10% |
| App Store Readiness | 70 (C-) | ~82 | ≥90 | 8% |

**Milestone: Phase 1 (Immediate Risks) is fully closed — all 15 items.** This is the biggest single driver of the Security/Backend jumps this iteration (payment tampering, the order-race, subscription-lapse, stranded-charge, and account-deletion findings all closed with real red/green evidence against the isolated Supabase branch — see LOG). Still not calling Security or Backend an "A": several Medium/Low findings remain open (see Phase 4 below) and none of these fixes have formal automated regression tests yet, only live red/green verification done during this pass (see Observed section).

**Milestone: Phase 2 (Must-Fix-if-Apple-Rejects-Again) is 4/6 closed** — MFR-5 (privacy manifest), MFR-4 (Crashlytics), MFR-3 (background-location descope), and MFR-1 (pre-upload checklist script) all closed this iteration, each verified with a real `flutter build ios --debug --simulator --no-codesign` (or, for MFR-1, a real script run) rather than guessed. This is the driver of the App Store Readiness bump. Remaining: MFR-2 and MFR-6 are process/watch items, not code (see below) — Phase 2 is effectively code-complete pending those.

**Milestone: Phase 3 (Quick Wins) is fully closed.** QW-3 (fail-open `SubscriptionStatus` default — a real security-relevant client-side gap, fixed alongside Phase 1's server-side subscription work), QW-4 (`.autoDispose` on all 19 flagged providers, including `pendingBookingCountProvider` — the single highest-leverage fix in the whole audit), QW-5 (2 dead files + 4 unused packages removed), QW-6 (`onboarding.png` recompressed 1.8MB→512KB, `icon.png` removed from the shipped bundle entirely) all closed this iteration. This is the driver of the Engineering jump (74→~82) and a further Security nudge (74→~76).

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

### Phase 2 — Must-Fix-if-Apple-Rejects-Again — 4/6 closed, code-complete pending 2 process items
- [x] MFR-1 Pre-upload checklist automation (dart-define/demo-account script) — closed iteration 5, see LOG
- [ ] MFR-2 Paywall App Review Notes — process item, not code; revisit at resubmission time
- [x] MFR-3 iOS background-location authorization gap — closed iteration 3, see LOG
- [x] MFR-4 Crash reporting SDK (= MED-9 partial) — closed iteration 3, see LOG
- [x] MFR-5 App-level `PrivacyInfo.xcprivacy` — closed iteration 3, see LOG
- [ ] MFR-6 Ad Boost payment-model guardrail — no code exists yet; watch item, block if Ad Boost work starts before this is resolved

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

### Phase 4 — Medium Improvements
- [x] MED server-side amount recomputation — see #1 above
- [x] MED ownership/`WITH CHECK` fixes — see #2/#8 above
- [x] MED-3 `menu-item-photos` storage policy scoping — see #9 above
- [x] MED tighten `profiles` SELECT — see #6 above
- [x] MED agent sender-check fixes — see #4/#5 above
- [x] MED-6 Idempotency key + order-cancel precondition — see #13/#14 above. **Not fully done: "compensating refund/alert" half of this item (auto-refund if placeOrder fails after charge) was not implemented — the fix instead makes retry safe via idempotency, which resolves the same user-facing harm via a different mechanism. Note this explicitly rather than silently claim the original sub-item.**
- [x] MED-7 Subscription-status check in payment functions + `fetchActiveTrucks` filter — see #15 above
- [ ] MED-8 `flutter_secure_storage` wiring — not started
- [ ] MED-9 Crash reporting (done, see MFR-4 above) + shared error/snackbar helper (not started) — split item, only half closed
- [x] MED-10 `delete-account` transactional fix — see #7 above. **Storage-object cleanup (avatar/truck photos) still not done — separate gap, needs Storage API calls from the Edge Function, noted in LOG.**
- [ ] MED-11 Batch `truck_profile_screen.dart`'s 6 round-trips — not started
- [ ] MED-12 Memoize map screen clustering (= #18) — not started
- [x] MED-13 Materialize migrations into git — closed iteration 1

### Phase 5 — Major Architecture Improvements (still blocked: Phase 2 not started — Hard Stop #5)
- [ ] ARCH-1 Domain/data-model layer separation — not started
- [ ] ARCH-2 Testing seam/mocking infrastructure — not started (prerequisite for rigorous automated regression tests on every item closed via live/branch verification so far — see Observed section)
- [ ] ARCH-3 Codebase-wide pagination + timeout pattern (= #17) — not started
- [ ] ARCH-4 Decompose six god screens — not started
- [ ] ARCH-5 Rebuild image pipeline — not started
- [ ] ARCH-6 AI agent trust-boundary shared library — not started
- [ ] ARCH-7 Agent dispatcher-vs-cron decision doc (= P6-3) — not started

### Phase 6 — Non-code deliverables
- [ ] P6-1 Cold-start GTM memo — not started
- [ ] P6-2 Accessibility roadmap (15-20 highest-traffic controls, priority order) — not started
- [ ] P6-3 Agent architecture decision doc — see ARCH-7 above

---

## Awaiting sign-off (Hard Stops)

- **Hard Stop #1 (rotate/regenerate secret):** `GOOGLE_PLACES_API_KEY`'s actual value was never rotated in Google Cloud Console — only proxied so it stops shipping in *future* builds. If it leaked from any previously-built APK/IPA before today, it's still valid and usable until rotated. Need you to rotate it in GCP and give me the new value to set as the Edge Function secret (not committed anywhere).
- **Hard Stop #6 (App Store submission):** current build was pulled from review per your decision last session — resubmission stays yours to trigger once Ship-Readiness Gate (§12) passes. Not close yet — Phase 2 hasn't started.

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

## Next action

Phase 2 and Phase 3 are both code-complete. Move to Phase 4's remaining items: MED-8 (`flutter_secure_storage` wiring), MED-9's shared error/snackbar helper half (crash reporting half already done via MFR-4), MED-11 (batch `truck_profile_screen.dart`'s 6 round-trips), MED-12 (memoize map screen clustering, = #18 — also closes a live-observed UX bug per performance.md §2). None of these need the Supabase branch. After Phase 4, Phase 5 (Major Architecture) remains blocked by Hard Stop #5 until Phase 2's remaining process items (MFR-2, MFR-6) are formally closed at resubmission time — treat as effectively unblockable for code work purposes right now.
