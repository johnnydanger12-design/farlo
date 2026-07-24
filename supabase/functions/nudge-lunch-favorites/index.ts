import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAgentSecret, isDryRun } from '../_shared/auth.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// Cron-invoked (agent_cron_call, daily ~lunchtime) — nudges a consumer only
// when a business they already follow is open right now. Deliberately no
// proximity/location targeting (no consumer location data exists anywhere in
// this project) and no fallback message for someone with zero open favorites
// — they get nothing that run, not a weaker generic message. Sends at most
// once per 10 days per consumer (notification_preferences.last_lunch_nudge_sent_at),
// enforced inside get_lunch_nudge_candidates() itself so this function stays a
// thin caller. See ~/.claude/plans/sorted-forging-gem.md for the full design.

// ---------------------------------------------------------------------------
// FCM helpers — copied verbatim from nudge-stalled-owners / send-booking-notification's
// fixed (result-checked) pattern.
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
): Promise<{ ok: boolean; error?: string }> {
  const msg: Record<string, unknown> = { token: fcmToken, notification: { title, body } };
  if (Object.keys(data).length > 0) msg.data = data;
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ message: msg }),
  });
  if (!res.ok) {
    const err = await res.text();
    console.error('FCM error:', err);
    return { ok: false, error: err };
  }
  return { ok: true };
}

function buildCopy(truckNames: string[]): { title: string; body: string } {
  if (truckNames.length === 1) {
    const name = truckNames[0];
    return {
      title: `${name} is open right now`,
      body: `You're following ${name} — swing by before they close.`,
    };
  }
  const shown = truckNames.slice(0, 2);
  const rest = truckNames.length - shown.length;
  const list = rest > 0 ? `${shown.join(', ')} and ${rest} more` : truckNames.join(', ');
  return {
    title: `${truckNames.length} businesses you follow are open right now`,
    body: `${list} are open right now.`,
  };
}

Deno.serve(async (req: Request) => {
  const authError = requireAgentSecret(req);
  if (authError) return authError;

  const dryRun = isDryRun(req);
  const url = new URL(req.url);
  const testUserId = url.searchParams.get('test_user_id');

  const { data: candidates, error } = await supabase.rpc('get_lunch_nudge_candidates', {
    p_test_user_id: testUserId,
  });

  if (error) {
    console.error('Error fetching lunch-nudge candidates:', error);
    return new Response(JSON.stringify({ error: 'db_error' }), { status: 500 });
  }

  const eligible = (candidates ?? []) as {
    user_id: string;
    truck_ids: string[];
    truck_names: string[];
    push_enabled: boolean;
  }[];

  if (dryRun) {
    return new Response(
      JSON.stringify({ dry_run: true, eligible_count: eligible.length, eligible }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  }

  if (eligible.length === 0) {
    return new Response(JSON.stringify({ notified: 0 }), { status: 200 });
  }

  const saJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
  const sa = saJson ? JSON.parse(saJson) : null;
  const accessToken = sa ? await getFCMAccessToken(sa) : null;

  let notifiedCount = 0;

  for (const c of eligible) {
    const { title, body } = buildCopy(c.truck_names);
    const relatedId = c.truck_ids.length === 1 ? c.truck_ids[0] : null;

    const { error: insertError } = await supabase.from('notifications').insert({
      user_id: c.user_id,
      type: 'lunch_nudge',
      title,
      body,
      related_id: relatedId,
    });
    if (insertError) {
      console.error(`Failed to insert lunch-nudge notification for user ${c.user_id}:`, insertError);
      continue;
    }

    // Stamp immediately so a failure below never causes a repeat nudge before
    // the 10-day cooldown is actually up.
    await supabase
      .from('notification_preferences')
      .upsert({ user_id: c.user_id, last_lunch_nudge_sent_at: new Date().toISOString() }, { onConflict: 'user_id' });
    notifiedCount++;

    if (!accessToken || !c.push_enabled) continue;

    const { data: tokenRow } = await supabase
      .from('push_tokens')
      .select('token')
      .eq('user_id', c.user_id)
      .order('updated_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (!tokenRow?.token) continue;

    const result = await sendFCM(tokenRow.token, title, body, sa.project_id, accessToken, {
      type: 'lunch_nudge',
      related_id: relatedId ?? '',
    });
    if (!result.ok) {
      console.error(`Push failed for user ${c.user_id}:`, result.error);
    }
  }

  return new Response(JSON.stringify({ notified: notifiedCount }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
