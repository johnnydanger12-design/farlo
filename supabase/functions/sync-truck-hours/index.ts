// Opt-in hours automation: for trucks with auto_hours_enabled = true, drives
// is_open and orders_accepting automatically instead of the owner manually
// tapping Go Live/Go Offline. Runs every 1 minute via cron.job. Mirrors the
// same field-update shape as the manual toggle in food_truck_repository.dart
// (updateOpenStatus/updateOrdersAccepting) so behavior stays consistent
// whether a truck is opened manually or automatically.
//
// Fixed-location businesses (business_type = 'fixed') derive their schedule
// from the weekly operating_hours table, as before. Mobile businesses
// (business_type = 'mobile') don't have a fixed weekly schedule — they
// derive it from today's planned_locations row(s) (announced via the
// Announce sheet), using each row's start_time/end_time, and also update
// latitude/longitude/address from the active row so the map pin reflects
// where the truck actually said it would be, without needing the owner's
// phone to be foregrounded and broadcasting live GPS.
//
// Untouched entirely: any truck with auto_hours_enabled = false (the default) —
// manual Go Live/Go Offline remains the only way those trucks change state.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { resolveTimezone, localNow, localDateString, windowStatus } from '../_shared/timeWindows.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

Deno.serve(async (req: Request) => {
  const cronSecret = Deno.env.get('CRON_SECRET');
  if (cronSecret && req.headers.get('x-cron-secret') !== cronSecret) {
    return new Response('Unauthorized', { status: 401 });
  }

  const now = new Date();

  const { data: trucks, error } = await supabase
    .from('food_trucks')
    .select('id, is_open, orders_accepting, latitude, longitude, timezone, business_type')
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

    let shouldBeOpen = false;
    let shouldAcceptOrders = false;
    let locationUpdate: { latitude: number; longitude: number; address: string | null } | null = null;

    if (truck.business_type === 'mobile') {
      const todayDateStr = localDateString(now, timezone);
      const { data: plannedRows } = await supabase
        .from('planned_locations')
        .select('start_time, end_time, latitude, longitude, address')
        .eq('truck_id', truck.id)
        .eq('event_date', todayDateStr)
        .not('start_time', 'is', null)
        .not('end_time', 'is', null);

      // A day can have more than one announced location (e.g. lunch spot,
      // then dinner spot) — pick whichever window is active *now*, and if
      // more than one somehow overlaps, the one ending soonest so the
      // "closing soon" cutoff below stays meaningful.
      let bestCloseMinutes = Infinity;
      let bestEffectiveNow = 0;
      let activeRow: { start_time: string; end_time: string; latitude: number | null; longitude: number | null; address: string | null } | null = null;
      for (const row of plannedRows ?? []) {
        // A row with no address (lat/lng never geocoded) can't drive
        // automation — there'd be nothing to show customers, and opening
        // with no location update would silently leave whatever coordinates
        // the truck last had (stale, or null on a truck that's never opened
        // before). Treat it the same as if nothing were announced at all.
        if (row.latitude == null || row.longitude == null) continue;
        const { isActive, closeMinutes, effectiveNow } = windowStatus(row.start_time, row.end_time, nowMinutes);
        if (isActive && closeMinutes < bestCloseMinutes) {
          bestCloseMinutes = closeMinutes;
          bestEffectiveNow = effectiveNow;
          activeRow = row;
        }
      }

      if (activeRow) {
        shouldBeOpen = true;
        shouldAcceptOrders = bestEffectiveNow < bestCloseMinutes - 15;
        locationUpdate = { latitude: activeRow.latitude!, longitude: activeRow.longitude!, address: activeRow.address };
      }
      // No matching row for today (nothing announced, no times set, or no
      // address set on what was announced) — shouldBeOpen stays false, same
      // as a fixed business's is_closed=true day.
    } else {
      const { data: hours } = await supabase
        .from('operating_hours')
        .select('open_time, close_time, is_closed')
        .eq('truck_id', truck.id)
        .eq('day_of_week', todayDow)
        .maybeSingle();

      if (hours && !hours.is_closed && hours.open_time && hours.close_time) {
        const { isActive, closeMinutes, effectiveNow } = windowStatus(hours.open_time, hours.close_time, nowMinutes);
        shouldBeOpen = isActive;
        shouldAcceptOrders = effectiveNow < closeMinutes - 15;
      }
    }

    const stateChanged = shouldBeOpen !== truck.is_open;
    const locationChanged = locationUpdate != null &&
      (truck.latitude !== locationUpdate.latitude || truck.longitude !== locationUpdate.longitude);

    if (stateChanged || (shouldBeOpen && locationChanged)) {
      const updatePayload: Record<string, unknown> = {};
      // Only touch is_open/session_started_at/opened_by_user_id when the
      // open state itself is actually changing — a same-day location change
      // (e.g. lunch spot → dinner spot) while already open shouldn't reset
      // "open since" back to now.
      if (stateChanged) {
        updatePayload.is_open = shouldBeOpen;
        updatePayload.session_started_at = shouldBeOpen ? now.toISOString() : null;
        updatePayload.opened_by_user_id = null;
        if (shouldBeOpen) updatePayload.has_ever_opened = true;
      }
      if (shouldBeOpen && locationUpdate) {
        updatePayload.latitude = locationUpdate.latitude;
        updatePayload.longitude = locationUpdate.longitude;
        updatePayload.address = locationUpdate.address ?? undefined;
        updatePayload.location_updated_at = now.toISOString();
      }
      await supabase.from('food_trucks').update(updatePayload).eq('id', truck.id);
      if (stateChanged) {
        if (shouldBeOpen) opened++;
        else closed++;
      }
    }

    if (shouldAcceptOrders !== truck.orders_accepting) {
      await supabase.from('food_trucks').update({ orders_accepting: shouldAcceptOrders }).eq('id', truck.id);
      if (shouldAcceptOrders) ordersOn++;
      else ordersOff++;
    }
  }

  return new Response(JSON.stringify({ opened, closed, ordersOn, ordersOff }), { status: 200 });
});
