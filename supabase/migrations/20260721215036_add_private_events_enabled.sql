alter table food_trucks add column private_events_enabled boolean not null default true;
comment on column food_trucks.private_events_enabled is 'Opt-out: when false, the public profile hides the "Request Private Event" button entirely for businesses that dont want catering/private-event inquiries.';
