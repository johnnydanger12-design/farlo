# Farlo — Accessibility Roadmap (Phase 6, P6-2)

**Status: a prioritized punch list, not yet implemented.** This turns `ux-review.md`'s accessibility finding (§7 grade: F/30 — "zero `Semantics`/`semanticLabel` across all 116 Dart files, confirmed independently 4 times") and its own recommendation ("`Semantics`/`semanticLabel` on the ~15-20 highest-traffic icon-only controls... and stop opting out of Material's minimum tap targets") into a concrete, ordered list with file:line citations, ready to become real Fix-Protocol items whenever this pass (or a future one) picks it up.

**Source:** `audit/ux-review.md` §5 Recommendation #5, and the touch-target/accessibility findings scattered across its per-screen reviews (re-gathered here into one list rather than left spread across 20+ screen sections).

**Why this is a document, not code yet:** 15-20 controls across ~10 files is a real implementation pass, comparable in size to one of the larger items already closed in Phases 3-4 of this remediation. Rather than rush it in alongside this iteration's other work, it's scoped and prioritized here so it can be picked up as its own clean Fix-Protocol item (or several) with proper red/green verification — VoiceOver/TalkBack behavior needs to actually be checked on a device or simulator with the accessibility inspector, not just code-reviewed, to call it done.

---

## Priority tiers

Ordered by the same logic `ux-review.md` itself uses: destructive/paid actions first (highest cost if inaccessible or mis-tapped), then highest-traffic surfaces (map, checkout, chat), then everything else.

### Tier 1 — Destructive or paid actions with a broken/undersized touch target (fix first)

1. **`my_requests_screen.dart:411-417`** — "Cancel Event" button. `ux-review.md` calls this the single most severe finding in the audit (grade F): `padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap` on a destructive action tied to a **paid booking**. Fix: remove all three opt-outs, restore Material's 48×48 minimum, add `Semantics(label: 'Cancel event booking', button: true)`.
2. **`booking_requests_screen.dart:971-972`** — PDF-share icon (owner side), `visualDensity: VisualDensity.compact` on a financial-document action. Add semantic label ("Share invoice PDF") and restore standard tap target.
3. **`dashboard_screen.dart:602-608`** — the Go Live `Switch` itself isn't touch-target-broken, but `ux-review.md` separately flags it as the single most business-critical control in the owner app with no dedicated visual weight or semantic label — add `Semantics(label: 'Go live — start accepting customers')` here even though the sizing issue is cosmetic, not a tap-target bug.
4. **`dashboard_screen.dart:652`** — orders-accepting `Switch`, explicitly shrunk via `materialTapTargetSize: MaterialTapTargetSize.shrinkWrap`. This one gates whether a truck can receive paid orders at all — same priority tier as #1.

### Tier 2 — Highest-traffic surfaces (map, checkout, chat — every user hits these every session)

5. **`map_screen.dart`'s truck pin markers** (`_onTruckTapped`, the `GestureDetector` wrapping `_TruckPin` inside the `MarkerLayer` builder) — the default launch route, the single highest-traffic tap target in the app, currently has no `Semantics` at all. Add a per-truck label, e.g. `Semantics(label: '${truck.name}, ${truck.isOpen ? "open" : "closed"}')`.
6. **`map_screen.dart`'s `_RecenterButton`** — icon-only, recenter-to-my-location control with no semantic label today.
7. **`map_screen.dart`'s `_OffScreenIndicator`** — the edge-of-screen arrow indicating an off-screen truck; icon-only, no label, and functionally important (it's how a user finds a truck that scrolled out of view).
8. **`truck_bottom_sheet.dart:276`** and **`truck_profile_screen.dart:248`** — the favorite-heart toggle, the single most-repeated icon-only interactive control in the consumer app (every truck card/profile). Add `Semantics(label: isFav ? 'Remove from favorites' : 'Add to favorites', button: true)` at both sites (they're two separate implementations of the same control per `code-quality.md`'s duplication findings — fix both, and consider whether they should be unified while touching both anyway).
9. **`booking_chat_screen.dart`'s send button** — part of a real paid-negotiation flow (chat → quote → deposit → invoice); no semantic label found on the icon-only send control.
10. **Order cart / add-to-order controls** (`order_cart_sheet.dart`, quantity +/- and add-to-cart buttons) — checkout is the core revenue path; icon-only quantity steppers need labels ("Increase quantity", "Decrease quantity").
11. **Search bar clear/close icon** (`map_screen.dart`'s search UI, `_SearchBar` — referenced at `map_screen.dart:142`'s debounce site) — icon-only clear button on the primary discovery input.

### Tier 3 — Confirmed sub-44×44 targets via deliberate opt-outs (systemic pattern, not destructive but widespread)

