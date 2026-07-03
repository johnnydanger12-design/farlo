# HANDOFF.md — Farlo
_Last updated: Jul 3 2026 — Fixed a bug where Aiden's inbox agent re-replied to the same email on 3 separate runs; Build 1.0.0+5 rejected a second time (Guideline 2.1(b), reviewer couldn't find the IAPs) and resubmitted Jul 2; Cowork's scheduled agents replaced with a self-hosted pg_cron + Supabase Edge Function system, plus per-run Anthropic cost tracking added to the weekly brief. Read time: ~4 min._

---

## Interrupted Task

None — session ended cleanly. Build 1.0.0+5 replied-to and resubmitted, status "Waiting for Review" as of Jul 2 afternoon. New agent automation system is live and unattended, one duplicate-reply bug in `agent-aiden-inbox` found and fixed Jul 3.

---

## Current State

| Feature | Status |
|---|---|
| App Store v1.0 | ⏳ Build 1.0.0+5 — rejected twice now. First (Jul 1): broken auth + missing ToS link, fixed. Second (Jul 2, Guideline 2.1(b)): reviewer couldn't locate the IAPs — root cause was the reviewer only ever created a Consumer account, which can never see the Business Owner paywall. Replied to Apple + rewrote App Review Notes with explicit navigation steps, resubmitted same day. Waiting on Apple. |
| Google Play | ✓ Internal testing track — build 2 (1.0.0) |
| Owner onboarding emails | ✓ 3-email sequence live — emails 1 & 2 fire on signup, email 3 via daily pg_cron at day 7 |
| Consumer welcome email | ✓ Single email fires on consumer account creation |
| AI agent system | ✓ Migrated off Claude Cowork (only ran when the desktop app was open/unlocked) to `pg_cron` + Supabase Edge Functions calling the Anthropic API directly — runs 24/7 unattended. All 12 jobs live. See AGENT_AUTOMATION_RUNBOOK.md (current system) — COWORK_AGENT_SETUP.md now describes the retired predecessor. |
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

**Aiden's inbox agent was re-replying to the same email on every run (found + fixed Jul 3):** Johnny reported Aiden kept answering a test email he'd already answered. `agent-aiden-inbox` re-scans `to:aiden@farlo.app newer_than:2d` on every run (7am + 4pm daily) and had no durable record of which threads it had already replied to — it relied entirely on the model reading free-text `supervisor_reports` history and self-judging whether a thread was already handled, and `log_inbox_action` was only ever instructed to be called for directive changes, not for replies. Confirmed via `agent_run_log` that the same thread (`19f2138f24cce1e6`) got a fresh reply on 3 separate runs (Jul 2 7am, Jul 2 4pm, Jul 3 7am) before the model happened to notice its own prior log entry on a 4th run and stop — non-deterministic, not a real fix. Added a new `agent_inbox_replies` table (`thread_id text primary key`, same `service role only` RLS pattern as the other agent tables) and changed the code to filter out already-replied thread IDs *before* the model ever sees them, and to record the thread_id itself the moment `send_reply_to_johnny` sends — no longer a model judgment call. `send_reply_to_johnny`'s tool schema now requires a `thread_id` argument. Deployed via `supabase functions deploy agent-aiden-inbox --no-verify-jwt`. Manually confirmed via a `dry_run=true` invocation (triggered directly through `agent_cron_call('agent-aiden-inbox', true)` in SQL, since `agent_run_log` — not the pg_net response, which timed out client-side at pg_net's 5s cap vs. the function's ~8s runtime — is the reliable way to read a run's outcome) that the stuck thread would have fired again that afternoon, then pre-inserted its thread_id into `agent_inbox_replies` to suppress it immediately rather than waiting for the fix to self-heal on the next run.

