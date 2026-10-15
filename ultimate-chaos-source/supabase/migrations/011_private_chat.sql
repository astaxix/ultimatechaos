begin;
create table chaos_private.blocks(blocker uuid not null references public.chaos_profiles on delete cascade,blocked uuid not null references public.chaos_profiles on delete cascade,created_at timestamptz not null default clock_timestamp(),primary key(blocker,blocked),check(blocker<>blocked));
create table public.chaos_messages(id uuid primary key default gen_random_uuid(),sender uuid not null references public.chaos_profiles on delete cascade,receiver uuid not null references public.chaos_profiles on delete cascade,body text not null check(length(trim(body)) between 1 and 500),nonce uuid not null,created_at timestamptz not null default clock_timestamp(),read_at timestamptz,unique(sender,nonce),check(sender<>receiver));
create table chaos_private.message_reports(reporter uuid not null references public.chaos_profiles on delete cascade,message_id uuid not null references public.chaos_messages on delete cascade,reason text not null check(reason in('spam','abuse','inappropriate')),created_at timestamptz not null default clock_timestamp(),primary key(reporter,message_id));
alter table chaos_private.blocks enable row level security;
alter table chaos_private.message_reports enable row level security;
alter table public.chaos_messages enable row level security;
revoke all on chaos_private.blocks,chaos_private.message_reports,public.chaos_messages from public,anon,authenticated;
grant select on public.chaos_messages to authenticated;
create index messages_pair on public.chaos_messages(least(sender,receiver),greatest(sender,receiver),created_at desc);
create index messages_unread on public.chaos_messages(receiver,sender) where read_at is null;
create index messages_spam on public.chaos_messages(sender,created_at desc);
create function chaos_private.friends_allowed(a uuid,b uuid) returns boolean language sql stable security definer set search_path='' as $$
 select a<>b and exists(select 1 from public.chaos_friends where status='accepted' and ((requester=a and receiver=b)or(requester=b and receiver=a))) and not exists(select 1 from chaos_private.blocks where (blocker=a and blocked=b)or(blocker=b and blocked=a));
$$;
-- This narrow predicate is callable by RLS, never a source of profile or message data.
revoke all on function chaos_private.friends_allowed(uuid,uuid) from public,anon,authenticated;
create function public.chaos_chat_visible(a uuid,b uuid) returns boolean language sql stable security definer set search_path='' as $$select auth.uid() in(a,b) and chaos_private.friends_allowed(a,b);$$;
revoke all on function public.chaos_chat_visible(uuid,uuid) from public,anon;
grant execute on function public.chaos_chat_visible(uuid,uuid) to authenticated;
create policy message_members on public.chaos_messages for select to authenticated using(public.chaos_chat_visible(sender,receiver));
alter publication supabase_realtime add table public.chaos_messages;

create function public.chaos_chat(action text,target uuid default null,message text default null,request_id uuid default null,message_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();existing public.chaos_messages;cutoff timestamptz;d jsonb;
begin
 if action='report' then
  select * into existing from public.chaos_messages where id=message_id and receiver=u;
  if existing.id is null or message not in('spam','abuse','inappropriate') then raise exception 'Ungültige Meldung';end if;
  insert into chaos_private.message_reports values(u,existing.id,message,clock_timestamp()) on conflict do nothing;
  return jsonb_build_object('reported',true);
 elsif action in('block','unblock') then
  if target is null or target=u or not exists(select 1 from public.chaos_friends where (requester=u and receiver=target)or(requester=target and receiver=u)) then raise exception 'Spieler nicht verfügbar';end if;
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

create function public.chaos_community() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();
begin
 update public.chaos_profiles set last_seen=clock_timestamp() where id=u;
 return jsonb_build_object('friends',coalesce((select jsonb_agg(to_jsonb(t)) from(select f.id,f.status,f.receiver=u incoming,p.id player,p.name,p.avatar,p.appearance,p.frame,p.xp,p.rating,
 case when p.last_seen<clock_timestamp()-interval '60 seconds' then 'offline' when exists(select 1 from chaos_private.sessions s join public.chaos_rooms r on r.id=s.room_id where s.player=p.id and r.phase<>'finished') then 'battle' else 'online' end presence,
 (select count(*) from public.chaos_messages where sender=p.id and receiver=u and read_at is null) unread
 from public.chaos_friends f join public.chaos_profiles p on p.id=case when f.requester=u then f.receiver else f.requester end where u in(f.requester,f.receiver) and not exists(select 1 from chaos_private.blocks b where (b.blocker=u and b.blocked=p.id)or(b.blocker=p.id and b.blocked=u)))t),'[]'::jsonb),
 'blocked',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name)) from chaos_private.blocks b join public.chaos_profiles p on p.id=b.blocked where b.blocker=u),'[]'::jsonb),
 'challenges',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'incoming',c.receiver=u,'player',p.id,'name',p.name,'appearance',p.appearance,'frame',p.frame,'status',c.status,'expires_at',c.expires_at,'code',r.code,'phase',r.phase))
 from public.chaos_challenges c join public.chaos_profiles p on p.id=case when c.sender=u then c.receiver else c.sender end join public.chaos_rooms r on r.id=c.room_id
 where u in(c.sender,c.receiver) and c.expires_at>clock_timestamp() and chaos_private.friends_allowed(c.sender,c.receiver) and ((c.status='pending' and r.phase='lobby')or(c.status in('accepted','declined') and c.created_at>clock_timestamp()-interval '10 minutes'))),'[]'::jsonb));
end;$$;

alter function public.chaos_social(text,text,integer,text,uuid,text) rename to chaos_social_v7;
alter function public.chaos_social_v7(text,text,integer,text,uuid,text) set schema chaos_private;
create function public.chaos_social(action text,display_name text default null,avatar_id integer default null,friend_code text default null,target_id uuid default null,item_id text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();other uuid;d jsonb;r public.chaos_rooms;
begin
 if action='add_friend' then select id into other from public.chaos_profiles where public.chaos_profiles.friend_code=upper(trim(chaos_social.friend_code));
 elsif action='challenge' then other:=target_id;
 elsif action='accept_challenge' then select sender into other from public.chaos_challenges where id=target_id;end if;
 if other is not null and exists(select 1 from chaos_private.blocks where (blocker=u and blocked=other)or(blocker=other and blocked=u)) then raise exception 'Spieler nicht verfügbar';end if;
 d:=chaos_private.chaos_social_v7(action,display_name,avatar_id,friend_code,target_id,item_id);
 if action='accept_challenge' and d->'game'->'room' is not null then
  select * into r from public.chaos_rooms where id=(d->'game'->'room'->>'id')::uuid for update;
  if r.phase='lobby' and r.guest=u then
   update public.chaos_rooms set phase='select',select_until=clock_timestamp()+interval '10 seconds',updated_at=clock_timestamp() where id=r.id;
   d:=jsonb_set(d,'{game}',public.chaos_action('ping',r.code));
  end if;
 end if;return d;
end;$$;
revoke all on function public.chaos_chat(text,uuid,text,uuid,uuid),public.chaos_community(),public.chaos_social(text,text,integer,text,uuid,text) from public,anon;
grant execute on function public.chaos_chat(text,uuid,text,uuid,uuid),public.chaos_community(),public.chaos_social(text,text,integer,text,uuid,text) to authenticated;
revoke all on all functions in schema chaos_private from public,anon,authenticated;
commit;
