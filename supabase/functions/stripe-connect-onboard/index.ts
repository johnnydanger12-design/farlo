import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

function stripePost(path: string, params: Record<string, string>, secretKey: string) {
  const body = Object.entries(params)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
    .join('&');
  return fetch(`https://api.stripe.com/v1${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${secretKey}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body,
  });
}

function stripeGet(path: string, secretKey: string) {
  return fetch(`https://api.stripe.com/v1${path}`, {
    headers: { Authorization: `Bearer ${secretKey}` },
  });
}

// Deep link back to the app after Stripe onboarding completes or needs refresh.
const RETURN_URL = 'https://farlo.app';
const REFRESH_URL = 'https://farlo.app';

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return new Response('Unauthorized', { status: 401 });
  }

  const stripeKey = Deno.env.get('STRIPE_SECRET_KEY');
  if (!stripeKey) {
    return new Response(
      JSON.stringify({ error: 'Stripe not configured' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) {
    return new Response('Unauthorized', { status: 401 });
  }

  // Look up existing Stripe account
  const { data: profile } = await supabase
    .from('profiles')
    .select('stripe_account_id')
    .eq('id', user.id)
    .single();

  let stripeAccountId = profile?.stripe_account_id as string | null;

  // Create Express account if not connected yet
  if (!stripeAccountId) {
    const acctRes = await stripePost('/accounts', {
      type: 'express',
      'capabilities[card_payments][requested]': 'true',
      'capabilities[transfers][requested]': 'true',
    }, stripeKey);

    const acct = await acctRes.json();
    if (!acctRes.ok) {
      console.error('Stripe account create error:', acct);
      return new Response(
        JSON.stringify({ error: acct.error?.message ?? 'stripe_error' }),
        { status: 502, headers: { 'Content-Type': 'application/json' } },
      );
    }

    stripeAccountId = acct.id;

    await supabase
      .from('profiles')
      .update({ stripe_account_id: stripeAccountId })
      .eq('id', user.id);
  }

  // Check if the account has completed onboarding (details_submitted = true).
  // If so, generate a login link to the Express dashboard instead of re-running
  // onboarding — onboarding links always land on RETURN_URL (farlo.app), not the dashboard.
  const acctRes = await stripeGet(`/accounts/${stripeAccountId}`, stripeKey);
  const acct = await acctRes.json();
  const detailsSubmitted = acctRes.ok && acct.details_submitted === true;

  if (detailsSubmitted) {
    const loginRes = await stripePost(
      `/accounts/${stripeAccountId}/login_links`,
      {},
      stripeKey,
    );
    const loginLink = await loginRes.json();
    if (loginRes.ok) {
      return new Response(
        JSON.stringify({ url: loginLink.url }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      );
    }
    // Login link failed (rare) — fall through to onboarding link as fallback.
    console.warn('Login link failed, falling back to onboarding:', loginLink);
  }

  // Account exists but onboarding not complete — send them through onboarding.
  const linkRes = await stripePost('/account_links', {
    account: stripeAccountId!,
    refresh_url: REFRESH_URL,
    return_url: RETURN_URL,
    type: 'account_onboarding',
  }, stripeKey);

  const link = await linkRes.json();
  if (!linkRes.ok) {
    console.error('Stripe account link error:', link);
    return new Response(
      JSON.stringify({ error: link.error?.message ?? 'stripe_error' }),
      { status: 502, headers: { 'Content-Type': 'application/json' } },
    );
  }

  return new Response(
    JSON.stringify({ url: link.url }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
