# Farlo — Production Bug Audit at 1M-User Scale (Phase 9: Discovery)

**Scope:** Flutter app (`lib/`) + Supabase Edge Functions (`supabase/functions/`), read against a
hypothetical **1,000,000 active users**. Discovery only — no code, config, or DB mutations were
made; no live Edge Functions or mutating SQL were invoked. Grounded in full reads of all eight prior
audit reports (`architecture.md`, `supabase-audit.md`, `ai-agents.md`, `code-quality.md`,
`app-store-review.md`, `ux-review.md`, `security.md`, `performance.md`) — known issues from those
reports are referenced only where directly relevant to a new finding, not re-litigated.

**Method:** Direct code reads/greps by the lead reviewer plus five parallel deep-dive passes (logical
bugs/crashes; race conditions/concurrency; forms/validation; unexpected states/navigation/offline;
scale-specific modeling), each independently grounded in the same prior-audit context and cross-
verified against the live repo. Every finding below has file:line evidence, a concrete trigger
scenario, and a probability/frequency estimate calibrated to 1,000,000 active users.

**Total new findings: 43**, spanning 10 categories. None of these are re-statements of the
already-documented issues listed in the task brief (non-transactional writes, the chat
input-clear-before-send bug, non-autoDispose providers as a general finding, zero pagination/
timeouts as a general finding, map per-frame rebuild, the specific payment/RLS/employee-shift
security findings, or iOS background location) — where a new finding is a fresh manifestation of one
of those root causes, it is explicitly labeled as such.

---

## 1. Executive Summary — Top 8 Findings Ranked by (Probability × Severity)

1. **`searchTrucks()` crashes the map search screen for any truck that has never gone live** — a
   force-unwrap on nullable `latitude`/`longitude` in `map_screen.dart:876-882`, fed by a query in
   `map_repository.dart:57-67` that (unlike its sibling `fetchActiveTrucks`) omits the
   not-null-location filter. **Certain within the first day of any meaningful signup volume** — every
   newly registered mobile truck sits in exactly this crash-triggering state until its first "Go
   Live" tap, and search is one of the first things anyone tries. **Severity: Critical (crash).**

2. **Consumer "Cancel Order" and owner "Accept Order" race with no optimistic-concurrency guard,
   producing a silent contradictory state and a wrongful refund.** `order_status_sheet.dart` holds a
   stale snapshot; `orders_repository.dart:91-98`'s `cancelOrder()` blindly sets
   `status='cancelled'` and fires a refund with no `.eq('status','pending')` precondition. **Expect
   dozens-to-low-hundreds of occurrences per day at 1M-user order volume** — order acceptance is
   often faster than a consumer re-opens the cancel sheet. **Severity: Critical (financial +
   data corruption).**

3. **A failed `placeOrder()` after a successful Stripe charge strands the customer's money with no
   compensating refund, and the cart is never cleared — inviting an immediate double-charge retry.**
   `order_cart_sheet.dart:32-89`: `cartNotifier.clear()` (line 68) is only reached after
   `repo.placeOrder()` succeeds; any exception between charge-success and order-insert (including
   the `_supabase.auth.currentUser!.id` force-unwrap in `orders_repository.dart:39`) is swallowed by
   a generic catch and never triggers a refund. **A steady daily trickle of stranded-charge support
   tickets/chargebacks at 1M-user checkout volume.** **Severity: Critical (financial, trust).**

4. **A lapsed/canceled subscription is never rechecked once a truck is already live — full paid
   functionality (visible on the map, accepting orders, taking deposit/invoice payments) continues
   indefinitely with no client or server-side recheck.** No realtime channel or poll on
   `subscription_provider.dart`, no router-level guard (`router.dart`'s `_AuthListenable` watches
   only `authProvider`/`onboardingProvider`), and confirmed **zero** subscription check inside
   `create-payment-intent`/`create-booking-payment-intent` or the public `fetchActiveTrucks()` query.
   **A continuous, certain revenue-leak/policy-bypass window for any owner whose card is declined or
   subscription cancels mid-session** — not an edge case, a design gap. **Severity: High (continuous
   silent revenue leak).**

5. **Ordinary search text containing a comma or parenthesis breaks truck search for every user.**
   `map_repository.dart:57-67` splices the raw user query directly into a PostgREST `.or()` filter
   string (`'name.ilike.%$q%,cuisine_type.ilike.%$q%'`) with no escaping — PostgREST's filter syntax
   treats commas/parentheses as structural separators. **The single most reproducible bug in this
   audit — fires on natural search text like "mac, cheese" or "bbq (smoked)", not an edge case.**
   **Severity: High (core-feature breakage at high frequency).**

6. **Realtime channel leak modeled concretely: ~200,000 permanently-open Postgres Realtime
   subscriptions from ONE leak path alone, at just 1% concurrent-user overlap.**
   `foodTruckProvider(truckId)` (`food_truck_provider.dart:22-37`, `AsyncNotifierProvider.family`,
   not `.autoDispose`) opens a `consumer-menu-$truckId` channel per truck ever viewed and never tears
   it down. A realistic 20-truck browsing session × 10,000 concurrently-active users (1% of 1M) =
   200,000 leaked channels from this provider alone, before counting the other non-autoDispose
   channel-bearing providers (`pendingBookingCountProvider`, dashboard channels). **This is an
   infrastructure risk that can degrade Realtime/connection-pool service for ALL users, not just the
   ones who caused it.** **Severity: High (systemic infra risk, new concrete scale modeling on top of
   the already-known non-autoDispose finding).**

7. **A systemic "no request sequencing" pattern means out-of-order network responses silently
   overwrite newer state with stale data across at least 5 `AsyncNotifier.load()/refresh()` call
   sites** (`OwnerTruckNotifier.refresh()`, `OwnerOrdersNotifier.load()`, `MyOrdersNotifier.load()`,
   `OwnerBookingRequestsNotifier.load()`), each triggered concurrently from realtime callbacks,
   app-resume, and pull-to-refresh with no generation/cancellation token. **Routine, not rare** — any
   truck getting more than one order within the same few-hundred-ms window (an ordinary lunch rush)
   can see its Order Queue transiently revert to a stale/wrong list. **Severity: High (routine, daily,
   trust-damaging).**

8. **`SubscriptionStatus.fromString` fails open: any unrecognized status string silently defaults to
   `trialing`, and `trialing` grants full paid access (`hasAccess == true`).**
   `subscription.dart:7-12,31-32`, gating real feature access at `dashboard_screen.dart:112,167` and
   `employees_screen.dart:145`. Currently unreachable via the live webhook (which only ever writes 4
   known values), but a landmine: the first time anyone extends the RevenueCat webhook's switch for a
   new event type, or a support engineer manually corrects a `subscriptions.status` typo, every owner
   with the resulting unrecognized value **instantly and silently regains full free access to every
   paid feature**, with no error, no log, no alert. **Severity: Medium-High (latent, systemic blast
   radius when triggered — a near-certainty at some point across a codebase's multi-year life at this
   scale).**

---

## 2. Findings by Category

### 2.1 Logical Bugs / State Machines

**2.1.1 — `SubscriptionStatus.fromString` fail-open default grants full paid access on any
unrecognized status string.**
- Evidence: `lib/features/owner_dashboard/models/subscription.dart:7-12`
  ```dart
  static SubscriptionStatus fromString(String s) => switch (s) {
        'active' => SubscriptionStatus.active,
        'past_due' => SubscriptionStatus.pastDue,
        'canceled' => SubscriptionStatus.canceled,
        _ => SubscriptionStatus.trialing,
      };
  ```
  and `:31-32`: `bool get hasAccess => status == SubscriptionStatus.active || status == SubscriptionStatus.trialing;`
  Consumed at `dashboard_screen.dart:112,167` (gates announcement send, go-live toggle) and
  `employees_screen.dart:145` (gates employee management).
- Trigger: `subscriptions.status` ever contains a value other than `active`/`past_due`/`canceled`/
  `trialing` — e.g. a future RevenueCat webhook event type added with a typo'd status string, a
  manual admin/support fix to a stuck row, or a data migration.
- What happens: the owner's client-side gate silently treats them as `trialing`, which grants
  `hasAccess == true` — full paid feature access with no billing behind it, no error, no log line
  anywhere client-side.
- Probability at scale: low today (the live `revenuecat-webhook/index.ts:46-61` switch only ever
  writes 4 known strings, confirmed by direct read), but the blast radius is systemic and the trigger
  condition (a future code change or manual DB touch) becomes near-certain over a multi-year product
  lifetime with a support team touching subscription rows regularly at 1M-user scale.
- Severity: Medium-High.

**2.1.2 — Unknown/future `event_booking_requests.status` values are mislabeled as "Pending", not
displayed as unknown.**
- Evidence: `lib/features/bookings/screens/booking_requests_screen.dart:612-616`
  ```dart
  final (label, bg, fg) = switch (status) {
        'accepted' => (...),
        'declined' => (...),
        'cancelled' => (...),
        _ => ('Pending', ...),   // any unrecognized value renders as "Pending"
      };
  ```
- Trigger: a booking status value the shipped app doesn't recognize (future migration adding e.g.
  `'expired'`/`'no_show'`, or simply a typo written by a support tool).
- What happens: unlike the equivalent order-status switches (which fall back to displaying the raw
  string, see §2.8), this one actively **relabels** an unrecognized status as "Pending" — a genuinely
  terminal/resolved booking could display as still awaiting a decision, confusing both parties into
  thinking action is still needed.
- Probability at scale: low today (no unrecognized value is currently written), but every future
  additive status change to this column silently reintroduces this exact mislabeling for the
  fraction of the 1M install base still on an older client — see §2.10.4 for the cross-version
  framing.
- Severity: Medium.

