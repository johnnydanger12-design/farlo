# Farlo Remediation — Current State

Working branch: `remediation/farlo-a-grade`. Supabase test branch: `remediation` (project ref `iwufrgjtlikkongopheu`, parent `weflrxyerxpsafcdetya`) — schema-only, no seed data except what a given test inserts. Get credentials via `supabase branches get remediation` when needed; never commit them.

**Iteration:** 2 (iteration 1 = last session's pre-protocol pass, reconciled below; iteration 2 = first pass under this protocol).

---

## Scorecard (last updated: iteration 2)

| Area | Baseline | Now (est.) | Target | Weight |
|---|---|---|---|---|
| **Overall** | 64 (D+) | **~68** | ≥90 (A) | — |
| Security | 46 (F) | ~60 | ≥90 | 25% |
| Engineering | 74 (C) | ~76 | ≥90 | 20% |
| Backend/Supabase | 66 (D+) | ~78 | ≥90 | 15% |
| UI/UX | 68 (C-) | 68 | ≥90 | 12% |
| Product | 73 (C+) | 73 | ≥90 | 10% |
| AI Agent System | 58 (D-) | ~70 | ≥90 | 10% |
| App Store Readiness | 70 (C-) | 70 | ≥90 | 8% |

These are rough re-estimates, not a formal re-audit — treat with the same skepticism the rest of this doc asks you to apply to the original citations. None of the seven categories meet their Definition of A (§10 of the operating prompt) yet, even where individual findings are closed, because several Definitions require things not yet done (formal tests on last session's fixes, remaining Criticals, the testing/accessibility/architecture work).

---

## Open items, by phase

Canonical IDs follow `FARLO_FINAL_AUDIT.md`'s Top 20 numbering where an item appears there; `QW-`/`MED-`/`ARCH-`/`MFR-`/`P6-` prefix items that only appear in Quick Wins / Medium / Major Architecture / Must-Fix-if-Rejects / Phase 6 respectively. Duplicates across lists are cross-referenced, not repeated.

### Phase 1 — Immediate Risks
- [x] #1 Payment amount tampering (`create-payment-intent`/`create-booking-payment-intent`) — closed iteration 1, see LOG. **Caveat: introduced a client/server contract break, see "Known blocker" below — not fully closed until that's resolved.**
- [x] #2 `invite_employee_by_email` no ownership check — closed iteration 1
- [x] #3 `GOOGLE_PLACES_API_KEY` embedded client-side — closed iteration 1 (proxied). **The underlying key value itself was never rotated in Google Cloud Console — Hard Stop #1, awaiting sign-off below.**
- [x] #4 `agent-aiden-supervisor` zero sender filtering — closed iteration 1
- [x] #5 `agent-aiden-inbox` spoofable sender allowlist — closed iteration 1
- [x] #6 `profiles` readable by every authenticated user — closed iteration 1
- [ ] #7 Account deletion FK-violation "zombie" accounts — not started
- [x] #8 `employee_shifts_update_own`/`scheduled_shifts` no `WITH CHECK` — closed iteration 1
- [ ] #9 `menu-item-photos` storage bucket over-permissive (Backend Critical #4, still open — blocks Backend-A) — not started
- [x] #10 `prospect-businesses` zero auth — closed iteration 1
- [x] #11 `searchTrucks()` null-coordinate crash — closed iteration 2, see LOG
- [x] #12 Unescaped search input breaking PostgREST filter — closed iteration 2, see LOG (same fix as #11)
- [ ] #13 Consumer-cancel vs. owner-accept order race — not started
- [ ] #14 Stranded Stripe charges / no idempotency key (= MED-6) — not started
- [ ] #15 Subscription lapse never rechecked (= MED-7) — not started

### Phase 2 — Must-Fix-if-Apple-Rejects-Again
- [ ] MFR-1 Pre-upload checklist automation (dart-define/demo-account script) — not started
- [ ] MFR-2 Paywall App Review Notes — process item, not code; revisit at resubmission time
- [ ] MFR-3 iOS background-location authorization gap — not started
- [ ] MFR-4 Crash reporting SDK (= MED-9 partial) — not started
- [ ] MFR-5 App-level `PrivacyInfo.xcprivacy` — not started
- [ ] MFR-6 Ad Boost payment-model guardrail — no code exists yet; watch item, block if Ad Boost work starts before this is resolved

### Phase 3 — Quick Wins
- [x] QW searchTrucks + unescaped filter — see #11/#12 above
- [ ] QW-3 `SubscriptionStatus.fromString` fail-open default — not started
- [ ] QW-4 `.autoDispose` on 19 flagged providers (= #16) — not started
- [ ] QW-5 Delete 2 dead files + 4 unused packages — not started
- [ ] QW-6 Recompress `onboarding.png`/`icon.png` — not started
- [x] QW `requireAgentSecret` on `prospect-businesses` — see #10 above
- [x] QW Google Places key — see #3 above
- [x] QW-9 Remove `RESEND_API_KEY` from client `.env.json` — closed iteration 1
- [ ] QW `PrivacyInfo.xcprivacy` — see MFR-5 above

### Phase 4 — Medium Improvements
- [x] MED server-side amount recomputation — see #1 above
- [x] MED ownership/`WITH CHECK` fixes — see #2/#8 above
- [ ] MED-3 `menu-item-photos` storage policy scoping — see #9 above
- [x] MED tighten `profiles` SELECT — see #6 above
- [x] MED agent sender-check fixes — see #4/#5 above
- [ ] MED-6 Idempotency key + compensating refund/alert + order-cancel precondition — see #13/#14 above
- [ ] MED-7 Subscription-status check in payment functions + `fetchActiveTrucks` filter — see #15 above
- [ ] MED-8 `flutter_secure_storage` wiring — not started
- [ ] MED-9 Crash reporting + shared error/snackbar helper — see MFR-4 above
- [ ] MED-10 `delete-account` transactional fix — see #7 above
- [ ] MED-11 Batch `truck_profile_screen.dart`'s 6 round-trips — not started
- [ ] MED-12 Memoize map screen clustering (= #18) — not started
- [x] MED-13 Materialize migrations into git — closed iteration 1

### Phase 5 — Major Architecture Improvements (do not start ahead of Phases 1-2 closing)
- [ ] ARCH-1 Domain/data-model layer separation — not started
- [ ] ARCH-2 Testing seam/mocking infrastructure — not started (this is also the prerequisite for rigorous red/green tests on several already-"closed" iteration-1 items — see Observed section)
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
- **Hard Stop #6 (App Store submission):** current build was pulled from review per your decision last session — resubmission stays yours to trigger once Ship-Readiness Gate (§12) passes.

## Blocked-technical

(none yet)

## Known blocker (not a Hard Stop, but blocks Ship-Readiness Gate)

`create-payment-intent`'s new required-`items` contract breaks order placement on any binary built before today's fix (including whatever was pulled from App Store review). The matching client code is committed but not shipped. This must close before Ship-Readiness Gate can pass — tracked under #1 above, not a separate item.

## Observed, not yet triaged

- Iteration 1's nine closed items (marked `[x]` above) were verified via live deployment + direct re-query (checked `pg_policies`, ran `flutter analyze`, spot-checked via SQL) — not via the formal red/green automated-test protocol this session is now operating under. They are almost certainly still correctly fixed (the underlying vulnerability is gone), but per §14's validation checklist ("no 'fixed' claim without a runnable test"), they don't yet have regression coverage. Once ARCH-2 (testing infrastructure) exists, backfill tests for these before certifying Security-A or Backend-A.
- `create-booking-payment-intent`'s accidental backward-compatibility (old client already sends what the new server needs) should get an explicit regression test once ARCH-2 lands, so it doesn't silently regress later.

## Next action

Resume with #13 (consumer-cancel vs. owner-accept race) or #9 (`menu-item-photos` storage scoping) — both pure Phase 1, both usable on the `remediation` Supabase branch already provisioned. Recommend #9 next since it's the one remaining open Backend Critical and unblocks Backend/Supabase-A once closed alongside #7.
