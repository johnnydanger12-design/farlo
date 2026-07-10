import type { MenuItem } from '../lib/types';
import { transformedImageUrl } from '../lib/imageUrl';

function groupByCategory(items: MenuItem[]): [string, MenuItem[]][] {
  const sorted = [...items].sort((a, b) => a.sort_order - b.sort_order);
  const groups = new Map<string, MenuItem[]>();
  for (const item of sorted) {
    if (!groups.has(item.category)) groups.set(item.category, []);
    groups.get(item.category)!.push(item);
  }
  return [...groups.entries()];
}

export function MenuSection({
  items,
  menuImageUrl,
  menuPdfUrl,
}: {
  items: MenuItem[];
  menuImageUrl: string | null;
  menuPdfUrl: string | null;
}) {
  if (items.length === 0) {
    if (menuImageUrl) {
      return (
        <section className="border-t border-[var(--border)] px-4 py-5">
          <h2 className="mb-3 text-sm font-semibold text-[var(--text)]">Menu</h2>
          <img src={transformedImageUrl(menuImageUrl, { width: 1000 })} alt="Menu" className="w-full rounded-lg" />
        </section>
      );
    }
    if (menuPdfUrl) {
      return (
        <section className="border-t border-[var(--border)] px-4 py-5">
          <h2 className="mb-3 text-sm font-semibold text-[var(--text)]">Menu</h2>
          <a href={menuPdfUrl} target="_blank" rel="noreferrer" className="text-sm font-medium text-[var(--primary)] underline">
            View menu (PDF)
          </a>
        </section>
      );
    }
    return null;
  }

  return (
    <section className="border-t border-[var(--border)] px-4 py-5">
      <h2 className="mb-3 text-sm font-semibold text-[var(--text)]">Menu</h2>
      <div className="space-y-6">
        {groupByCategory(items).map(([category, categoryItems]) => (
          <div key={category}>
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-[var(--muted)]">
              {category}
            </h3>
            <div className="space-y-3">
              {categoryItems
                .filter((i) => i.is_available)
                .map((item) => (
                  <div key={item.id} className="flex items-start justify-between gap-3">
                    <div className="min-w-0">
                      <div className="text-sm font-medium text-[var(--text)]">{item.name}</div>
                      {item.description && (
                        <div className="mt-0.5 text-xs text-[var(--muted)]">{item.description}</div>
                      )}
                    </div>
                    <div className="flex-shrink-0 text-sm font-medium text-[var(--text)]">
                      ${item.price.toFixed(2)}
                    </div>
                  </div>
                ))}
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
