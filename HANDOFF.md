# HANDOFF.md — Farlo
_Last updated: Consumer cancel bug fix + notification splits + map keyboard + logo. Read time: ~2 min._

---

## Interrupted Task

None — session ended cleanly on HANDOFF.md write. No mid-flight work.

---

## Current State

| Feature | Status |
|---|---|
| Consumer cancel → owner screen updates in real-time | ✓ Fixed this session (RLS + realtime) |
| Declined / Canceled section auto-expands after action | ✓ Fixed both owner + consumer screens |
| App logo on login screen | ✓ `assets/images/icon.png` at 80×80 above "Welcome" |
| Map search keyboard dismisses on tap/pan/truck tap | ✓ Fixed this session |
| Consumer notification splits | ✓ Announcements + Booking Updates toggles in account |
| Add to Calendar (accept booking) | ✓ `add_2_calendar` — native iOS editor, no permissions |
| Add to Calendar (manual booking) | ✓ Same flow in ManualBookingSheet after save |
| Map — real-time truck location | ✓ `activeTrucksProvider` is a StreamProvider (Supabase `.stream()`) |
| Password autofill (iOS Keychain / Android) | ✓ `AutofillGroup` + `autofillHints` + `finishAutofillContext` |
| Booking cancel labels — owner screen | ✓ "Canceled by you" / "Canceled by customer" / "Declined" |
| Booking cancel labels — consumer screen | ✓ "Canceled by you" / "Canceled by vendor" / "Declined" |
| Apple Sign In — Flutter code | ✓ Complete: nonce flow, entitlements wired |
| Apple Sign In — portal config | ✗ Not yet enabled in developer.apple.com |
| RevenueCat SDK | ✓ Configured, `premium` entitlement, purchase/restore complete |
| Google Sign-In Android | ✗ `google-services.json` still has empty `oauth_client` |
| GoogleService-Info.plist | ✗ Wrong bundle ID — iOS FCM push broken |
| REVENUECAT_WEBHOOK_SECRET | ✗ Not set in Supabase secrets |
| farlo.app website | ✗ Built, deployed to Squarespace, not yet published |
| `aps-environment` | ✗ Still `development` — must flip to `production` before TestFlight |
| Consumers notified when favorited truck goes live | ✗ Not wired — open_alert toggle exists in DB but no fan-out yet |

---

## Architecture

Feature-based Flutter under `lib/features/<name>/` — each feature owns models, providers, repositories, and screens/widgets. Supabase is the only backend; two `SECURITY DEFINER` RLS helper functions (`auth_user_owns_truck`, `auth_user_is_employee`). GoRouter 17.x uses two `StatefulShellRoute` stacks (consumer `/map`, `/favorites`, `/account`; owner `/dashboard`, `/owner-map`, `/owner-account`) driven purely by `authProvider` + `onboardingProvider`. The owner's booking requests screen holds a Supabase realtime channel subscription (`event_booking_requests` filtered by `truck_id`) so cross-device consumer cancels update the owner's list automatically. Push notifications go through FCM via Supabase edge functions; `send-booking-notification` handles booking + open/close alerts, `send-truck-announcement` fans out to followers.

---

## Recent Decisions (non-obvious)

**Root cause of consumer cancel not updating owner screen: missing RLS UPDATE policy.**
`cancelRequest()` does `UPDATE event_booking_requests SET status='cancelled' WHERE id=...`. There was no UPDATE policy for consumers — Supabase silently returned success with 0 rows affected. The consumer's local state updated optimistically so it *looked* correct on their device, masking the bug entirely. Fix: added `"consumers can cancel own requests"` policy restricting result to `status='cancelled', cancelled_by='consumer'` only.

**`event_booking_requests` was not in the `supabase_realtime` publication.**
Added the realtime subscription to the owner's screen but it would have silently done nothing until we ran `ALTER PUBLICATION supabase_realtime ADD TABLE event_booking_requests`. Always verify table is in publication before assuming `onPostgresChanges` works.

**Declined/Canceled section was there but collapsed — not a data bug.**
Both booking screens use a `_CollapsibleSection` with `_expanded = false` by default. After a cancel/decline the section appeared with the count badge but items were hidden. Fix: `initiallyExpanded: true` on the "Declined / Canceled" section + `ValueKey('closed')` / `ValueKey('past')` so Flutter preserves expansion state when tree structure changes (e.g., pending section disappears).

**Consumer notification splits: 3 toggles, not 1.**
Added `announcement_alert` and `booking_alert` boolean columns (both default `true`) to `notification_preferences`. `send-booking-notification` v8 now checks `booking_alert` for `booking_status_changed` (consumer-targeted). `send-truck-announcement` v2 now checks `announcement_alert` per follower via `.or('push_enabled.eq.false,announcement_alert.eq.false')`. Owner dialog unchanged.

**"Truck live alerts" for consumers: toggle exists in DB, push not wired.**
`open_alert` column exists and is saved correctly for consumers. But no edge function currently fans out to followers when a truck goes live — `truck_open`/`truck_closed` actions in `send-booking-notification` only notify the owner. Don't add the toggle to the consumer UI until the fan-out is built.

