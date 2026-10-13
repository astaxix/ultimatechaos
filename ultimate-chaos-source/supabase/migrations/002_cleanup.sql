-- Run after 001. Enable pg_cron in Supabase Database > Extensions first.
create extension if not exists pg_cron;
create function chaos_private.cleanup() returns void
language sql security definer set search_path='' as $$
 delete from public.chaos_rooms where updated_at<now()-interval '24 hours';
 delete from chaos_private.limits where coalesce(created,joined,'epoch'::timestamptz)<now()-interval '7 days';
$$;
revoke all on function chaos_private.cleanup() from public,anon,authenticated;
select cron.schedule('chaos-cleanup','*/15 * * * *','select chaos_private.cleanup()');
