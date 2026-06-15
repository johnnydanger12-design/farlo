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

  const userId = user.id;

  try {
    // Delete push tokens
    await supabaseAdmin.from('push_tokens').delete().eq('user_id', userId);

    // Delete favorites
    await supabaseAdmin.from('favorites').delete().eq('user_id', userId);

    // Delete reviews
    await supabaseAdmin.from('reviews').delete().eq('user_id', userId);

    // Delete consumer booking requests
    await supabaseAdmin
      .from('event_booking_requests')
      .delete()
      .eq('requester_id', userId);

    // If owner: delete truck data first
    const { data: truck } = await supabaseAdmin
      .from('food_trucks')
      .select('id')
      .eq('owner_id', userId)
      .maybeSingle();

    if (truck) {
      await supabaseAdmin
        .from('event_booking_requests')
        .delete()
        .eq('truck_id', truck.id);

      await supabaseAdmin
        .from('truck_employees')
        .delete()
        .eq('truck_id', truck.id);

      await supabaseAdmin.from('food_trucks').delete().eq('owner_id', userId);
    }

    await supabaseAdmin.from('subscriptions').delete().eq('owner_id', userId);

    // Delete the auth user last — cascades to profiles
    const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(userId);
    if (deleteError) throw deleteError;

    return new Response(JSON.stringify({ success: true }), {
      headers: { 'Content-Type': 'application/json' },
      status: 200,
    });
  } catch (error) {
    console.error('delete-account error:', error);
    return new Response(JSON.stringify({ error: String(error) }), {
      headers: { 'Content-Type': 'application/json' },
      status: 500,
    });
  }
});
