create table weekly_specials (
  id uuid primary key default gen_random_uuid(),
  truck_id uuid not null references food_trucks(id) on delete cascade,
  event_date date not null,
  title text not null,
  price numeric(8,2),
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);
comment on table weekly_specials is 'Per-day specials entered via the Announce flow (This Week''s Specials section) — dual-purpose, same pattern as planned_locations: broadcast as announcement text AND shown on the truck''s public profile (right above the menu) for the current calendar week only. Create-or-update by (truck_id, event_date) from the app, not a DB constraint.';

alter table weekly_specials enable row level security;

create policy "Anyone can view weekly specials"
  on weekly_specials for select
  using (true);

create policy "Owners manage their own weekly specials"
  on weekly_specials for all
  using (
    exists (
      select 1 from food_trucks ft
      where ft.id = weekly_specials.truck_id and ft.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from food_trucks ft
      where ft.id = weekly_specials.truck_id and ft.owner_id = auth.uid()
    )
  );
