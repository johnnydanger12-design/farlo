# HANDOFF.md — Good Truck Finder
_Last updated: Booking form + Dynamic Island + offline notifications session. Read time: ~2 min._

---

## Interrupted Task

Nothing mid-flight. All changes committed and pushed to GitHub.

---

## Current State

`flutter analyze` — zero issues.

| Feature | Status |
|---|---|
| GitHub push unblocked | ✓ History rewritten, old PAT removed, new PAT active |
| `font_awesome_flutter` v11 | ✓ Upgraded from 10.x; `FaIconData` type used in `_SocialButton` |
| Going-offline alert (owner) | ✓ `truck_closed` action in edge fn v4; `sendTruckClosedAlert` in service |
| `truck_open` bug fixed | ✓ Was silently failing — `user_id` was missing from request body |
| Notification pref label | ✓ "Going Live Alert" → "Live Status Alerts / goes live or offline" |
| Booking form — duration | ✓ DB column added; combined schedule picker replaces 3 separate popups |
| Booking form — required fields | ✓ name, email, location, guest count, date, start time, duration all required |
| Booking form — Dynamic Island | ✓ Real fix: `viewPadding.top` captured before modal, passed explicitly |
| Edge fn `send-booking-notification` | ✓ v4 — truck_open + truck_closed + booking actions |

---

## Architecture

Feature-based Flutter under `lib/features/<name>/` — each owns models, providers, repositories, screens/widgets. Supabase is the only backend; RLS enforced via two `SECURITY DEFINER` functions (`auth_user_owns_truck`, `auth_user_is_employee`) that break cross-table recursion. GoRouter 17.x handles nav via shell routes; `authProvider` is `ref.read` (not watched) in router redirect to avoid double-redirects. Firebase Messaging handles push on both platforms; tokens in `push_tokens` (one per user per platform). Notification prefs in `notification_preferences` — no row means all defaults true. Edge functions check prefs before sending. Social media handles stored without `@`; URLs built in code.

---

## Recent Decisions (non-obvious)

**Dynamic Island fix requires explicit padding, not SafeArea.** Flutter's `showModalBottomSheet` internally calls `MediaQuery.removePadding(removeTop: true)` on the route, which strips `padding.top` from every descendant's MediaQuery. This means `SafeArea(top: true)` inside a modal bottom sheet ALWAYS adds 0 padding regardless of device. The fix: capture `MediaQuery.of(context).viewPadding.top` from the scaffold context *before* calling `showModalBottomSheet`, then pass it as a constructor parameter (`topPadding`) to the sheet widget. Added to drag handle padding directly: `EdgeInsets.only(top: topPadding + 12)`. Same fix applied to `_SchedulePickerSheet`.

**Combined schedule picker — one modal, not three.** Date, start time, and duration were three separate popups. Replaced with `_SchedulePickerSheet`: an embedded `CalendarDatePicker` widget + tappable start time row (opens system time picker) + `ChoiceChip` duration selector, all in one bottom sheet. Done button disabled until duration is selected. Date defaults to 7 days out, time defaults to 12:00 PM. Returns a `_ScheduleResult` record.

**`font_awesome_flutter` v11 breaks `IconData` inheritance.** Flutter made `IconData` a `final` class in a recent version. `font_awesome_flutter` 10.x extended it — compile error. v11 introduces `FaIconData` as its own type, which `FaIcon` accepts. Any widget that stored `IconData icon` to pass to `FaIcon` must change to `FaIconData icon`.

**`sendTruckOpenAlert` was silently a no-op.** The Dart method called the edge function without `user_id` in the body. The edge function requires `user_id` to look up prefs and tokens — without it, it returned `{sent: false, reason: 'no_user_id'}` with no exception thrown. Fixed: both `sendTruckOpenAlert` and new `sendTruckClosedAlert` now pass `auth.currentUser?.id` in the body.

**History rewrite to remove leaked PAT.** Commit `34698d3` had Supabase PAT in `.mcp.json`. Since nothing had been pushed to GitHub yet (push was blocked by secret scanning), `git filter-branch --index-filter 'git rm --cached --ignore-unmatch .mcp.json'` rewrote all 11 commits cleanly. Backup refs cleaned up, PAT rotated in Supabase dashboard. Push now works normally.

