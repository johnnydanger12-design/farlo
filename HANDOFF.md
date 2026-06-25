# HANDOFF.md — Farlo
_Last updated: Jun 26 2026 — v1.0 resubmitted to App Store after rejection sweep. Read time: ~2 min._

---

## Interrupted Task

None — session ended cleanly. App Store submission sent Jun 26 2026. Waiting on Apple review.

---

## Current State

| Feature | Status |
|---|---|
| App Store v1.0 | ✓ Resubmitted Jun 26 2026 — In Review (build 1.0.0+3) |
| Apple rejection fixes | ✓ All 5 issues resolved — guest browsing, IAP, age rating, background location reply, Paid Apps Agreement signed |
| RevenueCat | ✓ Default offering configured with App Store products (monthly + yearly). Entitlement `premium` attached. |
| Paid Apps Agreement | ✓ Active — bank account added, agreement signed |
| Calendar redesign | ✓ ShiftWeekCard (iOS Calendar style) on dashboard; CalendarScreen with 3 views (List/Month/Timeline) + day view |
| Planned locations | ✓ DB table + realtime + Add Event sheet + Announce Week sheet |
| Follower notification prefs | ✓ `follower_notification_preferences` table; bell toggle on truck profile + favorites cards |
| Menu realtime (consumer) | ✓ `menu_items` added to `supabase_realtime` publication |
| Popups → cards | ✓ All 8 dialogs converted to bottom sheets (Name, Password, Notifications, Delete, Sign Out, Appearance, Add Employee, Announcement) |
| check-open-businesses | ✓ pg_cron job running every 30 min — notifies stale-open businesses |
| D-U-N-S | ✓ Obtained — ready to create Google Play Console account |
| Play Console | ⚠ Not yet created — blocked on D-U-N-S (now resolved, just not done yet) |
| RevenueCat Google Play | ⚠ Not set up — blocked on Play Console |
| Background location disclosure UI | ⚠ Still not built for Android/Play Store |
| EIN / business bank account | ⚠ In progress — EIN obtained, bank account opened for Apple, Stripe not yet updated |
| farlo.app download buttons | ⚠ href="#" placeholders — update once Apple approves |
| bookings@farlo.app alias | ⚠ Not created in Google Workspace yet |

---

## Architecture

Flutter + Riverpod 3.x + GoRouter (StatefulShellRoute — owner shell and consumer shell are separate indexed stacks). Supabase for auth/Postgres/RLS/realtime/storage/edge functions. Stripe Connect Express for payments (funds go direct to owner, Farlo never holds money). FCM push via custom service-account JWT flow in edge functions. RevenueCat manages subscriptions (iOS configured, Android pending). `business_type` ('mobile'|'fixed') drives GPS vs. static address logic. Employees are consumers with `truck_employees` records. Calendar (`CalendarScreen`) is a GoRouter sub-route `/dashboard/calendar` for owners, `Navigator.push` for employees (different shells).

---

## Recent Decisions

**Onboarding → `/map` not `/login` (Jun 26):** The onboarding screen was hardcoded to `context.go('/login')` after completion — that's why first-launch landed on the login screen instead of the map. Fixed to `context.go('/map')`.

**`subscriptions` table, not `owner_subscriptions` (Jun 26):** The private event booking button was silently failing because `_openBookingSheet()` queried a nonexistent table `owner_subscriptions`. Real table is `subscriptions`. Also added `owner_has_active_subscription(p_owner_id uuid)` SECURITY DEFINER RPC so consumers can check without RLS blocking them.

**`menu_items` not in realtime publication (Jun 26):** Consumer menu wasn't updating live because `menu_items` was never added to the `supabase_realtime` publication. Fixed with `ALTER PUBLICATION supabase_realtime ADD TABLE menu_items`.

**CalendarScreen uses GoRouter `/dashboard/calendar` (Jun 26):** Previously used `Navigator.push`, which broke double-tap-dashboard-to-reset. GoRouter route means `goBranch(0, initialLocation: true)` correctly resets the stack. Employee `ShiftWeekCard` still uses `Navigator.push` because employees are in the consumer shell where `/dashboard/calendar` doesn't exist.

