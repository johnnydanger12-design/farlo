# Phase 4 — Apple App Store Compliance Review

**Scope:** Farlo, build 1.0.0+5, as of Jul 3 2026. Discovery + written recommendations only — no code, config, or asset changes were made as part of this audit.

---

## 1. Executive Summary

**Submission status (per HANDOFF.md):** Build 1.0.0+5 has been rejected **three times** and is currently **"Waiting for Review"** after a same-day resubmission on Jul 3 for the third rejection (Guideline 2.3, inaccurate metadata). No app binary rebuild was needed for that fix — it was a pure App Store Connect metadata edit (removed "No credit card required to start." from the Description).

**Do the uncommitted working-tree changes touch the submitted binary?** No. HANDOFF.md explicitly states that `lib/core/widgets/background_location_disclosure.dart`, `lib/features/account/widgets/transfer_truck_sheet.dart`, `web/index.html`, and the Android icon/splash changes "were already pending in the working tree from a prior session — left untouched, not part of this commit." The Jul 3 fix required no rebuild. **These uncommitted changes are therefore not present in the binary currently in front of Apple review** — they will only ship in the next build (`+6`). This matters for reconciliation: none of the open uncommitted work can help or hurt the *current* review outcome; it only matters for whatever gets submitted next.

**Overall rejection-risk verdict for the current pending review (1.0.0+5):** **Moderate, but for reasons outside this diff.** The specific issue Apple flagged (the "no credit card required" sentence) has been directly and correctly fixed per Apple's own stated logic (StoreKit always requires a card on file for a trial). However, this review's history shows a pattern: two of the three rejections (2.1(a) broken auth, 2.1(b) IAP not found) were **process/verification failures**, not code defects that static analysis alone would have caught — the code was fine both times, but the *submitted artifact* or *review notes* were not. That pattern is a leading indicator for build `+6`: if `+6` is ever cut from this working tree without re-running the "verify dart-defines embedded" `strings` check (documented in HANDOFF.md's Setup Gotchas) and without re-confirming the demo account's subscription status is `trialing`, the same class of rejection can recur even though the Dart code is correct.

**New issues found in this audit, independent of rejection history:** No crash-reporting SDK anywhere in the app (Sentry/Crashlytics absent) — Apple review crash-tests cold launch and core flows with zero visibility if something breaks on their device. A genuine background-location functional gap on iOS (detailed in §5) where the code advertises background tracking but the permission-request path can never actually obtain the "Always" authorization required for it to work. Zero `Semantics`/accessibility labeling across all 116 Dart files. The marketing site (`farlo-app-web/index.html`) still has two `href="#"` placeholder download buttons — separate from and not addressed by the `web/index.html` uncommitted diff, which is Flutter's own web-build bootstrap file, not the marketing site.

---

## 2. Reconciliation with Known Rejection History

| # | Date | Guideline | Apple's stated reason | Root cause found | Fix applied | Verified in this audit? |
|---|------|-----------|------------------------|-------------------|--------------|--------------------------|
| 1 | Jul 1 | 2.1(a) + 3.1.2(c) | All 4 sign-in methods failed; ToS link missing from Description | `SUPABASE_URL` compiled as empty string into the 1.0.0+4 binary (dart-defines not embedded); `assert()` for config check is stripped in release builds so it failed silently | `main.dart` changed from `assert()` to a real `if`/`throw StateError`; ToS link added to App Description in ASC; Terms/Privacy links added to in-app subscription screen | **Confirmed present.** `lib/main.dart:32-36` now does `if (_supabaseUrl.isEmpty \|\| _supabasePublishableKey.isEmpty) throw StateError(...)` — no assert. `subscription_screen.dart:205-228` (`_LegalLinksRow`) confirmed live, links to `https://farlo.app/terms` and `https://farlo.app/privacy`. |
| 2 | Jul 2 | 2.1(b) | Reviewer "couldn't locate the IAPs" | Reviewer only created a Consumer account (Subscription screen is gated to `user.isOwner`); demo account `apple.review@farlo.app` also had `subscriptions.status='active'`, which would have hidden the purchase button even if used | Demo account reset to `status='trialing'`; App Review Notes rewritten with explicit tap-by-tap navigation | **Cannot verify App Store Connect state directly** (no ASC access in this audit) — but the in-app gating logic that caused the confusion (`Subscription screen gated to isOwner`, no bypass) is confirmed still present in code, meaning **this exact failure mode will recur for any future reviewer who only creates a Consumer account.** The fix is entirely process (review notes + one-time DB update), not a durable code fix. See punch-list item. |
| 3 | Jul 3 | 2.3 | "14-day free trial. No credit card required to start." — false for an IAP subscription | Claim doesn't hold for StoreKit/RevenueCat auto-renewable trials (a card is always required on file) | Line removed from Description; Promotional Text checked and confirmed clean | **Confirmed the underlying code makes no such claim anywhere in-app.** Grepped `lib/` for "no credit card", "credit card required", "free trial" — no in-app UI text repeats the retracted claim (trial-related copy in `subscription_screen.dart:137-153`, `469-473` only says "X days left in your free trial" / "Subscribe to keep full access," accurate and consistent with the corrected metadata). No code-level residue of the rejected claim. |

**Bottom line:** rejections 1 and 3 are durably fixed at the code/metadata level. Rejection 2's underlying *trigger condition* (Subscription screen unreachable without an owner account, and no forcing function in the app itself) is unchanged — only the review notes and a one-time data reset addressed it. If Apple assigns a different reviewer, or the reviewer's account creation on this pass again defaults to Consumer, the same rejection can happen a fourth time. This is not a code bug (gating a paywall to owners is correct product behavior) but it is a standing structural risk this specific app has now been bitten by once.

---

## 3. Findings by Category

### 1. App Store Review Guideline issues generally

**Finding 1.1 — 3.1.1 / 3.1.5: Ad Boost feature does not currently exist in code — no active violation, but the documented plan is a rejection risk when built.**
- Evidence: `grep -rln "boost\|Boost" lib/` returns zero results; no Supabase edge function directory matches `ad`/`boost`/`sponsor`. The feature exists only as a backlog item (per project memory: "Ad Boost — geo-targeted ad slot… flat-rate pricing, web checkout to avoid Apple 30%").
- Files involved: none yet (not implemented).
- Severity: N/A today; **High** if built as currently planned.
- Likelihood of rejection: N/A today (nothing to reject); **Likely** once built, under 3.1.1.
- Recommended action: Before building Ad Boost, get a definitive read on whether it qualifies for any 3.1.1 exemption. A geo-targeted ad slot purchased by a business owner to promote their listing inside the app is a digital feature consumed inside the app — this is squarely inside 3.1.1's "unlock features or functionality within the app" language, and routing payment through a web checkout specifically to avoid Apple's cut is the exact pattern 3.1.1 exists to prevent. The "reader app" exemption (3.1.3(a)) doesn't apply (Farlo isn't primarily consuming previously-purchased content). Physical/real-world-service exemptions (3.1.5) don't apply either — ad placement is a purely digital, in-app-consumed feature. Plan to sell Ad Boost via RevenueCat/StoreKit IAP like the owner subscription, not via external web checkout, unless you get explicit confirmation from Apple (e.g. via a pre-submission inquiry) that it qualifies for an exemption.

