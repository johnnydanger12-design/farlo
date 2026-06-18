# HANDOFF.md — Farlo
_Last updated: Business expansion, subscription gating, language pass, business_type feature. Read time: ~3 min._

---

## Interrupted Task

None — session ended cleanly. No mid-flight work.

---

## Current State

| Feature | Status |
|---|---|
| Subscription gates | ✓ Go live, announcements, add employee, booking requests all gated |
| Stripe status card on dashboard | ✓ Top of dashboard — "Set Up →" / "Dashboard →" |
| Orders-accepting toggle | ✓ Moved to status card as cascading row; removed duplicate from orders widget |
| business_type (mobile vs fixed) | ✓ DB column added, model updated, registration/upgrade flow, edit truck screen, go-open branch |
| Language genericization | ✓ All "food truck" user-facing strings replaced with generic business language |
| `order_items` RLS for employees | ✓ Fixed — `auth_user_works_for_truck()` added to SELECT policy |
| Stripe Connect post-onboarding UX | ✓ Auto-refresh on app resume; info banner explains to return to app |
| Farlo logo on login screen | ✓ `assets/images/Farlo Logo.png`, height 120 |
| consumer "Start a Business" upgrade | ✓ In Account → Manage Account → Business |
| Stripe keys | ⚠ Still TEST keys — must swap before App Store submission |
| RevenueCat key | ⚠ Still test key — needs Farlo App Store key before submission |
| Stripe live webhook | ⚠ Not configured — payment_status stays unpaid in test mode |

---

## Architecture

Flutter + Riverpod 3.x + GoRouter (StatefulShellRoute for owner/consumer shells). Supabase for auth, Postgres, RLS, realtime. Stripe Connect Express for payments — consumers pay via PaymentSheet, funds transfer to owner's connected account. Edge functions handle Stripe operations. FCM via custom JWT/service-account flow. Employees share the owner's order queue and open/close flow.

**business_type field:** `food_trucks.business_type TEXT NOT NULL DEFAULT 'mobile'`. Mobile = food truck with GPS tracking. Fixed = brick-and-mortar with static address, no GPS. `FoodTruck.isFixed` getter drives branching throughout the codebase. All existing trucks default to 'mobile'.

---

## Recent Decisions

