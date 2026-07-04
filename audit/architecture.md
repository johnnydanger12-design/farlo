# Farlo — Architecture Audit (Phase 1: Discovery)

**Scope:** Flutter app (`lib/`) + Supabase backend surface (`supabase/functions/`) + AI agent automation layer. Discovery only — no code changes. All paths relative to repo root `/Users/johnny/Desktop/Good Truck Finder`.

**Scale:** 116 Dart files, 26,793 lines under `lib/`. 25 Supabase Edge Functions (24 function dirs + `_shared`), ~4,969 lines of Deno/TS across the ones sampled. Single placeholder test file (`test/widget_test.dart`).

---

## Component Map

```
┌─────────────────────────────────────────────────────────────────────┐
│ Flutter App (lib/)                                                  │
│                                                                       │
│  main.dart ──▶ AppShell (MaterialApp.router) ──▶ routerProvider     │
│                     │                                (go_router)     │
│                     ├─▶ ConsumerShell (StatefulShellRoute)          │
│                     │     Map ─ Favorites ─ Notifications ─ Account │
│                     │                                                │
│                     └─▶ OwnerShell (StatefulShellRoute)             │
│                           Dashboard ─ Bookings ─ Notif ─ Account    │
│                                                                       │
│  Features (feature-first, each: models/providers/repositories/      │
│  screens/widgets):                                                   │
│   auth, food_trucks, map, favorites, notifications, account,        │
│   owner_dashboard, employees, bookings, orders, reviews, onboarding │
│                                                                       │
│  Each feature's Repository wraps SupabaseClient calls.              │
│  Each feature's Riverpod provider(s) wrap the Repository +          │
│  expose AsyncNotifier/StreamProvider/Notifier state to widgets.     │
│                                                                       │
│  core/ = cross-cutting: push notifications, location tracking,      │
│  RevenueCat config flag, theme provider, shared widgets/constants   │
│  services/ = 2 loose singletons (StorageService, SubscriptionService)│
└───────────────────────────┬───────────────────────────────────────┘
                             │ supabase_flutter (Postgres/RLS/Realtime/
                             │ Storage/Auth) + Edge Function invoke()
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Supabase Backend                                                     │
│  Postgres + RLS  |  Realtime (postgres_changes channels)            │
│  Storage buckets (truck-logos/photos/menus, avatars, brand)          │
│  Auth (email/pw, Sign in with Apple, Google)                        │
│                                                                       │
│  Edge Functions — two families:                                     │
│   (a) App-invoked (called directly from Flutter via                 │
│       functions.invoke): create-payment-intent, create-booking-     │
│       payment-intent, stripe-connect-onboard, create-refund,        │
│       send-order-notification, send-booking-notification,           │
│       send-message-notification, send-shift-notification,           │
│       send-truck-announcement, accept-truck-transfer,               │
│       generate-booking-invoice, delete-account                      │
│   (b) Backend-only / webhook / cron (never called from app):        │
│       stripe-webhook, revenuecat-webhook, send-owner-onboarding-    │
│       emails, send-owner-day7-checkin, send-consumer-welcome-email, │
│       send-booking-confirmation-email, prospect-businesses,         │
│       agent-* (9 functions, see below)                              │
└───────────────────────────┬───────────────────────────────────────┘
                             │ pg_cron schedules + DB triggers
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│ AI Agent Automation Layer (backend-only, no Flutter involvement)     │
│  agent-sage (support, every 5 min), agent-miles (sales, MWF 8am),   │
│  agent-piper (marketing), agent-aiden-inbox / agent-aiden-supervisor│
│  (weekly synthesis + cost report), agent-email-labeler,             │
│  agent-newsletter-cleanup, agent-stripe-weekly, agent-urgent-alert, │
│  agent-run-check. Shared brain in Postgres tables (agent_directives,│
│  supervisor_reports, support_tickets, sales_prospects,              │
│  content_queue, agent_run_log). Calls Anthropic API directly via    │
│  supabase/functions/_shared/claude-agent.ts.                        │
└───────────────────────────────────────────────────────────────────┘
```

---

## 1. Project Structure & Feature Organization

`lib/` is **feature-first**, not layered-first. Top-level dirs (`find lib -maxdepth 1`):

- `lib/main.dart` — entry point / bootstrap (Supabase, Firebase, Stripe, RevenueCat init).
- `lib/app_shell.dart` — root `MaterialApp.router` widget, theme, global auth-state side effects.
- `lib/router.dart` — single `go_router` configuration for the whole app.
- `lib/firebase_options.dart` — generated FlutterFire config.
- `lib/core/` — cross-cutting concerns: `constants/`, `extensions/`, `providers/` (only 1 file: `theme_provider.dart`), `utils/`, `widgets/` (shared UI atoms), plus loose top-level services (`location_tracking_service.dart`, `push_notification_service.dart`, `rc_config.dart`).
- `lib/services/` — 2 files only: `storage_service.dart`, `subscription_service.dart` (see §11 for inconsistency with `core/`).
- `lib/shells/` — `consumer_shell.dart`, `owner_shell.dart`, the two `StatefulNavigationShell` UI wrappers.
- `lib/features/` — 12 feature packages, each internally layered: `auth`, `food_trucks`, `map`, `favorites`, `notifications`, `account`, `owner_dashboard`, `employees`, `bookings`, `orders`, `reviews`, `onboarding`.

