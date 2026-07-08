import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Card, ErrorNote, Loading, Pill } from './ui';

interface Prospect {
  id: string;
  business_name: string;
  outreach_email: string | null;
  status: 'drafted' | 'contacted' | 'responded';
  last_contacted_at: string | null;
}

export function OutreachSection() {
  const [drafted, setDrafted] = useState<Prospect[] | null>(null);
  const [sent, setSent] = useState<Prospect[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [updating, setUpdating] = useState<string | null>(null);

  async function load() {
    const [draftedRes, sentRes] = await Promise.all([
      supabase
        .from('sales_prospects')
        .select('id, business_name, outreach_email, status, last_contacted_at')
        .eq('status', 'drafted')
        .order('business_name', { ascending: true }),
      supabase
        .from('sales_prospects')
        .select('id, business_name, outreach_email, status, last_contacted_at')
        .in('status', ['contacted', 'responded'])
        .order('last_contacted_at', { ascending: false })
        .limit(20),
    ]);
    if (draftedRes.error) setError(draftedRes.error.message);
    else setDrafted(draftedRes.data as Prospect[]);
    if (sentRes.error) setError(sentRes.error.message);
    else setSent(sentRes.data as Prospect[]);
  }

  useEffect(() => {
    load();
  }, []);

  async function markSent(id: string) {
    setUpdating(id);
    const { error } = await supabase
      .from('sales_prospects')
      .update({ status: 'contacted', last_contacted_at: new Date().toISOString(), response_notes: 'Sent by Johnny' })
      .eq('id', id);
    setUpdating(null);
    if (error) {
      setError(error.message);
      return;
    }
    load();
  }

  if (error) return <Card title="Outreach"><ErrorNote message={error} /></Card>;
  if (!drafted || !sent) return <Card title="Outreach"><Loading /></Card>;

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
                className="flex items-center justify-between gap-3 rounded-lg border border-[var(--border)] p-3"
              >
                <div>
                  <p className="text-sm font-medium">{p.business_name}</p>
                  <p className="text-xs text-[var(--muted)]">{p.outreach_email}</p>
                </div>
                <button
                  onClick={() => markSent(p.id)}
                  disabled={updating === p.id}
                  className="rounded-md bg-[var(--accent)] px-3 py-1.5 text-xs font-medium text-[#04121f] disabled:opacity-50"
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

      <Card title="Recently contacted">
        {sent.length === 0 ? (
          <p className="text-sm text-[var(--muted)]">No sent outreach yet.</p>
        ) : (
          <div className="flex flex-col gap-2">
            {sent.map((p) => (
              <div key={p.id} className="flex items-center justify-between gap-3 rounded-lg border border-[var(--border)] p-3">
                <div>
                  <p className="text-sm font-medium">{p.business_name}</p>
                  <p className="text-xs text-[var(--muted)]">{p.outreach_email}</p>
                </div>
                <div className="flex items-center gap-2">
                  <Pill tone={p.status === 'responded' ? 'good' : 'muted'}>{p.status}</Pill>
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
