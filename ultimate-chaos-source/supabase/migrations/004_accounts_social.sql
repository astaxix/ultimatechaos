-- Authenticated accounts, profiles, social graph, cosmetic shop, earned rewards.
create table public.chaos_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 name text not null check(length(trim(name)) between 2 and 24),
 friend_code text unique not null check(friend_code ~ '^[A-F0-9]{8}$'),
 avatar integer not null default 4 check(avatar between 0 and 6),
 frame text not null default 'basic' check(frame in ('basic','violet','gold','celestial')),
 xp integer not null default 0 check(xp>=0),coins integer not null default 250 check(coins>=0),
 matches integer not null default 0,wins integer not null default 0,
 last_seen timestamptz not null default clock_timestamp(),created_at timestamptz not null default clock_timestamp()
);
create table public.chaos_friends (
 id uuid primary key default gen_random_uuid(),requester uuid not null references public.chaos_profiles on delete cascade,
 receiver uuid not null references public.chaos_profiles on delete cascade,
 status text not null default 'pending' check(status in ('pending','accepted')),
 pair_key text generated always as (least(requester::text,receiver::text)||':'||greatest(requester::text,receiver::text)) stored unique,
 created_at timestamptz not null default clock_timestamp(),check(requester<>receiver)
);
create table public.chaos_challenges (
 id uuid primary key default gen_random_uuid(),sender uuid not null references public.chaos_profiles on delete cascade,
 receiver uuid not null references public.chaos_profiles on delete cascade,
 room_id uuid not null references public.chaos_rooms on delete cascade,
 status text not null default 'pending' check(status in ('pending','accepted','declined')),
 expires_at timestamptz not null default clock_timestamp()+interval '10 minutes',created_at timestamptz not null default clock_timestamp(),
 check(sender<>receiver)
);
create table chaos_private.inventory (
 player uuid not null references public.chaos_profiles on delete cascade,item text not null check(item in ('violet','gold','celestial')),
 primary key(player,item)
);
create table chaos_private.rewards (
 room_id uuid not null references public.chaos_rooms on delete cascade,match_no integer not null,player uuid not null,
 primary key(room_id,match_no,player)
);
alter table public.chaos_rooms add column reserved_guest uuid references public.chaos_profiles;
alter table public.chaos_profiles enable row level security;
alter table public.chaos_friends enable row level security;
alter table public.chaos_challenges enable row level security;
create policy profile_self on public.chaos_profiles for select to authenticated using(id=auth.uid());
create policy friend_members on public.chaos_friends for select to authenticated using(auth.uid() in (requester,receiver));
create policy challenge_members on public.chaos_challenges for select to authenticated using(auth.uid() in (sender,receiver));
revoke all on public.chaos_profiles,public.chaos_friends,public.chaos_challenges from public,anon,authenticated;
grant select on public.chaos_profiles,public.chaos_friends,public.chaos_challenges to authenticated;
revoke all on chaos_private.inventory,chaos_private.rewards from public,anon,authenticated;
alter publication supabase_realtime add table public.chaos_friends,public.chaos_challenges;

create function chaos_private.account_uid() returns uuid
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();
begin
 if u is null or not exists(select 1 from auth.users where id=u and not coalesce(is_anonymous,false) and email_confirmed_at is not null) then
  raise exception 'Bitte mit einem bestätigten Konto anmelden';
 end if;
 return u;
end;
$$;
revoke all on function chaos_private.account_uid() from public,anon,authenticated;

create function chaos_private.reward_match() returns trigger
language plpgsql security definer set search_path='' as $$
declare p uuid; inserted integer; coin_reward integer; xp_reward integer;
begin
 if new.phase='finished' and (old.phase is distinct from new.phase or old.match_no<>new.match_no) then
  for p in select id from (select new.host as id union select new.guest as id) players order by id loop
   -- Do not grant rewards for inactivity-farming: the player must have selected in every round.
   if p is not null and (select count(*) from chaos_private.moves where room_id=new.id and match_no=new.match_no and player=p)=10 then
    insert into chaos_private.rewards values(new.id,new.match_no,p) on conflict do nothing;
    get diagnostics inserted=row_count;
    if inserted=1 then
     coin_reward:=case when new.match_winner=p then 100 when new.match_winner is null then 60 else 40 end;
     xp_reward:=case when new.match_winner=p then 120 when new.match_winner is null then 80 else 60 end;
     update public.chaos_profiles set coins=coins+coin_reward,xp=xp+xp_reward,matches=matches+1,wins=wins+case when new.match_winner=p then 1 else 0 end where id=p;
    end if;
   end if;
  end loop;
 end if;
 return new;
