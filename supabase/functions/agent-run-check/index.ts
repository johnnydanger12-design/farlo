// Runs every 4 hours. Closes the silent-failure gap: alerts if an agent that has
// previously run successfully stops logging successful runs within its expected window.
// Only checks agents that have at least one prior run logged, so this stays quiet during
// incremental rollout rather than alerting on functions not deployed yet.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAgentSecret, isDryRun } from '../_shared/auth.ts';
import { startRun, finishRun } from '../_shared/run-log.ts';
import { sendEmail } from '../_shared/notify.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

// Max allowed hours since last successful run before flagging, sized to each schedule
// with headroom for the normal gap (e.g. Friday evening -> Monday morning for Miles).
const EXPECTED_WINDOWS_HOURS: Record<string, number> = {
  'agent-aiden-inbox': 18,
  'agent-aiden-supervisor': 192,
  'agent-sage': 0.5, // runs every 5 min now — 30 min of silence means something's actually wrong
  'agent-miles': 80,
  'agent-piper': 130,
  'agent-email-labeler': 30,
  'agent-newsletter-cleanup': 840,
  'agent-stripe-weekly': 192,
  'agent-urgent-alert': 2,
};

Deno.serve(async (req: Request) => {
  const authError = requireAgentSecret(req);
  if (authError) return authError;
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const dryRun = isDryRun(req);
  const runId = await startRun(supabase, 'agent-run-check', dryRun ? 'dry_run' : undefined);

  try {
    const stale: { agent_name: string; hoursSince: number; threshold: number }[] = [];

    for (const [agentName, thresholdHours] of Object.entries(EXPECTED_WINDOWS_HOURS)) {
      const { data: lastSuccess, error } = await supabase
        .from('agent_run_log')
        .select('finished_at')
        .eq('agent_name', agentName)
        .eq('status', 'success')
        .order('finished_at', { ascending: false })
        .limit(1)
        .maybeSingle();

      if (error) throw new Error(`agent_run_log query failed for ${agentName}: ${error.message}`);

      // Never having run at all means it isn't deployed/scheduled yet — not our problem.
      const { count } = await supabase
        .from('agent_run_log')
        .select('id', { count: 'exact', head: true })
        .eq('agent_name', agentName);
      if (!count || count === 0) continue;

      if (!lastSuccess) {
        stale.push({ agent_name: agentName, hoursSince: Infinity, threshold: thresholdHours });
        continue;
      }

      const hoursSince = (Date.now() - new Date(lastSuccess.finished_at).getTime()) / (1000 * 60 * 60);
      if (hoursSince > thresholdHours) {
        stale.push({ agent_name: agentName, hoursSince, threshold: thresholdHours });
      }
    }

    if (stale.length === 0) {
      await finishRun(supabase, runId, 'success', 'All agents within expected run windows.');
      return new Response(JSON.stringify({ stale: 0 }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const rows = stale
      .map((s) => `- ${s.agent_name}: no successful run in ${s.hoursSince === Infinity ? 'ever' : `${s.hoursSince.toFixed(1)}h`} (expected within ${s.threshold}h)`)
      .join('\n');

    const text = `These automation agents haven't logged a successful run within their expected window:\n\n${rows}\n\nCheck agent_run_log in Supabase for error_detail on the most recent failed rows.`;

    if (!dryRun) {
      await sendEmail({
        to: 'johnny@farlo.app',
        subject: `${stale.length} agent(s) may be stuck — Farlo automation`,
        text,
        from: 'Farlo Alerts <aiden@farlo.app>',
      });
    }

    await finishRun(
      supabase,
      runId,
      'success',
      `${dryRun ? '[dry run] would have flagged' : 'Flagged'} ${stale.length} stale agent(s).`,
    );

    return new Response(JSON.stringify({ stale: stale.length, dry_run: dryRun }), {
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
