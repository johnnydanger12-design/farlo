# Farlo — Supabase Backend Audit (Phase 2)

Project ref: `weflrxyerxpsafcdetya`. Read-only discovery audit conducted via `mcp__supabase__*`
(live project) and local repo inspection. All findings below are evidence-backed with exact
table/column/policy/function names and file:line references. No writes, migrations, or deploys
were performed as part of this audit.

---

## Critical Findings Summary (launch blockers)

| # | Finding | Where | Severity |
|---|---|---|---|
| 1 | `create-payment-intent` and `create-booking-payment-intent` trust a **client-supplied `amount_cents`** with no server-side recomputation from the order/quote/deposit record. A consumer can pay $0.50 for any order, or mark a real $2,000 event quote/deposit `paid` for $0.50. | `supabase/functions/create-payment-intent/index.ts`, `supabase/functions/create-booking-payment-intent/index.ts` | **Critical — payment fraud** |
| 2 | `invite_employee_by_email(p_truck_id, p_email)` is a `SECURITY DEFINER` RPC, **executable by `anon`/`authenticated` with no ownership check** on `p_truck_id`. Any signed-in user can add themselves (or anyone) as an `active` employee of **any** truck, instantly gaining `auth_user_is_employee`/`auth_user_works_for_truck`-gated access (live status updates, orders, shifts). Called directly from Flutter (`lib/features/employees/repositories/employees_repository.dart:30`). | DB function `public.invite_employee_by_email` | **Critical — privilege escalation** |
| 3 | `profiles` SELECT policy `"profiles: authenticated can read"` has `USING (true)` — **every authenticated user can read every other user's row**, including `email` and `stripe_account_id`. `profiles` is also in the `supabase_realtime` publication, so every change fans out to every connected client. | `pg_policies` (public.profiles), realtime publication | **High — PII/email/Stripe-ID exposure to entire user base** |
| 4 | Storage bucket `menu-item-photos`: INSERT and DELETE policies check **only `bucket_id = 'menu-item-photos'`** with no owner/path scoping — any authenticated user can upload to or delete photos from **any** truck's menu. | `storage.objects` policies `Authenticated users can upload/delete menu item photos` | **High — cross-tenant storage tampering** |
| 5 | `revenuecat-webhook` auth check is **fail-open**: `if (WEBHOOK_SECRET) {...}` skips signature verification entirely if `REVENUECAT_WEBHOOK_SECRET` is unset, which would let anyone POST fake subscription events to activate/deactivate any truck's paid listing. Needs confirmation the secret is actually set in prod, and the code should fail closed regardless. | `supabase/functions/revenuecat-webhook/index.ts` | **High (conditional)** |
| 6 | `send-owner-onboarding-emails` and `send-consumer-welcome-email` are public, unauthenticated (`verify_jwt: false`) POST endpoints with **no shared-secret gate and no resend/idempotency guard** — a caller who knows/guesses an `owner_id`+`subscription_id` or a consumer `user_id` can trigger repeat sends to a real inbox indefinitely, and response codes act as a user/subscription-existence oracle. | `supabase/functions/send-owner-onboarding-emails/index.ts`, `supabase/functions/send-consumer-welcome-email/index.ts` | **Medium** |
| 7 | 5 public storage buckets (`avatars`, `truck-logos`, `truck-photos`, `truck-menus`, `menu-item-photos`) allow **listing** via broad `SELECT` policies (flagged by Supabase's own linter), and 4 of the 5 have **no file-size or MIME-type limit** (`file_size_limit`/`allowed_mime_types` both `NULL`), enabling arbitrarily large/non-image uploads. | `storage.buckets` | **Medium** |
| 8 | 56 RLS policies re-evaluate `auth.uid()`/`auth.role()` per-row instead of `(select auth.uid())`, and `food_trucks`/`subscriptions` carry **duplicate, overlapping PERMISSIVE policies** (115 flagged instances) — both are Supabase-linter-confirmed performance risks that will degrade badly once tables grow past current single-digit/double-digit row counts. | `pg_policies`, Supabase performance advisor | **Medium — scale risk, not yet a launch blocker at current data volume** |
| 9 | 27 foreign-key columns have no covering index (`orders.truck_id`, `orders.consumer_id`, `order_items.order_id`, `food_trucks.owner_id`, `event_booking_requests.truck_id`, etc.) — RLS predicates and joins on these will full-scan as data grows. | `pg_indexes` vs. FK list | **Medium — scale risk** |
| 10 | `send-employee-invite` (deployed, no local source) performs **zero authorization** — any authenticated user (including a plain consumer) can send a "you've been invited to `<truckName>`" phishing-style email impersonating any truck. | Live edge function `send-employee-invite` | **Medium** |
| 11 | No `supabase/config.toml` and no `supabase/migrations/*.sql` exist locally (0 files) despite 74 migrations applied on the live project — the entire migration history exists **only** in the remote project, not in git. A lost/misconfigured Supabase project cannot be reconstructed from source control. | Repo state | **Medium — no schema source-of-truth in git** |
| 12 | `prospect-businesses` Edge Function has **no authentication at all** (confirmed — no shared bearer-secret check, unlike its 10 `agent-*` siblings). Attacker-controlled `{city, types}` body drives paid Google Places API calls and service-role writes to `sales_prospects` with no rate limit. | `supabase/functions/prospect-businesses/index.ts` | **High** |

Everything else below is Medium/Low context, performance, and design-quality material — see the
numbered sections.

---

## 1. Schema

`mcp__supabase__list_tables` (public schema, verbose) returns **29 tables**, all `uuid` PKs (one
exception: `support_tickets.ticket_number` is a supplementary `int4 GENERATED ALWAYS AS IDENTITY`
business-facing ticket number, not the PK). Row counts at audit time (all pre-launch test data,
per `HANDOFF.md`'s wipe plan): `profiles` 14, `food_trucks` 9, `subscriptions` 9,
`operating_hours` 7, `menu_items` 41, `reviews` 2, `favorites` 6, `truck_employees` 2,
`event_booking_requests` 1, `push_tokens` 1, `notification_preferences` 2, `truck_transfers` 0,
`booking_messages` 2, `notifications` 13, `orders` 0, `order_items` 0, `employee_shifts` 3,
`scheduled_shifts` 1, `booking_quotes` 0, `booking_deposits` 0, `planned_locations` 0,
`follower_notification_preferences` 3, `support_tickets` 3, `sales_prospects` 52,
`agent_directives` 10, `content_queue` 6, `supervisor_reports` 5, `agent_run_log` 693,
`agent_inbox_replies` 1.

**App-facing tables (22):** profiles, food_trucks, subscriptions, operating_hours, menu_items,
reviews, favorites, truck_employees, event_booking_requests, push_tokens,
notification_preferences, truck_transfers, booking_messages, notifications, orders, order_items,
employee_shifts, scheduled_shifts, booking_quotes, booking_deposits, planned_locations,
follower_notification_preferences.

**Backend/agent-only tables (7):** support_tickets, sales_prospects, agent_directives,
content_queue, supervisor_reports, agent_run_log, agent_inbox_replies — all locked with
`USING (false)` RLS (service-role only), never touched by the Flutter app. Not "dead" — actively
written by the agent-automation Edge Functions (confirmed by `agent_run_log` row count of 693).

**Table-usage cross-reference (Phase 1 vs. actual):** a parallel grep sweep of `lib/` found **22
distinct tables** referenced via `.from(...)` calls (all match live tables — **no broken refs, no
dead app-facing tables**). `lib/core/constants/supabase_constants.dart` (19 lines) defines only
**8** of those 22 table-name constants (`profilesTable`, `foodTrucksTable`, `operatingHoursTable`,
`menuItemsTable`, `reviewsTable`, `favoritesTable`, `subscriptionsTable`, `truckEmployeesTable`) —
**14 of 22 tables (64%) are accessed via raw string literals** bypassing the constants file
entirely: `booking_deposits`, `booking_messages`, `booking_quotes`, `employee_shifts`,
`event_booking_requests`, `follower_notification_preferences`, `notification_preferences`,
`notifications`, `order_items`, `orders`, `planned_locations`, `push_tokens`, `scheduled_shifts`,
`truck_transfers`. This confirms and sharpens Phase 1's finding — table coverage in
`SupabaseConstants` is worse than "~8 of ~19," it's 8 of 22 against the *current* schema.

**Foreign keys / relationships:** `profiles.id → auth.users.id` (1:1 extension table, no longer
auto-populated by trigger — see §7). `food_trucks.owner_id → auth.users.id` **and**
`food_trucks.opened_by_user_id → profiles.id` (two independent FK paths to the same conceptual
owner — not circular, but redundant/confusing: `owner_id` is the authoritative RLS-checked owner,
`opened_by_user_id` appears to be an onboarding-audit field). All other FKs are conventional
child→parent (`menu_items.truck_id`, `orders.truck_id`/`consumer_id`, `order_items.order_id`,
`booking_*.booking_id → event_booking_requests.id`, etc.) — no circular dependencies found.

**Extensions installed:** `pgcrypto`, `supabase_vault`, `pg_stat_statements`, `uuid-ossp`, `pg_net`,
`pg_cron` (1.6.4, active — see §10), `plpgsql`. **PostGIS is available but NOT installed**
(`installed_version: null`) despite `food_trucks.latitude`/`longitude` and
`planned_locations.latitude`/`longitude` being plain `double precision` columns — see §2 and §9.

---

## 2. Indexes

Every table has only its primary-key (and a few explicit unique/composite) index; **no
supplementary indexes exist on FK columns** beyond what's listed below. Supabase's own performance
advisor flags **27 unindexed foreign keys**:

`booking_deposits.booking_id`, `booking_messages.booking_id`, `booking_messages.sender_id`,
`booking_quotes.booking_id`, `employee_shifts.employee_id`, `employee_shifts.truck_id`,
`event_booking_requests.requester_id`, `event_booking_requests.truck_id`, `favorites.truck_id`,
`follower_notification_preferences.truck_id`, `food_trucks.opened_by_user_id`,
`food_trucks.owner_id`, `order_items.menu_item_id`, `order_items.order_id`,
`orders.consumer_id`, `orders.truck_id`, `planned_locations.created_by`,
`planned_locations.truck_id`, `reviews.user_id`, `sales_prospects.converted_owner_id`,
`scheduled_shifts.created_by`, `scheduled_shifts.employee_id`, `scheduled_shifts.truck_id`,
`support_tickets.user_id`, `truck_employees.user_id`, `truck_transfers.from_owner_id`,
`truck_transfers.to_user_id`.

Notably `orders.truck_id`/`orders.consumer_id` and `order_items.order_id` are unindexed — these are
exactly the columns hit by the RLS predicates `orders_consumer_select`/`order_items_select` on
every order-list query; currently masked by 0 rows, will full-scan once order volume grows.
`food_trucks.owner_id` is unindexed despite being the join key for `auth_user_owns_truck()`, called
from ~10 different RLS policies across the schema.

**Good indexes present:** `idx_menu_items_truck (truck_id, sort_order)`,
`idx_operating_hours_truck (truck_id, day_of_week)` + unique `(truck_id, day_of_week)`,
`idx_reviews_truck (truck_id, created_at DESC)`, `idx_favorites_user (user_id)` + unique
`(user_id, truck_id)`, `notifications_user_id_created_at_idx (user_id, created_at DESC)`,
`agent_run_log_agent_name_started_at_idx`, `truck_employees_unique_active` (partial unique on
`(truck_id, lower(invited_email)) WHERE status <> 'removed'`), `one_pending_transfer_per_truck`
(partial unique on `truck_id WHERE status = 'pending'`).

**Geospatial:** `food_trucks.latitude`/`longitude` and `planned_locations.latitude`/`longitude` are
plain `float8` columns with **no GIST/PostGIS index** — PostGIS isn't even installed on the
project. Any "trucks near me" query is either a client-side filter over all active trucks (fine at
9 rows, not fine at scale) or an unindexed bounding-box scan server-side. Not a launch blocker at
current volume, but flagged for the map feature's scalability (see §9/§10).

---

## 3. Policies & RLS — exhaustive per-table review

**RLS is enabled on all 29 public tables** (`relrowsecurity = true` confirmed via `pg_class` for
every table; none are `relforcerowsecurity`, i.e. table owners/superuser-role connections still
bypass RLS, which is standard Supabase behavior and fine since Edge Functions use the service-role
key deliberately). **No table has RLS enabled with zero policies** (no full-lockout tables) and
**no app-facing table has RLS disabled** (no wide-open tables).

### Locked-down backend tables (correct, `USING (false)`)
`agent_directives`, `agent_inbox_replies`, `agent_run_log`, `content_queue`, `sales_prospects`,
`supervisor_reports`, `support_tickets` — single policy `"service role only"` with `qual: false`
for `{public}` role, i.e. **no client (anon or authenticated) can read/write these at all**; only
service-role connections (which bypass RLS) can touch them. This is correct and matches
`AGENT_AUTOMATION_RUNBOOK.md`'s description of these as agent-automation-only tables.

### `profiles`
- INSERT: `auth.uid() = id` (self-insert only) — correct, and matches the app's known upsert
  pattern (auth trigger `handle_new_user()` was dropped in migration `20260612054246
  drop_auth_user_created_trigger`, per user memory; profile creation is now the app's
  responsibility — confirmed still the live state, no `on_auth_user_created` trigger exists).
- SELECT: **`USING (true)` for `{authenticated}`** — any signed-in user can read every profile row,
  including `email` and `stripe_account_id`. **Finding: High — see Critical Findings #3.**
- UPDATE: `auth.uid() = id` — correct, self-only.
- Realtime: `profiles` is in the `supabase_realtime` publication (see §6) — every profile
  INSERT/UPDATE/DELETE is broadcast to every subscriber whose SELECT policy allows the row, which
  given the `true` policy means **every connected authenticated client**, amplifying the exposure
  above from "queryable" to "pushed live" (email/avatar/display_name/stripe_account_id changes
  streamed to the whole user base in real time).

### `food_trucks`
Nine policies, several redundant (confirms Supabase's `multiple_permissive_policies` lint — see
§9): `"Owners manage their own truck"` (ALL, `owner_id = auth.uid()`), `"food_trucks: owner can
insert"` (INSERT, same check — duplicate of the ALL policy), `"Anyone can read active trucks"` +
`"food_trucks: anyone can read active trucks"` (two **identical** SELECT policies, `is_active =
true`), `"food_trucks: owner can read own truck"` (SELECT, duplicate of ALL),
`"employee_select_assigned_truck"` (SELECT via `auth_user_is_employee(id)` — correct, lets active
employees see their truck even if `is_active = false`), `"employee_update_truck_live"` (UPDATE via
`auth_user_is_employee(id)` — lets employees toggle live status), `"food_trucks: owner can update"`
+ `"food_trucks_owner_update"` (two duplicate owner UPDATE policies). No cross-tenant read/write
gap found — every write path correctly gates on `owner_id = auth.uid()` or
`auth_user_is_employee/owns_truck()`. **Finding: policy duplication is a maintainability/perf
issue, not a security hole** — but it's clear evidence of iterative migrations adding new policies
without removing superseded ones (matches Phase 1's non-transactional/ad-hoc schema-change
pattern).

### `menu_items` / `operating_hours`
SELECT policies are `USING (true)` (fully public read) — intentional (menu/hours should be public),
but note **neither is scoped to `food_trucks.is_active`**, so menu items and hours for
deactivated/soft-hidden trucks remain publicly queryable via direct `.from('menu_items')` calls.
Low-severity info leak (menu contents of an inactive truck). INSERT/UPDATE/DELETE all correctly
check `EXISTS (... food_trucks WHERE id = truck_id AND owner_id = auth.uid())`.

### `orders` / `order_items`
- `orders_consumer_insert`: `consumer_id = auth.uid()` — correct.
- `orders_consumer_select`: `consumer_id = auth.uid() OR auth_user_owns_truck(truck_id) OR
  auth_user_works_for_truck(truck_id)` — correctly scoped three ways (consumer, owner, employee).
- `orders_consumer_update`: `USING (consumer_id = auth.uid())`, **`WITH CHECK (status =
  'cancelled')`** — the WITH CHECK only constrains the resulting `status` value; it does **not**
  re-assert `consumer_id = auth.uid()` or restrict other columns. A consumer submitting a
  self-cancel UPDATE could, in the same request, also change `total_price`, `pickup_note`, or even
  `consumer_id` on their own order (since the row is only reachable if it was already theirs, the
  worst case is a consumer reassigning their own order to another user's id, or zeroing the price
  before cancelling — no direct fraud path since order total isn't charged from this table, but a
  data-integrity gap). **Finding: Low/Medium — tighten `WITH CHECK` to also pin `consumer_id =
  auth.uid()` and arguably freeze `total_price`.**
- `orders_owner_update` / `orders_employee_update`: `USING (auth_user_owns_truck/works_for_truck
  (truck_id))`, **no `WITH CHECK` at all** — an owner or employee can update *any* column
  including `payment_status`, `stripe_payment_intent_id`, `consumer_id`, `total_price` on any order
  for their truck. Functionally needed for status transitions, but the absence of a `WITH CHECK`
  means a compromised/malicious employee account could directly flip `payment_status` to `'paid'`
  without a real charge (bypassing Stripe entirely) — worth a follow-up `WITH CHECK` restricting
  which columns non-payment-flow actors can touch. **Finding: Medium.**
- `order_items_select`: correctly OR's consumer/owner/employee. `order_items_insert`: `EXISTS (...
  orders WHERE id = order_id AND consumer_id = auth.uid())` — correct. No UPDATE/DELETE policy on
  `order_items` at all (items are immutable post-creation from the client's perspective) — fine.

### `truck_employees` (the `invite_employee_by_email` blast radius)
- `owner_manage_employees`: ALL via `auth_user_owns_truck(truck_id)` — correct.
- `employee_view_own`: SELECT `user_id = auth.uid()` — correct.
- `employee_claim_invite`: UPDATE, `USING (lower(invited_email) = lower(auth.jwt()->>'email') AND
  status = 'pending')`, `WITH CHECK (user_id = auth.uid() AND status = 'active')` — this is the
  *intended* self-claim path for a pending invite, and it's correctly scoped to the invitee's own
  JWT email. **However**, the `invite_employee_by_email` RPC (see Critical Finding #2) bypasses all
  of this by inserting rows directly as `SECURITY DEFINER` with no caller-side RLS or ownership
  check — the RLS on this table is sound, but the RPC that writes to it isn't gated at all.

### `truck_transfers`
INSERT `WITH CHECK (from_owner_id = auth.uid() AND auth_user_owns_truck(truck_id))` — correct.
SELECT split correctly by `from_owner_id`/`to_user_id`. Cancel/decline UPDATEs check the
appropriate party + `status = 'pending'` in `USING`, but `WITH CHECK` only constrains
`status = 'cancelled'` — same class of minor gap as `orders_consumer_update` above (low
impact here since the only reachable rows are already the caller's own pending transfers).
No RLS policy allows setting `status = 'accepted'` — that's correctly reserved for the
`accept-truck-transfer` Edge Function (service-role, manually re-validates the JWT — see §5).

### `subscriptions`
`"Service role manages subscriptions"` (ALL, `auth.role() = 'service_role'`) is the only
UPDATE-capable policy — owners cannot self-modify `status`/`current_period_end` (correctly reserved
for the RevenueCat webhook). Two duplicate SELECT policies (`"Owners read their own subscription"`
+ `"subscriptions: owner can read own"`) and duplicate INSERT-adjacent logic — redundant but not a
security gap. `subscriptions_allow_owner_insert` migration (`20260612055306`) added client-side
self-insert (`auth.uid() = owner_id`) — needed for the initial trial-row creation during owner
signup, matches Phase 1's finding of a 4-step non-transactional owner signup.

### `booking_quotes` / `booking_deposits` / `booking_messages`
All correctly scoped via `EXISTS (... event_booking_requests ebr JOIN food_trucks ft ...)`
patterns or the `auth_user_in_booking()` SECURITY DEFINER helper — consumer sees their own
booking's quotes/deposits/messages, owner sees their truck's. No gaps found.

### `notifications`
SELECT/UPDATE/DELETE all `user_id = auth.uid()` — correct. **No INSERT policy for plain users** —
by design, only `SECURITY DEFINER` trigger functions (`notify_reviewer_on_response`,
`notify_truck_owner_on_review`) or the service role can create notification rows. Correct.

### Helper functions used inside policies
`auth_user_owns_truck`, `auth_user_is_employee` — both `SECURITY DEFINER`, added in migration
`fix_rls_recursion_truck_employees` (`20260613032501`) specifically to break an RLS
infinite-recursion cycle (food_trucks policies querying truck_employees, whose owner policy
queried food_trucks). This is a legitimate, well-documented pattern (comment in the migration
explains the recursion it fixes) — not a vulnerability, but it's why these two functions show up
in the Supabase security-advisor's "SECURITY DEFINER callable by anon" warnings (see §8); their
internal logic is self-contained and safe (`auth.uid()`-scoped, no way to pass an arbitrary
identity).

---

## 4. Storage

Six buckets, **all public**: `avatars`, `brand`, `menu-item-photos`, `truck-logos`, `truck-menus`,
`truck-photos`.

| Bucket | Public | Size limit | MIME allow-list | INSERT scoping | UPDATE/DELETE scoping |
|---|---|---|---|---|---|
| `avatars` | yes | none | none | `bucket_id='avatars' AND name = auth.uid()::text` (path-pinned — correct) | same path pin — correct |
| `truck-logos` | yes | none | none | `bucket_id='truck-logos' AND auth.role()='authenticated'` (**no path/owner scoping**) | `auth.uid() = owner` (storage-assigned owner column — correct *after* upload, but upload itself isn't scoped) |
| `truck-photos` | yes | none | none | same pattern as truck-logos | same as truck-logos |
| `truck-menus` | yes | none | none | `bucket_id='truck-menus' AND auth.role()='authenticated'` | **no UPDATE or DELETE policy exists at all** — nobody, including the owning truck, can ever replace/delete a menu file via the API once uploaded |
| `menu-item-photos` | yes | 5 MB | `image/jpeg`, `image/png`, `image/webp` | `bucket_id='menu-item-photos'` only — **no auth-role check, no path scoping** | `bucket_id='menu-item-photos'` only — **any authenticated user can delete any truck's menu photos** |
| `brand` | yes | none | none | (no objects.policies rows found for `brand` bucket — likely admin-managed only via dashboard/service role) | — |

**Findings:**
- **`menu-item-photos` (Critical Finding #4 above):** both INSERT and DELETE policies check only
  `bucket_id = 'menu-item-photos'` — not even `auth.role() = 'authenticated'` on delete, and no
  ownership/path check on either. Any authenticated user can overwrite or delete another truck's
  menu photos. This is the most permissive policy pair in the whole schema.
- **`truck-logos`/`truck-photos` INSERT** checks only `auth.role() = 'authenticated'`, not that the
  uploaded path corresponds to a truck the caller owns — a malicious authenticated user could
  upload into another truck's photo path (the `owner` column set at upload time only protects
  *update/delete after the fact*, not the initial write location). Medium severity — enables
  planting unwanted images at a path another truck's app UI may reference, though the app itself
  presumably scopes the path it writes to (`storage_service.dart` callers use
  `SupabaseConstants.truckLogosBucket`/`truckPhotosBucket` with app-controlled paths) — the gap is
  reachable only via direct API calls bypassing the app, not through normal UI flows.
- **`truck-menus` has no DELETE/UPDATE policy** — functional gap (owners can never replace/remove a
  menu PDF/image through the app), not a security hole, but confirms unbounded storage growth for
  this bucket (§10).
- **Public-bucket listing:** Supabase's own linter (`public_bucket_allows_listing`) flags all five
  content buckets (`avatars`, `menu-item-photos`, `truck-logos`, `truck-menus`, `truck-photos`) —
  each has a `SELECT` policy scoped only to `bucket_id`, which (per Supabase's documented behavior)
  permits `GET /storage/v1/object/list/<bucket>` enumeration of every file in the bucket, not just
  fetching a known URL. For `avatars` this means every user's profile-picture filename (their own
  UUID) is enumerable — low sensitivity since the path *is* the UUID already known to be a user id
  format, but still broader than intended.
- **No file-size/MIME limits** on 4 of 5 content buckets — only `menu-item-photos` has
  `file_size_limit: 5242880` + an image-only MIME allow-list. `avatars`, `truck-logos`,
  `truck-photos`, `truck-menus` accept arbitrary file size and type from any authenticated caller,
  which is both a storage-cost/abuse vector and (for `truck-menus`, meant to hold PDFs/images)
  theoretically allows uploading arbitrary file types served back from a public, trusted-looking
  `*.supabase.co` URL.

---

## 5. Edge Functions

**32 functions deployed live** (`list_edge_functions`), **30 have local source** under
`supabase/functions/`. Two are deployed-only with no local directory:
- **`send-employee-invite`** (verify_jwt: true) — drift: deployed but not in git.
- **`check-open-businesses`** (verify_jwt: false) — drift: deployed but not in git.

Both were fetched via `mcp__supabase__get_edge_function` for review (see below); both represent a
genuine **source-of-truth gap** — if the Supabase project were lost or the deploy history purged,
these two functions' code would not be recoverable from the repo. No local-only functions without
a matching deployment were found (all 30 local dirs have a matching live deployment) — no reverse
drift.

No hardcoded secrets were found in any of the 30 files reviewed across three focused sub-reviews
(payment/financial, notifications, and agent-automation groups) — every function reads credentials
via `Deno.env.get(...)`. Env vars used across the function set: `AGENT_DRY_RUN`,
`AGENT_EMAIL_SECRET`, `ANTHROPIC_API_KEY`, `FIREBASE_SERVICE_ACCOUNT_JSON`,
`GMAIL_SERVICE_ACCOUNT_JSON`, `GOOGLE_PLACES_API_KEY`, `RESEND_API_KEY`,
`REVENUECAT_WEBHOOK_SECRET`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `SUPABASE_ANON_KEY`,
`SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`, plus `CRON_SECRET` (used only by the deployed-only
`check-open-businesses`). **No `Access-Control-Allow-Origin` header is set anywhere in the
function set** — no explicit CORS handling exists; not a security issue by itself (all consumers
are the Flutter app / server-to-server), but if `web/index.html`'s web build ever calls an Edge
Function directly from browser JS, it will fail CORS preflight.

### Payment / financial group

| Function | verify_jwt | Finding | Severity |
|---|---|---|---|
| `create-payment-intent` | true | `amount_cents` taken directly from client body, only floor-validated (`< 50`), never recomputed from menu items/order total server-side. **Any authenticated user can create a PaymentIntent for an attacker-chosen amount routed to a real truck's Stripe Connect account.** | **Critical** |
| `create-booking-payment-intent` | true | Same client-trusted-amount pattern; additionally, the paid amount is never cross-checked against the real `booking_deposits`/`booking_quotes.amount` row before `stripe-webhook` marks that record `paid`. **A consumer can mark a real high-value quote/deposit "paid" for $0.50.** | **Critical** |
| `revenuecat-webhook` | false | Signature/secret check is inside `if (WEBHOOK_SECRET)` — **fails open if the env var is unset**, allowing unauthenticated fake subscription events to flip `food_trucks.is_active`/subscription status. Needs confirmation the secret is set in prod; code should fail closed regardless. | **High (conditional)** |
| `send-employee-invite` (deployed-only) | true | No Supabase client instantiated at all — zero ownership check between caller and the `truckName` supplied in the body. Any signed-in user can send a truck-impersonation "you're invited" email to any address. | **Medium** |
| `stripe-webhook` | false | Verifies Stripe HMAC signature correctly against `STRIPE_WEBHOOK_SECRET`; no replay-window/timestamp-tolerance check, non-constant-time string compare — low practical risk over HTTPS. | **Low** |
| `delete-account` | false | Manually verifies the caller's JWT via `supabaseAdmin.auth.getUser(token)` and scopes every delete to that verified `userId` — correct, no client-suppliable target account. Not wrapped in a transaction (partial-failure risk); doesn't clean up orders/received-reviews/storage objects. | **Low (data hygiene, not auth)** |
| `create-refund` | true | No client-supplied refund amount (full refund of the real charge only); correctly authorizes caller as order consumer or truck owner. A consumer can self-trigger a full refund with no owner approval step — business-policy question, not a vuln. | **Low/policy** |
| `stripe-connect-onboard`, `generate-booking-invoice`, `accept-truck-transfer` | mixed | All correctly scope every action to the JWT-verified caller's own id/ownership — `accept-truck-transfer` (verify_jwt: false) manually re-verifies the bearer token and scopes the transfer lookup to `to_user_id = <verified user>` + `status='pending'` + not-expired. | **None** |

### Notifications / transactional-email group

| Function | verify_jwt | Finding | Severity |
|---|---|---|---|
| `send-truck-announcement` | true | Correctly verifies `food_trucks.owner_id === caller` before blasting followers — the one function in this group with a proper ownership check. | **None** |
| `send-booking-confirmation-email` | true | Same correct ownership check (`truck.owner_id !== user.id` → 403). | **None** |
| `send-booking-notification`, `send-message-notification`, `send-order-notification`, `send-shift-notification` | true | verify_jwt blocks anonymous callers, but none of the four cross-check that the JWT's user is actually a party to the target `booking_id`/`order_id`/`shift_id` — any authenticated user can trigger a spoofed push/notification for an arbitrary (UUID-guessed) record. Nuisance-level only; no content leaked. | **Low** |
| `send-owner-onboarding-emails` | false | No auth of any kind; DB-validates the `owner_id`+`subscription_id` pairing (real check, not fake), but **no resend/idempotency guard** — repeatable spam to a real owner inbox, plus a narrow existence oracle via 404-vs-200 responses. | **Medium** |
| `send-consumer-welcome-email` | false | No auth; **no resend guard at all** (unlike the day-7 checkin function); repeatable spam to a real consumer inbox via a leaked/guessed `user_id`, plus an existence/role oracle. | **Medium** |
| `send-owner-day7-checkin` | false | No auth, but request body is ignored — function iterates eligible owners itself and stamps `onboarding_email3_sent_at`, so repeat POSTs can't double-spam a given owner. Cost/DoS exposure only (unauthenticated compute trigger). | **Low-Medium** |
| `check-open-businesses` (deployed-only) | false | Optional `CRON_SECRET` header check — but the live `cron.job` row that calls it sends no `x-cron-secret` header, strongly implying the secret is currently unset in prod, making the gate a no-op. A 2-hour per-truck cooldown prevents duplicate-spam; residual risk is unauthenticated compute cost. | **Low-Medium** |

### Agent-automation group (12 functions + prospect-businesses + send-agent-email)

10 of the 12 `agent-*` functions plus `send-agent-email` have `verify_jwt: false` at the platform
level and are invoked exclusively by `public.agent_cron_call(fn_name, dry_run)` (a `plpgsql` DB
function, confirmed via `pg_proc`), which pulls a bearer token from `vault.decrypted_secrets WHERE
name = 'agent_cron_bearer'` and calls `net.http_post` with `Authorization: Bearer <token>`. The
shared helper `supabase/functions/_shared/auth.ts:requireAgentSecret()` (lines 1-13) validates
that header against `Deno.env.get('AGENT_EMAIL_SECRET')` with plain string equality, fails closed
if the secret env var is unset (`!secret` short-circuits to 401), and returns a 401 `Response` on
mismatch. Per `AGENT_AUTOMATION_RUNBOOK.md:219`, `AGENT_EMAIL_SECRET` is confirmed to be
provisioned as the **same value** as the `agent_cron_bearer` Vault secret — the name mismatch
between the two is a documentation/rotation-risk footgun (easy to rotate one without the other and
silently break the whole automation chain) but is not currently broken.

**All 10 in-scope `agent-*` functions were individually confirmed** to call `requireAgentSecret()`
as the first statement inside `Deno.serve`, with `if (authError) return authError;` immediately
after — no missing-`return` bug, no logic that logs-and-continues, in any of them:
`agent-sage`, `agent-run-check`, `agent-urgent-alert`, `agent-aiden-inbox`,
`agent-aiden-supervisor`, `agent-email-labeler`, `agent-miles`, `agent-piper`,
`agent-stripe-weekly`, `agent-newsletter-cleanup`. **`send-agent-email`** uses an equivalent inline
bearer check (lines 11-18, same secret, same fail-closed shape, no shared-helper import) — also
confirmed correct. Blast radius if any of these were ever bypassed is real (service-role DB
access, real Gmail sends via a domain-wide-delegation service account for `agent-sage`/
`agent-aiden-*`, real Anthropic API spend) — but the gate itself checked out clean across the
board.

**`prospect-businesses` is the one function in this group with no authentication at all** — no
`requireAgentSecret` import, no inline bearer check, only a `req.method !== 'POST'` guard and a
"is `GOOGLE_PLACES_API_KEY` configured" check. Its body (`city`, optional `types`) is fully
attacker-controlled, drives a real (paid) Google Places Text Search loop, and writes results into
`sales_prospects` via the service-role client (bypassing RLS). Confirmed this is intentional-but-
unauthenticated design, not an oversight in an otherwise-protected function: `agent-miles` itself
calls it with **zero** `Authorization` header. **Finding: High** — anyone who discovers the
predictable `https://<project>.supabase.co/functions/v1/prospect-businesses` URL pattern can POST
arbitrary `{city, types}` repeatedly, draining Google Places API billing with no rate limit and
mass-inserting junk rows into `sales_prospects`. Recommend adding the same
`requireAgentSecret(req)` gate its 10 siblings already use.

`pg_cron` also directly (not via `agent_cron_call`) triggers `check-open-businesses` (every 30 min)
and `send-owner-day7-checkin` (daily noon) with **no Authorization header at all** — covered above.

---

## 6. Realtime

`supabase_realtime` publication includes 8 tables: `booking_messages`, `event_booking_requests`,
`food_trucks`, `menu_items`, `notifications`, `orders`, `profiles`, `scheduled_shifts`.

- **`profiles`** — combined with the `USING (true)` SELECT policy (§3), this means every
  profile-row change (email, display_name, avatar_url, **stripe_account_id**) is broadcast to
  every connected authenticated client, not just queryable on demand. This is the same underlying
  RLS gap as Critical Finding #3, just with a live-push amplifier.
- **`orders`** — RLS is correctly scoped (consumer/owner/employee), so realtime fan-out here is
  bounded by the same per-row policy Postgres Realtime evaluates per subscriber; no additional gap
  found, assuming the project's Realtime service has RLS-based authorization enabled (this is a
  dashboard-level toggle, not visible via SQL — recommend manually confirming "Enable RLS" is on
  for the Realtime settings on this project, since a misconfiguration there would bypass all of the
  policy analysis above for these 8 tables specifically).
