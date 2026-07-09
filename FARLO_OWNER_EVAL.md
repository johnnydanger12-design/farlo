# Farlo — Owner Evaluation: Would a Real Food Truck Owner Pay For This?

## 1. Persona & Method

**Who's evaluating this:** I'm playing **Ronnie Cole**, owner-operator of **Smoke Ring BBQ**, a single mobile food truck that's been working lunch spots, breweries, and weekend markets around Hartsville, SC for six years. It's me full-time plus one part-time employee (my nephew, weekends). Right now I run the business on a **Square reader** for payment, **Instagram Stories + a family group text** to tell regulars where I'm parked each day, **a paper notebook** for my nephew's hours, and **Instagram DMs + a Venmo deposit** for the two or three catering gigs I book a month. I'm comfortable with my phone and the apps I already use, but I'm not going to fight with anything complicated — if it doesn't save me time in the first week, it's gone.

I picked a mobile food truck in Hartsville specifically because that's who Farlo is actually chasing right now, not a guess: `audit/cold_start_gtm_memo.md` §3.1 names Hartsville, SC as the decided launch city, and the founder's sales agent ("Miles") already prospected 117 real food businesses there (`supabase/functions/agent-miles` context, 52+ added to `sales_prospects` per `HANDOFF.md`'s Jun 30 entry).

**What I actually checked before forming any opinion below** (not vibes — every claim in this report traces to something specific):
- Read `README.md` (a stock Flutter template stub — no real product doc there) and every `.md` file in the repo root and `audit/` — including `HANDOFF.md`, `REMEDIATION_STATE.md`, `audit/bugs.md`, `audit/product-review.md`, `audit/cold_start_gtm_memo.md`, `audit/remediation_status.md`.
- Had the actual `lib/` tree walked screen-by-screen for all eight owner-side capabilities Farlo claims (go live, menu, staff/schedule, private events, push notifications, orders, reviews, sign-up), checking each one specifically for whether it's wired to a real backend call or is UI-only.
- Had the live Supabase schema, RLS policies, edge functions, triggers, and current row counts inspected directly via MCP tools, cross-referenced against the migration files on disk.
- Cross-checked what the docs claim against current production data, not just the code — this mattered, because the docs describe a state that's already changed (see §2 and §5).

I'm not grading source code style — I don't care how clean the Riverpod providers are. I care whether this gets me more paying customers than what I do today, for less hassle than what I do today.

---

## 2. What Farlo Gets Right

**Every one of the eight things it claims to do is actually built, not a mockup.** I've been burned before by an app that looked finished in the screenshots and then the "add staff" button just... didn't do anything. That's not the case here. Sign-up, going live, menu management, staff + schedules, private event booking, push notifications, online orders, and reviews are all real screens hitting a real Postgres backend with real-time updates — confirmed by walking the code, not the marketing copy. Specifically:

- **The staff/schedule tool (`lib/features/employees/`) is genuinely better than my notebook.** Real clock-in/clock-out, a shared calendar my nephew can see on his own phone, shift assignment with accept/decline, and — this is the part that would actually get me to switch — the database won't let him clock in for a shift that didn't happen near "now": `employee_shifts` INSERT/UPDATE is locked to a 10-minute window around the real clock-in time (migration `20260704142556_restrict_employee_self_service_timesheet_and_shift_columns.sql`). That's a real fix for the thing every food truck owner worries about with a shared timesheet — someone padding hours after the fact.
- **The catering flow (`lib/features/bookings/`) is a legit upgrade from DMs + Venmo.** Request comes in, we message back and forth in-app, I send a quote, request a deposit, generate an invoice, get paid through Stripe — with the server, not my phone, computing the actual charge amount so nobody can tamper with it client-side. That whole chain replacing "someone DMs me, I guess at a price, they Venmo half of it and hope I remember" is a real time-saver and a real trust upgrade for the customer too.
- **"Going live" does what Instagram Stories does, automatically.** Toggle open, and Farlo pushes a real notification to everyone who's favorited my truck — no me remembering to post a Story every morning. Fixed-location businesses (a bakery, a stand) don't even need GPS, they just flip open/closed against a stored address (`HANDOFF.md`, Jun 29 note) — nice touch, means this isn't only built for trucks.
- **Reviews let me respond publicly**, same as Google/Yelp — a real trust signal, not vaporware (`lib/features/reviews/`, `set_owner_review_response` RPC).
- **They found their own critical bug before I would have hit it.** `REMEDIATION_STATE.md` documents a live, unauthenticated vulnerability (`agent_cron_call`, then later a second one on the GDPR export functions) that got caught and closed before I'd ever be exposed to it. I don't love that these existed, but I do trust a team that's actively hunting for this stuff over one that isn't.

---

## 3. Friction & Weaknesses

I'm not going to pretend this is all upside. Some of it's real friction I'd hit day one; some of it is a bigger problem underneath.

- **There are currently zero real businesses on this app, anywhere, including Hartsville.** I queried the live database myself (well, had it queried) — `food_trucks`, `menu_items`, `orders`, `reviews`, `event_booking_requests`: **every single one has 0 rows.** `REMEDIATION_STATE.md` confirms production was deliberately wiped clean on July 5, 2026, after Apple approved the app, and nothing real has been added back yet. So if I sign up tomorrow, I'm not "one of a few early trucks" — I'm the *first* account on the entire platform. There is nobody for a customer to find but me, and no customer is downloading an app to find one truck.
- **The pricing doesn't match that reality.** $29.99/month or $300/year, 14-day trial, no free tier (`lib/features/owner_dashboard/models/subscription.dart`, `audit/product-review.md` §3). The founder's own memo (`audit/cold_start_gtm_memo.md` §3.3) acknowledges this risk and offers early Hartsville owners a manual 30-day extension on top of the trial — 44 days total. That's a kind gesture, but 44 days of a ghost-town map doesn't get me a single order. The clock only helps if there's already traffic, and there isn't.
- **A prior internal review already caught the exact thing I'd hit first: the app's own default map screen, showing three overlapping test pins in Cupertino, CA** — not even my town (`audit/product-review.md` §2.2). That specific bug is marked fixed in `REMEDIATION_STATE.md` (MED-12, map clustering), but it tells me something: the team was testing this against three fake trucks in California, not against what a Hartsville customer would actually see, which today is nothing at all.
- **No owner-side analytics.** For $30/month I'd want to see: are people actually opening my page, what's my repeat-customer rate, when's my slow hour. `audit/product-review.md` §2.6 confirms this doesn't exist anywhere in `owner_dashboard`. My free Square dashboard already tells me more about my own sales than this would.
- **No "this truck isn't actually here" report mechanism for customers**, and no verified-business badge (`audit/product-review.md` §2.3) — for an app whose entire pitch is real-time location, that's a real trust gap if a customer drives out to a spot and I've already moved.
- **A minor but real privacy leak I noticed while this was being checked:** a backend function called `find_profile_by_email` lets anyone — no login required — look up whether an email address has an account and get back that person's display name, with zero rate limiting or authorization check on it. It's meant for the "transfer my truck to a new owner" flow, but as built, it's a working email-enumeration tool for the whole platform. Not something that affects my day-to-day, but worth knowing before I hand over my nephew's email for the staff invite feature.

To be fair to them: an earlier internal audit (`audit/bugs.md`) found 43 real bugs at hypothetical million-user scale — a payment race condition, a search crash, a subscription check that never re-runs — and `REMEDIATION_STATE.md` shows essentially all of them (Phases 1 through 5) have since been fixed with real regression tests, not just patched and hoped. That's more rigor than I'd have guessed goes into a small-business app. It just doesn't change what I'd see if I opened the app in Hartsville today.

---

## 4. Missing Features, Ranked by Impact

1. **Actual customers on the app in my town.** Not a feature — the whole thing — but it's the one gap that makes every other feature irrelevant until it's solved. Everything below assumes this gets fixed first.
2. **Some kind of free or pay-later tier until I've gotten my first orders.** The founder's own memo name-drops the DoorDash/Uber Eats commission model (pay only when you sell) as the safer approach for exactly my situation and then explicitly doesn't build it (`cold_start_gtm_memo.md` §3.3) — I understand why, it's a bigger lift, but for a truck with zero guaranteed orders, "pay us $30 and hope" is the actual barrier, not the 14 (or 44) days.
3. **Basic sales analytics.** Even a simple "orders this week / repeat customers / your busiest hour" would make the $30 easier to justify to myself every month.
4. **A "report this listing" flow.** If I'm trusting this to send customers to my exact GPS pin, I want customers to have a way to flag it when I've already left, so I hear about it instead of eating a bad review.

---

## 5. The Necessity Verdict

**Straight answer: if my business were doing fine financially, this would be the first thing I cut — not because it's bad, but because right now it does nothing for me.**

Here's the honest math. Everything Farlo actually built — the staff clock-in system, the catering quote-to-invoice pipeline, the automatic "we're live" push instead of me remembering to post a Story — would save me real time and would genuinely be worth $30/month **once it's actually sending me customers**. I checked the code myself: none of it is smoke. But a food-finder app with zero other businesses on it and zero consumer downloads in my area isn't a food-finder app yet, it's a very well-built private CRM for my own truck that I'm paying $360 a year for. My nephew's paper notebook is free.

**What would flip this to "I'd be in trouble without it":**

1. **Real proof of demand in Hartsville** — not "we launched here," but something concrete I can see before I pay: X other real food businesses live on the map, Y consumer app downloads in my zip code. Until I can see that, I'm guessing blind.
2. **Don't make me pay before I've made a dollar through it.** Either build the pay-per-order model they already floated and shelved, or at minimum extend the free window until *my first real order lands*, not a fixed 44 days that starts ticking the moment I sign up regardless of whether anyone's found me yet.
3. **Give me a number to look at every week that proves it's working** — even a bare-bones "12 people viewed your page, 3 favorited you" would turn this from a leap of faith into a decision I can actually make with data, the same way I already can with Square.

## 6. Bottom Line

If a friend running a truck asked me whether to bother: download it, poke around, don't pay for it yet. The tech underneath is legitimately more solid than I expected from a solo-founder app — the staff scheduling and catering-booking stuff alone beats what most of us are stitching together out of group texts and Venmo, and somebody's clearly stress-testing this thing hard before asking real business owners to trust it with their payments. But right now, in Hartsville or anywhere else, you'd be signing up to be the only business in the room. Check back once they've actually got a handful of real trucks on that map — that's the day this stops being a bet on the founder and starts being a bet on your own customers actually finding you.
