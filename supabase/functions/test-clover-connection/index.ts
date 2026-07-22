// Called from the self-serve Connect Clover screen before Save is enabled.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { testCloverConnection } from '../_shared/clover.ts';

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return new Response('Unauthorized', { status: 401 });

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user }, error: authError } = await userClient.auth.getUser();
  if (authError || !user) return new Response('Unauthorized', { status: 401 });

  let body: { merchant_id?: string; api_token?: string; environment?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ ok: false, reason: 'unknown', message: 'Bad request' }), { status: 400 });
  }
  const { merchant_id: merchantId, api_token: apiToken, environment } = body;
  if (!merchantId || !apiToken || !environment) {
    return new Response(
      JSON.stringify({ ok: false, reason: 'unknown', message: 'merchant_id, api_token, and environment are required' }),
      { status: 400 },
    );
  }

  const result = await testCloverConnection(merchantId, apiToken, environment);
  return new Response(JSON.stringify(result), { status: 200, headers: { 'Content-Type': 'application/json' } });
});
