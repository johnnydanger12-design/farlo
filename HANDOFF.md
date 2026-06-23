# HANDOFF.md — Farlo
_Last updated: App Store submitted, live keys swapped, push routing fixed, booking email added. Read time: ~2 min._

---

## Interrupted Task

None — session ended cleanly on App Store submission (Jun 20 2026). No mid-flight work.

---

## Current State

| Feature | Status |
|---|---|
| App Store submission | ✓ Version 1.0 submitted Jun 20 2026 — Waiting for Review (24-48hr) |
| Stripe live keys | ✓ sk_live in Supabase secrets, pk_live in .env.json, webhook registered |
| RevenueCat production key | ✓ appl_... key in .env.json |
| farlo.app | ✓ privacy, terms, support pages live on Squarespace |
| Push notification deep-linking | ✓ Fixed — cold-start buffer + role-aware routing |
| Booking confirmation email | ✓ Edge function deployed, awaiting RESEND_API_KEY + domain setup |
| Subscription gate snackbars | ✓ showCloseIcon: true added — users can dismiss without upgrading |
| Map popup overflow | ✓ Fixed — long addresses now truncate with ellipsis |
| Test accounts | ✓ apple.review@farlo.app (FarloReview2026!) — owner, active sub, full access |
| Screenshot accounts | ✓ 3 accounts (FarloTest123) — Smoky's BBQ, Taylor's Sweet Treats, The Daily Grind |
| RESEND_API_KEY | ⚠ Not set — booking emails silently skip |
| EU/France distribution | ⚠ Excluded from App Store v1 — DSA + encryption docs deferred to v2 |

---

## Architecture

Flutter + Riverpod 3.x + GoRouter (StatefulShellRoute — owner shell and consumer shell are separate indexed stacks, redirect enforces role). Supabase for auth, Postgres, RLS, realtime, storage, and edge functions. Stripe Connect Express for payments — funds go direct to owner's connected account, Farlo never holds money. FCM push via custom JWT/service-account flow (no FlutterFire messaging plugin — see push_notification_service.dart). RevenueCat manages iOS subscriptions. `business_type` ('mobile'|'fixed') on food_trucks drives GPS vs. static address branching. Employees are consumers with truck_employees records.

---

## Recent Decisions

**Push notification deep-linking overhaul:** Replaced fragile 300ms one-shot retry with a proper buffer pattern. `_pendingMessage` holds cold-start notifications; `onRouterReady()` (called from router.dart when `_sharedRouter` is set) and `onAuthResolved()` (called from app_shell.dart when auth settles) both attempt to drain it — only fires when BOTH are ready. Also added `_isOwner` flag so owner-role users receiving consumer-type notifications (e.g. announcements, booking_accepted) route to `/owner-notifications` instead of hitting the owner redirect and landing on `/dashboard`.

**Booking confirmation email uses Resend:** No email service was previously configured. Chose Resend (simple REST API, standard for Supabase edge functions). Function fails gracefully with `{ sent: false, reason: 'no_resend_key' }` if key not set — won't surface errors to users. From address is `bookings@farlo.app` — requires domain verification in Resend dashboard before emails actually send.

**ITSAppUsesNonExemptEncryption added to Info.plist:** Prevents Apple's encryption compliance dialog from appearing on every future build. App only uses standard HTTPS/TLS via OS networking stack — qualifies as non-exempt.

**App Store submitted without EU:** DSA (Digital Services Act) trader info required for all EU App Store territories. Skipped for v1 — user deferred to v2. Availability set to all countries except EU. Info.plist encryption fix means v2 build won't need the compliance dialog for France either.

**Test account subscription set manually via SQL:** apple.review@farlo.app was created through the app (normal flow), then subscription status was manually updated to 'active' with `current_period_end = NOW() + 1 year` so Apple's reviewer has full access without going through RevenueCat sandbox.

**3 screenshot accounts created via SQL:** Auth users can be created directly via SQL (auth.users + auth.identities + profiles + food_trucks + subscriptions). Critical: must set `raw_app_meta_data = '{"provider":"email","providers":["email"]}'` and `raw_user_meta_data` with sub/email/email_verified — without these, login silently fails. Also token fields (confirmation_token, recovery_token, etc.) must be empty string `''` not NULL.

---

## Traps / Dead Ends

- **SQL-created auth users won't log in** if `raw_app_meta_data`, `raw_user_meta_data`, or token fields are NULL. Must be set explicitly — see recent decisions above.
- **`Directory.systemTemp` on iOS** — not writable. Use `getTemporaryDirectory()` from `path_provider`.
- **`Share.shareXFiles` without `sharePositionOrigin`** — crashes on iOS. Always capture RenderBox position BEFORE any `await`.
- **`ownerTruckProvider` for employees** — always null for employees. Use `employeeGoLiveProvider(truckId)` instead.
- **`profiles.display_name`** — correct column. Not `full_name`, not `name`.
- **Stripe webhook `verify_jwt: false`** — Stripe sends no Supabase JWT. Must be false in `config.toml`.
- **GoRouter cold-start race** — `getInitialMessage()` can resolve before the router is built OR before auth loads. The 300ms retry was insufficient. Fixed with buffer + dual drain gates.
- **Owner redirect overrides notification routing** — owners navigated to consumer routes (`/notifications/my-requests`) get redirected to `/dashboard`. Fixed by routing owner-role users receiving consumer notifications to `/owner-notifications` instead.
- **Base64 encoding large arrays in Deno** — `String.fromCharCode(...new Uint8Array(bytes))` stack overflows. Use `.reduce()`.
- **`auth.identities.email` is a generated column** — cannot insert it directly. Omit from INSERT; it's derived from `identity_data`.

