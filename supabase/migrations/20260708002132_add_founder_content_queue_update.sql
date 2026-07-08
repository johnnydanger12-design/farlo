-- Founder needs to mark content_queue items posted/skipped from the dashboard's new
-- Content tab — this is already the documented intended workflow ("Piper writes content
-- here; Johnny sets status='posted'/'skipped'", per HANDOFF.md) but no RLS policy existed
-- to let the founder actually do that outside of a service-role SQL query.
CREATE POLICY "founder can update" ON public.content_queue
  FOR UPDATE USING (is_founder()) WITH CHECK (is_founder());