Each feature directory follows the same internal convention (verified across `food_trucks`, `map`, `orders`, `bookings`, `employees`, `reviews`, `favorites`, `notifications`, `owner_dashboard`, `auth`): `models/`, `providers/`, `repositories/`, `screens/`, `widgets/` — though not every feature has all five (e.g. `reviews` and `favorites` have no `screens/` subfolder for some, `onboarding` has no `repositories/` or `models/`). This is a **hybrid**: feature-first at the top level, layered-by-role one level down inside each feature — confirmed via `find lib -type d`.

## 2. Architectural Pattern

This is a **feature-first architecture with a lightweight repository pattern**, not full Clean Architecture (no use-case/interactor layer, no domain-layer abstraction separate from data models, no dependency-inversion interfaces for repositories — repositories are concrete classes injected via Riverpod `Provider`, not behind abstract interfaces).

Evidence:
- Repository pattern: `lib/features/food_trucks/repositories/food_truck_repository.dart:5-110`, `lib/features/map/repositories/map_repository.dart:6-67`, `lib/features/orders/repositories/orders_repository.dart:6-171`, `lib/features/auth/repositories/auth_repository.dart:12+` — each wraps one `SupabaseClient` and exposes typed methods; no interface/abstract base class exists anywhere (`grep -rn "abstract class" lib` — none found in repository layer).
- No use-case/interactor layer — providers call repository methods directly (`lib/features/food_trucks/providers/food_truck_provider.dart:20`, `:56`).
- "Controller" role is played by Riverpod `AsyncNotifier`/`Notifier` classes (e.g. `AuthNotifier` in `lib/features/auth/providers/auth_provider.dart:33-304`, `OwnerTruckNotifier` in `lib/features/food_trucks/providers/food_truck_provider.dart:49-168`) — this is closer to **MVVM-via-Riverpod** (Notifier = ViewModel, widget `build()` = View, Repository = Model/data access) than Clean Architecture.
- No domain models distinct from data models — `AppUser`, `FoodTruck`, `Order` etc. double as both API DTOs (`fromMap`/`toMap`) and UI-facing models (`lib/features/auth/models/app_user.dart:22-41`).

## 3. State Management

Riverpod confirmed (`flutter_riverpod: ^3.3.2` in `pubspec.yaml:38`). `riverpod_annotation: ^4.0.3` and dev deps `riverpod_generator: ^4.0.4` / `build_runner: ^2.15.0` are declared but **unused** — `grep -rln "@riverpod" lib` returns zero matches and `find lib -name "*.g.dart"` returns zero files. All providers are hand-written with the classic (non-codegen) Riverpod 3 API.

Provider types observed, with representative files:
- `AsyncNotifier` / `AsyncNotifierProvider` — the dominant pattern for anything backed by async fetch + mutation: `authProvider` (`lib/features/auth/providers/auth_provider.dart:306-308`), `ownerTruckProvider` (`lib/features/food_trucks/providers/food_truck_provider.dart:170-171`), `themeModeProvider` (`lib/core/providers/theme_provider.dart:6-7`).
- `AsyncNotifierProvider.family` — per-ID data, e.g. `foodTruckProvider` keyed by truck ID (`lib/features/food_trucks/providers/food_truck_provider.dart:43-46`).
- `StreamProvider` — realtime/GPS streams: `activeTrucksProvider`, `userLocationProvider` (`lib/features/map/providers/map_provider.dart:11-34`).
- `Notifier`/`NotifierProvider` — plain synchronous state: `SelectedTruckNotifier` (`lib/features/map/providers/map_provider.dart:36-45`), `cartProvider` (`lib/features/orders/providers/orders_provider.dart:111`).
- `FutureProvider.family` — one-shot async queries: `truckSearchProvider` (`lib/features/map/providers/map_provider.dart:47-50`).
- Plain `Provider` — DI for repositories/clients: `supabaseClientProvider`, `authRepositoryProvider` (`lib/features/auth/providers/auth_provider.dart:22-28`), `mapRepositoryProvider` (`lib/features/map/providers/map_provider.dart:7-9`).