---

## Modified Files (this session)

| File | Change |
|---|---|
| `lib/core/push_notification_service.dart` | Full rewrite of tap routing — buffer pattern, role-aware routing, `onRouterReady` + `onAuthResolved` drain gates |
| `lib/router.dart` | Added `PushNotificationService.onRouterReady()` call after `_sharedRouter` is assigned |
| `lib/app_shell.dart` | Added `PushNotificationService.onAuthResolved(user)` in auth listener to drain pending notifications |
| `lib/features/owner_dashboard/screens/dashboard_screen.dart` | Added `showCloseIcon: true` to 2 subscription gate snackbars |
| `lib/features/employees/screens/employees_screen.dart` | Added `showCloseIcon: true` to subscription gate snackbar |
| `lib/features/map/widgets/truck_bottom_sheet.dart` | Wrapped address Text in `Flexible` — fixes right overflow on long addresses |
| `ios/Runner/Info.plist` | Added `ITSAppUsesNonExemptEncryption = false` — bypasses encryption compliance dialog on all future builds |
| `supabase/functions/send-booking-confirmation-email/index.ts` | New — HTML email via Resend; accepts booking_id, fetches truck name, sends to contact_email |
| `farlo-app-web/privacy.html` | Added `<style>` block with mobile-responsive CSS for Squarespace Code Block |
| `farlo-app-web/terms.html` | Same as privacy.html |
| `farlo-app-web/support.html` | New — support page with iOS + Android cancel instructions, responsive CSS |
| `farlo-app-web/app-store-metadata.md` | Updated Support URL to `mailto:support@farlo.app` |

---

## Known Issues

| Issue | Severity |
|---|---|
| RESEND_API_KEY not set — booking confirmation emails silently skip | Medium — run `supabase secrets set RESEND_API_KEY=re_...` after Resend setup |
| bookings@farlo.app not verified as Resend sender domain | Medium — blocks emails even when key is set |
| EU territories excluded from App Store | Low — DSA trader info required; fill out in App Store Connect → App Information |
| Stripe live payment flow untested end-to-end | Low — webhook registered but real booking payment not verified in production |
| No LLC formed | Low — ToS and Privacy Policy note this; update both docs once formed |
| farlo.app download buttons are href="#" placeholders | Low — update once app is live in App Store |

---

## Next Steps

1. **Wait for Apple review** — watch email. If rejected, fix same day. Common first-rejection reasons: missing demo video, sign-in credentials not working, subscription not testable.
2. **Set up Resend** — create account at resend.com → add farlo.app domain → verify DNS → copy API key → `supabase secrets set RESEND_API_KEY=re_...`
3. **Test live Stripe payment** — make a real booking payment end-to-end; confirm webhook fires and `payment_status` updates correctly in Supabase.
4. **EU expansion (v2)** — complete DSA trader info in App Store Connect → App Information → add EU territories to Pricing and Availability.
5. **Update App Store download buttons on farlo.app** — replace href="#" placeholders with real App Store link once approved.

---

## Setup Gotchas

- **`.env.json`** at project root (gitignored). Keys: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `STRIPE_PUBLISHABLE_KEY` (pk_live), `REVENUECAT_APPLE_KEY` (appl_...), `GOOGLE_PLACES_API_KEY`, `GOOGLE_SIGN_IN_WEB_CLIENT_ID`.
- **Key changes in `.env.json` require full stop + rebuild**, not hot restart.
- **Supabase project**: `weflrxyerxpsafcdetya.supabase.co`. Deploy edge functions with `supabase functions deploy <name>`.
- **Stripe Connect**: Platform mode. Live webhook at `https://weflrxyerxpsafcdetya.supabase.co/functions/v1/stripe-webhook`. Events: `payment_intent.succeeded`, `charge.refunded`.
- **`stripe-webhook` must have `verify_jwt: false`** in `supabase/functions/stripe-webhook/config.toml`.
- **Employee flow**: Employees are consumer-role users with `truck_employees` records. Entry point is `employeeGoLiveProvider(truckId)`, not `ownerTruckProvider`.
- **Fixed business address**: Set via Google Places autocomplete. Stored as `address`, `latitude`, `longitude` on `food_trucks`. Never updated by GPS.
- **Realtime**: `orders` table is in `supabase_realtime` publication.
- **Apple review account**: `apple.review@farlo.app` / `FarloReview2026!` — owner role, active subscription set directly in DB, business "Farlo Test Kitchen" (Restaurant, fixed address).
- **Screenshot accounts**: `jwinburndcso@gmail.com`, `taylor.winburn94@gmail.com`, `johnny@peakdesignspace.com` — all password `FarloTest123`, all have active subscriptions and mobile food truck businesses.