- **`food_trucks`** — public read for active trucks, so realtime location/status updates broadcast
  to any subscribed map client; this is the intended "live map" behavior, not a leak, but at scale
  is a fan-out cost concern if many consumers subscribe simultaneously to a large active-truck set
  (see §9).
- **`menu_items`, `scheduled_shifts`, `booking_messages`, `event_booking_requests`,
  `notifications`** — all backed by scoped RLS policies; no gap found beyond the general
  performance note in §9 about `auth.uid()` re-evaluation cost, which also applies per-subscriber
  under Realtime.

---

## 7. Authentication

- **Signup trigger:** `on_auth_user_created` / `handle_new_user()` were dropped in migration
  `20260612054246 drop_auth_user_created_trigger` — confirmed still the live state (no such
  trigger/function exists in `pg_proc`/`pg_trigger` today). Profile creation is entirely
  client-driven now (`profiles: owner can insert` RLS policy, `auth.uid() = id`); per project
  memory the app performs an **upsert** (not insert) as a guard against races/retries — this
  matches the RLS design (`ON CONFLICT` upsert only needs the same INSERT policy, no additional
  RLS surface).
- **Users:** 14 rows in `auth.users`, all `email_confirmed_at IS NOT NULL` (14/14 confirmed) —
  consistent with `HANDOFF.md`'s note that these are pre-launch test accounts
  (`apple.review@farlo.app`, `jwinburndcso@gmail.com`, `johnny.danger12@gmail.com`, etc.), slated
  for a full wipe on Apple approval per the documented launch-wipe plan.
