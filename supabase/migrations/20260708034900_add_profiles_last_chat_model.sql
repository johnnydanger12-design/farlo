-- Persists the founder's last-selected Aiden chat model so it follows them across
-- devices/sessions. Covered by the existing "profiles: owner can update" policy
-- (auth.uid() = id, no column restriction) — no new RLS needed.
ALTER TABLE public.profiles ADD COLUMN last_chat_model text NOT NULL DEFAULT 'claude-sonnet-5';
