import { useEffect, useRef, useState } from 'react';
import { supabase } from '../lib/supabase';
import { ErrorNote, Loading } from './ui';

interface ChatMessage {
  id: string;
  role: 'founder' | 'aiden';
  content: string;
  created_at: string;
}

function ChatIcon() {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z" />
    </svg>
  );
}

export function AidenBubble() {
  const [open, setOpen] = useState(false);
  const [messages, setMessages] = useState<ChatMessage[] | null>(null);
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);
  const loadedRef = useRef(false);
  const containerRef = useRef<HTMLDivElement>(null);
  const headerRef = useRef<HTMLDivElement>(null);
  const [debugInfo, setDebugInfo] = useState('');

  useEffect(() => {
    if (!open) return;
    const t = setTimeout(() => {
      const c = containerRef.current?.getBoundingClientRect();
      const h = headerRef.current?.getBoundingClientRect();
      const hStyle = headerRef.current ? getComputedStyle(headerRef.current) : null;
      setDebugInfo(
        `container: w=${c?.width.toFixed(0)} l=${c?.left.toFixed(0)} r=${c?.right.toFixed(0)} | ` +
        `header: w=${h?.width.toFixed(0)} top=${h?.top.toFixed(0)} pt=${hStyle?.paddingTop} | ` +
        `docEl.clientWidth=${document.documentElement.clientWidth} innerWidth=${window.innerWidth} dpr=${window.devicePixelRatio}`,
      );
    }, 300);
    return () => clearTimeout(t);
  }, [open]);

  useEffect(() => {
    if (!open || loadedRef.current) return;
    loadedRef.current = true;
    supabase
      .from('aiden_chat_messages')
      .select('id, role, content, created_at')
      .order('created_at', { ascending: true })
      .limit(100)
      .then(({ data, error }) => {
        if (error) setError(error.message);
        else setMessages(data as ChatMessage[]);
      });
  }, [open]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, sending, open]);

  async function send(e: React.FormEvent) {
    e.preventDefault();
    const text = draft.trim();
    if (!text || sending) return;

    setError(null);
    setSending(true);
    setDraft('');

    const optimistic: ChatMessage = {
      id: `pending-${Date.now()}`,
      role: 'founder',
      content: text,
      created_at: new Date().toISOString(),
    };
    setMessages((prev) => [...(prev ?? []), optimistic]);

    const { data, error } = await supabase.functions.invoke<{ reply?: string; error?: string }>('aiden-chat', {
      body: { message: text },
    });

    setSending(false);

    if (error || !data?.reply) {
      setError(error?.message ?? data?.error ?? 'Aiden did not reply — try again.');
      return;
    }

    setMessages((prev) => [
      ...(prev ?? []),
      {
        id: `reply-${Date.now()}`,
        role: 'aiden',
        content: data.reply!,
        created_at: new Date().toISOString(),
      },
    ]);
  }

  if (!open) {
    return (
      <button
        onClick={() => setOpen(true)}
        aria-label="Open chat with Aiden"
        style={{ bottom: 'calc(env(safe-area-inset-bottom) + 1.5rem)' }}
        className="fixed right-6 z-50 flex h-14 w-14 items-center justify-center rounded-full bg-[var(--accent)] text-[#04121f] shadow-lg transition-transform hover:scale-105 active:scale-95"
      >
        <ChatIcon />
      </button>
    );
  }

  // Full-screen takeover rather than a corner-anchored floating panel — a plain
  // fixed inset-0 + flex column (header shrink-0, messages flex-1 scrollable, input
  // shrink-0 at the bottom) is the same well-tested pattern AuthGate's login screen
  // already uses successfully, including with the keyboard open. No custom
  // viewport/keyboard math needed at all, unlike the earlier corner-panel version.
  return (
    <div ref={containerRef} className="fixed inset-0 z-50 flex flex-col bg-[var(--bg)]">
      {debugInfo && (
        <div className="shrink-0 break-all bg-[var(--bad)]/20 p-2 text-[9px] text-[var(--bad)]">
          {debugInfo}
        </div>
      )}
      <div
        ref={headerRef}
        className="flex shrink-0 items-center justify-between border-b border-[var(--border)] px-4"
        style={{ paddingTop: 'calc(env(safe-area-inset-top) + 0.75rem)', paddingBottom: '0.75rem' }}
      >
        <span className="text-base font-semibold">Aiden</span>
        <button
          onClick={() => setOpen(false)}
          aria-label="Close chat"
          className="rounded-md p-1 text-[var(--muted)] hover:text-[var(--text)]"
        >
          ✕
        </button>
      </div>

      <div className="flex min-h-0 flex-1 min-w-0 flex-col gap-3 overflow-y-auto p-4">
        {messages === null ? (
          <Loading />
        ) : messages.length === 0 ? (
          <p className="text-sm text-[var(--muted)]">
            No messages yet — say hi to Aiden below.
          </p>
        ) : (
          messages.map((m) => (
            <div
              key={m.id}
              className={`flex min-w-0 ${m.role === 'founder' ? 'justify-end' : 'justify-start'}`}
            >
              <div
                className={`min-w-0 max-w-[85%] rounded-lg px-3 py-2 text-sm whitespace-pre-wrap break-words ${
                  m.role === 'founder'
                    ? 'bg-[var(--accent)] text-[#04121f]'
                    : 'border border-[var(--border)] bg-black/20 text-[var(--text)]'
                }`}
              >
                {m.content}
              </div>
            </div>
          ))
        )}
        {sending && (
          <div className="flex justify-start">
            <div className="rounded-lg border border-[var(--border)] bg-black/20 px-3 py-2 text-sm text-[var(--muted)]">
              Aiden is typing…
            </div>
          </div>
        )}
        <div ref={bottomRef} />
      </div>

      {error && (
        <div className="shrink-0 px-4">
          <ErrorNote message={error} />
        </div>
      )}

      <form
        onSubmit={send}
        className="flex min-w-0 shrink-0 gap-2 border-t border-[var(--border)] p-3"
        style={{ paddingBottom: 'max(0.75rem, env(safe-area-inset-bottom))' }}
      >
        <input
          type="text"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="Message Aiden…"
          disabled={sending}
          className="min-w-0 flex-1 rounded-md border border-[var(--border)] bg-transparent px-3 py-2 text-sm outline-none focus:border-[var(--accent)] disabled:opacity-50"
        />
        <button
          type="submit"
          disabled={sending || !draft.trim()}
          className="shrink-0 rounded-md bg-[var(--accent)] px-4 py-2 text-sm font-medium text-[#04121f] disabled:opacity-50"
        >
          Send
        </button>
      </form>
    </div>
  );
}