**Finding 1.2 — 2.1(b) recurrence risk: Subscription screen is unreachable without an owner account, with no forcing function for reviewers.**
- Evidence: `lib/features/owner_dashboard/screens/subscription_screen.dart` is only reachable via the owner navigation shell; HANDOFF.md confirms "Subscription screen is gated to `user.isOwner`" and that this exact gating caused the Jul 2 rejection.
- Files involved: `lib/features/owner_dashboard/screens/subscription_screen.dart`, routing/shell logic gating owner vs. consumer tabs.
- Severity: High.
- Likelihood of rejection: Possible (mitigated by review notes today, but the underlying trap is unchanged and has already fired once).
- Recommended action: Treat "explicit paywall navigation steps in App Review Notes" as a permanent checklist item for every future submission, not a one-time fix (HANDOFF.md's "General lesson" already says this — make sure it's actually followed for build `+6` and beyond). Consider also (optional, product-level) surfacing a very visible "Have a business? Get listed" entry point directly on the guest/consumer map screen so a reviewer poking around organically is more likely to find the owner flow without needing the notes at all.

### 2. Privacy Manifest (PrivacyInfo.xcprivacy)

**Finding 2.1 — No `PrivacyInfo.xcprivacy` at the Runner app level; only third-party SDKs ship their own.**
- Evidence: `find . -iname "*PrivacyInfo*"` returns 21 hits, **all under `ios/Pods/...`** (RevenueCat, Stripe (multiple modules), Firebase (Core/Messaging/Installations/CoreInternal), GoogleSignIn, GoogleUtilities, GoogleDataTransport, GTMAppAuth, GTMSessionFetcher, AppAuth, PromisesObjC/Swift, nanopb). None exists at `ios/Runner/PrivacyInfo.xcprivacy`.
- Files involved: `ios/Runner/` (missing file), `ios/Pods/*/PrivacyInfo.xcprivacy` (present, third-party).
- Severity: Medium.
- Likelihood of rejection: Possible. Apple's privacy manifest enforcement (since Spring 2024) requires an **aggregate** manifest at the app level declaring the app's own "required reason" API usage (UserDefaults is very likely used indirectly via `shared_preferences`; file timestamp APIs are used by `path_provider`/image caching). Apple's tooling checks the final compiled app, not just whether SDKs individually ship manifests — a top-level `PrivacyInfo.xcprivacy` for the Runner target itself, declaring `NSPrivacyAccessedAPICategoryUserDefaults` (reason `CA92.1` is the common case for `shared_preferences`) is standard practice and its absence has been a real (if inconsistently enforced) source of App Store Connect binary-processing warnings/rejections.
- Recommended action: Add `ios/Runner/PrivacyInfo.xcprivacy` declaring required-reason API usage for `shared_preferences` (UserDefaults, reason `CA92.1`) and any file-timestamp API usage pulled in transitively. Cross-check with `flutter_native_splash`, `image_picker`, `path_provider`, and `cached_network_image` for any additional required-reason APIs they touch that aren't already covered by their own bundled manifests. This is a config-only file addition — no app rebuild logic changes needed, low effort, meaningfully reduces risk on the next submission.

