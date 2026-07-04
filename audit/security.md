# Farlo — Security Audit (Phase 7)

**Scope:** Client-side/mobile security lens + cross-cutting security synthesis, building on Phase 2
(`audit/supabase-audit.md` — RLS/storage/edge-function audit), Phase 3 (`audit/ai-agents.md` —
prompt-injection/agent audit), Phase 4 (`audit/app-store-review.md`), and Phase 5
(`audit/code-quality.md`). Discovery only — no code, config, or live-function changes; no mutating
SQL (all DB access below is read-only `SELECT`/`pg_policies`/`pg_constraint`/advisor calls). All
paths relative to `/Users/johnny/Desktop/Good Truck Finder`.

---

## 1. Executive Summary

Phases 2–5 already found and documented the app's most severe backend issues (payment
amount-tampering, `invite_employee_by_email` privilege escalation, `profiles` PII over-exposure,
storage cross-tenant tampering, agent sender-spoofing). This phase deliberately did not
re-derive those — see the Consolidated Risk Register (§4) for the full picture including them.

**This phase's mandate — the client/mobile lens — surfaced one finding as severe as anything in
Phase 2: the same `GOOGLE_PLACES_API_KEY` Phase 2 flagged as "server-side only, unrestricted by
referrer" and explicitly punted to a follow-up ("worth confirming it isn't reused... not checked in
this pass") *is* reused, and *is* compiled directly into the Flutter client via `--dart-define`,
extractable from the shipped APK/IPA via `strings`.** That single finding closes Phase 2's open
question with the worst possible answer and is this phase's top new critical.

Beyond that, this phase found: auth tokens sit in the Supabase SDK's default `SharedPreferences`
backend rather than Keychain/Keystore-backed secure storage; account deletion is provably broken
(not just incomplete) for any user who ever sent a booking chat message or filed a support ticket,
due to two `NO ACTION` foreign keys colliding with the delete function's non-transactional design;
logout never invalidates the 19 non-`autoDispose` Riverpod providers Phase 5 found, so a
shared-device second login can render stale cached data from the previous user; and two RLS
policies on tables Phase 2 didn't deep-dive (`employee_shifts`, `scheduled_shifts`) allow an
employee to self-report arbitrary clock times via a direct API call, bypassing every UI control.

**New Critical/High findings from this phase: 4** (Google Places key embedded client-side; account
deletion FK-failure; two authorization-in-UI-only gaps on employee shift/timesheet data). All
other findings below are Medium/Low, either genuinely clean/positive results or minor hygiene gaps.

### Critical Findings Summary — this phase's NEW items only

| # | Finding | Where | Severity |
|---|---|---|---|
| N1 | `GOOGLE_PLACES_API_KEY` — the same unrestricted, billed-per-call Google API key Phase 2 flagged server-side — is **also compiled into the Flutter client** via `String.fromEnvironment('GOOGLE_PLACES_API_KEY')` and used in direct, unauthenticated `https://maps.googleapis.com/...&key=<key>` calls from the app. Extractable via `strings` on the built APK/IPA (or a MITM proxy on the app's own traffic) by anyone, giving unlimited free Places Autocomplete/Details/Text-Search calls billed to Farlo's Google Cloud project — a second, independent path to the same billing-fraud risk Phase 2 already flagged for `prospect-businesses`. | `lib/features/bookings/widgets/places_autocomplete_field.dart:6,70-74,98-102` | **Critical — billing fraud, key extraction** |
| N2 | Account deletion (`delete-account` Edge Function) **will hard-fail** for any user who has ever sent an event-booking chat message or filed a support ticket, because `booking_messages.sender_id → profiles` and `support_tickets.user_id → auth.users` are both `NO ACTION` (confirmed via `pg_constraint.confdeltype='a'`) and the function deletes rows non-transactionally (already flagged as a hygiene risk by Phase 2, now confirmed as an actual failure mode). The user ends up with favorites/reviews/subscription/truck **already deleted** but the `auth.users` row (and thus the ability to log back in) **still present** — a broken, half-deleted account, not merely an incomplete one. | `supabase/functions/delete-account/index.ts`, `pg_constraint` (`booking_messages_sender_id_fkey`, `support_tickets_user_id_fkey`) | **High — data-integrity + GDPR/CCPA-adjacent deletion failure** |
| N3 | `employee_shifts_update_own` RLS policy is `USING (auth.uid() = employee_id)` with **no `WITH CHECK`** — an employee can `PATCH` their own `employee_shifts` row directly via the Supabase REST API to set arbitrary `clocked_in_at`/`clocked_out_at` values (timesheet fraud). The Flutter app never exposes this in its UI (only `clockIn`/`clockOut` are called by the employee-facing screens), so this is a case of "authorization enforced only by which screens exist," not by the database. | `pg_policies` (`public.employee_shifts`), `lib/features/employees/repositories/employees_repository.dart:75-101` | **High — client-assumed-safe authorization gap Phase 2 didn't examine (table not in its per-table review)** |
| N4 | `scheduled_shifts_employee_update_status`'s `WITH CHECK` only re-asserts `auth.uid() = employee_id` — it does not constrain which columns change. An employee can rewrite their own scheduled shift's `scheduled_start`/`scheduled_end`/`notes` via a direct API call, not just flip `status` to accepted/declined as the UI implies. | `pg_policies` (`public.scheduled_shifts`) | **Medium-High — same class as N3, smaller blast radius** |

---

## 2. Findings by Category

### 1. Authentication

**1.1 — Auth token storage: default `SharedPreferences`-backed, not Keychain/Keystore.**
`supabase_flutter: ^2.14.2` is initialized with no custom `LocalStorage` implementation
(`lib/main.dart:38-41`: `Supabase.initialize(url:, publishableKey:)` — no `authOptions:`/
`localStorage:` override). The package's default (`local_storage.dart` in
`supabase_flutter-2.14.2`) persists the session (access token + refresh token) via
`SharedPreferences`, which on Android backs onto an app-private XML file
(`shared_prefs/*.xml`, plaintext, not Keystore-encrypted) and on iOS onto `NSUserDefaults` (an
app-sandboxed plist, not Keychain). `flutter_secure_storage`/`FlutterSecureStorage` is not a
dependency anywhere in the repo (`grep -rn "flutter_secure_storage" lib/ pubspec.yaml` → zero
hits). **Files:** `lib/main.dart:38-41`, `pubspec.yaml` (no `flutter_secure_storage` dependency).
**Severity: Medium-High.** **Exploitability:** requires physical device access, a rooted/jailbroken
device, an Android backup extraction (`adb backup`, if not disabled — see §7 Sensitive Data below),
or a malicious app with shared storage access on an older/misconfigured Android version — not
remotely exploitable, but is a real gap relative to the platform-standard practice (Keychain/
Keystore) most comparable apps use for session tokens. **Recommendation:** wire a
`flutter_secure_storage`-backed `LocalStorage` implementation into `Supabase.initialize(authOptions:
FlutterAuthClientOptions(localStorage: SecureLocalStorage()))` (a documented, common
supabase_flutter customization) so the JWT pair lives in Keychain/Keystore instead.

