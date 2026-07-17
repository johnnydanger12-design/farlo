alter table food_trucks add column auto_mark_ready_delay_minutes integer not null default 0;
alter table food_trucks add column auto_mark_complete_delay_minutes integer not null default 0;
comment on column food_trucks.auto_mark_ready_delay_minutes is 'Minutes to wait after an order is accepted/"Preparing" before auto-mark-ready fires. 0 = immediate (existing behavior).';
comment on column food_trucks.auto_mark_complete_delay_minutes is 'Minutes to wait after an order is marked ready before auto-mark-complete fires. 0 = immediate (existing behavior).';
