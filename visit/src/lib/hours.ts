// Port of lib/features/food_trucks/models/operating_hours.dart's
// hoursDisplay/_formatTime so hours render identically to the app.
import type { OperatingHours } from './types';

export const DAY_NAMES = [
  'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
];

function formatTime(time: string): string {
  const parts = time.split(':');
  const hour = parseInt(parts[0], 10);
  const minute = parts[1];
  const period = hour < 12 ? 'AM' : 'PM';
  const displayHour = hour === 0 ? 12 : hour > 12 ? hour - 12 : hour;
  return minute === '00' ? `${displayHour} ${period}` : `${displayHour}:${minute} ${period}`;
}

export function hoursDisplay(h: OperatingHours): string {
  if (h.is_closed) return 'Closed';
  if (!h.open_time || !h.close_time) return 'Hours not set';
  return `${formatTime(h.open_time)} – ${formatTime(h.close_time)}`;
}

export function sortedHours(hours: OperatingHours[]): OperatingHours[] {
  return [...hours].sort((a, b) => a.day_of_week - b.day_of_week);
}
