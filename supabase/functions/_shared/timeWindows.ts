// Truck-local time-window math, shared by sync-truck-hours (auto open/close),
// get-category-availability (consumer-facing display), and
// create-payment-intent (server-side purchase enforcement) — extracted here
// so all three use the exact same, already-proven overnight-safe window
// logic instead of three separate reimplementations that could drift apart.

const PLACES_API_KEY = Deno.env.get('GOOGLE_PLACES_API_KEY');

// The Supabase Edge Runtime's own clock is UTC — hours/locations are entered
// by owners as their own local wall-clock time, so "now" must be converted to
// each business's real local time before comparing, not assumed to be any one
// fixed zone. Resolved once per truck (from lat/lng, via Google's Time Zone
// API) and cached on food_trucks.timezone rather than looked up every run.
export async function resolveTimezone(lat: number, lng: number): Promise<string | null> {
  if (!PLACES_API_KEY) {
    console.warn('timeWindows: GOOGLE_PLACES_API_KEY not set, cannot resolve timezone');
    return null;
  }
  const timestamp = Math.floor(Date.now() / 1000);
  const url = `https://maps.googleapis.com/maps/api/timezone/json?location=${lat},${lng}&timestamp=${timestamp}&key=${PLACES_API_KEY}`;
  const res = await fetch(url);
  const data = await res.json();
  if (data.status !== 'OK' || !data.timeZoneId) {
    console.error('timeWindows: timezone lookup failed', data);
    return null;
  }
  return data.timeZoneId as string;
}

const DOW_BY_ABBR: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
const localNowFormatterCache = new Map<string, Intl.DateTimeFormat>();
const localDateFormatterCache = new Map<string, Intl.DateTimeFormat>();

export function localNow(date: Date, timeZone: string): { minutesSinceMidnight: number; dayOfWeek: number } {
  let fmt = localNowFormatterCache.get(timeZone);
  if (!fmt) {
    fmt = new Intl.DateTimeFormat('en-US', { timeZone, weekday: 'short', hour: 'numeric', minute: 'numeric', hourCycle: 'h23' });
    localNowFormatterCache.set(timeZone, fmt);
  }
  const parts: Record<string, string> = {};
  for (const p of fmt.formatToParts(date)) parts[p.type] = p.value;
  return {
    minutesSinceMidnight: Number(parts.hour) * 60 + Number(parts.minute),
    dayOfWeek: DOW_BY_ABBR[parts.weekday],
  };
}

// YYYY-MM-DD in the truck's own local timezone, for matching
// planned_locations.event_date (a plain date column, no timezone of its own).
export function localDateString(date: Date, timeZone: string): string {
  let fmt = localDateFormatterCache.get(timeZone);
  if (!fmt) {
    fmt = new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' });
    localDateFormatterCache.set(timeZone, fmt);
  }
  return fmt.format(date); // en-CA formats as YYYY-MM-DD
}

export function minutesSinceMidnight(time: string): number {
  const [h, m] = time.split(':').map(Number);
  return h * 60 + m;
}

// Overnight-safe window check (e.g. open 6pm, close 2am) — closeMinutes and
// nowMinutes are both pushed past midnight the same way so the comparison
// lines up regardless of which side of midnight "now" actually falls on.
export function windowStatus(startTime: string, endTime: string, nowMinutes: number) {
  const openMinutes = minutesSinceMidnight(startTime);
  let closeMinutes = minutesSinceMidnight(endTime);
  if (closeMinutes <= openMinutes) closeMinutes += 24 * 60;
  const effectiveNow = nowMinutes < openMinutes ? nowMinutes + 24 * 60 : nowMinutes;
  return { isActive: effectiveNow >= openMinutes && effectiveNow < closeMinutes, closeMinutes, effectiveNow };
}