**`duration` column is nullable in DB.** Old booking requests won't have a duration. The column is `text` nullable. In-app validation enforces it for new requests; `BookingRequest.fromMap` maps it to `String?`.

---

## Traps / Dead Ends

| Trap | What Happened | Don't Repeat |
|---|---|---|
| `SafeArea(top: true)` in modal | Flutter strips `padding.top` from modal MediaQuery — SafeArea adds 0pt | Capture `viewPadding.top` from scaffold context BEFORE the modal and pass explicitly |
| `FaIcon` accepts `FaIconData` not `IconData` in v11 | Type error at compile time | Any field passed to `FaIcon` must be typed `FaIconData` |
| `sendTruckOpenAlert` missing `user_id` | Silent no-op — edge fn returned `sent: false` with no exception | Always include `user_id` from `auth.currentUser?.id` in truck alert calls |
| `git filter-branch` with unstaged changes | Fails: "Cannot rewrite branches: You have unstaged changes" | `git stash` first, then filter-branch, then `git stash pop` |
| Nested modals strip padding twice | `_SchedulePickerSheet` shown from inside `BookTruckSheet` (also a modal) — same `removeTop` applies | Pass `topPadding` through the chain: caller → `BookTruckSheet` → `_SchedulePickerSheet` |

From previous sessions (still valid):
| Trap | Don't Repeat |
|---|---|
| `latLngToScreenPoint` on MapCamera | Use `latLngToScreenOffset` |
| `?'key': value` null-aware map entry | Use `'key': ?value` |
| `DropdownButtonFormField.value` | Use `initialValue` |
| `FamilyAsyncNotifier` | Not valid — extend plain `AsyncNotifier<T>` |
| `Navigator.pop(context)` in shell dialog | Use `dialogContext` from builder param |
| Watching `authProvider` in `routerProvider` | Use `ref.read` only |
| `StateProvider` / `valueOrNull` | Removed in Riverpod 3.x — use `NotifierProvider`, `asData?.value` |
| DB trigger `on_auth_user_created` | Dropped — do not re-add. Use `upsert` for profiles |
| Email confirmation ON | Signup creates no session → redirect loop. Must stay OFF |
| RLS recursion on `food_trucks` ↔ `truck_employees` | Use `SECURITY DEFINER` functions |
| SPM + space in path | `%20` double-encoded to `%2520` → pubspec.yaml not found; SPM globally disabled |

---

## Modified Files (this session)

| File | Change |
|---|---|
| `pubspec.yaml` / `pubspec.lock` | `font_awesome_flutter` bumped to `^11.0.0` |
| `lib/features/food_trucks/screens/truck_profile_screen.dart` | Capture `viewPadding.top` before booking modal; pass as `topPadding` |
| `lib/features/account/screens/account_screen.dart` | Notification toggle label: "Going Live Alert" → "Live Status Alerts" |
| `lib/core/push_notification_service.dart` | Fixed `sendTruckOpenAlert` (added `user_id`); added `sendTruckClosedAlert` |
| `lib/features/owner_dashboard/screens/dashboard_screen.dart` | Call `sendTruckClosedAlert` when toggling truck offline (with pref check) |
| `lib/features/bookings/models/booking_request.dart` | Added `duration` field (`String?`) |
| `lib/features/bookings/repositories/bookings_repository.dart` | Added `duration` param; inserts to DB column |
| `lib/features/bookings/widgets/book_truck_sheet.dart` | Full rewrite: combined schedule picker, `topPadding` param, required fields |
| `supabase/functions/send-booking-notification/index.ts` | v4 — added `truck_closed`; fixed `truck_open` to require `user_id` |

---

## Known Issues

