import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseAdmin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return new Response('Unauthorized', { status: 401 });

  const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(
    authHeader.replace('Bearer ', ''),
  );

  if (userError || !user) {
    return new Response('Unauthorized', { status: 401 });
  }

  const { transfer_id } = await req.json();
  if (!transfer_id) {
    return new Response(JSON.stringify({ error: 'transfer_id required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Fetch and validate the transfer
  const { data: transfer, error: fetchError } = await supabaseAdmin
    .from('truck_transfers')
    .select('*')
    .eq('id', transfer_id)
    .eq('to_user_id', user.id)
    .eq('status', 'pending')
    .single();

  if (fetchError || !transfer) {
    return new Response(JSON.stringify({ error: 'Transfer not found or already processed' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  if (new Date(transfer.expires_at) < new Date()) {
    return new Response(JSON.stringify({ error: 'Transfer has expired' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Guard: recipient must not already own a truck
  const { data: existingTruck } = await supabaseAdmin
    .from('food_trucks')
    .select('id')
    .eq('owner_id', user.id)
    .maybeSingle();

  if (existingTruck) {
    return new Response(
      JSON.stringify({ error: 'You already own a truck. A single account can only own one truck.' }),
      { status: 409, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const { truck_id, from_owner_id } = transfer;

  try {
    // Transfer truck ownership
    await supabaseAdmin
      .from('food_trucks')
      .update({ owner_id: user.id })
      .eq('id', truck_id);

    // New owner's role → 'owner'
    await supabaseAdmin
      .from('profiles')
      .update({ role: 'owner' })
      .eq('id', user.id);

    // Old owner's role → 'consumer'
    await supabaseAdmin
      .from('profiles')
      .update({ role: 'consumer' })
      .eq('id', from_owner_id);

    // Move subscription to new owner, or create a trialing one if none exists
    const { data: oldSub } = await supabaseAdmin
      .from('subscriptions')
      .select('id')
      .eq('owner_id', from_owner_id)
      .maybeSingle();

    if (oldSub) {
      await supabaseAdmin
        .from('subscriptions')
        .update({ owner_id: user.id })
        .eq('owner_id', from_owner_id);
    } else {
      await supabaseAdmin
        .from('subscriptions')
        .upsert({ owner_id: user.id, status: 'trialing' }, { onConflict: 'owner_id' });
    }

    // Mark transfer accepted
    await supabaseAdmin
      .from('truck_transfers')
      .update({ status: 'accepted' })
      .eq('id', transfer_id);

    return new Response(JSON.stringify({ success: true }), {
      headers: { 'Content-Type': 'application/json' },
      status: 200,
    });
  } catch (error) {
    console.error('accept-truck-transfer error:', error);
    return new Response(JSON.stringify({ error: String(error) }), {
      headers: { 'Content-Type': 'application/json' },
      status: 500,
    });
  }
});
