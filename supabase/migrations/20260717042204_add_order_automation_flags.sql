alter table food_trucks add column auto_accept_orders boolean not null default false;
alter table food_trucks add column auto_mark_ready boolean not null default false;
alter table food_trucks add column auto_mark_complete boolean not null default false;
comment on column food_trucks.auto_accept_orders is 'Opt-in: auto-advance pending->accepted ("Preparing"). For Clover-integrated trucks, gated on a successful print; otherwise fires immediately on order placement.';
comment on column food_trucks.auto_mark_ready is 'Opt-in: auto-advance accepted->ready the moment accepted is reached (however that happened).';
comment on column food_trucks.auto_mark_complete is 'Opt-in: auto-advance ready->completed the moment ready is reached (however that happened).';

-- Preserve Hope's already-live experience (auto accept+ready tied to Clover print,
-- manual complete) now that this is driven by explicit flags instead of being
-- hardcoded for any Clover-integrated truck.
update food_trucks
set auto_accept_orders = true, auto_mark_ready = true
where id = 'd4f7ba36-8189-4bac-806c-f97ab8eeb12f';
