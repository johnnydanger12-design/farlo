const RESEND_API_URL = 'https://api.resend.com/emails';

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const secret = Deno.env.get('AGENT_EMAIL_SECRET') ?? '';
  if (!secret || authHeader !== `Bearer ${secret}`) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let body: { to: string | string[]; subject: string; body?: string; html?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const { to, subject, body: text, html } = body;
  if (!to || !subject || (!text && !html)) {
    return new Response(JSON.stringify({ error: 'Missing required fields: to, subject, and body or html' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const resendKey = Deno.env.get('RESEND_API_KEY');
  if (!resendKey) {
    return new Response(JSON.stringify({ error: 'RESEND_API_KEY not configured' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const payload: Record<string, unknown> = {
    from: 'Aiden <aiden@farlo.app>',
    to: Array.isArray(to) ? to : [to],
    subject,
    ...(html ? { html } : { text }),
  };

  const res = await fetch(RESEND_API_URL, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${resendKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  const data = await res.json();

  if (!res.ok) {
    return new Response(JSON.stringify({ error: data }), {
      status: res.status,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(JSON.stringify({ success: true, id: data.id }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
