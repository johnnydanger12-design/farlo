// Thin Resend wrapper. New agent functions call Resend directly (matching
// send-owner-day7-checkin's pattern) rather than proxying through send-agent-email —
// one less hop, one less shared-secret dependency for anything built after this point.
// Kept as its own module so a second channel (SMS) can be added later without touching
// call sites — see agent-urgent-alert for the highest-value place that would plug in.

const RESEND_API_URL = 'https://api.resend.com/emails';

export async function sendEmail(opts: {
  to: string | string[];
  subject: string;
  html?: string;
  text?: string;
  from?: string;
  replyTo?: string;
}): Promise<void> {
  const resendKey = Deno.env.get('RESEND_API_KEY');
  if (!resendKey) throw new Error('RESEND_API_KEY not configured');

  const payload: Record<string, unknown> = {
    from: opts.from ?? 'Aiden <aiden@farlo.app>',
    to: Array.isArray(opts.to) ? opts.to : [opts.to],
    subject: opts.subject,
    ...(opts.html ? { html: opts.html } : { text: opts.text }),
    ...(opts.replyTo ? { reply_to: opts.replyTo } : {}),
  };

  const res = await fetch(RESEND_API_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${resendKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Resend error (${res.status}): ${err}`);
  }
}
