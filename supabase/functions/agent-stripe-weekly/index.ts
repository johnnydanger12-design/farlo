// Runs Fridays 16:00. Pure reporting, no actions/tools needed — fetches Stripe data
// deterministically, asks Claude for a well-written summary (no tool loop required),
// then sends it. Note: Farlo's subscription revenue is Apple/Google IAP, not Stripe —
// this only ever reflects order/booking-deposit payments (see prompt).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAgentSecret, isDryRun } from '../_shared/auth.ts';
import { startRun, finishRun } from '../_shared/run-log.ts';
import { sendEmail } from '../_shared/notify.ts';
import { runAgentLoop, MODEL_SONNET } from '../_shared/claude-agent.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const STRIPE_API = 'https://api.stripe.com/v1';

async function stripeGet(path: string, secretKey: string): Promise<{ data: unknown[] }> {
  const res = await fetch(`${STRIPE_API}${path}`, {
    headers: { Authorization: `Bearer ${secretKey}` },
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Stripe API error (${res.status}) ${path}: ${err}`);
  }
  return res.json();
}

const SYSTEM_PROMPT = `You are writing a weekly Stripe activity summary for Johnny Winburn, founder of Farlo (farlo.app) — a two-sided food marketplace. Stripe Connect Express is used for business owner payments; funds go directly to the owner's bank, Farlo never holds money. Stripe activity here is order payments and booking deposits only — Farlo's $29.99/mo or $299.99/yr subscription revenue comes via Apple/Google in-app purchase, not Stripe, so it will never appear here.

Write a short report with these sections: Payments Processed, Payouts, Disputes / Issues (flag these clearly if any), New Connected Accounts, Notes. If there's no activity at all (expected pre-launch), just say so plainly — that's a useful signal, not a failure. Keep it tight. Return only the report text, no preamble.`;

Deno.serve(async (req: Request) => {
  const authError = requireAgentSecret(req);
  if (authError) return authError;
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const dryRun = isDryRun(req);
  const runId = await startRun(supabase, 'agent-stripe-weekly', dryRun ? 'dry_run' : undefined);

  try {
    const stripeKey = Deno.env.get('STRIPE_SECRET_KEY');
    if (!stripeKey) throw new Error('STRIPE_SECRET_KEY not configured');

    const sevenDaysAgoTs = Math.floor((Date.now() - 7 * 24 * 60 * 60 * 1000) / 1000);
    const query = `created[gte]=${sevenDaysAgoTs}&limit=100`;

    const [charges, payouts, disputes, accounts] = await Promise.all([
      stripeGet(`/charges?${query}`, stripeKey),
      stripeGet(`/payouts?${query}`, stripeKey),
      stripeGet(`/disputes?${query}`, stripeKey),
      stripeGet(`/accounts?${query}`, stripeKey),
    ]);

    const userMessage = [
      `Date range: last 7 days (since ${new Date(sevenDaysAgoTs * 1000).toISOString().slice(0, 10)}).`,
      ``,
      `Charges (raw Stripe charge objects):`,
      JSON.stringify(charges.data, null, 2),
      ``,
      `Payouts:`,
      JSON.stringify(payouts.data, null, 2),
      ``,
      `Disputes:`,
      JSON.stringify(disputes.data, null, 2),
      ``,
      `New Connected Accounts created this week:`,
      JSON.stringify(accounts.data, null, 2),
    ].join('\n');

    const result = await runAgentLoop({
      systemPrompt: SYSTEM_PROMPT,
      userMessage,
      tools: [],
      handlers: {},
      model: MODEL_SONNET,
    });

    if (!dryRun) {
      await sendEmail({
        to: 'johnny@farlo.app',
        subject: `Stripe Weekly — ${new Date().toISOString().slice(0, 10)}`,
        text: result.finalText,
        from: 'Aiden <aiden@farlo.app>',
      });
    }

    await finishRun(supabase, runId, 'success', dryRun ? '[dry run] report generated, not sent' : 'Weekly Stripe report sent.');

    return new Response(JSON.stringify({ report: result.finalText, dry_run: dryRun }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    await finishRun(supabase, runId, 'failed', undefined, String(err));
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
