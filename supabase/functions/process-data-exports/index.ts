// Cron-triggered background worker (see cron job entry + agent_cron_call,
// same shared-bearer-secret mechanism as agent-stripe-weekly). Does the
// actual heavy lifting for the GDPR data-export pipeline: claims pending
// requests, compiles each user's data via compile_user_data_export(),
// uploads the result to the private data-exports Storage bucket, mints a
// short-lived signed URL, and notifies the user. Also expires old completed
// exports past their retention window.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { requireAgentSecret } from '../_shared/auth.ts';
import { sendEmail } from '../_shared/notify.ts';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
);

const BUCKET = 'data-exports';
const SIGNED_URL_TTL_SECONDS = 7 * 24 * 60 * 60; // 7 days — matches expires_at below

async function notifyReady(userId: string, email: string | null, requestId: string, downloadUrl: string) {
  await supabase.from('notifications').insert({
    user_id: userId,
    type: 'data_export_ready',
    title: 'Your data export is ready',
    body: 'Tap to download a copy of your Farlo data. This link expires in 7 days.',
    related_id: requestId,
  });

  if (!email) return;
  try {
    await sendEmail({
      to: email,
      subject: 'Your Farlo data export is ready',
      html: `<p>Your requested export of your Farlo account data is ready.</p>
<p><a href="${downloadUrl}">Download your data</a></p>
<p>This link expires in 7 days. If you didn't request this, you can safely ignore this email.</p>`,
    });
  } catch (e) {
    console.error(`Failed to email export-ready notice to ${email}:`, e);
  }
}

async function processOneRequest(request: { id: string; user_id: string }): Promise<void> {
  try {
    const { data: exportData, error: compileError } = await supabase.rpc('compile_user_data_export', {
      p_user_id: request.user_id,
    });
    if (compileError) throw compileError;

    const path = `${request.user_id}/${request.id}.json`;
    const { error: uploadError } = await supabase.storage
      .from(BUCKET)
      .upload(path, JSON.stringify(exportData, null, 2), {
        contentType: 'application/json',
        upsert: true,
      });
    if (uploadError) throw uploadError;

    const { data: signed, error: signError } = await supabase.storage
      .from(BUCKET)
      .createSignedUrl(path, SIGNED_URL_TTL_SECONDS);
    if (signError || !signed) throw signError ?? new Error('createSignedUrl returned no data');

    const expiresAt = new Date(Date.now() + SIGNED_URL_TTL_SECONDS * 1000).toISOString();

    const { error: updateError } = await supabase
      .from('data_export_requests')
      .update({
        status: 'completed',
        completed_at: new Date().toISOString(),
        expires_at: expiresAt,
        storage_path: path,
        download_url: signed.signedUrl,
      })
      .eq('id', request.id);
    if (updateError) throw updateError;

    const { data: profile } = await supabase
      .from('profiles')
      .select('email')
      .eq('id', request.user_id)
      .maybeSingle();

    await notifyReady(request.user_id, profile?.email ?? null, request.id, signed.signedUrl);
  } catch (e) {
    console.error(`Failed to process data export request ${request.id}:`, e);
    await supabase
      .from('data_export_requests')
      .update({ status: 'failed', error_message: String(e) })
      .eq('id', request.id);
  }
}

async function expireOldExports(): Promise<number> {
  const { data: toExpire, error } = await supabase
    .from('data_export_requests')
    .select('id, storage_path')
    .eq('status', 'completed')
    .lt('expires_at', new Date().toISOString());

  if (error || !toExpire || toExpire.length === 0) return 0;

  for (const row of toExpire) {
    if (row.storage_path) {
      await supabase.storage.from(BUCKET).remove([row.storage_path]);
    }
    await supabase
      .from('data_export_requests')
      .update({ status: 'expired', storage_path: null, download_url: null })
      .eq('id', row.id);
  }
  return toExpire.length;
}

Deno.serve(async (req: Request) => {
  const authError = requireAgentSecret(req);
  if (authError) return authError;
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  // Atomic claim: only rows still 'pending' at the moment of this UPDATE are
  // claimed, so an overlapping invocation (shouldn't happen at this cron
  // frequency, but Postgres row locking makes it safe regardless) can't
  // double-process the same request.
  const { data: claimed, error: claimError } = await supabase
    .from('data_export_requests')
    .update({ status: 'processing' })
    .eq('status', 'pending')
    .select('id, user_id');

  if (claimError) {
    return new Response(JSON.stringify({ error: claimError.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  for (const request of claimed ?? []) {
    await processOneRequest(request);
  }

  const expiredCount = await expireOldExports();

  return new Response(
    JSON.stringify({ processed: claimed?.length ?? 0, expired: expiredCount }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
});
