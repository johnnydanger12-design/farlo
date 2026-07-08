-- Founder wants a live chat conversation with Aiden in the dashboard, not just the
-- twice-daily email inbox check. Stores conversation history so context carries across
-- messages; writes only ever happen server-side via the new aiden-chat Edge Function
-- (using the service role key), matching the pattern used everywhere else in this
-- project — the founder gets read access, not a client-forgeable insert.
CREATE TABLE public.aiden_chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  role text NOT NULL CHECK (role IN ('founder', 'aiden')),
  content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.aiden_chat_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service role only" ON public.aiden_chat_messages FOR ALL USING (false);
CREATE POLICY "founder can read" ON public.aiden_chat_messages FOR SELECT USING (is_founder());
