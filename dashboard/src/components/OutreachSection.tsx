import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Card, ErrorNote, Loading, Pill } from './ui';

interface Prospect {
  id: string;
  business_name: string;
  outreach_email: string | null;
  status: 'drafted' | 'contacted' | 'responded';
  follow_up_count: number;
  last_contacted_at: string | null;
}

interface FollowupProspect {
  id: string;
  business_name: string;
  outreach_email: string | null;
  follow_up_count: number;
}

export function OutreachSection() {
  const [drafted, setDrafted] = useState<Prospect[] | null>(null);
  const [followupsDrafted, setFollowupsDrafted] = useState<FollowupProspect[] | null>(null);
  const [sent, setSent] = useState<Prospect[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [updating, setUpdating] = useState<string | null>(null);

  async function load() {
    const [draftedRes, followupRes, sentRes] = await Promise.all([
      supabase
        .from('sales_prospects')
        .select('id, business_name, outreach_email, status, follow_up_count, last_contacted_at')
        .eq('status', 'drafted')
        .order('business_name', { ascending: true }),
      supabase
        .from('sales_prospects')
        .select('id, business_name, outreach_email, follow_up_count')
        .not('pending_followup_subject', 'is', null)
        .order('business_name', { ascending: true }),
      supabase
        .from('sales_prospects')
        .select('id, business_name, outreach_email, status, follow_up_count, last_contacted_at')
        .in('status', ['contacted', 'responded'])
        .order('last_contacted_at', { ascending: false })
        .limit(20),
    ]);
    if (draftedRes.error) setError(draftedRes.error.message);
    else setDrafted(draftedRes.data as Prospect[]);
    if (followupRes.error) setError(followupRes.error.message);
    else setFollowupsDrafted(followupRes.data as FollowupProspect[]);
    if (sentRes.error) setError(sentRes.error.message);
    else setSent(sentRes.data as Prospect[]);
  }

  useEffect(() => {
    load();
  }, []);

  async function markInitialSent(id: string) {
    setUpdating(id);
    const now = new Date().toISOString();
    const { error } = await supabase
      .from('sales_prospects')
      .update({ status: 'contacted', first_contacted_at: now, last_contacted_at: now, response_notes: 'Sent by Johnny' })
      .eq('id', id);
    setUpdating(null);
    if (error) {
      setError(error.message);
      return;
    }
    load();
  }

  async function markFollowupSent(prospect: FollowupProspect) {
    setUpdating(prospect.id);
    const { data: row, error: readError } = await supabase
      .from('sales_prospects')
      .select('pending_followup_subject, pending_followup_body')
      .eq('id', prospect.id)
      .single();
    if (readError || !row) {
      setUpdating(null);
      setError(readError?.message ?? 'Could not read pending follow-up');
      return;
    }
    const { error } = await supabase
      .from('sales_prospects')
      .update({
        follow_up_count: prospect.follow_up_count + 1,
        last_contacted_at: new Date().toISOString(),
        last_email_subject: row.pending_followup_subject,
        last_email_body: row.pending_followup_body,
        pending_followup_subject: null,
        pending_followup_body: null,
        response_notes: 'Follow-up sent by Johnny',
      })
      .eq('id', prospect.id);
    setUpdating(null);
    if (error) {
      setError(error.message);
      return;
    }
    load();
  }

  if (error) return <Card title="Outreach"><ErrorNote message={error} /></Card>;
  if (!drafted || !followupsDrafted || !sent) return <Card title="Outreach"><Loading /></Card>;

  return (
    <div className="grid gap-6">
      <Card title="Drafted — waiting for you to send">
        {drafted.length === 0 ? (
          <p className="text-sm text-[var(--muted)]">Nothing drafted right now.</p>
        ) : (
          <div className="flex flex-col gap-2">
            {drafted.map((p) => (
              <div
                key={p.id}
                className="flex min-w-0 items-center justify-between gap-3 rounded-lg border border-[var(--border)] p-3"
              >
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">{p.business_name}</p>
                  <p className="truncate text-xs text-[var(--muted)]">{p.outreach_email}</p>
                </div>
                <button
                  onClick={() => markInitialSent(p.id)}
                  disabled={updating === p.id}
                  className="shrink-0 rounded-md bg-[var(--accent)] px-3 py-1.5 text-xs font-medium text-[#04121f] disabled:opacity-50"
                >
                  {updating === p.id ? 'Marking…' : 'Mark sent'}
                </button>
              </div>
            ))}
          </div>
        )}
        <p className="mt-3 text-xs text-[var(--muted)]">
          Miles saves these as Gmail drafts under outreach@farlo.app — check that mailbox to review and actually send. Marking one sent here starts its follow-up clock.
        </p>
      </Card>

      <Card title="Follow-ups drafted — waiting for you to send">
        {followupsDrafted.length === 0 ? (
          <p className="text-sm text-[var(--muted)]">No follow-ups drafted right now.</p>
        ) : (
          <div className="flex flex-col gap-2">
            {followupsDrafted.map((p) => (
              <div
                key={p.id}
                className="flex min-w-0 items-center justify-between gap-3 rounded-lg border border-[var(--border)] p-3"
              >
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">{p.business_name}</p>
                  <p className="truncate text-xs text-[var(--muted)]">
                    {p.outreach_email} · follow-up #{p.follow_up_count + 1}
                  </p>
                </div>
                <button
                  onClick={() => markFollowupSent(p)}
                  disabled={updating === p.id}
                  className="shrink-0 rounded-md bg-[var(--accent)] px-3 py-1.5 text-xs font-medium text-[#04121f] disabled:opacity-50"
                >
                  {updating === p.id ? 'Marking…' : 'Mark sent'}
                </button>
              </div>
            ))}
          </div>
        )}
      </Card>

      <Card title="Recently contacted">
        {sent.length === 0 ? (
          <p className="text-sm text-[var(--muted)]">No sent outreach yet.</p>
        ) : (
          <div className="flex flex-col gap-2">
            {sent.map((p) => (
              <div key={p.id} className="flex min-w-0 flex-wrap items-center justify-between gap-2 rounded-lg border border-[var(--border)] p-3">
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">{p.business_name}</p>
                  <p className="truncate text-xs text-[var(--muted)]">{p.outreach_email}</p>
                </div>
                <div className="flex shrink-0 items-center gap-2">
                  <Pill tone={p.status === 'responded' ? 'good' : 'muted'}>{p.status}</Pill>
                  {p.follow_up_count > 0 && <Pill tone="muted">{p.follow_up_count} follow-up(s)</Pill>}
                  <span className="text-xs text-[var(--muted)]">
                    {p.last_contacted_at ? new Date(p.last_contacted_at).toLocaleDateString() : '—'}
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}
