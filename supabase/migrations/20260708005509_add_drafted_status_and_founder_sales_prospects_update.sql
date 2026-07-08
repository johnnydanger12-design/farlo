-- Fixes a real gap found while discussing outreach with the founder: Miles marks a
-- prospect 'contacted' the instant he creates a Gmail draft, before the founder has
-- actually reviewed/sent it. Since his fetch only queries status='uncontacted', that
-- prospect silently drops out of his queue forever regardless of whether the draft is
-- ever actually sent — there's no way today to distinguish "drafted, sitting in Gmail"
-- from "actually sent". Adding a distinct 'drafted' status so Miles can mark that
-- state without prematurely claiming contact was made, plus a founder UPDATE policy so
-- the dashboard can flip it to 'contacted' (with the real send date) once the founder
-- actually sends it.
ALTER TABLE public.sales_prospects DROP CONSTRAINT sales_prospects_status_check;
ALTER TABLE public.sales_prospects ADD CONSTRAINT sales_prospects_status_check
  CHECK (status = ANY (ARRAY['uncontacted'::text, 'drafted'::text, 'contacted'::text, 'responded'::text, 'converted'::text, 'not_interested'::text, 'bounced'::text]));

CREATE POLICY "founder can update" ON public.sales_prospects
  FOR UPDATE USING (is_founder()) WITH CHECK (is_founder());
