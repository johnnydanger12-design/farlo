# Farlo — Remediation Status

**This is a living status document, not an audit report.** The ten reports in `audit/` (`architecture.md` through `product-review.md`, plus `FARLO_FINAL_AUDIT.md`) are point-in-time snapshots — they describe what was true when each phase ran and are intentionally left unedited as historical record. This file tracks what's actually been fixed since, cross-referenced back to the findings that motivated each change. Update it as remediation continues; don't edit the original reports.

Last updated: 2026-07-04, after the first remediation pass (9 items, addressing `FARLO_FINAL_AUDIT.md`'s "Immediate Risks" list).

---

## Fixed and live (backend/Supabase — took effect immediately on deploy)

| # | Finding | Source | What was done | Where |
|---|---|---|---|---|
| 1 | `invite_employee_by_email` RPC had no ownership check — anyone could join any truck as an employee | `supabase-audit.md` Critical #2; `security.md` Abuse Scenario #3 | Added `auth_user_owns_truck(p_truck_id)` check; raises on failure | DB function, migration `fix_invite_employee_by_email_ownership_check` |
| 2 | `employee_shifts_update_own`/`scheduled_shifts_employee_update_status` had no real column/value restriction — employees could falsify clock times or rewrite shift details | `security.md` N3/N4 | `employee_shifts`: INSERT/UPDATE now require clock timestamps within 10 min of `now()`, and UPDATE only while the shift is still open. `scheduled_shifts`: new `BEFORE UPDATE` trigger blocks employees from changing anything but `status` | DB policies + trigger, migration `restrict_employee_self_service_timesheet_and_shift_columns` |
| 3 | `profiles` table readable by every authenticated user (`USING (true)`), including email + Stripe Connect ID, realtime-broadcast to everyone | `supabase-audit.md` Critical #3; `security.md` §11 | SELECT policy tightened to self-only (`auth.uid() = id`); added 4 narrow `SECURITY DEFINER` RPCs for the legitimate cross-user reads (transfer counterparty, employee roster, stripe-connected check, email lookup) | DB policy + functions, migrations `tighten_profiles_select_add_narrow_lookup_functions`, `restore_legitimate_profile_embed_reads` |
| 4 | `create-payment-intent`/`create-booking-payment-intent` trusted a client-supplied amount | `supabase-audit.md` Critical #1; `security.md` Abuse Scenario #1 | Both now recompute the charge server-side — `create-payment-intent` from real `menu_items.price × quantity`, `create-booking-payment-intent` from the stored `booking_deposits`/`booking_quotes.amount` row. Client-supplied amount is no longer read at all | Edge Functions, deployed |
| 5 | `prospect-businesses` had no authentication — unlimited paid Google Places calls + service-role writes | `supabase-audit.md` Critical #12; `ai-agents.md` Top Risk #3 | Added the same `requireAgentSecret()` gate its sibling agent functions already use; `agent-miles` updated to send the bearer token | Edge Functions, deployed |
| 6 | `agent-aiden-inbox`'s sender allowlist tested the raw, unparsed `From:` header — spoofable via display name | `ai-agents.md` Top Risk #2 | Now tests `extractEmailAddress()`'s output against an anchored, exact-match regex | Edge Function, deployed |
| 7 | `agent-aiden-supervisor` applied zero sender filtering to inbound email fed into a directive-editing LLM | `ai-agents.md` Top Risk #1 | Added the same allowlist filter before messages enter the synthesis prompt | Edge Function, deployed |
| 8 | `GOOGLE_PLACES_API_KEY` compiled into the shipped Flutter binary — extractable, unrestricted, billed key | `security.md` N1 | Added a `places-autocomplete` proxy Edge Function; removed the key (and the unused `RESEND_API_KEY`) from `.env.json` | New Edge Function, deployed; local `.env.json` |
| 9 | 74 live Supabase migrations existed only on the remote project, no local source | `supabase-audit.md` §13 | Real `pg_dump` schema capture (29 tables, 84 RLS policies, 28 functions, 7 triggers) via direct Postgres connection (Docker wasn't available for the CLI's own path) | `supabase/config.toml`, `supabase/migrations/20260704000000_baseline_schema.sql` |
| 10 | `searchTrucks()` reachable-crash trigger — a test truck with null coordinates was `is_active = true` | `bugs.md` Executive Summary #1 | **Live data mitigated**, not code-fixed: deactivated the one truck in that state. The actual root cause (`map_repository.dart`'s `searchTrucks()` missing the null-location filter `fetchActiveTrucks()` already has) is still open — see below | Data change only |

## Client-side changes made, not yet shipped

These are committed to the repo (commit `b6030ac`) but require a new Flutter build to take effect — they do not touch the binary previously submitted to Apple:

- `lib/features/orders/repositories/orders_repository.dart`, `order_cart_sheet.dart` — send `items` instead of a computed amount to `create-payment-intent`.
- `lib/features/bookings/repositories/bookings_repository.dart`, `my_requests_screen.dart` — drop the now-unused client-computed amount for booking payments.
- `lib/features/account/providers/transfer_provider.dart`, `transfer_truck_sheet.dart`, `lib/features/employees/screens/employee_dashboard_screen.dart`, `lib/features/owner_dashboard/screens/dashboard_screen.dart` — route the four legitimate cross-user profile reads through the new RPCs instead of raw table reads.
- `lib/features/bookings/widgets/places_autocomplete_field.dart` — calls the `places-autocomplete` proxy instead of Google directly.

## ⚠️ Known consequence of this pass: order placement is currently broken on the previously-submitted binary

`create-payment-intent`'s new contract requires an `items` array so it can recompute the charge server-side — there is no secure way to keep it backward-compatible, because the old request shape (`truck_id` + `amount_cents`) never told the server what was actually in the cart. Since Edge Functions are shared live infrastructure, **the binary that was submitted to Apple (and any current tester's installed copy) will get a 400 error placing any food order**, starting from when this fix deployed (2026-07-04).

`create-booking-payment-intent` (deposit/invoice payments) is unaffected — the old client already sends everything the new server needs.

**Decision (2026-07-04):** rather than patch around this, the pending App Store submission is being pulled back manually (App Store Connect — not something this tooling can do) so the app can be fixed properly and resubmitted as one coherent build once it scores well across the audit set, rather than rushing a partial fix through review. Do not resubmit the currently-submitted binary as-is.

## Not addressed in this pass

Everything else in `FARLO_FINAL_AUDIT.md`'s Top 20 Issues, Quick Wins, Medium Improvements, and Major Architecture Improvements sections is still open, including (not exhaustive — see that document for the full list):

- The `searchTrucks()` code fix itself (§ above — only the live data trigger was neutralized).
- Unescaped search input breaking PostgREST filters (`bugs.md` §2.7.1).
- Consumer-cancel vs. owner-accept order race; no Stripe idempotency key on the order/booking payment flows.
- Subscription lapse never rechecked once a truck is live.
- 19 non-`.autoDispose` Riverpod providers; zero pagination/request timeouts codebase-wide.
- Map screen's per-frame rebuild (the underlying cause of the stacked-pin bug).
- Zero accessibility infrastructure.
- The product-level cold-start/go-to-market problem.
- App Store checklist items: crash reporting SDK, app-level `PrivacyInfo.xcprivacy`, the iOS background-location authorization gap, the Ad Boost payment-model risk.

None of these were in scope for this pass (they were prioritized as Quick Wins/Medium/Major, not Immediate Risks) — this section exists so this document doesn't imply more was fixed than actually was.