**2.1.3 — `truck_transfers.status` collapses two semantically different actions ("recipient
declined" vs. "owner cancelled") into the identical string, with no disambiguating column, and
neither write path guards on current status.**
- Evidence: `lib/features/account/screens/account_screen.dart:274-305` (`_declineTransfer`) and
  `:434-448` (`_cancelTransfer`) both execute `update({'status':'cancelled'}).eq('id', transferId)`
  with no `.eq('status','pending')` precondition; unlike `event_booking_requests` (which has a
  `cancelled_by` column), `truck_transfers` has no equivalent field.
- Trigger: the recipient accepts a transfer at nearly the same moment the original owner (impatient,
  or on a second device) cancels it.
- What happens: if `accept-truck-transfer` has already completed ownership transfer before the
  unconditioned cancel-update lands, the cancel silently overwrites `status` back to `'cancelled'`
  even though the truck has already changed hands — the original owner sees a "cancelled" success
  message while having actually lost the business, and the transfer log permanently misrepresents
  what happened.
- Probability at scale: truck transfer is a rare feature overall, so this is low-frequency but
  high-severity/high-confusion when it hits — a real financial/ownership dispute, not a cosmetic bug.
- Severity: Medium-High (rare trigger, severe/expensive-to-resolve outcome).

**2.1.4 — `orders.payment_status` is fetched but never read by any status-transition logic — an
owner can mark a refunded order "Completed" with zero indication anywhere in the UI.**
- Evidence: `lib/features/orders/models/order.dart:29` defines `paymentStatus` (`unpaid | paid |
  refunded`); `dashboard_screen.dart:48` includes it in a select list; a repo-wide grep confirms it
  is **never read** by any accept/ready/complete action, and no `_StatusChip`/`_StatusDot` widget
  renders it.
- Trigger: combine with §2.3.1's cancel/accept race — a refund fires, but the owner's queue still
  shows the order as `accepted`/`ready` (their screen hasn't refreshed) and they tap "Mark
  Completed"/hand over the food.
- What happens: the order is marked completed with the customer already refunded, with no owner-side
  signal that this order's money was returned — a direct, invisible profit-loss path that compounds
  with §2.3.1 rather than being independently rare.
- Probability at scale: bounded by how often §2.3.1's race occurs (dozens-to-hundreds/day at scale);
  this finding describes the second half of that same incident's damage.
- Severity: Medium (contributing factor, not independently triggered).

---

### 2.2 Crash Scenarios

**2.2.1 — `searchTrucks()` omits the not-null-location filter its sibling query has, producing a
force-unwrap crash on the map search results list. (Executive Summary #1.)**
- Evidence: `lib/features/map/repositories/map_repository.dart:11-19` (`fetchActiveTrucks`)
  correctly filters `.not('latitude','is',null).not('longitude','is',null)`; `map_repository.dart:
  57-67` (`searchTrucks`) has **no** such filter, only `.eq('is_active', true)`.
  `lib/features/map/models/food_truck.dart:64-65` confirms `latitude`/`longitude` are nullable.
  `lib/features/map/screens/map_screen.dart:876-882`:
  ```dart
  if (userPos != null) ...[
    _DistanceChip(
      meters: Geolocator.distanceBetween(
        userPos!.latitude, userPos!.longitude,
        truck.latitude!, truck.longitude!,   // <-- force-unwrap, no null guard
      ),
    ),
  ],
  ```
- Trigger: any user with location permission granted searches (by name or cuisine) and the result
  set includes an active-but-never-gone-live truck (a mobile business that registered but hasn't
  tapped "Go Live" even once — `setOpenStatus`, `food_truck_provider.dart:115-132`, is the only write
  path for `latitude`/`longitude` besides GPS tracking).
- What happens: immediate `Null check operator used on a null value` crash on the app's default
  launch screen, in its search feature.
- Probability at scale: **near-certain within the first day** of any real signup cohort — every new
  mobile truck sits in this crash-triggering state by default until its owner's first go-live tap,
  and testing/using search is one of the first things anyone (owner's friends, testers, curious
  early users) does.
- Severity: Critical.

**2.2.2 — `_supabase.auth.currentUser!.id` force-unwrap inside `placeOrder()`.**
- Evidence: `lib/features/orders/repositories/orders_repository.dart:39`.
- Trigger: the Supabase session/access token expires or fails silent refresh while the Stripe
  PaymentSheet is open (a 3DS challenge, backgrounding for biometric auth, or a slow network — all
  realistic during a payment flow that can run tens of seconds).
- What happens: throws a `TypeError` immediately after the card has already been successfully
  charged; caught by `order_cart_sheet.dart`'s generic `catch (e)` (not a hard crash to the user, but
  it is the direct trigger for the stranded-charge scenario in §1's Executive Summary #3).
- Probability at scale: any session-refresh hiccup mid-checkout reproduces this; a steady contributor
  to the daily stranded-charge trickle at 1M-user checkout volume.
- Severity: High (contributing cause of a Critical financial bug).

**2.2.3 — Unguarded `int.parse` on stringly-typed `"HH:MM"` operating-hours strings, reachable by
every consumer viewing any truck's profile.**
- Evidence: `lib/features/food_trucks/models/operating_hours.dart:30-37` (`_formatTime`, used by
  `hoursDisplay`) and `lib/features/owner_dashboard/screens/manage_hours_screen.dart:147-149,
  206-212` (`_pickTime`/`_TimeChip._display`) all do `time.split(':')` → `int.parse(parts[0])` /
  `int.parse(parts[1])` with no length check and no try/catch.
- Trigger: any future migration, admin tool, or a partial-write from the already-known non-atomic
  7-call `manage_hours_screen.dart:41-48` save loop that ever leaves an empty-string or malformed
  `open_time`/`close_time` value in `operating_hours`.
- What happens: crashes **every consumer** who opens that truck's profile (the read path,
  `hoursDisplay`, not just the owner's own edit screen) — one bad row poisons the profile for the
  entire audience of that truck, not just its owner.
- Probability at scale: low today (current write paths always produce well-formed zero-padded
  strings), but a landmine given the blast radius; worth hardening defensively before it's ever
  triggered by an unrelated future change.
- Severity: Medium (low current probability, but a genuinely severe, wide-blast-radius crash once
  triggered).

**2.2.4 — Verified clean (no bug, stated for completeness):** every order/booking/scheduled-shift
status-to-UI switch expression in the codebase (`order_status_sheet.dart`, `order_queue_screen.dart`,
`my_orders_screen.dart`, `booking_requests_screen.dart:612-628` for the label itself, `calendar_
screen.dart:1297-1301`, `shift_week_card.dart:438-442`) has a wildcard `_ =>` fallback — the specific
"old client crashes on a new server-added enum value" pattern the brief asked about was checked
exhaustively and **does not reproduce as a crash** anywhere (see §2.10.4 for the related, real bug —
these values don't crash, but they do silently disappear from bucketed list views). Geocoding
`.first` call sites (`location_tracking_service.dart:59`, `dashboard_screen.dart:233`,
`employee_dashboard_screen.dart:172`, `employees_provider.dart:207`) are all correctly guarded by
`.isNotEmpty` checks.

---

### 2.3 Race Conditions

**2.3.1 — Consumer "Cancel Order" vs. owner "Accept Order" race with no optimistic-concurrency
guard. (Executive Summary #2.)**
- Evidence: `lib/features/orders/widgets/order_status_sheet.dart` receives `order` as a plain
  constructor field (never watches a live provider) — the "Cancel Order" button's visibility is
  gated purely on `order.isPending` (line 203) computed once at sheet-open time from a stale
  snapshot. `lib/features/orders/repositories/orders_repository.dart:91-98` (`cancelOrder()`) does
  `update({'status':'cancelled'}).eq('id', orderId)` with **no** `.eq('status','pending')`
  precondition; `:115-129` (`updateOrderStatus()`, the owner's accept/ready/complete path) likewise
  has no precondition on the current status.
- Trigger: consumer opens the order-status sheet while the order is `pending`; before they tap
  Cancel, the owner accepts it (fast, realistic — order acceptance is often seconds). The realtime
  push updates the owner's queue and the consumer's list provider, but not the already-open sheet
  widget.
- What happens: consumer's "Cancel Order" tap blindly sets `status='cancelled'` and fires a refund
  (`_invokeRefund`), silently overwriting the owner's `accepted`/`ready` transition. The truck's local
  UI still shows `accepted`/`ready` until its next realtime tick while the DB says `cancelled` +
  refund initiated — the truck may already be preparing or have completed the food.
  Compounds directly with §2.1.4 (payment_status never re-checked before "Mark Completed").
- Probability at scale: a common few-second race, not exotic — **expect dozens-to-low-hundreds of
  occurrences per day** at 1M-user order volume.
- Severity: Critical (silent financial loss + food given away for a refunded order).

**2.3.2 — `accept-truck-transfer` double-invocation can silently downgrade the inherited owner's
paid subscription back to `trialing`.**
- Evidence: `supabase/functions/accept-truck-transfer/index.ts:33-37` fetches the transfer via
  `.eq('status','pending').single()` — a check-then-act read with no row lock — and only marks
  `status: 'accepted'` at the very end (`:108-111`), after 5 other non-transactional writes
  (`food_trucks.owner_id`, two `profiles.role` updates, and the subscription move/upsert at
  `:90-105`). The subscription logic specifically:
  ```ts
  const { data: oldSub } = await supabaseAdmin.from('subscriptions')
    .select('id').eq('owner_id', from_owner_id).maybeSingle();
  if (oldSub) {
    await supabaseAdmin.from('subscriptions').update({ owner_id: user.id }).eq('owner_id', from_owner_id);
  } else {
    await supabaseAdmin.from('subscriptions')
      .upsert({ owner_id: user.id, status: 'trialing' }, { onConflict: 'owner_id' });
  }
  ```
  The client caller, `lib/features/account/screens/account_screen.dart:235-269`
  (`_acceptTransfer`), has **no in-flight guard** — no `_accepting` boolean, no button-disable state —
  on the confirmation dialog's "Accept" button.
- Trigger: recipient double-taps "Accept" (no debounce/disable exists), or a network retry re-fires
  the same `functions.invoke('accept-truck-transfer')` call.
- What happens: both invocations pass the initial pending-check before either commits the final
  status update. The first to run the `UPDATE subscriptions ... WHERE owner_id = from_owner_id`
  moves the (possibly `active`, paid) subscription to the new owner. The second invocation's own
  `SELECT ... WHERE owner_id = from_owner_id` now returns null (already moved), so it takes the
  `else` branch and `upsert`s `{owner_id: user.id, status: 'trialing'}` — since a subscriptions row
  already exists with `owner_id = user.id` (the one just moved), the `onConflict: 'owner_id'` clause
  causes this to silently overwrite that row's status from `active` back to `trialing`.
- Result: the new owner inherits a truck whose subscription silently reads `trialing` instead of the
  paid `active` status it should have kept — invisible unless someone compares against what the old
  owner reported.
- Probability at scale: truck transfer is a rare feature overall, but among transfers that do occur,
  double-invocation is a routine double-tap scenario with no guard against it — expect this for a
  handful of users per month at real transfer volume, discovered only via support escalation.
- Severity: Medium-High.

**2.3.3 — Menu-item availability toggle and both "orders accepting" toggles fire with no in-flight
guard, and their errors are fully silent.**
- Evidence: `lib/features/owner_dashboard/screens/manage_menu_screen.dart:98-102`:
  ```dart
  onToggleAvailable: (val) {
    ref.read(foodTruckRepositoryProvider)
        .updateMenuItem(item.id, {'is_available': val})
        .then((_) => ref.read(ownerTruckProvider.notifier).refresh());
  },
  ```
  No `_saving`/debounce state (unlike the sibling `_MenuItemSheet`, which does have one), and no
  `.catchError` — a failed PATCH is completely silent. The identical missing-guard pattern recurs for
  the "accepting online orders" toggle at `dashboard_screen.dart:645-648` and
  `employee_dashboard_screen.dart:629-634` (a distinct field, `orders_accepting`, from the
  already-known go-live-toggle race).
- Trigger: an owner double-tapping/fat-fingering a Switch — completely ordinary touchscreen behavior,
  no coincidence required.
- What happens: N independent PATCH calls fire; HTTP responses can resolve out of order, so the final
  displayed state can settle on an earlier toggle's outcome rather than the owner's actual last
  intent, and any failure is silently swallowed — the switch just reverts on the next `refresh()`
  with zero explanation.
- Probability at scale: **routine — happens many times per hour across the fleet** at 1M-user scale,
  no rare coincidence needed.
- Severity: Medium (wrong-but-recoverable state, silent failure, real revenue impact if "accepting
  orders" ends up flipped the wrong way during a rush).

**2.3.4 — Duplicate employee invites are possible with no DB-level dedup, and a later bulk "claim"
update activates all duplicates simultaneously.**
- Evidence: direct DB inspection confirms `truck_employees` has **no** unique constraint beyond the
  primary key — only `truck_employees_pkey PRIMARY KEY (id)` and a status CHECK; there is no
  `(truck_id, invited_email)` uniqueness. `lib/features/employees/screens/employees_screen.dart:
  199-222`'s "Add Employee" button has no `_submitting` guard. `EmployeesRepository.
  claimPendingInvites` (`employees_repository.dart:46-56`) does an unconditional bulk
  `.eq('invited_email', email).eq('status','pending')` update with no `.limit(1)`.
- Trigger: a rapid double-tap on "Add Employee" for the same email (or an owner re-inviting someone
  who says "I didn't get the email," a realistic real-world action), each independently passing
  whatever "not already invited" check exists before either insert commits.
- What happens: two separate `truck_employees` rows are created for the same email. When that person
  signs up, `claimPendingInvites`'s unconditional bulk update flips **both** to `active`
  simultaneously — one person now has two live `truck_employees.id`s on one truck. Since
  `employee_shifts.employee_id`/`scheduled_shifts.employee_id` key off this id, that employee's
  clock-in/out history and assigned shifts can be scattered across two IDs, corrupting hours totals
  and producing a duplicate entry in the employee list.
- Probability at scale: plausible several times a day at 1M-user scale, given how often owners
  re-send invites for people who report a missing email.
- Severity: Medium (payroll/data-integrity corruption, not a crash).

**2.3.5 — Systemic "no request sequencing" pattern: at least 5 `AsyncNotifier.load()/refresh()`
call sites can silently apply a stale, out-of-order response over newer state. (Executive Summary
#7.)**
- Evidence: `OwnerTruckNotifier.refresh()` (`food_truck_provider.dart:103-113`),
  `OwnerOrdersNotifier.load()` (`orders_provider.dart:17-22`), `MyOrdersNotifier.load()`
  (`orders_provider.dart:44-49`), `OwnerBookingRequestsNotifier.load()`
  (`bookings_provider.dart:76-82`) — each does the identical shape:
  `state = AsyncLoading(); state = await AsyncValue.guard(() => freshFetch());` with **no
  generation/cancellation token**. Each is triggered concurrently from multiple independent sources:
  realtime `postgres_changes` callbacks (firing per DB event, e.g. `order_queue_screen.dart:
  66-68,80,95,107,116`), `didChangeAppLifecycleState.resumed`, and pull-to-refresh.
- Trigger: two overlapping triggers for the same provider within a short window — e.g. a realtime
  event from an order just accepted, plus an app-resume-triggered load fired a moment earlier but
  network-delayed. A realistic burst: any truck getting more than one order in the same few-hundred
  milliseconds (an ordinary lunch-rush pattern).
- What happens: whichever HTTP response lands **last** wins, even if it was requested first and
  reflects an older DB snapshot — the owner's Order Queue or Booking Requests screen can transiently
  and silently revert to a stale list (e.g. showing an already-accepted order back as "pending," or
  dropping a just-arrived order from view until the next event happens to trigger a corrective load).
- Probability at scale: **routine, not rare** — any truck with more than one concurrent order/booking
  event triggers overlapping loads; at thousands-of-trucks scale this is a constant background
  occurrence, not an edge case.
- Severity: High (broad, systemic, directly damages trust in "is my order queue accurate right now").

**2.3.6 — `setOpenStatus` optimistic update can be clobbered by its own realtime echo racing a
concurrent writer (owner + employee both with truck-status write access).**
- Evidence: `OwnerTruckNotifier.setOpenStatus` (`food_truck_provider.dart:115-132`) sets optimistic
  local state, then awaits the network write; the truck's own `truckChannel`
  (`food_truck_provider.dart:66-79`) fires `refresh()` on **any** `UPDATE` to that row — including
  the echo of this very write, and including any concurrent writer's update. `EmployeeGoLiveNotifier.
  setOpenStatus` (`employees_provider.dart:115-132`) has the identical optimistic-then-write shape
  and writes the same columns (`is_open`, `session_started_at`, `opened_by_user_id`).
- Trigger: an owner and an employee with write access to the same truck act on the go-live/close
  toggle within roughly the same network-round-trip window (~200-500ms) — plausible for any truck
  with active employee accounts, not a contrived coincidence.
- What happens: combined with §2.3.5's out-of-order `refresh()` bug, the final `is_open`/
  `opened_by_user_id` state can match **neither** party's last action, and each device may keep
  showing its own stale optimistic belief (e.g. owner's screen still says "You're Open" while the
  truck is actually closed) until a subsequent event happens to trigger a corrective refresh.
- Probability at scale: plausible multiple times a day for trucks with active employee accounts.
- Severity: Medium-High.

**2.3.7 — Booking accept/decline is a blind update with no status-guard — a real two-device lost
update.**
- Evidence: `bookings_repository.dart:105-116` (`updateRequestStatus`):
  ```dart
  final updates = {'status': status};
  await _supabase.from('event_booking_requests').update(updates).eq('id', requestId);
  ```
  No `.eq('status', 'pending')` guard, no read-back of current status first. The UI's `_updating`
  bool (`booking_requests_screen.dart:641-664`) only guards the local sheet instance — nothing
  prevents two live sessions of the same owner (phone + tablet/browser, which the app's UI explicitly
  allows since the same request is reachable from Dashboard, Booking Requests, or a push-notification
  deep link) from independently calling Accept on one device and Decline on the other. The
  `updated_at` column exists (via `set_updated_at` trigger) but is never read back/compared by any
  app code before writing — it provides no actual optimistic-locking protection today.
- Trigger: the identical pending request is open in two live owner sessions simultaneously —
  plausible for owners who work from both a phone and a tablet/desktop.
- What happens: whichever write reaches Postgres last silently wins with no conflict surfaced to
  either device; the "losing" device already showed a local success (sheet closed, no error).
- Probability at scale: rarer than §2.3.5/§2.3.6 — needs the identical record open in two sessions —
  but an occasional-and-real occurrence at 1M-user scale, not a contrived multi-step coincidence.
- Severity: Medium.

**2.3.8 — `expirePendingBookings` (client-triggered, no server cron) can race a concurrent Accept
action on the same row.**
- Evidence: `bookings_repository.dart:13-21` runs a blind `UPDATE ... WHERE status='pending' AND
  event_date < today` on every mount of the Booking Requests screen (`booking_requests_screen.dart:
  134`) — no interaction lock with a concurrent `updateRequestStatus('accepted')` call for the same
  row. See also §2.10.1 for the deeper timezone bug in how "today" is computed here.
- Trigger: two owner sessions open across a midnight rollover, one accepting a request the other's
  screen-open triggers an expire-sweep against.
- What happens: a request could be expired by one session while being accepted in another, landing
  in an inconsistent final state depending on write order.
- Probability at scale: low on its own, but compounds §2.3.7 and is a real contributing factor to
  overall booking-status unreliability.
- Severity: Low-Medium.

**2.3.9 — Booking chat has no reconnect/backfill mechanism — a dropped connection permanently and
silently drops messages until the thread is manually reopened.**
- Evidence: `booking_chat_screen.dart` fetches full history exactly once in `initState`
  (`_load()`); all subsequent updates rely solely on the `booking-chat-<id>` realtime channel's
  `insert` event. Unlike every other realtime consumer in the app (`order_queue_screen.dart`,
  `my_orders_screen.dart`, `employee_dashboard_screen.dart`, `booking_requests_screen.dart` — all of
  which mix in `WidgetsBindingObserver`/`didChangeAppLifecycleState` to force a fresh fetch on
  app-resume), `_BookingChatScreenState` does **not** implement `WidgetsBindingObserver` at all, and
  `.subscribe()` has no status callback to detect a drop/reconnect and trigger a catch-up fetch.
  Supabase Realtime's WebSocket auto-reconnects the connection but does not replay missed Postgres
  change events — there is no cursor/backfill.
- Trigger: an ordinary, brief connectivity drop (elevator, subway, weak signal) while a chat thread is
  open in the background — a daily-or-more occurrence per active user at 1M-user scale.
- What happens: any message sent by the other party during the gap is **permanently invisible** to
  the affected user until they manually leave and re-enter that exact chat thread. Since booking chat
  coordinates event logistics/deposits/estimates, a missed message can mean a missed deadline or
  no-show.
- Probability at scale: routine — requires nothing more than an ordinary brief connectivity drop
  while a chat is open, a daily occurrence at this scale.
- Severity: High (silent, permanent data loss on a trust-critical channel).

**2.3.10 — Duplicate concurrent clock-in creates a permanently open, invisible `employee_shifts`
row that silently inflates worked-hours totals.**
- Evidence: `employees_repository.dart` `clockIn()` (~lines 73-84) INSERTs unconditionally with no
  check for an existing `clocked_out_at IS NULL` row for the same `employee_id`+`truck_id`.
  `ActiveShiftNotifier.build()` (`shifts_provider.dart:17-31`) only ever surfaces the single
  most-recent open shift via `.order('clocked_in_at', ascending:false).limit(1).maybeSingle()`,
  silently ignoring any earlier duplicate open shift. The client-side `_clockingIn` guard
  (`employee_dashboard_screen.dart:55,104`) is local widget state that does not protect against a
  second device.
- Trigger: an employee logged into the same account on two devices (personal phone + a truck's
  shared tablet is a realistic, common pattern) both open to the clock-in screen, or clock in within
  a slow-network window on each.
- What happens: two open shift rows are created; the UI only ever shows/manages the newest one. The
  employee eventually clocks out of the visible one; the older duplicate row is **never closed** (no
  DB constraint prevents multiple open shifts, no cleanup job exists) — its `clocked_out_at` stays
  NULL forever, silently distorting any hours-worked aggregation that includes it.
- Probability at scale: multi-device employee accounts are a common real-world pattern — expect this
  routinely, dozens-to-hundreds of times per week across a userbase with meaningfully many
  truck-employee accounts.
- Severity: Medium (payroll-adjacent data-integrity corruption, silent, no crash).

---

### 2.4 Broken Forms

**2.4.1 — Free-text fields feeding unbounded-length DB columns have essentially no client-side
length cap app-wide.**
- Evidence: `grep -rn "maxLength" lib` returns only 6 hits in the entire app. Confirmed-uncapped
  fields feeding real name/description columns include: `edit_truck_screen.dart:271-276` (Truck
  Name), `:304-308` (Description), `:327-342` (all 5 social-handle fields, no validator at all),
  `manage_menu_screen.dart:474-479` (item Name), `:481-485` (item Description), `:528-535` (custom
  Category name), `account_screen.dart:947-953` (`_ChangeNameDialog` display name), `:1389-1398`
  (`_UpgradeToOwnerSheet` business name — not even wired to the Form's own validator), `send_
  estimate_sheet.dart:75-82`/`request_deposit_sheet.dart:94-101` (booking notes), `order_cart_
  sheet.dart:139-147` (pickup note), `write_review_sheet.dart:131-155` (review comment), and
  `book_truck_sheet.dart`'s manual-booking notes fields (lines 253, 764).
- Concrete layout-break confirmation: the app is internally inconsistent about guarding *render* of
  these same fields — `truck_profile_screen.dart:1010-1013` (customer-facing menu item name)
  applies `maxLines: 2, overflow: TextOverflow.ellipsis`, but the identical field in the owner's own
  menu manager (`manage_menu_screen.dart:244`, `Text(item.name, style: AppTextStyles.label)`) has no
  such guard, nor does the map's search-results row (`map_screen.dart:872`).
- Probability at scale: **high** — this is not abuse-dependent; an owner pasting a long product
  description or a review author writing a long comment breaks these two unguarded render sites
  organically, and because the data is stored (not just submitted once), every subsequent viewer of
  that truck sees the broken layout, forever, until someone edits it back down.
- Severity: Medium (visual breakage, not a crash, but a stored/replicated defect).

**2.4.2 — Menu item price of exactly $0.00 is silently accepted with no lower-bound-above-zero
check.**
- Evidence: `manage_menu_screen.dart:497-501`:
  ```dart
  validator: (v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    if (double.tryParse(v.trim()) == null) return 'Invalid price';
    return null;
  },
  ```
  `double.tryParse('0.00')` returns `0.0`, not null — passes. The input formatter blocks a leading
  `-` (no negative prices) but zero is fully valid.
- Trigger: an owner leaving the price field at a placeholder "0" and not noticing, or intentionally
  listing a free item.
- What happens: a cart consisting only of $0.00 items produces `amountCents = 0` at `order_cart_
  sheet.dart:40`, which Stripe rejects — surfaced to the consumer as the generic, unmapped
  `'Error: $e'` snackbar (`order_cart_sheet.dart:82-85`) rather than a clear message.
- Probability at scale: low-medium (owner data-entry mistake), but 100% reproducible once it occurs.
- Severity: Low-Medium.

**2.4.3 — Manual-booking phone/guest-count fields have effectively no format validation.**
- Evidence: `book_truck_sheet.dart`'s `ManualBookingSheet._phoneCtrl` (lines 721-726) restricts
  character set only (`FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-\(\)\+]'))`) with **no**
  `validator:` — a bare `"+"` or a 40-digit string passes. `_emailCtrl` (lines 710-719) only checks
  `v.contains('@')` — `"a@"`/`"@x"` pass, and this address is used to email a booking confirmation
  (`bookings_repository.dart` → `_invokeConfirmationEmail`), so a malformed address silently fails
  delivery with no owner feedback. `_guestCtrl` (lines 229-235, 741-746) uses
  `FilteringTextInputFormatter.digitsOnly` with no length cap — pasting a 19+ digit string overflows
  Dart's `int.tryParse` range and silently produces `guestCount: null` instead of an "invalid" error.
- Probability at scale: low-medium (owner-only feature, deliberate/accidental long paste required for
  the overflow case), but a genuine silent-data-loss path.
- Severity: Low-Medium.

**2.4.4 — Password-change minimum length (6) is inconsistent with sign-up's minimum (8), and all
three password fields are silently `.trim()`-ed before comparison/submission.**
- Evidence: `account_screen.dart:213-218`:
  ```dart
  final current = currentCtrl.text.trim();
  final newPass = newCtrl.text.trim();
  final confirm = confirmCtrl.text.trim();
  ```
  vs. `account_screen.dart:218`'s `newPass.length < 6` check, contrasted with `register_screen.dart:
  142`/`register_owner_screen.dart:284`'s `< 8` requirement.
- What happens: any user whose actual password (old or newly chosen) contains a leading/trailing
  space has it silently stripped — the password actually set on the account is not exactly what was
  typed, with no indication given.
- Probability at scale: low (few users intentionally pad passwords with spaces), but a genuine,
  silent correctness bug not present on the register/login flows.
- Severity: Low.

**2.4.5 — Owner sign-up shows a raw, unmapped exception string despite a working friendly-error
mapper existing in the same file.**
- Evidence: `register_owner_screen.dart:71-76` calls `_showError(error.toString())` directly for the
  email/password signup path; the same class's `_friendlyError()` mapper (lines 101-110) is used only
  for the social-signup path (line 98). Every equivalent screen (`register_screen.dart:48`, `login_
  screen.dart:45`) routes through the friendly mapper.
- Probability at scale: **high** — happens on every owner email/password sign-up failure, and
  duplicate-email sign-up attempts alone (a common mistake — re-registering) trigger this for a
  nontrivial fraction of the owner-track subset of a 1M-user base.
- Severity: Medium (UX/trust, not data-integrity, but very frequent).

**2.4.6 — Operating-hours screen's back button is unguarded during the known non-atomic 7-call save
loop.**
- Evidence: `manage_hours_screen.dart:89-92`'s back `IconButton` has no `_saving` guard (contrast
  `account_screen.dart:1026`'s `_ChangePasswordDialog` close button, which correctly does `_loading ?
  null : ...`).
- What happens: a user-initiated back-tap mid-save (or the OS backgrounding/killing the app) leaves
  some days upserted and others not, with **no error at all** shown (unlike a network failure, which
  at least surfaces the `Error: $e` snackbar) — silent partial save, purely user-triggerable at will.
- Probability at scale: low-medium, but triggerable on demand, not failure-dependent.
- Severity: Low-Medium.

**2.4.7 — Zero `RestorationMixin` usage anywhere — any long form loses all typed content if the OS
kills the app process while backgrounded.**
- Evidence: `grep -rn "RestorationMixin|RestorationScope|restorationId"` across all of `lib` returns
  zero hits.
- What happens: register_owner_screen.dart's 5-field form, edit_truck_screen.dart's ~13-field form,
  and the menu-item add sheet all lose every typed character if Android/iOS kills the process while
  backgrounded — common on low/mid-range Android devices, which will make up a meaningful fraction of
  a 1M-device install base.
- Probability at scale: medium — a real, recurring "I filled out the whole form and lost it" report
  at scale, standard Flutter behavior but conspicuously unaddressed on the app's longest forms.
- Severity: Medium.

**2.4.8 — Review comment field has no `maxLength` at all**, distinct from the owner-response field
(`truck_profile_screen.dart:1361`) which is capped — `write_review_sheet.dart:131-155`. Cross-
referenced with §2.4.1; called out separately because reviews are permanently stored and rendered on
every future viewer of that truck's profile, making this specific field's lack of a cap unusually
high-leverage.

---

### 2.5 Unexpected States

**2.5.1 — An owner account with zero trucks (a plausible outcome of the already-known non-atomic
4-step signup) hits a permanent, unrecoverable dead-end across at least 6 screens.**
- Evidence: `OwnerTruckNotifier.build()` (`food_truck_provider.dart:57`) correctly handles the
  empty-trucks case (`trucks.isEmpty ? null : trucks.first`, never crashes on `.first`), and every
  consuming screen null-checks gracefully: `dashboard_screen.dart:94-96` ("No truck found."),
  `manage_menu_screen.dart:48`, `booking_requests_screen.dart:110`, `order_queue_screen.dart:42`,
  `employees_screen.dart:32` all show the identical bare `"No truck found."` text with **no
  create-truck CTA anywhere** — confirmed via a repo-wide grep for any "create truck"/"add truck"
  flow reachable outside the initial `signUpOwner()` sequence: none exists.
- Trigger: the already-documented non-transactional 4-step owner signup (`auth.signUp` → `profiles`
  upsert → `food_trucks` insert → `subscriptions` insert, `auth_repository.dart:46-88`) fails between
  the profile-creation step and the truck-insert step (network drop, RLS hiccup, app backgrounded
  mid-signup).
- What happens: the owner has a real, logged-in account with a `profiles` row but no `food_trucks`
  row. Every single owner-facing screen they can reach shows "No truck found." with zero path
  forward — no button, no retry flow, no support-contact prompt. The only recovery is a manual
  backend fix by support staff.
- Probability at scale: bounded by how often the underlying 4-step signup partially fails (network
  drops, backgrounding during signup are common on mobile) — at 1M-user signup volume, even a 0.1-1%
  partial-failure rate on this sequence produces a steady stream of owners permanently stuck at this
  dead end, discoverable only via support contact. **This is a new, concrete consumer-facing
  consequence of the already-documented non-atomic-signup root cause**, not previously traced forward
  to this specific dead-end UI state by prior audits.
- Severity: High (100% blocked, zero self-service recovery, will generate support escalations).

**2.5.2 — Subscription lapse mid-session is never rechecked anywhere. (Executive Summary #4 — full
detail.)**
- Evidence: `subscription_provider.dart`'s `SubscriptionNotifier.build()` only re-fetches when
  `authProvider` changes; there is no realtime channel on `subscriptions` and no polling timer;
  `refresh()` is only ever called manually (post-purchase/restore, or a Retry button tap).
  `router.dart:40-73`'s `_AuthListenable` (lines 223-228) listens only to `authProvider`/
  `onboardingProvider` — never `subscriptionProvider`. `dashboard_screen.dart:166-179` only checks
  subscription status at the moment the owner taps the "Go Live" switch — if the truck is **already**
  open when RevenueCat's webhook flips the subscription to lapsed, nothing rechecks it.
  `map_repository.dart:11-19` (`fetchActiveTrucks`, the public map query) filters only on
  `is_active = true AND is_open = true` — no subscription check. Both `create-payment-intent` and
  `create-booking-payment-intent` (read in full) validate auth/truck-existence/Stripe-Connect status
  but **never call or check `owner_has_active_subscription`**.
- What happens: once a truck is opened, a lapsed/canceled/payment-failed subscription does not
  remove it from the map, does not block online orders, and does not block booking-deposit/invoice
  payments, for an unbounded amount of time — until the owner happens to manually toggle
  closed/open, or some unrelated event invalidates the provider.
- Probability at scale: **certain and continuous** — at normal card-decline/subscription-churn rates
  across a 1M-user owner base, this is not an edge case but a standing, silent revenue-leak/
  policy-bypass window that exists by design gap, not by rare coincidence.
- Severity: High.

**2.5.3 — A menu item deleted by the owner mid-session while already in a consumer's cart leaves a
placed order referencing a deleted `menu_item_id`.**
- Evidence: `CartItem` stores `name`/`price` denormalized at add-time (`truck_profile_screen.dart:
  1067-1071`); both `truck_profile_screen.dart` and the owner's menu screen listen for `menu_items`
  realtime changes and refresh their own provider state, but `cartProvider` (`orders_provider.dart:
  72-109`) is never invalidated by that event. `order_cart_sheet.dart`'s `_pay()` still calls
  `OrdersRepository.placeOrder()`, which inserts `order_items` referencing the now-nonexistent
  `menu_item_id` (`orders_repository.dart:56-68`) with no re-validation against current menu state.
- Trigger: an owner removes/86's a menu item (realistic during a rush — "we're out of X") while a
  consumer already has that item in their cart from a few minutes earlier.
- What happens: order placement succeeds silently; the order references a deleted menu item — a
  quiet data-integrity gap (not a crash) that could confuse any future reporting/analytics keyed off
  `order_items.menu_item_id`.
- Probability at scale: occasional but real at 1M-user order volume with active menu-availability
  toggling during rushes.
- Severity: Low-Medium.

**2.5.4 — Confirmed clean (no bug, stated for completeness):** empty-menu checkout does not crash
(the "Add" affordance simply never renders for a zero-menu truck, both `truck_profile_screen.dart:
353,363` and `order_cart_sheet.dart:35,162`'s gates prevent reaching checkout at all); zero-order/
zero-booking history screens (`my_orders_screen.dart:91-104`, `my_requests_screen.dart:116-129`) show
dedicated empty states before touching any list-head operation; a deactivated or deleted truck
referenced by an existing order/booking renders safely via nullable joined-model fields
(`Order.fromMap`'s `truckMap?['name']`, consumed as `order.truckName ?? 'Business'` throughout
`my_orders_screen.dart`/`my_requests_screen.dart`).

---

### 2.6 Navigation Failures

**2.6.1 — Back-navigation / sheet-dismissal during an in-flight payment can leave a duplicate,
un-deduplicated payment path open. (Executive Summary contributing detail to #3.)**
- Evidence: `truck_profile_screen.dart:1195-1200` opens `OrderCartSheet` via `showModalBottomSheet`
  with no `isDismissible: false`/`enableDrag: false`/`PopScope` guard; the `_paying` re-entrancy flag
  (`order_cart_sheet.dart:24,37,162`) is local widget state only, and `cartNotifier.clear()` (line 68)
  fires only after `placeOrder` succeeds.
- Trigger: user taps Pay; while `createPaymentIntent`/the Stripe PaymentSheet is still resolving, the
  user presses Android back, dismissing the sheet under the still-pending call (guarded only by
  `mounted` checks, so no crash, but the in-flight call isn't cancelled). The cart (shared Riverpod
  state) still holds the same items since `clear()` hasn't run. Reopening the truck profile and
  tapping "View Bag" creates a **brand-new** sheet instance with `_paying = false` and the same
  unclaimed items — tapping Pay again invokes `createPaymentIntent` a second time
  (`orders_repository.dart:17-31`), with **no `Idempotency-Key` header** on the underlying
  `stripePost` call and no dedup against the still-in-flight first attempt.
- The identical pattern, more easily reachable, exists in `my_requests_screen.dart:648-684`
  (`_ConsumerFinancialSectionState._pay`): a **local**, non-persisted `_depositJustPaid`/
  `_invoiceJustPaid` optimistic flag (lines 665-672) is used while waiting for the Stripe webhook to
  flip `booking_deposits.status`/`booking_quotes.status` server-side. If the widget rebuilds before
  the webhook lands (a realtime list refresh, or backgrounding/returning), a fresh state instance is
  created with the flag reset to `false`; since the DB status is still `requested`, the "Pay
  Deposit"/"Pay Invoice" button **reappears**, letting the user tap it again and call
  `createBookingPaymentIntent` a second time with the same lack of idempotency protection.
- What happens: two independent Stripe charges are possible for one cart/deposit/invoice.
- Probability at scale: Stripe webhook delivery is typically sub-second but can lag under load or
  retries; any user who backs out/returns or triggers a realtime refresh in that window is exposed.
  At 1M-user transaction volume, a low-single-digit-percent-of-transactions exposure rate translates
  to a meaningful volume of double-charge support/refund tickets.
- Severity: High (financial, compounds with §2.2.2/§1 Executive Summary #3).

**2.6.2 — No global 401/session-invalidation interceptor — a mid-screen session revocation surfaces
as a raw, unfriendly exception rather than a clean re-login prompt.**
- Evidence: `app_shell.dart:45-53` does correctly force `router.go('/map')` when the auth stream
  itself transitions authenticated → null, but a grep for `401`/interceptor patterns across `lib/`
  finds nothing — any individual repository call that races an out-of-band session revocation (a
  password changed elsewhere, an admin-revoked session) surfaces as a raw `PostgrestException`/
  `AuthException` caught by that screen's local, generic catch block
  (`ScaffoldMessenger...Text('Error: $e')`) rather than a "please log in again" message, until the
  auth stream itself catches up (which can lag the failed call by a few seconds).
- Probability at scale: low-frequency per user, but a routine occurrence in aggregate across 1M
  sessions (password changes, device revocations, token expiry edge cases all happen daily at scale).
- Severity: Low (confusing UX, not a crash or data-loss risk).

**2.6.3 — Confirmed clean (no bug, stated for completeness):** a full re-grep of every
`showDialog`/`showModalBottomSheet` call site across all 19 files that contain them found every
inline dialog correctly uses its own builder-scoped context for `Navigator.pop` — no new instance of
the previously-fixed dialogContext-vs-outer-context bug pattern exists beyond the already-confirmed-
clean `transfer_truck_sheet.dart:79`. Push-notification deep links never target a per-ID detail
screen (`push_notification_service.dart:162-220` only routes to generic list/queue screens), so a
deleted target booking/order cannot produce a null-fetch crash — it simply doesn't appear in the
resulting list.

---

### 2.7 Validation Issues (Data-Integrity Angle)

**2.7.1 — Ordinary search punctuation breaks truck search for every user. (Executive Summary #5.)**
- Evidence: `map_repository.dart:57-67`:
  ```dart
  Future<List<FoodTruck>> searchTrucks(String query) async {
    final q = query.trim();
    ...
    .or('name.ilike.%$q%,cuisine_type.ilike.%$q%')
    .limit(10);
  ```
  The raw user-typed search string is spliced directly into a PostgREST `.or()` filter expression
  with no escaping. PostgREST's filter syntax treats top-level commas and parentheses as structural
  separators/grouping tokens.
- Trigger: any search containing a comma or parenthesis — e.g. "mac, cheese", "bbq (smoked)", or a
  cuisine name copy-pasted with punctuation. Not an adversarial input; entirely ordinary text.
- What happens: the malformed filter expression either throws a 400 (surfaced as a generic
  `AsyncError` in `truckSearchProvider`, `map_provider.dart:47-50`, shown as an unstyled error where
  the user expects results) or silently misparses into an unintended clause, returning wrong results.
  This is not a SQL-injection/security issue (PostgREST filters are structurally constrained), purely
  a data-integrity/correctness bug.
- Probability at scale: **high — the single most commonly-triggered bug in this entire audit**,
  since it fires on ordinary natural-language search text, not edge-case input.
- Severity: High (core-feature breakage at very high frequency).

**2.7.2 — Owner "manual booking" entry allows a same-day, already-past-time booking with no
time-of-day check anywhere, unlike the consumer-facing booking form.**
- Evidence: `book_truck_sheet.dart` `_BookTruckSheetState._submit()` (lines 108-130) enforces
  `minDate = today + 7 days` both via the date-picker's `firstDate` and a second explicit check. The
  owner-facing `ManualBookingSheet._pickSchedule()` (lines 531-541) calls `_SchedulePickerSheet`
  **without** passing `minDate`, so it defaults to `widget.minDate ?? DateTime.now()` — today is
  selectable, and there is no time-of-day comparison anywhere.
- What happens: an owner can pick today's date plus a start time already in the past (it's 3pm, they
  pick 9am) and `createManualBooking` (`bookings_repository.dart:66-103`) inserts it with `status:
  'accepted'` — no client check, and (per prior-audit context) no DB CHECK constraint either.
- Probability at scale: low-medium (owner-only feature, typically used to log a past event after the
  fact — arguably intentional use, but the field has no framing that distinguishes "logging a past
  event" from "scheduling a future one").
- Severity: Low-Medium.

**2.7.3 — Operating hours have no open<close validation anywhere — an owner can set a close time
before the open time.**
- Evidence: `manage_hours_screen.dart` — read in full; `_pickTime` (lines 147-155) simply formats
  whatever `TimeOfDay` the native picker returns; `_save()` (lines 36-71) pushes `openTime`/
  `closeTime` straight to `repo.upsertOperatingHours` with no comparison between the two.
- What happens: an owner can set Monday open=17:00, close=09:00 and save successfully. Any downstream
  "is truck open right now" logic that assumes `open <= close` for that day will misbehave (either
  never-open or always-open, depending on implementation) for that day.
- Probability at scale: medium — an owner mis-tapping the AM/PM chip semantics on the time picker is
  a realistic, recurring mistake at scale, reachable through ordinary UI interaction, not a raw-API
  edge case.
- Severity: Medium.

**2.7.4 — The consumer-side booking 7-day minimum-lead-time rule is enforced client-side only, with
no DB backstop.**
- Evidence: `book_truck_sheet.dart:86,122` computes and checks `minDate` entirely in Dart; a grep of
  the schema's CHECK constraints (per the prior Supabase audit's enumeration) finds no constraint on
  `event_date` relative to `created_at`/`now()`.
- What happens: a direct API call (bypassing the app) can insert an `event_booking_requests` row for
  a date in the past or same-day, with no client validation in the way.
- Probability at scale: low (requires bypassing the app UI entirely — not reachable through normal
  use), included for completeness as a defense-in-depth gap, not an organically-triggered bug.
- Severity: Low.

---

### 2.8 Concurrency Issues

**2.8.1 — `push_tokens`' composite key `(user_id, platform)` allows only one registered device per
platform per user — multi-device push notifications silently break.**
- Evidence: `push_tokens`' schema (per direct inspection) has a composite primary key
  `(user_id, platform)`. `push_notification_service.dart:222-240` (`_storeToken`):
  ```dart
  await Supabase.instance.client.from('push_tokens').upsert(
    {'user_id': user.id, 'platform': platform, 'token': token, 'updated_at': ...},
    onConflict: 'user_id,platform',
  );
  ```
- Trigger: any user who uses the app on two devices of the same OS — an iPhone + iPad, or an old
  phone still logged in after upgrading to a new one without logging out first. A common, entirely
  non-adversarial real-world scenario.
- What happens: whichever device most recently opened the app upserts over the other device's stored
  FCM/APNs token for that platform. All subsequent push notifications (order accepted, booking
  response, shift assigned, chat message, the "still open?" reminder) are delivered **only** to the
  most-recently-registered device — the other device silently receives nothing, with zero indication
  of the problem on either device.
- Probability at scale: not a rare coincidence — a routine, daily occurrence for any user owning two
  same-OS devices, or anyone who upgrades phones without deleting the app from the old one first.
  Multi-device ownership overlap of this kind is common enough (easily 10-20% of users own 2 devices
  of the same OS, or fail to log out of an old device before upgrading) that this will produce a
  steady stream of "I stopped getting notifications" complaints at 1M-user scale, most of which will
  never be traced back to this root cause by support staff.
- Severity: Medium (silent notification loss, real business impact for truck owners missing "new
  order"/"shift assigned" alerts, but no data loss or crash).

**2.8.2 — See §2.3.6 (owner/employee concurrent go-live-toggle clobber) and §2.3.10 (duplicate
concurrent clock-in) — both are concurrency bugs specifically arising from two legitimate actors with
simultaneous write access to the same truck's state, cross-referenced here rather than repeated.**

**2.8.3 — Corrected premise, stated for completeness: `check-open-businesses` does not write
`is_open`.** Direct inspection of the deployed function source (not just its name/schedule) confirms
it only sends a "did you forget to close up?" push reminder and stamps a single, unrelated
notification-throttle timestamp column (`last_open_check_notified_at`) via a partial update — it
cannot clobber a concurrent owner toggle of `is_open` the way its name might suggest. The
pg-cron-vs-manual-toggle lost-update scenario hypothesized as a risk does **not** materialize for
this specific job as actually implemented; flagged here so effort isn't misspent chasing it in a
future pass.

---

### 2.9 Offline Behavior

**2.9.1 — Offline "close truck" toggle can throw an unhandled exception, leaving a false-positive
"Closed" UI state while the truck stays open server-side.**
- Evidence: `OwnerTruckNotifier.setOpenStatus` (`food_truck_provider.dart:115-132`) sets optimistic
  local state (switch flips immediately) **before** awaiting the network call, with a catch-and-
  rollback only inside the notifier method itself. But the specific caller wired to the "close" path,
  `dashboard_screen.dart`'s closing-branch handler (`_handleToggle`'s `isFixed` closing branch,
  ~lines 153-162), calls `setOpenStatus(false)` with **no surrounding try/catch at all** — unlike the
  `isFixed` opening branch (lines 183-208), which does catch and show a SnackBar.
- Trigger: an owner ending their shift while offline or on a degraded connection (a realistic
  end-of-rush scenario — parking lot, weak signal).
- What happens: the Switch optimistically flips to "Closed" immediately (per the provider's
  optimistic-update pattern); the unhandled exception from the failed network call propagates up
  through the widget callback uncaught (logged as an uncaught async error in debug, silently dropped
  in release) — the local state never rolls back because the surrounding catch that would trigger the
  rollback doesn't exist on this call path. The owner sees "Closed," walks away, and the truck remains
  `is_open = true` server-side and visible to customers on the live map (`fetchActiveTrucks()`)
  indefinitely, until the owner happens to reopen the app and notice the switch doesn't match reality.
- Probability at scale: given zero configured network timeouts anywhere (prior-audit finding) and
  outdoor/mobile usage being inherent to this app's use case, this is a realistic, non-rare occurrence
  — expect this multiple times per week at minimum across a 1M-user owner base with any meaningful
  fraction operating in weak-signal conditions (a defining characteristic of food-truck locations).
- Severity: High (false-positive success state on a core "did my truck actually close" action, with
  real customer-facing consequences — customers may travel to a truck the owner believes is closed).

**2.9.2 — Sending a chat message while offline fails completely silently, with the message
permanently and irrecoverably lost. (Distinct from, and worse than, the already-known
input-cleared-before-send-confirms bug.)**
- Evidence: `booking_chat_screen.dart:110-132`:
  ```dart
  _textController.clear();          // input wiped immediately
  try {
    await _repo.sendMessage(...);   // no timeout configured
  } catch (e) {
    debugPrint('send message failed: $e');   // entirely silent to the user
  } finally {
    if (mounted) setState(() => _sending = false);
  }
  ```
- What happens offline, traced end-to-end: text vanishes from the input immediately, the send button
  shows a spinner for the full duration of the (untimed) failed network call, then reverts to the
  send icon with **zero** indication of failure — no SnackBar, no retry affordance, no failed-message
  placeholder in the thread (messages only ever appear via the realtime echo of a successful insert
  or the initial load). The message is permanently lost with no trace anywhere, and the user has
  every reason to believe it sent.
- Probability at scale: requires nothing more than an ordinary brief connectivity drop while
  composing a message — a routine, daily-or-more occurrence per active user at this scale.
- Severity: High (silent, permanent, trust-critical data loss — this is the offline-specific,
  end-to-end elaboration of the already-known "clears input early" bug, showing the complete failure
  mode rather than just the premature-clear symptom).

**2.9.3 — Submitting a booking request offline can silently omit the owner-notification side effect
while the request itself still succeeds.**
- Evidence: `bookings_repository.dart`'s `submitRequest` (lines 124-163) has no top-level try/catch
  of its own around the insert; the fire-and-forget `_invokeNotification` helper (lines 302-313)
  wraps its own call in try/catch → `debugPrint` only.
- What happens: if the network fails specifically on the notification call (but the initial insert
  already succeeded), the booking request row is created successfully but the owner is never pinged
  — fully silent, visible only in a debug console no one is watching in production.
- Probability at scale: a routine occurrence any time the notification call specifically hits a
  transient failure independent of the main insert — given zero timeouts and zero retry logic
  anywhere in the app, this is not rare at 1M-user submission volume.
- Severity: Medium (the booking itself isn't lost, but the owner's awareness of it can be, delaying
  response time on time-sensitive event requests).

**2.9.4 — Placing an order offline fails visibly but with a raw, unfriendly error — not silent, but
not helpful either; cross-referenced against §1 Executive Summary #3 for the more severe stranded-
charge variant of this same flow.** `order_cart_sheet.dart:32-89`'s `_pay()` catches every failure
generically and shows `SnackBar('Error: $e')` — e.g. a raw `SocketException`/`ClientException`
string rather than a friendly "you appear to be offline" message. `_paying` resets via `finally`, so
there's no stuck-forever spinner for the pure-offline (pre-Stripe-charge) case specifically — but see
§2.2.2/§1 Executive Summary #3 for what happens when the failure occurs *after* the charge succeeds.

---

### 2.10 Edge Cases at 1M-User Scale

**2.10.1 — Timezone inconsistency: at least two write paths omit `.toUtc()` where the rest of the
codebase's convention requires it, producing multi-hour silent timestamp errors; a third comparison
uses device-local "today" against a business's date with no timezone concept at all.**
- Evidence: of 63 `DateTime.now()` call sites codebase-wide, only 12 use `.toUtc()` before writing to
  a `timestamptz` column. The employee-shift write path is mostly correct
  (`employees_repository.dart:83,95,170,195,196` all correctly call `.toUtc()`), which makes the
  exceptions concrete regressions rather than a codebase-wide absence of awareness:
  - `employees_repository.dart:52` — `'linked_at': DateTime.now().toIso8601String()` — **no
    `.toUtc()`**, breaking the pattern used two lines below at line 83. A device in
    `America/Los_Angeles` (UTC-7) claiming an employee invite at 2:00pm local writes a naive string
    Postgres interprets as UTC — stored as `14:00:00Z`, which is actually **7:00am PDT**, a silent
    7-hour error in `truck_employees.linked_at` for every employee-invite acceptance from any
    non-UTC device.
  - `announcement_prefs_provider.dart:38` — identical bug: `'updated_at': DateTime.now()
    .toIso8601String()` with no `.toUtc()`.
  - `bookings_repository.dart:14` (`expirePendingBookings`): `final today =
    DateTime.now().toIso8601String().substring(0, 10)` compares the **device's local calendar date**
    against `event_date`, with no truck-timezone awareness and no server-side cron equivalent — this
    runs client-side, triggered every time an owner opens the Booking Requests screen. An owner
    traveling in a timezone far from their truck's home timezone (e.g. checking bookings from
    `Pacific/Auckland`, UTC+12, for a truck in `America/Chicago`, UTC-5/6 — a 17-18 hour spread) has a
    local calendar date that can differ from the truck's actual business-day boundary by a full day,
    expiring pending bookings up to a day early or late depending on which device happens to open the
    screen last. The identical pattern recurs at `bookings_provider.dart:17`
    (`pendingBookingCountProvider`).
- Operating hours themselves (`openTime`/`closeTime` as bare `"HH:MM"` strings, no timezone tagging,
  set via the owner's own device clock) are **currently harmless by accident**: confirmed that no
  code path anywhere computes "is truck open now" by comparing `DateTime.now()` against these strings
  — `isOpen` is a purely manual toggle. This is a landmine, not a live bug: the first naive
  implementation of an "auto-detect open/closed from hours" feature (a near-certain future product
  ask) will be wrong for every consumer viewing a truck from outside its home timezone, and wrong
  twice a year for everyone during DST transitions, unless it's built with explicit timezone handling
  from day one.
- Probability at scale: the `linked_at`/`updated_at` bugs fire on every occurrence of their respective
  actions from a non-UTC device — effectively continuous at 1M-user scale, though low-consequence
  (these are audit-trail timestamps, not user-facing display values, today). The `expirePendingBookings`
  bug is lower-frequency (requires an owner actively traveling/operating cross-timezone) but directly
  affects real booking-availability correctness when it fires.
- Severity: Medium (today, mostly audit-trail-only consequence) to High (once/if any future feature
  computes real open/closed status from operating hours without addressing timezone properly).

**2.10.2 — Map marker clustering is O(k²) in the common case (not just pathologically), and degrades
from imperceptible to a certain multi-second freeze at concrete, reachable truck-count thresholds.**
- Evidence: `map_screen.dart:410-445`'s pipeline: `.where(_inVisibleBounds)` (O(N_total), evaluated
  against the **entire** nationwide active-trucks list, not a server-side bounding-box-prefiltered
  set, since there's no PostGIS query), then `.sort()` (O(k log k)), then
  `_applyClusterOffsets(sorted)` (`map_screen.dart:196-242`) — this last step loops each truck `i`
  against `groups.keys` (line 207), and because real-world food trucks are essentially never within
  the 5-meter dedup threshold of each other, `groups.keys` grows to include nearly every prior truck
  — making this **O(k²) in the normal case, not an edge case**. This entire pipeline reruns from
  scratch on every `mapEventStream` emission (line 72-74), which fires continuously during a drag
  gesture (~30-60 times over a 1-2 second pan/zoom), not once per gesture.
- Concrete thresholds (k = trucks visible on-screen after bounds-filtering):
  - k=50 (quiet suburb): ~2,500 comparisons, <1ms — imperceptible.
  - k=200 (a popular downtown lunch scene): ~40,000 comparisons plus 200 widget rebuilds — likely
    5-15ms on a mid-range phone, **eating most-to-all of the 16ms/60fps frame budget**.
  - k=500 (a major city or festival at lunch rush): ~250,000 comparisons — **certain visible
    jank/dropped frames on every pan/zoom gesture**, the concrete point where this stops being
    "maybe slower" and becomes "guaranteed stutter."
  - k=1,000+ (a mega-event or a metro-wide default view before zooming in): 1,000,000+ comparisons
    with dictionary lookups per pair — multi-hundred-millisecond hitches, perceived as the map briefly
    freezing mid-drag.
  - k=5,000+ (plausible for the app's default zoom=14 initial view immediately after opening in a
    dense metro, before any user zoom-in): 25,000,000+ comparisons — a genuine multi-second freeze.
  Because this reruns per-frame during a drag (not once at gesture-end), the k=500 "occasional jank"
  case becomes **sustained stutter for the entire duration of the gesture**, not a single hiccup.
- Probability at scale: certain to manifest the day any single city/region crosses a few hundred
  simultaneously-active trucks — a direct, foreseeable consequence of 1M-user-scale adoption in any
  dense metro, not a hypothetical.
- Severity: High (concrete, quantified performance cliff on the app's default launch screen).

**2.10.3 — Realtime channel leak modeled concretely at scale. (Executive Summary #6 — full
detail.)**
- Evidence: of the 6 providers `truck_profile_screen.dart` watches, only `foodTruckProvider(truckId)`
  (`food_truck_provider.dart:22-37`, `AsyncNotifierProvider.family`, not `.autoDispose`) opens a
  realtime channel (`consumer-menu-$truckId`) that is never torn down since the family instance is
  never disposed. The screen's own two directly-managed channels (`truck-profile-$truckId`,
  `truck-menu-$truckId`, opened/closed in `initState`/`dispose`) are correctly bounded and do not
  leak. `consumer-menu-$truckId` and the screen's own `truck-menu-$truckId` channel are also
  functionally redundant — both subscribe to the same `menu_items` filter and both trigger a
  `foodTruckProvider` invalidation, so every menu edit currently double-fires an invalidation while
  the screen is open (a minor efficiency note, not a correctness bug).
- Concrete modeling: a consumer visiting 50 distinct truck profiles in one session leaves **50
  permanently-leaked realtime channels** for that single user, persisting until app-process death
  (not screen navigation). At 1% of 1,000,000 users concurrently active (10,000 people) each having
  opened a realistic 20 truck profiles this session, that's **10,000 × 20 = 200,000 concurrently-open
  Realtime channel subscriptions from this ONE leak path alone** — before adding the other
  non-autoDispose channel-bearing providers already documented (`pendingBookingCountProvider`,
  dashboard's 3 direct channel sites).
- Why this matters beyond the individual user: Supabase Realtime concurrency is plan-gated (commonly
  low-hundreds to low-thousands of concurrent connections per project on standard compute tiers, per
  Supabase's documented architecture), and each channel subscription is also a live logical-
  replication filter Postgres must evaluate on every `menu_items` write platform-wide — so leaked
  channels impose write-amplification cost on **every** menu edit anywhere in the system, not just a
  cost borne by the user who leaked them. 200,000 leaked channels from one source, compounded by the
  other known leak sources, would require an enterprise-tier Realtime allocation just to stay
  connected, and risks degrading Realtime service (delayed/dropped events) for **all** users, not just
  the ones responsible for the leak.
- Probability at scale: this is a direct, arithmetic consequence of the already-known non-autoDispose
  finding, newly quantified here — not a probabilistic risk but a certainty once concurrent active-
  user counts reach the low tens-of-thousands, which 1% of a 1M-user base represents.
- Severity: High (systemic infrastructure risk, not merely a per-user memory leak).

**2.10.4 — A future additive status value (following the codebase's own established migration
pattern) causes orders/bookings to silently vanish from every bucketed list view on any device still
running an older app build.**
- Evidence: Dart switch *expressions* over a `String` require (and every one in this codebase
  correctly has) a wildcard `_ =>` fallback, so **no crash** occurs on an unrecognized status value
  anywhere (verified exhaustively — `orders_repository.dart:121-126` degrades to skipping a push
  notification; `my_orders_screen.dart:153-160`/`order_status_sheet.dart:227-234` fall back to
  displaying the raw string; `order_queue_screen.dart:230-235`'s `_StatusDot` falls back to a red
  dot, semantically implying "problem" for what could be an entirely benign new status — cosmetically
  wrong but not a crash). **The real bug is in the bucketing `.where()` filters, which are closed
  allowlists with no catch-all "other" bucket:**
  - `order.dart:34-37` (`isPending`/`isActive`/`isTerminal`) and `order_queue_screen.dart:121-123`
    bucket orders into exactly `{pending}` / `{accepted, ready}` / `{completed, declined, cancelled}`
    — covering exactly today's 6 known status strings. The identical bucketing is duplicated in
    `employee_dashboard_screen.dart:553-556`.
  - `my_requests_screen.dart:132-147` and `booking_requests_screen.dart:194-208` bucket bookings into
    exactly `{pending, accepted, declined, expired, cancelled}` with no catch-all section.
- Trigger: a future backend migration adds one new order/booking status value (e.g. `'refunded'`,
  `'disputed'`, `'no_show'`) — following the exact same additive-CHECK-constraint pattern the schema
  has already used repeatedly (per the prior Supabase audit's documentation of this schema's
  conventions).
- What happens: the order/booking still exists in the underlying (already-unbounded) fetched list,
  but satisfies **none** of the three/five bucket predicates — it simply disappears from every
  visible section of the Order Queue, My Orders, Booking Requests, and My Requests screens. No error,
  no crash, just a vanished record that the owner/consumer has no way to find in the app UI.
- Probability at scale: app-version rollout across 1,000,000 devices is never instantaneous — staged
  store rollouts plus users who disable auto-update routinely leave 10-20%+ of an install base on an
  older build for weeks after any release. **The first time this schema evolution pattern is applied
  to `orders.status`/`event_booking_requests.status` (a near-certainty over a multi-year product
  lifetime, given the schema has already evolved this way for other columns), every device still on
  the pre-update binary will silently and permanently lose visibility into any record that reaches the
  new status, for as long as that device goes un-updated.** This is a guaranteed failure the first
  time it happens, not a probabilistic one.
- Severity: High (silent, guaranteed-on-trigger, affects real money/booking-tracking visibility for a
  meaningful fraction of the install base for weeks at a time).

**2.10.5 — Connection-pool exhaustion timeline modeled concretely from realistic order-volume
growth, compounding three already-known findings simultaneously.**
- Evidence/modeling: `orders_repository.dart:80-89`/`:104+` and `bookings_repository.dart:23-30`/
  `:49-56` are confirmed fully unbounded (no `.range()`/`.limit()`), filtering on the unindexed FK
  columns `orders.truck_id`/`orders.consumer_id` (per the prior Supabase audit's confirmed list of 27
  unindexed foreign keys), under RLS policies that re-evaluate `auth.uid()` per row rather than once
  per query (also per the prior audit).
- Growth model: a conservative assumption of 5% of 1,000,000 users placing ~1 order/week yields
  50,000 orders/week. Over 6 months (~26 weeks): **~1.3M rows in `orders`**, continuing to grow
  ~50k/week thereafter. `event_booking_requests`/`booking_messages` would grow more slowly (bookings
  are rarer than orders) but follow the same curve, plausibly reaching the low hundreds-of-thousands
  over the same window.
- Concrete degradation timeline: unindexed sequential scans typically become measurably slow once a
  table crosses roughly 100,000-500,000 rows — the point where it stops trivially fitting in cache
  and per-row overhead (here, compounded by per-row `auth.uid()` re-evaluation) starts dominating:
  - **~2-4 weeks in** (~100k-200k rows): RLS-scan latency starts becoming noticeable (tens to
    low-hundreds of ms) on `fetchOrdersForTruck`/`fetchOrdersForConsumer`.
  - **~3 months in** (~650k rows): squarely in the range where a query that should be a <10ms indexed
    lookup becomes a multi-hundred-ms-to-multi-second query — and because the scan cost is
    per-query-over-the-whole-table, a truck with only 5 orders pays almost the same cost as one with
    5,000.
  - **~6 months in** (~1.3M rows): comfortably past the threshold — these queries are reliably slow
    for every request, not just occasionally.
- Connection-pool mechanism: Supabase's pooler (Supavisor/PgBouncer) holds a fixed connection budget.
  Given the already-confirmed **zero request timeouts anywhere except one 10-second RevenueCat call**
  (prior-audit finding), there is no client-side circuit breaker — slow queries simply queue behind
  each other on the pooler rather than failing fast. Under realistic peak concurrency (a lunch-rush
  spike where a meaningful fraction of active users simultaneously open Order Queue/My Orders
  screens), queries that should complete in ~10ms instead holding connections for 1-3+ seconds means
  each connection is held 100-300× longer than designed — a direct path to pool saturation and
  platform-wide request queuing/timeouts, not an isolated slow-query symptom.
- Probability at scale: this is presented as a **timeline, not a maybe** — a near-certain degradation
  path by the 3-6 month mark of sustained growth at even a modest 5%-of-1M ordering rate, being the
  direct, compounding consequence of three already-documented findings (unindexed FKs, per-row RLS,
  zero pagination) landing in the same request path simultaneously with a fourth (zero timeouts)
  removing any circuit breaker.
- Severity: High (platform-wide degradation risk, not scoped to one user or truck).

---

## 3. Quantified Summary Table

| # | Category | New bugs found | Severity distribution | Highest-probability bug in category |
|---|---|---|---|---|
| 1 | Logical bugs / state machines | 4 | High×1, Medium-High×1, Medium×2 | Subscription-status fail-open default (§2.1.1) — low probability today, near-certain trigger over product lifetime |
| 2 | Crash scenarios | 3 (+1 clean confirmation) | Critical×1, High×1, Medium×1 | `searchTrucks()` null-location crash (§2.2.1) — certain within day 1 of signups |
| 3 | Race conditions | 10 | Critical×1, High×2, Medium-High×2, Medium×4, Low-Medium×1 | Out-of-order `load()`/`refresh()` pattern (§2.3.5) — routine, daily, systemic across 5+ call sites |
| 4 | Broken forms | 8 | Medium×5, Low-Medium×2, Low×1 | Unbounded free-text fields, no maxLength app-wide (§2.4.1) — high frequency, organic trigger |
| 5 | Unexpected states | 3 (+2 clean confirmations) | High×1, High×1, Low-Medium×1 | Subscription-lapse gap (§2.5.2) — certain and continuous |
| 6 | Navigation failures | 2 (+2 clean confirmations) | High×1, Low×1 | Double-payment via sheet dismissal/rebuild (§2.6.1) — low-single-digit % of transactions at scale |
| 7 | Validation issues | 4 | High×1, Medium×1, Low-Medium×1, Low×1 | Unescaped search breaks PostgREST filter (§2.7.1) — highest-frequency bug in entire audit |
| 8 | Concurrency issues | 1 new (+2 cross-refs, 1 ruled-out) | Medium×1 | `push_tokens` composite-key multi-device notification loss (§2.8.1) — routine, daily at scale |
| 9 | Offline behavior | 4 | High×2, Medium×2 | Offline chat-send silent failure (§2.9.2) — routine, daily-or-more per active user |
| 10 | Edge cases at 1M-user scale | 5 | High×4, Medium×1 | Realtime channel leak concrete modeling (§2.10.3) — certain once concurrency reaches low tens-of-thousands |

**Total: 43 new, distinct findings** (excluding cross-referenced duplicates and explicitly-labeled
clean/ruled-out confirmations), plus 8 explicitly-verified clean/non-bug confirmations worth
retaining as settled questions (empty-menu checkout, zero-truck-owner crash risk, zero-history-screen
crash risk, deleted-truck-in-order null handling, deep-link-to-deleted-entity crash risk, dialog-
stacking, status-switch exhaustiveness, check-open-businesses lost-update).

---

## 4. Prioritized Fix Lists

### Fix before launch (or as an immediate post-launch hotfix if already shipped)

1. **`searchTrucks()` null-location crash (§2.2.1)** — one-line fix (add the same
   `.not('latitude','is',null).not('longitude','is',null)` filter `fetchActiveTrucks()` already has,
   or null-guard the `_DistanceChip` call site). Trivial fix, certain-to-hit crash on the app's
   default screen.
2. **Unescaped search input breaking PostgREST `.or()` (§2.7.1)** — escape or parameterize the search
   term (e.g. via `.textSearch`/manual escaping of `,()` or switching to two separate `.ilike()`
   calls combined client-side). Highest-frequency bug in the whole audit; trivial to fix once
   identified.
3. **Consumer-cancel-vs-owner-accept race (§2.3.1)** — add `.eq('status', 'pending')` as a
   precondition on `cancelOrder()`'s update, and have the RPC/update report back whether it actually
   matched a row so the UI can show "this order was already accepted" instead of silently refunding.
4. **Stranded-charge / no-idempotency payment flows (§2.6.1, §2.2.2)** — add a Stripe
   `Idempotency-Key` derived from a stable client-side identifier (cart/booking + user), and add a
   compensating-refund or at-least-alerting path when `placeOrder()` fails after a successful charge.
   This is a direct financial/trust risk and the fix (idempotency key) is a well-understood, low-risk
   pattern.
5. **Subscription-lapse gap (§2.5.2)** — at minimum, add a subscription-status check inside
   `create-payment-intent`/`create-booking-payment-intent` (server-side, cannot be bypassed) and
   have `fetchActiveTrucks()` also filter on active subscription status so a lapsed truck disappears
   from the public map. This closes the revenue-leak/policy-bypass hole without needing the full
   client-side realtime-recheck fix immediately.
6. **`SubscriptionStatus.fromString` fail-open default (§2.1.1)** — change the default case to a new
   `SubscriptionStatus.unknown`/`expired` value that `hasAccess` treats as `false`, not `trialing`.
   One-line change, removes a systemic landmine before any future engineer or migration trips it.
7. **Owner zero-truck dead-end (§2.5.1)** — add a "Create your truck" CTA/flow reachable from the
   "No truck found." state, so a partially-failed signup is self-service-recoverable rather than
   requiring a support ticket.
8. **Offline chat-send and offline close-toggle silent failures (§2.9.1, §2.9.2)** — surface a real
   error/retry affordance instead of `debugPrint`-only catches; restore the typed text on chat-send
   failure. Directly extends the already-planned fix for the known "clears input early" bug — do them
   together.

### Monitor / fix post-launch (real but lower immediate blast-radius, or requiring larger refactors)

1. **Systemic out-of-order `load()`/`refresh()` race (§2.3.5) and its `setOpenStatus` interaction
   (§2.3.6)** — the correct fix (a generation/cancellation token per notifier, or switching to
   Riverpod's newer request-cancellation patterns) touches 5+ call sites and is a genuine refactor;
   worth scoping carefully rather than rushing, but should be scheduled soon given its "routine,
   daily" frequency.
2. **Realtime channel leak, concrete modeling (§2.10.3)** — the fix (add `.autoDispose` to the 19
   already-known family providers) is already Phase 5/8's top recommendation; this phase's
   contribution is the concrete scale-failure model justifying doing it *before* concurrent-user
   counts reach the tens-of-thousands, not after an incident.
3. **Map clustering O(k²) at scale (§2.10.2)** — the underlying per-frame-rebuild issue is already
   known (Phase 8); this phase adds the concrete truck-count thresholds (k=500 certain jank, k=5,000
   certain multi-second freeze) that should inform how urgently to prioritize the memoization fix
   relative to other backlog items — treat as urgent once any single metro approaches a few hundred
   simultaneously-active trucks, not before.
4. **Cross-version bucketing on future status values (§2.10.4)** — no immediate action needed since
   no new status value exists today, but the fix (add an "Other" catch-all bucket to every bucketed
   list screen) should be done in the *same* pull request as any future migration that adds a new
   order/booking status — flag this finding in that future PR's description so it isn't forgotten.
5. **Connection-pool exhaustion timeline (§2.10.5)** — the fix (add indexes to the 27 unindexed FKs,
   implement `.range()` pagination, wrap `auth.uid()` in `(select ...)`) is already fully documented
   by Phase 2/8; this phase's contribution is the concrete 3-6-month timeline — treat the pagination
   piece specifically as due before order volume crosses roughly 100k-200k rows (§2.10.5's ~2-4-week
   mark under the modeled growth rate), not as a someday item.
6. **`push_tokens` multi-device notification loss (§2.8.1)** — requires a schema change (drop the
   composite PK, move to a per-device-token table keyed by a device identifier) — a real fix but
   non-trivial; worth scoping once other Critical/High items are addressed, given its "silent, no
   crash, no data loss" severity profile.
7. **Duplicate employee invite (§2.3.4) and duplicate concurrent clock-in (§2.3.10)** — both need a
   DB-level uniqueness constraint (`(truck_id, invited_email) WHERE status <> 'removed'` for
   invites; a partial unique index on `(employee_id, truck_id) WHERE clocked_out_at IS NULL` for
   shifts) — small, well-scoped fixes, but not urgent enough to block launch given their
   dozens-per-week (not per-day) frequency.
8. **Broken-forms items (§2.4.1-§2.4.8) and remaining validation gaps (§2.7.2-§2.7.4)** — collect
   into the same maxLength/validation pass the prior UX/code-quality audits already recommended;
   none of these are individually launch-blocking, but the unbounded-text-field issue (§2.4.1) is the
   highest-value single fix in this group given it's a stored, replicated defect (every future viewer
   of an affected truck sees the breakage, not just the one submission).
9. **Booking accept/decline lost-update and transfer accept/cancel race (§2.3.7, §2.3.2)** — both
   need a conditional `.eq('status', 'pending')` guard on their respective updates plus a
   caller-side "someone already acted on this" error message — same shape of fix as item 3 in the
   pre-launch list, but lower frequency, so can follow shortly after.
10. **Timezone write-path fixes (§2.10.1)** — add `.toUtc()` at the two identified missing call sites
    (`employees_repository.dart:52`, `announcement_prefs_provider.dart:38`) as a quick, isolated fix;
    treat the `expirePendingBookings` device-local-date issue and the operating-hours
    timezone-tagging landmine as design work to schedule before any future "auto-detect open/closed
    from hours" feature is built, not before launch.
