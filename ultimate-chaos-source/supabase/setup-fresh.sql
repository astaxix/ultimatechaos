-- ULTIMATE CHAOS: run only on a fresh Supabase project in SQL Editor.
-- All schema changes commit together. Existing game installations are protected.
begin;
do $$ begin
 if to_regclass('public.chaos_rooms') is not null then
  raise exception 'Game already installed. Apply only missing individual migrations.';
 end if;
end $$;

-- 001_game.sql
-- All secret moves live outside the exposed public schema.
create schema if not exists chaos_private;
revoke all on schema chaos_private from public, anon, authenticated;

create table public.chaos_rooms (
 id uuid primary key default gen_random_uuid(),
 code text unique not null check(code ~ '^[A-Z0-9]{6}$'),
 host uuid not null, guest uuid,
 host_name text not null, guest_name text,
 phase text not null default 'lobby' check(phase in ('lobby','select','result','finished')),
 match_no integer not null default 1,
 round_no integer not null default 1,
 host_score integer not null default 0, guest_score integer not null default 0,
 host_locked boolean not null default false, guest_locked boolean not null default false,
 host_ready boolean not null default false, guest_ready boolean not null default false,
 host_choice integer, guest_choice integer,
 winner uuid, reveal_at timestamptz,
 host_seen timestamptz not null default now(), guest_seen timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(host <> guest), check(host_score between 0 and 3), check(guest_score between 0 and 3),
 check(host_choice between 0 and 6), check(guest_choice between 0 and 6),
 check(phase in ('result','finished') or (host_choice is null and guest_choice is null))
);
create table chaos_private.moves (
 room_id uuid not null references public.chaos_rooms on delete cascade,
 match_no integer not null, round_no integer not null,
 player uuid not null, choice integer not null check(choice between 0 and 6),
 primary key(room_id,match_no,round_no,player)
);
create table chaos_private.limits (
 player uuid primary key, created timestamptz, joined timestamptz, join_count integer not null default 0
);
alter table public.chaos_rooms enable row level security;
create policy members_read on public.chaos_rooms for select to authenticated
 using (auth.uid() = host or auth.uid() = guest);
revoke all on public.chaos_rooms from anon, authenticated;
grant select on public.chaos_rooms to authenticated;
revoke all on all tables in schema chaos_private from public, anon, authenticated;

create function chaos_private.beats(a integer,b integer) returns boolean
language sql immutable set search_path = '' as $$
 select case a
 when 0 then b in (2,5,4) when 1 then b in (0,5,6) when 2 then b in (1,3,6)
 when 3 then b in (0,1,4) when 4 then b in (1,2,6) when 5 then b in (2,3,4)
 when 6 then b in (0,3,5) else false end
$$;