- **Client key handling:** `lib/main.dart:13-41` reads `SUPABASE_URL`/`SUPABASE_PUBLISHABLE_KEY`
  via `String.fromEnvironment(...)` (populated at build time from `.env.json` via
  `--dart-define-from-file`), uses the modern **publishable-key** pattern (not the legacy anon
  JWT), and **fails loudly** (`throw StateError`) if either is empty — a deliberate hardening added
  after a prior App Store rejection where a misconfigured release build silently shipped with an
  empty Supabase URL. `.env.json` is gitignored and confirmed not present in tracked git history
  (`git ls-files` shows only the placeholder `.env.json.example`). **No `service_role` key material
  found anywhere in `lib/`** (`grep -rn "service_role\|SERVICE_ROLE" lib/` returns zero matches) —
  clean separation between client and server credentials.
- **Auth advisor findings (Supabase linter):**
  - `auth_leaked_password_protection` — **disabled**. HaveIBeenPwned compromised-password checking
    is off; recommend enabling before public launch. **Low/Medium.**
  - `auth_db_connections_absolute` (INFO) — Auth server is configured for a fixed max of 10
    connections rather than a percentage-based allocation; won't scale automatically if the
    project's compute tier is upsized later. **Informational.**
  - JWT expiry, additional auth providers, and other dashboard-only auth settings are **not
    visible via SQL/MCP tooling** and there is no local `supabase/config.toml` to cross-check
    (see §13) — recommend manually confirming JWT expiry and enabled providers in the Supabase
    dashboard as part of pre-launch sign-off, since this audit could not verify them.

