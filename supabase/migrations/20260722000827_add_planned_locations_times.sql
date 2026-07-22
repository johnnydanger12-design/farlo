alter table planned_locations add column start_time time;
alter table planned_locations add column end_time time;
comment on column planned_locations.start_time is 'Optional. Will drive the future mobile auto-open/close feature (open during this window while a planned location exists for today) — not consumed by anything yet, but needs to be captured now so that feature has real data once built.';
comment on column planned_locations.end_time is 'See start_time.';