### 3. ATT (App Tracking Transparency)

**Finding 3.1 — No ATT implementation, and none needed.** Confirmed clean.
- Evidence: `grep -rn "NSUserTracking\|AppTrackingTransparency\|app_tracking_transparency" ios/ lib/ pubspec.yaml` → zero hits. `pubspec.yaml` dependencies contain no ad/attribution SDK (no Facebook SDK, AppsFlyer, Adjust, Mixpanel, Amplitude, Segment). The only Firebase packages are `firebase_core` and `firebase_messaging` (push delivery only, not `firebase_analytics`), which does not access IDFA and does not require ATT.
- Severity: N/A (no issue).
- Likelihood of rejection: Unlikely — correctly not implemented because correctly not needed.
- Recommended action: None required today. If Firebase Analytics, any ad network, or an attribution SDK is added later, an ATT prompt (`app_tracking_transparency` package + `NSUserTrackingUsageDescription`) becomes mandatory before that SDK can access IDFA.

### 4. Permissions

Full `ios/Runner/Info.plist` usage-description keys, cross-checked against actual plugin usage in `lib/`:

| Key | Value | Used in code? | Assessment |
|---|---|---|---|
| `NSLocationWhenInUseUsageDescription` | "Farlo uses your location to show nearby food trucks. Truck owners share their live location with customers." | Yes — `geolocator` used throughout (`map_provider.dart`, `dashboard_screen.dart`, `employees_provider.dart`) | Specific, accurate, matches behavior. Good. |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | "Farlo uses your location in the background to keep your truck's position updated for customers while you're serving." | Declared and referenced in `AppleSettings(allowBackgroundLocationUpdates: true)` in `lib/core/location_tracking_service.dart:40-46` | Text is accurate to *intent*, but see Finding 5.1 below — the app never actually completes the flow needed to obtain this authorization level on iOS. |
| `NSCalendarsUsageDescription` / `NSCalendarsFullAccessUsageDescription` / `NSCalendarsWriteOnlyAccessUsageDescription` | "Farlo needs calendar access to add booked events." | Yes — `add_2_calendar: ^3.0.1` in `pubspec.yaml`, used for booking confirmations | Fine, matches usage. |
| `NSPhotoLibraryUsageDescription` | "Farlo needs access to your photo library to let you upload truck photos and logos." | Yes — `image_picker: ^1.1.2` | Fine. |
| `NSCameraUsageDescription` | "Farlo needs camera access to let you take photos of your truck." | Yes — `image_picker` supports camera source | Fine. |
| `NSUserTrackingUsageDescription` | Not present | Correctly absent (no tracking SDK) | Fine — see §3. |
| `NSPushNotificationUsageDescription` | Not present | N/A — this is not a real Info.plist key (push permission doesn't use a usage-description string on iOS); no issue. | Not applicable, no fix needed. |

- Severity: Low (this category is essentially clean).
- Likelihood of rejection: Unlikely on permissions text alone.
- Recommended action: No changes needed to the *text* of these descriptions. The one substantive issue in this area is the Always-location behavioral gap, covered separately in §5 since it's a functional bug, not a copy problem.

### 5. Location

**Finding 5.1 — iOS never actually requests "Always" authorization, so the app's own background-location code path is very unlikely to function on iOS in most real user sessions, despite the app declaring and depending on it.**

This is the single most consequential *new* finding of this audit — it's grounded directly in this codebase's plugin dependency, not generic guidance.

- Evidence chain:
  1. `ios/Runner/Info.plist` declares **both** `NSLocationWhenInUseUsageDescription` and `NSLocationAlwaysAndWhenInUseUsageDescription`.
  2. `lib/core/widgets/background_location_disclosure.dart:30-34` calls `Geolocator.checkPermission()` / `Geolocator.requestPermission()` on **both** platforms as the only permission-request step for iOS (the doc comment at the top of the file states: *"On iOS, skips the disclosure and falls through to Geolocator directly (CoreLocation handles the permission UI natively)."*). No iOS-specific step ever calls anything to escalate to "Always."
  3. The underlying native plugin, `geolocator_apple` (`/Users/johnny/.pub-cache/hosted/pub.dev/geolocator_apple-2.3.13/darwin/geolocator_apple/Sources/geolocator_apple/Handlers/PermissionHandler.m:72-78`), contains this exact branching logic:
     ```objc
     if ([[NSBundle mainBundle] objectForInfoDictionaryKey:@"NSLocationWhenInUseUsageDescription"] != nil) {
       [locationManager requestWhenInUseAuthorization];
     }
     #if !BYPASS_PERMISSION_LOCATION_ALWAYS
     else if ([self containsLocationAlwaysDescription]) {
       [locationManager requestAlwaysAuthorization];
     }
     #endif
     ```
     Because `NSLocationWhenInUseUsageDescription` **is present** in Farlo's Info.plist, the first branch always wins — `requestAlwaysAuthorization` is **never called**, regardless of the fact that the Always description key also exists. `Geolocator.requestPermission()` on iOS, as used by this app, can only ever grant "When In Use."
  4. `lib/core/location_tracking_service.dart:40-46` then unconditionally configures `AppleSettings(..., allowBackgroundLocationUpdates: true)` for every iOS session when a truck owner goes live, regardless of what authorization was actually granted.
  5. Net effect: on iOS, a truck owner who backgrounds the app while "live" will very likely stop transmitting location almost immediately (iOS suspends location delivery to apps without `authorizedAlways` status shortly after backgrounding), even though the in-app disclosure text and the code comment ("iOS: runs in background via UIBackgroundModes + allowBackgroundLocationUpdates") both assert this works.
- Files involved: `ios/Runner/Info.plist`, `lib/core/widgets/background_location_disclosure.dart`, `lib/core/location_tracking_service.dart`.
- Severity: **High.**
- Likelihood of rejection: **Possible.** This isn't guaranteed to trigger a rejection on its own (Apple can't easily observe "did background location silently stop" from outside), but it is exactly the kind of feature-doesn't-work-as-advertised gap that has already burned this app twice on unrelated grounds (2.1(a) auth, 2.1(b) paywall) — and if a reviewer happens to background the app mid-review while testing the "owner goes live" flow and then checks the map from a second account, the truck will appear to vanish, which reads as a functional bug (2.1) rather than a location-policy issue.
- Recommended action: Two options. (a) Simplest and lowest-risk: since Farlo's own architecture note says "fixed businesses show at stored lat/lng, mobile businesses push GPS on open" — reconsider whether "Always" background tracking is actually necessary for the core use case, or whether reliable *foreground* tracking plus a clear "your last known location may be stale after backgrounding" model is sufficient, matching what a lot of similar map apps ship on iOS. This would let you drop `NSLocationAlwaysAndWhenInUseUsageDescription`, drop `UIBackgroundModes: location`, and drop `allowBackgroundLocationUpdates`, which also reduces review scrutiny (Apple applies extra scrutiny to any Always-location + background-mode combination for non-navigation apps). (b) If background tracking must be kept, add an explicit second step after the When-In-Use grant: check `Geolocator.checkPermission()` status, and if it's `LocationPermission.whileInUse` (not `.always`), show a follow-up prompt directing the user to Settings to upgrade to "Always" (mirroring the pattern the Android branch of `background_location_disclosure.dart` already does for `Permission.locationAlways`), and don't set `allowBackgroundLocationUpdates: true` until authorization is confirmed as always. This is a real code fix, not just a copy fix.

