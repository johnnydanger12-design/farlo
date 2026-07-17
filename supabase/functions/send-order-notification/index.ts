import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { notifyOrderStatus } from '../_shared/orderNotifications.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  let body: Record<string, string>;
  try {
    body = await req.json();
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  const { action, order_id: orderId } = body;
  if (!orderId) {
    return new Response(
      JSON.stringify({ sent: false, reason: 'no_order_id' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const result = await notifyOrderStatus(supabase, action, orderId);
  return new Response(JSON.stringify(result), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