**1.2 — Password reset:** `resetPasswordForEmail` (`auth_repository.dart:135-140`) delegates
entirely to Supabase Auth's built-in flow with `redirectTo: 'com.farlo.app://reset-password'` — no
app-level rate limiting, but Supabase Auth applies its own server-side rate limits to this endpoint
by default (not independently verified in this pass, flagged in Phase 2 as a dashboard-only setting
outside SQL/MCP visibility). No code-level issue found on the client side.

**1.3 — Account enumeration: signup reveals existence, login/reset are silent (inconsistent
posture).** `register_screen.dart:59` (`_friendlyError`) explicitly maps Supabase's
"User already registered" error to **`'An account with this email already exists.'`** — a direct,
intentional account-existence oracle on the signup form. By contrast, `login_screen.dart` and the
password-reset flow rely on Supabase Auth's default generic-error behavior (does not reveal
existence). **Files:** `lib/features/auth/screens/register_screen.dart:52-63`. **Severity:
Low-Medium.** **Exploitability:** trivial — script the signup endpoint with a list of candidate
emails, positive/negative response reveals which are registered Farlo users. Low real-world impact
given the user base is still pre-launch, but worth fixing before scale (many apps intentionally
accept this tradeoff for UX; flagging so it's a conscious choice, not an oversight). **Recommendation:**
either accept this consciously (common, defensible product choice) or return a generic "check your
email to continue" message regardless of registration state, matching login/reset's posture.

**1.4 — OAuth (Google/Apple):** both flows (`auth_repository.dart:190-247`) generate and verify a
nonce (`generateRawNonce()` → SHA-256 → passed through to `signInWithIdToken`), which is the correct
anti-replay pattern for Sign in with Apple/Google ID-token exchange. No issue found — matches
Phase 4's clean 4.8 finding.

**1.5 — Token refresh:** handled transparently by `supabase_flutter`'s internal auto-refresh
(no custom refresh logic in the app to audit) — standard, no gap found.

**1.6 — Logout completeness: Supabase session is cleared correctly; app-level cached state is
not.** `AuthNotifier.signOut()` (`auth_provider.dart:230-234`) calls
`authRepository.signOut()` → `_supabase.auth.signOut()` (clears the SDK session, which given §1.1
means the `SharedPreferences`-stored tokens are actually removed on this path — the storage-location
gap is about extraction risk while a token is live, not about signOut failing to clear it), then
`Purchases.logOut()`, then sets `state = const AsyncData(null)`. **It never calls
`ref.invalidate(...)` or otherwise tears down the 19 non-`.autoDispose` `AsyncNotifierProvider
.family`/`FutureProvider.family` instances Phase 5 found** (`bookings_provider.dart`,
`food_truck_provider.dart`, `employees_provider.dart`, `shifts_provider.dart`, `dashboard_screen.dart`,
`favorites_provider.dart`, `map_provider.dart`, `reviews_provider.dart`,
`planned_locations_provider.dart`). Combined with Phase 5's finding that `pendingBookingCountProvider`
keeps a live Realtime channel open per truck ID forever, this means: on a shared/handed-off device,
if User A logs out and User B logs in **without a full app restart**, any provider keyed by a
truck/booking/order ID User A previously viewed remains resident in the `ProviderContainer` and can
resurface stale data (e.g., a cached booking-count badge, a cached truck profile, cached order-queue
contents) until that specific provider happens to be rebuilt. **Files:**
`lib/features/auth/providers/auth_provider.dart:230-234`. **Severity: Medium.** **Exploitability:**
requires a shared device + no app restart between users — realistic for a family tablet or a
loaner/demo device scenario, low for the typical single-owner-phone use case. **Recommendation:**
call `ref.container.invalidate(...)` per known family provider, or (simpler) restart the
`ProviderScope` via a key change on sign-out/sign-in transitions.

**1.7 — Change-password flow correctly re-authenticates** (`auth_repository.dart:142-149`
re-calls `signInWithPassword` with the current password before allowing `updateUser`) — no gap.

---

### 2. Authorization (beyond RLS)

**2.1 — Employee role/permission model: Dart code assumes RLS is the only gate, and in two spots
that gate has holes not covered by Phase 2's per-table review** (Phase 2's §3 covered `profiles`,
`food_trucks`, `menu_items`/`operating_hours`, `orders`/`order_items`, `truck_employees`,
`truck_transfers`, `subscriptions`, `booking_quotes`/`deposits`/`messages`, `notifications` — it did
**not** review `employee_shifts`, `scheduled_shifts`, `push_tokens`,
`follower_notification_preferences`, `planned_locations`, or `event_booking_requests` in depth).
Spot-checking those six tables this phase found:
- `employee_shifts` and `scheduled_shifts` gaps — see N3/N4 in the Critical Findings table above.
  Concretely: `employees_repository.dart:99-101` (`updateWorkedShift`, intended for **owner** use
  only, called from an owner-only screen) writes `clocked_in_at`/`clocked_out_at` with just
  `.eq('id', shiftId)` — the *client* code trusts that only owners can reach this screen, and RLS
  is the only backstop; but RLS's `employee_shifts_update_own` policy independently grants the same
  write capability to the employee whose shift it is, with no column restriction. Two different
  actors (owner via `owner_update_employee_shifts`, employee via `employee_shifts_update_own`) can
  both freely rewrite the same clock-time columns — the owner path is intentional, the employee
  path is very likely not.
- `push_tokens`, `follower_notification_preferences`: correctly self-scoped
  (`auth.uid() = user_id`/`follower_id`), no gap found — clean.
- `planned_locations`: `consumers_read_planned_locations` is `USING (true)` — fully public read of
  every truck's planned future locations. This appears to be an intentional product feature (a
  "where we'll be next" board), not a leak — flagged only for completeness, no action needed unless
  product intent differs.
- `event_booking_requests`: owner/consumer split is correctly scoped via `auth_user_owns_truck`/
  `requester_id = auth.uid()`; the owner UPDATE policy's `WITH CHECK` re-validates
  `auth_user_owns_truck(truck_id)` (better than the `orders`/`truck_transfers` pattern Phase 2
  flagged for missing `WITH CHECK` entirely) — clean.

