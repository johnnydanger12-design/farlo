import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// ---------------------------------------------------------------------------
// Helpers
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

  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signingInput),
  );

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
  if (!res.ok) {
    const err = await res.text();
    console.error('FCM error:', err);
  }
}

async function checkPrefs(userId: string): Promise<{ allowed: boolean; reason?: string }> {
  const { data: prefs } = await supabase
    .from('notification_preferences')
    .select('push_enabled, booking_alert')
    .eq('user_id', userId)
    .maybeSingle();

  if (!prefs) return { allowed: true };
  if (!prefs.push_enabled) return { allowed: false, reason: 'push_disabled' };
  if (!prefs.booking_alert) return { allowed: false, reason: 'booking_alert_disabled' };
  return { allowed: true };
}

async function insertNotification(
  userId: string,
  type: string,
  title: string,
  body: string,
  relatedId?: string,
): Promise<void> {
  const { error } = await supabase.from('notifications').insert({
    user_id: userId,
    type,
    title,
    body,
    related_id: relatedId ?? null,
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

  const { booking_id: bookingId, sender_id: senderId } = body;
  if (!bookingId || !senderId) {
    return new Response(JSON.stringify({ sent: false, reason: 'missing_params' }), { status: 200 });
  }

  const { data: booking, error: bookingErr } = await supabase
    .from('event_booking_requests')
    .select('requester_id, contact_name, food_trucks(owner_id, name)')
    .eq('id', bookingId)
    .single();

  if (bookingErr || !booking) {
    console.error('Booking not found:', bookingErr);
    return new Response(JSON.stringify({ sent: false, reason: 'booking_not_found' }), { status: 200 });
  }

  const ownerId = (booking.food_trucks as Record<string, string> | null)?.owner_id ?? null;
  const requesterId = booking.requester_id as string | null;
  const truckName = (booking.food_trucks as Record<string, string> | null)?.name ?? 'The truck';
  const contactName = (booking.contact_name as string | null) ?? 'Someone';

  let targetUserId: string;
  let title: string;
  let notifBody: string;

  if (senderId === ownerId) {
    // Owner sent → notify the consumer
    if (!requesterId) {
      return new Response(JSON.stringify({ sent: false, reason: 'no_requester' }), { status: 200 });
    }
    targetUserId = requesterId;
    title = 'New Message';
    notifBody = `${truckName} sent you a message about your booking.`;
  } else {
    // Consumer sent → notify the truck owner
    if (!ownerId) {
      return new Response(JSON.stringify({ sent: false, reason: 'no_owner' }), { status: 200 });
    }
    targetUserId = ownerId;
    title = 'New Message';
    notifBody = `${contactName} sent you a message about their booking request.`;
  }

  // Always persist to in-app inbox — FCM is best-effort after this.
  await insertNotification(targetUserId, 'new_message', title, notifBody, bookingId);

  const { allowed, reason } = await checkPrefs(targetUserId);
  if (!allowed) {
    return new Response(JSON.stringify({ sent: false, reason }), { status: 200 });
  }

  const saJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
  if (!saJson) {
    console.warn('FIREBASE_SERVICE_ACCOUNT_JSON not set — skipping push');
    return new Response(JSON.stringify({ sent: false, reason: 'not_configured' }), { status: 200 });
  }

  const { data: tokenRow } = await supabase
    .from('push_tokens')
    .select('token')
    .eq('user_id', targetUserId)
    .order('updated_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!tokenRow?.token) {
    return new Response(JSON.stringify({ sent: false, reason: 'no_token' }), { status: 200 });
  }

  const sa = JSON.parse(saJson);
  const accessToken = await getFCMAccessToken(sa);
  await sendFCM(tokenRow.token, title, notifBody, sa.project_id, accessToken, {
    type: 'new_message',
    related_id: bookingId,
    recipient_is_owner: senderId === ownerId ? 'true' : 'false',
  });

  return new Response(JSON.stringify({ sent: true }), { status: 200 });
});
