import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// Set REVENUECAT_WEBHOOK_SECRET in Supabase Edge Function secrets.
// In RevenueCat dashboard → Project Settings → Webhooks, set the Authorization header value to this secret.
const WEBHOOK_SECRET = Deno.env.get('REVENUECAT_WEBHOOK_SECRET') ?? '';

serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  if (WEBHOOK_SECRET) {
    const auth = req.headers.get('Authorization');
    if (auth !== WEBHOOK_SECRET) {
      return new Response('Unauthorized', { status: 401 });
    }
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response('Invalid JSON', { status: 400 });
  }

  const event = body.event as Record<string, unknown> | undefined;
  if (!event) return new Response('Missing event', { status: 400 });

  const appUserId = event.app_user_id as string | undefined;
  const eventType = event.type as string | undefined;
  const expirationMs = event.expiration_at_ms as number | undefined;

  if (!appUserId || !eventType) {
    return new Response('Missing required fields', { status: 400 });
  }

  type StatusRow = { status: string; isActive: boolean };

  const outcome: StatusRow | null = (() => {
    switch (eventType) {
      case 'INITIAL_PURCHASE':
      case 'RENEWAL':
      case 'UNCANCELLATION':
      case 'PRODUCT_CHANGE':
        return { status: 'active', isActive: true };
      case 'TRIAL_STARTED':
        return { status: 'trialing', isActive: true };
      case 'BILLING_ISSUE':
        return { status: 'past_due', isActive: false };
      case 'CANCELLATION':
      case 'EXPIRATION':
        return { status: 'canceled', isActive: false };
      default:
        return null;
    }
  })();

  if (!outcome) {
    // Unhandled event type — acknowledge and ignore
    return new Response('Ignored', { status: 200 });
  }

  const currentPeriodEnd = expirationMs
    ? new Date(expirationMs).toISOString()
    : null;

  const now = new Date().toISOString();

  const { error: subError } = await supabase
    .from('subscriptions')
    .upsert(
      {
        owner_id: appUserId,
        status: outcome.status,
        product_identifier: event.product_id as string | undefined ?? null,
        current_period_end: currentPeriodEnd,
        updated_at: now,
      },
      { onConflict: 'owner_id' },
    );

  if (subError) {
    console.error('subscriptions upsert error:', subError);
    return new Response('DB error', { status: 500 });
  }

  const { error: truckError } = await supabase
    .from('food_trucks')
    .update({ is_active: outcome.isActive, updated_at: now })
    .eq('owner_id', appUserId);

  if (truckError) {
    console.error('food_trucks update error:', truckError);
    return new Response('DB error', { status: 500 });
  }

  return new Response('OK', { status: 200 });
});
