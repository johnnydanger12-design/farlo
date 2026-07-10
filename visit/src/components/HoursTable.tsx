import type { OperatingHours } from '../lib/types';
import { DAY_NAMES, hoursDisplay, sortedHours } from '../lib/hours';

export function HoursTable({ hours }: { hours: OperatingHours[] }) {
  if (hours.length === 0) return null;

  return (
    <section className="border-t border-[var(--border)] px-4 py-5">
      <h2 className="mb-3 text-sm font-semibold text-[var(--text)]">Hours</h2>
      <div className="space-y-1.5">
        {sortedHours(hours).map((h) => (
          <div key={h.day_of_week} className="flex justify-between text-sm">
            <span className="text-[var(--muted)]">{DAY_NAMES[h.day_of_week]}</span>
            <span className="text-[var(--text)]">{hoursDisplay(h)}</span>
          </div>
        ))}
      </div>
    </section>
  );
}