**dispose() pattern (memory: `feedback_riverpod_dispose.md` flagged never mutating provider state in `dispose()`):** No violation of this rule was found in the current codebase. `grep -n "void dispose()" -A8` across `lib/` (checked `app_shell.dart:34-37`, `booking_requests_screen.dart:158-162`, `stripe_connect_screen.dart:50-54`, `my_orders_screen.dart:54-58`, `order_queue_screen.dart:86-90`, `order_cart_sheet.dart:27-30`) shows all `dispose()` overrides only cancel subscriptions/controllers or remove Supabase realtime channels — none call `ref.read`/mutate provider `state`. The specific bug this memory references (`CartNotifier.clear()` called via `Future.microtask` in dispose, per `HANDOFF.md`'s Jun 30 entry) appears already fixed/worked around — not independently re-verified against `order_cart_sheet.dart` internals in this pass, flagged for Phase 2 spot-check.

Realtime is used heavily as a de facto state-invalidation mechanism: providers subscribe to `postgres_changes` and call `ref.invalidateSelf()`/`refresh()` on change (`lib/features/food_trucks/providers/food_truck_provider.dart:34`, `:77`, `:94`), rather than using Supabase realtime purely for cross-client sync.

## 4. Navigation / Routing

`go_router: ^17.3.0`, single `routerProvider` defined once in `lib/router.dart:40-220`, exposed via `sharedRouter` global getter (`lib/router.dart:35`) for use in non-widget code (push notification tap routing, `lib/core/push_notification_service.dart`).

- **Redirect/guard logic**: `lib/router.dart:44-73`, a single `redirect` callback using `ref.read` (not `watch`) so the router itself is never recreated (see comment `lib/router.dart:37-39`). Order of checks: onboarding-incomplete → force `/onboarding`; unauthenticated + not on an auth/guest route → force `/login`; authenticated + on an auth route → route to `/dashboard` or `/map` by role; authenticated owner not on an owner-prefixed route → force `/dashboard`.
- **Refresh trigger**: `_AuthListenable` (`lib/router.dart:223-227`) listens to `authProvider` and `onboardingProvider` via `ref.listen` and calls `notifyListeners()`, which go_router uses as `refreshListenable` to re-run `redirect`.
- **Two independent `StatefulShellRoute.indexedStack` trees**: consumer (`lib/router.dart:82-125`, 4 branches: Map/Favorites/Notifications/Account) and owner (`lib/router.dart:128-214`, 4 branches: Dashboard/Bookings/Notifications/Account), each with its own shell widget (`ConsumerShell`, `OwnerShell` in `lib/shells/`). Nested routes hang off the primary branch of each (e.g. truck profile, calendar, edit-truck under `/dashboard`).
- **Deep linking**: `app_links: ^6.4.0` is a dependency (used for password-reset / universal links per `AppShell`'s `onAuthStateChange` listener at `lib/app_shell.dart:26-30`, which routes to `/set-new-password` on `AuthChangeEvent.passwordRecovery`). Push-notification deep links are buffered and drained once router + auth are both ready (`lib/core/push_notification_service.dart:18-45`), guarding against a race where `getInitialMessage()` resolves before the router exists.
- **Dialog/context-pop pattern inside shell routes** (memory: `feedback_navigator_pop_in_shell.md` — must use `dialogContext`, not outer `context`): the codebase is now **largely consistent** — 35 of the `dialogContext`-style call sites checked (`dashboard_screen.dart:343,353,358,568,580,585`; `manage_menu_screen.dart:162,167,171`; `my_requests_screen.dart:310,315,317,454,461,470,477,479`; `login_screen.dart:79`; `truck_bottom_sheet.dart:28,33`) correctly name the dialog's own `BuildContext` parameter `dialogContext` and pop with it. One remaining raw `Navigator.pop(context)` was found at `lib/features/account/widgets/transfer_truck_sheet.dart:79`, but it is **not** a repeat of the bug — that `context` belongs to `_TransferTruckSheetState` itself (the sheet's own content widget, passed directly as `showModalBottomSheet`'s `builder` return value in the caller), not a nested dialog inside it, so popping with it is correct. No new instances of the memory's bug pattern were found in this pass.

## 5. Dependency Injection

Primarily **Riverpod provider-based DI** with a secondary, inconsistent pattern of manual/global instantiation:

- Standard pattern: repository providers wrap concrete repository classes taking `SupabaseClient` in their constructor, e.g. `foodTruckRepositoryProvider` (`lib/features/food_trucks/providers/food_truck_provider.dart:9-11`), `authRepositoryProvider` (`lib/features/auth/providers/auth_provider.dart:26-28`), `mapRepositoryProvider` (`lib/features/map/providers/map_provider.dart:7-9`). Widgets never construct repositories directly in the common case — they go through `ref.read(xRepositoryProvider)`.
- **Inconsistency #1 — `lib/services/`**: `storage_service.dart:30` instantiates `StorageService` as an eager **top-level global** (`final storageServiceInstance = StorageService(Supabase.instance.client);`), not a Riverpod provider — different DI convention from every other service/repository in the codebase, and it evaluates `Supabase.instance.client` at library-load time rather than lazily, creating an implicit ordering dependency on `Supabase.initialize()` in `main.dart:36-39` having already run before this file is first imported.
- **Inconsistency #2 — manual re-instantiation bypassing the provider**: `lib/features/owner_dashboard/screens/dashboard_screen.dart:908` and `:1359` construct `OrdersRepository(Supabase.instance.client)` and `FavoritesRepository(Supabase.instance.client)` directly inline instead of using `ref.read(ordersRepositoryProvider)` / `ref.read(favoritesRepositoryProvider)` — bypasses the DI layer for those two calls even though provider equivalents exist elsewhere in the codebase.
- `subscriptionServiceProvider` (`lib/services/subscription_service.dart:38`) *is* a Riverpod provider, so the `services/` folder mixes both conventions internally.

## 6. Services, Repositories, Models — Data Access Isolation

Table/bucket name constants exist in `lib/core/constants/supabase_constants.dart:1-19` but cover only 8 of the ~19 tables actually queried. A repo-wide scan of `.from('...')` call sites (`grep -rn "\.from('" lib`) found raw string literals used for: `event_booking_requests` (9), `employee_shifts` (8), `profiles` (7, despite a constant existing), `orders` (7), `scheduled_shifts` (6), `truck_transfers` (5), `notifications` (5), `planned_locations` (4), `food_trucks` (4, despite a constant existing), `booking_quotes` (4), `booking_messages` (3), `notification_preferences` (2), `follower_notification_preferences` (2), `booking_deposits` (2), `avatars` (2), `truck_employees` (1), `subscriptions` (1), `push_tokens` (1), `order_items` (1). So table-name-as-magic-string is the *actual* prevailing convention; `SupabaseConstants` is only partially adopted (used in `food_truck_repository.dart`, `map_repository.dart`, `auth_repository.dart` but not in `orders_repository.dart`, `bookings_repository.dart`, `transfer_truck_sheet.dart:71`, etc.).

**Supabase calls are not fully isolated behind repositories.** `grep` for `Supabase.instance.client` outside `repositories/`/`providers/` directories found **18 screen/widget files** calling Supabase directly: `account_screen.dart`, `transfer_truck_sheet.dart`, `set_new_password_screen.dart`, `booking_chat_screen.dart`, `booking_requests_screen.dart`, `employee_dashboard_screen.dart`, `employees_screen.dart`, `announce_week_sheet.dart`, `assign_shift_sheet.dart`, `employee_go_live_card.dart`, `truck_profile_screen.dart`, `notifications_screen.dart`, `my_orders_screen.dart`, `order_queue_screen.dart`, `stripe_connect_screen.dart`, `order_cart_sheet.dart`, `dashboard_screen.dart`, `edit_truck_screen.dart`. Much of this is legitimate direct realtime-channel subscription in `StatefulWidget`s (e.g. `dashboard_screen.dart:1038,1247,1263` sets up `_ordersChannel`/`_workedChannel`/`_scheduledChannel` directly), which is a defensible pattern for widget-lifecycle-scoped realtime — but some is plain CRUD that duplicates what a repository should own (e.g. `dashboard_screen.dart:32-78` block queries `profiles` and other tables directly rather than through a repository method).

Service layer proper (`lib/core/`, `lib/services/`):
- `LocationTrackingService` (`lib/core/location_tracking_service.dart:14-86`) — singleton (`instance` static field, `_-` private constructor), wraps `Geolocator.getPositionStream` with distance/time throttling (30m / 10s, `:32`, `:52`) and reverse-geocodes via `geocoding` package; platform-branches Android foreground-service vs iOS background-modes settings (`:29-47`).
- `PushNotificationService` (`lib/core/push_notification_service.dart`, 241 lines) — static-method class wrapping Firebase Messaging, cold-start deep-link buffering (`:18-45`), and fire-and-forget edge function invocations for truck-open/closed alerts (`:59-80`).
- `StorageService` / `SubscriptionService` (`lib/services/`) — thin wrappers over Supabase Storage and RevenueCat `Purchases`, respectively.

Models are plain Dart classes with `fromMap`/`toMap` (no `freezed`/`json_serializable` — neither is a dependency in `pubspec.yaml`), e.g. `AppUser` (`lib/features/auth/models/app_user.dart`), `FoodTruck`, `Order`. No `copyWith` audited for correctness in this pass but `truck.copyWith(...)` is used for optimistic UI updates (`lib/features/food_trucks/providers/food_truck_provider.dart:119-123,137-144,153`).

## 7. Data Flow — Two Traced End-to-End Flows

**Flow A — Consumer map → sees trucks:**
`MapScreen` (`lib/features/map/screens/map_screen.dart`) → `ref.watch(activeTrucksProvider)` (`lib/features/map/providers/map_provider.dart:11-13`, a `StreamProvider`) → `MapRepository.streamActiveTrucks()` (`lib/features/map/repositories/map_repository.dart:22-55`) → creates a `StreamController` that on `onListen` (a) immediately calls `fetchActiveTrucks()` (`:11-20`, a `SELECT ... WHERE is_active=true AND is_open=true AND lat/lng NOT NULL`) and (b) opens a Supabase Realtime channel `active-trucks` on `food_trucks` table `PostgresChangeEvent.all`, re-running `fetchActiveTrucks()` on every change (`:37-45`). User location comes from a separate `userLocationProvider` `StreamProvider` (`map_provider.dart:17-34`) wrapping `Geolocator.getPositionStream`. Tapping a pin sets `selectedTruckProvider` (`SelectedTruckNotifier`, `map_provider.dart:36-45`) which drives `TruckBottomSheet` (`lib/features/map/widgets/truck_bottom_sheet.dart`).

**Flow B — Owner creates/updates truck listing:**
Signup: `RegisterOwnerScreen` → `authProvider.notifier.signUpOwner(...)` (`lib/features/auth/providers/auth_provider.dart:90-116`) → `AuthRepository.signUpOwner` (`lib/features/auth/repositories/auth_repository.dart:46-88`) does `supabase.auth.signUp` then three inserts in sequence (no transaction — see §11): `profiles` upsert (`:62-67`), `food_trucks` insert (`:69-80`), `subscriptions` insert with `status: 'trialing'` (`:82-85`). Post-signup edits: `OwnerTruckNotifier` (`lib/features/food_trucks/providers/food_truck_provider.dart:49-168`) loads the owner's truck via `FoodTruckRepository.fetchOwnerTrucks` (`food_truck_repository.dart:19-25`), and screens like `EditTruckScreen`/`ManageMenuScreen`/`ManageHoursScreen` call `ownerTruckProvider.notifier.updateProfile(...)` etc., which round-trip through `FoodTruckRepository.updateProfile/updateOpenStatus/updateLocation/upsertOperatingHours/addMenuItem` (`food_truck_repository.dart:27-109`) and then call `refresh()` to reload state (`food_truck_provider.dart:166`). Going live also triggers `LocationTrackingService.instance.start(onLocation: updateLocation)` (`food_truck_provider.dart:60-61`), which streams GPS into `FoodTruckRepository.updateLocation` on a throttle.

**Flow C — Order placement (sampled, not in the original two but directly relevant to "order flow"):**
`OrderCartSheet` (`lib/features/orders/widgets/order_cart_sheet.dart`) reads `cartProvider` (`Notifier<Map<String,CartItem>>`, `orders_provider.dart:111`) → on checkout calls `OrdersRepository.createPaymentIntent` (invokes edge function `create-payment-intent`, `orders_repository.dart:17-31`) → Stripe payment sheet (`flutter_stripe`) confirms client-side → `OrdersRepository.placeOrder` (`:33-78`) does a **non-transactional** sequence: insert `orders` row, insert `order_items` rows, fire-and-forget invoke `send-order-notification` (`:70`, `_invokeNotification`), then re-fetch the joined order row. Owner side: `OrderQueueScreen` subscribes to a realtime channel directly (bypassing the repository, `order_queue_screen.dart` per §6) and calls `OrdersRepository.updateOrderStatus` (`:115-129`) on accept/decline, which conditionally fires notification and/or refund edge functions.

## 8. Flutter ↔ Supabase / Edge Functions / AI Agent Communication

**Auth**: `supabase_flutter: ^2.14.2`, initialized in `main.dart:36-39` with URL/publishable key from `--dart-define-from-file=.env.json` (compile-time constants, `main.dart:13-14`). Session handled entirely client-side via `supabase.auth`; `AuthRepository` wraps `signInWithPassword`, `signUp`, Apple/Google OAuth (`lib/features/auth/repositories/auth_repository.dart`).

**Edge Functions invoked directly from the Flutter app** (via `supabase.functions.invoke(...)`, confirmed by grep across `lib/`): `create-payment-intent`, `create-booking-payment-intent`, `stripe-connect-onboard` (`orders_repository.dart:21,136`), `create-refund`, `send-order-notification` (`orders_repository.dart:149,162`), `send-truck-announcement`, `send-booking-notification` (`push_notification_service.dart:52,63,76`), plus (not directly grepped but named in `HANDOFF.md`) `send-message-notification`, `send-shift-notification`, `accept-truck-transfer`, `generate-booking-invoice`, `delete-account`.

**Edge Functions that are backend-only / never called from the app** — triggered by DB triggers, Stripe/RevenueCat webhooks, or `pg_cron`: `stripe-webhook`, `revenuecat-webhook`, `send-owner-onboarding-emails` (DB trigger on `subscriptions` insert/update per `HANDOFF.md`), `send-owner-day7-checkin` (daily cron), `send-consumer-welcome-email` (DB trigger on `profiles` insert), `send-booking-confirmation-email`, `prospect-businesses` (sales agent tool), and all 9 `agent-*` functions.

**AI Agent System** — fully backend, no Flutter involvement. Per `HANDOFF.md` (updated Jul 3 2026, `HANDOFF.md:1-2`) and `AGENT_AUTOMATION_RUNBOOK.md:1-11`, this was migrated off "Claude Cowork" (desktop-app-gated scheduled tasks, documented as the now-retired system in `COWORK_AGENT_SETUP.md`) to `pg_cron` + Supabase Edge Functions calling the Anthropic API directly, running 24/7. 9 agent functions: `agent-sage` (support, every 5 min), `agent-miles` (sales, MWF), `agent-piper` (marketing), `agent-aiden-inbox` + `agent-aiden-supervisor` (weekly synthesis/cost report to `johnny@farlo.app`), `agent-email-labeler`, `agent-newsletter-cleanup`, `agent-stripe-weekly`, `agent-urgent-alert`, `agent-run-check`. Shared code in `supabase/functions/_shared/`: `claude-agent.ts` (Anthropic call loop + usage capture), `gmail.ts`, `pricing.ts` (cost estimation), `run-log.ts`, `auth.ts`, `notify.ts`. Shared state lives in Postgres tables (`agent_directives`, `supervisor_reports`, `support_tickets`, `sales_prospects`, `content_queue`, `agent_run_log`).

**Orphaned artifact**: a root-level `index.ts` (untracked, `git status` shows `?? index.ts`) is a near-duplicate but *not identical* copy of `supabase/functions/send-owner-onboarding-emails/index.ts` — different import style (`jsr:` vs `esm.sh`), different constant structure (diffed, not byte-identical). This is dead/stray code sitting at repo root, not part of the deployed function tree — flag for cleanup, and for Phase 2 to confirm it's not accidentally what gets deployed by any tooling.

**Untracked/uncommitted Supabase functions**: `git status` shows 5 function directories and `supabase/.temp/` as untracked (`prospect-businesses`, `send-agent-email`, `send-consumer-welcome-email`, `send-owner-day7-checkin`, `send-owner-onboarding-emails`) even though they are live and referenced in `HANDOFF.md` as deployed — working tree is ahead of what's committed to git for backend code.

## 9. Major Modules & Interactions

| Module | Depends on | Consumed by |
|---|---|---|
| `auth` | Supabase Auth, RevenueCat (`rc_config.dart`), `sign_in_with_apple`, `google_sign_in` | `router` (redirect logic), almost every feature (via `authProvider`) |
| `router` | `auth`, `onboarding` providers | `app_shell` |
| `map` | Supabase Realtime, `geolocator` | `food_trucks` (truck detail nav), consumer shell |
| `food_trucks` | `map` models (`FoodTruck`), `auth`, `LocationTrackingService` | `owner_dashboard`, `map`, `bookings`, `orders`, `reviews` |
| `owner_dashboard` | `food_trucks`, `orders`, `favorites`, `employees`, `bookings`, Stripe Connect | owner shell |
| `orders` | `food_trucks` (truck ref), Stripe (`flutter_stripe`), Edge Functions | consumer + owner order screens |
| `bookings` | `food_trucks`, Stripe, Edge Functions (`generate-booking-invoice`) | owner + consumer booking screens |
| `employees` | `food_trucks` (truck_id), `auth` | owner dashboard only |
| `favorites` | `food_trucks` | consumer favorites tab, dashboard's follower features |
| `notifications` | Firebase Messaging, Supabase table `notifications` | both shells (badge counts) |
| `reviews` | `food_trucks`, `auth` | `truck_profile_screen` |
| `core` | (leaf — no feature deps) | everything |

`core` and `auth` are the two universal dependencies; `food_trucks` is the central domain entity most other features key off of (via `truck_id`).

## 10. Strengths

- **Consistent feature-first layout** at the top level (`models/providers/repositories/screens/widgets` per feature) makes the codebase navigable despite its size — verified across 8+ features.
- **Repository pattern is real, not cargo-culted**, for the majority of data access: `FoodTruckRepository`, `MapRepository`, `OrdersRepository`, `AuthRepository`, `BookingsRepository` all cleanly wrap one `SupabaseClient` each with typed methods and no leaked query-builder objects into providers.
- **Deliberate, documented defensive engineering** around real production incidents: the `main.dart:27-38` fail-loud check on empty Supabase config was added specifically because `assert()` was silently stripped in release mode and caused a real App Store rejection (per `HANDOFF.md`'s Jul 1 entry) — the fix and its rationale are both in the code comment and the handoff doc.
- **Auth timeouts and optimistic-update rollback discipline**: `_authTimeout`/`withAuthTimeout` extension (`auth_provider.dart:11-19`) prevents indefinite hangs; `OwnerTruckNotifier.setOpenStatus`/`updateOrdersAccepting` (`food_truck_provider.dart:115-160`) apply optimistic state then roll back on failure via `catch` + `rethrow`.
- **Router redirect uses `ref.read` not `ref.watch`** with an explicit `ChangeNotifier` bridge (`_AuthListenable`) specifically to avoid router-recreation churn — shows Riverpod/go_router interaction was thought through, not just wired up naively (`router.dart:37-39` comment).
- **Realtime is used consistently as an invalidation signal** (not just raw display data) across `food_truck_provider.dart`, `map_repository.dart`, `dashboard_screen.dart` — one coherent mental model for "how does the UI learn about server-side changes."
- **Cold-start push-notification race condition explicitly solved**: `PushNotificationService`'s pending-message buffer (`push_notification_service.dart:18-45`) is a well-reasoned fix for a real ordering hazard (FCM resolving before router/auth are ready).

## 11. Weaknesses / Inconsistencies

- **Supabase access is not uniformly isolated behind repositories** — 18 screen/widget files call `Supabase.instance.client` directly (§6), some legitimately (widget-lifecycle realtime subscriptions) but some duplicating repository-owned CRUD, e.g. raw table queries inside `dashboard_screen.dart:32-78`.
- **`SupabaseConstants` (`core/constants/supabase_constants.dart`) is only ~30% adopted** — most `.from('table')` call sites use raw string literals for table names (§6 table), including in files that already import the constants class for other tables (e.g. `orders_repository.dart` never uses `SupabaseConstants.foodTrucksTable`, joins via raw `'food_trucks(name)'` string at `:11,83`). Typo-in-a-string-literal is a live risk with zero compiler protection.
- **DI is inconsistent**: most services are Riverpod providers, but `storageServiceInstance` (`lib/services/storage_service.dart:30`) is an eagerly-instantiated top-level global with an implicit init-order dependency on `Supabase.instance.client` being ready; `dashboard_screen.dart:908,1359` manually construct repositories inline instead of reading the existing providers.
- **`lib/core/` vs `lib/services/` split has no clear rule** — `LocationTrackingService`/`PushNotificationService` live in `core/`, `StorageService`/`SubscriptionService` live in `services/`, both are the same kind of thing (stateless-ish wrapper services); no discoverable principle differentiates the two folders.
- **"God screen" files**: `dashboard_screen.dart` is 1,524 lines, `account_screen.dart` 1,458, `calendar_screen.dart` 1,435, `truck_profile_screen.dart` 1,426, `booking_requests_screen.dart` 1,375, `map_screen.dart` 1,025 — six files over 1,000 lines each mixing UI, direct Supabase calls, dialog builders, and business logic in one `StatefulWidget`/`ConsumerStatefulWidget`. No sub-widget extraction discipline evident at this scale (spot-checked `dashboard_screen.dart`).
- **No domain/data-model separation** — `AppUser`, `FoodTruck`, `Order` etc. are simultaneously wire-format DTOs (`fromMap`/`toMap` matching Postgres column names) and UI view-models; a backend column rename requires touching UI-adjacent code.
- **Multi-step writes without DB transactions**: `AuthRepository.signUpOwner` (`auth_repository.dart:46-88`) performs `auth.signUp` → `profiles` upsert → `food_trucks` insert → `subscriptions` insert as four sequential, non-atomic client calls — a mid-sequence failure (network drop, RLS rejection) leaves a user in a partial state (e.g. profile without a truck, or truck without a subscription row). Same pattern in `OrdersRepository.placeOrder` (`orders_repository.dart:33-78`: insert `orders`, then insert `order_items`, then fire notification, then re-fetch — no rollback of the `orders` row if `order_items` insert fails).
- **Effectively zero automated test coverage**: `test/widget_test.dart` is a single placeholder (`expect(true, isTrue)`), with a comment "Phase 1 focus: unit tests for auth logic" that was apparently never followed through. No tests exist for `AuthNotifier`, `OrdersRepository`, router redirect logic, or any provider.
- **Declared-but-unused dependencies**: `riverpod_annotation`/`riverpod_generator`/`build_runner` are in `pubspec.yaml:39,68-69` but `@riverpod` codegen is used nowhere (`grep -rln "@riverpod" lib` = empty, zero `.g.dart` files) — either dead weight to prune or an incomplete migration.
- **Dead/orphaned file**: root-level `index.ts` (untracked, not part of `supabase/functions/`) is a near-duplicate of `send-owner-onboarding-emails/index.ts` with a different import style — stray, should be removed or clarified.
- **Backend code ahead of git**: 5 live, referenced-in-docs Edge Function directories plus `supabase/.temp/` are untracked in git (`git status`), meaning the committed repo does not currently reflect the deployed backend state.
- **`.env.json.example` is incomplete relative to what `main.dart` actually reads**: `main.dart:13` reads `STRIPE_PUBLISHABLE_KEY` via `String.fromEnvironment`, but `.env.json.example` (`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `REVENUECAT_APPLE_KEY`, `REVENUECAT_GOOGLE_KEY`) omits it — a new dev following the example file would build a Stripe-less app silently (no `flutter analyze`/runtime error, `Stripe.publishableKey` is simply left unset — guarded by `main.dart:22` `if (_stripePublishableKey.isNotEmpty)`, so it fails silently rather than loudly, unlike the Supabase check three lines below it).

## 12. Concerns for Later Phases (flagged, not investigated deeply here)

- **Security/RLS review needed**: repositories trust the client to send correct IDs (e.g. `consumerId = _supabase.auth.currentUser!.id` client-side in `orders_repository.dart:39`) — whether Postgres RLS policies independently enforce ownership on every table (`orders`, `order_items`, `food_trucks`, `truck_transfers`, `booking_quotes`, etc.) was not verified in this pass and is core Phase-2 (backend/Supabase) territory. `.mcp.json` in the repo working tree contains a plaintext Supabase management API bearer token (`sbp_...`) — it is correctly gitignored (verified via `git ls-files .mcp.json` = empty), so not a committed-secret leak, but worth a Phase-2 note on local secret hygiene.
- **Transactional integrity**: the multi-step, non-atomic write sequences noted in §11 (owner signup, order placement) are a correctness/data-integrity risk under partial failure — worth checking whether Postgres functions/triggers backstop atomicity server-side, or whether it's genuinely client-sequenced with no compensating logic.
- **Scalability of the realtime-invalidation pattern**: every open `food_truck_provider`/`map_repository` stream holds a live Postgres Realtime channel per truck/screen; no code was seen capping concurrent channel counts — worth checking behavior at scale (many trucks, many simultaneous owner dashboards).
- **God-screen maintainability**: the six 1,000+ line screen files (§11) are a growing risk for merge conflicts and regression as feature velocity continues — worth a refactor pass to extract widgets/controllers before they grow further, independent of any specific bug.
- **App Store readiness**: per `HANDOFF.md` (`HANDOFF.md:9-20`), build `1.0.0+5` has been rejected three times (auth config, IAP discoverability, inaccurate metadata) and is currently "Waiting for Review" as of the stated last-updated date. Android RevenueCat and Play Store background-location declaration are both flagged incomplete in the same status table. This is a live release-blocking concern, not purely architectural, but the recurring root causes (silently-stripped `assert()`, dart-define misconfiguration, reviewer-navigation ambiguity) suggest the release/build-verification process itself is a gap worth a dedicated phase.
- **Native/platform layer**: `android/` and `ios/` were not audited in this pass (explicitly out of scope) beyond noting `MainActivity.kt`, splash/launcher-icon assets, and `styles.xml` show as locally modified in `git status` — flag for a native-layer phase given the app is mid-launch-iteration on both stores.
- **AI agent system reliability**: `HANDOFF.md`/`AGENT_AUTOMATION_RUNBOOK.md` document at least 3 real production bugs already found and fixed in the agent layer post-launch (duplicate email replies, wrong DB column, unanchored regex on email headers) — this is a fast-iterating, low-test-coverage backend subsystem now handling real customer-facing support/sales communication; worth a dedicated review of `_shared/claude-agent.ts` and the loop/cost-protection logic described in the runbook.

## 13. Tech Stack & Dependencies

`pubspec.yaml`: `environment.sdk: ^3.12.1` (Dart 3.12.1 confirmed installed via `dart --version`; Flutter 3.44.1 stable channel installed locally). App `version: 1.0.0+5`.

**State/Nav/Backend:**
- `flutter_riverpod: ^3.3.2`, `riverpod_annotation: ^4.0.3` (unused, see §11)
- `go_router: ^17.3.0`
- `supabase_flutter: ^2.14.2`

**Maps/Location:**
- `flutter_map: ^8.3.0`, `latlong2: ^0.9.1`, `geolocator: ^14.0.2`, `geocoding: ^4.0.0`, `permission_handler: ^12.0.3`

**Payments:**
- `flutter_stripe: ^13.0.0`, `purchases_flutter: ^10.2.3` (RevenueCat)

**Push/Analytics infra:**
- `firebase_core: ^3.9.0`, `firebase_messaging: ^15.2.5`

**Auth:**
- `sign_in_with_apple: ^6.1.2`, `google_sign_in: ^7.2.0`, `crypto: ^3.0.6` (nonce hashing for Sign in with Apple)

**Misc:**
- `cached_network_image: ^3.4.1`, `image_picker: ^1.1.2`, `url_launcher: ^6.3.2`, `share_plus: ^10.1.0`, `add_2_calendar: ^3.0.1`, `app_links: ^6.4.0`, `shared_preferences: ^2.3.2`, `font_awesome_flutter: ^11.0.0`, `http: ^1.2.0`, `path_provider: ^2.1.5`

**Dev:**
- `flutter_lints: ^6.0.0` (default rule set, no custom rules enabled/disabled — `analysis_options.yaml` has all customization commented out)
- `riverpod_generator: ^4.0.4`, `build_runner: ^2.15.0` — declared, unused (§11)
- `flutter_launcher_icons: ^0.14.1`, `flutter_native_splash: ^2.4.4`

**Notable absences**: no `freezed`/`json_serializable` (manual `fromMap`/`toMap` everywhere), no analytics SDK (no Firebase Analytics, Mixpanel, Amplitude, Sentry, or any crash-reporting package in `pubspec.yaml` — production crash visibility is a gap worth Phase-2 attention), no `dio` (plain `http` + Supabase's own client), no explicit HTTP retry/interceptor library. Dependency versions all look current for a mid-2026 Flutter app (Riverpod 3.x, go_router 17.x are both recent majors) — nothing egregiously outdated was observed, though a `flutter pub outdated` run was not executed in this pass (would require network access / CI context).