---

## 8. Security (cross-cutting)

- **SQL injection surface:** no raw string interpolation into SQL found in any reviewed Edge
  Function; all DB access goes through the `supabase-js` query builder or parameterized RPC calls.
  No injection surface identified.
- **`SECURITY DEFINER` functions callable by `anon`/`authenticated`** (11 flagged by Supabase's
  linter): `auth_user_in_booking`, `auth_user_is_employee`, `auth_user_owns_truck`,
  `delete_owner_review_response`, `get_truck_follower_count`, `invite_employee_by_email`,
  `notify_reviewer_on_response`, `notify_truck_owner_on_review`, `owner_has_active_subscription`,
  `set_owner_review_response`, `trigger_send_consumer_welcome_email`,
  `trigger_send_owner_onboarding_emails`, `update_truck_rating`. Reviewed each definition directly
  via `pg_proc`: **all are safe self-contained `auth.uid()`-scoped checks except
  `invite_employee_by_email`, which has no ownership check at all** — see Critical Finding #2.
  `owner_has_active_subscription`/`get_truck_follower_count` leak only a boolean/count (low-value
  info disclosure if called with an arbitrary `owner_id`/`truck_id` — technically anyone can probe
  "does this owner have an active sub," Low severity).
- **`function_search_path_mutable`** (8 functions flagged): `set_updated_at`,
  `update_truck_rating`, `auth_user_in_booking`, `auth_user_works_for_truck`,
  `owner_has_active_subscription`, `trigger_send_owner_onboarding_emails`,
  `trigger_send_consumer_welcome_email`, `agent_cron_call` — none of these pin `SET search_path`,
  a defense-in-depth best practice against search-path-hijacking if a malicious schema/role is ever
  introduced. **Low**, but a one-line fix per function (`SET search_path = public`).