**Subscription gating model (Option A):** Go live requires active subscription. Also gates: announcements, add employee, booking requests (consumer-side checks truck owner's `owner_subscriptions` row). Order-ahead gating moved from edit-truck toggle (which is now plain on/off) to the dashboard orders cascade row with a Stripe popup.

**Stripe status card at dashboard top:** Always visible — "Set Up →" when not connected, "Dashboard →" when connected (uses login_links for Express dashboard access). The "orders accepting" toggle is a cascading row inside the status card, only visible when live + ordersEnabled.

**business_type onboarding:** Two-card picker (Mobile / Fixed Location) on both registration and consumer upgrade sheet. Fixed businesses set a static Google Places address; that lat/lng is stored permanently. Edit Truck screen shows a Places address field for fixed businesses only.

**Go-open branching:** `_handleToggle` in dashboard and `handleGoLive` in employees_provider both branch on `truck.isFixed`. Fixed: just `setOpenStatus(true)`, no GPS. Mobile: full permission → get position → updateLocation → start tracking flow.

**Language:** All user-visible "food truck/truck" strings replaced with "business/local businesses". Class names, variable names, route names, DB columns unchanged. `business_type_picker.dart` still says "Food truck or pop-up" for the mobile type description — intentional.

---

## Traps / Dead Ends

- **`ownerTruckProvider` for employees**: Queries `food_trucks WHERE owner_id = auth.uid()` — always null for employees. Use `employeeGoLiveProvider(truckId)` instead.
- **stripe-webhook verify_jwt**: Must be `false`. Stripe sends no JWT.
- **`profiles.display_name`**: Correct column (not `full_name`, not `name`).
- **Stripe test accounts on live keys**: Delete `stripe_account_id` from profiles to reset. Recovery: `UPDATE profiles SET stripe_account_id = NULL WHERE stripe_account_id IS NOT NULL` then re-onboard.
- **Hot reload vs hot restart for env changes**: `.env.json` key changes only take effect on full stop + rebuild.
- **Fixed business GPS**: Never start `LocationTrackingService` for fixed businesses. `food_truck_provider.build()` already guards re-attach on app restart.
- **`_activeOrdersProvider` silent errors**: Uses `ordersAsync.asData?.value ?? []` — parse errors show as "No active orders."
- **PlacesAutocompleteField coordinates**: The widget calls `onCoordinatesSelected(lat, lng)` only when the user picks from autocomplete dropdown. If they type a full address and don't pick from the list, `_lat`/`_lng` stays null. The registration validation guards against this.

---

## Modified Files (this session — highlights)

| Area | Key Files |
|---|---|
| Subscription gates | `dashboard_screen.dart`, `employees_screen.dart`, `truck_profile_screen.dart`, `account_screen.dart` |
| Stripe dashboard | `dashboard_screen.dart` (`_StripeStatusCard`), `stripe_connect_screen.dart` (auto-refresh), `stripe-connect-onboard/index.ts` (login_links) |
| business_type | `food_truck.dart` (model), `auth_repository.dart`, `auth_provider.dart`, `register_owner_screen.dart`, `account_screen.dart`, `edit_truck_screen.dart`, `dashboard_screen.dart`, `employees_provider.dart`, `employee_dashboard_screen.dart`, `food_truck_provider.dart` |
| Language pass | 12 Flutter files + `send-booking-notification`, `send-order-notification` edge functions |
| RLS | `order_items_employee_select` migration |
| Shared widgets | `lib/features/auth/widgets/business_type_picker.dart` (new), `places_autocomplete_field.dart` (label + coordinates callback) |

---

## Known Issues

| Issue | Severity |
|---|---|
| Stripe keys are TEST — `pk_test_...` in `.env.json`, `sk_test_...` in Supabase secrets | High — must swap before App Store submission |
| RevenueCat `REVENUECAT_APPLE_KEY` is `test_VuvKGy...` in `.env.json` | High — needs Farlo App Store key |
| Stripe live webhook not configured — `payment_status` stays `unpaid` | Medium — orders work, webhook just never fires in test mode |
| After Stripe Connect onboarding, user lands on farlo.app | Medium — auto-refresh on resume handles status update, but no branded landing page |
| Subscription screen `trialing` status treated as inactive | Low — owner in trial period can't go live; intentional but may be too aggressive for launch |

---

## Next Steps

1. **Swap Stripe keys**: `STRIPE_SECRET_KEY` → `sk_live_...`, `STRIPE_WEBHOOK_SECRET` → live `whsec_...`, `.env.json` → `pk_live_...`. Full stop + rebuild.
2. **Swap RevenueCat key**: Replace `test_VuvKGy...` in `.env.json` `REVENUECAT_APPLE_KEY` with production key.
3. **Configure Stripe test webhook**: Register `https://weflrxyerxpsafcdetya.supabase.co/functions/v1/stripe-webhook` in Stripe test dashboard. Test deposit/invoice paid flow end-to-end.
4. **Trialing subscription decision**: Decide if owners in `trialing` status should be able to go live (currently blocked). If yes, update the subscription check to allow `trialing` as well as `active`.
5. **App Store metadata**: Screenshots, description, and keywords still reference "food trucks" — update before submission to reflect the multi-business positioning.
6. **farlo.app landing page**: Build a simple page at `farlo.app/stripe-connect/return` that explains "Return to the Farlo app to continue setup."

---

## Setup Gotchas

- **`.env.json`** at project root — not committed. Contains `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `STRIPE_PUBLISHABLE_KEY`, `REVENUECAT_APPLE_KEY`, `GOOGLE_PLACES_API_KEY`, `GOOGLE_SIGN_IN_WEB_CLIENT_ID`.
- **Supabase project**: `weflrxyerxpsafcdetya.supabase.co`.
- **Stripe Connect**: Platform mode. Requires completing platform profile at `dashboard.stripe.com/settings/connect/platform-profile`.
- **`stripe-webhook` must have `verify_jwt: false`** in `supabase/functions/stripe-webhook/config.toml`.
- **Employee flow**: Employees are consumer-role users with `truck_employees` records. `employeeGoLiveProvider(truckId)` is the entry point.
- **`profiles.display_name`** is the correct column.
- **Realtime**: `orders` table is in the `supabase_realtime` publication.
- **Fixed business address**: Set via Google Places autocomplete in registration or Edit Business screen. Stored as `address`, `latitude`, `longitude` on the `food_trucks` row. Never updated by GPS.
- **business_type_picker.dart**: Shared widget at `lib/features/auth/widgets/business_type_picker.dart`. Used in both registration and consumer upgrade sheet.
