import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { callerOwnsTruck } from './authorization.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  // This function had no authorization at all beyond the platform's
  // verify_jwt gate (any signed-in user, not specifically the truck's
  // owner) — anyone with a Farlo account could POST an arbitrary email/
  // truckName/ownerName and have Farlo's Resend account send it to any
  // address (security.md §4 Consolidated Risk Register, Medium:
  // "send-employee-invite ... performs zero authorization"). Verify the
  // caller actually owns the truck they're inviting for, and derive
  // truckName/ownerName from the database rather than trusting whatever
  // strings the client sent.
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return new Response('Unauthorized', { status: 401 });
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

  let email: string, truckId: string, isExistingUser: boolean;
  try {
    const body = await req.json();
    email = body.email;
    truckId = body.truck_id;
    isExistingUser = body.isExistingUser === true;
    if (!email || !truckId) throw new Error('Missing fields');
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid request body' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const { data: truck, error: truckErr } = await supabase
    .from('food_trucks')
    .select('name, owner_id')
    .eq('id', truckId)
    .single();

  if (truckErr || !callerOwnsTruck(truck, user.id)) {
    return new Response(JSON.stringify({ error: 'not_truck_owner' }), {
      status: 403,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const { data: ownerProfile } = await supabase
    .from('profiles')
    .select('display_name')
    .eq('id', user.id)
    .single();

  const truckName = truck.name;
  const ownerName = ownerProfile?.display_name || 'Your employer';

  const resendKey = Deno.env.get('RESEND_API_KEY');
  if (!resendKey) {
    console.log(`[invite] No RESEND_API_KEY set. Skipping email to ${email}.`);
    return new Response(JSON.stringify({ sent: false, reason: 'no_api_key' }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const subject = isExistingUser
    ? `You've been added to ${truckName} on Good Truck Finder`
    : `You've been invited to join ${truckName} on Good Truck Finder`;

  const html = isExistingUser
    ? `
      <p>Hi there,</p>
      <p><strong>${ownerName}</strong> has added you as an employee for <strong>${truckName}</strong> on Good Truck Finder.</p>
      <p>Open the app — you'll see a card on the map screen letting you go live for the truck.</p>
      <p>— The Good Truck Finder team</p>
    `
    : `
      <p>Hi there,</p>
      <p><strong>${ownerName}</strong> has invited you to join <strong>${truckName}</strong> as an employee on Good Truck Finder.</p>
      <p>Download the app and <strong>sign up using this email address (${email})</strong>. Once you're signed in, you'll see a card on the map screen letting you go live for the truck.</p>
      <p>— The Good Truck Finder team</p>
    `;

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${resendKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'Good Truck Finder <onboarding@resend.dev>',
      to: [email],
      subject,
      html,
    }),
  });

  if (!res.ok) {
    const err = await res.text();
    console.error(`[invite] Resend error: ${err}`);
    return new Response(JSON.stringify({ sent: false, reason: 'resend_error', detail: err }), {
      status: 502,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify({ sent: true }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
