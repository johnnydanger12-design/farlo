# HANDOFF.md — Good Truck Finder
_Last updated: Phase 1, auth bug-fix session 2. Read time: ~2 min._

---

## Interrupted Task

Fixing owner sign-up. The `signUpOwner` was failing with `profiles_pkey` duplicate key because a DB trigger was auto-inserting a profile row before the app's own insert ran. Two fixes were just applied (see Modified Files) but **have not been verified yet by the user**. User needs to: drop the trigger in Supabase, clean up test data, and re-test sign-up.

---

## Current State

- Flutter analyzes clean (`flutter analyze`: no issues)
- Builds and runs on iOS simulator (`iPhone 17`)
- App opens to `/login` correctly (auth redirect works)
- Sign-in: **works** ✓
- Consumer sign-up: **assumed working** (not re-tested this session)
- Owner sign-up: **fix applied, unverified** — trigger drop SQL provided, upsert change made
- Sign-out: **fix applied, assumed working** — dialog context bug fixed + AppShell fallback added
- Supabase tables: `profiles`, `food_trucks`, `subscriptions` all created and have RLS ✓
- All Phase 2–5 screens are stubs

---

## Architecture

Feature-based Flutter app. `lib/features/<name>/` holds models, providers, repositories, screens per feature. `lib/core/` has shared constants/widgets. `lib/shells/` has two bottom-nav shells gated by role. `main.dart` inits Supabase and wraps everything in `ProviderScope`. `app_shell.dart` is the root `MaterialApp.router` (also holds a `ref.listen` for sign-out navigation). `router.dart` owns a single `GoRouter` created once inside a `Provider` with `_AuthListenable` bridging Riverpod → GoRouter's `refreshListenable`. `AuthNotifier` (AsyncNotifier) holds `AppUser?`. Supabase is the full backend.

---

## Recent Decisions (non-obvious)

**`upsert` not `insert` for profiles** — A DB trigger (`on_auth_user_created`) was in the original SQL and fires immediately when `auth.signUp()` resolves, inserting a profile row before the app code runs. App code then hit `profiles_pkey` duplicate key. Fixed by: (1) dropping the trigger via SQL so app code is sole owner of profile creation, and (2) switching profile inserts to `upsert` as a safety net against any future trigger or retry. Don't revert to `insert`.

**`dialogContext` not outer `context` in sign-out dialog** — `showDialog` pushes onto the root Navigator (`useRootNavigator: true` by default). `StatefulShellRoute` gives each branch its own nested Navigator. Using the outer `BuildContext` (from `AccountScreen.build`) for `Navigator.pop` resolved to the **branch** Navigator, not the root. The branch navigator tried to pop `AccountScreen` (its only route), removing it and leaving the branch empty — hence the black screen. Always use the dialog builder's own `context` parameter for `Navigator.pop` inside dialogs when you're inside a shell route.

**`ref.listen` in `AppShell.build()` for sign-out navigation** — `_AuthListenable` notifies GoRouter to re-run the redirect when auth state changes, but the redirect firing and the widget rebuild are asynchronous. Added a direct `ref.listen` in `AppShell` that calls `router.go('/login')` when user transitions from authenticated → null. This is the belt-and-suspenders guarantee that navigation happens even if the redirect timing is off.

**`ref.listen` NOT in `AuthNotifier.build()`** — Supabase fires `onAuthStateChange` the instant `signUp()` resolves, before the profile row is inserted. If we listened and called `ref.invalidateSelf()`, `fetchCurrentUser()` would run, find no profile, return null, and the router would kick the user to login mid-signup. This listener must never be re-added to `AuthNotifier.build()`.

**Router created ONCE with `ref.read` in redirect** — Watching `authProvider` inside `routerProvider` would recreate `GoRouter` on every auth change → double redirect loops. Router is a non-auto-dispose `Provider`, redirect uses `ref.read`.

**`asData?.value` not `valueOrNull`** — Riverpod 3.x removed `valueOrNull`. Use `asData?.value`.

**`publishableKey` not `anonKey`** — `supabase_flutter` 2.x deprecated `anonKey`. Use `publishableKey` from Supabase dashboard → Settings → API.

---

## Traps / Dead Ends

| Trap | What Happened | Don't Repeat |
|---|---|---|
| `Navigator.pop(context)` in dialog inside shell | Used AccountScreen context → hit branch Navigator → popped AccountScreen → black screen | Use `dialogContext` from builder param |
| DB trigger + manual profile insert | Trigger fires before app code → `profiles_pkey` duplicate | Trigger dropped; use `upsert` for profiles |
| Deleting test user from wrong place | Deleted from Table Editor (profile row) but not from Authentication → Users → "user already registered" on retry | Delete from Authentication → Users first; cascade handles profile |
| `riverpod_lint` / `custom_lint` | Version conflict with Riverpod 3.3.2 | Skip — incompatible |
| `valueOrNull` getter | Removed in Riverpod 3.x | Use `asData?.value` |
| `__` for unused params | Dart linter flags `unnecessary_underscores` | Use `c, s` or single `_` |
| `ref.listen` in `AsyncNotifier.build()` | Race: Supabase auth event fires before profile insert → null user → redirect to login mid-signup | Do not add back |
| Watching `authProvider` in `routerProvider` | Recreated GoRouter on every auth change → double redirect loops | Use `ref.read` in redirect only |
| Email confirmation ON in Supabase | Signup creates no session → `fetchCurrentUser()` returns null → redirect loop | Must be OFF |

