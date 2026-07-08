-- Builds the follow-up automation the sales_targets directive describes ("initial -> +3
-- days -> +10 days -> stop") but that never actually existed in code — previously,
-- 'contacted' prospects just silently dropped out of Miles's queue forever with no
-- re-surfacing logic at all.
--
-- first_contacted_at anchors both follow-up thresholds (day 3, day 10 from the *initial*
-- send, not sequential gaps) and is set once, the same moment status flips to 'contacted'.
-- follow_up_count (0/1/2) gates eligibility and stops after the second follow-up.
--
-- pending_followup_subject/body mirrors the same 'drafted vs confirmed sent' distinction
-- already built for initial outreach: a follow-up Miles drafts does NOT advance
-- follow_up_count or last_contacted_at until the founder confirms it was actually sent
-- (via the dashboard) — otherwise we'd reintroduce the exact bug that was just fixed,
-- just one level deeper.
--
-- last_email_subject/body holds the most recently *confirmed-sent* email's content, so
-- Miles has real context to write a natural follow-up referencing what was already said.
ALTER TABLE public.sales_prospects
  ADD COLUMN first_contacted_at timestamptz,
  ADD COLUMN follow_up_count integer NOT NULL DEFAULT 0,
  ADD COLUMN last_email_subject text,
  ADD COLUMN last_email_body text,
  ADD COLUMN pending_followup_subject text,
  ADD COLUMN pending_followup_body text;
