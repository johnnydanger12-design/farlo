alter table food_trucks add column timezone text;
comment on column food_trucks.timezone is 'IANA timezone (e.g. America/Chicago), resolved once from latitude/longitude via Google Time Zone API and cached — used by sync-truck-hours instead of assuming a single timezone for every business.';
