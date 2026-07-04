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
    // All app-data cleanup happens in one atomic Postgres transaction — see
    // the delete_account_data() migration. This also clears the NO ACTION
    // foreign keys (booking_messages.sender_id, food_trucks.opened_by_user_id,
    // support_tickets.user_id, sales_prospects.converted_owner_id) that
    // previously made the auth.users delete below throw partway through,
    // leaving a half-deleted "zombie" account (security.md N2).
    const { error: cleanupError } = await supabaseAdmin.rpc('delete_account_data', {
      p_user_id: userId,
    });
    if (cleanupError) throw cleanupError;

    // Delete the auth user last — cascades to profiles.
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
