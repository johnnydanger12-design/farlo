-- A lapsed/canceled subscription was never rechecked once a truck was live — no
-- realtime listener, no router guard, no server-side check anywhere. A lapsed
-- truck stayed fully visible on the public map and could keep accepting orders/
-- booking payments indefinitely (bugs.md Executive Summary #4). This is an RLS
-- fix rather than a client fix so it takes effect immediately for every current
-- and future client, with no app update needed. Also consolidates the two
-- identical duplicate "anyone can read active trucks" policies flagged
-- separately in supabase-audit.md's performance section.
drop policy "Anyone can read active trucks" on food_trucks;
drop policy "food_trucks: anyone can read active trucks" on food_trucks;

create policy "food_trucks: public can read active subscribed trucks" on food_trucks
for select
using (is_active = true and owner_has_active_subscription(owner_id));