**Build 1.0.0+5 rejected again — Guideline 2.1(b), reviewer couldn't find the IAPs (Jul 2):** Apple said they couldn't locate "Owner Monthly Sub, Owner Yearly Sub" etc. anywhere in the app. Traced the in-app paywall path by code (`SubscriptionScreen`, reachable in 3-4 taps from a fresh owner signup, no gating logic hides it, no code path removes the button on empty/failed RevenueCat config) — confirmed the app itself has no bug here. Root cause found by cross-referencing Supabase `auth` logs against `profiles`: exactly one account was created during the review window, from a genuine Apple corporate IP (`17.64.126.135`) via Sign in with Apple, and its `role` is `consumer` — the reviewer never touched the owner side at all, so of course no IAP was visible (Subscription screen is gated to `user.isOwner`). Compounding problem: the demo owner account provided in App Review Information (`apple.review@farlo.app`) had `subscriptions.status = 'active'` (set Jun 19, testing purchase), so even if the reviewer *had* used those credentials they'd land on the "Active / Renews" screen with no purchase button — a second dead end. Fix: (1) reset that demo account's subscription `status` to `trialing` in Supabase (`UPDATE subscriptions SET status='trialing' WHERE owner_id=...`) so it now lands on the real paywall; (2) replied to Apple and rewrote the App Review Notes field with an explicit numbered tap-by-tap path to the Subscription screen (Login → "Have a business? Get listed" → create owner account → Account tab → Subscription), instead of the previous notes which described user types but never said how to navigate to the paywall. Resubmitted Jul 2, status "Waiting for Review."

**General lesson:** with the login wall removed (a deliberate 1.0.0+4 fix — consumer tabs are open to guests), there is no forcing function that pushes an App Review reviewer toward the owner/paywall flow. App Review Notes must now always include explicit step-by-step navigation to any paywall/IAP screen, not just a description of account types — don't assume the reviewer will find the "Have a business? Get listed" link on their own.

**Cost tracking added to Aiden's weekly brief (Jul 2):** Since the new agent system is pay-per-token, `agent_run_log` now captures `input_tokens`/`output_tokens`/`cache_read_tokens`/`web_search_requests`/`model` per run (from the Messages API's own `usage` block). `agent-aiden-supervisor` computes a deterministic per-agent cost estimate from Anthropic's published rates (`_shared/pricing.ts`) and appends it to both the emailed brief and the `supervisor_reports` row, labeled clearly as an estimate, not an invoice reconciliation. Verified live against a real run (53,550 input / 5,267 output tokens ≈ $0.16). Known limitation: each week's figure excludes the cost of generating that week's own brief (the query runs before the current run's tokens are known) — total is consistently a little low, not wildly wrong. Not fixed, documented in AGENT_AUTOMATION_RUNBOOK.md.

**Cowork's scheduled agents replaced with self-hosted `pg_cron` + Edge Functions (Jul 2):** Cowork's scheduled tasks only run when the desktop app is open and the machine unlocked — confirmed through repeated direct testing, not a config issue, which defeats "hands-off automation." Rebuilt all 8 Cowork agents (Aiden Inbox/Supervisor, Sage, Miles, Piper, Email Labeler, Newsletter Cleanup, Stripe Weekly) as Supabase Edge Functions on `pg_cron`, calling the Anthropic API directly. The shared Supabase "brain" (`agent_directives`, `supervisor_reports`, `support_tickets`, `sales_prospects`, `content_queue`) is unchanged — only the execution layer underneath it. Added two new agents with no Cowork equivalent: `agent-urgent-alert` (15-min fast path for `priority=urgent` tickets, previously stuck waiting for the weekly brief) and `agent-run-check` (alerts if an agent stops logging successful runs within its expected window). Gmail access reuses the existing FCM service-account JWT pattern from `send-truck-announcement` for Workspace domain-wide delegation. All 12 jobs are live; Cowork's matching scheduled tasks are disabled (Cowork itself untouched, can be re-enabled as an emergency fallback). Full rollout notes, credential rotation, known gaps, and incident log in **AGENT_AUTOMATION_RUNBOOK.md** — read that before touching any agent function.

