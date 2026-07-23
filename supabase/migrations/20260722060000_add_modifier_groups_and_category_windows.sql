-- Single-select modifier groups: a row with group_name = null behaves exactly
-- as before (independent toggle). Rows sharing a non-null
-- (menu_item_id, group_name) form a required single-select group — exactly
-- one must be chosen (e.g. "Choice of Side": Grits / Hashbrowns). No separate
-- "required" flag — grouped always means required, matching every real
-- example on the menus this was built against. included_by_default marks
-- which option is pre-selected in its group.
alter table menu_item_modifiers add column group_name text;
create unique index menu_item_modifiers_group_name_unique
  on menu_item_modifiers (menu_item_id, group_name, name)
  where group_name is not null;
comment on column menu_item_modifiers.group_name is 'Non-null groups this row with same-named siblings on the same item into a required single-select choice (radio buttons) instead of an independent toggle.';

-- Snapshot of the chosen option(s) at order time, same rationale as
-- removed_modifiers/added_modifiers (added in 20260717044528): never a live
-- join, so later menu edits never rewrite order history.
alter table order_items add column selected_options jsonb not null default '[]';
comment on column order_items.selected_options is 'Array of {group_name, name, price_delta} for each required single-select group\''s chosen option at order time.';

-- Per-category purchase windows. A category with zero rows here is
-- unrestricted (purchasable whenever the truck itself is open) — that's the
-- entire mechanism, no separate boolean flag. Multiple rows per
-- (truck_id, category_name, day_of_week) are allowed on purpose, mirroring
-- planned_locations' precedent, since a category can need more than one
-- window on the same day (e.g. Blue Plate Special: 11am-2pm AND 5pm-9pm).
-- category_name matches menu_items.category by plain text, consistent with
-- how categories are already linked everywhere else in this schema (no FK).
create table category_purchase_windows (
  id uuid primary key default gen_random_uuid(),
  truck_id uuid not null references food_trucks(id) on delete cascade,
  category_name text not null,
  day_of_week integer not null,
  start_time time not null,
  end_time time not null,
  created_at timestamptz not null default now(),
  constraint category_purchase_windows_day_of_week_check check (day_of_week >= 0 and day_of_week <= 6)
);
comment on table category_purchase_windows is 'Time windows during which a menu category can actually be purchased (browsing is never restricted). Zero rows for a category = always purchasable whenever the truck is open.';

alter table category_purchase_windows enable row level security;

create policy "Anyone can view category purchase windows"
  on category_purchase_windows for select
  using (true);

create policy "Owners manage their own category purchase windows"
  on category_purchase_windows for all
  using (truck_id in (select id from food_trucks where owner_id = auth.uid()))
  with check (truck_id in (select id from food_trucks where owner_id = auth.uid()));
