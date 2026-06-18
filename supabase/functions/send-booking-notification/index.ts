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

async function checkPrefs(
  userId: string,
  checkOpenAlert = false,
): Promise<{ allowed: boolean; reason?: string }> {
  const { data: prefs } = await supabase
    .from('notification_preferences')
    .select('push_enabled, open_alert')
    .eq('user_id', userId)
    .maybeSingle();

  if (!prefs) return { allowed: true };
  if (!prefs.push_enabled) return { allowed: false, reason: 'push_disabled' };
  if (checkOpenAlert && !prefs.open_alert) return { allowed: false, reason: 'open_alert_disabled' };
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

  const saJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');

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
  let notifType: string;
  let relatedId: string | undefined;

  if (action === 'truck_open') {
    const userId = body.user_id;
    const truckName = body.truck_name ?? 'Your business';
    if (!userId) {
      return new Response(JSON.stringify({ sent: false, reason: 'no_user_id' }), { status: 200 });
    }
    targetUserId = userId;
    notifType = 'truck_open';
    title = "You're Open!";
    notifBody = `${truckName} is now open and visible on the map.`;

    const { allowed, reason } = await checkPrefs(userId, true);
    if (!allowed) {
      return new Response(JSON.stringify({ sent: false, reason }), { status: 200 });
    }
  } else if (action === 'truck_closed') {
    const userId = body.user_id;
    const truckName = body.truck_name ?? 'Your business';
    if (!userId) {
      return new Response(JSON.stringify({ sent: false, reason: 'no_user_id' }), { status: 200 });
    }
    targetUserId = userId;
    notifType = 'truck_closed';
    title = "You're Closed";
    notifBody = `${truckName} is now closed and hidden from the map.`;

    const { allowed, reason } = await checkPrefs(userId, true);
    if (!allowed) {
      return new Response(JSON.stringify({ sent: false, reason }), { status: 200 });
    }
  } else {
    // booking_created / booking_status_changed / booking_cancelled_by_consumer
    const bookingId = body.booking_id;
    if (!bookingId) {
      return new Response(JSON.stringify({ sent: false, reason: 'no_booking_id' }), { status: 200 });
    }
    relatedId = bookingId;

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
      notifType = 'booking_created';
      title = 'New Booking Request';
      notifBody = `${booking.contact_name} wants to book you for a ${booking.event_type}`;
    } else if (action === 'booking_cancelled_by_consumer') {
      targetUserId = booking.food_trucks?.owner_id ?? null;
      notifType = 'booking_cancelled_by_consumer';
      title = 'Booking Canceled';
      notifBody = `${booking.contact_name} canceled their ${booking.event_type} booking.`;
    } else if (action === 'booking_status_changed') {
      targetUserId = booking.requester_id ?? null;
      if (booking.status === 'accepted') {
        notifType = 'booking_accepted';
        title = 'Booking Accepted!';
        notifBody = `${booking.food_trucks?.name} accepted your booking request`;
      } else if (booking.status === 'cancelled') {
        notifType = 'booking_cancelled_by_owner';
        title = 'Event Canceled';
        const reason = booking.cancellation_reason as string | null;
        notifBody = reason
          ? `${booking.food_trucks?.name} had to cancel your event. They said: "${reason}"`
          : `${booking.food_trucks?.name} had to cancel your event.`;
      } else {
        notifType = 'booking_declined';
        title = 'Booking Declined';
        notifBody = `${booking.food_trucks?.name} has declined your booking request`;
      }
    } else if (action === 'estimate_sent') {
      targetUserId = booking.requester_id ?? null;
      notifType = 'estimate_sent';
      title = 'You Have an Estimate';
      notifBody = `${booking.food_trucks?.name} sent an estimate for your event.`;
    } else if (action === 'estimate_responded') {
      targetUserId = booking.food_trucks?.owner_id ?? null;
      notifType = 'estimate_responded';
      const accepted = body.accepted === 'true';
      title = accepted ? 'Estimate Accepted' : 'Estimate Declined';
      notifBody = accepted
        ? `${booking.contact_name} accepted your estimate.`
        : `${booking.contact_name} declined your estimate.`;
    } else if (action === 'deposit_requested') {
      targetUserId = booking.requester_id ?? null;
      notifType = 'deposit_requested';
      title = 'Deposit Requested';
      notifBody = `${booking.food_trucks?.name} is requesting a deposit for your event.`;
    } else if (action === 'deposit_paid') {
      targetUserId = booking.food_trucks?.owner_id ?? null;
      notifType = 'deposit_paid';
      title = 'Deposit Received';
      notifBody = `${booking.contact_name} paid the deposit for your event.`;
    } else if (action === 'invoice_sent') {
      targetUserId = booking.requester_id ?? null;
      notifType = 'invoice_sent';
      title = 'Invoice Ready';
      notifBody = `${booking.food_trucks?.name} sent an invoice for your event.`;
    } else if (action === 'invoice_paid') {
      targetUserId = booking.food_trucks?.owner_id ?? null;
      notifType = 'invoice_paid';
      title = 'Invoice Paid';
      notifBody = `${booking.contact_name} paid the invoice for your event.`;
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

  // Always persist to in-app inbox (truck_open/truck_closed are transient — skip those).
  if (targetUserId && action !== 'truck_open' && action !== 'truck_closed') {
    await insertNotification(targetUserId, notifType!, title!, notifBody!, relatedId);
  }

  if (!saJson) {
    console.warn('FIREBASE_SERVICE_ACCOUNT_JSON not set — skipping push');
    return new Response(JSON.stringify({ sent: false, reason: 'not_configured' }), { status: 200 });
  }

  // Look up push token
  const { data: tokenRow } = await supabase
    .from('push_tokens')
    .select('token')
    .eq('user_id', targetUserId!)
    .order('updated_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!tokenRow?.token) {
    return new Response(JSON.stringify({ sent: false, reason: 'no_token' }), { status: 200 });
  }

  const sa = JSON.parse(saJson);
  const accessToken = await getFCMAccessToken(sa);
  await sendFCM(tokenRow.token, title!, notifBody!, sa.project_id, accessToken, {
    type: notifType!,
    related_id: relatedId ?? '',
  });

  return new Response(JSON.stringify({ sent: true }), { status: 200 });
});