12. **`account_screen.dart:689,817,943,1026,1127`** — 5 separate close `IconButton`s across different sheets, all using `visualDensity: VisualDensity.compact`. Fix all 5 in one pass since they're the same pattern repeated.
13. **`account_screen.dart:589-595`** — edit-name pencil icon, ~20×20.
14. **`login_screen.dart:164-165`** — "Forgot password?" shrunk to `Size(0,36)` with `shrinkWrap`.
15. **`login_screen.dart:217-228`** — "Sign up"/"Get listed"/"Browse as guest" links, bare `GestureDetector`-wrapped `Text` with no padding. Note: `ux-review.md` separately flags "Browse as guest" as a **live-confirmed near-dead-end** (didn't render in the visible viewport across 3 live captures) — if that navigation issue gets its own fix, do the touch-target fix in the same pass since it's the same element.
16. **`manage_menu_screen.dart:265,271`** — edit/delete icon buttons, `visualDensity: VisualDensity.compact`.
17. **`manage_menu_screen.dart:259`** — availability `Switch`, `shrinkWrap`.
18. **`employees_screen.dart:182`** — close "X" on the add-employee sheet, `visualDensity: VisualDensity.compact`.
19. **`calendar_screen.dart` / `shift_week_card.dart`'s mini accept/decline glyphs** — raw unicode ✓/✗ inside a 24×24 `_MiniButton`, no label, on a primary shift-response action.
20. **`dashboard_screen.dart:1002-1003`** — Stripe-connect CTA text button, ~24-28px effective height (payout-related, arguably belongs in Tier 1 given it's money-adjacent — flagged here since the audit graded it alongside the other Tier 3 items, but treat as higher priority if picked up piecemeal).

### Decision: `Tooltip` accepted as equivalent to explicit `Semantics(label:)` for simple icon-only buttons (resolved iteration 10, A+ pass)

Items 12-13's actual fix (commit `22f32b1`, iteration 9) used `IconButton`'s `tooltip:` parameter plus explicit 44×44 `constraints` instead of a literal `Semantics(label:)` wrapper as this roadmap originally specified — flagged by a later verification pass as a deviation worth resolving explicitly rather than leaving ambiguous.

**Decision: accepted as a real equivalent, not a shortcut.** Flutter's `Tooltip` widget (which `IconButton.tooltip` wraps its child in) applies `Semantics(label: message)` to that child by default — VoiceOver/TalkBack announce the tooltip text exactly as they would an explicit `Semantics` wrapper's label, and `tooltip` additionally provides a visible long-press hint sighted users get for free, which a bare `Semantics()` wrapper does not. For a simple icon-only `IconButton` with no additional semantic state to convey (no `toggled`/`selected`/`button:` distinction beyond what `IconButton` already implies), `tooltip:` is the equivalent, idiomatically-preferred Flutter mechanism, not a lesser substitute.

**When to still use explicit `Semantics()` instead:** controls that need to convey extra state (`toggled:`, `selected:`, a `Switch`'s current value, a custom `GestureDetector`-based control with no built-in tooltip support) — items 5 (map truck pins), 8 (favorite-heart toggle), and the `Switch` instances in Tier 1 all correctly use explicit `Semantics()` for exactly this reason, and that pattern stays as-is. This decision only settles the specific case of a plain icon-only `IconButton`/`TextButton` with nothing beyond a label to announce.

No code change needed as a result of this decision — it ratifies iteration 9's already-shipped implementation choice rather than requiring items 12-13 to be redone.

### Also flagged, lower urgency (not icon-only controls, but same root cause)

- **`booking_requests_screen.dart:66-82`** — `Dismissible` swipe-to-delete with no alternate tap-based delete path. Not a touch-target-size issue, but a pure-gesture-only interaction is itself an accessibility gap (VoiceOver users can't perform arbitrary swipe gestures the same way) — worth a tap-based alternative (e.g., a leading edit/delete icon) alongside the swipe.

---

## Suggested implementation shape (for whoever picks this up)

1. **Don't do all 20 in one sweep with no verification** — this is exactly the kind of "mechanical but needs real device verification" item where a code-only fix isn't enough to call it done. VoiceOver (iOS Simulator or device) / TalkBack (Android) needs to actually announce each fixed control correctly.
2. **Group by file, not by tier, when implementing** — items 12-13, 16-18 are cheap, single-file, single-pattern fixes (`visualDensity`/`shrinkWrap` removal + one `Semantics` wrapper each) and can likely be done as one PR-sized pass across `account_screen.dart`/`manage_menu_screen.dart`/`employees_screen.dart` together.
3. **Tier 1 and the map pin (item 5) deserve their own focused pass** with real red/green verification (confirm the old broken state via a screenshot/VoiceOver test, fix, confirm the new state announces correctly) — same rigor as the Phase 1-4 items in `REMEDIATION_LOG.md`, since these are the highest-consequence items on the list.
4. **This list is not exhaustive** — `ux-review.md` explicitly says "zero `Semantics`/`semanticLabel` across all 116 Dart files," meaning strictly complete accessibility coverage is a much larger effort than 20 controls. This roadmap targets the audit's own "highest-traffic" framing, not full WCAG-style coverage — treat it as the first pass, not the last.
