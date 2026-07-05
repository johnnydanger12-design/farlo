// Client-facing half of the GDPR data-export pipeline: verifies the caller,
// then only ever inserts a `pending` row and returns immediately — the
// actual compilation/upload happens in process-data-exports, a
// cron-triggered background worker (see that function + the migration's
// comment for why this is async rather than a synchronous compile-and-return
// call).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { hasActiveRequest } from './logic.ts';

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
  if (userError || !user) return new Response('Unauthorized', { status: 401 });

  const { data: existing, error: fetchError } = await supabaseAdmin
    .from('data_export_requests')
    .select('status')
    .eq('user_id', user.id)
    .in('status', ['pending', 'processing']);

  if (fetchError) {
    return new Response(JSON.stringify({ error: fetchError.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  if (hasActiveRequest(existing ?? [])) {
    return new Response(JSON.stringify({ error: 'export_already_in_progress' }), {
      status: 409,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const { data: inserted, error: insertError } = await supabaseAdmin
    .from('data_export_requests')
    .insert({ user_id: user.id })
    .select('id, status, requested_at')
    .single();

  if (insertError) {
    // A concurrent request slipping past the check above and hitting the
    // DB's partial unique index is the one case this can still legitimately
    // fail on — surface it as the same friendly 409, not a raw 500.
    if (insertError.code === '23505') {
      return new Response(JSON.stringify({ error: 'export_already_in_progress' }), {
        status: 409,
        headers: { 'Content-Type': 'application/json' },
      });
    }
    return new Response(JSON.stringify({ error: insertError.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify({ request: inserted }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
