# HANDOFF.md — Good Truck Finder
_Last updated: Owner booking inbox + push notifications (Firebase FCM) session. Read time: ~2 min._

---

## Interrupted Task

Nothing mid-flight. All changes complete, `flutter analyze` is clean.

---

## Current State

`flutter analyze` — zero issues.

| Feature | Status |
|---|---|
| Employee invite — instant if account exists, pending if not | ✓ DB RPC + dynamic email |
| Employee display name in owner list | ✓ FK → profiles, joined via PostgREST |
| Operating hours — removed entirely | ✓ Profile screen + dashboard tile + subscription feature list |
| Change password — consumer + owner accounts | ✓ Re-auth then updateUser |
| Edge indicators for off-screen favorited trucks | ✓ Life360-style, `latLngToScreenOffset` + MapEvent stream |
| Default map center when location denied | ✓ 34.375, -80.074 |
| Request Private Event booking form | ✓ DB table + sheet + button on truck profile |
| Owner booking requests inbox | ✓ `/dashboard/bookings` — list, status badges, detail sheet, accept/decline |
| Push notifications — booking created | ✓ FCM → owner when consumer submits request |
| Push notifications — status changed | ✓ FCM → consumer when owner accepts/declines |

---

## Architecture

Feature-based Flutter under `lib/features/<name>/` — each feature owns models, providers, repositories, screens/widgets. `lib/features/bookings/` has models, providers, repositories, screens, and widgets. Supabase is the only backend; RLS is enforced on every table. Two `SECURITY DEFINER` functions (`auth_user_owns_truck`, `auth_user_is_employee`) break cross-table RLS recursion — do not drop them. GoRouter 17.x handles all navigation via shell routes; `authProvider` is read (not watched) in the router redirect to avoid double redirects. Firebase Messaging handles push on both platforms; tokens stored in `push_tokens` table (one per user per platform, upserted on login).

---

## Recent Decisions (non-obvious)

**Employee invite — RPC not direct insert.** `invite_employee_by_email(p_truck_id, p_email)` is a `SECURITY DEFINER` Postgres function that checks `profiles` by email, inserts as `active` (with `user_id`) if found or `pending` if not, and returns `{ already_user, display_name }`. The Flutter repo calls this RPC and returns a `bool` so the screen can show the right snackbar and send the right email variant.

**Employee FK changed from `auth.users` → `profiles`.** PostgREST only auto-joins on explicit FKs. The old FK to `auth.users` prevented the `profiles(display_name)` join. Dropped and re-added pointing to `profiles.id` — functionally the same UUID, no data loss. `ON DELETE SET NULL` so a deleted profile demotes the row rather than cascading.

**Edge indicators only for favorited + open trucks.** Showing every open truck off-screen would be cluttered. Filtered to `t.isOpen && favIds.contains(t.id)`. The `favIds` set comes from the already-watched `favoritedTruckIdsProvider` — no extra query. A `StreamSubscription<MapEvent>` on `_mapController.mapEventStream` drives `setState` so indicators update every frame during pan/zoom. `LayoutBuilder` provides the actual Stack dimensions (excluding bottom nav bar) so edge clamping is accurate.

**Change password re-authenticates first.** Supabase `updateUser` works on any live session. We call `signInWithPassword` first with the current password to verify it before allowing the change — otherwise any signed-in session could change the password silently.

**Push notifications are fire-and-forget.** `BookingsRepository._invokeNotification` spawns an unawaited async closure so a slow/failing FCM call never blocks the DB write or the UI. Notification failure is logged to debugPrint only — no user-facing error.

**`send-booking-notification` edge function uses raw FCM HTTP v1 API with RS256 JWT.** No `firebase-admin` npm package — the function generates a short-lived OAuth access token from the service account JSON (`FIREBASE_SERVICE_ACCOUNT_JSON` secret) using `crypto.subtle`, then calls `https://fcm.googleapis.com/v1/projects/{project_id}/messages:send` directly. This avoids npm cold-start overhead. If `FIREBASE_SERVICE_ACCOUNT_JSON` is not set, the function returns `{ sent: false, reason: 'not_configured' }` and logs a warning — no crash.

**`push_tokens` primary key is `(user_id, platform)`.** One token per user per platform — upserted via `PushNotificationService._storeToken` on startup and on `onTokenRefresh`. Service role key (in the edge function) can read across all users; RLS only allows users to write their own row.

**`aps-environment: development` in entitlements.** Suitable for TestFlight and direct device installs. Change to `production` before App Store submission.