**2.2 — IDOR risk surface, cross-referenced against Phase 2's RLS map:** every repository method in
`lib/features/*/repositories/*.dart` passes a client-supplied ID (`truckId`, `shiftId`, `orderId`,
`bookingId`) straight into a `.eq('id', ...)` filter with **zero client-side ownership
pre-check** — this is architecturally consistent across the whole app (RLS is meant to be the sole
authorization boundary, which is a defensible pattern *if* RLS is airtight). The concrete risk is
therefore entirely a function of Phase 2's RLS findings plus this phase's two additions (N3/N4):
wherever RLS has a `WITH CHECK` gap or missing policy, the client's "just send the ID" pattern turns
that gap into a real IDOR the moment someone calls the API directly (Postman/curl with a stolen or
legitimately-obtained JWT) instead of through the app UI. This is the single most important
structural point of this section: **the app has no defense-in-depth against RLS gaps** — every RLS
finding in Phase 2 (missing `WITH CHECK` on `orders_owner_update`/`orders_consumer_update`/
`truck_transfers` cancel-update) and this phase's N3/N4 is a *direct*, not theoretical, client-callable
gap because nothing else stands between an authenticated user and the row.

**2.3 — Owner vs. consumer vs. employee UI gating is otherwise consistent with the DB role model.**
`router.dart:44-73`'s redirect logic gates owner-only routes on `user.isOwner` (sourced from
`profiles.role`), matching the RLS helper functions' use of the same conceptual role split. No
client-only permission check was found that lacks *any* server-side backing (the `subscription_screen`
gating Phase 4 already flagged is a product-routing decision, not a security bypass — a consumer
who forced navigation to the subscription screen would still hit `owner_has_active_subscription`/
RLS-scoped queries that return nothing for a non-owner).

---

### 3. Secrets