**`foodTruckProvider` converted to AsyncNotifierProvider (Jun 26):** Was a simple `FutureProvider.family` with no realtime. Converted to `AsyncNotifier` so it sets up a `menu_items` realtime channel in `build()`. TruckProfileScreen also has its own `_menuChannel` for belt-and-suspenders.

**`acceptedBookingsForMonthProvider` promoted (Jun 26):** Was a private `_acceptedBookingsForMonthProvider` in `dashboard_screen.dart`. Moved to `bookings_provider.dart` as public so calendar screens can use it.

**Planned locations → teal color `0xFF0D9488` in calendar (Jun 26):** New event type. Shown as teal dots/chips on month grid, teal "all-day" blocks at top of timeline, teal event rows in list view.

**`check-open-businesses` edge function (Jun 26):** Cron job via pg_cron (every 30 min). Checks `operating_hours` first (notifies 30 min past scheduled close). Falls back to 8-hour rule if no hours set. Stores `last_open_check_notified_at` on `food_trucks`. Re-asks every 2 hours if still open.

---

## Traps / Dead Ends

- **`owner_subscriptions` table doesn't exist** — it's called `subscriptions`. Don't let autocomplete fool you.
- **`menu_items` realtime** — even after adding a channel subscription in Dart, events won't fire unless the table is in the Supabase realtime publication. Check with `SELECT tablename FROM pg_publication_tables WHERE pubname = 'supabase_realtime'`.
- **Employee CalendarScreen in owner shell** — if `ShiftWeekCard.isOwner = false` and you push `/dashboard/calendar`, the employee lands in the owner's GoRouter shell (Bookings/Dashboard nav shows, "No truck found" error). Employee must use `Navigator.push` with `CalendarScreen` directly.
- **SQL-created auth users won't log in** if `raw_app_meta_data` or token fields are NULL.
- **`Directory.systemTemp` on iOS** — not writable, use `path_provider`.
- **GoRouter cold-start race** — `getInitialMessage()` can fire before router or auth. Fixed with buffer + dual drain gates in `PushNotificationService`.
- **`favoritedTruckIdsProvider` for heart button** — returns `{}` for unauthenticated users (safe, no crash).
- **`play-services-tapandpay` stub** — `android/local-maven/` contains a stub AAR. Do NOT remove or Android build breaks.
- **`firebase_options.dart` is a stub** — `projectId: 'good-truck-finder'` is the internal Firebase project ID, cannot be renamed.
- **Timeline events overflow** — `_TimelineBlock` must have `ClipRRect` wrapper and hide subtitle when height < 44px. Already in place.
- **Scheduled shifts in RLS** — uses `auth_user_owns_truck(truck_id)` function. Function exists and is correct.
- **`_buildSheetContainer` helper** — defined at file scope in `account_screen.dart`. Available to all widgets in that file for the 8 converted bottom sheets.

---

## Modified Files (This Session — Big Ones)

| File | What changed |
|---|---|
| `lib/router.dart` | Added guest routes (`/map`, `/set-new-password`), `/dashboard/calendar` route, owner redirect exclusions |
| `lib/app_shell.dart` | Converted to StatefulWidget; Supabase auth listener for password recovery; sign-out routes owner→/login, consumer→/map |
| `lib/features/onboarding/screens/onboarding_screen.dart` | Goes to `/map` after completion (was `/login`) |
| `lib/features/employees/widgets/shift_week_card.dart` | New: iOS Calendar-style dashboard week card |
| `lib/features/employees/screens/calendar_screen.dart` | New: full calendar with 3 views + day drill-down |
| `lib/features/food_trucks/screens/truck_profile_screen.dart` | Private event query fixed (`subscriptions`); `owner_has_active_subscription` RPC; `_menuChannel` realtime; bell button |
| `lib/features/food_trucks/providers/food_truck_provider.dart` | Converted to AsyncNotifierProvider with `menu_items` realtime |
| `lib/features/account/screens/account_screen.dart` | All 8 dialogs → bottom sheets; `_SheetHandle` + `_buildSheetContainer` helpers added |
| `lib/features/map/screens/map_screen.dart` | Marker z-order (first arrival on top); cluster offset spreading |
| `lib/features/notifications/screens/notifications_screen.dart` | All notification types routed; announcement → bottom sheet; shift → opens EmployeeDashboardScreen |
| `lib/features/bookings/providers/bookings_provider.dart` | `acceptedBookingsForMonthProvider` promoted from private |
| `lib/core/widgets/app_button.dart` | Disabled state uses brand color (not grey) |
| `lib/shells/consumer_shell.dart` | Guest tab tap → SignInPromptSheet instead of redirect |