**Null-aware map entry syntax (Dart 3.7).** `'key': ?nullableValue` omits the entry if value is null. `?'key': value` checks if the KEY is null (not useful when key is a string literal — analyzer warns). The `if (x != null) 'key': x` pattern triggers `use_null_aware_elements` lint in this project.

---

## Traps / Dead Ends

| Trap | What Happened | Don't Repeat |
|---|---|---|
| `latLngToScreenPoint` on MapCamera | Doesn't exist | Correct method: `latLngToScreenOffset` (returns `Offset`) |
| `?'key': value` null-aware map entry | Analyzer error: key can't be null | Use `'key': ?value` instead |
| `DropdownButtonFormField.value` | Deprecated Flutter 3.33+ | Use `initialValue` |
| `FamilyAsyncNotifier` superclass | Not valid in Riverpod 3.3.2 | Pass arg via constructor; extend plain `AsyncNotifier<T>` |
| `Navigator.pop(context)` in shell dialog | Hits branch Navigator → black screen | Always use `dialogContext` from builder param |
| Watching `authProvider` in `routerProvider` | Recreates GoRouter on every auth change | Use `ref.read` in redirect only |
| `StateProvider` / `valueOrNull` | Removed in Riverpod 3.x | `NotifierProvider` + `Notifier`; use `asData?.value` |
| `RadioListTile.groupValue` / `onChanged` | Deprecated Flutter 3.32 | Use `RadioGroup` or manual `ListTile` + checkmark |
| `const BoxDecoration(color: Theme.of(context)...)` | Compile error | Drop `const` from `BoxDecoration`; keep `const` inside for `BorderRadius` only |
| DB trigger `on_auth_user_created` | Created duplicate profile rows | Dropped — do not re-add. Use `upsert` for profiles |
| Email confirmation ON | Signup creates no session → redirect loop | Must stay OFF in Supabase Auth settings |
| RLS infinite recursion on `food_trucks` ↔ `truck_employees` | Cross-table policy cycle | Always use `SECURITY DEFINER` functions for cross-table RLS |
| `catchError` on `FunctionResponse` future | Must return `FunctionResponse` | Use unawaited async closure with try/catch instead |
| `ColorScheme.background` | Deprecated Flutter 3.18+ | Use `ColorScheme.surface` |
| `AppTextStyles.bodyMedium` | Doesn't exist | Available styles: `heading1/2/3`, `body`, `bodySmall`, `label`, `caption`, `buttonText` |

---

## Modified Files (this session)

| File | Change |
|---|---|
| **NEW** `lib/features/bookings/screens/booking_requests_screen.dart` | Owner inbox — list grouped pending/past, status badges, detail sheet, accept/decline |
| `lib/features/bookings/repositories/bookings_repository.dart` | Added `fetchOwnerRequests`, `updateRequestStatus`; `submitRequest` now returns booking ID + fires notification; `_invokeNotification` helper |
| `lib/features/bookings/providers/bookings_provider.dart` | Added `OwnerBookingRequestsNotifier` + `ownerBookingRequestsProvider` with optimistic status update |
| `lib/router.dart` | Added `/dashboard/bookings` route |
| `lib/features/owner_dashboard/screens/dashboard_screen.dart` | Added Booking Requests tile |
| `lib/main.dart` | Added `Firebase.initializeApp()` + `PushNotificationService.initialize()` |
| **NEW** `lib/core/push_notification_service.dart` | Requests permission, stores/refreshes FCM token in `push_tokens` |
| **NEW** `lib/firebase_options.dart` | Generated by `flutterfire configure` — real iOS + Android Firebase app IDs |
| **NEW** `ios/Runner/Runner.entitlements` | `aps-environment: development` |
| `ios/Runner.xcodeproj/project.pbxproj` | `CODE_SIGN_ENTITLEMENTS` set for Debug/Profile/Release; `GoogleService-Info.plist` added by flutterfire |
| `android/app/google-services.json` | Generated by `flutterfire configure` |
| `pubspec.yaml` | Added `firebase_core: ^3.9.0`, `firebase_messaging: ^15.2.5` |
| **NEW** `supabase/functions/send-booking-notification/index.ts` | FCM HTTP v1 via RS256 JWT from service account |
| **Supabase migration** `create_push_tokens` | `push_tokens` table + RLS |
| **Supabase Edge Function** `send-booking-notification` v1 | Deployed — `FIREBASE_SERVICE_ACCOUNT_JSON` secret set |

---

## Known Issues