end;
$$;
revoke all on function chaos_private.reward_match() from public,anon,authenticated;
create trigger award_match after update on public.chaos_rooms for each row execute function chaos_private.reward_match();

-- Wrap the tested timed game engine in registered-account checks.
alter function public.chaos_action(text,text,text,integer,integer,integer) set schema chaos_private;
alter function chaos_private.chaos_action(text,text,text,integer,integer,integer) rename to play;
revoke all on function chaos_private.play(text,text,text,integer,integer,integer) from public,anon,authenticated;
create function public.chaos_action(action text,room_code text default null,player_name text default null,choice integer default null,expected_round integer default null,expected_match integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid(); p public.chaos_profiles; reserved uuid;
begin
 select * into p from public.chaos_profiles where id=u;
 if p.id is null then raise exception 'Bitte zuerst dein Profil einrichten'; end if;
 if action='join' then
  select reserved_guest into reserved from public.chaos_rooms where code=upper(trim(room_code)) for update;
  if reserved is not null and reserved<>u and not exists(select 1 from public.chaos_rooms where code=upper(trim(room_code)) and host=u) then
   raise exception 'Dieser Raum ist für einen herausgeforderten Freund reserviert';
  end if;
 end if;
 return chaos_private.play(action,room_code,p.name,choice,expected_round,expected_match);
end;
$$;
revoke all on function public.chaos_action(text,text,text,integer,integer,integer) from public,anon;
grant execute on function public.chaos_action(text,text,text,integer,integer,integer) to authenticated;

create function public.chaos_social(action text,display_name text default null,avatar_id integer default null,friend_code text default null,target_id uuid default null,item_id text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 u uuid:=chaos_private.account_uid(); p public.chaos_profiles; f public.chaos_friends; ch public.chaos_challenges;
 other uuid; price integer; code text; result jsonb; created_room uuid;
begin
 select * into p from public.chaos_profiles where id=u for update;
 if action='profile' then
  if display_name is null or length(trim(display_name)) not between 2 and 24 or avatar_id is null or avatar_id not between 0 and 6 then raise exception 'Name oder Profilbild ungültig'; end if;
  if p.id is null then
   loop
    code:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
    begin insert into public.chaos_profiles(id,name,friend_code,avatar) values(u,trim(display_name),code,avatar_id) returning * into p;exit;
    exception when unique_violation then
     select * into p from public.chaos_profiles where id=u;
     if p.id is not null then exit; end if;
    end;
   end loop;
  else update public.chaos_profiles set name=trim(display_name),avatar=avatar_id where id=u returning * into p; end if;
 elsif p.id is null then return jsonb_build_object('profile',null,'friends','[]'::jsonb,'challenges','[]'::jsonb,'inventory','[]'::jsonb);
 elsif action='add_friend' then
  select id into other from public.chaos_profiles where public.chaos_profiles.friend_code=upper(trim(chaos_social.friend_code));
  if other is null or other=u then raise exception 'Freundescode nicht gefunden oder dein eigener Code'; end if;
  if (select count(*) from public.chaos_friends where requester=u and status='pending')>=20 then raise exception 'Maximal 20 offene Freundesanfragen'; end if;
  insert into public.chaos_friends(requester,receiver) values(u,other) on conflict(pair_key) do nothing;
 elsif action in ('accept_friend','decline_friend','remove_friend') then
  select * into f from public.chaos_friends where id=target_id for update;
  if f.id is null or u not in (f.requester,f.receiver) then raise exception 'Kein Zugriff auf diese Anfrage'; end if;
  if action='accept_friend' then
   if f.receiver<>u then raise exception 'Nur der Empfänger darf annehmen'; end if;
   update public.chaos_friends set status='accepted' where id=f.id;
  elsif action='decline_friend' then
   if f.receiver<>u then raise exception 'Nur der Empfänger darf ablehnen'; end if;
   delete from public.chaos_friends where id=f.id;
  else delete from public.chaos_friends where id=f.id; end if;
 elsif action='challenge' then
  if not exists(select 1 from public.chaos_friends where status='accepted' and ((requester=u and receiver=target_id)or(receiver=u and requester=target_id))) then raise exception 'Nur bestätigte Freunde können herausgefordert werden'; end if;
  if exists(select 1 from public.chaos_challenges where sender=u and receiver=target_id and status='pending' and expires_at>clock_timestamp()) then raise exception 'Herausforderung ist bereits offen'; end if;
  result:=public.chaos_action('create');
  created_room:=(result->'room'->>'id')::uuid;
  update public.chaos_rooms set reserved_guest=target_id where id=created_room;
  insert into public.chaos_challenges(sender,receiver,room_id) values(u,target_id,created_room);
 elsif action in ('accept_challenge','decline_challenge') then
  select * into ch from public.chaos_challenges where id=target_id for update;
  if ch.id is null or ch.receiver<>u or ch.status<>'pending' or ch.expires_at<=clock_timestamp() then raise exception 'Herausforderung nicht verfügbar'; end if;
  if action='accept_challenge' then
   select public.chaos_rooms.code into code from public.chaos_rooms where id=ch.room_id;
   result:=public.chaos_action('join',code);
   if result->>'error' is not null then raise exception '%',result->>'error'; end if;
   update public.chaos_challenges set status='accepted' where id=ch.id;
  else update public.chaos_challenges set status='declined' where id=ch.id; end if;
 elsif action='buy' then
  price:=case item_id when 'violet' then 150 when 'gold' then 350 when 'celestial' then 700 else null end;
  if price is null then raise exception 'Shopartikel nicht gefunden'; end if;
  if exists(select 1 from chaos_private.inventory where player=u and item=item_id) then raise exception 'Artikel gehört dir bereits'; end if;
  if p.coins<price then raise exception 'Nicht genügend Coins'; end if;
  insert into chaos_private.inventory values(u,item_id);
  update public.chaos_profiles set coins=coins-price where id=u;
 elsif action='equip' then
  if item_id<>'basic' and not exists(select 1 from chaos_private.inventory where player=u and item=item_id) then raise exception 'Diesen Rahmen besitzt du nicht'; end if;
  update public.chaos_profiles set frame=item_id where id=u;
 elsif action<>'state' then raise exception 'Ungültige Aktion'; end if;
 if p.id is not null then update public.chaos_profiles set last_seen=clock_timestamp() where id=u; end if;
 select * into p from public.chaos_profiles where id=u;
 return jsonb_build_object('profile',to_jsonb(p),
  'friends',coalesce((select jsonb_agg(jsonb_build_object('id',fr.id,'status',fr.status,'incoming',fr.receiver=u,'profile',jsonb_build_object('id',o.id,'name',o.name,'avatar',o.avatar,'frame',o.frame,'xp',o.xp,'last_seen',o.last_seen)))
   from public.chaos_friends fr join public.chaos_profiles o on o.id=case when fr.requester=u then fr.receiver else fr.requester end where u in(fr.requester,fr.receiver)),'[]'::jsonb),
  'challenges',coalesce((select jsonb_agg(jsonb_build_object('id',cl.id,'incoming',cl.receiver=u,'name',o.name,'status',cl.status,'room_code',r.code,'expires_at',cl.expires_at))
   from public.chaos_challenges cl join public.chaos_profiles o on o.id=case when cl.sender=u then cl.receiver else cl.sender end join public.chaos_rooms r on r.id=cl.room_id
   where u in(cl.sender,cl.receiver) and cl.status<>'declined' and cl.expires_at>clock_timestamp() and r.phase='lobby'),'[]'::jsonb),
  'inventory',coalesce((select jsonb_agg(item) from chaos_private.inventory where player=u),'[]'::jsonb),
  'game',result);
end;
$$;
revoke all on function public.chaos_social(text,text,integer,text,uuid,text) from public,anon;
grant execute on function public.chaos_social(text,text,integer,text,uuid,text) to authenticated;
