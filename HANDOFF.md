# HANDOFF.md — Good Truck Finder
_Last updated: Employee sub-accounts + dark mode polish session. Read time: ~2 min._

---

## Interrupted Task

Nothing mid-flight. All changes complete, `flutter analyze` is clean. Commit before continuing.

---

## Current State

`flutter analyze` — zero issues.

| Feature | Status |
|---|---|
| Dark mode — `write_review_sheet`, `review_card`, `register_screen`, `register_owner_screen` | ✓ All hardcoded colors replaced |
| Sign-out + Appearance dialogs — white bg in light mode | ✓ `Theme.of(context).brightness == Brightness.light ? Colors.white : null` |
| Register screen buttons match Sign In color | ✓ `backgroundColor: AppColors.primary` on all three register buttons |
| Menu board + Hours section on truck profile | ✓ `_Section` widget uses `colorScheme.surface` |
| Theme mode scoped per user | ✓ Key is `theme_mode_<userId>` — switching accounts no longer bleeds theme |
| Employee sub-accounts | ✓ DB + RLS + owner manage screen + employee go-live card + auto-link on login + invite email edge function |

---

## Architecture

Feature-based Flutter under `lib/features/<name>/` — each feature owns models, providers, repositories, screens. New `lib/features/employees/` follows same pattern. Consumer accounts that are added as employees keep their consumer shell but see a **pinned go-live card** at the bottom of the map screen (`EmployeeGoLiveCard`). The card uses `employeeGoLiveProvider(truckId)` (family notifier, truck-id parameterised). Owner manages employees at `/dashboard/employees` via `truckEmployeesProvider(truckId)`. Auto-linking happens in `AuthNotifier._claimInvites()` on every sign-in/sign-up — zero effort for the employee. RLS is protected by two `SECURITY DEFINER` functions (`auth_user_owns_truck`, `auth_user_is_employee`) that break a cross-table recursion cycle.

---

## Recent Decisions (non-obvious)

**RLS infinite recursion — SECURITY DEFINER functions.** The `food_trucks` employee policies queried `truck_employees`, whose owner policy queried `food_trucks` → infinite loop. Fixed with two `SECURITY DEFINER` SQL functions (`auth_user_owns_truck`, `auth_user_is_employee`) that read the target table bypassing its RLS. This is the standard Postgres fix; don't revert to inline subqueries.

**No profiles join on `truck_employees`.** `truck_employees.user_id` has an FK to `auth.users`, not `profiles`. PostgREST requires an explicit FK to auto-join. Rather than adding a migration, the query fetches `*` only and the tile falls back to `invitedEmail` when `displayName` is null. Acceptable — employees are shown by email until name lookup is added.

**`FamilyAsyncNotifier` doesn't exist in Riverpod 3.3.2.** Family async notifiers must use constructor injection: `AsyncNotifierProvider.family((arg) => MyNotifier(arg))` where `MyNotifier extends AsyncNotifier<T>` and stores `arg` as a field. `FamilyAsyncNotifier` as a superclass causes "classes can only extend other classes" compile error.

**Employee accounts are pure consumer accounts.** No new role, no schema changes to `profiles`. An employee is just a consumer whose email appears in `truck_employees` with `status = 'active'`. If they're removed they still use the app normally as a consumer.

**Auto-link is idempotent.** `_claimInvites` runs on every sign-in/sign-up with an UPDATE where `invited_email = email AND status = 'pending'`. If there's nothing to claim it's a no-op. Safe to call multiple times.

**Invite email uses `onboarding@resend.dev`.** This is Resend's free test address. Works for testing but can only deliver to the Resend account owner's email. Switch to a verified domain (`goodtruckfinder.com`) in Resend dashboard + update edge function `from:` field before production.

**Theme mode is per-user, falls back to System for guests.** Key `theme_mode_guest` is used when `user_id` is null. Switching accounts now loads each account's saved preference independently.

---

## Traps / Dead Ends