**New files:** `sign_in_prompt_sheet.dart`, `set_new_password_screen.dart`, `planned_location.dart`, `planned_locations_provider.dart`, `planned_locations_repository.dart`, `calendar_screen.dart`, `add_event_sheet.dart`, `announce_week_sheet.dart`, `plan_location_sheet.dart`, `shift_week_card.dart`, `announcement_prefs_provider.dart`

**DB migrations applied:**
- `planned_locations` table + RLS
- `follower_notification_preferences` table + RLS  
- `last_open_check_notified_at` column on `food_trucks`
- `owner_has_active_subscription` SECURITY DEFINER function
- `menu_items` added to `supabase_realtime` publication
- `pg_cron` + `pg_net` extensions enabled; `check-open-businesses` job scheduled

---

## Known Issues

| Issue | Severity |
|---|---|
| Consumer Stripe snackbar on Add to Bag | Low — only reproducible with test data (ordersEnabled=true without Stripe). Won't happen in production. |
| Announcement bell decision — also in Account settings? | Low — description now says "go to their page" to mute. Acceptable for v1. |
| Android: background location disclosure UI not built | Medium — required before Play Store submission |
| Android: Play Console account not created | Medium — D-U-N-S ready, just not done |
| bookings@farlo.app Google Workspace alias | Low — forward to johnny@farlo.app; bounces without it |
| Entity name in Apple developer account still "JOHNNY DEE WINBURN" | Low — contact Apple Support to change to Farlo Technologies LLC |

---

## Next Steps

1. **Watch for Apple review result** — respond same day if rejected. If approved, update farlo.app download buttons (href="#" → App Store link).
2. **Create Google Play Console** ($25) → upload AAB to internal testing → build background location disclosure UI → RevenueCat Android setup.
3. **Stripe business update** — update Stripe account with EIN + business bank account.
4. **bookings@farlo.app alias** — create in Google Workspace forwarding to johnny@farlo.app.
5. **Order ahead illumination feature** — see backlog in memory.

---

## Setup Gotchas

- **`.env.json`** at project root (gitignored). Keys: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `STRIPE_PUBLISHABLE_KEY` (pk_live), `REVENUECAT_APPLE_KEY` (appl_...), `REVENUECAT_GOOGLE_KEY` (empty), `GOOGLE_PLACES_API_KEY`, `GOOGLE_SIGN_IN_WEB_CLIENT_ID`.
- **Build command:** `flutter build ipa --dart-define-from-file=.env.json` → IPA at `build/ios/ipa/Farlo.ipa`
- **Open in Transporter:** `open -a Transporter "/Users/johnny/Desktop/Good Truck Finder/build/ios/ipa/Farlo.ipa"`
- **Current build number:** `1.0.0+3` (pubspec.yaml has `+2` which Flutter exported as build 3 — next build use `+4`)
- **Android release:** `flutter build appbundle --dart-define-from-file=.env.json` → `build/app/outputs/bundle/release/app-release.aab`. Requires `android/app/farlo-release.keystore` + `android/key.properties` (both gitignored, back up externally).
- **Supabase project:** `weflrxyerxpsafcdetya.supabase.co`. Edge functions: `supabase functions deploy <name>`.
- **Firebase project:** internal ID is `good-truck-finder` (cannot be renamed). `firebase_options.dart` is a stub — do not run `flutterfire configure`.
- **Stripe webhook** at `https://weflrxyerxpsafcdetya.supabase.co/functions/v1/stripe-webhook` — must have `verify_jwt: false`.
- **Test accounts:** `apple.review@farlo.app` / `FarloReview2026!` (owner, active sub). Screenshot accounts: `jwinburndcso@gmail.com`, `taylor.winburn94@gmail.com`, `johnny@peakdesignspace.com` — all `FarloTest123`. jwinburndcso password was reset to `Farlo26!` via DB on Jun 24 2026.
- **GitHub:** `https://github.com/johnnydanger12-design/farlo`
