// Companion to push-order-to-clover's immediate auto-accept/ready/complete
// cascade: handles the case where a truck has set a delay (in minutes) before
// auto-mark-ready and/or auto-mark-complete fire, rather than instantly. Runs
// every minute via cron.job. push-order-to-clover deliberately skips these
// transitions whenever a truck's delay is > 0, so there's exactly one place
// that ever performs a given transition — this function owns all delayed
// ones, immediate ones are owned there.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { notifyOrderStatus } from '../_shared/orderNotifications.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

Deno.serve(async (req: Request) => {
  const cronSecret = Deno.env.get('CRON_SECRET');
  if (cronSecret && req.headers.get('x-cron-secret') !== cronSecret) {
    return new Response('Unauthorized', { status: 401 });
  }

  const now = new Date();
  let readyAdvanced = 0;
  let completeAdvanced = 0;

  // accepted -> ready, once auto_mark_ready_delay_minutes have passed since
  // the order entered 'accepted' (updated_at — the only writer of that
  // column for this transition, same convention push-order-to-clover uses).
  const { data: readyCandidates } = await supabase
    .from('orders')
    .select('id, updated_at, food_trucks!inner(auto_mark_ready, auto_mark_ready_delay_minutes)')
    .eq('status', 'accepted')
    .eq('food_trucks.auto_mark_ready', true)
    .gt('food_trucks.auto_mark_ready_delay_minutes', 0);

  for (const order of readyCandidates ?? []) {
    const truck = order.food_trucks as unknown as { auto_mark_ready_delay_minutes: number };
    const dueAt = new Date(order.updated_at).getTime() + truck.auto_mark_ready_delay_minutes * 60_000;
    if (now.getTime() < dueAt) continue;

    const { data: rows } = await supabase
      .from('orders')
      .update({ status: 'ready', updated_at: now.toISOString() })
      .eq('id', order.id)
      .eq('status', 'accepted')
      .select('id');
    if (rows && rows.length > 0) {
      await notifyOrderStatus(supabase, 'order_ready', order.id);
      readyAdvanced++;
    }
  }

  // ready -> completed, once auto_mark_complete_delay_minutes have passed
  // since the order was marked ready. No consumer notification, matching the
  // existing manual "Mark Completed" flow (a silent close-out).
  const { data: completeCandidates } = await supabase
    .from('orders')
    .select('id, updated_at, food_trucks!inner(auto_mark_complete, auto_mark_complete_delay_minutes)')
    .eq('status', 'ready')
    .eq('food_trucks.auto_mark_complete', true)
    .gt('food_trucks.auto_mark_complete_delay_minutes', 0);

  for (const order of completeCandidates ?? []) {
    const truck = order.food_trucks as unknown as { auto_mark_complete_delay_minutes: number };
    const dueAt = new Date(order.updated_at).getTime() + truck.auto_mark_complete_delay_minutes * 60_000;
    if (now.getTime() < dueAt) continue;

    const { data: rows } = await supabase
      .from('orders')
      .update({ status: 'completed', updated_at: now.toISOString() })
      .eq('id', order.id)
      .eq('status', 'ready')
      .select('id');
    if (rows && rows.length > 0) completeAdvanced++;
  }

  return new Response(JSON.stringify({ readyAdvanced, completeAdvanced }), { status: 200 });
});
