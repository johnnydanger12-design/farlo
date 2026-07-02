// Runs every 15 min. Purely mechanical — no Claude call needed. This is the fix for the
// biggest gap in the old system: an urgent support ticket (billing dispute, account
// deletion) used to sit until Aiden's weekly brief. Now it reaches Johnny within 15 min.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAgentSecret, isDryRun } from '../_shared/auth.ts';
import { startRun, finishRun } from '../_shared/run-log.ts';
import { sendEmail } from '../_shared/notify.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

Deno.serve(async (req: Request) => {
  const authError = requireAgentSecret(req);
  if (authError) return authError;
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const dryRun = isDryRun(req);
  const runId = await startRun(supabase, 'agent-urgent-alert', dryRun ? 'dry_run' : undefined);

  try {
    const { data: tickets, error } = await supabase
      .from('support_tickets')
      .select('id, from_name, from_email, subject, body, escalation_reason, created_at')
      .eq('priority', 'urgent')
      .is('urgent_alert_sent_at', null)
      .order('created_at', { ascending: true })
      .limit(25);

    if (error) throw new Error(`support_tickets query failed: ${error.message}`);

    if (!tickets || tickets.length === 0) {
      await finishRun(supabase, runId, 'success', 'No new urgent tickets.');
      return new Response(JSON.stringify({ alerted: 0 }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const rows = tickets
      .map((t) => `- "${t.subject}" from ${t.from_name ?? t.from_email} (${t.from_email}) — ${new Date(t.created_at).toLocaleString()}${t.escalation_reason ? `\n  Why: ${t.escalation_reason}` : ''}\n  ${t.body.slice(0, 200)}${t.body.length > 200 ? '...' : ''}`)
      .join('\n\n');

    const subject = tickets.length === 1
      ? 'Urgent support ticket needs you'
      : `${tickets.length} urgent support tickets need you`;

    const text = `These support tickets are flagged urgent and need your personal attention — Sage didn't draft a reply, this needs judgment:\n\n${rows}\n\nCheck support@farlo.app.`;

    if (!dryRun) {
      await sendEmail({
        to: 'johnny@farlo.app',
        subject,
        text,
        from: 'Farlo Alerts <aiden@farlo.app>',
      });

      const ids = tickets.map((t) => t.id);
      const { error: stampError } = await supabase
        .from('support_tickets')
        .update({ urgent_alert_sent_at: new Date().toISOString() })
        .in('id', ids);
      if (stampError) throw new Error(`Failed to stamp urgent_alert_sent_at: ${stampError.message}`);
    }

    await finishRun(
      supabase,
      runId,
      'success',
      `${dryRun ? '[dry run] would have alerted' : 'Alerted'} on ${tickets.length} urgent ticket(s).`,
    );

    return new Response(JSON.stringify({ alerted: tickets.length, dry_run: dryRun }), {
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