| Issue | Severity | Notes |
|---|---|---|
| Foreground push banners (iOS) | Low | `setForegroundNotificationPresentationOptions` is set — should show banners. Untested without real device. |
| Invite email from `onboarding@resend.dev` | Medium (prod) | Resend test address — only delivers to Resend account owner. Verify `goodtruckfinder.com` in Resend + update edge function `from:` |
| `REVENUECAT_WEBHOOK_SECRET` not set in Supabase | High (subscriptions) | Webhook accepts all requests until configured |
| CartoDB tiles require attribution in production | Medium | Must credit © CARTO + © OpenStreetMap in App Store build |
| `aps-environment: development` in entitlements | Medium (prod) | Change to `production` before App Store submission |
| No shimmer/skeleton loading | Low | Phase 6 |
| No delete account flow | Low | Phase 6 — App Store required |
| No menu PDF/image upload UI | Medium | Columns exist, no picker |
| Recent searches not scoped to user | Low | SharedPreferences key `recent_searches` is device-global |
| RevenueCat purchase untestable on simulator | Expected | Requires real device + sandbox Apple ID |

---

## Next Steps (priority order)

1. **App icon + splash** — `flutter_launcher_icons` + `flutter_native_splash`. High visual impact for demos.
2. **RevenueCat production setup** — App Store Connect product (`com.goodtruckfinder.owner.monthly`), RC dashboard entitlement `premium`, Apple API key → `.env.json`. Wire `REVENUECAT_WEBHOOK_SECRET` in Supabase Edge Function secrets + RC webhook URL.
3. **Resend production domain** — Verify `goodtruckfinder.com` in Resend, update edge function `from:` field (`send-employee-invite`), redeploy.
4. **Delete account flow** — Required by App Store. Supabase `auth.admin.deleteUser` via edge function + cascade delete profile/trucks/tokens.
5. **Menu PDF/image upload UI** — Columns exist in DB, no picker UI. Add to Edit Truck screen.

---

## Setup Gotchas

- **Run**: `flutter run --dart-define-from-file=.env.json` — plain `flutter run` hits an assert
- **`.env.json`** (gitignored, project root) — keys: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `REVENUECAT_APPLE_KEY`, `REVENUECAT_GOOGLE_KEY`
- **Supabase project**: `weflrxyerxpsafcdetya` — `https://weflrxyerxpsafcdetya.supabase.co`
- **Email confirmation**: must be OFF (Supabase → Auth → Providers → Email)
- **DB trigger**: `on_auth_user_created` is dropped — do not re-add
- **RLS functions**: `auth_user_owns_truck(uuid)` + `auth_user_is_employee(uuid)` are SECURITY DEFINER — required to prevent recursion, do not drop
- **`invite_employee_by_email(uuid, text)`**: SECURITY DEFINER RPC — checks profiles, inserts active or pending, returns jsonb `{ already_user, display_name }`
- **Flutter**: 3.44.1 stable, darwin-arm64. Xcode 26.5, Android SDK 36.1.0
- **Riverpod**: 3.3.2 — no `valueOrNull`, no `StateProvider`, no `FamilyAsyncNotifier`
- **go_router**: 17.3.0 — dialog `Navigator.pop` must use `dialogContext` not widget context
- **purchases_flutter**: 10.2.3 — `PurchaseParams.package(pkg)` is the correct purchase API
- **RC entitlement ID**: `premium` — must match RevenueCat dashboard exactly
- **shared_preferences**: 2.3.2 — theme mode key: `theme_mode_<userId>`, recent searches: `recent_searches` (device-global)
- **Dark tiles**: CartoDB Dark Matter — free for dev, requires attribution for production
- **flutter_map**: 8.3.0 — coordinate conversion: `camera.latLngToScreenOffset(LatLng)` returns `Offset` (NOT `latLngToScreenPoint`)
- **Dart 3.7 null-aware map entries**: `'key': ?nullableValue` omits the entry if null. `?'key': value` checks the key (wrong for string literals).
- **Firebase**: project `good-truck-finder`. `firebase_options.dart` generated by `flutterfire configure`. `FIREBASE_SERVICE_ACCOUNT_JSON` set in Supabase → Edge Functions → `send-booking-notification` → Secrets. Firebase CLI: `firebase login` then `$HOME/.pub-cache/bin/flutterfire configure`.
- **iOS push entitlements**: `ios/Runner/Runner.entitlements` — `aps-environment: development`. Change to `production` for App Store.
- **Resend**: invite email from `onboarding@resend.dev` (test only). `RESEND_API_KEY` set in Supabase → Edge Functions → `send-employee-invite` → Secrets
- **GitHub**: `https://github.com/johnnydanger12-design/good-truck-finder.git`
- **Plan file**: `/Users/johnny/.claude/plans/project-planning-good-truck-compiled-pony.md`