**3.1 — No `service_role`/Stripe-secret/webhook-secret material found in `lib/`, `android/`,
`ios/`** — confirms and re-verifies Phase 2's finding independently this phase
(`grep -rnE "service_role|sk_live_|sk_test_|-----BEGIN (RSA|PRIVATE)" lib/ android/ ios/` → zero
hits outside `supabase/functions/`, where they're all correctly sourced via `Deno.env.get(...)`).
**Clean.**

**3.2 — `GOOGLE_PLACES_API_KEY` is the one real secret-handling failure found this phase** — see
Critical Finding N1. It is present in `.env.json` (gitignored, confirmed untracked via
`git ls-files`) alongside legitimate client-appropriate keys (`SUPABASE_PUBLISHABLE_KEY`,
`STRIPE_PUBLISHABLE_KEY`, `REVENUECAT_APPLE_KEY`/`REVENUECAT_GOOGLE_KEY`,
`GOOGLE_SIGN_IN_WEB_CLIENT_ID`) — but unlike those, a Google Places API key is a **billed, secret-grade
credential**, not a publishable/public-by-design one, and it is genuinely referenced and embedded
via `String.fromEnvironment('GOOGLE_PLACES_API_KEY')` in `places_autocomplete_field.dart:6`.

**3.3 — `RESEND_API_KEY` is present in the client's `.env.json` but never referenced anywhere in
`lib/`** (`grep -rn "RESEND_API_KEY" lib/` → zero hits). Since dart-define values are only baked
into the compiled binary if a `String.fromEnvironment(key)` call exists in the source, this
specific key is **not** currently extractable from the shipped app — but its presence in the
client build-config file at all is scope creep: a genuinely server-only secret (used exclusively by
Edge Functions for transactional email) sits in the same file distributed to every developer/CI
runner who builds the Flutter app, with no functional reason to be there. **Files:** `.env.json`
(local, gitignored — key inventoried by name only, value not reproduced here).
**Severity: Low-Medium (hygiene).** **Recommendation:** remove `RESEND_API_KEY` from `.env.json`
entirely; it belongs only in Supabase Edge Function secrets (where it's correctly also configured,
per Phase 2 §11).

**3.4 — Firebase client config keys** (`lib/firebase_options.dart:28,35`,
`android/app/google-services.json:31`, `ios/Runner/GoogleService-Info.plist:12` — the literal
strings `AIzaSyA2EMaJfDkWqIkQ31zhJUWR_GItv6zCYwE` and `AIzaSyBUVH-fEgaJfLZxl6RN7GPGLGCkwJODZME`) are
Google's standard **client-facing** Firebase config API keys, which Google's own documentation
states are safe to ship in a compiled app (they identify the Firebase project to Google's backend;
access control is enforced by Firebase Security Rules / App Check, not key secrecy). **Not a
finding** — flagged only to distinguish this expected exposure from the genuinely dangerous one
(N1) that looks superficially similar (`AIzaSy...` prefix) but is a different, billed, unrestricted
API surface (Places API), not a project-identifier key.

**3.5 — `.gitignore` correctly excludes `.env.json`** (line 2: `.env.json`) and `.env.json` is
confirmed untracked (`git ls-files | grep env.json` → only `.env.json.example`). No accidental-commit
risk found in the current working tree.

---

### 4. API Keys — inventory

| Key | Client or server? | Type | Exposure assessment |
|---|---|---|---|
| `SUPABASE_PUBLISHABLE_KEY` | Client (`.env.json` → dart-define) | Publishable | Correct — designed for client exposure, RLS is the real gate. |
| `STRIPE_PUBLISHABLE_KEY` | Client | Publishable | Correct — Stripe publishable keys are meant to be public. |
| `REVENUECAT_APPLE_KEY`/`REVENUECAT_GOOGLE_KEY` | Client | Public SDK key | Correct — RevenueCat's client SDK keys are designed for embedding. |
| `GOOGLE_SIGN_IN_WEB_CLIENT_ID` | Client | Public OAuth client ID | Correct — OAuth client IDs are not secrets. |
| **`GOOGLE_PLACES_API_KEY`** | **Client AND server** (`prospect-businesses` Edge Function + `places_autocomplete_field.dart`) | **Billed, secret-grade** | **Wrong — see N1. Should be server-only, never dart-defined.** |
| `RESEND_API_KEY` | Server (Edge Functions) only, but also sits unused in client `.env.json` | Secret | Correctly used server-side; incorrectly also present in client config file (§3.3). |
| `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `REVENUECAT_WEBHOOK_SECRET`, `ANTHROPIC_API_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `AGENT_EMAIL_SECRET`, Gmail/Firebase service-account JSON | Server only (Edge Function env vars) | Secret | Correctly externalized, confirmed by Phase 2 and re-confirmed this phase (`grep` sweep found zero hardcoded values). |

No rotation/expiry policy or comments were found for any of these (no `HANDOFF.md`-documented
rotation cadence beyond the incident-driven Vault/`AGENT_EMAIL_SECRET` naming mismatch Phase 2
already flagged).

---

### 5. Environment Variables

- **Flutter build:** `--dart-define-from-file=.env.json`, consumed via `String.fromEnvironment(...)`
  at the top of each file that needs a value (`main.dart`, `auth_repository.dart`,
  `places_autocomplete_field.dart`). `.env.json` is gitignored and untracked (§3.5). No CI
  pipeline config (GitHub Actions/Codemagic/Fastlane) was found in the repo to review for how
  secrets are injected in automated builds (`find . -iname "*.yml" -path "*workflows*"`,
  `codemagic.yaml` — none found) — if builds are only ever produced locally today, this is fine;
  worth a process note if CI is added later (secrets would need to move to CI secret storage, not a
  checked-in file).
- **Edge Functions:** `Deno.env.get(...)` used consistently. The **fail-open pattern already
  flagged in Phase 2 for `revenuecat-webhook`** (`if (WEBHOOK_SECRET) { check } ` — skips the check
  entirely if the env var is unset) was checked against every other Edge Function this phase — **no
  other function shares this exact pattern**. All other auth-gated functions either use the
  `requireAgentSecret()` shared helper (fails closed: `if (!secret) return 401`, confirmed in
  `_shared/auth.ts`) or manually verify a JWT via `supabaseAdmin.auth.getUser(token)` (fails closed:
  no token/invalid token → 401). `revenuecat-webhook` remains the only fail-open credential check in
  the function set.

---

### 6. RLS — synthesis, not re-audit

Ranking Phase 2's RLS findings by actual exploitability given this phase's confirmation that **the
client has zero defense-in-depth beyond RLS** (§2.2):

1. **`invite_employee_by_email`** (Phase 2 Critical #2) — highest exploitability of all RLS gaps:
   zero preconditions, callable by any authenticated user, immediate privilege escalation. Confirmed
   still live via `get_advisors` (`anon_security_definer_function_executable` /
   `authenticated_security_definer_function_executable` both still flag it).
2. **`create-payment-intent`/`create-booking-payment-intent`** (Phase 2 Critical #1) — this phase's
   trace of `order_cart_sheet.dart:47-58` confirms the exact client mechanics: `amountCents =
   (cartNotifier.total * 100).round()` is computed **entirely from client-held cart state** and sent
   directly to the Edge Function with no server recomputation — exactly the pattern Phase 2 flagged,
   now traced end-to-end to the UI layer that produces the tampered value (see Abuse Scenario #1).
3. **`profiles: authenticated can read USING (true)`** (Phase 2 Critical #3) — this phase confirms
   the exposed columns are exactly `email`, `display_name`, `avatar_url`, `role`, `stripe_account_id`,
   `created_at` (via `information_schema.columns`) — no phone number or other high-sensitivity field
   is in `profiles` itself (those live in `support_tickets`/`sales_prospects`, correctly locked).
4. **N3/N4 (this phase)** — lower exploitability than #1-3 (requires already being a legitimate
   employee of *some* truck, not an arbitrary stranger) but a real, previously-unexamined gap.
5. **`menu-item-photos` storage cross-tenant tampering** (Phase 2 Critical #4) — unchanged assessment.

**Additional tables spot-checked this phase, not deeply covered by Phase 2:** `employee_shifts`,
`scheduled_shifts` (findings above), `push_tokens`, `follower_notification_preferences`,
`planned_locations`, `event_booking_requests` (all clean or intentional-by-design, see §2.1).

---

### 7. Supabase — service_role usage across Edge Functions

Every one of the 30 local Edge Functions instantiates a `service_role`-keyed client
(`Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!`) — confirmed via repo-wide grep (30 matches, one per
function file). For each function group:

- **Payment functions** (`create-payment-intent`, `create-booking-payment-intent`,
  `create-refund`, `stripe-webhook`, `stripe-connect-onboard`, `generate-booking-invoice`) —
  service-role use is justified: they need to read `profiles.stripe_account_id`/`food_trucks
  .owner_id` across tenant boundaries (by design, to route a payment to the correct connected
  account) and write payment-status columns RLS intentionally keeps out of client `WITH CHECK`
  reach. **No downgrade to user-JWT+RLS is realistic here** — the whole point is cross-tenant
  lookups a consumer's own RLS-scoped session couldn't perform.
- **`delete-account`** — justified: deleting another table's rows on behalf of the verified caller
  requires bypassing RLS's self-scoping in a few spots (e.g. deleting `truck_employees` rows for a
  truck the *deleting owner* owns) — appropriate use, though see N2 for the actual deletion-completeness
  bug.
- **Notification/email functions** — justified where they need to read across owner/consumer
  boundaries to compose a notification (e.g. `send-order-notification` needs both the consumer's and
  the truck's data). None were found accepting a dynamic table/column name as a parameter (checked
  specifically per the audit brief's confused-deputy concern) — every function's table access is a
  hardcoded literal in the source, not derived from request input. **No confused-deputy risk found.**
- **Agent functions** — justified and already covered in depth by Phase 3; service-role is required
  for the agents' cross-table read/write scope by design.
- **`prospect-businesses`** — service-role use here is the aggravating factor in Phase 2's existing
  finding: because the function is both unauthenticated *and* uses service-role (bypassing RLS
  entirely) to write into `sales_prospects`, there's no RLS-level backstop even if the auth gate were
  someday accidentally removed elsewhere — not a new finding, but worth naming as the reason a
  future "let's just add rate limiting" fix wouldn't be sufficient on its own; the missing
  `requireAgentSecret()` gate (Phase 2's recommendation) is still the correct primary fix.

**No instance of a dynamic/attacker-controlled table or column name was found anywhere in the 30
functions.**

---

### 8. Injection

- **SQL injection:** confirmed clean, independently re-verified this phase — every Edge Function
  uses the `supabase-js` query builder or Stripe's form-encoded REST API (`stripePost` helper in
  `create-payment-intent`/`create-booking-payment-intent` builds a URL-encoded body via
  `encodeURIComponent`, not raw SQL) — no template-literal SQL construction found anywhere in
  `supabase/functions/`.
- **Command injection:** no `Deno.run`/`Deno.Command`/subprocess invocation found anywhere in
  `supabase/functions/` (`grep -rn "Deno.run\|Deno.Command" supabase/functions` → zero hits).
- **XSS:** `web/index.html` is Flutter's own web-build bootstrap scaffold (splash screen HTML only,
  confirmed by reading its content) — no user-controlled data is ever interpolated into it. No
  `WebView`/`webview_flutter`/`InAppWebView` usage exists anywhere in `lib/`
  (`grep -rln "WebView\|webview_flutter\|InAppWebView" lib/ pubspec.yaml` → zero hits) — the app
  never renders remote or user-generated HTML/JS content in an embedded browser context. **No XSS
  surface exists in this app.**
- **Deep link injection:** Android declares one custom scheme intent-filter
  (`android:scheme="farlo"`, `AndroidManifest.xml`) and iOS declares the matching
  `CFBundleURLSchemes: ["farlo"]` (plus the separate Google Sign-In reverse-client-ID scheme, which
  is handled entirely inside the `google_sign_in` plugin, not app code). Tracing actual usage: the
  only concrete deep link built into the app is the password-reset redirect
  (`com.farlo.app://reset-password`, `auth_repository.dart:139`) — **Supabase's own SDK parses this
  redirect internally to resume the recovery session; the app's `router.dart` does not parse
  arbitrary deep-link query parameters into navigation targets or database queries anywhere.**
  `sharedRouter`'s only external-input-driven navigation is push-notification tap routing
  (`push_notification_service.dart`, out of this section's deep-link scope but architecturally
  similar) — not independently re-verified this phase for parameter injection, flagged as a
  low-priority follow-up given push payloads originate from Farlo's own trusted backend, not
  arbitrary third parties. **No exploitable deep-link injection found.**

---

### 9. Validation

- **DB-level CHECK constraints exist and back up client-side enum validation** — confirmed via
  `pg_constraint` query: `orders.status`/`payment_status`, `event_booking_requests.status`,
  `truck_employees.status`, `scheduled_shifts.status`, `booking_quotes`/`booking_deposits.status`
  and `.amount > 0`, `reviews.rating BETWEEN 1 AND 5`, `profiles.role`, `operating_hours
  .day_of_week BETWEEN 0 AND 6`, `push_tokens.platform`, `truck_transfers.status` all have real
  `CHECK` constraints — a direct-API caller cannot insert an invalid enum value or a
  non-positive quote/deposit amount even bypassing the Flutter client entirely. **Genuinely good,
  consistently-applied backstop.**
- **Gap: no length/format constraints on free-text columns** — `menu_items.name`,
  `food_trucks.name`/`address`, `profiles.display_name`, booking `notes`, etc. have no `CHECK
  (length(...) < N)` or format constraint; client-side `maxLength` on `TextFormField`s is the only
  gate. A direct API call can insert arbitrarily long strings (storage-cost/display-breakage risk,
  not a security vulnerability per se). **Severity: Low.**
- **Payment functions: validation is real but minimal, not absent** — `create-payment-intent`/
  `create-booking-payment-intent` do check `amount_cents` is present and `>= 50` (Stripe's own
  minimum-chargeable-amount floor) and that `truck_id`/`booking_id` resolve to a real row with a
  connected Stripe account — this is genuine validation, just entirely insufficient because it never
  cross-checks the amount against the actual order/quote/deposit total (Phase 2's core finding,
  re-confirmed and traced to its client origin in §6 above). It is **not** "zero validation," it's
  "validation of the wrong thing."
- **Agent-facing functions (inbound email/webhook payload schema validation)** — ties to Phase 3's
  findings: `agent-aiden-inbox`/`agent-aiden-supervisor` perform no structural validation of inbound
  email content before it reaches the LLM (by design, since email is naturally free text) — this is
  Phase 3's territory and not re-derived here. `revenuecat-webhook`/`stripe-webhook` do validate
  `body.event`/required fields exist before acting (`revenuecat-webhook/index.ts:33-38`), on top of
  (for Stripe) real signature verification — reasonable webhook payload hygiene.

---

### 10. Logging

- **No tokens, passwords, JWTs, or API keys found in any `debugPrint`/`print`/`console.log` call**,
  client or server (`grep -rn "debugPrint\|print(" lib/` cross-referenced against
  token/password/secret/key/auth keywords → zero matches; equivalent `console.log`/`console.error`
  sweep across `supabase/functions/` → zero matches for the same keyword set). **Clean.**
- **Minor PII-in-logs, low severity:** a handful of Edge Functions log the recipient's raw email
  address on successful send — `send-consumer-welcome-email/index.ts:112`
  (`console.log(\`Consumer welcome email sent to ${profile.email}\`)`) and
  `send-owner-day7-checkin/index.ts:157` (same pattern). These are Supabase platform logs, not
  publicly exposed, but do mean plaintext customer emails sit in log storage beyond the DB itself.
  **Severity: Low.** **Recommendation:** log a user ID or truncated identifier instead of the raw
  email if these logs are retained long-term or shipped to a third-party log sink in the future.
- **Log access/retention:** per the brief's own framing, this is lower priority — Supabase project
  logs are accessible only to whoever has dashboard/MCP access to the project (currently the
  founder), no broader access was found or is architecturally implied. Not independently audited
  beyond this observation.
- Phase 5's 15 empty `catch(_){}` and 17 `debugPrint`-only catches were reviewed specifically for
  sensitive-data leakage in this pass — **none of them print request bodies, tokens, or full user
  objects**; they print exception messages or nothing at all. The Phase 5 finding stands as an
  error-handling/UX issue, not a data-exposure one.

---

### 11. PII

**Inventory (client-reachable data only; agent-side `sales_prospects`/`support_tickets` PII is
correctly service-role-locked per Phase 2, not re-inventoried here):**

| Data | Table(s) | Minimization | Exposure |
|---|---|---|---|
| Email | `profiles.email` | 1:1 with account, necessary | Over-exposed to all authenticated users via `profiles` `USING (true)` SELECT (Phase 2 Critical #3) |
| Display name, avatar | `profiles.display_name`/`avatar_url` | Necessary for social features | Same over-exposure as above (lower sensitivity) |
| Stripe Connect account ID | `profiles.stripe_account_id` | Necessary for owner payouts | Same over-exposure — higher sensitivity than email (financial account linkage) |
| Precise GPS (truck owner, live) | `food_trucks.latitude/longitude` (current value only — **no history table**, confirmed via `dashboard_screen.dart:253-254` calling `ownerTruckProvider.notifier.updateLocation`, an `UPDATE` not an `INSERT`) | **Good — only current location retained, no GPS trail persisted.** 30 m/10 s throttle (Phase 5 §2.10) further limits write frequency. | Public by design (customers need to find the truck) — appropriate for the product. |
| Payment metadata (PaymentIntent ID, amount) | `orders.stripe_payment_intent_id`, Stripe itself | Tokenized (§12) | RLS-scoped to consumer/owner/employee — no gap beyond Phase 2's `WITH CHECK` note. |
| Push/device tokens | `push_tokens` | Necessary | Correctly self-scoped RLS, no gap found. |
| Booking/order contact text (pickup notes, chat messages) | `orders.pickup_note`, `booking_messages` | Necessary | Correctly RLS-scoped to booking participants. |

- **Deletion mechanism is broken for a real subset of users — see N2.** This is the most important
  PII finding of this phase: Phase 4 confirmed account deletion *exists* and satisfies 5.1.1(v) on
  paper; this phase found the actual server-side deletion **throws a Postgres FK violation and
  aborts partway through** for anyone who ever used the booking-chat feature or contacted support,
  leaving that user's PII (profile, email, remaining rows) in the database indefinitely while other
  rows (favorites, reviews, subscription, truck) are already gone. **Storage objects (avatar,
  truck-logo/photo/menu images) are never deleted by `delete-account` for any user**, confirmed by
  reading the full function body — this was Phase 2's suspicion, now confirmed as fact for 100% of
  deletions, not just the FK-failure subset.
- **No data-export mechanism found anywhere in the app** (`grep -rn "export\|download.*data\|data
  export" lib/features/account/` → nothing resembling a GDPR/CCPA data-export feature) — a gap
  Phase 4 didn't examine from this angle; flagged here as a compliance-adjacent completeness note,
  not a security vulnerability per se.

---

### 12. Sensitive Data

- **No raw payment card data ever touches Farlo's client or server code.** Confirmed via
  `grep -rn "CardField\|CardFormField\|PaymentSheet" lib/` — both payment surfaces
  (`order_cart_sheet.dart:49-58`, `my_requests_screen.dart:657-664`) use Stripe's
  `PaymentSheet`/`presentPaymentSheet()` API, which is fully tokenized client-side (card data goes
  directly to Stripe, never through Farlo's servers or app code) — **out of PCI scope by design,
  correctly implemented.**
- **Client-side-at-rest exposure is the auth-token storage gap already covered in §1.1** — no other
  sensitive data (payment details, PII) was found cached unencrypted client-side beyond the
  `AuthNotifier`'s in-memory `AppUser` state (email/display name/role — low sensitivity, and memory-
  only, not persisted to disk beyond what `SharedPreferences` already holds for the session).

---

### 13. Rate Limiting

**Edge Function inventory (building on Phase 2/3's unauthenticated-endpoint findings, this phase
adds concrete abuse-cost estimates):**

- **`prospect-businesses`** (Phase 2 High finding, Phase 3 Top Risk #3) — no auth, no rate limit.
  Concrete abuse cost: the function's own logic (`prospect-businesses/index.ts`) loops up to 3
  pages × 6 place types = **up to 18 Google Places API calls per single unauthenticated POST**.
  Google's Places API (Text Search) is billed in the ~$17–32 per 1,000 requests range depending on
  SKU/fields requested. A trivial script firing this endpoint once per second for one hour would
  generate ~64,800 Places API calls — **roughly $1,100–$2,100 of Google Cloud billing in a single
  hour**, with no rate limit, no auth, and no alerting on the billing side (only `agent-run-check`
  watches agent *staleness*, nothing watches API spend in real time). This is a materially higher
  blast radius than "some junk rows in `sales_prospects`" — it's a live, uncapped, third-party
  billing exposure.
- **New this phase: the embedded client-side `GOOGLE_PLACES_API_KEY` (N1) is a second, independent
  path to the exact same billing exposure**, reachable without ever touching Farlo's own API at
  all — an attacker who extracts the key from the APK/IPA can call `maps.googleapis.com` directly,
  bypassing any rate limiting Farlo could ever add to its own `prospect-businesses` endpoint. Any
  fix that only adds auth to `prospect-businesses` (Phase 2's recommendation) **leaves this second
  path completely open** — the key itself must be rotated to one scoped by referrer/bundle ID (which
  Google Places API supports for client-side keys) or the autocomplete feature must be proxied
  through a Farlo-controlled Edge Function instead of calling Google directly from the client.
- **`send-owner-onboarding-emails`/`send-consumer-welcome-email`** (Phase 2 Medium finding) — no new
  cost estimate beyond Phase 2's (email-spam / existence-oracle, not billing-fraud scale).
- **Client-side abuse surfaces, checked this phase:**
  - *Rapid signup:* no app-level throttle; relies on Supabase Auth's platform-level rate limiting
    (not independently verified, standard Supabase default — out of this audit's visibility).
  - *Rapid location-update spam to Realtime:* not a viable abuse vector — only the truck's own
    owner/employee (RLS-scoped via `auth_user_owns_truck`/`auth_user_is_employee`) can write to
    `food_trucks.latitude/longitude`; a consumer has no write path to spam here.
  - *Rapid order/booking creation:* no `.limit()`/throttle on `orders`/`event_booking_requests`
    INSERT from a given consumer — a scripted loop could create unlimited pending orders/booking
    requests (no payment is captured until the separate PaymentIntent flow, so this is a
    storage/UX-noise cost, not a financial-fraud vector on its own) — **Severity: Low.**

---

## 3. Concrete Abuse Scenarios

**1. Zero-cost food order via client-controlled payment amount.** An attacker (any signed-up
consumer, or someone who intercepts the app's own traffic with a proxy) opens `order_cart_sheet
.dart`'s flow, which computes `amountCents = (cartNotifier.total * 100).round()` entirely from
client-held cart state (`order_cart_sheet.dart:47`) and POSTs it to `create-payment-intent`. The
attacker modifies the request (or simply patches the app) to send `amount_cents: 50` (Stripe's
$0.50 floor, the only server-side check that exists) regardless of the real order total, completes
the $0.50 PaymentSheet charge, then calls `placeOrder` with the full, real item list — Stripe
processes a real charge for $0.50 while the truck fulfills a full-price order, with the difference
going unnoticed until manual reconciliation. *(Phase 2's underlying vuln; this phase traced the
exact client code path that produces the tampered value.)*

**2. Google Cloud billing drain via the embedded client API key.** An attacker downloads Farlo's
public APK, runs `strings app.apk | grep AIzaSy` (or decompiles it, or proxies the app's own
traffic once), and recovers the live `GOOGLE_PLACES_API_KEY`. They script direct calls to
`https://maps.googleapis.com/maps/api/place/textsearch/json?query=...&key=<stolen key>` at whatever
volume they choose — Farlo's Google Cloud project is billed per call with no rate limit and no
awareness the calls didn't come from the app. Within hours this can produce a bill in the hundreds
to low thousands of dollars, discovered only when Google's monthly invoice arrives or a budget
alert fires (if one is even configured).

**3. Truck privilege escalation via the employee-invite RPC, now traceable end-to-end to real
customer data exposure.** *(Phase 2's underlying vuln — restated here with the concrete downstream
blast radius this phase's employee-RLS review adds.)* An attacker calls
`rpc('invite_employee_by_email', {p_truck_id: '<any UUID>', p_email: '<own email>'})` directly
(no ownership check exists), instantly becoming an `active` employee of a truck they have no
relationship to. From there, they can read that truck's live order queue, booking requests, and
(per N3) directly `PATCH` their own now-real `employee_shifts` row to fabricate arbitrary worked
hours, or use `employee_shifts_select_owner`-adjacent visibility to see the truck's other staff
data — all without the truck owner ever approving or even knowing an "employee" was added.

**4. Timesheet fraud by a legitimate but dishonest employee.** A truck's actual, legitimately-invited
employee (no privilege escalation needed) calls the Supabase REST API directly —
`PATCH /rest/v1/employee_shifts?id=eq.<their own shift id>` with `{"clocked_in_at": "<earlier
time>", "clocked_out_at": "<later time>"}` — and succeeds, because `employee_shifts_update_own`'s
RLS has no `WITH CHECK` restricting which columns an employee may alter on their own row. The app's
UI never exposes this (only the owner-facing `updateWorkedShift` screen does), so the owner has no
reason to suspect a client-side gate is missing; the fraud is invisible unless the owner
independently reconciles hours against some other record.

**5. Half-deleted "zombie" account after account deletion.** A consumer who once sent a message in
an event-booking chat thread (`booking_messages`) requests account deletion via the in-app "Delete
Account" flow. `delete-account` successfully deletes their `push_tokens`, `favorites`, `reviews`,
and `event_booking_requests` rows, then attempts `auth.admin.deleteUser(userId)` — which fails with
a foreign-key violation because `booking_messages.sender_id → profiles` is `NO ACTION` and their
profile can't be cascaded away while messages still reference it. The function's outer catch
returns a 500; the user sees a generic delete-failed error (or, depending on the exact Dart-side
handling, may believe deletion succeeded since local sign-out still occurs per
`auth_repository.dart:157-159`) — but their `auth.users`/`profiles` row, email, and remaining data
persist indefinitely, silently violating the "I deleted my account" expectation and any GDPR/CCPA
deletion-request obligation.

**6. Cross-tenant menu-photo defacement combined with client-assumed-safe upload paths.** *(Phase
2's underlying vuln, restated with the client angle this phase adds.)* Because
`storage_service.dart`'s callers always construct paths scoped to the truck the *legitimate* app
user owns, the app itself never exercises the gap — but `menu-item-photos`' INSERT/DELETE policies
check only `bucket_id = 'menu-item-photos'` with no owner/path scoping. An attacker who authenticates
as any consumer and calls the Storage REST API directly (bypassing the app's own path-construction
logic entirely, since — per §2.2 — nothing about the client's "safe" path construction is enforced
server-side) can overwrite or delete **any** truck's menu photos, e.g. replacing a competitor's menu
images with objectionable content or blank files, degrading their listing with zero attribution
back to the attacker.

**7. Shared-device stale-data leak.** A food-truck-festival vendor hands their phone to a second
employee to check the booking queue; the first employee had earlier logged out. Because
`AuthNotifier.signOut()` never invalidates Riverpod's non-`.autoDispose` family providers, the
second employee's session (a different truck, different bookings) can, in the window before every
relevant provider happens to naturally rebuild, briefly render cached counts/badges left over from
the first employee's truck — a data-hygiene/privacy leak between two legitimate but different
principals on the same device, not requiring any attack, just normal shared-device use.

**8. Reviewer-triggered false "truck vanished" report during App Store re-review.** *(Restating
Phase 4's Finding 5.1 briefly for completeness of the abuse-scenario set, since it's plausibly
triggerable by an ordinary reviewer action, not just an attacker)* — an Apple reviewer backgrounds
the app mid-review while a demo truck is "live"; because iOS never actually grants "Always"
location authorization (Phase 4's finding), the truck's live position silently stops updating,
and a second reviewer account viewing the map sees the truck disappear — read as a functional bug,
risking a fourth rejection unrelated to any of this app's actual security posture.

---

## 4. Consolidated Risk Register (Phases 2, 3, and 7 — deduplicated, severity-ranked)

| Sev | Finding | Source | Where |
|---|---|---|---|
| Critical | `create-payment-intent`/`create-booking-payment-intent` trust client-supplied `amount_cents`, no server recomputation | Phase 2 | `supabase/functions/create-payment-intent/index.ts`, `create-booking-payment-intent/index.ts`; client trace: `order_cart_sheet.dart:47` |
| Critical | `invite_employee_by_email` SECURITY DEFINER RPC has no ownership check on `p_truck_id` — anyone can join any truck as an employee | Phase 2 | DB function `public.invite_employee_by_email`; called from `employees_repository.dart:30` |
| Critical | `GOOGLE_PLACES_API_KEY` embedded client-side via dart-define, extractable from APK/IPA, unrestricted billing exposure | **Phase 7 (new)** | `lib/features/bookings/widgets/places_autocomplete_field.dart:6,70-74,98-102` |
| High | `profiles` SELECT policy `USING (true)` — every authenticated user reads every profile incl. email/`stripe_account_id`; also realtime-published | Phase 2 | `pg_policies` (`public.profiles`); realtime publication |
| High | `menu-item-photos` storage INSERT/DELETE scoped only to `bucket_id`, no owner/path check — cross-tenant tampering | Phase 2 | `storage.objects` policies |
| High | `prospect-businesses` fully unauthenticated, drives paid Google Places calls + service-role writes, no rate limit; concrete cost estimate ~$1,100-2,100/hr at trivial script volume | Phase 2 (existence) / **Phase 7 (cost estimate)** | `supabase/functions/prospect-businesses/index.ts` |
| High | `agent-aiden-supervisor` applies zero sender filtering on inbound email fed to a directive-editing LLM | Phase 3 | `agent-aiden-supervisor/index.ts:102-119,212-213` |
| High | `agent-aiden-inbox`'s sender allowlist regex tests the raw, unparsed `From:` header — spoofable | Phase 3 | `agent-aiden-inbox/index.ts:17,115` |
| High | Account deletion (`delete-account`) fails via FK violation for users with booking-chat messages or support tickets; non-transactional, leaves half-deleted "zombie" accounts; storage objects never deleted for anyone | Phase 2 (partial) / **Phase 7 (confirmed mechanism + full breadth)** | `supabase/functions/delete-account/index.ts`; `pg_constraint` (`booking_messages_sender_id_fkey`, `support_tickets_user_id_fkey`) |
| High | `employee_shifts_update_own` RLS has no `WITH CHECK` — employee can self-report arbitrary clock times via direct API call | **Phase 7 (new)** | `pg_policies` (`public.employee_shifts`) |
| Medium-High | `scheduled_shifts_employee_update_status` `WITH CHECK` doesn't constrain which columns change | **Phase 7 (new)** | `pg_policies` (`public.scheduled_shifts`) |
| Medium-High | Auth tokens stored via default `SharedPreferences`-backed local storage, not Keychain/Keystore | **Phase 7 (new)** | `lib/main.dart:38-41`; no `flutter_secure_storage` dependency |
| Medium (conditional) | `revenuecat-webhook` fails open (skips signature check) if `REVENUECAT_WEBHOOK_SECRET` unset | Phase 2 | `supabase/functions/revenuecat-webhook/index.ts` |
| Medium | `prospect-businesses` also reachable via the embedded client Places key (N1), independent of any auth fix to the Edge Function itself | **Phase 7 (new)** | Combines Phase 2 finding + `places_autocomplete_field.dart` |
| Medium | Logout never invalidates non-`.autoDispose` Riverpod family providers — stale cached data can leak across users on a shared device | Phase 5 (root cause) / **Phase 7 (logout-completeness angle)** | `auth_provider.dart:230-234`; provider list per Phase 5 §2.7 |
| Medium | `prospect-businesses`'s attacker-controlled `business_name` is a stored prompt-injection payload later read verbatim by `agent-miles` | Phase 3 | `prospect-businesses/index.ts:120-133`; `agent-miles/index.ts:156-157` |
| Medium | No delimiting between trusted `agent_directives` and untrusted customer/prospect text in any agent prompt | Phase 3 | `agent-sage/index.ts:243-249` and equivalents in `agent-miles`, `agent-piper`, `agent-aiden-inbox` |
| Medium | `orders_owner_update`/`orders_employee_update` have no `WITH CHECK` — owner/employee could flip `payment_status` to `'paid'` without a real charge | Phase 2 | `pg_policies` (`public.orders`) |
| Medium | `send-owner-onboarding-emails`/`send-consumer-welcome-email` unauthenticated, no resend guard, existence oracle | Phase 2 | respective `index.ts` files |
| Medium | `send-employee-invite` (deployed, no local source) performs zero authorization | Phase 2 | live Edge Function, no git source |
| Medium | 5 public storage buckets allow listing; 4 of 5 have no file-size/MIME limits | Phase 2 | `storage.buckets`, `get_advisors` |
| Medium | 56 RLS policies re-evaluate `auth.uid()` per-row; `food_trucks`/`subscriptions` have duplicate PERMISSIVE policies | Phase 2 | `pg_policies`, performance advisor |
| Medium | 27 unindexed FKs | Phase 2 | `pg_indexes` |
| Medium | `RESEND_API_KEY` present (unused) in client `.env.json` — server secret scope creep into client build config | **Phase 7 (new)** | `.env.json` |
| Medium | 15 empty `catch(_){}` + 17 `debugPrint`-only catches (client), 2 of which are user-facing silent failures on paid/committed actions | Phase 5 | `booking_chat_screen.dart:118-129`, `booking_requests_screen.dart:647`, others |
| Medium | Account enumeration: signup explicitly reveals "email already exists," inconsistent with login/reset's silent posture | **Phase 7 (new)** | `register_screen.dart:52-63` |
| Medium | No `PrivacyInfo.xcprivacy` at the Runner app level | Phase 4 | `ios/Runner/` |
| Medium | No crash-reporting SDK (Sentry/Crashlytics absent) | Phase 4 | `pubspec.yaml` |
| Medium | iOS background-location "Always" authorization never actually obtained despite app depending on it | Phase 4 | `ios/Runner/Info.plist`, `location_tracking_service.dart` |
| Low-Medium | No data-export/GDPR-style download mechanism found in-app | **Phase 7 (new)** | `lib/features/account/` |
| Low | Minor PII (customer email) logged in plaintext in 2 Edge Function success-log lines | **Phase 7 (new)** | `send-consumer-welcome-email/index.ts:112`, `send-owner-day7-checkin/index.ts:157` |
| Low | `auth_leaked_password_protection` disabled (HaveIBeenPwned check off) | Phase 2 | Supabase Auth advisor |
| Low | 8 `SECURITY DEFINER` functions with mutable `search_path` | Phase 2 | `get_advisors` |
| Low | No length/format CHECK constraints on free-text columns (defense-in-depth gap only) | **Phase 7 (new)** | schema-wide |
| Low | 1 leaked `TextEditingController` in employee-invite dialog | Phase 5 | `employees_screen.dart:156` |
| Low | Ad Boost feature (not yet built) risks 3.1.1 rejection if built with external web checkout | Phase 4 | project backlog, not yet code |
| Clean/positive | No XSS surface (no WebView anywhere); no SQL injection anywhere; no command injection anywhere; nonce-verified OAuth; tokenized Stripe payments (no PCI scope); no `service_role` in client code; no CORS-facing browser calls; location history correctly minimized (current-value-only, no GPS trail table) | **Phase 7 (verified)** | multiple |

---

## Appendix: Method

Grounded in full reads of `audit/supabase-audit.md`, `audit/ai-agents.md`, `audit/code-quality.md`,
`audit/app-store-review.md` before starting. Evidence gathered via: repo-wide `grep`/`rg` sweeps for
secrets, storage APIs, token storage, deep links, WebView usage, and logging keywords; full reads of
`lib/main.dart`, `lib/features/auth/repositories/auth_repository.dart`,
`lib/features/auth/providers/auth_provider.dart`, `lib/features/employees/repositories
/employees_repository.dart`, `lib/features/bookings/widgets/places_autocomplete_field.dart`,
`lib/core/location_tracking_service.dart`, `lib/router.dart`,
`supabase/functions/create-payment-intent/index.ts`,
`supabase/functions/create-booking-payment-intent/index.ts`,
`supabase/functions/revenuecat-webhook/index.ts`, `supabase/functions/stripe-webhook/index.ts`,
`supabase/functions/delete-account/index.ts` (via `mcp__supabase__get_edge_function`); read-only
`SELECT`s against `pg_policies`, `pg_constraint`, `information_schema.columns`/
`table_constraints`/`referential_constraints`, and `mcp__supabase__get_advisors` (security) for
`employee_shifts`, `scheduled_shifts`, `push_tokens`, `follower_notification_preferences`,
`planned_locations`, `event_booking_requests`, `profiles`, `notifications`, `booking_messages`,
`booking_quotes`, `booking_deposits`, `subscriptions`, `support_tickets`, `order_items` — all via
`mcp__supabase__execute_sql` (SELECT only, no mutations). No code changes, migrations, deploys, or
live Edge Function invocations were performed.
