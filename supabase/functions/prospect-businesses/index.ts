import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAgentSecret } from '../_shared/auth.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const PLACES_API_KEY = Deno.env.get('GOOGLE_PLACES_API_KEY')!;

// Business types worth prospecting — maps to Google Places types
const PROSPECT_TYPES = [
  'restaurant',
  'bakery',
  'cafe',
  'food',
  'meal_takeaway',
  'meal_delivery',
];

interface PlaceResult {
  place_id: string;
  name: string;
  formatted_address: string;
  types: string[];
  formatted_phone_number?: string;
  website?: string;
}

async function searchPlaces(query: string, pageToken?: string): Promise<{ results: PlaceResult[]; next_page_token?: string }> {
  const params: Record<string, string> = {
    query,
    key: PLACES_API_KEY,
  };
  if (pageToken) params.pagetoken = pageToken;

  const url = `https://maps.googleapis.com/maps/api/place/textsearch/json?${new URLSearchParams(params)}`;
  const res = await fetch(url);
  const data = await res.json();

  if (data.status !== 'OK' && data.status !== 'ZERO_RESULTS') {
    console.error('Places API error:', data.status, data.error_message);
  }

  return {
    results: data.results ?? [],
    next_page_token: data.next_page_token,
  };
}

Deno.serve(async (req: Request) => {
  const authError = requireAgentSecret(req);
  if (authError) return authError;
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  if (!PLACES_API_KEY) {
    return new Response(JSON.stringify({ error: 'GOOGLE_PLACES_API_KEY not set' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let city: string, types: string[] | undefined;
  try {
    ({ city, types } = await req.json());
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  if (!city) {
    return new Response(JSON.stringify({ error: 'city is required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const searchTypes = types ?? PROSPECT_TYPES;

  // Fetch existing Farlo business google_place_ids to skip them
  const { data: existingTrucks } = await supabase
    .from('food_trucks')
    .select('id')
    .not('id', 'is', null);

  // Fetch already-prospected place IDs
  const { data: existingProspects } = await supabase
    .from('sales_prospects')
    .select('google_place_id')
    .not('google_place_id', 'is', null);

  const prospectedIds = new Set((existingProspects ?? []).map((p) => p.google_place_id));

  let totalFound = 0;
  let newCount = 0;
  let alreadyProspected = 0;

  for (const type of searchTypes) {
    const query = `food businesses ${city} ${type}`;
    let pageToken: string | undefined;
    let page = 0;

    do {
      // Google requires a short delay before using next_page_token
      if (pageToken) await new Promise((r) => setTimeout(r, 2000));

      const { results, next_page_token } = await searchPlaces(query, pageToken);
      pageToken = next_page_token;
      page++;

      for (const place of results) {
        totalFound++;

        if (prospectedIds.has(place.place_id)) {
          alreadyProspected++;
          continue;
        }

        // Parse city/state from formatted_address (e.g. "123 Main St, Columbia, SC 29201, USA")
        const addressParts = place.formatted_address.split(',').map((s) => s.trim());
        const stateZip = addressParts[addressParts.length - 2] ?? '';
        const stateMatch = stateZip.match(/^([A-Z]{2})/);

        const { error: upsertError } = await supabase
          .from('sales_prospects')
          .upsert(
            {
              business_name: place.name,
              business_type: place.types?.find((t) => PROSPECT_TYPES.includes(t)) ?? 'restaurant',
              address: place.formatted_address,
              city: addressParts[addressParts.length - 3] ?? city,
              state: stateMatch?.[1] ?? null,
              google_place_id: place.place_id,
              status: 'uncontacted',
            },
            { onConflict: 'google_place_id' },
          );

        if (!upsertError) {
          prospectedIds.add(place.place_id);
          newCount++;
        }
      }

      // Max 3 pages per type to avoid runaway API usage
    } while (pageToken && page < 3);
  }

  const existingFarloCount = existingTrucks?.length ?? 0;

  console.log(`Prospecting ${city}: found=${totalFound} new=${newCount} already_prospected=${alreadyProspected} existing_farlo=${existingFarloCount}`);

  return new Response(
    JSON.stringify({
      city,
      found: totalFound,
      new: newCount,
      already_prospected: alreadyProspected,
      existing_farlo: existingFarloCount,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