### 6. Notifications

**Finding 6.1 — Push permission is requested unconditionally on cold launch with no soft-ask / pre-permission explainer.**
- Evidence: `lib/main.dart:62` calls `PushNotificationService.initialize()` unawaited, immediately after `runApp(...)`. `lib/core/push_notification_service.dart:118-126` calls `FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true)` as the very first thing `initialize()` does — there is no prior in-app screen, dialog, or contextual moment gating this call.
- Files involved: `lib/main.dart:58-62`, `lib/core/push_notification_service.dart:118-131`.
- Severity: Low (not a guideline violation — Apple does not require a soft-ask).
- Likelihood of rejection: Unlikely to cause a rejection by itself, but it is a real UX/approval-optics flag: the very first thing every new user — including an App Review reviewer — sees on a completely fresh install is the native permission dialog, with zero context about why Farlo wants to send notifications. This is the exact pattern Apple's own HIG explicitly discourages ("provide a clear benefit... before requesting permission").
- Recommended action: Move the permission request to a contextual moment (e.g. right after a consumer favorites their first truck, or right after an owner completes onboarding) and add a one-screen or one-sheet soft-ask beforehand explaining the specific benefit ("Get notified when your favorite truck opens nearby"). This is a UX change to `main.dart`/`push_notification_service.dart` call sites, not a permission-copy change.

### 7. Background tasks

