# visit — Farlo public business pages

A small, public, read-only web page per Farlo business — e.g.
`visit.farlo.app/ciscos-grill-and-grub` — for sharing on social media (Facebook,
Instagram bio links, etc.) where the in-app "Share" button previously only
linked to the generic `farlo.app` marketing site.

Vite + React + TypeScript + Tailwind v4, same stack and conventions as
`dashboard/` (the founder dashboard) — no router library, no state
management, no component library, just the Supabase JS client talking
directly to the database with the public anon key.

## How it works

- One route: the business's `slug` is read directly from the URL path
  (`window.location.pathname` — see `src/App.tsx`), no router library.
- Fetches `food_trucks` by `slug`, with `operating_hours` and `menu_items`
  embedded — same query shape the Flutter app's `fetchById()` uses.
- **No extra visibility logic needed**: the same RLS policy that gates the
  public map (`is_active = true`) applies here automatically, since this
  page uses the same anon key. A business that hasn't been activated yet
  just shows the "not live yet" state — nothing to build or maintain for
  that case.
- `slug` is generated server-side by a Postgres trigger on `food_trucks`
  INSERT (see `supabase/migrations/20260710213921_add_food_trucks_slug.sql`
  onward) — every new business gets a working share page automatically,
  with no Flutter app changes and no app-store release involved.

## Local development

```
cp .env.example .env   # fill in VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY
npm install
npm run dev
```

Visit `http://localhost:5173/<any-real-slug>` — check the `slug` column on
`food_trucks` for a real one, or query `select slug from food_trucks`.

## Deploy

Same pattern as `dashboard/`: a Cloudflare Pages project pointed at this
subdirectory (root directory `visit`, build command `npm run build`, output
`dist`), with a `visit` CNAME added in Squarespace DNS. No config files
needed in-repo — see `HANDOFF.md` for the exact steps already used for
`dash.farlo.app`.

## Known gap to close before/soon after shipping

The in-app "Share" button (`_shareTruckProfile()` in
`lib/features/owner_dashboard/screens/dashboard_screen.dart`) still doesn't
link here — that's a small Flutter change requiring a new app build, queued
to ship alongside the other pending fixes in the next release rather than
block this page's launch.