- **Synchronous HTTP inside DB triggers:** `trigger_send_owner_onboarding_emails` and
  `trigger_send_consumer_welcome_email` call `extensions.http_post(...)` **synchronously** from an
  `AFTER INSERT/UPDATE` trigger — unlike `agent_cron_call`, which correctly uses the async
  `net.http_post`. A slow/hung Edge Function response would hold the triggering transaction (a
  `profiles` or `subscriptions` INSERT) open for the duration of the HTTP call. Both wrap the call
  in `EXCEPTION WHEN OTHERS` so a failure doesn't roll back the parent write, but latency is still
  inherited synchronously. **Medium — recommend migrating both to `pg_net`'s async `net.http_post`
  like `agent_cron_call` already does.**
- **CORS:** no `Access-Control-Allow-Origin` header set in any Edge Function — see §5.
- **Rate limiting:** none observed on any public-facing Edge Function (webhook or trigger-invoked).
  `prospect-businesses` (verify_jwt: false) in particular burns real Google Places API quota per
  call with no auth/rate-limit reviewed in this pass — recommend a follow-up look specifically at
  its input surface before launch, since it's a paid third-party API behind a public URL.
- **PII exposure:** `profiles.email`/`stripe_account_id` over-exposed via RLS (Critical Finding
  #3); `sales_prospects`/`support_tickets` (containing customer emails/phone numbers/ticket bodies)
  are correctly locked to service-role only.

---

## 9. Performance

- **`auth_rls_initplan` (56 instances):** nearly every RLS policy calls `auth.uid()` /
  `auth.role()` directly instead of `(select auth.uid())`, which Postgres cannot cache/hoist as an
  `InitPlan` — it re-evaluates the auth function **once per row scanned**, not once per query.
  Affected tables include `profiles`, `food_trucks`, `subscriptions`, `operating_hours`,
  `menu_items`, `reviews`, `favorites`, `truck_transfers`, `truck_employees`,
  `event_booking_requests`, `push_tokens`, `notification_preferences`, `booking_messages`,
  `notifications`, `orders` — effectively the whole schema. At current row counts (single/double
  digits) this is invisible; at scale it's a straightforward, well-documented Supabase performance
  fix (wrap every `auth.uid()`/`auth.role()` call in policies with `(select ...)`).
- **`multiple_permissive_policies` (115 instances)** across `booking_deposits`, `booking_quotes`,
  `employee_shifts`, `event_booking_requests`, `follower_notification_preferences`,
  **`food_trucks`**, `orders`, `planned_locations`, `scheduled_shifts`, **`subscriptions`**,
  `truck_employees`, `truck_transfers` — Postgres must evaluate *every* PERMISSIVE policy for a
  given command and OR the results together, so duplicate policies (see `food_trucks` in §3) are
  pure overhead. Confirms Phase 1's observation of ad-hoc, additive schema changes without cleanup.
- **N+1 / god-screen risk:** not independently re-verified in this pass (see Phase 1
  `architecture.md` for the screen-level analysis) — but the unindexed FK list in §2 means several
  of those screens' underlying queries (order lists by `truck_id`/`consumer_id`, booking lists by
  `truck_id`) will degrade from sequential scans as data grows, compounding any N+1 pattern
  already present at the app layer.
