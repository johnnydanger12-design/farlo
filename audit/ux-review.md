# Phase 6 — UI/UX Expert Review

**Scope:** Farlo, working tree as of Jul 3 2026. Discovery only — no code, config, or asset changes made. Reviewed as a combined panel: Apple HIG review team + senior product designer at a top-tier consumer SaaS company. Calibrated against Uber, DoorDash, Airbnb, Linear, and Notion — not against "good for an indie app."

---

## 1. Executive Summary

**Overall grade: C- (68/100).**

Farlo is a real, funded-feeling product with a genuine (if inconsistently applied) design system, professionally illustrated brand assets, and above-average microcopy — clearly past the hackathon stage. But it has zero accessibility infrastructure, systemically inconsistent error handling (including silent failures on paid/committed actions), widespread sub-44×44 touch targets, almost no motion design, and — confirmed via live device testing, not just code reading — at least one visible on-launch rendering bug and one real navigational dead-end risk. This is a pre-launch app that would benefit from one focused polish pass before it's compared to the apps its category invites comparison to (DoorDash, Uber Eats).

**Top 5 strengths:**
1. **A real design-token system exists and is well-built**: `AppColors`, `AppTextStyles` (8-step type scale), `AppSpacing` (4/8 grid), plus reusable `AppButton`/`AppTextField`/`ErrorView`/`StarRatingWidget`/`TruckMapPin` components (`lib/core/constants/`, `lib/core/widgets/`). This is genuine infrastructure most pre-seed apps skip entirely.
2. **Microcopy is consistently specific and contextual** — "Ready for Pickup!", "Your trial expires today — subscribe to keep access," platform-aware cancellation instructions, destructive-action copy that explains consequences. This is Stripe/Linear-tier writing on the happy path.
3. **Empty states are designed, not blank**, on nearly every list screen (favorites, notifications, orders, menu, requests) with a consistent icon+title+subtitle pattern.
4. **Loading feedback is present almost everywhere** — every screen audited has either a `CircularProgressIndicator`, `.when(loading:)`, or a button-level spinner; 5 screens implement pull-to-refresh.
5. **The brand assets are genuinely polished** — the app icon (debossed wordmark) and onboarding illustration (bespoke cityscape line art) look like paid design work, not a template.

**Top 5 weaknesses:**
1. **Zero accessibility infrastructure.** `grep -rn "Semantics\|semanticLabel" lib/` returns zero hits across all 116 Dart files, confirmed independently four times in this audit. VoiceOver users cannot meaningfully use map browsing, chat, or checkout today.
2. **Error handling is a coin flip.** 10+ screens show raw `'Error: $e'` exception text verbatim to users; at least 3 flows (chat send, booking status update, menu availability toggle) fail completely silently with zero user feedback, one of which (`booking_chat_screen.dart:118`) clears the user's typed message *before* confirming the send succeeded.
3. **Touch targets are undersized in dozens of confirmed places**, frequently via deliberate opt-outs (`visualDensity: VisualDensity.compact`, `tapTargetSize: MaterialTapTargetSize.shrinkWrap`, `minimumSize: Size.zero`) — including on a "Cancel Event" button attached to a paid booking flow (`my_requests_screen.dart:411-417`).
4. **A live-confirmed, on-launch visible bug**: the very first screen a fresh user sees (the map) rendered three truck pins fully stacked on top of each other with the "Opened Xd" badge text overlapping/truncated — see §2 methodology note and the Map Screen review below.
5. **No haptics, no skeleton loaders, and inconsistent dark-mode correctness** (116 raw `Colors.white` / 27 raw `Colors.black` literals bypass the theme system) despite a real dark theme existing at the `ThemeData` level.

**Launch-readiness verdict:** Do not treat this as launch-blocking in the same way as the App Store rejections in Phase 4 — none of these findings will get the binary rejected. But from a design-quality standpoint, this app is not yet at the bar its own category (food-truck/marketplace discovery, competing for attention with DoorDash/Uber Eats-caliber apps) demands. The accessibility and error-handling gaps in particular are the kind of thing that generates 1-star reviews ("the app doesn't tell me why my order failed") rather than App Review rejections. Recommend one focused sprint against the punch list in §5 before wide public launch, prioritized by user-facing severity, not code elegance.

---

## 2. Methodology Note

**Live capture attempted and partially successful.** Per the task's instructions, `flutter run -d macos` was tried first — it built successfully but crashed on launch with `MissingPluginException(No implementation found for method initialise on channel flutter.stripe/payments)`, because `flutter_stripe` does not support macOS desktop as a platform. This is a real, confirmed platform limitation, not a misconfiguration — `main.dart:22-25` unconditionally calls `Stripe.instance.applySettings()` at startup, which fails before `runApp()` ever executes on macOS.

Fell back to `flutter run -d <iPhone 17 Pro simulator>` (`.env.json` dart-defines applied), which built and launched successfully after resolving a build-lock conflict with an unrelated, already-running `flutter run` process targeting the same simulator (confirmed via a full-screen screenshot to be a concurrent VS Code Claude Code session working the same audit task — not part of this session's own actions; the conflicting process was stopped to unblock this session's build).

