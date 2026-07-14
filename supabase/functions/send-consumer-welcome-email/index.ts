import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

function emailHtml(firstName: string): string {
  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
</head>
<body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;color:#1a1a1a;max-width:560px;margin:0 auto;padding:32px 20px;">
  <p style="font-size:22px;font-weight:700;margin:0 0 24px;">farlo</p>

  <p style="font-size:16px;margin:0 0 16px;">Hey ${firstName},</p>
  <p style="font-size:16px;margin:0 0 24px;">You're on Farlo — the app that shows you what's open near you, right now.</p>

  <table style="width:100%;border-collapse:collapse;margin:0 0 24px;">
    <tr><td style="padding:10px 0;border-bottom:1px solid #f0f0f0;font-size:15px;"><strong>Follow businesses you love</strong> — tap the heart on any profile to follow them. You'll get a notification every time they post a special, update their location, or go live.</td></tr>
    <tr><td style="padding:10px 0;font-size:15px;"><strong>Order ahead</strong> — when a business has ordering on, browse their menu and place an order right through the app.</td></tr>
  </table>

  <hr style="border:none;border-top:1px solid #e5e5e5;margin:24px 0;" />

  <p style="font-size:14px;color:#555;margin:0 0 8px;">Run a food truck, pop-up, or other food business? You can list it on Farlo too — Account → Manage Account → Start a Business.</p>

  <hr style="border:none;border-top:1px solid #e5e5e5;margin:24px 0;" />

  <p style="font-size:16px;margin:0 0 32px;">— <strong>Johnny</strong>, Farlo</p>

  <img src="https://weflrxyerxpsafcdetya.supabase.co/storage/v1/object/public/brand/Email%20Logo.png" alt="Farlo" style="height:32px;width:auto;display:block;margin:0 0 12px;" />
  <p style="font-size:12px;color:#888;margin:0;">Farlo Technologies LLC &middot; Hartsville, SC<br/>Questions? Reply to this email or contact <a href="mailto:support@farlo.app" style="color:#2563EB;">support@farlo.app</a></p>
</body>
</html>`;
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const resendKey = Deno.env.get('RESEND_API_KEY');
  if (!resendKey) {
    console.warn('RESEND_API_KEY not set — skipping consumer welcome email');
    return new Response(JSON.stringify({ sent: false, reason: 'no_resend_key' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let user_id: string;
  try {
    ({ user_id } = await req.json());
  } catch {
    return new Response('Bad request', { status: 400 });
  }

  if (!user_id) {
    return new Response(
      JSON.stringify({ error: 'Missing user_id' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('email, display_name, role')
    .eq('id', user_id)
    .single();

  if (profileError || !profile) {
    return new Response(
      JSON.stringify({ error: 'profile_not_found' }),
      { status: 404, headers: { 'Content-Type': 'application/json' } },
    );
  }

  if (profile.role !== 'consumer') {
    return new Response(
      JSON.stringify({ skipped: true, reason: 'not_a_consumer' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const firstName = profile.display_name?.split(' ')[0] ?? 'there';

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${resendKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'Johnny at Farlo <support@farlo.app>',
      reply_to: 'support@farlo.app',
      to: [profile.email],
      subject: 'Welcome to Farlo',
      html: emailHtml(firstName),
    }),
  });

  if (!res.ok) {
    const err = await res.text();
    console.error(`Resend error (${res.status}):`, err);
    return new Response(JSON.stringify({ sent: false, reason: 'resend_error' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  console.log(`Consumer welcome email sent to ${profile.email}`);

  return new Response(
    JSON.stringify({ success: true, owner: profile.email }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
