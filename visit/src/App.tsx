import { useEffect, useState } from 'react';
import { supabase } from './lib/supabase';
import type { FoodTruck } from './lib/types';
import { Loading } from './components/Loading';
import { NotFound } from './components/NotFound';
import { Hero } from './components/Hero';
import { OpenBadge } from './components/OpenBadge';
import { HoursTable } from './components/HoursTable';
import { MenuSection } from './components/MenuSection';
import { SocialLinks } from './components/SocialLinks';
import { DownloadCta } from './components/DownloadCta';
import { OpenOrder } from './components/OpenOrder';

function getOrderIdFromPath(): string | null {
  const match = /^\/order\/([^/]+)\/?$/.exec(window.location.pathname);
  return match ? decodeURIComponent(match[1]) : null;
}

function getSlugFromPath(): string {
  // Slugs are always generated lowercase (see the food_trucks slug trigger),
  // but a shared/typed link can arrive in any casing (autocapitalize, someone
  // typing the business's proper-cased name, etc.) — lowercase here so the
  // exact-match query below isn't case-sensitive in practice.
  return window.location.pathname.replace(/^\/+|\/+$/g, '').toLowerCase();
}

type State =
  | { status: 'loading' }
  | { status: 'not-found' }
  | { status: 'found'; truck: FoodTruck };

export default function App() {
  const orderId = getOrderIdFromPath();
  const [state, setState] = useState<State>({ status: 'loading' });

  useEffect(() => {
    if (orderId) return;
    const slug = getSlugFromPath();
    if (!slug) {
      setState({ status: 'not-found' });
      return;
    }

    let cancelled = false;

    supabase
      .from('food_trucks')
      .select('*, operating_hours(*), menu_items(*)')
      .eq('slug', slug)
      .maybeSingle()
      .then(({ data, error }) => {
        if (cancelled) return;
        if (error || !data) {
          setState({ status: 'not-found' });
          return;
        }
        setState({ status: 'found', truck: data as FoodTruck });
      });

    return () => {
      cancelled = true;
    };
  }, [orderId]);

  if (orderId) return <OpenOrder orderId={orderId} />;
  if (state.status === 'loading') return <Loading />;
  if (state.status === 'not-found') return <NotFound />;

  const { truck } = state;

  return (
    <div className="mx-auto min-h-dvh max-w-lg bg-[var(--surface)] shadow-sm">
      <Hero photoUrls={truck.photo_urls} logoUrl={truck.logo_url} name={truck.name} />

      <div className="px-4 py-5">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h1 className="text-xl font-semibold text-[var(--text)]">{truck.name}</h1>
            <p className="text-sm text-[var(--muted)]">{truck.cuisine_type}</p>
          </div>
          <OpenBadge isOpen={truck.is_open} />
        </div>

        <p className="mt-2 text-sm text-[var(--muted)]">
          {truck.review_count > 0
            ? `★ ${truck.average_rating.toFixed(1)} · ${truck.review_count} review${truck.review_count === 1 ? '' : 's'}`
            : 'No reviews yet'}
        </p>

        {truck.address && <p className="mt-2 text-sm text-[var(--text)]">{truck.address}</p>}

        {truck.description && (
          <p className="mt-4 text-sm leading-relaxed text-[var(--text)]">{truck.description}</p>
        )}
      </div>

      <HoursTable hours={truck.operating_hours} />
      <MenuSection items={truck.menu_items} menuImageUrl={truck.menu_image_url} menuPdfUrl={truck.menu_pdf_url} />
      <SocialLinks truck={truck} />

      <div className="border-t border-[var(--border)] px-4 py-6 text-center">
        <p className="mb-3 text-sm text-[var(--muted)]">Order ahead and follow {truck.name} on Farlo</p>
        <DownloadCta />
      </div>
    </div>
  );
}
