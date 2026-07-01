# HANDOFF.md — Farlo
_Last updated: Jul 1 2026 (afternoon) — Build 1.0.0+5 uploaded, processed, and resubmitted to Apple for review after 1.0.0+4's rejection (broken auth + missing ToS link). Read time: ~3 min._

---

## Interrupted Task

None — session ended cleanly. Build 1.0.0+5 is with Apple for review.

---

## Current State

| Feature | Status |
|---|---|
| App Store v1.0 | ⏳ Build 1.0.0+5 resubmitted Jul 1 — fixes the 1.0.0+4 rejection (broken auth + missing ToS link). Waiting on Apple. |
| Google Play | ✓ Internal testing track — build 2 (1.0.0) |
| Owner onboarding emails | ✓ 3-email sequence live — emails 1 & 2 fire on signup, email 3 via daily pg_cron at day 7 |
| Consumer welcome email | ✓ Single email fires on consumer account creation |
| AI agent system | ✓ All 4 agents configured — Aiden/Sage/Miles/Piper. See COWORK_AGENT_SETUP.md |
| RevenueCat iOS | ✓ Configured — entitlement `premium`, monthly + yearly products |
| RevenueCat Android | ⚠ Partially set up — Play Console products created, service account uploaded, waiting for Google permissions propagation (up to 24hrs) |
| Background location declaration | ⚠ Required before Play Store production — Policy → App content in Play Console |
| farlo.app download buttons | ⚠ href="#" placeholders — update once Apple approves |
| EIN / Stripe business update | ⚠ In progress |

---

## Architecture

Flutter + Riverpod 3.x + GoRouter (StatefulShellRoute — owner and consumer shells are separate indexed stacks). Supabase for auth/Postgres/RLS/realtime/storage/edge functions. Stripe Connect Express for payments (funds go direct to owner). FCM push via custom service-account JWT in edge functions. RevenueCat manages subscriptions (iOS live, Android pending). `business_type` ('mobile'|'fixed') drives GPS vs. stored address logic — fixed businesses show at their stored lat/lng, mobile businesses push GPS on open. **Farlo is a small business platform, not just food trucks** — design all features for any small food business type (pop-ups, brick and mortar, caterers, etc.).

---

## Recent Decisions

