import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// ---------------------------------------------------------------------------
// FCM helpers (same pattern as send-booking-notification)
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
  const s = typeof input === 'string'
    ? btoa(input)
    : btoa(String.fromCharCode(...new Uint8Array(input)));
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
  if (!res.ok) console.error('FCM error:', await res.text());
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  // Verify caller owns this truck
  const authHeader = req.headers.get('Authorization') ?? '';
  const { data: { user }, error: authErr } = await supabase.auth.getUser(
    authHeader.replace('Bearer ', ''),
  );
  if (authErr || !user) {
    return new Response('Unauthorized', { status: 401 });
  }

  let truckId: string;
  let title: string;
  let message: string;
  try {
    ({ truck_id: truckId, title, message } = await req.json());
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  if (!truckId || !title?.trim() || !message?.trim()) {
    return new Response('truck_id, title, and message are required', { status: 400 });
  }

  const { data: truck } = await supabase
    .from('food_trucks')
    .select('owner_id')
    .eq('id', truckId)
    .single();

  if (!truck || truck.owner_id !== user.id) {
    return new Response('Forbidden', { status: 403 });
  }

  // Get all followers of this truck
  const { data: favs } = await supabase
    .from('favorites')
    .select('user_id')
    .eq('truck_id', truckId);

  const followerIds: string[] = favs?.map((f: { user_id: string }) => f.user_id) ?? [];
  if (followerIds.length === 0) {
    return new Response(JSON.stringify({ sent: 0 }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // Fan-out to in-app inbox for every follower regardless of push preference.
  await supabase.from('notifications').insert(
    followerIds.map((userId) => ({
      user_id: userId,
      type: 'announcement',
      title,
      body: message,
      related_id: truckId,
    })),
  );

  // FCM push — only if Firebase is configured.
  const saJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
  if (saJson) {
    // Find followers who have explicitly disabled push
    const { data: disabledPrefs } = await supabase
      .from('notification_preferences')
      .select('user_id')
      .in('user_id', followerIds)
      .eq('push_enabled', false);

    const disabledIds = new Set<string>(
      disabledPrefs?.map((p: { user_id: string }) => p.user_id) ?? [],
    );
    const enabledIds = followerIds.filter((id) => !disabledIds.has(id));

    if (enabledIds.length > 0) {
      // Get one push token per enabled follower (most recently updated)
      const { data: tokenRows } = await supabase
        .from('push_tokens')
        .select('user_id, token')
        .in('user_id', enabledIds)
        .order('updated_at', { ascending: false });

      // Deduplicate: one token per user (latest)
      const seen = new Set<string>();
      const tokens: string[] = [];
      for (const row of (tokenRows ?? []) as { user_id: string; token: string }[]) {
        if (!seen.has(row.user_id)) {
          seen.add(row.user_id);
          tokens.push(row.token);
        }
      }

      if (tokens.length > 0) {
        const sa = JSON.parse(saJson);
        const accessToken = await getFCMAccessToken(sa);
        await Promise.allSettled(
          tokens.map((t) => sendFCM(t, title, message, sa.project_id, accessToken, { type: 'announcement', related_id: truckId })),
        );
      }
    }
  }

  // sent = inbox fan-out count (always reflects followers who got the in-app notification)
  return new Response(JSON.stringify({ sent: followerIds.length }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
