// Runs 1st of month, 17:00. Pure mechanical cleanup — no judgment call involved, so no
// Claude call at all.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAgentSecret, isDryRun } from '../_shared/auth.ts';
import { startRun, finishRun } from '../_shared/run-log.ts';
import { getGmailAccessToken, searchThreads, getLabelIdMap, addLabel, removeLabel } from '../_shared/gmail.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

Deno.serve(async (req: Request) => {
  const authError = requireAgentSecret(req);
  if (authError) return authError;
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  const dryRun = isDryRun(req);
  const runId = await startRun(supabase, 'agent-newsletter-cleanup', dryRun ? 'dry_run' : undefined);

  try {
    const accessToken = await getGmailAccessToken('johnny@farlo.app');
    const labelIds = await getLabelIdMap(accessToken);
    const trashLabelId = labelIds['TRASH'];
    const inboxLabelId = labelIds['INBOX'];

    const threads = await searchThreads(accessToken, 'label:Newsletters older_than:30d', 100);

    if (threads.length === 0) {
      await finishRun(supabase, runId, 'success', 'Nothing to clean up.');
      return new Response(JSON.stringify({ trashed: 0 }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    let trashed = 0;
    for (const t of threads) {
      if (!dryRun) {
        if (trashLabelId) await addLabel(accessToken, t.id, trashLabelId);
        if (inboxLabelId) {
          try {
            await removeLabel(accessToken, t.id, inboxLabelId);
          } catch {
            // already out of inbox — fine
          }
        }
      }
      trashed++;
    }

    await finishRun(supabase, runId, 'success', `${dryRun ? '[dry run] would have trashed' : 'Trashed'} ${trashed} thread(s).`);

    return new Response(JSON.stringify({ trashed, dry_run: dryRun }), {
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
