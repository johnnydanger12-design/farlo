// Opt-in hours automation: for trucks with auto_hours_enabled = true, drives
// is_open and orders_accepting directly from their operating_hours rows instead
// of the owner manually tapping Go Live/Go Offline. Runs every 1 minute via
// cron.job. Mirrors the same field-update shape as the manual toggle in
// food_truck_repository.dart (updateOpenStatus/updateOrdersAccepting) so
// behavior stays consistent whether a truck is opened manually or automatically.
//
// Untouched entirely: any truck with auto_hours_enabled = false (the default) —
// manual Go Live/Go Offline remains the only way those trucks change state.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const PLACES_API_KEY = Deno.env.get('GOOGLE_PLACES_API_KEY');

// The Supabase Edge Runtime's own clock is UTC — operating_hours are entered
// by owners as their own local wall-clock time, so "now" must be converted to
// each business's real local time before comparing, not assumed to be any one
// fixed zone. Resolved once per truck (from lat/lng, via Google's Time Zone
// API) and cached on food_trucks.timezone rather than looked up every run.
async function resolveTimezone(lat: number, lng: number): Promise<string | null> {
  if (!PLACES_API_KEY) {
    console.warn('sync-truck-hours: GOOGLE_PLACES_API_KEY not set, cannot resolve timezone');
    return null;
  }
  const timestamp = Math.floor(Date.now() / 1000);
  const url = `https://maps.googleapis.com/maps/api/timezone/json?location=${lat},${lng}&timestamp=${timestamp}&key=${PLACES_API_KEY}`;
  const res = await fetch(url);
  const data = await res.json();
  if (data.status !== 'OK' || !data.timeZoneId) {
    console.error('sync-truck-hours: timezone lookup failed', data);
    return null;
  }
  return data.timeZoneId as string;
}

const DOW_BY_ABBR: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
const formatterCache = new Map<string, Intl.DateTimeFormat>();

function localNow(date: Date, timeZone: string): { minutesSinceMidnight: number; dayOfWeek: number } {
  let fmt = formatterCache.get(timeZone);
  if (!fmt) {
    fmt = new Intl.DateTimeFormat('en-US', { timeZone, weekday: 'short', hour: 'numeric', minute: 'numeric', hourCycle: 'h23' });
    formatterCache.set(timeZone, fmt);
  }
  const parts: Record<string, string> = {};
  for (const p of fmt.formatToParts(date)) parts[p.type] = p.value;
  return {
    minutesSinceMidnight: Number(parts.hour) * 60 + Number(parts.minute),
    dayOfWeek: DOW_BY_ABBR[parts.weekday],
  };
}

function minutesSinceMidnight(time: string): number {
  const [h, m] = time.split(':').map(Number);
  return h * 60 + m;
}

Deno.serve(async (req: Request) => {
  const cronSecret = Deno.env.get('CRON_SECRET');
  if (cronSecret && req.headers.get('x-cron-secret') !== cronSecret) {
    return new Response('Unauthorized', { status: 401 });
  }

  const now = new Date();

  const { data: trucks, error } = await supabase
    .from('food_trucks')
    .select('id, is_open, orders_accepting, latitude, longitude, timezone')
    .eq('auto_hours_enabled', true);

  if (error) {
    console.error('sync-truck-hours: error fetching trucks', error);
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  let opened = 0;
  let closed = 0;
  let ordersOn = 0;
  let ordersOff = 0;

  for (const truck of trucks ?? []) {
    let timezone = truck.timezone as string | null;
    if (!timezone && truck.latitude != null && truck.longitude != null) {
      timezone = await resolveTimezone(truck.latitude, truck.longitude);
      if (timezone) {
        await supabase.from('food_trucks').update({ timezone }).eq('id', truck.id);
      }
    }
    if (!timezone) {
      // No coordinates yet, or the lookup failed — skip this truck this run
      // rather than guess a zone; it'll resolve as soon as coordinates/API
      // access are in place.
      continue;
    }

    const { minutesSinceMidnight: nowMinutes, dayOfWeek: todayDow } = localNow(now, timezone);

    const { data: hours } = await supabase
      .from('operating_hours')
      .select('open_time, close_time, is_closed')
      .eq('truck_id', truck.id)
      .eq('day_of_week', todayDow)
      .maybeSingle();

    let shouldBeOpen = false;
    let shouldAcceptOrders = false;

    if (hours && !hours.is_closed && hours.open_time && hours.close_time) {
      const openMinutes = minutesSinceMidnight(hours.open_time);
      let closeMinutes = minutesSinceMidnight(hours.close_time);
      // Overnight window (e.g. open 6pm, close midnight/2am) — close_time's
      // clock value is numerically smaller than open_time's. Push it past
      // midnight, and if "now" is on the early-morning side of that same
      // window, push now forward the same way so the comparison lines up.
      if (closeMinutes <= openMinutes) closeMinutes += 24 * 60;
      const effectiveNowMinutes = nowMinutes < openMinutes ? nowMinutes + 24 * 60 : nowMinutes;
      const ordersOffMinutes = closeMinutes - 15;

      shouldBeOpen = effectiveNowMinutes >= openMinutes && effectiveNowMinutes < closeMinutes;
      shouldAcceptOrders = effectiveNowMinutes >= openMinutes && effectiveNowMinutes < ordersOffMinutes;
    }

    if (shouldBeOpen !== truck.is_open) {
      await supabase
        .from('food_trucks')
        .update({
          is_open: shouldBeOpen,
          session_started_at: shouldBeOpen ? now.toISOString() : null,
          opened_by_user_id: null,
          ...(shouldBeOpen ? { has_ever_opened: true } : {}),
        })
        .eq('id', truck.id);
      if (shouldBeOpen) opened++;
      else closed++;
    }

    if (shouldAcceptOrders !== truck.orders_accepting) {
      await supabase.from('food_trucks').update({ orders_accepting: shouldAcceptOrders }).eq('id', truck.id);
      if (shouldAcceptOrders) ordersOn++;
      else ordersOff++;
    }
  }

  return new Response(JSON.stringify({ opened, closed, ordersOn, ordersOff }), { status: 200 });
});
