alter table food_trucks add column auto_hours_enabled boolean not null default false;
alter table food_trucks add column hours_hidden boolean not null default false;
comment on column food_trucks.auto_hours_enabled is 'Opt-in: when true, sync-truck-hours (cron) drives is_open/orders_accepting from operating_hours instead of the owner manually toggling Go Live/Go Offline.';
comment on column food_trucks.hours_hidden is 'Opt-in: when true, consumer-facing UI omits the hours section entirely instead of inferring closed from missing hours.';
