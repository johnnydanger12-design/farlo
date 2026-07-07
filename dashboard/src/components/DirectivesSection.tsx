import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Card, ErrorNote, Loading, Pill } from './ui';

interface Directive {
  directive_key: string;
  content: string;
  updated_at: string;
  updated_by: string;
  locked: boolean;
}

const AGENT_NAMES = [
  'agent-sage',
  'agent-miles',
  'agent-piper',
  'agent-aiden-supervisor',
  'agent-run-check',
  'agent-newsletter-cleanup',
  'agent-stripe-weekly',
  'agent-urgent-alert',
  'agent-email-labeler',
];

export function DirectivesSection() {
  const [directives, setDirectives] = useState<Directive[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editingKey, setEditingKey] = useState<string | null>(null);
  const [draft, setDraft] = useState('');
  const [saving, setSaving] = useState(false);
  const [triggering, setTriggering] = useState<string | null>(null);
  const [triggerMessage, setTriggerMessage] = useState<string | null>(null);

  async function load() {
    const { data, error } = await supabase
      .from('agent_directives')
      .select('directive_key, content, updated_at, updated_by, locked')
      .order('directive_key', { ascending: true });
    if (error) setError(error.message);
    else setDirectives(data as Directive[]);
  }

  useEffect(() => {
    load();
  }, []);

  function startEdit(d: Directive) {
    setEditingKey(d.directive_key);
    setDraft(d.content);
  }

  async function save(key: string) {
    setSaving(true);
    const { error } = await supabase
      .from('agent_directives')
      .update({ content: draft, updated_by: 'founder_dashboard' })
      .eq('directive_key', key);
    setSaving(false);
    if (error) {
      setError(error.message);
      return;
    }
    setEditingKey(null);
    load();
  }

  async function triggerAgent(name: string) {
    setTriggering(name);
    setTriggerMessage(null);
    const { error } = await supabase.rpc('founder_trigger_agent', { fn_name: name });
    setTriggering(null);
    setTriggerMessage(error ? `Failed: ${error.message}` : `${name} triggered.`);
  }

  return (
    <div className="grid gap-6">
      <Card title="Run an agent now">
        <div className="flex flex-wrap gap-2">
          {AGENT_NAMES.map((name) => (
            <button
              key={name}
              onClick={() => triggerAgent(name)}
              disabled={triggering !== null}
              className="rounded-md border border-[var(--border)] px-3 py-1.5 text-sm hover:border-[var(--accent)] disabled:opacity-50"
            >
              {triggering === name ? 'Triggering…' : name}
            </button>
          ))}
        </div>
        {triggerMessage && <p className="mt-3 text-sm text-[var(--muted)]">{triggerMessage}</p>}
      </Card>

      <Card title="Directives">
        {error && <ErrorNote message={error} />}
        {!directives ? (
          <Loading />
        ) : (
          <div className="flex flex-col gap-3">
            {directives.map((d) => (
              <div key={d.directive_key} className="rounded-lg border border-[var(--border)] p-3">
                <div className="mb-2 flex items-center justify-between gap-2">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium">{d.directive_key}</span>
                    {d.locked && <Pill tone="warn">locked</Pill>}
                  </div>
                  <span className="text-xs text-[var(--muted)]">
                    updated {new Date(d.updated_at).toLocaleDateString()} by {d.updated_by}
                  </span>
                </div>
                {editingKey === d.directive_key ? (
                  <div className="flex flex-col gap-2">
                    <textarea
                      value={draft}
                      onChange={(e) => setDraft(e.target.value)}
                      rows={8}
                      className="w-full rounded-md border border-[var(--border)] bg-black/20 p-2 text-sm outline-none focus:border-[var(--accent)]"
                    />
                    <div className="flex gap-2">
                      <button
                        onClick={() => save(d.directive_key)}
                        disabled={saving}
                        className="rounded-md bg-[var(--accent)] px-3 py-1.5 text-sm font-medium text-[#04121f] disabled:opacity-50"
                      >
                        {saving ? 'Saving…' : 'Save'}
                      </button>
                      <button
                        onClick={() => setEditingKey(null)}
                        className="rounded-md border border-[var(--border)] px-3 py-1.5 text-sm"
                      >
                        Cancel
                      </button>
                    </div>
                  </div>
                ) : (
                  <div>
                    <p className="whitespace-pre-wrap text-sm text-[var(--muted)] line-clamp-3">
                      {d.content}
                    </p>
                    {!d.locked && (
                      <button
                        onClick={() => startEdit(d)}
                        className="mt-2 text-xs text-[var(--accent)]"
                      >
                        Edit
                      </button>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}
