alter table profiles add column phone text;

comment on column profiles.phone is 'Optional, collected at checkout — used to match/create a Clover Customer record so Farlo orders count toward a business''s Clover Rewards loyalty points, same as an in-person phone-number entry would.';
