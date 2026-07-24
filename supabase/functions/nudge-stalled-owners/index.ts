import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAgentSecret, isDryRun } from '../_shared/auth.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// Cron-invoked (agent_cron_call, daily) — nudges an owner who signed up but
// never added a single menu item, the one thing every real stalled
// Hartsville signup has had in common (has_ever_opened alone isn't a
// reliable signal — one stalled business went live once with nothing set up
// and was never touched again). Sends once per truck (onboarding_nudge_sent_at
// stamp) — this is a nudge, not a drip; if it needs to repeat later that's a
// deliberate follow-up decision, not an automatic retry.

// ---------------------------------------------------------------------------
// FCM helpers — copied from send-booking-notification's fixed pattern (the
// one copy in this codebase whose sendFCM() return value is actually checked
// before reporting success; several sibling functions still have the older,
// unchecked version — see HANDOFF.md).
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

Deno.serve(async (req: Request) => {
  const authError = requireAgentSecret(req);
  if (authError) return authError;

  const dryRun = isDryRun(req);
  const threeDaysAgo = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000).toISOString();

  // Eligible: created more than 3 days ago, never nudged, and — the one
  // real common thread across every stalled signup — zero menu items.
  const { data: candidates, error } = await supabase
    .from('food_trucks')
    .select('id, owner_id, name')
    .lt('created_at', threeDaysAgo)
    .is('onboarding_nudge_sent_at', null);

  if (error) {
    console.error('Error fetching candidate trucks:', error);
    return new Response(JSON.stringify({ error: 'db_error' }), { status: 500 });
  }

  const eligible: { id: string; owner_id: string; name: string }[] = [];
  for (const truck of candidates ?? []) {
    const { count } = await supabase
      .from('menu_items')
      .select('id', { count: 'exact', head: true })
      .eq('truck_id', truck.id);
    if (!count) eligible.push(truck);
  }

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

  for (const truck of eligible) {
    const title = 'Add your menu';
    const body = `${truck.name} isn't getting discovered without a menu — add a few items, it only takes a few minutes.`;

    // Always persist to the in-app inbox — this is the durable nudge; push is
    // just an accelerant and may not reach a device with no token/opted out.
    const { error: insertError } = await supabase.from('notifications').insert({
      user_id: truck.owner_id,
      type: 'onboarding_menu_nudge',
      title,
      body,
      related_id: truck.id,
    });
    if (insertError) {
      console.error(`Failed to insert nudge notification for truck ${truck.id}:`, insertError);
      continue;
    }

    // Stamp immediately so a failure below never causes a repeat nudge —
    // this is a one-time nudge by design, not a retry loop.
    await supabase
      .from('food_trucks')
      .update({ onboarding_nudge_sent_at: new Date().toISOString() })
      .eq('id', truck.id);
    notifiedCount++;

    if (!accessToken) continue;

    const { data: prefs } = await supabase
      .from('notification_preferences')
      .select('push_enabled')
      .eq('user_id', truck.owner_id)
      .maybeSingle();
    if (prefs && !prefs.push_enabled) continue;

    const { data: tokenRow } = await supabase
      .from('push_tokens')
      .select('token')
      .eq('user_id', truck.owner_id)
      .order('updated_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (!tokenRow?.token) continue;

    const result = await sendFCM(tokenRow.token, title, body, sa.project_id, accessToken, {
      type: 'onboarding_menu_nudge',
      related_id: truck.id,
    });
    if (!result.ok) {
      console.error(`Push failed for truck ${truck.id}:`, result.error);
    }
  }

  return new Response(JSON.stringify({ notified: notifiedCount }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