---

## Modified Files (cumulative — both sessions)

| File | Summary |
|---|---|
| `lib/main.dart` | Supabase.initialize with `publishableKey`. ProviderScope wraps AppShell. |
| `lib/app_shell.dart` | Root MaterialApp.router. Added `ref.listen` on `authProvider` → calls `router.go('/login')` when user becomes null (sign-out fallback). |
| `lib/router.dart` | GoRouter created once; redirect uses `ref.read` + `asData?.value`; `_AuthListenable` bridges Riverpod → Listenable. |
| `lib/features/auth/providers/auth_provider.dart` | `AuthNotifier` (AsyncNotifier). No `ref.listen`/`invalidateSelf`. State managed by explicit method calls only. |
| `lib/features/auth/repositories/auth_repository.dart` | All Supabase auth calls. Profile inserts changed from `.insert()` to `.upsert()` to survive trigger race. |
| `lib/features/auth/models/app_user.dart` | `AppUser` + `UserRole` enum. |
| `lib/features/auth/screens/login_screen.dart` | Email+password login form. |
| `lib/features/auth/screens/register_screen.dart` | Consumer signup form. |
| `lib/features/auth/screens/register_owner_screen.dart` | Owner signup form. Error snackbar duration 10s; `debugPrint` on error for terminal visibility. |
| `lib/features/account/screens/account_screen.dart` | Sign-out dialog uses `dialogContext` (not outer context) for `Navigator.pop`. Null user shows spinner not blank. `context.go('/login')` after signOut. |
| `lib/shells/consumer_shell.dart` | NavigationBar: Map/Favorites/Account. |
| `lib/shells/owner_shell.dart` | NavigationBar: Dashboard/Map/Account. |
| `lib/core/constants/` | `app_colors.dart`, `app_text_styles.dart`, `app_spacing.dart`, `supabase_constants.dart` |
| `lib/core/widgets/` | `app_button.dart`, `app_text_field.dart`, `star_rating_widget.dart`, `error_view.dart`, `loading_overlay.dart` |
| Stub screens | `map_screen.dart`, `favorites_screen.dart`, `dashboard_screen.dart` — placeholder text only |

---

## Known Issues

| Issue | Severity | Status |
|---|---|---|
| Owner sign-up `profiles_pkey` duplicate | **Critical** | Fix applied (upsert + drop trigger SQL provided), not yet user-verified |
| Trigger must be dropped in Supabase | **Critical** | SQL provided in last message, user must run it |
| Test data cleanup needed before re-testing | **Critical** | User must delete test account from Authentication → Users + orphaned profile row |
| Sign-out black screen | **Critical** | Fixed (dialog context + AppShell listener), not re-confirmed post-fix |
| `register_owner_screen.dart` snackbar duration | Low | Left at 10s for debugging — revert to 4s once sign-up is confirmed working |
| `debugPrint` left in register_owner_screen | Low | Remove before ship |
| No Phase 2–5 features | Expected | All placeholder screens |

---

## Next Steps (in order)

1. **Verify owner sign-up**: Run trigger drop SQL in Supabase → delete test data → re-test full sign-up → confirm landing on Dashboard tab
2. **Verify consumer sign-up**: Register as consumer → confirm landing on Map tab
3. **Verify sign-out**: Sign in → tap Account → Sign Out → confirm landing on Login
4. **Commit auth fixes**: Once all three above pass, commit all modified files with message `"fix: auth flow — sign-out black screen, owner signup trigger conflict"`
5. **Begin Phase 2 — Map Core**: Add `flutter_map`, `latlong2`, `geolocator`, `permission_handler`, `cached_network_image`. Build MapScreen with OSM tiles, truck markers, bottom sheet.

---

## Setup Gotchas

- **Run command**: `flutter run --dart-define-from-file=.env.json` — plain `flutter run` hits an assert and shows a blank screen
- **`.env.json`** exists locally at project root (gitignored). Keys: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`. Use the "Publishable key" from Supabase dashboard → Settings → API, NOT the "anon public" JWT
- **Supabase project ID**: `weflrxyerxpsafcdetya`
- **Email confirmation**: Must be OFF — Supabase dashboard → Authentication → Providers → Email → toggle "Confirm email" OFF
- **DB trigger**: Must be dropped — `drop trigger if exists on_auth_user_created on auth.users; drop function if exists public.handle_new_user();`
- **Flutter**: 3.44.1 stable, darwin-arm64 (M1). `flutter analyze` must pass before any commit
- **Riverpod**: 3.3.2 — `valueOrNull` does not exist, use `asData?.value`. `riverpod_lint` cannot be added (version conflict)
- **go_router**: 17.3.0 — `StatefulShellRoute` gives each branch its own nested Navigator; always use dialog builder's own context for `Navigator.pop` inside shells
- **GitHub**: `https://github.com/johnnydanger12-design/good-truck-finder.git`
- **Plan file**: `/Users/johnny/.claude/plans/project-planning-good-truck-compiled-pony.md`
- **Memory file**: `/Users/johnny/.claude/projects/-Users-johnny-Desktop-Good-Truck-Finder/memory/project_good_truck_finder.md`
