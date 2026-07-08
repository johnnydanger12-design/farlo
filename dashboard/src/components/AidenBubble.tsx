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

  // Below sm (640px) the panel is positioned via JS against window.visualViewport
  // instead of plain CSS — iOS Safari doesn't shrink position:fixed's containing
  // block when the on-screen keyboard opens (only the *visual* viewport shrinks),
  // so a CSS-only bottom-anchored panel ends up partly hidden under the keyboard.
  // Desktop/tablet has no on-screen keyboard to worry about, so it stays plain
  // Tailwind (sm: classes below).
  const [mobileLayout, setMobileLayout] = useState(
    () => window.matchMedia('(max-width: 639px)').matches,
  );
  const [viewport, setViewport] = useState<{ height: number; offsetTop: number } | null>(
    () => (window.visualViewport
      ? { height: window.visualViewport.height, offsetTop: window.visualViewport.offsetTop }
      : null),
  );

  useEffect(() => {
    const mq = window.matchMedia('(max-width: 639px)');
    const onChange = () => setMobileLayout(mq.matches);
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);

  useEffect(() => {
    if (!open) return;
    function update() {
      if (window.visualViewport) {
        setViewport({ height: window.visualViewport.height, offsetTop: window.visualViewport.offsetTop });
      }
    }
    update();
    window.visualViewport?.addEventListener('resize', update);
    window.visualViewport?.addEventListener('scroll', update);
    return () => {
      window.visualViewport?.removeEventListener('resize', update);
      window.visualViewport?.removeEventListener('scroll', update);
    };
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

  return (
    <>
      {open && (
        <div
          className="fixed inset-0 z-40 sm:hidden bg-black/50"
          onClick={() => setOpen(false)}
        />
      )}

      {open && (
        <div
          className={`fixed z-50 flex min-w-0 flex-col overflow-hidden rounded-2xl border border-[var(--border)] bg-[var(--panel)] shadow-2xl
                     sm:inset-x-auto sm:top-auto sm:bottom-24 sm:right-6 sm:h-[32rem] sm:w-96
                     ${mobileLayout ? '' : 'inset-x-3 bottom-3 top-16'}`}
          style={
            mobileLayout && viewport
              ? { top: viewport.offsetTop + 12, left: '0.75rem', right: '0.75rem', height: viewport.height - 24 }
              : mobileLayout
                ? { top: 'calc(env(safe-area-inset-top) + 1rem)', bottom: '0.75rem', left: '0.75rem', right: '0.75rem' }
                : undefined
          }
        >
          <div className="flex shrink-0 items-center justify-between border-b border-[var(--border)] px-4 py-3">
            <span className="text-sm font-semibold">Aiden</span>
            <button
              onClick={() => setOpen(false)}
              aria-label="Close chat"
              className="rounded-md p-1 text-[var(--muted)] hover:text-[var(--text)]"
            >
              ✕
            </button>
          </div>

          <div className="flex min-h-0 flex-1 min-w-0 flex-col gap-3 overflow-y-auto p-3">
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
            <div className="shrink-0 px-3">
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
              autoFocus
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
      )}

      <button
        onClick={() => setOpen((v) => !v)}
        aria-label={open ? 'Close chat with Aiden' : 'Open chat with Aiden'}
        style={{ bottom: 'calc(env(safe-area-inset-bottom) + 1.5rem)' }}
        className="fixed right-6 z-50 flex h-14 w-14 items-center justify-center rounded-full bg-[var(--accent)] text-[#04121f] shadow-lg transition-transform hover:scale-105 active:scale-95"
      >
        {open ? <span className="text-xl">✕</span> : <ChatIcon />}
      </button>
    </>
  );
}