**Sage policy change: sends support replies directly instead of drafting for review (Jul 2):** Decided after Sage's judgment proved solid in live testing. Two paths per ticket: `send_reply` (only for questions clearly grounded in `support_kb`, auto-appends an AI-disclosure line, marks ticket `resolved`) or `escalate_to_human` (billing disputes, account deletions, low confidence — sends a warm human-handoff acknowledgment, marks `urgent`, feeds the 15-min alert path). Runs every 5 minutes (was 2x/day) — worst-case response latency dropped from ~18hrs to ~5min. Includes loop/cost protection: `looksAutomated()` skips no-reply/bounce/auto-responder senders entirely, plus a hard 3-message-per-ticket circuit breaker independent of that detection. Reply subjects include a human-readable ticket reference number.

**Two real production bugs found and fixed during live-fire testing (Jul 2):** (1) `escalate_to_human` was writing to a `support_tickets.response_notes` column that only exists on `sales_prospects` (copy-paste mistake) — the `priority=urgent` write silently failed, meaning escalated tickets never reached the urgent-alert path. Fixed by adding a real `escalation_reason` column. (2) The "don't reprocess our own reply" check tested the raw `From` header with a regex anchored to end in `@farlo.app`, but real headers end in `@farlo.app>` (trailing bracket from the display name format) — never matched, so ticket auto-resolution silently never worked since the very first live run. Fixed with a proper `extractEmailAddress()` helper in `_shared/gmail.ts` — general lesson: never test a raw email header with an anchored regex, always extract the address first. Both live-verified after the fix.

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

- **Never trust an LLM agent's own judgment to dedupe "have I already handled this?" across runs — enforce it in code.** `agent-aiden-inbox` relied on the model reading free-text `supervisor_reports` history to decide whether it had already replied to a thread; it re-sent the same reply 3 times before it happened to notice its own log entry. Fixed with a real `agent_inbox_replies` tracking table filtered in code before the model ever sees the thread — same lesson as Sage's `support_tickets.gmail_thread_id` circuit breaker, apply it to any new agent that replies to email.
- **pg_net's `net._http_response` has a 5-second response-capture timeout, independent of the actual HTTP call.** `agent_cron_call()`'s `net.http_post` can time out and leave `content`/`status_code` null in `net._http_response` even though the target edge function ran fine and completed later (confirmed via the edge function logs and `agent_run_log`, both of which showed success). Don't use `net._http_response` to check an agent run's outcome — read `agent_run_log` instead, it's written directly by the function regardless of whether the caller that triggered it is still listening.
- **App Review Notes must give explicit step-by-step navigation to any paywall, not just describe account types** — Apple rejected 1.0.0+5 a second time (2.1(b)) because the reviewer created only a Consumer account (confirmed via Supabase auth logs cross-referenced with `profiles.role`) and never found the owner-only Subscription screen. With the login wall removed, nothing in the app forces a reviewer toward the owner flow — the review notes are the only forcing function. Always spell out the exact taps.
- **Any demo/review account with an already-active subscription hides the purchase flow from reviewers** — `apple.review@farlo.app` had `subscriptions.status='active'` from earlier manual testing, so even a reviewer who did sign in with it would see "Active / Renews," not a purchase button. Keep review demo accounts in `trialing` status, not `active`, so the actual IAP buttons are visible. Reset via `UPDATE subscriptions SET status='trialing' WHERE owner_id=...`.
- **Claude Cowork's scheduled tasks only run when the desktop app is open and unlocked** — confirmed through repeated testing, not a config issue. Don't rely on Cowork for anything that needs to run unattended; use the `pg_cron` + Edge Function system (AGENT_AUTOMATION_RUNBOOK.md) instead.
- **Never test a raw email header (`From`, `To`, etc.) with an anchored regex** — display-name formats like `"Sage | Farlo Support" <support@farlo.app>` don't end where you'd expect (`@farlo.app>`, not `@farlo.app`), so a naive `/@farlo\.app$/` silently never matches. This caused Sage's ticket auto-resolution to silently never work since its first live run. Always extract the address first (`extractEmailAddress()` in `_shared/gmail.ts`), then compare.
- **`btoa()` can't encode non-Latin1 characters** — any Gmail raw-message base64 encoding must UTF-8-byte-encode via `TextEncoder` first, or it throws `InvalidCharacterError` on any en-dash, arrow, or curly quote (i.e. normal LLM-written prose). Fixed in `_shared/gmail.ts`'s `buildRawMessage()`.
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
| `agent_inbox_replies` table (`thread_id text primary key`, `replied_at`) | Jul 3 — durable record of Gmail threads `agent-aiden-inbox` has already replied to, checked in code before a thread is shown to the model. Same `service role only` RLS as the other agent tables. Fixes the duplicate-reply bug. |
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

