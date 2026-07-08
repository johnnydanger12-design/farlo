import { useEffect, useRef, useState } from 'react';
import { supabase } from '../lib/supabase';
import { ErrorNote, Loading, Modal } from './ui';
import { CHAT_MODELS, DEFAULT_MODEL_ID, modelLabel } from '../lib/models';

interface ChatMessage {
  id: string;
  role: 'founder' | 'aiden' | 'system';
  content: string;
  image_paths?: string[];
  created_at: string;
}

interface ConversationSummary {
  id: string;
  title: string | null;
  last_message_at: string;
}

interface PendingImage {
  path: string;
  previewUrl: string;
  uploading: boolean;
}

const RECENTS_PAGE_SIZE = 20;

function ListIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
      <path d="M4 6h12M4 10h12M4 14h8" />
    </svg>
  );
}

function formatRelative(iso: string): string {
  return new Date(iso).toLocaleString([], { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
}

export function ChatSection() {
  const [founderId, setFounderId] = useState<string | null>(null);
  const [conversationId, setConversationId] = useState<string | null>(null);
  const [conversationTitle, setConversationTitle] = useState<string | null>(null);
  const [messages, setMessages] = useState<ChatMessage[] | null>(null);
  const [model, setModel] = useState(DEFAULT_MODEL_ID);
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pendingImage, setPendingImage] = useState<PendingImage | null>(null);
  const [recentsOpen, setRecentsOpen] = useState(false);
  const [conversations, setConversations] = useState<ConversationSummary[] | null>(null);
  const [recentsHasMore, setRecentsHasMore] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      const uid = data.user?.id;
      if (!uid) return;
      setFounderId(uid);
      supabase
        .from('profiles')
        .select('last_chat_model')
        .eq('id', uid)
        .single()
        .then(({ data: profile }) => {
          if (profile?.last_chat_model) setModel(profile.last_chat_model);
        });
    });

    supabase
      .from('aiden_conversations')
      .select('id, title')
      .order('last_message_at', { ascending: false })
      .limit(1)
      .then(({ data }) => {
        if (data && data.length > 0) {
          openConversation(data[0].id, data[0].title);
        } else {
          setMessages([]);
        }
      });
  }, []);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, sending]);

  async function openConversation(id: string, title: string | null) {
    setConversationId(id);
    setConversationTitle(title);
    setMessages(null);
    setError(null);
    const { data, error } = await supabase
      .from('aiden_chat_messages')
      .select('id, role, content, image_paths, created_at')
      .eq('conversation_id', id)
      .order('created_at', { ascending: true })
      .limit(100);
    if (error) setError(error.message);
    else setMessages(data as ChatMessage[]);
  }

  function newChat() {
    setConversationId(null);
    setConversationTitle(null);
    setMessages([]);
    setDraft('');
    removePendingImage();
    setError(null);
    setRecentsOpen(false);
  }

  async function openRecents() {
    setRecentsOpen(true);
    setConversations(null);
    const { data } = await supabase
      .from('aiden_conversations')
      .select('id, title, last_message_at')
      .order('last_message_at', { ascending: false })
      .range(0, RECENTS_PAGE_SIZE - 1);
    setConversations(data ?? []);
    setRecentsHasMore((data?.length ?? 0) === RECENTS_PAGE_SIZE);
  }

  async function loadMoreRecents() {
    const offset = conversations?.length ?? 0;
    const { data } = await supabase
      .from('aiden_conversations')
      .select('id, title, last_message_at')
      .order('last_message_at', { ascending: false })
      .range(offset, offset + RECENTS_PAGE_SIZE - 1);
    setConversations((prev) => [...(prev ?? []), ...(data ?? [])]);
    setRecentsHasMore((data?.length ?? 0) === RECENTS_PAGE_SIZE);
  }

  function selectConversation(c: ConversationSummary) {
    openConversation(c.id, c.title);
    setRecentsOpen(false);
  }

  function changeModel(newModelId: string) {
    if (newModelId === model) return;
    setModel(newModelId);
    // Client-side only note — not persisted, just makes a mid-conversation switch
    // visually clear rather than silent.
    setMessages((prev) => [
      ...(prev ?? []),
      { id: `switch-${Date.now()}`, role: 'system', content: `Switched to ${modelLabel(newModelId)}`, created_at: new Date().toISOString() },
    ]);
    if (founderId) {
      supabase.from('profiles').update({ last_chat_model: newModelId }).eq('id', founderId).then();
    }
  }

  async function handleFileSelect(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setError(null);
    const previewUrl = URL.createObjectURL(file);
    setPendingImage({ path: '', previewUrl, uploading: true });
    const ext = file.name.split('.').pop() || 'jpg';
    const path = `chat/${crypto.randomUUID()}.${ext}`;
    const { error } = await supabase.storage.from('aiden-chat-photos').upload(path, file, { contentType: file.type });
    if (error) {
      setError(`Photo upload failed: ${error.message}`);
      URL.revokeObjectURL(previewUrl);
      setPendingImage(null);
      return;
    }
    setPendingImage({ path, previewUrl, uploading: false });
  }

  function removePendingImage() {
    setPendingImage((prev) => {
      if (prev) URL.revokeObjectURL(prev.previewUrl);
      return null;
    });
  }

  async function send(e: React.FormEvent) {
    e.preventDefault();
    if (sending || pendingImage?.uploading) return;
    const text = draft.trim() || (pendingImage ? '📷' : '');
    if (!text) return;

    setError(null);
    setSending(true);
    setDraft('');
    const imagePaths = pendingImage ? [pendingImage.path] : [];
    const previewUrlToRevoke = pendingImage?.previewUrl;
    setPendingImage(null);

    const optimistic: ChatMessage = {
      id: `pending-${Date.now()}`,
      role: 'founder',
      content: text,
      image_paths: imagePaths,
      created_at: new Date().toISOString(),
    };
    setMessages((prev) => [...(prev ?? []), optimistic]);

    const { data, error } = await supabase.functions.invoke<{
      reply?: string;
      conversation_id?: string;
      error?: string;
    }>('aiden-chat', {
      body: { message: text, conversation_id: conversationId ?? undefined, model, image_paths: imagePaths },
    });

    setSending(false);
    if (previewUrlToRevoke) URL.revokeObjectURL(previewUrlToRevoke);

    if (error || !data?.reply) {
      setError(error?.message ?? data?.error ?? 'Aiden did not reply — try again.');
      return;
    }

    if (!conversationId && data.conversation_id) {
      setConversationId(data.conversation_id);
      setConversationTitle(text.length > 40 ? `${text.slice(0, 40)}…` : text);
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
    // h-full, not a bounded Card: this fills exactly the space its flex-1 parent in
    // App.tsx gives it (the full screen below the header, no page-level scroll), so
    // the input below is the last item in an exactly-sized column — it sits at the
    // true bottom of the screen with no sticky/fixed positioning trick required.
    <section className="flex min-h-0 min-w-0 flex-1 flex-col rounded-xl border border-[var(--border)] bg-[var(--panel)]">
      <div className="flex shrink-0 items-center justify-between gap-2 border-b border-[var(--border)] px-3 py-3">
        <div className="flex min-w-0 items-center gap-1.5">
          <button
            onClick={openRecents}
            aria-label="Conversations"
            className="shrink-0 rounded-md p-1.5 text-[var(--muted)] hover:text-[var(--text)]"
          >
            <ListIcon />
          </button>
          <h2 className="min-w-0 truncate text-sm font-semibold uppercase tracking-wide text-[var(--muted)]">
            {conversationTitle ?? 'New chat with Aiden'}
          </h2>
        </div>
        <select
          value={model}
          onChange={(e) => changeModel(e.target.value)}
          aria-label="Model"
          className="shrink-0 rounded-md border border-[var(--border)] bg-transparent px-2 py-1 text-xs outline-none focus:border-[var(--accent)]"
        >
          {CHAT_MODELS.map((m) => (
            <option key={m.id} value={m.id}>
              {m.label}
            </option>
          ))}
        </select>
      </div>

      <div className="flex min-h-0 min-w-0 flex-1 flex-col gap-3 overflow-y-auto p-4">
        {messages === null ? (
          <Loading />
        ) : messages.length === 0 ? (
          <p className="text-sm text-[var(--muted)]">
            No messages yet — say hi to Aiden below.
          </p>
        ) : (
          messages.map((m) =>
            m.role === 'system' ? (
              <p key={m.id} className="text-center text-xs text-[var(--muted)]">
                {m.content}
              </p>
            ) : (
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
            ),
          )
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

      {pendingImage && (
        <div className="flex shrink-0 items-center gap-2 border-t border-[var(--border)] px-3 pt-3">
          <div className="relative">
            <img src={pendingImage.previewUrl} alt="Attached" className="h-14 w-14 rounded-md object-cover" />
            {pendingImage.uploading && (
              <div className="absolute inset-0 flex items-center justify-center rounded-md bg-black/50 text-[10px] text-white">
                Uploading…
              </div>
            )}
          </div>
          <button
            type="button"
            onClick={removePendingImage}
            className="text-xs text-[var(--muted)] hover:text-[var(--text)]"
          >
            Remove
          </button>
        </div>
      )}

      <form
        onSubmit={send}
        className={`flex shrink-0 min-w-0 gap-2 px-3 py-3 ${pendingImage ? '' : 'border-t border-[var(--border)]'}`}
        style={{ paddingBottom: 'max(0.75rem, env(safe-area-inset-bottom))' }}
      >
        <input ref={fileInputRef} type="file" accept="image/*" onChange={handleFileSelect} className="hidden" />
        <button
          type="button"
          onClick={() => fileInputRef.current?.click()}
          disabled={sending}
          aria-label="Attach photo"
          className="shrink-0 rounded-md border border-[var(--border)] px-3 py-2 text-sm text-[var(--muted)] hover:border-[var(--accent)] hover:text-[var(--text)] disabled:opacity-50"
        >
          +
        </button>
        <input
          type="text"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="Message Aiden…"
          disabled={sending}
          autoFocus
          // text-base (16px), not text-sm (14px) — anything smaller triggers iOS
          // Safari's auto-zoom-on-focus, which visibly breaks this layout.
          className="min-w-0 flex-1 rounded-md border border-[var(--border)] bg-transparent px-3 py-2 text-base outline-none focus:border-[var(--accent)] disabled:opacity-50"
        />
        <button
          type="submit"
          disabled={sending || pendingImage?.uploading || (!draft.trim() && !pendingImage)}
          className="shrink-0 rounded-md bg-[var(--accent)] px-4 py-2 text-sm font-medium text-[#04121f] disabled:opacity-50"
        >
          Send
        </button>
      </form>

      <Modal open={recentsOpen} onClose={() => setRecentsOpen(false)} title="Conversations">
        <div className="flex flex-col gap-2">
          <button
            onClick={newChat}
            className="rounded-md border border-[var(--accent)] px-3 py-2 text-left text-sm font-medium text-[var(--accent)]"
          >
            + New chat
          </button>
          {conversations === null ? (
            <Loading />
          ) : conversations.length === 0 ? (
            <p className="text-sm text-[var(--muted)]">No conversations yet.</p>
          ) : (
            conversations.map((c) => (
              <button
                key={c.id}
                onClick={() => selectConversation(c)}
                className={`min-w-0 rounded-md px-3 py-2 text-left text-sm ${
                  c.id === conversationId ? 'bg-[var(--accent)] text-[#04121f]' : 'hover:bg-black/20'
                }`}
              >
                <div className="truncate font-medium">{c.title || 'Untitled conversation'}</div>
                <div className={`text-xs ${c.id === conversationId ? 'text-[#04121f]/70' : 'text-[var(--muted)]'}`}>
                  {formatRelative(c.last_message_at)}
                </div>
              </button>
            ))
          )}
          {recentsHasMore && (
            <button onClick={loadMoreRecents} className="py-1 text-xs text-[var(--muted)] hover:text-[var(--text)]">
              Load more
            </button>
          )}
        </div>
      </Modal>
    </section>
  );
}