| Trap | What Happened | Don't Repeat |
|---|---|---|
| RLS infinite recursion | `food_trucks` ↔ `truck_employees` policies created a cycle | Always use `SECURITY DEFINER` functions for cross-table RLS subqueries |
| `profiles` join on `truck_employees` | No FK exists → PGRST200 error | Can't auto-join without an explicit FK; fetch `*` and handle null display name |
| `FamilyAsyncNotifier` as superclass | Compile error in Riverpod 3.3.2 — not a valid class | Pass arg via constructor; notifier extends plain `AsyncNotifier<T>` |
| `Navigator.pop(context)` in shell dialog | Hits branch Navigator → black screen | Always use `dialogContext` from the builder param |
| Watching `authProvider` in `routerProvider` | Recreates GoRouter on every auth change → double redirects | Use `ref.read` in redirect only |
| `StateProvider` (Riverpod 3.x) | Removed | Use `NotifierProvider` + `Notifier` |
| `valueOrNull` (Riverpod 3.x) | Removed | Use `asData?.value` |
| `RadioListTile.groupValue` / `onChanged` | Deprecated Flutter 3.32 | Use `RadioGroup` or manual `ListTile` + checkmark |
| `const BoxDecoration(color: Theme.of(context)...)` | Compile error — not const | Drop `const` from `BoxDecoration`; move `const` inside to `BorderRadius` only |
| DB trigger `on_auth_user_created` | Was creating duplicate profile rows | Dropped — do not re-add. Use `upsert` for profiles |
| Email confirmation ON | Signup creates no session → redirect loop | Must stay OFF in Supabase Auth settings |

---

## Modified Files (this session)

| File | Change |
|---|---|
| `lib/features/reviews/widgets/write_review_sheet.dart` | Drag handle + text field fill/borders → `colorScheme` tokens |
| `lib/features/reviews/widgets/review_card.dart` | Container surface + border → `colorScheme` tokens |
| `lib/features/auth/screens/register_screen.dart` | Removed hardcoded scaffold/AppBar bg; added `backgroundColor: AppColors.primary` to button |
| `lib/features/auth/screens/register_owner_screen.dart` | Same as register_screen |
| `lib/features/account/screens/account_screen.dart` | Sign-out + Appearance dialogs: white in light mode, theme in dark; removed old `Colors.white` hardcode |
| `lib/features/food_trucks/screens/truck_profile_screen.dart` | `_Section` widget container → `colorScheme.surface` |
| `lib/core/providers/theme_provider.dart` | Key scoped to `theme_mode_<userId>`; watches `authProvider.future` so it rebuilds on account switch |
| `lib/core/constants/supabase_constants.dart` | Added `truckEmployeesTable` |
| `lib/features/auth/providers/auth_provider.dart` | Added `_claimInvites()` called after every sign-in/sign-up |
| `lib/features/owner_dashboard/screens/dashboard_screen.dart` | Added Employees tile → `/dashboard/employees` |
| `lib/features/map/screens/map_screen.dart` | Watches `myEmployeeTrucksProvider`; renders `EmployeeGoLiveCard` stack pinned at bottom |
| `lib/router.dart` | Added `/dashboard/employees` route |
| **NEW** `lib/features/employees/models/truck_employee.dart` | Model for `truck_employees` rows |
| **NEW** `lib/features/employees/repositories/employees_repository.dart` | CRUD: fetch, invite, remove, claimPendingInvites, fetchEmployeeTrucks |
| **NEW** `lib/features/employees/providers/employees_provider.dart` | `truckEmployeesProvider` (owner), `myEmployeeTrucksProvider` (employee), `employeeGoLiveProvider` (go-live notifier), shared `handleGoLive()` |
| **NEW** `lib/features/employees/screens/employees_screen.dart` | Owner: list + add + remove employees |
| **NEW** `lib/features/employees/widgets/employee_go_live_card.dart` | Pinned card on map with live toggle for employee's assigned truck |
| **Supabase migration** `truck_employees` | New table + RLS policies (pending/active/removed lifecycle) |
| **Supabase migration** `fix_rls_recursion_truck_employees` | `auth_user_owns_truck()` + `auth_user_is_employee()` SECURITY DEFINER functions; rewrote employee RLS policies |
| **Supabase Edge Function** `send-employee-invite` v3 | Sends invite email via Resend; from `onboarding@resend.dev`; silent no-op if `RESEND_API_KEY` not set |

