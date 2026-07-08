import { useEffect, useRef, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Card, ErrorNote, Loading } from './ui';

interface ChatMessage {
  id: string;
  role: 'founder' | 'aiden';
  content: string;
  created_at: string;
}

export function ChatSection() {
  const [messages, setMessages] = useState<ChatMessage[] | null>(null);
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    supabase
      .from('aiden_chat_messages')
      .select('id, role, content, created_at')
      .order('created_at', { ascending: true })
      .limit(100)
      .then(({ data, error }) => {
        if (error) setError(error.message);
        else setMessages(data as ChatMessage[]);
      });
  }, []);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, sending]);

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
    <Card title="Chat with Aiden">
      <div className="flex min-w-0 flex-col gap-3">
        <div className="flex max-h-[60vh] min-h-[300px] min-w-0 flex-col gap-3 overflow-y-auto rounded-lg border border-[var(--border)] bg-black/10 p-3">
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

        {error && <ErrorNote message={error} />}

        {/* sticky, not fixed — stays in normal document flow (so it naturally
            participates in the browser's own scroll-into-view-above-keyboard
            behavior) while still visually pinned to the bottom of the viewport
            as the page scrolls. position:fixed is what caused every earlier
            layout bug in this app on iOS — sticky doesn't share that failure mode. */}
        <form
          onSubmit={send}
          className="sticky bottom-0 flex min-w-0 gap-2 bg-[var(--panel)] py-2"
          style={{ paddingBottom: 'max(0.5rem, env(safe-area-inset-bottom))' }}
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
    </Card>
  );
}
