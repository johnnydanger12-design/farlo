create or replace function public.get_active_cron_job_names()
returns setof text
language sql
security definer
set search_path to 'public'
as $function$
  select jobname from cron.job where active = true;
$function$;

revoke all on function public.get_active_cron_job_names() from public, anon, authenticated;
grant execute on function public.get_active_cron_job_names() to service_role;
