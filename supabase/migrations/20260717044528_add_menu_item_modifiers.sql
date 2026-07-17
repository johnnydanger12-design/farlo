create table menu_item_modifiers (
  id uuid primary key default gen_random_uuid(),
  menu_item_id uuid not null references menu_items(id) on delete cascade,
  name text not null,
  price_delta numeric(8,2) not null default 0,
  included_by_default boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);
comment on table menu_item_modifiers is 'Per-item customization options an owner defines, e.g. a burger''s Pickles/Mayo/Ketchup/Mustard. included_by_default=true + price_delta=0 is a free ingredient a customer can remove; included_by_default=false + price_delta>0 is a paid add-on a customer can add.';

alter table menu_item_modifiers enable row level security;

create policy "Anyone can view menu item modifiers"
  on menu_item_modifiers for select
  using (true);

create policy "Owners manage their own menu item modifiers"
  on menu_item_modifiers for all
  using (
    exists (
      select 1 from menu_items mi
      join food_trucks ft on ft.id = mi.truck_id
      where mi.id = menu_item_modifiers.menu_item_id and ft.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from menu_items mi
      join food_trucks ft on ft.id = mi.truck_id
      where mi.id = menu_item_modifiers.menu_item_id and ft.owner_id = auth.uid()
    )
  );

alter table order_items add column removed_modifiers text[] not null default '{}';
alter table order_items add column added_modifiers jsonb not null default '[]';
comment on column order_items.removed_modifiers is 'Names of default-included modifiers the customer removed at order time (free) — a snapshot, not a live join, so later menu edits never rewrite history.';
comment on column order_items.added_modifiers is 'Array of {name, price_delta} for optional paid add-ons the customer selected at order time — a snapshot for the same reason as removed_modifiers.';
