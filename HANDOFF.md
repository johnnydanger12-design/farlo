# HANDOFF.md — Farlo
_Last updated: Jun 23 2026 — Resend live, LLC docs updated, Android build working. Read time: ~3 min._

---

## Interrupted Task

None — session ended cleanly on Jun 23 2026. No mid-flight work.

---

## Current State

| Feature | Status |
|---|---|
| App Store submission | ✓ Version 1.0 submitted Jun 20 2026 — In Review |
| GitHub repo | ✓ Renamed to `farlo` — johnnydanger12-design/farlo |
| Branding | ✓ All "Good Truck Finder" references purged from source files |
| Stripe live keys | ✓ sk_live in Supabase secrets, pk_live in .env.json, webhook registered |
| RevenueCat production key | ✓ appl_... key in .env.json, bundle ID confirmed com.farlo.app |
| farlo.app | ✓ Privacy, terms, support pages live on Squarespace — LLC info updated |
| Push notification deep-linking | ✓ Fixed — cold-start buffer + role-aware routing |
| Booking confirmation email | ✓ Live — RESEND_API_KEY set, farlo.app domain verified, reply_to set to truck owner |
| Android build | ✓ Release AAB builds clean — signed with farlo-release.keystore |
| Android release keystore | ✓ `android/app/farlo-release.keystore` — password in `android/key.properties` (gitignored) |
| LLC | ✓ Farlo Technologies LLC filed in SC — went live Jun 23 2026 |
| Test accounts | ✓ apple.review@farlo.app (FarloReview2026!) — owner, active sub, full access |
| Screenshot accounts | ✓ 3 accounts (FarloTest123) — Smoky's BBQ, Taylor's Sweet Treats, The Daily Grind |
| Google Play Console | ⚠ Blocked — D-U-N-S number application in progress (filed Jun 23 2026) |
| RevenueCat Google Play | ⚠ Not set up — REVENUECAT_GOOGLE_KEY empty; blocked on Play Console account |
| Background location disclosure | ⚠ Required for Play Store — in-app prominent disclosure not yet built |
| EU/France distribution | ⚠ Excluded from App Store v1 — DSA + encryption docs deferred to v2 |
| EIN | ⚠ Not yet obtained — needed for business bank account and Stripe business update |
| Business bank account | ⚠ Not yet opened — blocked on EIN |
| External account migration | ⚠ Deferred — Supabase, RevenueCat, Claude still under personal Google account |
| farlo.app download buttons | ⚠ href="#" placeholders — update once app is live in App Store |
| Stripe live payment flow | ⚠ Untested end-to-end in production |

---

## Architecture

Flutter + Riverpod 3.x + GoRouter (StatefulShellRoute — owner shell and consumer shell are separate indexed stacks, redirect enforces role). Supabase for auth, Postgres, RLS, realtime, storage, and edge functions. Stripe Connect Express for payments — funds go direct to owner's connected account, Farlo never holds money. FCM push via firebase_messaging plugin on client; server-side uses custom JWT/service-account flow to call FCM API directly (see send-*-notification edge functions). RevenueCat manages subscriptions (iOS live, Android pending). `business_type` ('mobile'|'fixed') on food_trucks drives GPS vs. static address branching. Employees are consumers with truck_employees records. App serves food trucks, cafes, pop-ups, and other independent food businesses — not food trucks only.

---

## Recent Decisions

**Resend email live (Jun 23 2026):** RESEND_API_KEY set in Supabase secrets. farlo.app domain verified in Resend (DKIM + SPF + MX all green). `send-booking-confirmation-email` edge function updated to set `reply_to` to the truck owner's email — customer replies go directly to the vendor, not to Farlo. From address: `bookings@farlo.app`. Also create a `bookings@farlo.app` alias in Google Workspace forwarding to `johnny@farlo.app` so replies to that address don't bounce.

**LLC formed (Jun 23 2026):** Farlo Technologies LLC filed in South Carolina, went live today. ToS and Privacy Policy on farlo.app updated to reflect the registered entity. D-U-N-S number application filed with D&B (Google Developer flow, US, LLC, Managing Member, SIC 7372). Play Console account blocked until D-U-N-S is issued (typically 1-5 business days for the Google-expedited flow).

**Android build working (Jun 23 2026):** Release AAB builds cleanly. Several Gradle issues resolved:
- `add_2_calendar` hardcodes `compileSdkVersion 33` — fixed by overriding all library subprojects to compileSdk 36 in root `build.gradle.kts` (using `afterEvaluate`, skipping `:app` which is already evaluated).
- `sqflite_android 2.4.3` references `Build.VERSION_CODES.BAKLAVA` (API 36) — resolved by bumping the override to 36 (SDK 36 is installed).
- `flutter_stripe 13` pulls in `stripe-android-issuing-push-provisioning` which requires `play-services-tapandpay` (not publicly available — Google Tap and Pay partner program only). Fixed with: (a) Stripe's Maven repo `https://a.stripe-cloud.com/stripe-issuing-android` for `stripe-android-issuing-push-provisioning`, (b) local stub AAR at `android/local-maven/` for `play-services-tapandpay:17.1.2`. Farlo does not use Stripe Issuing — stub is intentional.

**Android release signing:** Keystore at `android/app/farlo-release.keystore`, alias `farlo`, passwords in `android/key.properties` (gitignored). Both files are gitignored. **Back up the keystore file and password externally — losing them means you can never update the Play Store app.** Password is also in `.env.json` under `RESEND_API_KEY`... no wait, it's in `key.properties` only. Store in 1Password.

