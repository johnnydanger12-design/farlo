-- Founder is switching everything over to his business email. is_founder() is
-- checked live against auth.jwt() on every request (not cached), so this takes
-- effect immediately for every RLS policy and RPC gated by it — no data migration
-- needed, just re-pointing the one comparison.
CREATE OR REPLACE FUNCTION public.is_founder() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT auth.jwt() ->> 'email' = 'johnny@farlo.app';
$$;
