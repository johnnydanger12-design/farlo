-- aiden_chat_messages was one flat, unbounded conversation. The founder wants real
-- threads (Recents list + New Chat), so messages now belong to a conversation row.
-- Same write pattern as aiden_chat_messages itself: service role only, founder reads —
-- all writes happen server-side through the aiden-chat Edge Function, never a direct
-- client insert.
CREATE TABLE public.aiden_conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text,
  model text NOT NULL DEFAULT 'claude-sonnet-5',
  created_at timestamptz NOT NULL DEFAULT now(),
  last_message_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.aiden_conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service role only" ON public.aiden_conversations FOR ALL USING (false);
CREATE POLICY "founder can read" ON public.aiden_conversations FOR SELECT USING (is_founder());

ALTER TABLE public.aiden_chat_messages ADD COLUMN conversation_id uuid;
ALTER TABLE public.aiden_chat_messages ADD COLUMN image_paths text[] NOT NULL DEFAULT '{}';

-- Backfill: every existing message becomes one legacy conversation so nothing is lost.
DO $$
DECLARE
  legacy_id uuid;
  latest timestamptz;
BEGIN
  IF EXISTS (SELECT 1 FROM public.aiden_chat_messages) THEN
    SELECT max(created_at) INTO latest FROM public.aiden_chat_messages;
    INSERT INTO public.aiden_conversations (title, last_message_at)
    VALUES ('Earlier conversation', latest)
    RETURNING id INTO legacy_id;

    UPDATE public.aiden_chat_messages SET conversation_id = legacy_id;
  END IF;
END $$;

ALTER TABLE public.aiden_chat_messages ALTER COLUMN conversation_id SET NOT NULL;
ALTER TABLE public.aiden_chat_messages
  ADD CONSTRAINT aiden_chat_messages_conversation_id_fkey
  FOREIGN KEY (conversation_id) REFERENCES public.aiden_conversations(id);
