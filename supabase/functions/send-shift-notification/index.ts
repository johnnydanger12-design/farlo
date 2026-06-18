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

async function sendFCM(fcmToken: string, title: string, body: string, projectId: string, accessToken: string): Promise<void> {
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ message: { token: fcmToken, notification: { title, body } } }),
  });
  if (!res.ok) console.error('FCM error:', await res.text());
}

async function insertNotification(userId: string, type: string, title: string, body: string, relatedId?: string): Promise<void> {
  const { error } = await supabase.from('notifications').insert({
    user_id: userId,
    type,
    title,
    body,
    related_id: relatedId ?? null,
  });
  if (error) console.error('Failed to insert notification:', error);
}

async function pushToUser(userId: string, title: string, body: string, type: string, relatedId?: string): Promise<void> {
  await insertNotification(userId, type, title, body, relatedId);

  const saJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
  if (!saJson) { console.warn('FIREBASE_SERVICE_ACCOUNT_JSON not set'); return; }

  const { data: tokenRow } = await supabase
    .from('push_tokens')
    .select('token')
    .eq('user_id', userId)
    .order('updated_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!tokenRow?.token) return;

  const sa = JSON.parse(saJson);
  const accessToken = await getFCMAccessToken(sa);
  await sendFCM(tokenRow.token, title, body, sa.project_id, accessToken);
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  let body: Record<string, string>;
  try { body = await req.json(); } catch { return new Response('Bad request', { status: 400 }); }

  const { action, shift_id } = body;

  if (action === 'shift_assigned') {
    // Owner assigned a shift → notify the employee
    if (!shift_id) return new Response(JSON.stringify({ sent: false, reason: 'no_shift_id' }), { status: 200 });

    const { data: shift, error } = await supabase
      .from('scheduled_shifts')
      .select('*, food_trucks(name)')
      .eq('id', shift_id)
      .single();
    if (error || !shift) return new Response(JSON.stringify({ sent: false, reason: 'shift_not_found' }), { status: 200 });

    const start = new Date(shift.scheduled_start);
    const dateStr = start.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', timeZone: 'UTC' });
    const timeStr = start.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true, timeZone: 'UTC' });

    await pushToUser(
      shift.employee_id,
      'New Shift Assigned',
      `You've been scheduled for ${dateStr} at ${timeStr} at ${shift.food_trucks?.name ?? 'your truck'}.`,
      'shift_assigned',
      shift_id,
    );
    return new Response(JSON.stringify({ sent: true }), { status: 200 });
  }

  if (action === 'shift_corrected') {
    // Owner edited an employee's worked shift → notify the employee
    if (!shift_id) return new Response(JSON.stringify({ sent: false, reason: 'no_shift_id' }), { status: 200 });

    const { data: shift, error } = await supabase
      .from('employee_shifts')
      .select('*, food_trucks(name)')
      .eq('id', shift_id)
      .single();
    if (error || !shift) return new Response(JSON.stringify({ sent: false, reason: 'shift_not_found' }), { status: 200 });

    const clockedIn = new Date(shift.clocked_in_at);
    const dateStr = clockedIn.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', timeZone: 'UTC' });

    await pushToUser(
      shift.employee_id,
      'Shift Times Updated',
      `Your shift on ${dateStr} at ${shift.food_trucks?.name ?? 'your truck'} was updated by the owner.`,
      'shift_corrected',
      shift_id,
    );
    return new Response(JSON.stringify({ sent: true }), { status: 200 });
  }

  if (action === 'shift_response') {
    // Employee accepted or declined a scheduled shift → notify the owner
    if (!shift_id) return new Response(JSON.stringify({ sent: false, reason: 'no_shift_id' }), { status: 200 });

    const { data: shift, error } = await supabase
      .from('scheduled_shifts')
      .select('*, food_trucks(name, owner_id), profiles:employee_id(display_name)')
      .eq('id', shift_id)
      .single();
    if (error || !shift) return new Response(JSON.stringify({ sent: false, reason: 'shift_not_found' }), { status: 200 });

    const ownerId = shift.food_trucks?.owner_id;
    if (!ownerId) return new Response(JSON.stringify({ sent: false, reason: 'no_owner' }), { status: 200 });

    const employeeName = (shift.profiles as Record<string, string> | null)?.display_name?.split(' ')[0] ?? 'An employee';
    const start = new Date(shift.scheduled_start);
    const dateStr = start.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', timeZone: 'UTC' });
    const accepted = shift.status === 'accepted';

    await pushToUser(
      ownerId,
      accepted ? 'Shift Accepted' : 'Shift Declined',
      accepted
        ? `${employeeName} accepted their shift on ${dateStr}.`
        : `${employeeName} declined their shift on ${dateStr}.`,
      accepted ? 'shift_accepted' : 'shift_declined',
      shift_id,
    );
    return new Response(JSON.stringify({ sent: true }), { status: 200 });
  }

  return new Response(JSON.stringify({ sent: false, reason: 'unknown_action' }), { status: 200 });
});