| Issue | Severity | Notes |
|---|---|---|
| Push notifications untested on real device | High | Simulator has no APNs. All FCM code is correct but unverified end-to-end |
| `REVENUECAT_WEBHOOK_SECRET` not set | High (subscriptions) | Webhook accepts all requests until configured |
| No rate limiting on announcements | Medium | Owner can spam followers. Add cooldown (e.g., 1/hour) before App Store |
| Invite email from `onboarding@resend.dev` | Medium (prod) | Test only — verify `goodtruckfinder.com` in Resend |
| `aps-environment: development` in entitlements | Medium (prod) | Change to `production` before App Store submission |
| `websiteUrl` no validation | Low | `canLaunchUrl` silently fails on bad input |
| Follower count in announcement sheet has no loading state | Low | Shows `0 followers` while loading instead of a spinner |
| No shimmer/skeleton loading | Low | Phase 6 |
| No delete account flow | Low | **App Store required** — edge function + `auth.admin.deleteUser` + cascade |

---

## Next Steps (priority order)

1. **Test push on real device** — `flutter run --dart-define-from-file=.env.json` on physical iPhone. Verify going-live, going-offline, booking, and follower announcement all arrive.
2. **App icon + splash** — `flutter_launcher_icons` + `flutter_native_splash`. High visual impact for demos.
3. **RevenueCat production setup** — App Store Connect product `com.goodtruckfinder.owner.monthly`, RC entitlement `premium`, Apple API key in `.env.json`, `REVENUECAT_WEBHOOK_SECRET` in Supabase secrets.
4. **Delete account flow** — Required by App Store. Edge function + `auth.admin.deleteUser` + cascade delete profile/trucks/tokens/prefs.
5. **Announcement rate limiting** — Add `last_announcement_at` to `food_trucks`; check in `send-truck-announcement` edge fn before sending.

---

## Setup Gotchas

- **Run**: `flutter run --dart-define-from-file=.env.json` — plain `flutter run` hits an assert
- **`.env.json`** (gitignored, project root) — keys: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `REVENUECAT_APPLE_KEY`, `REVENUECAT_GOOGLE_KEY`
- **SPM disabled globally**: `flutter config --no-enable-swift-package-manager` — do not re-enable; space in project path breaks it
- **CocoaPods**: `ios/Podfile` and `ios/Podfile.lock` are committed. After `flutter clean`, run `flutter run` (it runs pod install automatically)
- **Supabase project**: `weflrxyerxpsafcdetya` — `https://weflrxyerxpsafcdetya.supabase.co`
- **Email confirmation**: must be OFF (Supabase → Auth → Providers → Email)
- **DB trigger**: `on_auth_user_created` is dropped — do not re-add
- **RLS functions**: `auth_user_owns_truck(uuid)` + `auth_user_is_employee(uuid)` are SECURITY DEFINER — required, do not drop
- **`notification_preferences`**: no row = all prefs default true
- **Social media**: handles stored without `@`; URLs constructed in `_SocialSection._urlFor()`
- **Firebase**: `Firebase.apps.isEmpty` guard in `main.dart`; push init is unawaited post-runApp
- **Simulator**: push notifications do not work (no APNs). Test all FCM features on real device only
- **Flutter**: 3.44.1 stable, darwin-arm64. Xcode 26.5
- **Riverpod**: 3.3.2 — no `valueOrNull`, no `StateProvider`, no `FamilyAsyncNotifier`; use `asData?.value`
- **go_router**: 17.3.0 — dialog `Navigator.pop` must use `dialogContext` not widget context
- **font_awesome_flutter**: 11.0.0 — use `FaIcon(icon)` with `FaIconData` type (NOT Flutter's `IconData`). Dark mode: flip black icons (TT/X) to white
- **Dynamic Island**: Do NOT use `SafeArea(top: true)` inside modals — Flutter strips `padding.top`. Capture `MediaQuery.of(context).viewPadding.top` from scaffold context before `showModalBottomSheet` and pass as a constructor param
- **Edge functions**: `send-booking-notification` v4, `send-truck-announcement` v1 — both deployed and active. `FIREBASE_SERVICE_ACCOUNT_JSON` secret is set
- **GitHub**: `https://github.com/johnnydanger12-design/good-truck-finder.git` — push is working (history was rewritten to remove leaked PAT)
- **Plan file**: `/Users/johnny/.claude/plans/project-planning-good-truck-compiled-pony.md`
