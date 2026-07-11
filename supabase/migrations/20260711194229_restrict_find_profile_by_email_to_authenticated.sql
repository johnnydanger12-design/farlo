-- find_profile_by_email(p_email) had no authorization check at all and was
-- executable by anon -- a live email-enumeration oracle (any unauthenticated
-- caller could POST an email and learn whether it's registered plus the
-- account's display name). Legitimate use is the truck-transfer recipient
-- lookup (transfer_truck_sheet.dart), which only ever runs from an
-- already-authenticated screen -- there is no real anon use case.
--
-- NOTE, corrected after verifying rather than assuming: the other 3 narrow
-- profile-lookup RPCs added in the same original pass (invite_employee_by_email,
-- profile_display_name, profile_stripe_connected) are NOT already restricted
-- the same way -- checked has_function_privilege('anon', ...) directly and
-- all three are still anon-executable. invite_employee_by_email is safe
-- anyway (its own internal auth_user_owns_truck() check fails closed for
-- anon, since auth.uid() is null there). profile_display_name and
-- profile_stripe_connected are NOT similarly protected -- same class of
-- finding as this one, genuinely still open, deliberately not fixed in this
-- migration (out of the scope confirmed for this pass) -- see the release
-- report's Open Decisions section.
--
-- A bare REVOKE ... FROM anon, authenticated is not sufficient by itself --
-- Postgres also grants EXECUTE to PUBLIC by default on every function at
-- creation, and that grant survives a per-role revoke untouched (this
-- exact lesson already cost a real incident this project: agent_cron_call
-- stayed exploitable after a first "fix" that only revoked from named
-- roles). Explicitly revoke from PUBLIC too, then re-grant only to
-- authenticated.

REVOKE EXECUTE ON FUNCTION public.find_profile_by_email(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.find_profile_by_email(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.find_profile_by_email(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.find_profile_by_email(text) TO authenticated;
