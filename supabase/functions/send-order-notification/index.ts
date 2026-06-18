import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// ---------------------------------------------------------------------------
// Helpers (same FCM pattern as send-booking-notification)
// ---------------------------------------------------------------------------

function pemToBytes(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function b64url(input: string | ArrayBuffer): string {
  let s: string;
  if (typeof input === 'string') {
    s = btoa(input);
  } else {
    s = btoa(String.fromCharCode(...new Uint8Array(input)));
  }
  return s.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

async function getFCMAccessToken(sa: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const payload = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToBytes(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(signingInput));
  const jwt = `${signingInput}.${b64url(sig)}`;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const data = await res.json();
  return data.access_token;
}

async function sendFCM(
  fcmToken: string,
  title: string,
  body: string,
  projectId: string,
  accessToken: string,
  data: Record<string, string> = {},
): Promise<void> {
  const msg: Record<string, unknown> = { token: fcmToken, notification: { title, body } };
  if (Object.keys(data).length > 0) msg.data = data;
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ message: msg }),
    },
  );
  if (!res.ok) console.error('FCM error:', await res.text());
}

async function insertNotification(
  userId: string,
  type: string,
  title: string,
  body: string,
  relatedId: string,
): Promise<void> {
  const { error } = await supabase.from('notifications').insert({
    user_id: userId,
    type,
    title,
    body,
    related_id: relatedId,
  });
  if (error) console.error('Failed to insert notification:', error);
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

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

  const { data: order, error: orderErr } = await supabase
    .from('orders')
    .select('*, food_trucks(owner_id, name), profiles(display_name)')
    .eq('id', orderId)
    .single();

  if (orderErr || !order) {
    console.error('Order not found:', orderErr);
    return new Response(
      JSON.stringify({ sent: false, reason: 'order_not_found' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const truckName: string = (order.food_trucks as Record<string, string> | null)?.name ?? 'the business';
  const consumerName: string = (order.profiles as Record<string, string> | null)?.display_name ?? 'A customer';
  const ownerId: string | null = (order.food_trucks as Record<string, string> | null)?.owner_id ?? null;
  const totalFormatted = `$${Number(order.total_price).toFixed(2)}`;

  let targetUserId: string;
  let notifType: string;
  let title: string;
  let notifBody: string;

  switch (action) {
    // order_placed and order_cancelled are intentionally omitted — the order
    // queue is realtime so owners/employees work from the screen directly.
    case 'order_accepted':
      targetUserId = order.consumer_id;
      notifType = 'order_accepted';
      title = 'Order Accepted';
      notifBody = `${truckName} accepted your order. Head over when ready!`;
      break;
    case 'order_ready':
      targetUserId = order.consumer_id;
      notifType = 'order_ready';
      title = 'Order Ready for Pickup!';
      notifBody = `Your order from ${truckName} is ready. Come grab it!`;
      break;
    case 'order_declined':
      targetUserId = order.consumer_id;
      notifType = 'order_declined';
      title = 'Order Declined';
      notifBody = `${truckName} couldn't fulfill your order. You've been refunded.`;
      break;
    default:
      return new Response(
        JSON.stringify({ sent: false, reason: 'unknown_action' }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      );
  }

  await insertNotification(targetUserId, notifType, title, notifBody, orderId);

  const saJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
  if (!saJson) {
    console.warn('FIREBASE_SERVICE_ACCOUNT_JSON not set — skipping push');
    return new Response(
      JSON.stringify({ sent: false, reason: 'not_configured' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const { data: prefs } = await supabase
    .from('notification_preferences')
    .select('push_enabled')
    .eq('user_id', targetUserId)
    .maybeSingle();
  if (prefs && !prefs.push_enabled) {
    return new Response(
      JSON.stringify({ sent: false, reason: 'push_disabled' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const { data: tokenRow } = await supabase
    .from('push_tokens')
    .select('token')
    .eq('user_id', targetUserId)
    .order('updated_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!tokenRow?.token) {
    return new Response(
      JSON.stringify({ sent: false, reason: 'no_token' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const sa = JSON.parse(saJson);
  const accessToken = await getFCMAccessToken(sa);
  await sendFCM(tokenRow.token, title, notifBody, sa.project_id, accessToken, {
    type: notifType,
    related_id: orderId,
  });

  return new Response(
    JSON.stringify({ sent: true }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
