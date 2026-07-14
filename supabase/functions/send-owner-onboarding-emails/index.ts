import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

async function sendEmail(
  resendKey: string,
  to: string,
  subject: string,
  html: string,
  scheduledAt?: string,
): Promise<void> {
  const payload: Record<string, unknown> = {
    from: 'Johnny at Farlo <support@farlo.app>',
    reply_to: 'support@farlo.app',
    to: [to],
    subject,
    html,
  };
  if (scheduledAt) {
    payload.scheduled_at = scheduledAt;
  }
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${resendKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    const err = await res.text();
    console.error(`Resend error (${res.status}):`, err);
  }
}

function emailBase(body: string): string {
  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
</head>
<body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;color:#1a1a1a;max-width:560px;margin:0 auto;padding:32px 20px;">
  <p style="font-size:22px;font-weight:700;margin:0 0 24px;">farlo</p>
  ${body}
  <hr style="border:none;border-top:1px solid #e5e5e5;margin:32px 0;" />
  <img src="https://weflrxyerxpsafcdetya.supabase.co/storage/v1/object/public/brand/Email%20Logo.png" alt="Farlo" style="height:32px;width:auto;display:block;margin:0 0 12px;" />
  <p style="font-size:12px;color:#888;margin:0;">Farlo Technologies LLC &middot; Hartsville, SC<br/>Questions? Reply to this email or contact <a href="mailto:support@farlo.app" style="color:#2563EB;">support@farlo.app</a></p>
</body>
</html>`;
}

function email1Html(firstName: string): string {
  return emailBase(`
    <p style="font-size:16px;margin:0 0 16px;">Hey ${firstName},</p>
    <p style="font-size:16px;margin:0 0 20px;">Welcome to Farlo. Here's how to get found:</p>
    <table style="width:100%;border-collapse:collapse;margin:0 0 20px;">
      <tr><td style="padding:10px 0;border-bottom:1px solid #f0f0f0;font-size:15px;"><strong>1. Tap "Open for Business"</strong> on your dashboard — that's what puts you on the map. Everything else builds on this.</td></tr>
      <tr><td style="padding:10px 0;border-bottom:1px solid #f0f0f0;font-size:15px;"><strong>2. Add a photo</strong> — it's the first thing people see before they tap your profile.</td></tr>
      <tr><td style="padding:10px 0;border-bottom:1px solid #f0f0f0;font-size:15px;"><strong>3. Set your address</strong> — for fixed locations. Food trucks and pop-ups share their live GPS location automatically when you're open.</td></tr>
      <tr><td style="padding:10px 0;font-size:15px;"><strong>4. Write a short description</strong> — one or two sentences on what you make and what sets you apart.</td></tr>
    </table>
    <p style="font-size:16px;margin:0 0 20px;">Once those are done, you're live.</p>
    <p style="font-size:16px;margin:0;">— <strong>Johnny</strong>, Farlo</p>
  `);
}

function email2Html(firstName: string): string {
  return emailBase(`
    <p style="font-size:16px;margin:0 0 16px;">Hey ${firstName},</p>
    <p style="font-size:16px;margin:0 0 16px;">Quick tip: businesses with a menu get significantly more profile taps than ones without.</p>
    <p style="font-size:15px;margin:0 0 8px;"><strong>Add your menu:</strong></p>
    <p style="font-size:15px;margin:0 0 20px;color:#555;">Account → Menu → Add Item. Even a basic list of your most popular dishes helps people know what to expect before they show up.</p>
    <p style="font-size:15px;font-weight:600;margin:0 0 12px;">A few more things worth doing this week:</p>
    <table style="width:100%;border-collapse:collapse;margin:0 0 20px;">
      <tr><td style="padding:10px 0;border-bottom:1px solid #f0f0f0;font-size:15px;"><strong>Write your bio</strong> — one or two sentences on what you make and what sets you apart.</td></tr>
      <tr><td style="padding:10px 0;border-bottom:1px solid #f0f0f0;font-size:15px;"><strong>Set your hours</strong> — so people know when to expect you.</td></tr>
      <tr><td style="padding:10px 0;font-size:15px;"><strong>Use the Announce button</strong> — tap it to push a notification to everyone following you. Daily specials, new items, location updates.</td></tr>
    </table>
    <p style="font-size:16px;margin:0;">— <strong>Johnny</strong>, Farlo</p>
  `);
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const resendKey = Deno.env.get('RESEND_API_KEY');
  if (!resendKey) {
    console.warn('RESEND_API_KEY not set — skipping onboarding emails');
    return new Response(JSON.stringify({ sent: false, reason: 'no_resend_key' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let owner_id: string, subscription_id: string;
  try {
    ({ owner_id, subscription_id } = await req.json());
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  if (!owner_id || !subscription_id) {
    return new Response(
      JSON.stringify({ error: 'Missing owner_id or subscription_id' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const { data: sub, error: subError } = await supabase
    .from('subscriptions')
    .select('id, owner_id, status')
    .eq('id', subscription_id)
    .eq('owner_id', owner_id)
    .single();

  if (subError || !sub) {
    return new Response(
      JSON.stringify({ error: 'subscription_not_found' }),
      { status: 404, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('email, display_name')
    .eq('id', owner_id)
    .single();

  if (profileError || !profile) {
    return new Response(
      JSON.stringify({ error: 'profile_not_found' }),
      { status: 404, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const firstName = profile.display_name?.split(' ')[0] ?? 'there';
  const ownerEmail = profile.email;

  const day2 = new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString();

  await sendEmail(resendKey, ownerEmail, "You're on Farlo — here's how to go live", email1Html(firstName));
  await sendEmail(resendKey, ownerEmail, 'Make your Farlo profile convert', email2Html(firstName), day2);

  console.log(`Onboarding emails 1 & 2 queued for ${ownerEmail}`);

  return new Response(
    JSON.stringify({ success: true, owner: ownerEmail }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