1. **Watch for Apple review result on 1.0.0+5** — replied to the 2.1(b) rejection + rewrote App Review Notes with explicit paywall navigation steps, resubmitted Jul 2, status "Waiting for Review." If approved, do these IN ORDER before posting anything public:
   - **Wipe all test data** — Supabase dashboard → Authentication → Users → select all → Delete (cascades to profiles, food_trucks, subscriptions, etc.). Do NOT wipe: agent_directives, content_queue, supervisor_reports, sales_prospects, agent_run_log. Every current account is a test account — wipe everything, nothing to preserve. This includes `apple.review@farlo.app`, whose subscription status was reset to `trialing` on Jul 2 for review purposes — no action needed, it gets wiped with everything else.
   - Update farlo.app download buttons (href="#" → App Store link).
   - Lift the `sales_targets` HOLD directive so Miles starts real outreach — watch its first live `agent_run_log` entry and actual Gmail drafts before trusting it fully unattended (see Known Gaps in AGENT_AUTOMATION_RUNBOOK.md).
2. **RevenueCat Android — finish:** In RevenueCat, retry the credentials refresh (Google permissions take up to 24hrs). Once green: Product catalog → Products → add `com.farlo.app.owner.sub.monthly` + `com.farlo.app.owner.sub.yearly` → attach to `premium` entitlement → attach to Default Offering. Copy the `goog_...` API key → add to `.env.json` as `REVENUECAT_GOOGLE_KEY` → `flutter build appbundle --dart-define-from-file=.env.json`.
3. **Background location declaration** — Play Console → Policy → App content → fill out the background location permission form.
4. **Watch the agent automation system for its first week live** — check `agent_run_log` for failures periodically (AGENT_AUTOMATION_RUNBOOK.md → Checking logs). Re-enable the matching Cowork task as an emergency fallback if anything looks wrong; Cowork itself hasn't been removed, only paused.
5. **Promote Android to production** — once Apple approves and RevenueCat Android is live, promote internal testing AAB to production track.
6. **Stripe business update** — update Stripe account with EIN + business bank account. Google Play merchant account also needs a bank account added (Payments profile → Add payment method).
7. **Canva integration for Piper (optional, deferred)** — Piper currently ships copy-only content with `needs_asset: true` flagged. Canva's API requires per-user OAuth with rotating refresh tokens, real ongoing maintenance risk for something unattended — worth a dedicated follow-up if wanted, not a quick add.

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
- **AI agents:** Run on `pg_cron` + Supabase Edge Functions (not Cowork — see AGENT_AUTOMATION_RUNBOOK.md for the current system, checking logs, pausing a job, rotating credentials). All context still lives in Supabase `agent_directives` table. Foundation rows (`locked=true`): brand_guidelines, company_story, product_flows_owner, product_flows_consumer, website_content. Operational rows (`locked=false`): farlo_context, company_direction, marketing_focus, sales_targets, support_kb. Aiden manages operational rows; never touch locked rows without updating them directly in Supabase.