- **Geospatial "near me" queries:** no PostGIS/GIST index exists (§2); any location-radius query is
  either an unindexed scan or entirely client-side filtering over `is_active = true` trucks. Fine
  today (9 trucks), a real bottleneck once the active-truck count grows into the hundreds+.
- **Realtime fan-out cost:** `food_trucks` and `profiles` are the two riskiest tables in the
  realtime publication for fan-out cost — `food_trucks` because many consumer clients may
  simultaneously subscribe to live open/closed + location state, `profiles` because (per §3/§6) its
  overly-broad SELECT policy means the fan-out audience is "every authenticated client," not a
  scoped subset.

---

## 10. Scalability

- **Connection pooling:** not directly observable via the tools available in this audit (no client
  connection-string config was reviewed) — Supabase's advisor did flag the Auth service's
  connection allocation as absolute-count rather than percentage-based (§7), which is the one
  concrete pooling-adjacent signal available; recommend confirming Supavisor/pgbouncer transaction
  mode is used for the app's runtime connections (standard Supabase default) as part of scale
  planning rather than as a launch blocker.
- **`pg_cron` jobs (13 active, confirmed via `cron.job`):**

  | Job | Schedule | Target |
  |---|---|---|
  | `check-open-businesses` | `*/30 * * * *` (every 30 min) | Edge Function, no auth header |
  | `send-owner-day7-checkin` | `0 12 * * *` (daily noon) | Edge Function, no auth header |
  | `agent-aiden-supervisor` | `0 6 * * 1` (Mon 6am) | via `agent_cron_call`, live (`dry_run=false`) |
  | `agent-aiden-inbox-morning` | `0 7 * * *` | via `agent_cron_call` |
  | `agent-aiden-inbox-afternoon` | `0 16 * * *` | via `agent_cron_call` |
  | `agent-miles` | `0 8 * * 1,3,5` | via `agent_cron_call` |
  | `agent-piper` | `0 9 * * 2,4` | via `agent_cron_call` |
  | `agent-email-labeler` | `0 17 * * *` | via `agent_cron_call` |
  | `agent-newsletter-cleanup` | `0 17 1 * *` (monthly) | via `agent_cron_call` |
  | `agent-stripe-weekly` | `0 16 * * 5` (Fri 4pm) | via `agent_cron_call` |
  | `agent-urgent-alert` | `*/15 * * * *` (every 15 min) | via `agent_cron_call` |
  | `agent-run-check` | `0 */4 * * *` (every 4h) | via `agent_cron_call` |
  | *(agent-sage's schedule)* | per `AGENT_AUTOMATION_RUNBOOK.md`, "every 5 min" | not present as a separate `cron.job` row distinct from the others at audit time — schedule described in docs runs more frequently than any other job; worth confirming its `cron.job` entry matches the documented 5-minute cadence live. |

  Note the live `cron.job.command` text for the two agent jobs actually reads
  `select public.agent_cron_call('agent-aiden-supervisor', false)` (i.e. **`dry_run=false`, live
  mode**) even though the migration `agent_cron_schedule` that originally created these jobs used
  `dry_run=true` — confirms the jobs were later flipped to live (matches
  `AGENT_AUTOMATION_RUNBOOK.md`'s "Status as of Jul 2 2026: all 12 jobs are LIVE"), i.e. the cron
  schedule was patched post-migration rather than via a new migration file — another instance of
  live-vs-migration-history drift (see §13).
  `agent_cron_call` adds a `pg_sleep(floor(random() * 90))` jitter before firing — reasonable, but
  means a `plpgsql` function execution (and its underlying pg_cron worker/connection) is held open
  for up to 90 seconds doing nothing but sleeping, once per scheduled job (worst case ~13 concurrent
  90-second sleeps across the job set) — minor connection-slot pressure, not a real risk at this
  job count but worth remembering before adding many more jobs.
- **Unbounded growth vectors:** `agent_run_log` (693 rows already, uncapped, no retention/cleanup
  job); `notifications` (no cleanup job, no soft-delete/archival); `truck-menus` storage bucket has
  no DELETE policy (§4), so old files can never be removed even manually by the owner. None of
  these are launch blockers at current volume but should have a retention plan before general
  availability.
- **Cost tracking:** per `AGENT_AUTOMATION_RUNBOOK.md`, `agent_run_log` now records
  `input_tokens`/`output_tokens`/`cache_read_tokens`/`web_search_requests`/`model` per run and
  `agent-aiden-supervisor` computes a weekly Anthropic cost estimate — a reasonable homegrown
  safeguard against silent cost blowups from the agent system, documented as slightly undercounting
  (excludes the cost of generating the report that contains it).

---

## 11. Secrets

Repo-wide search for hardcoded credentials (`supabase/functions/**`, no `supabase/config.toml`
exists to check, no tracked `.env*` files) found **zero hardcoded API keys, service-role keys,
webhook secrets, or third-party credentials** — every secret is sourced via `Deno.env.get(...)` on
the Edge Function side, and via `String.fromEnvironment(...)` / `.env.json`
(gitignored, confirmed untracked) on the Flutter client side.

Secrets confirmed externalized correctly: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`,
`REVENUECAT_WEBHOOK_SECRET`, `RESEND_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_PLACES_API_KEY`,
`GMAIL_SERVICE_ACCOUNT_JSON`, `FIREBASE_SERVICE_ACCOUNT_JSON`, `AGENT_EMAIL_SECRET`,
`SUPABASE_SERVICE_ROLE_KEY`/`SUPABASE_ANON_KEY`/`SUPABASE_URL`, plus a Vault-stored
`agent_cron_bearer` secret (accessed via `vault.decrypted_secrets`, never exposed to any client).

**Findings are about correctness of *use*, not exposure of *values*:**
- `revenuecat-webhook`'s use of `REVENUECAT_WEBHOOK_SECRET` fails open if unset (§5/Critical #5) —
  a secrets-*handling* bug, not a leak.
- The Vault secret name `agent_cron_bearer` vs. the Edge Function env var name it's checked against
  (`AGENT_EMAIL_SECRET`) don't match — a naming/documentation gap that increases the chance of a
  future credential-rotation mistake (§5).
- `GOOGLE_PLACES_API_KEY` is documented in `COWORK_AGENT_SETUP.md` as "no app restrictions,
  restricted to Places API only" — i.e. it's an unrestricted-by-referrer server-side key, which is
  appropriate since it's only ever used from an Edge Function (never shipped to the client), but
  worth confirming it isn't reused anywhere in the Flutter app's own Google Maps/Places
  integration (a client-embedded, unrestricted key would be a real exposure) — not checked in this
  pass, flagged for follow-up.

---

## 12. Database design

- **Naming:** consistent `snake_case`, mostly plural table names (`profiles`, `food_trucks`,
  `menu_items`, etc.); a handful of singular/collective names for the agent-automation tables
  (`agent_directives`, `content_queue`, `supervisor_reports`) are a minor stylistic inconsistency,
  not a real defect (they're key-value/queue/report tables where "plural" doesn't fit naturally).
- **Primary keys:** `uuid` with `gen_random_uuid()` default everywhere except two composite PKs
  (`push_tokens (user_id, platform)`, `follower_notification_preferences (follower_id, truck_id)`)
  and one supplementary identity column (`support_tickets.ticket_number`, human-facing sequential
  ticket number alongside the real `uuid` PK) — consistent, sensible convention throughout.
- **Timestamps:** `created_at timestamptz default now()` is present and consistent on nearly every
  table. `updated_at` is present (with a shared `set_updated_at()` trigger function, `pg_proc`
  confirmed) on `food_trucks`, `subscriptions`, `orders`, `support_tickets`, `sales_prospects`, but
  **absent** on `booking_quotes`/`booking_deposits`/`event_booking_requests` (status changes on
  these aren't independently timestamped beyond `created_at`) — minor observability gap, not a
  defect.
- **Enums vs. free text:** no native Postgres `enum` types are used anywhere — every "enum-like"
  column (`profiles.role`, `orders.status`, `event_booking_requests.status`,
  `truck_employees.status`, `support_tickets.status/priority/type`, `sales_prospects.status`, etc.)
  is `text` with a `CHECK (col = ANY (ARRAY[...]))` constraint instead. This is a defensible,
  commonly-recommended Postgres pattern (easier to alter than a native enum) — **not a defect**,
  just worth noting as a deliberate design choice, consistently applied across the whole schema.
- **Soft delete:** no table uses a `deleted_at`/`is_deleted` soft-delete convention except
  `food_trucks.is_active`/`is_open` (business-status flags, not delete markers) and
  `truck_employees.status = 'removed'` (a status value, not a delete flag). All other tables are
  hard-delete (e.g., `delete-account` physically deletes rows via cascade). Consistent, no mixed
  convention found.
- **Circular FKs:** none found — see §1 (the `food_trucks.owner_id`/`opened_by_user_id` dual-FK
  situation is redundant, not circular).
- **`menu_items.price default 0`:** a menu item can be created with `price = 0` and no non-zero
  constraint — minor data-quality gap (an owner could accidentally publish a free item), not a
  security issue.

---

## 13. Migration quality

- **Critical gap: no migration history in git.** `supabase/migrations/` exists as a directory but
  contains **0 files**; there is also **no `supabase/config.toml`** anywhere in the repo. The live
  project has **74 applied migrations** (`list_migrations`, earliest `20260612054246` through
  latest `20260703140827`, all named with the standard `YYYYMMDDHHMMSS_description` Supabase CLI
  convention — the *naming* convention itself is fine). This means: **the entire schema history
  exists only inside the live Supabase project**, retrievable via `supabase_migrations.schema_migrations`
  (confirmed queryable — full SQL `statements` arrays are stored there) but not checked into
  version control at all. If this project were lost, deleted, or needed to be forked/replicated,
  there is no local migration set to `supabase db push` against a fresh project. **Recommend
  running `supabase db pull` (or equivalent) to materialize `supabase/migrations/*.sql` into the
  repo before launch** — this is a repo-hygiene/disaster-recovery gap, not a live-security issue.
- **Idempotency:** spot-checked several migrations via `supabase_migrations.schema_migrations`
  (`drop_auth_user_created_trigger` uses `DROP TRIGGER IF EXISTS`/`DROP FUNCTION IF EXISTS` —
  idempotent; `storage_bucket_rls`, `fix_rls_recursion_truck_employees`,
  `agent_tables_rls`/`create_agent_inbox_replies` all use plain `CREATE POLICY`/`CREATE TABLE`
  without `IF NOT EXISTS` guards — **not safely re-runnable**, standard for Supabase CLI-managed
  migrations that are only ever applied once via the tracked `schema_migrations` ledger, so low
  practical risk as long as that ledger stays intact, but there's no textual idempotency
  safety-net if a migration were ever replayed by hand).
- **Destructive operations:** `drop_auth_user_created_trigger` is the only structurally destructive
  migration reviewed, and it's guarded (`IF EXISTS`). No `DROP COLUMN`/`DROP TABLE` without guards
  was found in the migrations pulled for review; a full destructive-operation audit would require
  pulling all 74 migrations' `statements`, which wasn't exhaustively done in this pass (only ~8
  were spot-checked by name/relevance) — recommend doing this once migrations are materialized to
  git per the point above, so they're diffable.
- **Live-vs-history drift confirmed:** the `agent_cron_schedule` migration
  (`20260702044908`) creates all agent cron jobs with `dry_run := true`; the live `cron.job` table
  today shows `dry_run := false` for all of them — i.e., the jobs were flipped to live **without a
  corresponding migration file**, presumably via a direct `cron.alter_job`/manual SQL change or
  dashboard action. This is exactly the kind of out-of-band, unmigrated live patch the audit brief
  asked to watch for, and it's real: **the live cron configuration cannot be reconstructed from the
  migration history alone.**
- **Rollback strategy:** no down-migrations exist (single-direction `up` files only) — standard
  for Supabase CLI projects, not itself a defect, but combined with the missing local migration
  files above, there is currently **no way to reconstruct or roll back this schema from source
  control at all.**

---

## Appendix: sub-review provenance

Sections 5 (Edge Functions) and parts of §1/§7/§11 draw on three parallel read-only sub-agent
reviews (payment/financial functions, notification functions, and the agent-automation function
group + `_shared/auth.ts`) plus one grep sweep of `lib/` for table references, RPC calls, storage
bucket usage, and secret leakage — all conducted with the same read-only constraints as this
report and cross-referenced against direct `pg_policies`/`pg_proc`/`pg_indexes` queries before
being included above.
