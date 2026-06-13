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
): Promise<void> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ message: { token: fcmToken, notification: { title, body } } }),
    },
  );
  if (!res.ok) {
    const err = await res.text();
    console.error('FCM error:', err);
  }
}

async function checkPrefs(
  userId: string,
  checkOpenAlert = false,
): Promise<{ allowed: boolean; reason?: string }> {
  const { data: prefs } = await supabase
    .from('notification_preferences')
    .select('push_enabled, open_alert')
    .eq('user_id', userId)
    .maybeSingle();

  // No row means defaults (all enabled)
  if (!prefs) return { allowed: true };
  if (!prefs.push_enabled) return { allowed: false, reason: 'push_disabled' };
  if (checkOpenAlert && !prefs.open_alert) return { allowed: false, reason: 'open_alert_disabled' };
  return { allowed: true };
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const saJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
  if (!saJson) {
    console.warn('FIREBASE_SERVICE_ACCOUNT_JSON not set — skipping notification');
    return new Response(JSON.stringify({ sent: false, reason: 'not_configured' }), { status: 200 });
  }

  let body: Record<string, string>;
  try {
    body = await req.json();
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  const { action } = body;
  let targetUserId: string | null = null;
  let title: string;
  let notifBody: string;

  if (action === 'truck_open') {
    const userId = body.user_id;
    const truckName = body.truck_name ?? 'Your truck';
    if (!userId) {
      return new Response(JSON.stringify({ sent: false, reason: 'no_user_id' }), { status: 200 });
    }
    targetUserId = userId;
    title = "You're Live!";
    notifBody = `${truckName} is now live and visible on the map.`;

    const { allowed, reason } = await checkPrefs(userId, true);
    if (!allowed) {
      return new Response(JSON.stringify({ sent: false, reason }), { status: 200 });
    }
  } else {
    // booking_created / booking_status_changed
    const bookingId = body.booking_id;
    if (!bookingId) {
      return new Response(JSON.stringify({ sent: false, reason: 'no_booking_id' }), { status: 200 });
    }

    const { data: booking, error: bookingErr } = await supabase
      .from('event_booking_requests')
      .select('*, food_trucks(owner_id, name)')
      .eq('id', bookingId)
      .single();

    if (bookingErr || !booking) {
      console.error('Booking not found:', bookingErr);
      return new Response(JSON.stringify({ sent: false, reason: 'booking_not_found' }), { status: 200 });
    }

    if (action === 'booking_created') {
      targetUserId = booking.food_trucks?.owner_id ?? null;
      title = 'New Booking Request';
      notifBody = `${booking.contact_name} wants to book your truck for a ${booking.event_type}`;
    } else if (action === 'booking_status_changed') {
      targetUserId = booking.requester_id ?? null;
      const accepted = booking.status === 'accepted';
      title = accepted ? 'Booking Accepted!' : 'Booking Declined';
      notifBody = accepted
        ? `${booking.food_trucks?.name} accepted your booking request`
        : `${booking.food_trucks?.name} has declined your booking request`;
    } else {
      return new Response(JSON.stringify({ sent: false, reason: 'unknown_action' }), { status: 200 });
    }

    if (!targetUserId) {
      return new Response(JSON.stringify({ sent: false, reason: 'no_target_user' }), { status: 200 });
    }

    const { allowed, reason } = await checkPrefs(targetUserId);
    if (!allowed) {
      return new Response(JSON.stringify({ sent: false, reason }), { status: 200 });
    }
  }

  // Look up push token
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
  await sendFCM(tokenRow.token, title, notifBody, sa.project_id, accessToken);

  return new Response(JSON.stringify({ sent: true }), { status: 200 });
});