**Background location (Android):** `ACCESS_BACKGROUND_LOCATION` is intentionally declared. Mobile business owners need to broadcast GPS while the app is backgrounded. Google Play requires a prominent in-app disclosure dialog before requesting this permission — not yet built. Required before Play Store submission.

---

## Traps / Dead Ends

- **SQL-created auth users won't log in** if `raw_app_meta_data`, `raw_user_meta_data`, or token fields are NULL. Must be set explicitly. Also `auth.identities.email` is a generated column — omit from INSERT.
- **`Directory.systemTemp` on iOS** — not writable. Use `getTemporaryDirectory()` from `path_provider`.
- **`Share.shareXFiles` without `sharePositionOrigin`** — crashes on iOS. Always capture RenderBox position BEFORE any `await`.
- **`ownerTruckProvider` for employees** — always null for employees. Use `employeeGoLiveProvider(truckId)` instead.
- **`profiles.display_name`** — correct column. Not `full_name`, not `name`.
- **Stripe webhook `verify_jwt: false`** — Stripe sends no Supabase JWT. Must be false in `config.toml`.
- **GoRouter cold-start race** — `getInitialMessage()` can resolve before the router is built OR before auth loads. Fixed with buffer + dual drain gates.
- **Owner redirect overrides notification routing** — fixed by routing owner-role users receiving consumer notifications to `/owner-notifications`.
- **Base64 encoding large arrays in Deno** — `String.fromCharCode(...new Uint8Array(bytes))` stack overflows. Use `.reduce()`.
- **firebase_options.dart is a stub** — do not run `flutterfire configure` without intending to overwrite it. `projectId: 'good-truck-finder'` is the Firebase project's internal ID — cannot be renamed, leave it.
- **Don't commit `supabase/.temp/`** — not in .gitignore but should be excluded.
- **`flutter_01.png`** in project root — stray screenshot, don't commit it.
- **`play-services-tapandpay` stub** — `android/local-maven/` contains a stub AAR for this Google NFC partner SDK. It satisfies the build graph only; Stripe Issuing push provisioning does not work (not needed). Do not remove it or the Android build will break.
- **Android `afterEvaluate` ordering** — the root `build.gradle.kts` uses `afterEvaluate` in a `subprojects` block but skips `:app` explicitly because `:app` is already evaluated via `evaluationDependsOn`. Do not remove the `project.name != "app"` guard.

---

## Next Steps

1. **Wait for Apple review** — watch email. If rejected, fix same day.
2. **D-U-N-S → Play Console** — D-U-N-S filed Jun 23 2026. Once issued, create Google Play Console account ($25), upload AAB to internal testing track.
3. **Background location disclosure UI** — required before Play Store submission. Prominent dialog before `ACCESS_BACKGROUND_LOCATION` request explaining GPS broadcast feature.
4. **RevenueCat Google Play Billing** — after Play Console is set up: create Android app in RevenueCat, link Google Play, set up subscription products, get `REVENUECAT_GOOGLE_KEY` (goog_...), add to `.env.json`.
5. **Test live Stripe payment** — real booking end-to-end in production.
6. **Update farlo.app download buttons** — replace href="#" once Apple approves.
7. **EIN → business bank account → update Stripe** — in progress behind the scenes.
8. **Migrate external accounts** — after Apple approval: RevenueCat, Supabase, git commit email.
9. **bookings@farlo.app alias** — create in Google Workspace forwarding to johnny@farlo.app so customer booking reply emails don't bounce.

---

## Setup Gotchas

- **`.env.json`** at project root (gitignored). Keys: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `STRIPE_PUBLISHABLE_KEY` (pk_live), `REVENUECAT_APPLE_KEY` (appl_...), `REVENUECAT_GOOGLE_KEY` (empty — pending), `GOOGLE_PLACES_API_KEY`, `GOOGLE_SIGN_IN_WEB_CLIENT_ID`, `RESEND_API_KEY`.
- **Key changes in `.env.json` require full stop + rebuild**, not hot restart.
- **Android release build**: `flutter build appbundle --dart-define-from-file=.env.json` → outputs to `build/app/outputs/bundle/release/app-release.aab`
- **Android keystore**: `android/app/farlo-release.keystore` + `android/key.properties` — both gitignored. Back up externally.
- **Supabase project**: `weflrxyerxpsafcdetya.supabase.co`. Deploy edge functions with `supabase functions deploy <name>`.
- **Stripe Connect**: Platform mode. Live webhook at `https://weflrxyerxpsafcdetya.supabase.co/functions/v1/stripe-webhook`. Events: `payment_intent.succeeded`, `charge.refunded`.
- **`stripe-webhook` must have `verify_jwt: false`** in `supabase/functions/stripe-webhook/config.toml`.
- **Employee flow**: Employees are consumer-role users with `truck_employees` records. Entry point is `employeeGoLiveProvider(truckId)`, not `ownerTruckProvider`.
- **Fixed business address**: Set via Google Places autocomplete. Stored as `address`, `latitude`, `longitude` on `food_trucks`. Never updated by GPS.
- **Realtime**: `orders` table is in `supabase_realtime` publication.
- **Apple review account**: `apple.review@farlo.app` / `FarloReview2026!` — owner role, active subscription set directly in DB, business "Farlo Test Kitchen" (Restaurant, fixed address).
- **Screenshot accounts**: `jwinburndcso@gmail.com`, `taylor.winburn94@gmail.com`, `johnny@peakdesignspace.com` — all password `FarloTest123`, all have active subscriptions and mobile food truck businesses.
- **GitHub remote**: `https://github.com/johnnydanger12-design/farlo`