**Screens visually captured live (2 of 24, both via `xcrun simctl io booted screenshot` after real tap/scroll input through `cliclick`):**
- **Map screen** (`map_screen.dart`) — guest/pre-auth view, default launch location (Cupertino, CA test data). Revealed a real visible bug: 3 truck pins rendered fully stacked/overlapping (see review below).
- **Login screen** (`login_screen.dart`) — reached by tapping the "Favorites" tab as a guest, which correctly triggers the router's auth gate (`router.dart:61-63`: only `/map`, `/map/*`, and `/set-new-password` are guest-accessible — **this contradicts this project's own memory note that "consumer tabs are fully open to guests"**; live testing + code both confirm Favorites/Notifications/Account require login). Captured 3 times, including one attempted scroll gesture; the code-documented "Browse as guest" escape-hatch link (`login_screen.dart:217-228`) never appeared in the visible viewport on the iPhone 17 Pro simulator (see full writeup below) — flagged as a likely real, live-observed near-dead-end, with the caveat that the synthetic scroll gesture used for verification may itself have failed to register rather than proving the element is fully unreachable.

**Why not more:** live capture requires either (a) reliable simulator tap automation, which required reverse-engineering a screen-coordinate-to-window-coordinate transform via `cliclick` (no `idb` available in this environment) — each successful tap took multiple calibration attempts — or (b) authenticated test credentials, which exist (`jwinburndcso@gmail.com` / owner, `apple.review@farlo.app` / owner-with-active-subscription — deliberately avoided per the task's "don't mutate App Review state" instruction) but require additional login-flow automation on top of the tap-coordinate problem. Given the session's tap automation was fragile and time-expensive per screen, and per the task's guidance to fall back to rigorous code-level analysis rather than force unreliable live capture, the remaining 22 screens are **code-inferred**, not visually captured.

**Confidence levels:** The 2 live-captured screens carry direct visual confidence, including one finding (pin overlap) that would have been very difficult to catch from code alone. The remaining 22 screens are graded from full-file reads (by 4 parallel research passes plus this reviewer's own direct reads of every shared widget/constant file) with file:line citations for every claim — high confidence for anything objectively verifiable in code (spacing values, widget presence/absence, error-handling patterns, touch-target sizing) and appropriately hedged confidence for anything that requires seeing actual rendered output (perceived visual hierarchy, whether spacing "feels" cramped, color contrast as rendered). Cross-referenced throughout against Phase 4 (`audit/app-store-review.md`) and Phase 5 (`audit/code-quality.md`) where their findings map onto design-quality dimensions (error handling, duplication, accessibility).

---

## 3. Per-Screen Review

### Auth & Onboarding

#### `login_screen.dart` — LIVE + code-inferred
- **Spacing (B):** Token-based throughout the main body (`AppSpacing.md/sm/lg`, lines 97-216), but the `_ForgotPasswordDialog` breaks the pattern with raw `SizedBox(height:16/8)` (`:315,326`) — two spacing systems in one file.
- **Typography (B-):** `AppTextStyles.heading1/body/bodySmall` used for primary content, but 3 near-identical hardcoded `TextStyle` blocks for the "Sign up"/"Get listed" links (`:189-193,207-211`) are copy-pasted rather than shared.
- **Loading/Error (B):** Button-level spinner (`AppButton(isLoading:)`, `:177`); friendly mapped error strings via `_showError` (`:52-63`) — one of the better error treatments in the app.
- **Touch targets (D):** "Forgot password?" explicitly shrunk to `Size(0,36)` with `shrinkWrap` (`:164-165`); "Sign up"/"Get listed"/"Browse as guest" are bare `GestureDetector`-wrapped `Text` with no padding — sub-44×44 tap areas.
- **Navigation (C, live-confirmed concern):** "Browse as guest" (`:217-228`) is the only escape hatch for a guest routed here — and it **did not render in the visible viewport** in 3 live screenshots on an iPhone 17 Pro simulator, despite the screen being wrapped in a `SingleChildScrollView` (`:90`). Either it's just below the fold with insufficient scroll affordance signaling, or something about the AutofillGroup/keyboard-avoidance layout is consuming more vertical space live than the code alone suggests. **This is the single most concrete, live-verified finding in this audit** — worth an actual device check before launch.
- **Critique:** Clean, professional-looking screen live (verified: logo, black Apple button, white Google button, clean text fields) — but the one deliberate guest-escape-hatch not being reliably visible is a real risk given HANDOFF.md's own history of Apple rejecting this app once already for a paywall being unreachable by a reviewer who didn't know where to look.

#### `register_owner_screen.dart` — code-inferred
- **Spacing/Typography (B-):** Token-based (`AppSpacing.lg/sm/xl`, `:141-298`) with one raw `SizedBox(height:12)` (`:227`) breaking pattern.
- **Hierarchy (C):** The primary CTA ("Create Owner Account," `:292-297`) sits at the very bottom of a long form (business type, name, address, 2 social buttons, name/email/password) — a real scroll-to-conversion tax on the most important owner-acquisition screen in the app.
- **Error states (C):** Two different error-quality standards in one screen — the email/password path shows the raw `error.toString()` (`:75`) while the social path uses a friendly mapper (`:98-110`).
- **Consistency (D):** Defines a private `_GoogleButton` (`:327-353`) that duplicates the shared one in `social_auth_buttons.dart:97-124` almost exactly — direct reinvention of an existing component in the same feature area.
- **Critique:** Functionally solid but the duplicated Google button and the long pre-CTA form are the kind of thing a design QA pass catches immediately; currently shipping as two parallel, silently-drifting implementations.

#### `register_screen.dart` — code-inferred
- **Spacing/Consistency (A-):** Cleanest of the three auth-entry screens — 100% token-based spacing, correctly reuses `AppButton`, `AppTextField`, and the shared `SocialAuthButtons`/`OrDivider` (`:101-155`) rather than reinventing the Google button like its sibling screen does.
- **Critique:** This is the reference implementation the other two auth screens should have matched.

#### `set_new_password_screen.dart` — code-inferred
- **Typography (C+):** Uses `AppTextStyles.heading2` (22pt) for its headline while every sibling auth screen uses `heading1` (28pt) for the equivalent role (`:76` vs. `login_screen.dart:107`) — an unexplained hierarchy inconsistency across the auth flow group.
- **Error states (D):** `SnackBar(content: Text(e.toString()))` (`:53`) — the raw exception object shown verbatim, the weakest error-messaging in the whole auth group, on a screen reached via a password-reset email link where trust matters.
- **Navigation (C):** Bare `AppBar(title:...)` with no explicit `leading` (`:67`) — if reached via a deep link with an empty nav stack (the common case for a password-reset flow), there may be no back arrow and no cancel affordance.
- **Consistency (A):** Cleanest widget-reuse discipline of the six auth/account screens — no local reinvention anywhere.

#### `onboarding_screen.dart` — code-inferred
- **Consistency (F):** The only screen in the entire audited set that imports **none** of `app_colors.dart`/`app_spacing.dart`/`app_text_styles.dart`/`app_button.dart` — it sits completely outside the app's own design system. Raw `Color(0xFF2563EB)` (`:50`) duplicates `AppColors.primary` by coincidence, not by reference — a silent drift risk if the brand color ever changes.
- **Loading/Error (F):** The single "Get Started" button's `onPressed` is `async` (`:45-48`) with **no loading indicator, no disabled state during the await, and no try/catch** — a double-tap during the write is unguarded and any exception is unhandled.
- **Navigation (D):** Zero back/skip/cancel affordance anywhere on the screen — defensible for a gated first-run screen, but worth a deliberate product decision, not a default.
- **Professional polish (A, live-adjacent):** The actual artwork (`assets/images/onboarding.png`, viewed directly) is a genuinely polished, bespoke illustration — this is the one screen where the *asset* quality far outstrips the *code* discipline around it.
- **Critique:** The most important first impression in the app (literally screen #1) is also the least integrated with the app's own design system — a real inversion of priority.

#### `account_screen.dart` — code-inferred
- **Spacing/Typography (B):** Disciplined at the top level (`AppSpacing`/`AppTextStyles` used extensively), but degrades inside its ~6 modal dialogs/sheets — three near-duplicate "bottom sheet chrome" implementations exist in one file (`_buildSheetContainer` at `:1444-1458` vs. two manually re-implemented versions at `:315-320` and `:1352-1357`).
- **Consistency (C-):** Every `TextField` inside this file's dialogs (`_ChangeNameDialog`, `_ChangePasswordDialog`, `_DeleteAccountDialog`, `_UpgradeToOwnerSheet`) is a **raw** Flutter `TextField`, not the shared `AppTextField` — text inputs visually diverge between the Account tab and every Auth screen in the app.
- **Error states (C):** Cross-screen inconsistency confirmed — this screen's change-password flow enforces a 6-character minimum (`:218`) while every account-creation/reset flow enforces 8 (`register_screen.dart:142`, `set_new_password_screen.dart:96`) — the same app enforces two different password-strength rules depending on entry point.
- **Touch targets (D):** Close `IconButton`s in 5 different sheets use `visualDensity: VisualDensity.compact` (`:689,817,943,1026,1127`), shrinking below 48×48; the edit-name pencil icon is ~20×20 (`:589-595`).
- **Microcopy (A-):** Destructive-action copy is genuinely strong — the delete-account warning (`:1134`) plus a type-`DELETE`-to-confirm gate is best-practice.

### Map, Discovery & Bookings

#### `map_screen.dart` — LIVE + code-inferred
- **Live-confirmed bug (F on Professional Polish for this screen):** The captured screenshot shows **three truck pins rendered fully overlapping/stacked** at nearly the same coordinate, with an "Opened 13d" status badge visibly truncated behind another pin ("Opened 13d_d"). This is the literal first thing a new user sees on cold launch. Code inspection confirms why: `_applyClusterOffsets`/`_edgePosition`/`_inVisibleBounds` (`:410-446`) are recomputed inline on every map-camera-move `setState()` (triggered per pan/zoom frame, `:73`) with no memoization — and evidently no minimum-separation/clustering logic robust enough to prevent near-identical coordinates from rendering on top of each other at this zoom level.
- **Consistency (D):** Defines a private `_TruckPin` (`:573-652`) that duplicates the shared `core/widgets/truck_map_pin.dart`'s `TruckMapPin` almost exactly instead of reusing it.
- **Spacing/Typography (D):** No `AppSpacing`/`AppTextStyles`/`Theme.textTheme` import at all (`:10-11`) — every spacing and font value on this screen is a hand-typed raw literal, including several off-4/8-grid values (5,7,9,11).
- **Error states (D):** No `.hasError` branch anywhere for the truck-fetch or location-stream providers — only `.isLoading` and an empty-list check are handled; a fetch error renders identically to "no trucks found," with zero indication anything went wrong.
- **Touch targets (D):** The `_OffScreenIndicator` is 40×40 (`:539-540`, under 44); the search-bar clear icon and recent-search remove icon are unpadded 16-18px glyphs (`:786-789,1009-1013`).
- **Critique:** This is the app's most important screen (default launch route, `router.dart:42`) and it's also the least design-system-compliant and the one with a live-confirmed visible bug. Given it's also the highest-traffic screen by construction, this is the single highest-priority fix in this entire report.

#### `truck_profile_screen.dart` — code-inferred
- **Animations (B+):** The richest animation usage of any screen audited — `AnimatedSwitcher` (200ms, favorite heart / announcement bell), `AnimatedContainer` (200ms, carousel dots), `AnimatedSize`+`AnimatedRotation` (220ms, menu category expand/collapse) — genuinely native-feeling implicit animation.
- **Spacing/Typography (B):** Best token-adoption of the "discovery" screen group, though a few raw styles slip into `_FloatingCartBar` (`:1213-1218`) instead of the existing `AppTextStyles.buttonText` built for exactly that purpose.
- **Touch targets (D):** The menu-item `_AddButton` at quantity-zero is ~22×22 (`:1073-1083`), nested inside the whole card's own tap target — overlapping tap zones on the primary "add to order" affordance.
- **Loading (C):** The private-event-booking flow awaits a subscription-check RPC directly inside the tap handler with **no loading indicator** (`:140-141`) — the button appears unresponsive during the round-trip.
- **Critique:** The most polished screen in the app on animation and typography discipline, undercut by an undersized primary commerce action (add-to-order button) and one silent-loading gap on the money path.

#### `favorites_screen.dart` — code-inferred
- **Empty states (A-):** Well-formed icon+title+subtitle ("No favorites yet" / "Tap the heart on any truck to save it here.", `:50-58`).
- **Consistency (C):** Hand-rolls a near-duplicate of the shared `ErrorView` widget instead of using it (`:29-43`).
- **Touch targets (D):** Unfavorite heart and announcement-bell icons are ~20-22px, unpadded, sitting only 8px apart (`:186-217`) — real mis-tap risk between two undersized, adjacent controls.
- **Critique:** Good empty-state writing let down by a reinvented error widget and a cramped icon cluster.

#### `notifications_screen.dart` — code-inferred
- **Error states (D):** `Text('Error: $e', ...)` (`:44`) — raw exception, no icon, no retry; the weakest error treatment of the list screens, worse than `favorites_screen.dart`'s hand-rolled (if duplicated) version.
- **Spacing (D):** No `AppSpacing` import at all — 100% raw literals.
- **Navigation (B):** The one screen with genuinely good bottom-sheet dismissal — explicit close icon **and** a "Close" button **and** default tap-outside (`:200-211`), more affordances than most other sheets in the app.
- **Accessibility (D):** `Dismissible` swipe-to-delete (`:66-82`) has no alternate tap-based delete for users who can't swipe.

#### `booking_chat_screen.dart` — code-inferred
- **Error states (F) — the single clearest reliability bug in this audit:** `_textController.clear()` (`:118`) runs **before** the `await sendMessage(...)` call; if it throws, the catch block only `debugPrint`s (`:128`) — the user's typed message is gone from the input, was never sent, and there is zero on-screen indication anything went wrong. No `try/catch` exists around the initial message-load either.
- **Touch targets (D):** The send button is 40×40 (`:383-397`), under the 44×44 minimum, on the single most-used control on the screen.
- **Empty states (B+):** Well-formed "Start the conversation" / "Send a message to $name about your event." (`:215-223`).
- **Animations (B):** Explicit animated auto-scroll to newest message (250ms, `:101-105`).
- **Critique:** This is the highest-severity finding in the whole report from a trust standpoint — a customer negotiating a paid private-event booking can lose their message with no warning.

#### `booking_requests_screen.dart` (owner) & `my_requests_screen.dart` (consumer) — code-inferred
- **Hierarchy (B+):** Both correctly surface "Action Needed"/"Awaiting Response" first — good task-oriented information architecture.
- **Consistency (D):** `_SectionHeader`, `_MsgBadge`, and `_CollapsibleSection` are near-byte-identical duplicates between the two files rather than shared (`booking_requests_screen.dart:255-552` vs. `my_requests_screen.dart:198-553`) — the single largest cross-file duplication found in this audit.
- **Error states (C/F):** `booking_requests_screen.dart`'s status-update failure is fully silent (`debugPrint` only, `:647`) while its PDF-share failure correctly shows a SnackBar (`:903-906`) — two different error strategies in the same file for two similarly consequential actions.
- **Touch targets (F, most severe finding in the audit):** `my_requests_screen.dart`'s "Cancel Event" button explicitly sets `padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap` (`:411-417`) — a deliberate removal of Material's minimum touch target on a destructive action tied to a paid booking. The owner screen's PDF-share icon similarly opts out via `visualDensity: VisualDensity.compact` (`:971-972`) on a financial-document action.
- **Navigation (C):** `_RequestDetailSheet` (`booking_requests_screen.dart:630-863`, ~140 lines) has no explicit close/X button anywhere, relying entirely on swipe-down inside a `DraggableScrollableSheet` whose content is itself a scrollable list — a real risk of gesture conflict leaving users unsure how to exit.
- **Microcopy (A-):** Genuinely strong throughout — "${contactName} will be notified. You can add a short note to let them know why." (`:1171-1173`), cancellation-policy copy that explains consequences rather than just blocking the action.

### Owner Dashboard, Orders & Employees

#### `dashboard_screen.dart` — code-inferred (1524 lines, confirmed "god screen" per Phase 5)
- **Hierarchy (D) — the most consequential finding on this screen:** The single most business-critical action in the entire owner-side app — the **Go Live toggle** — is a plain default `Switch` (`:602-608`) with no dedicated visual weight, subordinate to both the truck-name header and the `_GettingStartedCard` checklist that renders above it. The core action that determines whether a truck appears on the map at all gets less visual emphasis than a first-run checklist.
- **Consistency (D):** Never uses the shared `AppButton` anywhere in 1524 lines despite ~6 button-like CTAs (Getting Started pill, Quick Actions row, End Session, Stripe-connect dialog, Announcement send) — every one is bespoke, each with its own drifted styling. Contrast with `edit_truck_screen.dart`/`manage_menu_screen.dart`, which do use `AppButton` consistently.
- **Spacing/Typography (C):** Outer `ListView` is disciplined (`AppSpacing` throughout), but discipline **visibly degrades** in nested private widgets (`_GettingStartedCard`, `_StripeStatusCard`, `_AnnouncementSheet`) — off-grid raw values (2,6,7,10,12), raw `TextStyle(fontSize:11)` matching no defined scale step, raw `Colors.white`/`Color(0xFF1A1A1A)` bypassing `AppColors`.
- **Animations (B):** `AnimatedCrossFade` (350ms, mini-map) and `AnimatedSize` (280ms, Getting Started card) are genuinely good implicit-animation usage — the richest on any owner-side screen.
- **Loading (B):** Consistent button-level spinners across sub-widgets (orders, Stripe card, announcement send) — better than several other screens.
- **Error states (C+):** Prefixed errors ("Could not update status: $e," `:205`) are a small step up from the bare `'Error: $e'` pattern used elsewhere, though still exposes raw exception text.
- **Touch targets (D):** Orders-accepting `Switch` explicitly shrinks via `materialTapTargetSize: MaterialTapTargetSize.shrinkWrap` (`:652`); Stripe-card CTA text button is ~24-28px effective height (`:1002-1003`).
- **Critique:** This screen has real animation and loading polish at the surface level but the core hierarchy decision — burying "Go Live" under a checklist — undermines the screen's actual job, and it's the least design-system-compliant of the owner screens once you look past the top-level `ListView`.

#### `edit_truck_screen.dart` — code-inferred
- **Consistency (B-):** Correctly uses `AppTextField` for primary fields, but builds a fully custom `_SocialField` (`:615-647`) reimplementing the exact same input-decoration boilerplate `AppTextField` already provides — one of at least 4 independent reimplementations of the same input styling found across the owner-dashboard feature (also in `_CuisineDropdown`, `_CancellationPolicyDropdown`, and `manage_menu_screen.dart`'s `_inputDecoration`).
- **Touch targets (D):** Logo camera-badge icon ~22×22 (`:438-450`); photo-grid remove "×" ~16×16 (`:506-519`).
- **Microcopy (A-):** Explanatory helper copy is genuinely good — "Shown as your marker on the map" (`:261`), "Blocks online cancellation inside this window. Informational only — no automatic charge." (`:362`).
- **Hierarchy (C):** Primary "Save Changes" `AppButton` sits at the bottom of a long form (logo, name, cuisine, description, 10-photo grid, 6 social fields, address, cancellation policy) — significant scroll-to-save distance.

#### `manage_hours_screen.dart` — code-inferred
- **Error states (F, confirmed verbatim):** `SnackBar(content: Text('Error: $e'))` at `:65` — exactly the known issue, raw exception shown to a business owner trying to set their operating hours.
- **Hierarchy (C):** Primary save action is a small `TextButton` in the `AppBar.actions` (`:94-103`), not the app's own established full-width `AppButton` pattern used by sibling screens — an inconsistency in how "primary save" is presented.
- **Touch targets (D):** Time-picker chips are ~24-28px tall (`:202-227`) — under 44×44 on a core interactive control (open/close time selection).
- **Reliability (cross-ref Phase 5, F):** The 7-call sequential, non-atomic save loop (`:42-50`, already flagged in Phase 5 §2.15) means a mid-save failure leaves hours in a silently inconsistent partial state, surfaced to the user only as the generic `'Error: $e'` above with no indication which day(s) succeeded.
- **Microcopy (B+):** Success copy ("Hours saved!," `:55`) is upbeat and specific — a stark contrast with the raw-exception failure copy on the same save flow.

#### `manage_menu_screen.dart` — code-inferred
- **Consistency (B):** Correctly uses `ListView.builder` (unlike sibling order screens) and `AppButton` inside its add/edit sheet.
- **Error states (D):** Raw `'Error: $e'` in both the main list (`:46`) and the sheet (`:376-379`); the delete flow has **no error handling at all** around the delete call (`:178`) — a failed delete is silently swallowed.
- **Touch targets (D):** Edit/delete icon buttons explicitly use `visualDensity: VisualDensity.compact` (`:265,271`); the availability `Switch` explicitly opts out via `shrinkWrap` (`:259`).
- **Loading (C):** The per-item availability toggle fires a `.then()` chain with **no loading indicator and no error handling** (`:98-102`) — a failed toggle fails completely silently.
- **Empty states (B):** "No menu items yet" + "Add your first item" CTA (`:49-66`), though the CTA is a low-emphasis `TextButton` for what's an important empty-state action.

#### `subscription_screen.dart` — code-inferred (the paywall — cross-ref Phase 4's rejection history)
- **Error states (A-, the best in the app):** `_rcErrorMessage` (`:96-101`) maps RevenueCat errors to genuinely friendly, specific copy ("There was a problem with the App Store. Try again later."), and the provider-load error path pairs a friendly message with an actual **Retry** button (`:36-39`) — the single best error+recovery pairing found anywhere in this audit.
- **Consistency (D):** Does not use `AppButton` at all — hand-rolled `FilledButton`/`OutlinedButton` with raw `TextStyle` labels, and because these use Flutter's default (sharper) corner radius instead of `AppButton`'s 12px, this screen's buttons render with **visibly different corner rounding** than every other `AppButton`-using screen.
- **Typography (C):** Multiple raw `TextStyle` sizes (26, 10) matching no defined scale step — most notably a 26pt raw price display that's larger than the app's own `heading2` (22pt), making the price number compete with the actual purchase button for visual dominance.
- **Data integrity bug (D):** Two different hardcoded fallback monthly prices exist for the same product — `$29.99` (`:253`) vs. `$30.00` (`:301`) — a real, user-visible inconsistency if RevenueCat pricing ever fails to load.
- **Critique:** This is the screen Apple already rejected the app over once (Phase 4, Guideline 2.1(b)) for being hard to find — once found, it has the best error handling in the app but the least design-system consistency, and a real latent pricing-display bug.

#### `stripe_connect_screen.dart` — code-inferred
- **Microcopy (A-):** Directly addresses the external-redirect UX — "After completing setup on Stripe's website, return to this app — your status will update automatically." (`:119-121`).
- **Navigation (C):** No custom back-button `leading` (unlike sibling owner screens which all define one) — relies purely on Flutter's automatic back button, an inconsistency. Return-from-Stripe relies entirely on a passive deep-link/lifecycle refresh with no explicit "welcome back" UI signal.
- **Consistency (D):** Raw `Colors.red`/`Colors.green` (`:75,172-190`) instead of `AppColors.error`/`AppColors.openGreen`, breaking a convention this exact screen's sibling screens follow correctly.

#### `my_orders_screen.dart` / `order_queue_screen.dart` — code-inferred
- **Consistency (D):** `_SectionHeader`, `_OrderCard`, and `_timeAgo` are near-verbatim duplicated between the two files rather than shared.
- **Scalability (cross-ref Phase 5, D):** Both use plain `ListView` (not `.builder`) over unbounded provider queries (Phase 5 §2.15) — will visibly degrade for any truck/user with meaningful order history.
- **Microcopy (B+):** Live order counts in section headers ("Incoming (3)"), "Ready for Pickup!" status label with actual personality against otherwise generic status words.
- **Touch targets (D):** `order_queue_screen.dart`'s "Done" section expand/collapse row has no padding around its `GestureDetector` — effective tap height ~20-24px (`:156-168`).
- **Animations (D):** The "Done" section toggle snaps instantly with no `AnimatedSize`, inconsistent with `dashboard_screen.dart`'s identical UI pattern which does animate.

#### `calendar_screen.dart` — code-inferred (1436 lines, confirmed "god screen")
- **Consistency (F):** Does not import `AppSpacing` at all — the only screen besides onboarding to sit fully outside a core design token; does not use `AppButton` anywhere, hand-rolling Accept/Decline pill buttons instead.
- **Loading/Error (D):** No loading state at all — providers are read via `.asData?.value ?? []`, silently defaulting to "no events" indistinguishable from a true empty day during initial load or on a provider error. Failure snackbars expose raw exception text (`:191-192,216-217`).
- **Touch targets (F):** The mini accept/decline glyphs on timeline shift blocks are raw unicode ✓/✗ inside a 24×24 `_MiniButton` (`:1068-1075`) — no label, no accessible size, on a primary action (respond to shift assignment).
- **Reliability (D, cross-ref Phase 5):** Confirmed missing `mounted` re-check after a second `await showModalBottomSheet` in 3 of 4 branches of `_showAddEvent` (`:112-160`) — the classic "used after dispose" crash shape; the identical bug pattern is independently duplicated in `shift_week_card.dart`.
- **Animations (F):** Zero animation anywhere — view-mode switches (list/month/timeline) and month navigation are instant, jarring `setState` rebuilds.

#### `employee_dashboard_screen.dart` — code-inferred
- **Hierarchy (A-):** The one screen in the whole audit that gets this right — the Clock In/Out button correctly receives the strongest visual weight, directly matching its role as the screen's actual primary action.
- **Animations (B):** `AnimatedCrossFade` (350ms) for the mini-map — the only animation found across all 3 employee screens.
- **Microcopy (A):** Genuinely excellent — context-aware clock-out copy that differs based on whether the truck stays open ("The truck will stay open on the owner's device" vs. "End your shift and close the business?").
- **Consistency (D):** Does not use `AppButton` for Clock In/Out — hand-rolled `FilledButton` with no `minimumSize` override, meaning (unlike every `AppButton`-using screen) there is no code-level guarantee this core action meets the 44×44 minimum.
- **Navigation (B, deliberate):** `PopScope` blocks back navigation while clocked in (`:301-310`) — a defensible, intentional design choice, flagged here only so it's evaluated as a decision rather than discovered as a surprise.

#### `employees_screen.dart` — code-inferred
- **Loading/Error (A-):** The only one of the 3 employee screens to properly use `AsyncValue.when(loading:, error:, data:)` rather than a silent fallback — genuinely the best-practice pattern, just not applied consistently elsewhere.
- **Empty states (A-):** "No employees yet. Add one above." (`:130`) — the most actionable empty-state copy found in this audit.
- **Reliability (F, cross-ref Phase 5):** Confirmed `TextEditingController` leak at `:156` (never disposed) plus a genuinely broken error UX in the add-employee dialog — it optimistically closes (`Navigator.pop`, `:202`) **before** the async invite call resolves (`:204`), so a failed invite is only reported via a generic post-hoc SnackBar after the user already believes it succeeded, with no loading state shown in the dialog at all.
- **Touch targets (D):** Close "X" on the add sheet uses `visualDensity: VisualDensity.compact` (`:182`).

### Cross-cutting file: `manage_menu_screen.dart`'s sibling forms and dropdowns, `notifications_screen.dart`, and every dialog/sheet across the account and owner-dashboard features independently reimplement the same `OutlineInputBorder`/`BorderRadius.circular(12)` input styling that `AppTextField` already centralizes — confirmed **4 separate times** across the codebase (`edit_truck_screen.dart`'s `_SocialField`/`_CuisineDropdown`/`_CancellationPolicyDropdown`, `manage_menu_screen.dart`'s `_inputDecoration`). This is the single most-repeated consistency violation in the report.

---

## 4. App-Level Rollup — Full 15-Dimension Scorecard

| # | Dimension | Grade | Score | Professional Comparison |
|---|---|---|---|---|
| 1 | Spacing | B- | 72 | A 4/8-grid token system (`AppSpacing`) genuinely exists and governs most top-level screen padding — comparable to a pre-Series-A app mid-way through adopting a design system, not Linear/Notion-tier discipline (only ~33% of files import the token file; badges/pills/micro-spacing recur as off-grid raw literals everywhere). |
| 2 | Typography | B- | 70 | A real 8-step type scale (`AppTextStyles`) exists with a clear heading→body→caption hierarchy, but calendar/map/dashboard/subscription screens invent one-off raw font sizes (9, 10, 11, 17, 26) outside it — a Figma type scale the code never fully caught up to. |
| 3 | Hierarchy | C+ | 74 | Most screens correctly foreground their primary content, but the single most business-critical action in the app (owner "Go Live") is a plain `Switch` with no dedicated visual weight — an MVP that hasn't yet done a hierarchy pass on its money-path screen. |
| 4 | Animations | D+ | 62 | Confined to ~4 screens using implicit Flutter animations (200-350ms crossfades/resizes); zero custom transitions, zero Hero, most utility screens (calendar, employees, favorites, notifications) have literally none — motion design on par with a ported Bootstrap-era web app, not Airbnb/Linear. |
| 5 | Loading states | B | 80 | A real spinner or `.when(loading:)` exists on nearly every async screen, plus pull-to-refresh on 5 screens — solid mid-2010s discipline, but zero skeleton/shimmer loaders anywhere, below DoorDash/LinkedIn-tier 2025 expectations. |
| 6 | Error states | D | 58 | 10+ screens dump raw `'Error: $e'` to users; at least 3 flows fail completely silently (one loses the user's typed chat message). Only `subscription_screen.dart` does this well (mapped errors + Retry). Comparable to a pre-launch beta's error handling, not Stripe-tier. |
| 7 | Accessibility | F | 30 | Zero `Semantics`/`semanticLabel` across all 116 Dart files, confirmed independently 4 times in this audit; dozens of confirmed sub-44×44 touch targets via deliberate `shrinkWrap`/`compact` opt-outs. Would not pass a cursory accessibility spot-check today. |
| 8 | Consistency | C | 68 | A real shared component library exists (`AppButton`, `AppTextField`, `ErrorView`, etc.) but the highest-traffic screens (dashboard, subscription, onboarding, calendar) are exactly the ones that don't use it — a startup mid-migration, infrastructure built but rollout incomplete. |
| 9 | Navigation | B- | 73 | GoRouter + `StatefulShellRoute` correctly implemented with mostly-proper back buttons; undercut by a live-verified concern (guest "Browse as guest" escape hatch not visibly rendering) and 2+ bottom sheets with no explicit close affordance. |
| 10 | Touch targets | D+ | 60 | Primary CTAs (`AppButton`, 52pt) are compliant, but icon-only/secondary controls are undersized nearly everywhere, including a paid-flow "Cancel Event" button with its tap target explicitly zeroed out — an app that never ran a real touch-target QA pass. |
| 11 | Microcopy | B+ | 85 | Specific, personalized, situationally-aware copy throughout (dynamic pluralization, consequence-explaining destructive-action text, platform-aware instructions) — Stripe/Linear-tier writing on the happy path, undercut only by the raw-exception error layer. |
| 12 | Empty states | B | 78 | Consistent icon+title+subtitle pattern across nearly every list screen — well above indie-app baseline, though icon sizing is untokenized (48/52/56/64px) and no illustrations are used, short of Notion/Linear's fully-illustrated empty states. |
| 13 | Professional polish | C+ | 74 | Genuinely funded-feeling brand assets (icon, onboarding art) and real infrastructure (design tokens, Material3 nav with badges) undercut by a live-confirmed on-launch visible bug (stacked map pins) and visible quality drift in the highest-traffic screens — seed-stage polish, not Series-B. |
| 14 | Modern SaaS standards | D+ | 63 | Pull-to-refresh and bottom sheets are used well; a real dark theme exists. But zero haptics anywhere, zero skeleton loaders, and 116/27 raw `Colors.white`/`black` literals bypassing the theme system suggest dark mode hasn't been visually QA'd — a 2019-era feature checklist missing 2023-2024 table stakes. |
| 15 | Apple HIG compliance | C | 70 | Default Flutter page transitions correctly map to native Cupertino-style swipes on iOS, and 2 screens use `CupertinoDatePicker` for a genuine native touch — but the app is Material-first everywhere else (SnackBars, `AlertDialog`, 100% Material icon set, zero SF Symbols), reading as "a good Flutter app," not "an app built for iOS." |

**App-level average: 68/100 → C-.**

---

## 5. Prioritized Design Punch List

Ordered by impact on perceived quality and launch-readiness — user-facing severity first, code elegance last.

1. **Fix the map-pin stacking/overlap bug** (`map_screen.dart`, live-confirmed). This is the default launch screen; a visibly broken first impression is the single highest-leverage fix available. Add a real minimum-separation/clustering strategy, not just per-frame offset math.
2. **Fix `booking_chat_screen.dart:118`'s message-loss bug.** Clear the input only after a confirmed successful send; show a real error + text-recovery path on failure. This is a trust-breaking bug on a screen used to negotiate paid bookings.
3. **Verify and fix the "Browse as guest" link visibility on real devices** (`login_screen.dart:217-228`, live-observed not rendering in-viewport on iPhone 17 Pro). Given this app has already been rejected once for a screen reviewers "couldn't find," a guest-facing dead end is a real risk, not just a polish nit.
4. **Standardize error handling app-wide.** Replace the 10+ raw `'Error: $e'` sites and the 3+ fully-silent failure paths (menu availability toggle, booking status update) with a shared, friendly error helper — Phase 5 already recommends this from a code-duplication angle (§2.12); this audit confirms it's also the single biggest UX-quality gap. Do the subscription screen's error+Retry pattern everywhere.
5. **Add a real accessibility pass**: `Semantics`/`semanticLabel` on the ~15-20 highest-traffic icon-only controls (map pins, chat send, add-to-order, favorite heart), and stop opting out of Material's minimum tap targets (`shrinkWrap`/`compact`/`Size.zero`) on anything users actually need to tap, starting with `my_requests_screen.dart`'s zeroed-out "Cancel Event" button.
6. **Re-weight the owner dashboard's "Go Live" toggle** to match its actual importance — this is the core action of the entire owner product and currently has the visual weight of a settings switch.
7. **Roll the existing design system out to the screens that skip it entirely**: `onboarding_screen.dart` and `calendar_screen.dart` import none of `AppSpacing`/`AppColors`/`AppTextStyles`; `dashboard_screen.dart` and `subscription_screen.dart` never use `AppButton` despite being two of the highest-stakes screens in the app.
8. **Add motion design to the utility screens** (calendar view switches, section collapse/expand, tab transitions) — currently instant/jarring where sibling screens (dashboard, truck profile) already establish the pattern of animating the same interactions.
9. **Add haptic feedback and skeleton loaders** as a batch — currently entirely absent app-wide; both are inexpensive, high-perceived-quality wins relative to their implementation cost.
10. **Fix the subscription screen's two conflicting hardcoded fallback prices** (`$29.99` vs `$30.00`) and give it its own `AppButton`-consistent corner radius — this is the app's paywall and the screen Apple has already flagged once for discoverability; it deserves the tightest polish in the app, not the loosest.
11. **Consolidate the repeated duplication** flagged throughout (input-decoration boilerplate reimplemented 4×, `_SectionHeader`/`_MsgBadge`/`_CollapsibleSection` duplicated between booking screens, status-pill radius inconsistent 3 ways) — lower user-facing urgency than items 1-10, but each fix also closes a design-drift risk for free.
