import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Card, ErrorNote, Loading, Pill } from './ui';

interface ContentItem {
  id: string;
  platform: 'tiktok' | 'instagram' | 'facebook' | 'x' | 'email';
  caption: string;
  hashtags: string | null;
  visual_description: string | null;
  needs_asset: boolean;
  status: 'queued' | 'posted' | 'skipped';
  created_at: string;
}

const FILTERS = ['queued', 'posted', 'skipped', 'all'] as const;
type Filter = (typeof FILTERS)[number];

function statusTone(status: ContentItem['status']) {
  if (status === 'posted') return 'good' as const;
  if (status === 'skipped') return 'warn' as const;
  return 'muted' as const;
}

function CopyButton({ text, label }: { text: string; label: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      onClick={async () => {
        await navigator.clipboard.writeText(text);
        setCopied(true);
        setTimeout(() => setCopied(false), 1500);
      }}
      className="rounded-md border border-[var(--border)] px-2 py-1 text-xs hover:border-[var(--accent)]"
    >
      {copied ? 'Copied' : label}
    </button>
  );
}

export function ContentSection() {
  const [items, setItems] = useState<ContentItem[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<Filter>('queued');
  const [updating, setUpdating] = useState<string | null>(null);

  async function load() {
    const { data, error } = await supabase
      .from('content_queue')
      .select('id, platform, caption, hashtags, visual_description, needs_asset, status, created_at')
      .order('created_at', { ascending: false });
    if (error) setError(error.message);
    else setItems(data as ContentItem[]);
  }

  useEffect(() => {
    load();
  }, []);

  async function setStatus(id: string, status: 'posted' | 'skipped') {
    setUpdating(id);
    const { error } = await supabase
      .from('content_queue')
      .update({ status, ...(status === 'posted' ? { posted_at: new Date().toISOString() } : {}) })
      .eq('id', id);
    setUpdating(null);
    if (error) {
      setError(error.message);
      return;
    }
    load();
  }

  if (error) return <Card title="Content"><ErrorNote message={error} /></Card>;
  if (!items) return <Card title="Content"><Loading /></Card>;

  const visible = filter === 'all' ? items : items.filter((i) => i.status === filter);

  return (
    <Card
      title="Content queue"
      action={
        <div className="flex gap-1">
          {FILTERS.map((f) => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`rounded-full px-3 py-1 text-xs font-medium ${
                filter === f
                  ? 'bg-[var(--accent)] text-[#04121f]'
                  : 'border border-[var(--border)] text-[var(--muted)]'
              }`}
            >
              {f}
            </button>
          ))}
        </div>
      }
    >
      {visible.length === 0 ? (
        <p className="text-sm text-[var(--muted)]">Nothing here.</p>
      ) : (
        <div className="flex flex-col gap-3">
          {visible.map((item) => (
            <div key={item.id} className="rounded-lg border border-[var(--border)] p-3">
              <div className="mb-2 flex items-center justify-between gap-2">
                <div className="flex items-center gap-2">
                  <Pill tone="muted">{item.platform}</Pill>
                  <Pill tone={statusTone(item.status)}>{item.status}</Pill>
                  {item.needs_asset && <Pill tone="warn">needs visual</Pill>}
                </div>
                <span className="text-xs text-[var(--muted)]">
                  {new Date(item.created_at).toLocaleDateString()}
                </span>
              </div>

              <p className="whitespace-pre-wrap text-sm">{item.caption}</p>

              {item.hashtags && (
                <p className="mt-2 text-sm text-[var(--accent)]">{item.hashtags}</p>
              )}

              {item.needs_asset && item.visual_description && (
                <div className="mt-2 rounded bg-black/20 p-2">
                  <p className="text-xs uppercase tracking-wide text-[var(--muted)]">
                    Visual needed — not generated yet
                  </p>
                  <p className="mt-1 text-sm text-[var(--muted)]">{item.visual_description}</p>
                </div>
              )}

              <div className="mt-3 flex flex-wrap gap-2">
                <CopyButton text={item.caption} label="Copy caption" />
                {item.hashtags && <CopyButton text={item.hashtags} label="Copy hashtags" />}
                {item.status === 'queued' && (
                  <>
                    <button
                      onClick={() => setStatus(item.id, 'posted')}
                      disabled={updating === item.id}
                      className="rounded-md bg-[var(--good)] px-2 py-1 text-xs font-medium text-[#04121f] disabled:opacity-50"
                    >
                      Mark posted
                    </button>
                    <button
                      onClick={() => setStatus(item.id, 'skipped')}
                      disabled={updating === item.id}
                      className="rounded-md border border-[var(--border)] px-2 py-1 text-xs disabled:opacity-50"
                    >
                      Skip
                    </button>
                  </>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}
