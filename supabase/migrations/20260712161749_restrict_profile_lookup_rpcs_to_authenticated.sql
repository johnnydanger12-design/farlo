-- profile_display_name(uuid) and profile_stripe_connected(uuid) had no
-- authorization check and were executable by anon -- same class of finding
-- as find_profile_by_email (previous migration), found while fixing that
-- one. profile_stripe_connected is the more real exposure of the two,
-- since food_trucks.owner_id is a plain, publicly-fetched column (both
-- in-app and on visit.farlo.app), so any truck's owner UUID is trivially
-- discoverable -- someone could look up any business and learn whether
-- that owner has completed Stripe onboarding. profile_display_name is
-- lower severity (UUIDs aren't guessable by brute force, and the one known
-- public leak path -- reviews.user_id -- already shows the display name
-- in the review itself).
--
-- Both must stay callable by ordinary authenticated users, not just the
-- owner/founder -- that residual (any authenticated user can look up
-- another user via these narrow RPCs) was already accepted project-wide
-- when this batch of lookup RPCs was built; only the anon-level exposure
-- is the regression being closed here.

REVOKE EXECUTE ON FUNCTION public.profile_display_name(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.profile_display_name(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.profile_display_name(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.profile_display_name(uuid) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.profile_stripe_connected(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.profile_stripe_connected(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.profile_stripe_connected(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.profile_stripe_connected(uuid) TO authenticated;
