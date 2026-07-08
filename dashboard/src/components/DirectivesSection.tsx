import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Card, ErrorNote, Loading, Modal, Pill } from './ui';

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
  const [openKey, setOpenKey] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
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

  const openDirective = directives?.find((d) => d.directive_key === openKey) ?? null;

  function openRow(d: Directive) {
    setOpenKey(d.directive_key);
    setEditing(false);
    setDraft(d.content);
  }

  function closeModal() {
    setOpenKey(null);
    setEditing(false);
  }

  async function save() {
    if (!openKey) return;
    setSaving(true);
    const { error } = await supabase
      .from('agent_directives')
      .update({ content: draft, updated_by: 'founder_dashboard' })
      .eq('directive_key', openKey);
    setSaving(false);
    if (error) {
      setError(error.message);
      return;
    }
    setEditing(false);
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
    <div className="flex min-w-0 flex-col gap-6">
      <Card title="Run an agent now">
        <div className="-mx-1 flex gap-2 overflow-x-auto px-1 pb-1">
          {AGENT_NAMES.map((name) => (
            <button
              key={name}
              onClick={() => triggerAgent(name)}
              disabled={triggering !== null}
              className="shrink-0 whitespace-nowrap rounded-md border border-[var(--border)] px-3 py-1.5 text-sm hover:border-[var(--accent)] disabled:opacity-50"
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
          <div className="flex flex-col gap-2">
            {directives.map((d) => (
              <button
                key={d.directive_key}
                onClick={() => openRow(d)}
                className="flex min-w-0 items-center justify-between gap-2 rounded-lg border border-[var(--border)] p-3 text-left hover:border-[var(--accent)]"
              >
                <span className="min-w-0 truncate text-sm font-medium">{d.directive_key}</span>
                <span className="flex shrink-0 items-center gap-2">
                  {d.locked && <Pill tone="warn">locked</Pill>}
                  <span className="text-xs text-[var(--muted)]">
                    {new Date(d.updated_at).toLocaleDateString()}
                  </span>
                </span>
              </button>
            ))}
          </div>
        )}
      </Card>

      <Modal open={openDirective !== null} onClose={closeModal} title={openDirective?.directive_key ?? ''}>
        {openDirective && (
          <div>
            <p className="mb-3 text-xs text-[var(--muted)]">
              Updated {new Date(openDirective.updated_at).toLocaleDateString()} by {openDirective.updated_by}
              {openDirective.locked && (
                <>
                  {' · '}
                  <Pill tone="warn">locked</Pill>
                </>
              )}
            </p>
            {editing ? (
              <div className="flex flex-col gap-2">
                <textarea
                  value={draft}
                  onChange={(e) => setDraft(e.target.value)}
                  rows={12}
                  className="w-full rounded-md border border-[var(--border)] bg-black/20 p-2 text-sm outline-none focus:border-[var(--accent)]"
                />
                <div className="flex gap-2">
                  <button
                    onClick={save}
                    disabled={saving}
                    className="rounded-md bg-[var(--accent)] px-3 py-1.5 text-sm font-medium text-[#04121f] disabled:opacity-50"
                  >
                    {saving ? 'Saving…' : 'Save'}
                  </button>
                  <button
                    onClick={() => setEditing(false)}
                    className="rounded-md border border-[var(--border)] px-3 py-1.5 text-sm"
                  >
                    Cancel
                  </button>
                </div>
              </div>
            ) : (
              <div>
                <p className="whitespace-pre-wrap break-words text-sm text-[var(--muted)]">
                  {openDirective.content}
                </p>
                {!openDirective.locked && (
                  <button
                    onClick={() => setEditing(true)}
                    className="mt-3 text-xs text-[var(--accent)]"
                  >
                    Edit
                  </button>
                )}
              </div>
            )}
          </div>
        )}
      </Modal>
    </div>
  );
}