**No "change login type" screen needed.**
With Apple/Google sign-in added, decided against a provider-switching UI. Complexity is high (re-auth required, Apple token is one-time), real-world demand is low. Handle the edge case (same email on two providers) with a clear error message instead.

**Map keyboard: three unfocus points needed.**
`_searchFocusNode.unfocus()` added to: (1) `MapOptions.onTap`, (2) `MapOptions.onPositionChanged` on any gesture, (3) `_onTruckTapped` before opening the sheet. Without #3, Flutter restores focus to the search field when the truck bottom sheet closes.

---

## Traps / Dead Ends

| Trap | What Happened | Don't Repeat |
|---|---|---|
| Consumer cancel silently no-ops | Missing RLS UPDATE policy → 0 rows updated, no error, local state masks it | Always check RLS for every table operation (SELECT/INSERT/UPDATE/DELETE separately) |
| `onPostgresChanges` fires nothing | Table not in `supabase_realtime` publication | Run `SELECT * FROM pg_publication_tables WHERE pubname='supabase_realtime'` before assuming realtime works |
| `_CollapsibleSection` resets to collapsed | No `ValueKey` → Flutter re-creates state when tree structure changes | Always key `StatefulWidget`s that must survive sibling insertions/removals |
| `device_calendar` + `permission_handler` | iOS 26 real device: no dialog, no Calendar entry | Use `add_2_calendar` — no permissions needed |
| `TextInput` from `material.dart` | IDE says import redundant; it's not | Keep `import 'package:flutter/services.dart' show TextInput'` |
| `cancelledBy` not in `_withStatus()` | Wrong sublabel until refresh | Set `cancelledBy` in local copy same as `status` |
| `_StatusBadge` switch wildcard | Cancelled bookings showed "Pending" | Always add explicit `'cancelled'` case, don't rely on `_` wildcard |
| `SafeArea(top: true)` in modal sheet | Dynamic Island clipped handle | Capture `MediaQuery.of(context).viewPadding.top` from scaffold context *before* `showModalBottomSheet` |
| `StateProvider` / `valueOrNull` | Both removed in Riverpod 3.x | Use `asData?.value` |
| SPM enabled on iOS | Space in project path breaks Swift Package Manager | `flutter config --no-enable-swift-package-manager` — do not re-enable |
| `event_booking_requests_status_check` constraint | `cancelled` not in CHECK values → silent 400 | Check DB CHECK constraints when adding new status values |
| `google-services.json` empty `oauth_client` | File not refreshed after creating Android OAuth client | Download fresh from Firebase Console after any credential change |
| `flutter_launcher_icons` with `android: "launcher_icon"` | New file created; manifest references `ic_launcher` | Use `android: "ic_launcher"` to overwrite in-place |

---

## Modified Files (this session)

| File | Change |
|---|---|
| `lib/features/bookings/screens/booking_requests_screen.dart` | Added Supabase import; `_CollapsibleSection` gets `initiallyExpanded` + `ValueKey`; realtime channel subscription in `_BookingRequestsListState` (init + dispose) |
| `lib/features/bookings/screens/my_requests_screen.dart` | Same `_CollapsibleSection` fixes (this file has its own copy of the widget) |
| `lib/features/auth/screens/login_screen.dart` | Added `Image.asset('assets/images/icon.png')` centered above "Welcome" heading |
| `lib/features/map/screens/map_screen.dart` | `_searchFocusNode.unfocus()` in `onTap`, `onPositionChanged`, and `_onTruckTapped` |
| `lib/features/account/screens/account_screen.dart` | Consumer notification dialog: 3 toggles (Push master, Announcements, Booking Updates); owner dialog unchanged |
| `lib/features/account/providers/notification_prefs_provider.dart` | Added `setAnnouncementAlert` + `setBookingAlert` methods; `_current` getter to avoid repeated null coalescing |
| `lib/features/account/repositories/notification_prefs_repository.dart` | `NotifPrefs` typedef extended with `announcementAlert` + `bookingAlert`; fetch/update wired to new DB columns |

**DB changes (Supabase — already live):**
- `event_booking_requests`: added RLS policy `"consumers can cancel own requests"` (UPDATE, scoped to own rows, result must be `cancelled`/`consumer`)
- `event_booking_requests`: added to `supabase_realtime` publication
- `notification_preferences`: added `announcement_alert boolean DEFAULT true` and `booking_alert boolean DEFAULT true`

**Edge functions deployed:**
- `send-booking-notification` → v8: `checkPrefs` now accepts `checkBookingAlert`; `booking_status_changed` passes it `true`
- `send-truck-announcement` → v2: excludes followers with `push_enabled=false OR announcement_alert=false`

---

## Known Issues

| Issue | Severity | Notes |
|---|---|---|
| `aps-environment: development` | **High (TestFlight)** | Change to `production` in `ios/Runner/Runner.entitlements` before first TestFlight build |
| `google-services.json` empty `oauth_client` | **High** | Android Google Sign-In non-functional. Firebase Console → Android app → Download → replace |
| `GoogleService-Info.plist` wrong bundle ID | **High** | iOS FCM push broken. Firebase Console → iOS app (`com.farlo.app`) → Download → replace |
| Apple Sign In not configured in portal | **High** | Code complete. Next: developer.apple.com → Identifiers → `com.farlo.app` → enable Sign In with Apple → Supabase Auth → Apple provider |
| `REVENUECAT_WEBHOOK_SECRET` not set | **High (subscriptions)** | Supabase project secrets → add key. Until then webhook accepts any request |
| RevenueCat IAP product not created | **High (subscriptions)** | App Store Connect → create `com.farlo.app.owner.monthly`; RC dashboard → `premium` entitlement + current offering |
| Consumer "truck live" push not wired | **Medium** | `open_alert` saved to DB for consumers but no edge function fans out to followers when truck goes live. Don't show the toggle until built |
| Calendar add — manual booking not tested | **Medium** | Code correct; needs physical device test |
| farlo.app not published | **Medium** | Squarespace site built; user is handling publish |
| Password autofill not tested on device | **Medium** | Wired correctly; verify "Save to iPhone?" sheet appears before GoRouter navigates away |

---

## Next Steps (priority order)

1. **Change `aps-environment` to `production`** — one-line edit in `ios/Runner/Runner.entitlements`. Blocks all TestFlight push notifications.

2. **Apple Sign In portal setup** — developer.apple.com → Identifiers → `com.farlo.app` → enable Sign In with Apple → Supabase Dashboard → Auth → Apple provider → Service ID + key. Flutter code is 100% done.

3. **Refresh Firebase config files** — `google-services.json` from Firebase Console Android app; `GoogleService-Info.plist` from Firebase Console iOS app (`com.farlo.app`). Both must match bundle ID `com.farlo.app` or FCM/Google Sign-In stays broken.

4. **RevenueCat + TestFlight prep** — App Store Connect: create `com.farlo.app.owner.monthly` IAP; RC dashboard: `premium` entitlement + current offering; Supabase secrets: `REVENUECAT_WEBHOOK_SECRET`.

5. **Consumer truck live alerts** (when ready) — build edge function that fires when `food_trucks.is_active` flips true, finds all `favorites` for that truck, filters by `push_enabled=true AND open_alert=true`, sends FCM. Then expose the toggle in the consumer notification dialog.

---

## Setup Gotchas

- **Run command**: `flutter run --dart-define-from-file=.env.json` — plain `flutter run` asserts on missing env vars
- **`.env.json` keys**: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `REVENUECAT_APPLE_KEY`, `REVENUECAT_GOOGLE_KEY`, `GOOGLE_PLACES_API_KEY`, `GOOGLE_SIGN_IN_WEB_CLIENT_ID` — gitignored, never commit
- **App name / IDs**: Farlo · iOS bundle `com.farlo.app` · Android applicationId `com.farlo.app`
- **SPM disabled**: `flutter config --no-enable-swift-package-manager` — space in project path breaks it
- **GoRouter**: any change to `router.dart` requires full restart, not hot reload
- **Riverpod 3.3.2**: use `asData?.value` — no `valueOrNull`, no `StateProvider`
- **go_router 17.3.0**: dialogs must use `dialogContext` from builder, not widget `context`
- **font_awesome_flutter 11.0.0**: use `FaIcon(FontAwesomeIcons.x)` — `IconData` is now `final`
- **share_plus 10.1.4**: `Share.share(text)` — NOT the v13 `ShareParams` API
- **device_calendar**: REMOVED — do not re-add. Use `add_2_calendar`
- **add_2_calendar 3.1.0**: opens native iOS `EKEventEditViewController` — no permission needed
- **Supabase project**: `weflrxyerxpsafcdetya` · `https://weflrxyerxpsafcdetya.supabase.co`
- **Email confirmation**: OFF — Supabase → Auth → Providers → Email
- **DB trigger** `on_auth_user_created`: dropped — `AuthRepository` handles profile creation via upsert
- **RLS functions**: `auth_user_owns_truck(uuid)` + `auth_user_is_employee(uuid)` are `SECURITY DEFINER` — do not drop
- **`cancelled_by` values**: `'consumer'` or `'owner'` — used in UI label logic, do not change
- **Booking statuses**: `pending`, `accepted`, `declined`, `cancelled` — all in DB CHECK constraint
- **notification_preferences columns**: `push_enabled`, `open_alert` (owner: truck live; consumer: future), `announcement_alert` (consumer), `booking_alert` (consumer) — all boolean, default true
- **Android debug SHA-1**: `47:C4:1E:1D:6D:6B:52:96:E5:C3:FA:1A:DA:72:25:84:26:E7:E3:A4`
- **Edge functions deployed**: `send-booking-notification` v8, `send-booking-confirmation-email` v1, `send-truck-announcement` v2, `send-employee-invite` v5, `revenuecat-webhook` v3, `delete-account` v1, `accept-truck-transfer` v1
- **Primary color**: `AppColors.primary` = `#2563EB`
- **GitHub**: `https://github.com/johnnydanger12-design/good-truck-finder.git`
- **Supabase realtime**: `event_booking_requests` is now in `supabase_realtime` publication — required for owner screen live updates