create function public.chaos_action(
 action text, room_code text default null, player_name text default null,
 choice integer default null, expected_round integer default null, expected_match integer default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 u uuid := auth.uid(); r public.chaos_rooms; lim chaos_private.limits;
 a integer; b integer; mine integer; candidate text; i integer;
 alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
 if u is null then raise exception 'Anmeldung erforderlich'; end if;
 if action in ('create','join') then
  if player_name is null or length(trim(player_name)) not between 1 and 24 then
   raise exception 'Name muss 1–24 Zeichen haben'; end if;
  insert into chaos_private.limits(player) values(u) on conflict do nothing;
  select * into lim from chaos_private.limits where player=u for update;
 end if;
 if action='create' then
  if lim.created > now()-interval '10 seconds' then raise exception 'Bitte kurz warten'; end if;
  if (select count(*) from public.chaos_rooms where host=u and updated_at>now()-interval '24 hours') >= 3 then
   raise exception 'Maximal drei aktive Räume'; end if;
  for i in 1..20 loop
   candidate := '';
   for a in 1..6 loop candidate := candidate || substr(alphabet,1+floor(random()*length(alphabet))::integer,1); end loop;
   begin
    insert into public.chaos_rooms(code,host,host_name) values(candidate,u,trim(player_name)) returning * into r;
    exit;
   exception when unique_violation then null;
   end;
  end loop;
  if r.id is null then raise exception 'Raum konnte nicht erstellt werden'; end if;
  update chaos_private.limits set created=now() where player=u;
 else
  -- Serialize every mutation, including simultaneous moves and rematches.
  if action='join' then
   if lim.joined is null or lim.joined<now()-interval '1 minute' then
    update chaos_private.limits set joined=now(),join_count=1 where player=u;
   elsif lim.join_count >= 15 then
    -- Return instead of raising, so the persisted attempt counter is not rolled back.
    return jsonb_build_object('error','Zu viele Versuche. Bitte eine Minute warten.');
   else update chaos_private.limits set join_count=join_count+1 where player=u;
   end if;
  end if;
  select * into r from public.chaos_rooms where code=upper(trim(room_code)) and updated_at>now()-interval '24 hours' for update;
  if r.id is null then
   if action='join' then return jsonb_build_object('error','Raum nicht gefunden oder abgelaufen'); end if;
   raise exception 'Raum nicht gefunden oder abgelaufen';
  end if;
  if action='join' then
   if u=r.host or u=r.guest then null;
   elsif r.guest is not null or r.phase<>'lobby' then return jsonb_build_object('error','Raum ist bereits voll');
   else r.guest:=u; r.guest_name:=trim(player_name); r.guest_seen:=now(); end if;
  elsif u<>r.host and u is distinct from r.guest then raise exception 'Kein Zugriff auf diesen Raum'; end if;
  if action in ('choose','ready') and (expected_round is distinct from r.round_no or expected_match is distinct from r.match_no) then
   raise exception 'Runde hat sich geändert. Bitte aktualisieren'; end if;
  if action='start' then
   if u<>r.host then raise exception 'Nur der Gastgeber kann starten'; end if;
   if r.phase<>'lobby' or r.guest is null or r.guest_seen<now()-interval '45 seconds' then raise exception 'Beide Spieler müssen verbunden sein'; end if;
   r.phase:='select';
  elsif action='choose' then
   if r.phase<>'select' or choice is null or choice not between 0 and 6 then raise exception 'Ungültiger Spielzug'; end if;
   select m.choice into mine from chaos_private.moves m where m.room_id=r.id and m.match_no=r.match_no and m.round_no=r.round_no and m.player=u;
   if mine is not null and mine<>choice then raise exception 'Auswahl ist bereits verbindlich'; end if;
   insert into chaos_private.moves values(r.id,r.match_no,r.round_no,u,choice) on conflict do nothing;
   if u=r.host then r.host_locked:=true; else r.guest_locked:=true; end if;
   if r.host_locked and r.guest_locked then
    select m.choice into a from chaos_private.moves m where m.room_id=r.id and m.match_no=r.match_no and m.round_no=r.round_no and m.player=r.host;
    select m.choice into b from chaos_private.moves m where m.room_id=r.id and m.match_no=r.match_no and m.round_no=r.round_no and m.player=r.guest;
    r.host_choice:=a; r.guest_choice:=b; r.winner:=null;
    if a<>b then
     if chaos_private.beats(a,b) then r.winner:=r.host; r.host_score:=r.host_score+1;
     else r.winner:=r.guest; r.guest_score:=r.guest_score+1; end if;
    end if;
    r.phase:=case when r.host_score=3 or r.guest_score=3 then 'finished' else 'result' end;
    r.reveal_at:=now()+interval '3 seconds';
   end if;
  elsif action='ready' then
   if r.phase not in ('result','finished') or now()<r.reveal_at+interval '4 seconds' then raise exception 'Kampf läuft noch'; end if;
   if u=r.host then r.host_ready:=true; else r.guest_ready:=true; end if;
   if r.host_ready and r.guest_ready then
    if r.phase='finished' then
     r.match_no:=r.match_no+1; r.round_no:=1; r.host_score:=0; r.guest_score:=0;
     delete from chaos_private.moves where room_id=r.id;
    else r.round_no:=r.round_no+1; end if;
    r.phase:='select'; r.host_ready:=false; r.guest_ready:=false;
    r.host_locked:=false; r.guest_locked:=false; r.host_choice:=null; r.guest_choice:=null;
    r.winner:=null; r.reveal_at:=null;
   end if;
  elsif action='leave' then
   if u=r.host then delete from public.chaos_rooms where id=r.id; return jsonb_build_object('left',true); end if;
   if r.phase='lobby' then r.guest:=null; r.guest_name:=null; r.guest_seen:=null;
   else r.guest_seen:=now()-interval '1 minute'; end if;
  elsif action not in ('join','state','ping') then raise exception 'Ungültige Aktion'; end if;
 end if;
 if action<>'state' and action<>'leave' then
  if u=r.host then r.host_seen:=now(); else r.guest_seen:=now(); end if;
 end if;
 if action<>'state' then
  r.updated_at:=now();
  update public.chaos_rooms set guest=r.guest,guest_name=r.guest_name,phase=r.phase,
   match_no=r.match_no,round_no=r.round_no,host_score=r.host_score,guest_score=r.guest_score,
   host_locked=r.host_locked,guest_locked=r.guest_locked,host_ready=r.host_ready,guest_ready=r.guest_ready,
   host_choice=r.host_choice,guest_choice=r.guest_choice,winner=r.winner,reveal_at=r.reveal_at,
   host_seen=r.host_seen,guest_seen=r.guest_seen,updated_at=r.updated_at where id=r.id;
 end if;
 select m.choice into mine from chaos_private.moves m where m.room_id=r.id and m.match_no=r.match_no and m.round_no=r.round_no and m.player=u;
 return jsonb_build_object('room',to_jsonb(r),'my_choice',mine,'server_now',now());
end;
$$;
revoke all on function public.chaos_action(text,text,text,integer,integer,integer) from public, anon;
grant execute on function public.chaos_action(text,text,text,integer,integer,integer) to authenticated;
revoke all on all functions in schema chaos_private from public,anon,authenticated;
-- Only the sanitized rooms table is published. Never add chaos_private.moves.
alter publication supabase_realtime add table public.chaos_rooms;


-- 003_timed_rounds.sql
-- Upgrade existing games to 10 rounds with a server-authoritative 5 second window.
-- Run after 001 (and 002 for cleanup). Existing active games return to the lobby.
alter table public.chaos_rooms drop constraint chaos_rooms_host_score_check;
alter table public.chaos_rooms drop constraint chaos_rooms_guest_score_check;
alter table public.chaos_rooms add constraint chaos_rooms_host_score_check check(host_score between 0 and 10);
alter table public.chaos_rooms add constraint chaos_rooms_guest_score_check check(guest_score between 0 and 10);
alter table public.chaos_rooms add column select_until timestamptz;
alter table public.chaos_rooms add column next_round_at timestamptz;
alter table public.chaos_rooms add column match_winner uuid;
update public.chaos_rooms set phase='lobby',round_no=1,match_no=match_no+1,host_score=0,guest_score=0,
 host_locked=false,guest_locked=false,host_ready=false,guest_ready=false,
 host_choice=null,guest_choice=null,winner=null,reveal_at=null;
delete from chaos_private.moves;

create function chaos_private.advance(r public.chaos_rooms) returns public.chaos_rooms
language plpgsql set search_path='' as $$
declare a integer; b integer;
begin
 if r.phase='select' and clock_timestamp()>=r.select_until then
  select m.choice into a from chaos_private.moves m where m.room_id=r.id and m.match_no=r.match_no and m.round_no=r.round_no and m.player=r.host;
  select m.choice into b from chaos_private.moves m where m.room_id=r.id and m.match_no=r.match_no and m.round_no=r.round_no and m.player=r.guest;
  r.host_choice:=a; r.guest_choice:=b; r.winner:=null;
  if a is null and b is not null then r.winner:=r.guest;
  elsif b is null and a is not null then r.winner:=r.host;
  elsif a is not null and b is not null and a<>b then
   r.winner:=case when chaos_private.beats(a,b) then r.host else r.guest end;
  end if;
  if r.winner=r.host then r.host_score:=r.host_score+1;
  elsif r.winner=r.guest then r.guest_score:=r.guest_score+1; end if;
  r.reveal_at:=r.select_until; r.next_round_at:=r.select_until+interval '6 seconds';
  r.phase:=case when r.round_no=10 then 'finished' else 'result' end;
  if r.phase='finished' then
   r.match_winner:=case when r.host_score>r.guest_score then r.host when r.guest_score>r.host_score then r.guest else null end;
  end if;
 end if;
 if r.phase='result' and clock_timestamp()>=r.next_round_at then
  r.round_no:=r.round_no+1; r.phase:='select';
  r.select_until:=clock_timestamp()+interval '5 seconds'; r.next_round_at:=null;
  r.host_choice:=null; r.guest_choice:=null; r.winner:=null; r.reveal_at:=null;
  r.host_locked:=false; r.guest_locked:=false;
 end if;
 return r;
end;
$$;
revoke all on function chaos_private.advance(public.chaos_rooms) from public,anon,authenticated;

create or replace function public.chaos_action(
 action text, room_code text default null, player_name text default null,
 choice integer default null, expected_round integer default null, expected_match integer default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 u uuid:=auth.uid(); r public.chaos_rooms; prior public.chaos_rooms;
 lim chaos_private.limits; mine integer; candidate text; i integer; a integer;
 alphabet text:='ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; action_error text;
begin
 if u is null then raise exception 'Anmeldung erforderlich'; end if;
 if action in ('create','join') then
  if player_name is null or length(trim(player_name)) not between 1 and 24 then raise exception 'Name muss 1–24 Zeichen haben'; end if;
  insert into chaos_private.limits(player) values(u) on conflict do nothing;
  select * into lim from chaos_private.limits where player=u for update;
 end if;
 if action='create' then
  if lim.created>clock_timestamp()-interval '10 seconds' then raise exception 'Bitte kurz warten'; end if;
  if (select count(*) from public.chaos_rooms where host=u and updated_at>clock_timestamp()-interval '24 hours')>=3 then raise exception 'Maximal drei aktive Räume'; end if;
  for i in 1..20 loop
   candidate:='';
   for a in 1..6 loop candidate:=candidate||substr(alphabet,1+floor(random()*length(alphabet))::integer,1); end loop;
   begin
    insert into public.chaos_rooms(code,host,host_name) values(candidate,u,trim(player_name)) returning * into r; exit;
   exception when unique_violation then null; end;
  end loop;
  if r.id is null then raise exception 'Raum konnte nicht erstellt werden'; end if;
  update chaos_private.limits set created=clock_timestamp() where player=u;
 else
  if action='join' then
   if lim.joined is null or lim.joined<clock_timestamp()-interval '1 minute' then
    update chaos_private.limits set joined=clock_timestamp(),join_count=1 where player=u;
   elsif lim.join_count>=15 then return jsonb_build_object('error','Zu viele Versuche. Bitte eine Minute warten.');
   else update chaos_private.limits set join_count=join_count+1 where player=u; end if;
  end if;
  select * into r from public.chaos_rooms where code=upper(trim(room_code)) and updated_at>clock_timestamp()-interval '24 hours' for update;
  if r.id is null then
   if action='join' then return jsonb_build_object('error','Raum nicht gefunden oder abgelaufen'); end if;
   raise exception 'Raum nicht gefunden oder abgelaufen';
  end if;
  prior:=r;
  if action='join' then
   if u=r.host or u=r.guest then null;
   elsif r.guest is not null or r.phase<>'lobby' then return jsonb_build_object('error','Raum ist bereits voll');
   else r.guest:=u; r.guest_name:=trim(player_name); r.guest_seen:=clock_timestamp(); end if;
  elsif u<>r.host and u is distinct from r.guest then raise exception 'Kein Zugriff auf diesen Raum'; end if;
  -- Only members may advance a room. Even state reads finalize overdue windows.
  r:=chaos_private.advance(r);
  if action in ('choose','ready') and (expected_round is distinct from r.round_no or expected_match is distinct from r.match_no) then
   action_error:='Runde hat sich geändert. Bitte aktualisieren';
  elsif action='start' then
   if u<>r.host then raise exception 'Nur der Gastgeber kann starten'; end if;
   if r.phase<>'lobby' or r.guest is null or r.guest_seen<clock_timestamp()-interval '45 seconds' then raise exception 'Beide Spieler müssen verbunden sein'; end if;
   r.phase:='select'; r.select_until:=clock_timestamp()+interval '5 seconds';
  elsif action='choose' then
   if r.phase<>'select' or clock_timestamp()>=r.select_until then action_error:='Auswahlzeit abgelaufen';
   elsif choice is null or choice not between 0 and 6 then action_error:='Ungültiger Spielzug';
   else
    -- Editable until the server deadline. The final accepted choice is used.
    insert into chaos_private.moves values(r.id,r.match_no,r.round_no,u,choice)
     on conflict(room_id,match_no,round_no,player) do update set choice=excluded.choice;
    if u=r.host then r.host_locked:=true; else r.guest_locked:=true; end if;
   end if;
  elsif action='ready' then
   if r.phase<>'finished' then action_error:='Nur nach zehn Runden ist ein Rematch möglich';
   elsif clock_timestamp()<r.next_round_at then action_error:='Kampf läuft noch';
   else
    if u=r.host then r.host_ready:=true; else r.guest_ready:=true; end if;
    if r.host_ready and r.guest_ready then
     r.match_no:=r.match_no+1; r.round_no:=1; r.host_score:=0; r.guest_score:=0; r.match_winner:=null;
     r.phase:='select'; r.select_until:=clock_timestamp()+interval '5 seconds'; r.next_round_at:=null;
     r.host_ready:=false; r.guest_ready:=false; r.host_locked:=false; r.guest_locked:=false;
     r.host_choice:=null; r.guest_choice:=null; r.winner:=null; r.reveal_at:=null;
     delete from chaos_private.moves where room_id=r.id;
    end if;
   end if;
  elsif action='leave' then
   if u=r.host then delete from public.chaos_rooms where id=r.id; return jsonb_build_object('left',true); end if;
   if r.phase='lobby' then r.guest:=null; r.guest_name:=null; r.guest_seen:=null;
   else r.guest_seen:=clock_timestamp()-interval '1 minute'; end if;
  elsif action not in ('join','state','ping') then raise exception 'Ungültige Aktion'; end if;
 end if;
 if action not in ('state','leave') then
  if u=r.host then r.host_seen:=clock_timestamp(); else r.guest_seen:=clock_timestamp(); end if;
 end if;
 if action<>'state' or r is distinct from prior then
  r.updated_at:=clock_timestamp();
  update public.chaos_rooms set guest=r.guest,guest_name=r.guest_name,phase=r.phase,
   match_no=r.match_no,round_no=r.round_no,host_score=r.host_score,guest_score=r.guest_score,
   host_locked=r.host_locked,guest_locked=r.guest_locked,host_ready=r.host_ready,guest_ready=r.guest_ready,
   host_choice=r.host_choice,guest_choice=r.guest_choice,winner=r.winner,reveal_at=r.reveal_at,
   host_seen=r.host_seen,guest_seen=r.guest_seen,updated_at=r.updated_at,
   select_until=r.select_until,next_round_at=r.next_round_at,match_winner=r.match_winner where id=r.id;
 end if;
 select m.choice into mine from chaos_private.moves m where m.room_id=r.id and m.match_no=r.match_no and m.round_no=r.round_no and m.player=u;
 return jsonb_build_object('room',to_jsonb(r),'my_choice',mine,'server_now',clock_timestamp(),'error',action_error);
end;
$$;


-- 004_accounts_social.sql
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


-- 002_cleanup.sql
-- Run after 001. Enable pg_cron in Supabase Database > Extensions first.
create extension if not exists pg_cron;
create function chaos_private.cleanup() returns void
language sql security definer set search_path='' as $$
 delete from public.chaos_rooms where updated_at<now()-interval '24 hours';
 delete from chaos_private.limits where coalesce(created,joined,'epoch'::timestamptz)<now()-interval '7 days';
$$;
revoke all on function chaos_private.cleanup() from public,anon,authenticated;
select cron.schedule('chaos-cleanup','*/15 * * * *','select chaos_private.cleanup()');


commit;
