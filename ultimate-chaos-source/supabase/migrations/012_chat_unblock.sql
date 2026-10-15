begin;
-- A user may undo their own block even after the friendship was removed.
create or replace function public.chaos_chat(action text,target uuid default null,message text default null,request_id uuid default null,message_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();existing public.chaos_messages;cutoff timestamptz;d jsonb;
begin
 if action='report' then
  select * into existing from public.chaos_messages where id=message_id and receiver=u;
  if existing.id is null or message not in('spam','abuse','inappropriate') then raise exception 'Ungültige Meldung';end if;
  insert into chaos_private.message_reports values(u,existing.id,message,clock_timestamp()) on conflict do nothing;
  return jsonb_build_object('reported',true);
 elsif action in('block','unblock') then
  if target is null or target=u or (not exists(select 1 from public.chaos_friends where (requester=u and receiver=target)or(requester=target and receiver=u)) and not (action='unblock' and exists(select 1 from chaos_private.blocks where blocker=u and blocked=target))) then raise exception 'Spieler nicht verfügbar';end if;
  if action='block' then
   insert into chaos_private.blocks(blocker,blocked) values(u,target) on conflict do nothing;
   update public.chaos_challenges set status='declined' where status='pending' and ((sender=u and receiver=target)or(sender=target and receiver=u));
  else delete from chaos_private.blocks where blocker=u and blocked=target;end if;
  return jsonb_build_object('blocked',action='block');
 elsif action not in('state','send','older') then raise exception 'Ungültige Chataktion';end if;
 if not chaos_private.friends_allowed(u,target) then raise exception 'Chat ist nur zwischen bestätigten, nicht blockierten Freunden möglich';end if;
 if action='send' then
  if request_id is null or message is null or length(trim(message)) not between 1 and 500 then raise exception 'Nachricht muss 1 bis 500 Zeichen lang sein';end if;
  perform pg_advisory_xact_lock(hashtextextended(u::text,6014011));
  select * into existing from public.chaos_messages where sender=u and nonce=request_id;
  if existing.id is not null then
   if existing.receiver<>target or existing.body<>trim(message) then raise exception 'Diese Sende-ID wurde bereits verwendet';end if;
  else
   if exists(select 1 from public.chaos_messages where sender=u and created_at>clock_timestamp()-interval '750 milliseconds') or (select count(*) from public.chaos_messages where sender=u and created_at>clock_timestamp()-interval '1 minute')>=20 then raise exception 'Bitte kurz warten. Maximal 20 Nachrichten pro Minute.';end if;
   insert into public.chaos_messages(sender,receiver,body,nonce) values(u,target,trim(message),request_id);
  end if;
 end if;
 if action='older' then select created_at into cutoff from public.chaos_messages where id=message_id and ((sender=u and receiver=target)or(sender=target and receiver=u));if cutoff is null then raise exception 'Ungültige Verlaufsseite';end if;end if;
 update public.chaos_messages set read_at=clock_timestamp() where receiver=u and sender=target and read_at is null;
 select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at,t.id),'[]'::jsonb) into d from(select id,sender,receiver,body,created_at,read_at from public.chaos_messages where ((sender=u and receiver=target)or(sender=target and receiver=u)) and (cutoff is null or (created_at,id)<(cutoff,message_id)) order by created_at desc,id desc limit 50)t;
 return jsonb_build_object('messages',d,'has_more',jsonb_array_length(d)=50);
end;$$;
revoke all on function public.chaos_chat(text,uuid,text,uuid,uuid) from public,anon;
grant execute on function public.chaos_chat(text,uuid,text,uuid,uuid) to authenticated;
commit;