**Finding 7.1 — `UIBackgroundModes` declares only `location`, and it is used, but see Finding 5.1 for whether it functions as intended.**
- Evidence: `ios/Runner/Info.plist` — `UIBackgroundModes: [location]`. No `fetch` or `remote-notification` declared, consistent with FCM being used for foreground/standard push only (no silent/background content-available pushes observed in `push_notification_service.dart`).
- Severity: Low (declaration itself isn't over-broad).
- Likelihood of rejection: Unlikely on the declaration itself; the risk is entirely the functional gap in Finding 5.1, not an over-declared/unused mode.
- Recommended action: No change to the *declaration* — it's minimal and matches intended use. Fix the underlying authorization-flow gap (5.1) instead so the declared mode actually does what it claims.

### 8. Crashes

**Finding 8.1 — No crash-reporting SDK anywhere in the app.**
- Evidence: `grep -in "sentry\|crashlytics"` across `pubspec.yaml` and `lib/` returns zero hits. Firebase is present (`firebase_core`, `firebase_messaging`) but `firebase_crashlytics` is not a dependency.
- Files involved: `pubspec.yaml`.
- Severity: **High** (visibility gap, not a guideline violation per se).
- Likelihood of rejection: N/A directly, but this compounds every other finding: given this app has already been rejected three times, twice for issues that were invisible without Apple literally sending back error screenshots (HANDOFF.md: *"Johnny then found the actual screenshots Apple attached... this confirms SUPABASE_URL was compiled as an empty string"*), the team is currently flying blind on any crash that happens on a reviewer's or user's device. If Apple crash-tests build `+6` and it crashes, there will again be zero server-side signal, repeating the exact investigative dead-end documented for the Jul 1 rejection.
- Recommended action: Add `firebase_crashlytics` (trivial addition given Firebase is already configured) or Sentry before the next submission. This is the single highest-leverage investment for reducing time-to-diagnosis on any future rejection, independent of whether it changes review outcomes directly.

**Finding 8.2 — Force-unwraps / `late` usage in critical paths, sampled.**
- Evidence: `grep -rn "!\." lib/features/auth/ lib/features/owner_dashboard/` → 15 matches (not all are true force-unwraps; many are `!=`/method calls, requires manual triage). 40 `late` declarations repo-wide, sampled examples are `TextEditingController` fields initialized in `initState()` (`edit_truck_screen.dart:28-39`, `manage_menu_screen.dart:300-303`) — this is a standard, low-risk Flutter pattern (controllers are always initialized before build), not a crash risk.
- Severity: Low.
- Likelihood of rejection: Unlikely — sampled `late` usage looks conventional and safe. Flagging only because the task requested it; no action needed unless a deeper pass surfaces a `late` field read before assignment.
- Recommended action: No action required from this pass. If crash reports start arriving (once 8.1 is fixed), triage against this list first.

### 9. Missing disclosures

**Finding 9.1 — `farlo.app` marketing site (`farlo-app-web/index.html`) still has two `href="#"` placeholder download buttons — this is a different file from the one touched by the uncommitted `web/index.html` diff.**
- Evidence: `farlo-app-web/index.html:101` (`<a href="#" class="btn-primary">... Download on App Store`) and `farlo-app-web/index.html:105` (`<a href="#" class="btn-secondary">... Get it on Google Play`). Confirmed via `git log` these lines are unchanged since commit `2e24223` (Jun 19) — i.e., this is the actual, long-standing placeholder memory already flagged, and it is **not** what the uncommitted `web/index.html` diff touches. That file (`web/index.html`) is Flutter's own web-app build bootstrap HTML (splash-screen scaffolding for `flutter build web`), a completely different artifact from the marketing site. The uncommitted diff to it only adds blank lines around the Flutter splash-screen boilerplate — no content change, no relation to the download-button placeholders.
- A second near-duplicate copy exists at `website/index.html:117` and `website/index.html:121`, same `href="#"` pattern — unclear if `website/` or `farlo-app-web/` is the one actually deployed to farlo.app; worth confirming only one is live to avoid drift.
- Files involved: `farlo-app-web/index.html`, `website/index.html`.
- Severity: Low (this is the marketing website, not the app binary — does not itself cause an App Store rejection).
- Likelihood of rejection: Unlikely to affect the review directly, but Apple reviewers do sometimes spot-check the app's stated support/marketing URL, and this is a real, live "broken link" a real user would hit before Apple ever approves — currently open per HANDOFF.md's plan ("update once Apple approves"), which is a reasonable sequencing choice.
- Recommended action: Confirm which of `farlo-app-web/` vs `website/` is the deployed site (delete or clearly mark the other to prevent someone updating the wrong one later), and keep the existing plan to wire up real store links once Apple approves. Not urgent before resubmission, but track it — don't let "once Apple approves" silently slip.

**Finding 9.2 — Privacy Policy / Terms of Service links: confirmed present and functional in-app.**
- Evidence: `subscription_screen.dart:205-228` (`_LegalLinksRow`), `background_location_disclosure.dart:154-167` (Privacy Policy link in the disclosure sheet itself, a nice touch), both pointing to `https://farlo.app/terms` / `https://farlo.app/privacy`, matching `farlo-app-web/terms.html` and `farlo-app-web/privacy.html`, which contain real (non-placeholder) legal content, not Lorem ipsum.
- Severity: N/A — clean.
- Recommended action: None. This closes out the Jul 1 rejection's second half correctly.

### 10. Authentication

**Finding 10.1 — Sign in with Apple present and correctly prioritized alongside Google; no 4.8 risk found.**
- Evidence: `lib/features/auth/widgets/social_auth_buttons.dart:54-67` — `SignInWithAppleButton` is rendered **first**, `_GoogleButton` second, both offered on every auth screen that offers social sign-in (confirmed also referenced from `register_owner_screen.dart`). `pubspec.yaml` includes both `sign_in_with_apple: ^6.1.2` and `google_sign_in: ^7.2.0`.
- Severity: N/A — clean, satisfies 4.8.
- Recommended action: None.

**Finding 10.2 — In-app account deletion confirmed, satisfies 5.1.1(v).**
- Evidence: `lib/features/account/screens/account_screen.dart:416-419` ("Delete Account" tile) → `_showDeleteAccountDialog` → `_DeleteAccountDialog` (line 1083+, with an explicit "This is permanent..." warning and a confirmation step) → `authProvider.notifier.deleteAccount()` → `lib/features/auth/repositories/auth_repository.dart:162-166`, which calls a real Supabase edge function `delete-account` (server-side deletion, not a "contact support" workaround) and locally signs out.
- Severity: N/A — clean.
- Recommended action: None required for compliance. Minor suggestion: confirm the `delete-account` edge function actually cascades/purges `food_trucks`, `subscriptions`, `orders`, and Storage objects (avatars, truck photos) server-side, not just the `auth.users` row — worth a quick Supabase-side check (out of scope for this Apple-focused audit, but relevant to 5.1.1(v)'s spirit of full data deletion).

### 11. Subscriptions

**Finding 11.1 — Owner subscription correctly implemented via RevenueCat/StoreKit IAP, with restore-purchases and pre-purchase price disclosure.**
- Evidence: `lib/features/owner_dashboard/screens/subscription_screen.dart` — purchase flow at lines 64-78 uses `purchases_flutter`'s `Purchases` API via `subscriptionProvider.notifier.purchase()`; `_restore()` (lines 80-94) implements Restore Purchases with user-facing feedback; pricing is shown before purchase via `_PricingToggle` (lines 289-378) with a monthly/annual toggle, computed savings %, and a graceful fallback (`_fallbackMonthly`/`_fallbackAnnual`) if RevenueCat hasn't returned live offerings yet; auto-renew/cancellation instructions are platform-aware (`Platform.isIOS ? 'App Store' : 'Google Play'`, line 176 and 195); legal links present (`_LegalLinksRow`).
- Severity: N/A — clean, this whole flow appears to correctly satisfy 3.1.2.
- Recommended action: None for the subscription flow itself. Re-confirm the RevenueCat Apple entitlement/offering config is still correctly attached before `+6` ships (unrelated code risk — HANDOFF.md notes RevenueCat iOS is "Configured," Android is still pending, which doesn't affect iOS review).

**Finding 11.2 — Food/order payments correctly use Stripe Connect (not IAP), and correctly qualify for the physical-goods exemption.**
- Evidence: `lib/features/orders/` — `stripe_connect_screen.dart`, `orders_repository.dart`, `order_cart_sheet.dart` process food orders (physical goods, picked up/served in person) through Stripe Connect Express, with funds going direct to the truck owner (per architecture notes in HANDOFF.md). This is real-world goods/services rendered outside the app, correctly exempt from 3.1.1/IAP under Guideline 3.1.5(a) — Apple explicitly permits marketplace apps facilitating real-world food orders to use non-IAP payment processors (this is the same model Grubhub/DoorDash/Uber Eats use).
- Severity: N/A — clean.
- Recommended action: None. Just be careful this precedent isn't accidentally cited to justify Ad Boost (Finding 1.1) — food orders and ad placements are fundamentally different categories under 3.1, and conflating them is exactly the mistake that gets apps rejected.

### 12. Broken links

**Finding 12.1 — Only the two `farlo-app-web`/`website` download buttons (Finding 9.1) qualify as true placeholder/broken links. No other `href="#"`, empty `Uri.parse('')`, `example.com`, or TODO-style link found.**
- Evidence: `grep -n 'href="#"' web/index.html` → zero hits (confirms `web/` is not the site with the placeholder). Full-repo grep for `example.com`, `Uri.parse('')` (empty string), and similar patterns in `lib/` and `web/` returned nothing beyond what's already covered above.
- Severity: Low.
- Recommended action: See Finding 9.1's recommendation; nothing further found.

### 13. Placeholder content

**Finding 13.1 — No TODO/FIXME/Lorem ipsum/"coming soon" strings found in `lib/`.** Confirmed clean via `grep -rn "TODO\|FIXME\|Lorem ipsum\|coming soon\|Coming Soon" lib/` → zero hits.
- Severity: N/A — clean.
- Recommended action: None. Note for context (not a new finding, already known and intentionally accepted per HANDOFF.md's Traps section): the *marketing website* copy ("Now Available on iOS & Android") is explicitly documented as placeholder-not-launch-status and is deliberately being left alone by the team's own agent (Aiden) until actual launch — this is a known, tracked exception, not an oversight.

### 14. Accessibility

**Finding 14.1 — Zero `Semantics`/`semanticLabel` usage across the entire codebase.**
- Evidence: `grep -rln "Semantics(\|semanticLabel" lib/ --include="*.dart"` → 0 files, out of 116 total Dart files. `FloatingActionButton` used once; 25 files use `SnackBar`/`ScaffoldMessenger` for user feedback (these have no default accessible focus announcement without explicit `Semantics` wrapping, though Flutter's default `SnackBar` does get picked up by VoiceOver reasonably well without extra work). 105 hardcoded `fontSize:` occurrences — worth checking whether any block Dynamic Type scaling (Flutter's default `TextStyle(fontSize:)` still scales with the system text-size setting unless wrapped in `MediaQuery(textScaler: TextScaler.noScaling)`, so this alone isn't necessarily a problem, but a `Semantics` review would be the way to confirm).
- Files involved: repo-wide.
- Severity: Medium.
- Likelihood of rejection: Unlikely to be a standalone rejection reason (Apple's automated/manual review rarely rejects purely for accessibility gaps unless egregious), but worth fixing proactively — Apple has been increasing accessibility scrutiny over time, and zero `Semantics` usage on icon-only buttons (map pin taps, the single FAB, image-only truck cards) means VoiceOver users likely cannot use core flows (map browsing, add-to-cart) at all.
- Recommended action: Not blocking for the current resubmission. As a follow-up (not urgent, but real): audit icon-only interactive elements (map markers, the FAB, image thumbnails acting as buttons) and add `Semantics`/`semanticLabel` to the ~10-15 highest-traffic ones (map pin, add-to-cart button, truck card tap targets) before considering the app accessibility-complete.

### 15. Human Interface Guidelines

**Finding 15.1 — Heavy `SnackBar` usage for feedback that iOS conventionally handles via alerts/toasts; not a violation, just HIG guidance.**
- Evidence: 25 files use `SnackBar`, including for consequential feedback like location-permission-denied (`background_location_disclosure.dart:38-40`, `54-63`) and purchase-restore results (`subscription_screen.dart:85-90`). `FloatingActionButton` used once (Material-first pattern, not idiomatic iOS but common and accepted in cross-platform Flutter apps).
- Severity: Low — not a guideline violation, purely a "feels non-native" note.
- Likelihood of rejection: Unlikely. Apple does not reject for non-native-feeling UI unless it's confusing or broken.
- Recommended action: No action required for submission. Longer-term polish idea only: consider `Platform.isIOS` branches to use `CupertinoAlertDialog`/native-style banners for the highest-visibility moments (permission denials, purchase errors) since the app already does per-platform branching elsewhere (`transfer_truck_sheet.dart`, `subscription_screen.dart` both already check `Platform.isIOS` for copy) — this is a pattern already established in the codebase, just not extended to feedback UI.

### 16. Incomplete functionality

**Finding 16.1 — No dead/unwired screens or non-functional buttons found in the areas sampled (auth, subscription, account, location, transfer-truck).** All flows reviewed (delete account, transfer truck, subscription purchase/restore, location disclosure, social auth) trace through to real backend calls (Supabase edge functions, RevenueCat, Geolocator) with no stubbed-out handlers or `// TODO: implement` gaps.
- Severity: N/A for the sampled areas.
- Recommended action: This audit sampled the areas most relevant to Apple's guidelines (auth, payments, permissions, account lifecycle) rather than every screen in the app; a full click-through QA pass (outside this audit's static-analysis scope) is still the right complement before submitting `+6`, per the existing `verify`-skill-style workflow already used elsewhere in this project.

### 17. App metadata mismatches

**Finding 17.1 — Version numbers are consistent and correctly wired dynamically; no mismatch found.**
- Evidence: `pubspec.yaml:20` → `version: 1.0.0+5`. `ios/Runner/Info.plist` uses `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)` (not hardcoded), confirmed resolved dynamically via `ios/Runner.xcodeproj/project.pbxproj:509,695,718` (`CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)"`). `android/app/build.gradle.kts:42-43` uses `flutter.versionCode` / `flutter.versionName` (also dynamic, sourced from `pubspec.yaml`). All three platforms will report `1.0.0` / build `5` consistently for the currently-submitted binary, matching HANDOFF.md's stated "Current iOS build number: 1.0.0+5." (Non-shipping `RunnerTests` scheme entries hardcode `MARKETING_VERSION = 1.0` / `CURRENT_PROJECT_VERSION = 1` — this is a test target, not the shipped app, no impact.)
- Severity: N/A — clean.
- Recommended action: None; just remember to bump to `+6` for the next build per HANDOFF.md's own instruction, which `pubspec.yaml` currently still shows as `+5` (correct — this hasn't been bumped yet because no rebuild has happened since the metadata-only fix).

**Finding 17.2 — Android launcher-icon change (in the uncommitted working tree) is internally coherent and appears complete; not a build-breaking risk, but is unrelated to and does not affect the current iOS review.**
- Evidence: New adaptive icon setup — `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` references `@color/ic_launcher_background` (newly added `android/app/src/main/res/values/colors.xml`, `#2563EB`) and `@drawable/ic_launcher_foreground` (new PNGs present at all 5 densities: hdpi/mdpi/xhdpi/xxhdpi/xxxhdpi). The 9 deleted `android12splash.png` files are cleanly de-referenced — `git diff` on both `values-v31/styles.xml` and `values-night-v31/styles.xml` shows `android:windowSplashScreenAnimatedIcon` was removed *along with* the deletion (not left dangling), replaced by a solid `windowSplashScreenIconBackgroundColor` (`#2563EB` light, unified from the previous per-theme colors). `grep -rn "android12splash" android/` confirms zero remaining references anywhere. Legacy non-adaptive `mipmap-{h,m,x,xx,xxx}dpi/ic_launcher.png` files are untouched/still present (used as fallback for pre-Android-8 devices, which is correct — adaptive icons need the `mipmap-anydpi-v26` XML for API 26+ *and* the legacy PNGs for older OSes, both present).
- Severity: N/A for the current iOS review (this is 100% Android-scoped: new adaptive launcher icon + simplified splash background color, no iOS assets touched).
- Recommended action: This looks safe to commit as-is from a coherence standpoint. Since it's Android-only, it has zero bearing on the pending iOS 1.0.0+5 review — flagging only so it isn't mistaken for part of the App Store fix when reconciling the diff. Recommend committing it as a separate, clearly-labeled commit from any future iOS-relevant change, and running an actual `flutter build appbundle` locally to confirm the adaptive icon renders correctly before the next Android release (the task's constraints prohibited running that build as part of this audit).

---

## 4. Prioritized Punch List

Ordered by (likelihood of rejection × severity), most urgent first. "Blocks resubmission" = should happen before build `+6` goes to Apple; "Track, not blocking" = real but doesn't need to gate the next submission.

1. **[Blocks next submission's safety margin] Re-verify the dart-defines/config-embedding check and demo-account subscription status before ANY future rebuild.** This isn't a new finding — it's HANDOFF.md's own documented process (the `strings`-on-`App.framework` check, and resetting `apple.review@farlo.app` to `trialing`) — but given two of three rejections trace to exactly these two process gaps, treat both as a hard release-checklist gate, not a "remember to do it" note. (Reconciliation §2.)

2. **[High severity, Possible likelihood] Fix the iOS background-location authorization gap (Finding 5.1).** The app currently cannot obtain the "Always" permission it depends on for its advertised "location shared while backgrounded" feature on iOS — either add the missing second-step Always-upgrade prompt, or scope the feature down to foreground-only and remove the now-unjustified `UIBackgroundModes`/Always-usage-description declarations. This is a real functional bug independently of Apple, and it sits in exactly the risk zone (feature-doesn't-work-as-advertised) that's already burned this app.

3. **[High severity, visibility multiplier] Add crash reporting (Finding 8.1).** Given the pattern of "we couldn't tell what broke without Apple's screenshots," this is the highest-leverage single change for making the *next* rejection (if any) fast to diagnose instead of another multi-day forensic exercise.

4. **[Medium severity, Possible likelihood] Add a Runner-level `PrivacyInfo.xcprivacy` (Finding 2.1).** Config-only, low effort, addresses a real gap in Apple's Spring-2024-onward enforcement that's currently uncovered at the app level (all 21 existing manifests are third-party/Pods-only).

5. **[High severity if/when built, currently N/A] Do not build Ad Boost with external web checkout as currently scoped (Finding 1.1).** Route through RevenueCat/StoreKit IAP like the owner subscription, or get explicit Apple pre-clearance for an exemption, before writing any code for it.

6. **[Structural, Possible recurrence] Keep "explicit paywall navigation steps in App Review Notes" as a permanent per-submission checklist item (Finding 1.2), since the underlying owner-gating structure that caused the Jul 2 rejection is unchanged and correct-by-design — the review notes are the only mitigation.**

7. **[Low severity, Track not blocking] Wire up the real App Store/Play Store links in `farlo-app-web/index.html:101,105` once Apple approves (Finding 9.1)**, and resolve which of `farlo-app-web/` vs `website/` is actually deployed to avoid future drift between the two near-duplicate copies.

8. **[Low severity, UX polish] Move the push-notification permission request off cold-launch and add a soft-ask (Finding 6.1).** Not a rejection risk, but currently the first thing every fresh install — including a reviewer's — sees is an unexplained system permission dialog.

9. **[Medium severity, longer-term] Add `Semantics`/accessibility labeling to the highest-traffic icon-only interactive elements (Finding 14.1)** — map pins, the one FAB, image-tap truck cards. Not urgent for this resubmission, but a real, currently-total gap.

10. **[No action needed, informational] The Android launcher-icon/splash rework in the working tree (Finding 17.2) is coherent and safe to commit — it just has zero relevance to the pending iOS review and shouldn't be conflated with it during reconciliation.**