---

## Known Issues

| Issue | Severity | Notes |
|---|---|---|
| Employee display name not shown in owner's list | Low | No FK from `truck_employees.user_id` → `profiles.id`; falls back to email. Add FK + rejoin if name display matters |
| Invite email from address is `onboarding@resend.dev` | Medium (prod) | Test only — Resend only delivers to account owner's email. Verify `goodtruckfinder.com` in Resend + update edge function `from:` |
| `REVENUECAT_WEBHOOK_SECRET` not set in Supabase | High (subscriptions) | Webhook accepts all requests until configured |
| CartoDB tiles require attribution in production | Medium | Must credit © CARTO + © OpenStreetMap in App Store build |
| No shimmer/skeleton loading | Low | Phase 6 |
| No delete account flow | Low | Phase 6 — App Store required |
| No menu PDF/image upload UI | Medium | Columns exist, no picker |
| Recent searches not scoped to user | Low | SharedPreferences key `recent_searches` is device-global |
| RevenueCat purchase untestable on simulator | Expected | Requires real device + sandbox Apple ID |

---

## Next Steps (priority order)

1. **Commit this session's work** — everything is clean, nothing in flight.
2. **Phase 6 — Polish** — `shimmer` skeletons on map/profile load. Pull-to-refresh on reviews. No-internet banner (`connectivity_plus`). Error retry buttons.
3. **App icon + splash** — `flutter_launcher_icons` + `flutter_native_splash`. High visual impact for demos.
4. **RevenueCat manual setup** — App Store Connect product (`com.goodtruckfinder.owner.monthly`), RC dashboard entitlement `premium`, Apple API key → `.env.json`. Wire `REVENUECAT_WEBHOOK_SECRET` in Supabase Edge Function secrets + RC webhook URL.
5. **Resend production domain** — Verify `goodtruckfinder.com` in Resend, update edge function `from:` field, redeploy.

---

## Setup Gotchas

- **Run**: `flutter run --dart-define-from-file=.env.json` — plain `flutter run` hits an assert
- **`.env.json`** (gitignored, project root) — keys: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `REVENUECAT_APPLE_KEY`, `REVENUECAT_GOOGLE_KEY`
- **Supabase project**: `weflrxyerxpsafcdetya` — `https://weflrxyerxpsafcdetya.supabase.co`
- **Email confirmation**: must be OFF (Supabase → Auth → Providers → Email)
- **DB trigger**: `on_auth_user_created` is dropped — do not re-add
- **RLS functions**: `auth_user_owns_truck(uuid)` + `auth_user_is_employee(uuid)` are SECURITY DEFINER — required to prevent recursion, do not drop
- **Flutter**: 3.44.1 stable, darwin-arm64. Xcode 26.5, Android SDK 36.1.0
- **Riverpod**: 3.3.2 — no `valueOrNull`, no `StateProvider`, no `FamilyAsyncNotifier`
- **go_router**: 17.3.0 — dialog `Navigator.pop` must use `dialogContext` not widget context
- **purchases_flutter**: 10.2.3 — `PurchaseParams.package(pkg)` is the correct purchase API
- **RC entitlement ID**: `premium` — must match RevenueCat dashboard exactly
- **shared_preferences**: 2.3.2 — theme mode key: `theme_mode_<userId>`, recent searches: `recent_searches` (device-global)
- **Dark tiles**: CartoDB Dark Matter — free for dev, requires attribution for production
- **Resend**: invite email from `onboarding@resend.dev` (test only). `RESEND_API_KEY` set in Supabase → Edge Functions → `send-employee-invite` → Secrets
- **GitHub**: `https://github.com/johnnydanger12-design/good-truck-finder.git`
- **Plan file**: `/Users/johnny/.claude/plans/project-planning-good-truck-compiled-pony.md`
