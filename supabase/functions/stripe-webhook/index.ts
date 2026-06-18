import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

async function verifyStripeSignature(
  rawBody: string,
  signatureHeader: string,
  secret: string,
): Promise<boolean> {
  const t = signatureHeader.split(',').find((p) => p.startsWith('t='))?.slice(2);
  const v1 = signatureHeader.split(',').find((p) => p.startsWith('v1='))?.slice(3);
  if (!t || !v1) return false;

  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(`${t}.${rawBody}`),
  );
  const computed = Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  return computed === v1;
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET');
  if (!webhookSecret) {
    console.error('STRIPE_WEBHOOK_SECRET not set');
    return new Response('Not configured', { status: 500 });
  }

  const signature = req.headers.get('Stripe-Signature');
  if (!signature) {
    return new Response('Missing signature', { status: 400 });
  }

  const rawBody = await req.text();

  const valid = await verifyStripeSignature(rawBody, signature, webhookSecret);
  if (!valid) {
    return new Response('Invalid signature', { status: 400 });
  }

  let event: Record<string, unknown>;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return new Response('Bad JSON', { status: 400 });
  }

  const eventType = event.type as string;
  const eventData = (event.data as Record<string, unknown>)?.object as Record<string, unknown>;

  if (eventType === 'payment_intent.succeeded') {
    const piId = eventData?.id as string | null;
    const metadata = eventData?.metadata as Record<string, string> | null;
    const metaType = metadata?.type;

    if (piId) {
      if (metaType === 'deposit') {
        // Booking deposit paid
        const { error } = await supabase
          .from('booking_deposits')
          .update({ status: 'paid', stripe_payment_intent_id: piId })
          .eq('id', metadata?.record_id);
        if (error) {
          console.error('Failed to mark deposit paid:', error);
        } else if (metadata?.booking_id) {
          supabase.functions.invoke('send-booking-notification', {
            body: { action: 'deposit_paid', booking_id: metadata.booking_id },
          }).catch((e: unknown) => console.error('deposit_paid notification failed:', e));
        }
      } else if (metaType === 'invoice') {
        // Booking invoice paid
        const { error } = await supabase
          .from('booking_quotes')
          .update({ status: 'paid', stripe_payment_intent_id: piId })
          .eq('id', metadata?.record_id);
        if (error) {
          console.error('Failed to mark invoice paid:', error);
        } else if (metadata?.booking_id) {
          supabase.functions.invoke('send-booking-notification', {
            body: { action: 'invoice_paid', booking_id: metadata.booking_id },
          }).catch((e: unknown) => console.error('invoice_paid notification failed:', e));
        }
      } else {
        // Regular order payment
        const { error } = await supabase
          .from('orders')
          .update({ payment_status: 'paid' })
          .eq('stripe_payment_intent_id', piId);
        if (error) console.error('Failed to mark order paid:', error);
      }
    }
  } else if (eventType === 'charge.refunded') {
    const piId = eventData?.payment_intent as string | null;
    if (piId) {
      const { error } = await supabase
        .from('orders')
        .update({ payment_status: 'refunded' })
        .eq('stripe_payment_intent_id', piId);
      if (error) console.error('Failed to mark order refunded:', error);
    }
  } else {
    // Unhandled event types are fine — Stripe sends many
    console.log('Unhandled Stripe event:', eventType);
  }

  return new Response(JSON.stringify({ received: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
