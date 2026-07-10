import type { FoodTruck } from '../lib/types';

const LINKS: { key: keyof FoodTruck; label: string }[] = [
  { key: 'social_instagram', label: 'Instagram' },
  { key: 'social_facebook', label: 'Facebook' },
  { key: 'social_tiktok', label: 'TikTok' },
  { key: 'social_twitter', label: 'Twitter / X' },
  { key: 'social_youtube', label: 'YouTube' },
  { key: 'website_url', label: 'Website' },
];

export function SocialLinks({ truck }: { truck: FoodTruck }) {
  const present = LINKS.filter(({ key }) => truck[key]);
  if (present.length === 0) return null;

  return (
    <section className="border-t border-[var(--border)] px-4 py-5">
      <h2 className="mb-3 text-sm font-semibold text-[var(--text)]">Find us online</h2>
      <div className="flex flex-wrap gap-2">
        {present.map(({ key, label }) => (
          <a
            key={key}
            href={truck[key] as string}
            target="_blank"
            rel="noreferrer"
            className="rounded-full border border-[var(--border)] px-3 py-1 text-xs font-medium text-[var(--text)] transition hover:bg-[var(--bg)]"
          >
            {label}
          </a>
        ))}
      </div>
    </section>
  );
}