**Build 1.0.0+4 rejected, root cause found, Build 1.0.0+5 fixed (Jul 1):** Apple rejected on two guidelines. **Guideline 2.1(a):** all four sign-in methods (Apple, Google, email, new account creation) failed with an error on every attempt. Initial investigation (Supabase `auth.audit_log_entries` showed zero requests during the review window, REST/Storage/Realtime worked fine in the same window, code review of all 4 auth paths found nothing, and a from-scratch reproduction on a matching iPad Air 11" M3 / iPadOS 26.5 simulator with the current codebase worked perfectly) initially pointed to a possible fluke on Apple's end. Johnny then found the actual screenshots Apple attached to the rejection, which showed the real error: `AuthRetryableFetchException(message: Invalid argument(s): No host specified in URI /auth/v1/token?grant_type=password, statusCode: null)`. This confirms `SUPABASE_URL` was compiled as an **empty string** into the submitted 1.0.0+4 binary — every `_supabase.auth.*` call built a URI with no host, failing instantly client-side before any network request was made (explaining the zero server-side log entries). Root cause of *why* it was empty is unconfirmed — Johnny reports he ran the documented `flutter build ipa --dart-define-from-file=.env.json` command, so this may have been a one-off archive/upload mixup rather than a process bug. Fix: verified `.env.json` is correct, rebuilt 1.0.0+5 with the same command, and confirmed via `strings` on the compiled `App.framework/App` binary inside the IPA that the correct Supabase URL and publishable key are actually embedded before allowing upload — do this verification step on every future release build, since Xcode gives no warning when dart-defines are missing. Also hardened `main.dart`: the old `assert()` config check was silently stripped in release builds (the reason this shipped unnoticed) — replaced with a real `if`/`throw` that fails loudly in every build mode. Added 20s timeouts + friendlier error messages to all 4 auth flows and a 10s timeout around `Purchases.configure()` as defense-in-depth, though these weren't the root cause. **Guideline 3.1.2(c):** Privacy Policy URL was already correctly set in App Store Connect (App Privacy page) — only the Terms of Use link was missing from the App Description, which Johnny added directly in ASC (no app rebuild needed for that half). Also added visible Terms of Use / Privacy Policy links to the in-app subscription screen as extra insurance.

**Build 1.0.0+4 submitted (Jun 30):** Apple rejected build 3 for Guideline 2.1 (IAPs not submitted) and 5.1.1 (login wall). Build 4 fixes both: IAPs attached to submission, and all login wall issues resolved — consumer tabs fully open to guests, sign-out lands on `/map`, "Browse as guest" link on login screen, cart gated at "Add to Bag" (centralized in `_tryAddToCart`). Also fixed a crash in guest→truck profile→Add to Bag→Sign In→Browse as guest flow (`Future.microtask` for `CartNotifier.clear()` in dispose). Test trucks moved to Infinite Loop, Cupertino (~37.3318, -122.0300). Build 4 is "Waiting for Review" as of Jun 30 evening. Apple reviewers always create their own accounts via Apple Sign-In private relay, never use the `apple.review@farlo.app` test account. Known reviewer accounts: "Edward Wood" (owner) and "John Apple" (consumer), both created Jun 30.

**AI agent system deployed (Jun 30):** 4 Cowork scheduled agents — Aiden (Supervisor, Mon 6am), Sage (Support, daily 9am+3pm), Miles (Sales, Mon/Wed/Fri 8am), Piper (Marketing, Tue/Thu 9am). All agent context stored in Supabase `agent_directives` table with two tiers: `locked=true` rows (brand_guidelines, company_story, product_flows_owner, product_flows_consumer, website_content) are permanent and set by Johnny; `locked=false` rows (farlo_context, company_direction, marketing_focus, sales_targets, support_kb) are managed by Aiden weekly. Aiden reads farlo.app/terms/privacy every Monday and updates `website_content`. Nothing auto-sends — Sales saves Gmail drafts, Support saves Gmail drafts, Marketing writes to `content_queue` table. Only Aiden sends directly (weekly brief to johnny@farlo.app). Full setup in `COWORK_AGENT_SETUP.md`.

**prospect-businesses edge function tested (Jun 30):** Hartsville SC returned 117 food businesses, 52 new prospects added to `sales_prospects`. Chain filtering handled via agent directive — Aiden flagged ~10 chains (Burger King, Sonic, etc.) and updated Miles's directives to skip them. Miles also skips any prospect where no contact email can be found (sets `response_notes='No email found - worth manual outreach'`).

**Canva brand kit created (Jun 30):** https://www.canva.com/brand/kAGpfS3ZJUg — stored in `brand_guidelines` directive so Piper uses it automatically.

**Owner onboarding email sequence (Jun 29):** 3 emails. Email 1 (immediate) and Email 2 (48hr Resend scheduled_at) fire from `send-owner-onboarding-emails` edge function, triggered by DB trigger on `subscriptions` INSERT/UPDATE. Email 3 (day 7) is a separate `send-owner-day7-checkin` edge function called by pg_cron daily at noon UTC — it checks `food_trucks.has_ever_opened` and sends either a growth email or a "you're not live yet" nudge depending on the result.

**Trigger fires on 'trialing' not just 'active' (Jun 29):** The RevenueCat webhook upserts subscriptions on conflict `owner_id`. New owners get a row inserted with `status='trialing'` directly at signup in `auth_repository.dart` — before any RevenueCat event. The original trigger only fired on `status='active'`, meaning trial users got zero onboarding emails for 14 days. Fixed: trigger WHEN clause is `status IN ('trialing', 'active') AND onboarding_emails_sent_at IS NULL`. The `onboarding_emails_sent_at` guard (stamped by the trigger before calling the edge function) prevents duplicate sends when trial later converts to active.

**Email 3 moved out of Resend scheduled_at (Jun 29):** Originally scheduled via Resend's `scheduled_at` at signup time, making it impossible to branch on `has_ever_opened`. Moved to pg_cron batch pattern (matching `check-open-businesses`) so it can check live DB state at day 7.

**Consumer welcome email (Jun 29):** Single email, no sequence. Triggers on `profiles` INSERT where `role = 'consumer'`. Includes "Start a Business" CTA at the bottom (Account → Manage Account → Start a Business) as a soft owner conversion pitch.

**Email sender config (Jun 29):** All emails — from: `Johnny at Farlo <support@farlo.app>`, reply_to: `support@farlo.app`. Logo at `https://weflrxyerxpsafcdetya.supabase.co/storage/v1/object/public/brand/Email%20Logo.png` in footer of all emails.

**"Multi-truck" renamed to "multi-business" (Jun 29):** Farlo is not just a food truck app. Feature backlog and all future design should use "multi-business" framing — covers restaurant groups, vendors with multiple stands, caterers with storefronts, etc.

**Fixed location behavior clarified (Jun 29):** Fixed businesses toggle open/closed without GPS — their pin shows at whatever lat/lng was stored at signup. Map query filters `is_open=true AND is_active=true AND latitude IS NOT NULL AND longitude IS NOT NULL` — closed businesses of any type disappear from the map entirely. Fixed businesses can't edit their location post-onboarding (v2 backlog).

---

## Traps / Dead Ends

- **`assert()` for required config is stripped in release builds** — `main.dart` used to `assert()` that `SUPABASE_URL`/`SUPABASE_PUBLISHABLE_KEY` were non-empty. Asserts no-op in `--release`/`--profile`, so a release archive built without `--dart-define-from-file` launches fine and only fails deep inside auth calls, with server-side logs showing nothing (the request never leaves the device — fails client-side building the URI). This is exactly what caused the 1.0.0+4 Apple rejection. Now a real `if`/`throw StateError` that fails loudly in every build mode. If you ever revert this to an `assert`, this bug can recur silently.
- **Before uploading any iOS release build, verify the dart-defines actually got embedded** — Xcode/Flutter give no warning if they didn't. After `flutter build ipa`, run: `unzip -oq build/ios/ipa/Farlo.ipa -d /tmp/ipa_check && strings /tmp/ipa_check/Payload/Runner.app/Frameworks/App.framework/App | grep weflrxyerxpsafcdetya`. Should print several `https://weflrxyerxpsafcdetya.supabase.co/...` lines. If empty, the dart-defines were dropped — do not upload.
- **When Apple rejects with a vague bug report ("displayed errors"), ask for the actual screenshots/text before spending much time reproducing blind** — a from-scratch reproduction on a matching device/OS can genuinely work fine (correct code, correct env) while the actual *submitted binary* was still broken for an unrelated build/packaging reason. Server-side log absence is a strong clue (client-side failure, request never sent) but the exact error text is what actually cracks it.
- **`agent_directives` locked rows must never be overwritten by Aiden** — `locked=true` rows are set by Johnny and are permanent. Aiden's prompt explicitly says only UPSERT `locked=false` rows. If an agent seems to have wrong brand/product context, check the locked rows in Supabase first.
- **farlo.app shows "Now Available on iOS & Android" — this is placeholder copy**, not launch status. Aiden reads the website every Monday; his `website_content` directive includes a note about this so he doesn't flag it as a launch signal every week.
- **Apple reviewers use Apple Sign-In with private relay emails** — they never use `apple.review@farlo.app`. Known reviewer accounts: "Edward Wood" and "John Apple" (both created Jun 30 with `@privaterelay.appleid.com` emails). Edward Wood (owner) is in Miles's email sequence — that's expected.
- **`owner_subscriptions` table doesn't exist** — it's called `subscriptions`.
- **Resend `scheduled_at` can't be made conditional** — can't cancel or branch a pre-scheduled email after the fact. Use pg_cron + edge function for any day-N email that needs to check live DB state before sending.
- **`onboarding_emails_sent_at` is stamped by the DB trigger, not the edge function** — if you call the edge function directly (e.g. for testing), the column won't be stamped. That's intentional for test purposes but be aware real accounts called directly bypass the guard.
- **Trial users don't get onboarding emails if trigger only checks `status='active'`** — subscriptions are inserted as `'trialing'` at signup, 14 days before any RevenueCat event. Trigger must include `'trialing'`.
- **day-7 cron must filter `status IN ('trialing', 'active')`** — at day 7 of a 14-day trial, status is still `'trialing'`, not `'active'`. Filtering only `'active'` misses all trial users.
- **`play-services-tapandpay` stub** — `android/local-maven/` contains a stub AAR. Do NOT remove or Android build breaks.
- **`firebase_options.dart` is a stub** — `projectId: 'good-truck-finder'`. Do not run `flutterfire configure`.
- **GoRouter cold-start race** — `getInitialMessage()` can fire before router or auth. Fixed with buffer + dual drain gates in `PushNotificationService`.
- **Employee CalendarScreen** — employees must use `Navigator.push` with `CalendarScreen` directly. Pushing `/dashboard/calendar` via GoRouter lands them in the owner shell.
- **MainActivity must be FlutterFragmentActivity** — was FlutterActivity. Stripe throws PlatformException on Android init without this.
- **SQL-created auth users won't log in** if `raw_app_meta_data` or token fields are NULL.

---

## Modified Files (This Session)

| File | Change |
|---|---|
| `lib/main.dart` | Config-missing check changed from `assert()` (stripped in release) to a real `if`/`throw`. `Purchases.configure()` wrapped in a 10s timeout + try/catch so it can never block app launch. |
| `lib/features/auth/providers/auth_provider.dart` | Added a 20s `.withAuthTimeout` extension, applied to all 6 auth entry points (email sign-in/up, owner sign-up, Apple/Google sign-in, Apple/Google owner sign-up). |
| `lib/features/auth/screens/login_screen.dart` | Replaced raw `error.toString()` with a `_friendlyError()` mapper (timeout, invalid credentials, email not confirmed, network). |
| `lib/features/auth/screens/register_screen.dart` | Same `_friendlyError()` pattern for signup (timeout, already-registered, network). |
| `lib/features/auth/screens/register_owner_screen.dart` | Added a `timeout` case to its existing `_friendlyError()`. |
| `lib/features/auth/widgets/social_auth_buttons.dart` | Added a `timeout` case to its existing `_friendlyError()`. |
| `lib/features/owner_dashboard/screens/subscription_screen.dart` | Added a `_LegalLinksRow` (Terms of Use / Privacy Policy) below the auto-renew disclosure text. |
| `pubspec.yaml` | Bumped to 1.0.0+5 |

Note: `lib/core/widgets/background_location_disclosure.dart`, `lib/features/account/widgets/transfer_truck_sheet.dart`, `web/index.html`, and the Android icon/splash changes were already pending in the working tree from a prior session — left untouched, not part of this commit.

---

## DB Changes (This Session)

| Change | Purpose |
|---|---|
| `agent_directives` table | Key-value store for all agent context. `locked` column separates foundation (Johnny-owned) from operational (Aiden-managed) rows. 10 rows seeded. |
| `content_queue` table | Piper writes content here; Johnny sets status='posted'/'skipped'. Replaces marketing-queue.md. |
| `supervisor_reports` table | Aiden writes weekly brief here and emails to johnny@farlo.app. Replaces supervisor-report.md. |
| RLS on all 3 agent tables | `USING (false)` — service role only, same pattern as support_tickets and sales_prospects |
| `support_tickets` table | Sage reads/writes — ticket tracking with gmail_thread_id for threading |
| `sales_prospects` table | Miles reads/writes — 52 Hartsville prospects seeded |
| `subscriptions.onboarding_emails_sent_at TIMESTAMPTZ` | Guard: prevents duplicate welcome sequence on renewal |
| `subscriptions.onboarding_email3_sent_at TIMESTAMPTZ` | Guard: prevents day-7 email firing twice |
| Trigger `on_subscription_onboarding_eligible` | AFTER INSERT OR UPDATE on subscriptions, WHEN `status IN ('trialing','active') AND onboarding_emails_sent_at IS NULL` |
| Trigger `on_consumer_profile_created` | AFTER INSERT on profiles, WHEN `role='consumer'` |
| pg_cron `send-owner-day7-checkin` | Runs daily at noon UTC |
| `GOOGLE_PLACES_API_KEY` Supabase secret | Server-side Places API key — no app restrictions, restricted to Places API only |

---

## Known Issues

| Issue | Severity |
|---|---|
| RevenueCat Android credentials not yet validated | Medium — Play Console products created, service account JSON uploaded to RevenueCat, permissions granted in Play Console. Google permissions propagation can take up to 24hrs — retry refresh in RevenueCat tomorrow. Then add products to entitlement, get `REVENUECAT_GOOGLE_KEY`, add to `.env.json`, rebuild AAB. |
| Background location declaration form | Medium — required before Play Store production. Policy → App content in Play Console |
| Fixed business can't edit location post-onboarding | Low — manual DB fix workaround. v2 backlog |
| Entity name in Apple account still "JOHNNY DEE WINBURN" | Low — contact Apple Support to change to Farlo Technologies LLC |
| farlo.app download buttons are href="#" placeholders | Low — update once Apple approves |

---

## Next Steps

1. **Watch for Apple review result on 1.0.0+5** — uploaded, processed, and resubmitted Jul 1. If approved, do these IN ORDER before posting anything public:
   - **Wipe all test data** — Supabase dashboard → Authentication → Users → select all → Delete (cascades to profiles, food_trucks, subscriptions, etc.). Do NOT wipe: agent_directives, content_queue, supervisor_reports, sales_prospects. Every current account is a test account — wipe everything, nothing to preserve.
   - Update farlo.app download buttons (href="#" → App Store link).
   - Tell Aiden in a Cowork chat to flip all agents to launch mode.
   - Activate the 4 Cowork scheduled tasks.
2. **RevenueCat Android — finish:** In RevenueCat, retry the credentials refresh (Google permissions take up to 24hrs). Once green: Product catalog → Products → add `com.farlo.app.owner.sub.monthly` + `com.farlo.app.owner.sub.yearly` → attach to `premium` entitlement → attach to Default Offering. Copy the `goog_...` API key → add to `.env.json` as `REVENUECAT_GOOGLE_KEY` → `flutter build appbundle --dart-define-from-file=.env.json`.
3. **Background location declaration** — Play Console → Policy → App content → fill out the background location permission form.
4. **Activate Cowork agents** — don't start scheduled tasks until app is live. When ready, run Aiden first (he seeds `website_content`), then the other three. Full instructions in `COWORK_AGENT_SETUP.md`.
5. **Promote Android to production** — once Apple approves and RevenueCat Android is live, promote internal testing AAB to production track.
6. **Stripe business update** — update Stripe account with EIN + business bank account. Google Play merchant account also needs a bank account added (Payments profile → Add payment method).

---

## Setup Gotchas

- **`.env.json`** at project root (gitignored). Keys: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `STRIPE_PUBLISHABLE_KEY` (pk_live), `REVENUECAT_APPLE_KEY` (appl_...), `REVENUECAT_GOOGLE_KEY` (empty until Android set up), `GOOGLE_PLACES_API_KEY`, `GOOGLE_SIGN_IN_WEB_CLIENT_ID`.
- **iOS build:** `flutter build ipa --dart-define-from-file=.env.json` → IPA at `build/ios/ipa/Farlo.ipa`. **Before uploading, verify the config actually got embedded** (see Traps/Dead Ends above) — 1.0.0+4 shipped with an empty Supabase URL and Apple rejected it for completely broken auth.
- **Open in Transporter:** `open -a Transporter "/Users/johnny/Desktop/Good Truck Finder/build/ios/ipa/Farlo.ipa"`
- **Current iOS build number:** 1.0.0+5, in review with Apple as of Jul 1. Next iOS build use `+6`.
- **Android release:** `flutter build appbundle --dart-define-from-file=.env.json` → `build/app/outputs/bundle/release/app-release.aab`. Requires `android/app/farlo-release.keystore` + `android/key.properties` (both gitignored — back up externally).
- **Supabase project:** `weflrxyerxpsafcdetya.supabase.co`. Deploy edge functions: `supabase functions deploy <name> --no-verify-jwt`.
- **Firebase project:** internal ID `good-truck-finder` (cannot be renamed). `firebase_options.dart` is a stub — do not run `flutterfire configure`.
- **Stripe webhook:** `https://weflrxyerxpsafcdetya.supabase.co/functions/v1/stripe-webhook` — must have `verify_jwt: false`.
- **Test accounts:** `apple.review@farlo.app` / `FarloReview2026!` (owner, active sub). `jwinburndcso@gmail.com` / `Farlo26!` (owner). `johnny.danger12@gmail.com` (consumer). All others: `FarloTest123`.
- **GitHub:** `https://github.com/johnnydanger12-design/farlo`
- **Google Play Console:** play.google.com/console — account under `johnny@farlo.app`. App ID: `4973234026077565344`.
- **Farlo Technologies LLC:** EIN 42-3336763, incorporated South Carolina Jun 22 2026 via ZenBusiness.
- **Brand assets:** Logo for emails at `https://weflrxyerxpsafcdetya.supabase.co/storage/v1/object/public/brand/Email%20Logo.png`. Canva brand kit: `https://www.canva.com/brand/kAGpfS3ZJUg`.
- **AI agents:** All context in Supabase `agent_directives` table. Foundation rows (`locked=true`): brand_guidelines, company_story, product_flows_owner, product_flows_consumer, website_content. Operational rows (`locked=false`): farlo_context, company_direction, marketing_focus, sales_targets, support_kb. Aiden manages operational rows; never touch locked rows without updating them directly in Supabase.
