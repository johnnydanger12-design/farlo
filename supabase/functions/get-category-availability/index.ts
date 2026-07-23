// Public, read-only: returns which of a truck's menu categories are
// currently purchasable, computed in the truck's own local time via the same
// shared window logic sync-truck-hours and create-payment-intent use — so
// what a consumer sees here always matches what checkout will actually
// allow, rather than drifting from a separately-reimplemented calculation.
//
// A category is only included in the response if it has at least one
// category_purchase_windows row — categories with none are unrestricted
// (always purchasable whenever the truck is open) and the client should
// treat any category missing from this map as available.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { resolveTimezone, localNow, windowStatus } from '../_shared/timeWindows.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

Deno.serve(async (req: Request) => {
  let body: { truck_id?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'truck_id is required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }
  const truckId = body.truck_id;
  if (!truckId) {
    return new Response(JSON.stringify({ error: 'truck_id is required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const { data: windowRows, error: windowErr } = await supabase
    .from('category_purchase_windows')
    .select('category_name, day_of_week, start_time, end_time')
    .eq('truck_id', truckId);

  if (windowErr) {
    return new Response(JSON.stringify({ error: windowErr.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // No restricted categories at all — nothing to compute, return an empty map.
  if (!windowRows || windowRows.length === 0) {
    return new Response(JSON.stringify({}), { status: 200, headers: { 'Content-Type': 'application/json' } });
  }

  const { data: truck, error: truckErr } = await supabase
    .from('food_trucks')
    .select('timezone, latitude, longitude')
    .eq('id', truckId)
    .single();

  if (truckErr || !truck) {
    return new Response(JSON.stringify({ error: 'truck_not_found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let timezone = truck.timezone as string | null;
  if (!timezone && truck.latitude != null && truck.longitude != null) {
    timezone = await resolveTimezone(truck.latitude, truck.longitude);
    if (timezone) {
      await supabase.from('food_trucks').update({ timezone }).eq('id', truckId);
    }
  }
  if (!timezone) {
    // Can't compute without a timezone — report every restricted category as
    // unavailable rather than guessing, since a wrong "available" would let
    // a client add-to-cart something checkout will then reject anyway.
    const result: Record<string, boolean> = {};
    for (const w of windowRows) result[w.category_name] = false;
    return new Response(JSON.stringify(result), { status: 200, headers: { 'Content-Type': 'application/json' } });
  }

  const { minutesSinceMidnight: nowMinutes, dayOfWeek: todayDow } = localNow(new Date(), timezone);
  const categories = [...new Set(windowRows.map((w) => w.category_name))];
  const result: Record<string, boolean> = {};
  for (const categoryName of categories) {
    const rowsForToday = windowRows.filter((w) => w.category_name === categoryName && w.day_of_week === todayDow);
    result[categoryName] = rowsForToday.some((w) => windowStatus(w.start_time, w.end_time, nowMinutes).isActive);
  }

  return new Response(JSON.stringify(result), { status: 200, headers: { 'Content-Type': 'application/json' } });
});
