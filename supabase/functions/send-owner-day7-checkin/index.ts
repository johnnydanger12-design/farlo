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
): Promise<void> {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${resendKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'Johnny at Farlo <support@farlo.app>',
      reply_to: 'support@farlo.app',
      to: [to],
      subject,
      html,
    }),
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

// Sent when has_ever_opened = true — focus on growth and monetization
function emailGoneLiveHtml(firstName: string, businessName: string): string {
  return emailBase(`
    <p style="font-size:16px;margin:0 0 16px;">Hey ${firstName},</p>
    <p style="font-size:16px;margin:0 0 20px;">${businessName} has been on the map for a week. Here's what moves the needle from here:</p>
    <table style="width:100%;border-collapse:collapse;margin:0 0 20px;">
      <tr><td style="padding:10px 0;border-bottom:1px solid #f0f0f0;font-size:15px;"><strong>Post announcements regularly.</strong> Every Announce pushes a notification to your followers. A few times a week keeps you top of mind — daily specials, where you're at, new menu items.</td></tr>
      <tr><td style="padding:10px 0;font-size:15px;"><strong>Set up online ordering.</strong> Connect your Stripe account from your dashboard. Orders go directly to your bank — Farlo doesn't take a cut of sales.</td></tr>
    </table>
    <p style="font-size:16px;margin:0;">— <strong>Johnny</strong>, Farlo</p>
  `);
}

// Sent when has_ever_opened = false — direct nudge to go live
function emailNotLiveHtml(firstName: string, businessName: string): string {
  return emailBase(`
    <p style="font-size:16px;margin:0 0 16px;">Hey ${firstName},</p>
    <p style="font-size:16px;margin:0 0 16px;">You signed up for Farlo a week ago, but ${businessName} isn't showing up on the map yet.</p>
    <p style="font-size:16px;margin:0 0 16px;">The only thing between you and being found: open the app and tap <strong>"Open for Business"</strong> on your dashboard.</p>
    <p style="font-size:16px;margin:0 0 20px;">That's it. One tap and you're live.</p>
    <p style="font-size:15px;color:#555;margin:0 0 20px;">If you haven't finished your profile yet, start with a photo and your location — then go live.</p>
    <p style="font-size:16px;margin:0;">— <strong>Johnny</strong>, Farlo</p>
  `);
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const resendKey = Deno.env.get('RESEND_API_KEY');
  if (!resendKey) {
    console.warn('RESEND_API_KEY not set — skipping day-7 checkin emails');
    return new Response(JSON.stringify({ sent: false, reason: 'no_resend_key' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const sixDaysAgo = new Date(Date.now() - 6 * 24 * 60 * 60 * 1000).toISOString();
  const eightDaysAgo = new Date(Date.now() - 8 * 24 * 60 * 60 * 1000).toISOString();

  // Find owners whose onboarding kicked off 6–8 days ago and haven't received email 3 yet
  const { data: eligible, error } = await supabase
    .from('subscriptions')
    .select('id, owner_id')
    .in('status', ['trialing', 'active'])
    .not('onboarding_emails_sent_at', 'is', null)
    .lt('onboarding_emails_sent_at', sixDaysAgo)
    .gt('onboarding_emails_sent_at', eightDaysAgo)
    .is('onboarding_email3_sent_at', null);

  if (error) {
    console.error('Error fetching eligible owners:', error);
    return new Response(JSON.stringify({ error: 'db_error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  if (!eligible || eligible.length === 0) {
    console.log('No owners due for day-7 email');
    return new Response(JSON.stringify({ sent: 0 }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let sentCount = 0;

  for (const sub of eligible) {
    const { data: profile } = await supabase
      .from('profiles')
      .select('email, display_name')
      .eq('id', sub.owner_id)
      .single();

    if (!profile?.email) {
      console.warn(`No profile for owner ${sub.owner_id} — skipping`);
      continue;
    }

    const { data: truck } = await supabase
      .from('food_trucks')
      .select('name, has_ever_opened')
      .eq('owner_id', sub.owner_id)
      .maybeSingle();

    const firstName = profile.display_name?.split(' ')[0] ?? 'there';
    const businessName = truck?.name ?? 'your business';
    const hasEverOpened = truck?.has_ever_opened === true;

    const subject = hasEverOpened
      ? 'Here\'s what to focus on next'
      : `${businessName} still isn't on the map`;

    const html = hasEverOpened
      ? emailGoneLiveHtml(firstName, businessName)
      : emailNotLiveHtml(firstName, businessName);

    await sendEmail(resendKey, profile.email, subject, html);

    // Stamp sent-at so this owner is never picked up again
    await supabase
      .from('subscriptions')
      .update({ onboarding_email3_sent_at: new Date().toISOString() })
      .eq('id', sub.id);

    console.log(`Day-7 email (${hasEverOpened ? 'growth' : 'nudge'}) sent to ${profile.email} (${businessName})`);
    sentCount++;
  }

  return new Response(
    JSON.stringify({ sent: sentCount }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
