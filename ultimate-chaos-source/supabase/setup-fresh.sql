-- ULTIMATE CHAOS: fresh projects only. Existing installations use individual migrations.
begin;
do $$ begin
 if to_regclass('public.chaos_rooms') is not null then raise exception 'Game already installed. Apply only missing individual migrations.';end if;
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


-- 005_bot_rewards.sql

alter table public.chaos_rooms add column if not exists is_bot boolean not null default false;
alter table public.chaos_profiles alter column coins set default 0;

create or replace function chaos_private.reward_match() returns trigger
language plpgsql security definer set search_path='' as $$
declare p uuid; inserted integer; coin_reward integer; xp_reward integer;
begin
 if new.phase='finished' and (old.phase is distinct from new.phase or old.match_no<>new.match_no) then
  for p in select id from (select new.host as id union select new.guest as id where not new.is_bot) players order by id loop
   -- A completed match with at least one move earns XP. AFK sessions earn nothing.
   if p is not null and exists(select 1 from chaos_private.moves where room_id=new.id and match_no=new.match_no and player=p) then
    insert into chaos_private.rewards values(new.id,new.match_no,p) on conflict do nothing;
    get diagnostics inserted=row_count;
    if inserted=1 then
     coin_reward:=case when new.match_winner=p then 100 else 0 end;
     xp_reward:=case when new.match_winner=p then 120 when new.match_winner is null then 60 else 40 end;
     update public.chaos_profiles set coins=coins+coin_reward,xp=xp+xp_reward,matches=matches+1,wins=wins+case when new.match_winner=p then 1 else 0 end where id=p;
    end if;
   end if;
  end loop;
 end if;
 return new;
end;
$$;
revoke all on function chaos_private.reward_match() from public,anon,authenticated;

create or replace function public.chaos_action(action text,room_code text default null,player_name text default null,choice integer default null,expected_round integer default null,expected_match integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid(); p public.chaos_profiles; r public.chaos_rooms; d jsonb; reserved uuid; bot_move integer;
begin
 select * into p from public.chaos_profiles where id=u;
 if p.id is null then raise exception 'Bitte zuerst dein Profil einrichten'; end if;
 if action='bot' then
  d:=chaos_private.play('create',null,p.name,null,null,null);
  select * into r from public.chaos_rooms where id=(d->'room'->>'id')::uuid for update;
  update public.chaos_rooms set is_bot=true,guest=gen_random_uuid(),guest_name='Chaos-Bot',guest_seen=clock_timestamp(),phase='select',select_until=clock_timestamp()+interval '5 seconds',guest_locked=true,updated_at=clock_timestamp() where id=r.id returning * into r;
  -- Commit the random bot move before the player receives the selection screen.
  insert into chaos_private.moves values(r.id,r.match_no,r.round_no,r.guest,floor(random()*7)::integer);
  return chaos_private.play('state',r.code,p.name,null,null,null);
 end if;
 select * into r from public.chaos_rooms where code=upper(trim(room_code)) for update;
 if action='join' then
  reserved:=r.reserved_guest;
  if r.is_bot and u<>r.host then raise exception 'Dies ist ein Duell gegen den Bot'; end if;
  if reserved is not null and reserved<>u and u<>r.host then raise exception 'Dieser Raum ist für einen herausgeforderten Freund reserviert'; end if;
 end if;
 if r.is_bot then
  if u<>r.host then raise exception 'Kein Zugriff auf dieses Bot-Duell'; end if;
  update public.chaos_rooms set guest_seen=clock_timestamp(),guest_ready=case when action='ready' then true else guest_ready end where id=r.id and (guest_seen<clock_timestamp()-interval '20 seconds' or (action='ready' and not guest_ready));
 end if;
 d:=chaos_private.play(action,room_code,p.name,choice,expected_round,expected_match);
 if d->>'left'='true' then return d; end if;
 if r.is_bot then
  select * into r from public.chaos_rooms where id=r.id;
  if r.phase='select' then
   -- Repeated reads cannot replace the precommitted choice. No client choice is read.
   bot_move:=floor(random()*7)::integer;
   insert into chaos_private.moves values(r.id,r.match_no,r.round_no,r.guest,bot_move) on conflict do nothing;
   update public.chaos_rooms set guest_locked=true where id=r.id and not guest_locked;
   select * into r from public.chaos_rooms where id=r.id;
  end if;
  d:=jsonb_set(d,'{room}',to_jsonb(r));
 end if;
 if d->'room'->>'phase'='finished' and exists(select 1 from chaos_private.rewards where room_id=(d->'room'->>'id')::uuid and match_no=(d->'room'->>'match_no')::integer and player=u) then
  d:=d||jsonb_build_object('rewards',jsonb_build_object('xp',case when d->'room'->>'match_winner'=u::text then 120 when d->'room'->>'match_winner' is null then 60 else 40 end,'coins',case when d->'room'->>'match_winner'=u::text then 100 else 0 end,'total_xp',(select xp from public.chaos_profiles where id=u)));
 end if;
 return d;
end;
$$;
revoke all on function public.chaos_action(text,text,text,integer,integer,integer) from public,anon;
grant execute on function public.chaos_action(text,text,text,integer,integer,integer) to authenticated;


-- 006_character_atelier.sql

alter table public.chaos_profiles add column if not exists appearance jsonb not null default '{"body":"masculine","skin":"#dba77d","hair":"swept","hairColor":"#30251f","eyes":"#63b5bd","face":"soft","brows":"natural","beard":"none","outfitColor":"#344761","outfit":"starter","hat":"none","aura":"none"}';
alter table chaos_private.inventory drop constraint if exists inventory_item_check;
create table if not exists chaos_private.styles(id text primary key,slot text not null check(slot in ('outfit','hat','aura','frame')),price integer not null check(price>0));
insert into chaos_private.styles values
 ('coat-nocturne','outfit',450),('armor-solstice','outfit',900),('jacket-street','outfit',250),('robe-astral','outfit',550),
 ('hat-beanie','hat',150),('hat-crown','hat',650),('hat-cap','hat',200),('hat-halo','hat',400),
 ('aura-ember','aura',500),('aura-frost','aura',500),('aura-void','aura',1000),
 ('violet','frame',150),('gold','frame',350),('celestial','frame',700) on conflict(id) do nothing;
revoke all on chaos_private.styles from public,anon,authenticated;
alter table chaos_private.inventory add constraint inventory_style_fk foreign key(item) references chaos_private.styles(id);

-- Keep the proven social engine and enrich only already-authorized friend records.
alter function public.chaos_social(text,text,integer,text,uuid,text) rename to chaos_social_v4;
alter function public.chaos_social_v4(text,text,integer,text,uuid,text) set schema chaos_private;
do $$begin execute replace(pg_get_functiondef('chaos_private.chaos_social_v4(text,text,integer,text,uuid,text)'::regprocedure),'chaos_social.friend_code','chaos_social_v4.friend_code');end;$$;
revoke all on function chaos_private.chaos_social_v4(text,text,integer,text,uuid,text) from public,anon,authenticated;
create function public.chaos_social(action text,display_name text default null,avatar_id integer default null,friend_code text default null,target_id uuid default null,item_id text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d jsonb;
begin
 d:=chaos_private.chaos_social_v4(action,display_name,avatar_id,friend_code,target_id,item_id);
 return jsonb_set(d,'{friends}',coalesce((select jsonb_agg(jsonb_set(f,'{profile,appearance}',p.appearance)) from jsonb_array_elements(d->'friends') f join public.chaos_profiles p on p.id=(f->'profile'->>'id')::uuid),'[]'::jsonb));
end;
$$;
revoke all on function public.chaos_social(text,text,integer,text,uuid,text) from public,anon;
grant execute on function public.chaos_social(text,text,integer,text,uuid,text) to authenticated;

create function public.chaos_style(action text,appearance jsonb default null,item_id text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();p public.chaos_profiles;s chaos_private.styles;k text;v text;normalized jsonb;slot_name text;
begin
 select * into p from public.chaos_profiles where id=u for update;
 if p.id is null then raise exception 'Bitte zuerst dein Profil einrichten'; end if;
 if action='appearance' then
  if appearance is null or jsonb_typeof(appearance)<>'object' or octet_length(appearance::text)>2048 then raise exception 'Aussehen ungültig'; end if;
  normalized:=p.appearance;
  for k,v in select key,value from jsonb_each_text(appearance) loop
   if k in ('skin','hairColor','eyes','outfitColor') then
    if v is null or v !~ '^#[a-fA-F0-9]{6}$' then raise exception 'Farbe ungültig'; end if;
   elsif k='body' then
    if v is null or v not in ('masculine','feminine','androgynous') then raise exception 'Körper ungültig'; end if;
   elsif k='hair' then
    if v is null or v not in ('swept','crop','curls','long','bob','braids','bun','bald') then raise exception 'Frisur ungültig'; end if;
   elsif k='face' then
    if v is null or v not in ('soft','angular','round') then raise exception 'Gesicht ungültig'; end if;
   elsif k='brows' then
    if v is null or v not in ('natural','bold') then raise exception 'Augenbrauen ungültig'; end if;
   elsif k='beard' then
    if v is null or v not in ('none','stubble','full') then raise exception 'Bart ungültig'; end if;
   elsif k in ('outfit','hat','aura') then
    -- Appearance editing cannot grant or equip paid cosmetics.
    if v is distinct from p.appearance->>k then raise exception 'Styles bitte über die Sammlung ausrüsten'; end if;
   else raise exception 'Unbekannte Aussehensoption'; end if;
   normalized:=jsonb_set(normalized,array[k],to_jsonb(v));
  end loop;
  update public.chaos_profiles set appearance=normalized where id=u;
 elsif action='buy' then
  select * into s from chaos_private.styles where id=item_id;
  if s.id is null then raise exception 'Shopartikel nicht gefunden'; end if;
  if exists(select 1 from chaos_private.inventory where player=u and item=item_id) then raise exception 'Artikel gehört dir bereits'; end if;
  if p.coins<s.price then raise exception 'Nicht genügend Coins'; end if;
  insert into chaos_private.inventory values(u,item_id);
  update public.chaos_profiles set coins=coins-s.price where id=u;
 elsif action='equip' then
  if item_id in ('outfit:reset','hat:reset','aura:reset') then
   slot_name:=split_part(item_id,':',1);
   update public.chaos_profiles set appearance=jsonb_set(public.chaos_profiles.appearance,array[slot_name],to_jsonb(case when slot_name='outfit' then 'starter' else 'none' end)) where id=u;
  elsif item_id='basic' then update public.chaos_profiles set frame='basic' where id=u;
  else
   select * into s from chaos_private.styles where id=item_id;
   if s.id is null or not exists(select 1 from chaos_private.inventory where player=u and item=item_id) then raise exception 'Diesen Style besitzt du nicht'; end if;
   if s.slot='frame' then update public.chaos_profiles set frame=s.id where id=u;
   else update public.chaos_profiles set appearance=jsonb_set(public.chaos_profiles.appearance,array[s.slot],to_jsonb(s.id)) where id=u; end if;
  end if;
 elsif action<>'state' then raise exception 'Ungültige Aktion'; end if;
 return public.chaos_social('state');
end;
$$;
revoke all on function public.chaos_style(text,jsonb,text) from public,anon;
grant execute on function public.chaos_style(text,jsonb,text) to authenticated;

alter function public.chaos_action(text,text,text,integer,integer,integer) rename to chaos_action_v5;
alter function public.chaos_action_v5(text,text,text,integer,integer,integer) set schema chaos_private;
revoke all on function chaos_private.chaos_action_v5(text,text,text,integer,integer,integer) from public,anon,authenticated;
create function public.chaos_action(action text,room_code text default null,player_name text default null,choice integer default null,expected_round integer default null,expected_match integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d jsonb;h public.chaos_profiles;g public.chaos_profiles;u uuid:=chaos_private.account_uid();
begin
 d:=chaos_private.chaos_action_v5(action,room_code,player_name,choice,expected_round,expected_match);
 if d->>'left'='true' or d->'room' is null then return d; end if;
 select * into h from public.chaos_profiles where id=(d->'room'->>'host')::uuid;
 select * into g from public.chaos_profiles where id=(d->'room'->>'guest')::uuid;
 return d||jsonb_build_object('players',jsonb_build_object('host',jsonb_build_object('appearance',h.appearance,'frame',h.frame,'xp',h.xp),'guest',jsonb_build_object('appearance',g.appearance,'frame',g.frame,'xp',g.xp)),
  'wallet',(select jsonb_build_object('xp',xp,'coins',coins) from public.chaos_profiles where id=u));
end;
$$;
revoke all on function public.chaos_action(text,text,text,integer,integer,integer) from public,anon;
grant execute on function public.chaos_action(text,text,text,integer,integer,integer) to authenticated;


-- 007_campaign_packs.sql

alter table public.chaos_profiles add column campaign_unlocked integer not null default 0 check(campaign_unlocked between 0 and 8);
alter table public.chaos_profiles add column card_skin text not null default 'classic';
alter table public.chaos_rooms add column campaign_stage integer check(campaign_stage between 0 and 7);
alter table public.chaos_rooms add column round_limit integer not null default 10 check(round_limit between 10 and 18);
alter table public.chaos_rooms add column required_wins integer not null default 0 check(required_wins between 0 and 18);
alter table public.chaos_rooms add column reward_xp integer not null default 120;
alter table public.chaos_rooms add column reward_coins integer not null default 100;
alter table public.chaos_rooms drop constraint chaos_rooms_host_score_check;
alter table public.chaos_rooms drop constraint chaos_rooms_guest_score_check;
alter table public.chaos_rooms add check(host_score between 0 and 18);
alter table public.chaos_rooms add check(guest_score between 0 and 18);
alter table chaos_private.styles drop constraint styles_slot_check;
alter table chaos_private.styles add check(slot in ('outfit','hat','aura','frame','card'));
alter table chaos_private.styles add column rarity integer not null default 1 check(rarity between 1 and 3);
update chaos_private.styles set rarity=case when id in ('armor-solstice','hat-crown','aura-void','celestial') then 3 when id in ('coat-nocturne','robe-astral','hat-halo','aura-ember','aura-frost','gold') then 2 else 1 end;
insert into chaos_private.styles values('card-frost','card',350,1),('card-ember','card',650,2),('card-eclipse','card',1000,3);
create table chaos_private.packs(player uuid not null references public.chaos_profiles on delete cascade,tier integer not null check(tier between 0 and 2),quantity integer not null default 0 check(quantity>=0),primary key(player,tier));
create table chaos_private.loot_receipts(id uuid primary key,player uuid not null references public.chaos_profiles on delete cascade,action text not null,tier integer not null,reward jsonb not null,created_at timestamptz not null default clock_timestamp());
revoke all on chaos_private.packs,chaos_private.loot_receipts from public,anon,authenticated;
insert into chaos_private.packs select id,0,xp/250 from public.chaos_profiles where xp>=250;
create function chaos_private.level_packs() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.xp/250>old.xp/250 then insert into chaos_private.packs values(new.id,0,new.xp/250-old.xp/250) on conflict(player,tier) do update set quantity=chaos_private.packs.quantity+excluded.quantity;end if;
 return new;
end;$$;
revoke all on function chaos_private.level_packs() from public,anon,authenticated;
create trigger grant_level_packs after update of xp on public.chaos_profiles for each row execute function chaos_private.level_packs();

-- Existing game rules, with immutable per-room campaign round limits and boss objectives.
do $$declare definition text;begin
 definition:=pg_get_functiondef('chaos_private.advance(public.chaos_rooms)'::regprocedure);
 definition:=replace(definition,'r.round_no=10','r.round_no=r.round_limit');
 definition:=replace(definition,'r.match_winner:=case when r.host_score>r.guest_score then r.host when r.guest_score>r.host_score then r.guest else null end;',
 'r.match_winner:=case when r.is_bot and r.required_wins>0 then case when r.host_score>=r.required_wins then r.host else r.guest end when r.host_score>r.guest_score then r.host when r.guest_score>r.host_score then r.guest else null end;');
 execute definition;
end;$$;
create function chaos_private.bot_choice(r public.chaos_rooms) returns integer language plpgsql set search_path='' as $$
declare predicted integer;chosen integer;
begin
 -- Only completed earlier rounds are read. The active human choice is never inspected.
 if r.campaign_stage is not null and random()<least(.85,r.campaign_stage*.12) then
  select choice into predicted from (select choice from chaos_private.moves where room_id=r.id and match_no=r.match_no and round_no<r.round_no and player=r.host order by round_no desc limit 5) history group by choice order by count(*) desc,random() limit 1;
  if predicted is not null then select n into chosen from generate_series(0,6) n where chaos_private.beats(n,predicted) order by random() limit 1;return chosen;end if;
 end if;
 return floor(random()*7)::integer;
end;$$;
revoke all on function chaos_private.bot_choice(public.chaos_rooms) from public,anon,authenticated;
do $$begin execute replace(pg_get_functiondef('chaos_private.chaos_action_v5(text,text,text,integer,integer,integer)'::regprocedure),'bot_move:=floor(random()*7)::integer;','bot_move:=chaos_private.bot_choice(r);');end;$$;

create or replace function chaos_private.reward_match() returns trigger language plpgsql security definer set search_path='' as $$
declare p uuid;inserted integer;coin_reward integer;xp_reward integer;
begin
 if new.phase='finished' and (old.phase is distinct from new.phase or old.match_no<>new.match_no) then
  for p in select id from(select new.host id union select new.guest id where not new.is_bot) players order by id loop
   if p is not null and exists(select 1 from chaos_private.moves where room_id=new.id and match_no=new.match_no and player=p) then
    insert into chaos_private.rewards values(new.id,new.match_no,p) on conflict do nothing;get diagnostics inserted=row_count;
    if inserted=1 then
     coin_reward:=case when new.match_winner=p then new.reward_coins else 0 end;
     xp_reward:=case when new.match_winner=p then new.reward_xp when new.match_winner is null then 60+coalesce(new.campaign_stage,0)*15 else 40+coalesce(new.campaign_stage,0)*10 end;
     update public.chaos_profiles set coins=coins+coin_reward,xp=xp+xp_reward,matches=matches+1,wins=wins+case when new.match_winner=p then 1 else 0 end,
      campaign_unlocked=case when new.campaign_stage is not null and new.match_winner=p then greatest(campaign_unlocked,new.campaign_stage+1) else campaign_unlocked end where id=p;
    end if;
   end if;
  end loop;
 end if;return new;
end;$$;
revoke all on function chaos_private.reward_match() from public,anon,authenticated;

alter function public.chaos_social(text,text,integer,text,uuid,text) rename to chaos_social_v6;
alter function public.chaos_social_v6(text,text,integer,text,uuid,text) set schema chaos_private;
revoke all on function chaos_private.chaos_social_v6(text,text,integer,text,uuid,text) from public,anon,authenticated;
create function public.chaos_social(action text,display_name text default null,avatar_id integer default null,friend_code text default null,target_id uuid default null,item_id text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();d jsonb;
begin d:=chaos_private.chaos_social_v6(action,display_name,avatar_id,friend_code,target_id,item_id);
 return d||jsonb_build_object('packs',coalesce((select jsonb_object_agg(tier::text,quantity) from chaos_private.packs where player=u),'{}'::jsonb));end;$$;
revoke all on function public.chaos_social(text,text,integer,text,uuid,text) from public,anon;
grant execute on function public.chaos_social(text,text,integer,text,uuid,text) to authenticated;

-- Card designs have their own equipment slot, never a gameplay modifier.
alter function public.chaos_style(text,jsonb,text) rename to chaos_style_v6;
alter function public.chaos_style_v6(text,jsonb,text) set schema chaos_private;
revoke all on function chaos_private.chaos_style_v6(text,jsonb,text) from public,anon,authenticated;
create function public.chaos_style(action text,appearance jsonb default null,item_id text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();s chaos_private.styles;
begin
 if action='equip' then
  if item_id='card:reset' then update public.chaos_profiles set card_skin='classic' where id=u;return public.chaos_social('state');end if;
  select * into s from chaos_private.styles where id=item_id;
  if s.slot='card' then
   if not exists(select 1 from chaos_private.inventory where player=u and item=item_id) then raise exception 'Diesen Style besitzt du nicht';end if;
   update public.chaos_profiles set card_skin=s.id where id=u;return public.chaos_social('state');
  end if;
 end if;
 return chaos_private.chaos_style_v6(action,appearance,item_id);
end;$$;
revoke all on function public.chaos_style(text,jsonb,text) from public,anon;
grant execute on function public.chaos_style(text,jsonb,text) to authenticated;

create function public.chaos_loot(action text,pack_tier integer,request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();p public.chaos_profiles;receipt chaos_private.loot_receipts;price integer;roll integer;draw_rarity integer;s chaos_private.styles;reward jsonb;amount integer;qty integer;
begin
 if request_id is null or pack_tier not between 0 and 2 or pack_tier is null then raise exception 'Pack ungültig';end if;
 select * into p from public.chaos_profiles where id=u for update;if p.id is null then raise exception 'Bitte zuerst dein Profil einrichten';end if;
 select * into receipt from chaos_private.loot_receipts where id=request_id;
 if receipt.id is not null then
  if receipt.player<>u or receipt.action<>action or receipt.tier<>pack_tier then raise exception 'Anfrage ungültig';end if;
  return public.chaos_social('state')||jsonb_build_object('loot',receipt.reward);
 end if;
 if action='buy' then
  price:=case pack_tier when 0 then 150 when 1 then 400 else 900 end;
  if p.coins<price then raise exception 'Nicht genügend Coins';end if;
  update public.chaos_profiles set coins=coins-price where id=u;
  insert into chaos_private.packs values(u,pack_tier,1) on conflict(player,tier) do update set quantity=chaos_private.packs.quantity+1;
  reward:=jsonb_build_object('kind','purchased','tier',pack_tier);
 elsif action='open' then
  select quantity into qty from chaos_private.packs where player=u and tier=pack_tier for update;
  if coalesce(qty,0)<1 then raise exception 'Kein Pack dieser Stufe vorhanden';end if;
  update chaos_private.packs set quantity=quantity-1 where player=u and tier=pack_tier;
  roll:=floor(random()*100)::integer;
  if roll<(case pack_tier when 0 then 20 when 1 then 10 else 5 end) then reward:=jsonb_build_object('kind','empty','tier',pack_tier);
  elsif roll<(case pack_tier when 0 then 55 when 1 then 40 else 30 end) then
   amount:=case pack_tier when 0 then 40+floor(random()*61)::integer when 1 then 100+floor(random()*151)::integer else 250+floor(random()*451)::integer end;
   update public.chaos_profiles set coins=coins+amount where id=u;reward:=jsonb_build_object('kind','coins','coins',amount,'tier',pack_tier);
  else
   draw_rarity:=case pack_tier when 0 then case when roll<90 then 1 when roll<98 then 2 else 3 end when 1 then case when roll<75 then 1 when roll<95 then 2 else 3 end else case when roll<55 then 1 when roll<85 then 2 else 3 end end;
   select * into s from chaos_private.styles where chaos_private.styles.rarity=draw_rarity order by random() limit 1;
   if exists(select 1 from chaos_private.inventory where player=u and item=s.id) then
    amount:=s.price/5;update public.chaos_profiles set coins=coins+amount where id=u;reward:=jsonb_build_object('kind','duplicate','item',s.id,'coins',amount,'tier',pack_tier);
   else insert into chaos_private.inventory values(u,s.id);reward:=jsonb_build_object('kind','item','item',s.id,'tier',pack_tier);end if;
  end if;
 else raise exception 'Ungültige Aktion';end if;
 insert into chaos_private.loot_receipts values(request_id,u,action,pack_tier,reward,clock_timestamp());
 return public.chaos_social('state')||jsonb_build_object('loot',reward);
end;$$;
revoke all on function public.chaos_loot(text,integer,uuid) from public,anon;
grant execute on function public.chaos_loot(text,integer,uuid) to authenticated;

alter function public.chaos_action(text,text,text,integer,integer,integer) rename to chaos_action_v6;
alter function public.chaos_action_v6(text,text,text,integer,integer,integer) set schema chaos_private;
revoke all on function chaos_private.chaos_action_v6(text,text,text,integer,integer,integer) from public,anon,authenticated;
create function public.chaos_action(action text,room_code text default null,player_name text default null,choice integer default null,expected_round integer default null,expected_match integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();d jsonb;r public.chaos_rooms;g public.chaos_profiles;
begin
 d:=chaos_private.chaos_action_v6(action,room_code,player_name,choice,expected_round,expected_match);
 if d->>'left'='true' or d->'room' is null then return d;end if;
 select * into r from public.chaos_rooms where id=(d->'room'->>'id')::uuid;
 if r.campaign_stage is not null and r.phase='finished' and d?'rewards' then
  d:=jsonb_set(d,'{rewards,xp}',to_jsonb(case when r.match_winner=u then r.reward_xp when r.match_winner is null then 60+r.campaign_stage*15 else 40+r.campaign_stage*10 end));
  d:=jsonb_set(d,'{rewards,coins}',to_jsonb(case when r.match_winner=u then r.reward_coins else 0 end));
 end if;
 d:=jsonb_set(d,'{players,host,card_skin}',to_jsonb((select card_skin from public.chaos_profiles where id=r.host)));
 select * into g from public.chaos_profiles where id=r.guest;
 if g.id is not null then d:=jsonb_set(d,'{players,guest,card_skin}',to_jsonb(g.card_skin));end if;
 return d;
end;$$;
revoke all on function public.chaos_action(text,text,text,integer,integer,integer) from public,anon;
grant execute on function public.chaos_action(text,text,text,integer,integer,integer) to authenticated;

create function public.chaos_campaign(stage integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();p public.chaos_profiles;d jsonb;r public.chaos_rooms;names text[]:=array['Milo','Nora','Kaito','Seraphine','Rook','Nyx','Astra','Veyr'];xps integer[]:=array[120,160,200,320,260,300,360,600];coins integer[]:=array[100,140,180,300,240,280,340,600];
begin
 select * into p from public.chaos_profiles where id=u for update;
 if p.id is null or stage is null or stage not between 0 and 7 or stage>p.campaign_unlocked then raise exception 'Dieses Kapitel ist noch gesperrt';end if;
 d:=public.chaos_action('bot');select * into r from public.chaos_rooms where id=(d->'room'->>'id')::uuid;
 update public.chaos_rooms set campaign_stage=stage,guest_name=names[stage+1],round_limit=case stage when 3 then 14 when 7 then 18 else 10 end,required_wins=case stage when 3 then 8 when 7 then 11 else 0 end,reward_xp=xps[stage+1],reward_coins=coins[stage+1] where id=r.id returning * into r;
 update chaos_private.moves set choice=chaos_private.bot_choice(r) where room_id=r.id and player=r.guest and match_no=r.match_no and round_no=r.round_no;
 return public.chaos_action('state',r.code);
end;$$;
revoke all on function public.chaos_campaign(integer) from public,anon;
grant execute on function public.chaos_campaign(integer) to authenticated;


-- 008_life_duels.sql

-- Existing live matches retain their rules; only newly created rooms use version 2.
alter table public.chaos_rooms add column rules_version integer not null default 1 check(rules_version in(1,2));
alter table public.chaos_rooms alter column rules_version set default 2;
alter table public.chaos_rooms add column host_hp integer not null default 5 check(host_hp>=0);
alter table public.chaos_rooms add column guest_hp integer not null default 5 check(guest_hp>=0);
alter table public.chaos_rooms add column host_max_hp integer not null default 5 check(host_max_hp>0);
alter table public.chaos_rooms add column guest_max_hp integer not null default 5 check(guest_max_hp>0);
alter table public.chaos_rooms add column host_confirmed boolean not null default false;
alter table public.chaos_rooms add column guest_confirmed boolean not null default false;
alter table public.chaos_rooms add column host_missed integer not null default 0;
alter table public.chaos_rooms add column guest_missed integer not null default 0;
alter table public.chaos_rooms add column end_reason text check(end_reason in('knockout','forfeit','inactivity','abandoned'));
create table chaos_private.sessions(
 player uuid primary key references public.chaos_profiles on delete cascade,
 room_id uuid references public.chaos_rooms on delete cascade
);
alter table chaos_private.sessions enable row level security;
revoke all on chaos_private.sessions from public,anon,authenticated;
create index chaos_rooms_participant_host on public.chaos_rooms(host,phase);
create index chaos_rooms_participant_guest on public.chaos_rooms(guest,phase) where not is_bot;

insert into chaos_private.sessions(player,room_id)
select distinct on(player) player,id from (select host as player,id,updated_at from public.chaos_rooms where phase<>'finished' union all select guest,id,updated_at from public.chaos_rooms where guest is not null and not is_bot and phase<>'finished') active order by player,updated_at desc;

-- Serialize assignment per player, rather than counting historical rooms.
create function chaos_private.claim_session(u uuid,requested uuid default null) returns void
language plpgsql set search_path='' as $$
declare existing public.chaos_rooms;existing_id uuid;seen timestamptz;
begin
 insert into chaos_private.sessions(player) values(u) on conflict do nothing;
 select room_id into existing_id from chaos_private.sessions where player=u for update;
 select * into existing from public.chaos_rooms where id=existing_id;
 if existing.id is not null and existing.id is distinct from requested and existing.phase<>'finished' then
  seen:=case when existing.host=u then existing.host_seen else existing.guest_seen end;
  if seen>clock_timestamp()-interval '90 seconds' then
   raise exception 'Du hast bereits einen laufenden Kampf. Kehre über „Kampf fortsetzen“ zurück.';
  end if;
  update public.chaos_rooms set phase='finished',
   end_reason=case when not existing.is_bot and existing.guest is not null and (case when u=existing.host then existing.guest_seen else existing.host_seen end)>clock_timestamp()-interval '90 seconds' then 'forfeit' else 'abandoned' end,
   match_winner=case when not existing.is_bot and existing.guest is not null and (case when u=existing.host then existing.guest_seen else existing.host_seen end)>clock_timestamp()-interval '90 seconds' then case when u=existing.host then existing.guest else existing.host end else null end,
   next_round_at=clock_timestamp(),updated_at=clock_timestamp() where id=existing.id;
 end if;
 update chaos_private.sessions set room_id=requested where player=u;
end;$$;

create function chaos_private.advance_lives(r public.chaos_rooms) returns public.chaos_rooms
language plpgsql set search_path='' as $$
declare a integer;b integer;resolution timestamptz;
begin
 if r.phase='select' and (clock_timestamp()>=r.select_until or (r.host_confirmed and r.guest_confirmed)) then
  resolution:=least(clock_timestamp(),r.select_until);
  select choice into a from chaos_private.moves where room_id=r.id and match_no=r.match_no and round_no=r.round_no and player=r.host;
  select choice into b from chaos_private.moves where room_id=r.id and match_no=r.match_no and round_no=r.round_no and player=r.guest;
  r.host_missed:=case when a is null then r.host_missed+1 else 0 end;
  r.guest_missed:=case when b is null then r.guest_missed+1 else 0 end;
  -- Missing selections get a server-random power for either side. These automatic
  -- choices are not written to moves and therefore cannot mint participation XP.
  a:=coalesce(a,floor(random()*7)::integer);b:=coalesce(b,floor(random()*7)::integer);
  r.host_choice:=a;r.guest_choice:=b;r.winner:=null;
  if a<>b then
   r.winner:=case when chaos_private.beats(a,b) then r.host else r.guest end;
   if r.winner=r.host then r.guest_hp:=greatest(0,r.guest_hp-1);r.host_score:=r.host_score+1;
   else r.host_hp:=greatest(0,r.host_hp-1);r.guest_score:=r.guest_score+1;end if;
  end if;
  r.reveal_at:=resolution;r.next_round_at:=resolution+interval '6 seconds';r.phase:='result';
  if r.host_hp=0 or r.guest_hp=0 then
   r.phase:='finished';r.end_reason:='knockout';r.match_winner:=case when r.guest_hp=0 then r.host else r.guest end;
  elsif r.host_missed>=3 or r.guest_missed>=3 then
   r.phase:='finished';r.end_reason:='inactivity';
   r.match_winner:=case when r.host_missed>=3 and r.guest_missed>=3 then null when r.host_missed>=3 then r.guest else r.host end;
  end if;
 end if;
 if r.phase='result' and clock_timestamp()>=r.next_round_at then
  r.round_no:=r.round_no+1;r.phase:='select';r.select_until:=clock_timestamp()+interval '10 seconds';
  r.next_round_at:=null;r.host_choice:=null;r.guest_choice:=null;r.winner:=null;r.reveal_at:=null;
  r.host_locked:=false;r.guest_locked:=r.is_bot;r.host_confirmed:=false;r.guest_confirmed:=r.is_bot;
  if r.is_bot then
   insert into chaos_private.moves values(r.id,r.match_no,r.round_no,r.guest,chaos_private.bot_choice(r)) on conflict do nothing;
  end if;
 end if;
 return r;
end;$$;

create function chaos_private.life_snapshot(r public.chaos_rooms,u uuid) returns jsonb
language plpgsql set search_path='' as $$
declare mine integer;d jsonb;h public.chaos_profiles;g public.chaos_profiles;p public.chaos_profiles;
begin
 if u<>r.host and u is distinct from r.guest then raise exception 'Kein Zugriff auf diesen Raum';end if;
 select * into h from public.chaos_profiles where id=r.host;select * into g from public.chaos_profiles where id=r.guest;
 select * into p from public.chaos_profiles where id=u;
 select choice into mine from chaos_private.moves where room_id=r.id and match_no=r.match_no and round_no=r.round_no and player=u;
 d:=jsonb_build_object('room',to_jsonb(r),'my_choice',mine,'server_now',clock_timestamp(),
  'wallet',jsonb_build_object('coins',p.coins,'xp',p.xp),
  'players',jsonb_build_object('host',jsonb_build_object('appearance',h.appearance,'frame',h.frame,'xp',h.xp,'card_skin',h.card_skin),
   'guest',jsonb_build_object('appearance',g.appearance,'frame',g.frame,'xp',g.xp,'card_skin',g.card_skin)));
 if exists(select 1 from chaos_private.rewards where room_id=r.id and match_no=r.match_no and player=u) then
  d:=d||jsonb_build_object('rewards',jsonb_build_object('xp',case when r.match_winner=u then r.reward_xp when r.match_winner is null then 60+coalesce(r.campaign_stage,0)*15 else 40+coalesce(r.campaign_stage,0)*10 end,
   'coins',case when r.match_winner=u then r.reward_coins else 0 end,'total_xp',p.xp));
 end if;return d;
end;$$;

-- Reward policy is unchanged, except abandoned sessions cannot award anything.
do $$declare definition text;begin
 definition:=pg_get_functiondef('chaos_private.reward_match()'::regprocedure);
 definition:=replace(definition,'if new.phase=''finished'' and (','if new.phase=''finished'' and new.end_reason is distinct from ''abandoned'' and (');
 execute definition;
end;$$;

alter function public.chaos_action(text,text,text,integer,integer,integer) rename to chaos_action_v7;
alter function public.chaos_action_v7(text,text,text,integer,integer,integer) set schema chaos_private;
revoke all on function chaos_private.chaos_action_v7(text,text,text,integer,integer,integer) from public,anon,authenticated;
create function public.chaos_action(action text,room_code text default null,player_name text default null,choice integer default null,expected_round integer default null,expected_match integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();r public.chaos_rooms;prior public.chaos_rooms;p public.chaos_profiles;
 lim chaos_private.limits;candidate text;i integer;j integer;mine integer;action_error text;
 alphabet text:='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
 select * into p from public.chaos_profiles where id=u;
 if p.id is null then raise exception 'Bitte zuerst dein Profil einrichten';end if;
 if action='resume' then
  select x.* into r from public.chaos_rooms x join chaos_private.sessions s on s.room_id=x.id where s.player=u and x.phase<>'finished';
  if r.id is null then return jsonb_build_object('room',null);end if;
  return public.chaos_action('ping',r.code);
 end if;
 if action in('create','bot','join') then
  insert into chaos_private.limits(player) values(u) on conflict do nothing;
  select * into lim from chaos_private.limits where player=u for update;
 end if;
 if action in('create','bot') then
  perform chaos_private.claim_session(u);
  if lim.created>clock_timestamp()-interval '10 seconds' then raise exception 'Bitte kurz warten';end if;
  for i in 1..20 loop
   candidate:='';for j in 1..6 loop candidate:=candidate||substr(alphabet,1+floor(random()*length(alphabet))::integer,1);end loop;
   begin
    insert into public.chaos_rooms(code,host,host_name) values(candidate,u,p.name) returning * into r;exit;
   exception when unique_violation then null;end;
  end loop;
  if r.id is null then raise exception 'Raum konnte nicht erstellt werden';end if;
  update chaos_private.sessions set room_id=r.id where player=u;
  update chaos_private.limits set created=clock_timestamp() where player=u;
  if action='bot' then
   update public.chaos_rooms set is_bot=true,guest=gen_random_uuid(),guest_name='Chaos-Bot',guest_seen=clock_timestamp(),
    phase='select',select_until=clock_timestamp()+interval '10 seconds',guest_locked=true,guest_confirmed=true,updated_at=clock_timestamp() where id=r.id returning * into r;
   insert into chaos_private.moves values(r.id,r.match_no,r.round_no,r.guest,chaos_private.bot_choice(r));
  end if;
 else
  -- Joiners lock their assignment before the target room, preventing two tabs
  -- from putting the same player into different active matches.
  if action='join' then
   if lim.joined is null or lim.joined<clock_timestamp()-interval '1 minute' then
    update chaos_private.limits set joined=clock_timestamp(),join_count=1 where player=u;
   elsif lim.join_count>=15 then return jsonb_build_object('error','Zu viele Versuche. Bitte eine Minute warten.');
   else update chaos_private.limits set join_count=join_count+1 where player=u;end if;
   select * into r from public.chaos_rooms where code=upper(trim(room_code));
   if r.id is null or r.updated_at<clock_timestamp()-interval '24 hours' then return jsonb_build_object('error','Raum nicht gefunden oder abgelaufen');end if;
   perform chaos_private.claim_session(u,r.id);
  end if;
  select * into r from public.chaos_rooms where code=upper(trim(room_code)) for update;
  if r.id is null or r.updated_at<clock_timestamp()-interval '24 hours' then raise exception 'Raum nicht gefunden oder abgelaufen';end if;
  if r.rules_version=1 then return chaos_private.chaos_action_v7(action,room_code,player_name,choice,expected_round,expected_match);end if;
  prior:=r;
  if action='join' then
   if r.is_bot and r.host<>u then raise exception 'Dies ist ein Duell gegen den Bot';end if;
   if r.reserved_guest is not null and r.reserved_guest<>u and r.host<>u then raise exception 'Dieser Raum ist für einen herausgeforderten Freund reserviert';end if;
   if u=r.host or u=r.guest then null;
   elsif r.guest is not null or r.phase<>'lobby' then raise exception 'Raum ist bereits voll';
   else r.guest:=u;r.guest_name:=p.name;r.guest_seen:=clock_timestamp();end if;
  elsif u<>r.host and u is distinct from r.guest then raise exception 'Kein Zugriff auf diesen Raum';end if;
  r:=chaos_private.advance_lives(r);
  if action in('choose','confirm','ready') and (expected_round is distinct from r.round_no or expected_match is distinct from r.match_no) then
   action_error:='Runde hat sich geändert. Bitte aktualisieren';
  elsif action='start' then
   if u<>r.host then raise exception 'Nur der Gastgeber kann starten';end if;
   if r.phase<>'lobby' or r.guest is null or r.guest_seen<clock_timestamp()-interval '45 seconds' then raise exception 'Beide Spieler müssen verbunden sein';end if;
   r.phase:='select';r.select_until:=clock_timestamp()+interval '10 seconds';
  elsif action='choose' then
   if r.phase<>'select' then action_error:='Auswahlzeit abgelaufen';
   elsif choice is null or choice not between 0 and 6 then action_error:='Ungültiger Spielzug';
   elsif (u=r.host and r.host_confirmed) or (u=r.guest and r.guest_confirmed) then action_error:='Deine Auswahl ist bereits bestätigt';
   else
    insert into chaos_private.moves values(r.id,r.match_no,r.round_no,u,choice)
     on conflict(room_id,match_no,round_no,player) do update set choice=excluded.choice;
    if u=r.host then r.host_locked:=true;else r.guest_locked:=true;end if;
   end if;
  elsif action='confirm' then
   if r.phase<>'select' then action_error:='Auswahlzeit abgelaufen';
   elsif not exists(select 1 from chaos_private.moves where room_id=r.id and match_no=r.match_no and round_no=r.round_no and player=u) then action_error:='Wähle zuerst eine Macht';
   else
    if u=r.host then r.host_confirmed:=true;else r.guest_confirmed:=true;end if;
    r:=chaos_private.advance_lives(r);
   end if;
  elsif action='ready' then
   if r.phase<>'finished' then action_error:='Ein Rematch ist erst nach Matchende möglich';
   elsif clock_timestamp()<r.next_round_at then action_error:='Kampf läuft noch';
   else
    perform chaos_private.claim_session(u,r.id);
    if u=r.host then r.host_ready:=true;else r.guest_ready:=true;end if;
    if r.is_bot then r.guest_ready:=true;end if;
    if r.host_ready and r.guest_ready then
     -- Both real players must still be available for the same room.
     if not r.is_bot then perform chaos_private.claim_session(case when u=r.host then r.guest else r.host end,r.id);end if;
     r.match_no:=r.match_no+1;r.round_no:=1;r.host_score:=0;r.guest_score:=0;r.match_winner:=null;r.end_reason:=null;
     r.host_hp:=r.host_max_hp;r.guest_hp:=r.guest_max_hp;r.host_missed:=0;r.guest_missed:=0;
     r.phase:='select';r.select_until:=clock_timestamp()+interval '10 seconds';r.next_round_at:=null;
     r.host_ready:=false;r.guest_ready:=false;r.host_locked:=false;r.guest_locked:=r.is_bot;
     r.host_confirmed:=false;r.guest_confirmed:=r.is_bot;r.host_choice:=null;r.guest_choice:=null;r.winner:=null;r.reveal_at:=null;
     if r.is_bot then insert into chaos_private.moves values(r.id,r.match_no,r.round_no,r.guest,chaos_private.bot_choice(r));end if;
    end if;
   end if;
  elsif action='leave' then
   if r.phase='lobby' and u=r.guest then r.guest:=null;r.guest_name:=null;r.guest_seen:=null;
   elsif r.phase<>'finished' then
    r.phase:='finished';r.end_reason:=case when r.is_bot or r.guest is null then 'abandoned' else 'forfeit' end;
    r.match_winner:=case when r.end_reason='abandoned' then null when u=r.host then r.guest else r.host end;
    r.next_round_at:=clock_timestamp();r.reveal_at:=clock_timestamp();
   end if;
   update chaos_private.sessions set room_id=null where player=u and room_id=r.id;
  elsif action not in('join','state','ping') then raise exception 'Ungültige Aktion';end if;
  if action not in('state','leave') then
   if u=r.host then r.host_seen:=clock_timestamp();else r.guest_seen:=clock_timestamp();end if;
  end if;
  if action<>'state' or r is distinct from prior then
   r.updated_at:=clock_timestamp();
   update public.chaos_rooms set guest=r.guest,guest_name=r.guest_name,guest_seen=r.guest_seen,host_seen=r.host_seen,
    phase=r.phase,match_no=r.match_no,round_no=r.round_no,host_score=r.host_score,guest_score=r.guest_score,
    host_locked=r.host_locked,guest_locked=r.guest_locked,host_ready=r.host_ready,guest_ready=r.guest_ready,
    host_choice=r.host_choice,guest_choice=r.guest_choice,winner=r.winner,reveal_at=r.reveal_at,
    select_until=r.select_until,next_round_at=r.next_round_at,match_winner=r.match_winner,updated_at=r.updated_at,
    host_hp=r.host_hp,guest_hp=r.guest_hp,host_confirmed=r.host_confirmed,guest_confirmed=r.guest_confirmed,
    host_missed=r.host_missed,guest_missed=r.guest_missed,end_reason=r.end_reason where id=r.id;
  end if;
  if action='leave' then return jsonb_build_object('left',true);end if;
 end if;
 return chaos_private.life_snapshot(r,u)||jsonb_build_object('error',action_error);
end;$$;
revoke all on function public.chaos_action(text,text,text,integer,integer,integer) from public,anon;
grant execute on function public.chaos_action(text,text,text,integer,integer,integer) to authenticated;

alter function public.chaos_campaign(integer) rename to chaos_campaign_v7;
alter function public.chaos_campaign_v7(integer) set schema chaos_private;
revoke all on function chaos_private.chaos_campaign_v7(integer) from public,anon,authenticated;
create function public.chaos_campaign(stage integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare d jsonb;r public.chaos_rooms;u uuid:=chaos_private.account_uid();hp integer;
begin
 d:=chaos_private.chaos_campaign_v7(stage);
 hp:=case stage when 3 then 8 when 7 then 11 else 5 end;
 update public.chaos_rooms set guest_hp=hp,guest_max_hp=hp where id=(d->'room'->>'id')::uuid returning * into r;
 return public.chaos_action('state',r.code);
end;$$;
revoke all on function public.chaos_campaign(integer) from public,anon;
grant execute on function public.chaos_campaign(integer) to authenticated;
revoke all on all functions in schema chaos_private from public,anon,authenticated;


-- 009_endless_arena.sql

alter table chaos_private.rewards add column xp integer check(xp>=0);
alter table chaos_private.rewards add column coins integer check(coins>=0);
alter table public.chaos_profiles add column endless_best integer not null default 0 check(endless_best>=0);
alter table public.chaos_rooms add column game_mode text not null default 'duel' check(game_mode in('duel','endless'));
alter table public.chaos_rooms add column endless_wave integer not null default 1 check(endless_wave>0);
alter table public.chaos_rooms drop constraint chaos_rooms_host_score_check;
alter table public.chaos_rooms drop constraint chaos_rooms_guest_score_check;
alter table public.chaos_rooms add check(host_score>=0);
alter table public.chaos_rooms add check(guest_score>=0);
create table chaos_private.endless_runs(
 id uuid primary key default gen_random_uuid(),
 player uuid not null references public.chaos_profiles on delete cascade,
 room_id uuid unique references public.chaos_rooms on delete set null,
 current_wave integer not null default 1 check(current_wave>0),
 defeated integer not null default 0 check(defeated>=0),
 coins integer not null default 0 check(coins>=0),xp integer not null default 0 check(xp>=0),
 final_hp integer not null default 10 check(final_hp between 0 and 10),
 previous_best integer not null default 0,active boolean not null default true,
 created_at timestamptz not null default clock_timestamp(),finished_at timestamptz
);
alter table chaos_private.endless_runs enable row level security;
revoke all on chaos_private.endless_runs from public,anon,authenticated;
create unique index endless_one_active_run on chaos_private.endless_runs(player) where active;
create index endless_history on chaos_private.endless_runs(player,created_at desc);
create function chaos_private.endless_coins(wave integer) returns integer language sql immutable set search_path='' as $$select least(125,20+least(wave,21)*5);$$;
create function chaos_private.endless_xp(wave integer) returns integer language sql immutable set search_path='' as $$select least(120,15+least(wave,27)*4);$$;
create function chaos_private.endless_name(wave integer) returns text language sql immutable set search_path='' as $$
 select (array['Funkenwächter','Nebelhexe','Kristallklinge','Sonnenritter','Schattenvogt','Astraljägerin','Sternenwache','Chaosfürst'])[1+(wave-1)%8]||' · '||wave::text;
$$;

-- An inter-wave victory is still part of the same active run.
do $$declare definition text;begin
 definition:=pg_get_functiondef('chaos_private.claim_session(uuid,uuid)'::regprocedure);
 definition:=replace(definition,'existing.phase<>''finished''','(existing.phase<>''finished'' or (existing.game_mode=''endless'' and existing.match_winner=existing.host and existing.end_reason=''knockout''))');
 definition:=replace(definition,'next_round_at=clock_timestamp(),updated_at=clock_timestamp() where id=existing.id;',
 'next_round_at=clock_timestamp(),updated_at=clock_timestamp() where id=existing.id;
  update chaos_private.endless_runs set active=false,finished_at=clock_timestamp() where room_id=existing.id and active;');
 execute definition;
 definition:=pg_get_functiondef('chaos_private.bot_choice(public.chaos_rooms)'::regprocedure);
 definition:=replace(definition,'if r.campaign_stage is not null and random()<least(.85,r.campaign_stage*.12) then',
 'if (r.campaign_stage is not null or r.game_mode=''endless'') and random()<(case when r.game_mode=''endless'' then least(.75,(r.endless_wave-1)*.08) else least(.85,r.campaign_stage*.12) end) then');
 execute definition;
end;$$;

create or replace function chaos_private.reward_match() returns trigger language plpgsql security definer set search_path='' as $$
declare p uuid;inserted integer;coin_reward integer;xp_reward integer;
begin
 if new.phase='finished' and (old.phase is distinct from new.phase or old.match_no<>new.match_no) then
  if new.game_mode='endless' then
   if new.match_winner=new.host and new.end_reason='knockout' then
    coin_reward:=0;xp_reward:=0;
    if exists(select 1 from chaos_private.moves where room_id=new.id and match_no=new.match_no and player=new.host) then coin_reward:=chaos_private.endless_coins(new.endless_wave);xp_reward:=chaos_private.endless_xp(new.endless_wave);end if;
    insert into chaos_private.rewards(room_id,match_no,player,xp,coins) values(new.id,new.match_no,new.host,xp_reward,coin_reward) on conflict do nothing;get diagnostics inserted=row_count;
    if inserted=1 then
     update public.chaos_profiles set coins=coins+coin_reward,xp=xp+xp_reward,endless_best=case when exists(select 1 from chaos_private.moves where room_id=new.id and player=new.host) then greatest(endless_best,new.endless_wave) else endless_best end where id=new.host;
     update chaos_private.endless_runs set defeated=defeated+1,coins=coins+coin_reward,xp=xp+xp_reward,final_hp=new.host_hp where room_id=new.id and active;
    end if;
   else
    update chaos_private.endless_runs set active=false,finished_at=clock_timestamp(),final_hp=new.host_hp where room_id=new.id and active;
    if exists(select 1 from chaos_private.moves where room_id=new.id and player=new.host) then
     xp_reward:=case when new.end_reason='knockout' and new.host_hp=0 then 10 else 0 end;
     update public.chaos_profiles set xp=xp+xp_reward,matches=matches+1,endless_best=greatest(endless_best,new.endless_wave) where id=new.host;
     update chaos_private.endless_runs set xp=xp+xp_reward where room_id=new.id;
    end if;
   end if;
   return new;
  end if;
  if new.end_reason is distinct from 'abandoned' then
   for p in select id from(select new.host id union select new.guest id where not new.is_bot) players order by id loop
    if p is not null and exists(select 1 from chaos_private.moves where room_id=new.id and match_no=new.match_no and player=p) then
     insert into chaos_private.rewards values(new.id,new.match_no,p) on conflict do nothing;get diagnostics inserted=row_count;
     if inserted=1 then
      coin_reward:=case when new.match_winner=p then new.reward_coins else 0 end;
      xp_reward:=case when new.match_winner=p then new.reward_xp when new.match_winner is null then 60+coalesce(new.campaign_stage,0)*15 else 40+coalesce(new.campaign_stage,0)*10 end;
      update public.chaos_profiles set coins=coins+coin_reward,xp=xp+xp_reward,matches=matches+1,wins=wins+case when new.match_winner=p then 1 else 0 end,
       campaign_unlocked=case when new.campaign_stage is not null and new.match_winner=p then greatest(campaign_unlocked,new.campaign_stage+1) else campaign_unlocked end where id=p;
     end if;
    end if;
   end loop;
  end if;
 end if;return new;
end;$$;

alter function chaos_private.advance_lives(public.chaos_rooms) rename to advance_lives_v8;
create function chaos_private.advance_lives(r public.chaos_rooms) returns public.chaos_rooms language plpgsql set search_path='' as $$
begin
 r:=chaos_private.advance_lives_v8(r);
 if r.game_mode='endless' and r.phase='finished' and r.match_winner=r.host and r.host_missed>=3 then
  r.match_winner:=r.guest;r.end_reason:='inactivity';
 end if;
 if r.game_mode='endless' and r.phase='finished' and r.match_winner=r.host and r.end_reason='knockout' and clock_timestamp()>=r.next_round_at then
  r.endless_wave:=r.endless_wave+1;r.match_no:=r.match_no+1;r.round_no:=1;r.host_score:=0;r.guest_score:=0;
  r.guest_hp:=r.endless_wave;r.guest_max_hp:=r.endless_wave;r.guest_name:=chaos_private.endless_name(r.endless_wave);
  r.reward_coins:=chaos_private.endless_coins(r.endless_wave);r.reward_xp:=chaos_private.endless_xp(r.endless_wave);
  r.phase:='select';r.select_until:=clock_timestamp()+interval '10 seconds';r.next_round_at:=null;r.end_reason:=null;r.match_winner:=null;
  r.host_choice:=null;r.guest_choice:=null;r.winner:=null;r.reveal_at:=null;r.host_locked:=false;r.guest_locked:=true;
  r.host_confirmed:=false;r.guest_confirmed:=true;r.host_ready:=false;r.guest_ready:=false;r.guest_missed:=0;
  insert into chaos_private.moves values(r.id,r.match_no,r.round_no,r.guest,chaos_private.bot_choice(r));
  update chaos_private.endless_runs set current_wave=r.endless_wave,final_hp=r.host_hp where room_id=r.id and active;
  update public.chaos_profiles set endless_best=greatest(endless_best,r.endless_wave) where id=r.host and exists(select 1 from chaos_private.moves where room_id=r.id and player=r.host);
 end if;
 return r;
end;$$;

alter function chaos_private.life_snapshot(public.chaos_rooms,uuid) rename to life_snapshot_v8;
create function chaos_private.life_snapshot(r public.chaos_rooms,u uuid) returns jsonb language plpgsql set search_path='' as $$
declare d jsonb;run chaos_private.endless_runs;actual_xp integer;actual_coins integer;
begin
 d:=chaos_private.life_snapshot_v8(r,u);
 select xp,coins into actual_xp,actual_coins from chaos_private.rewards where room_id=r.id and match_no=r.match_no and player=u;
 if actual_xp is not null then d:=d||jsonb_build_object('rewards',jsonb_build_object('xp',actual_xp,'coins',actual_coins,'total_xp',(select xp from public.chaos_profiles where id=u)));end if;
 if r.game_mode='endless' then
  select * into run from chaos_private.endless_runs where room_id=r.id and player=u;
  d:=d||jsonb_build_object('endless',jsonb_build_object('id',run.id,'wave',r.endless_wave,'defeated',run.defeated,'coins',run.coins,'xp',run.xp,'hp',r.host_hp,
   'best',(select endless_best from public.chaos_profiles where id=u),'new_record',(select endless_best>run.previous_best from public.chaos_profiles where id=u),'active',run.active));
 end if;return d;
end;$$;

-- Persist wave configuration when the shared state machine advances.
do $$declare definition text;begin
 definition:=pg_get_functiondef('public.chaos_action(text,text,text,integer,integer,integer)'::regprocedure);
 definition:=replace(definition,'host_missed=r.host_missed,guest_missed=r.guest_missed,end_reason=r.end_reason where id=r.id;',
 'host_missed=r.host_missed,guest_missed=r.guest_missed,end_reason=r.end_reason,endless_wave=r.endless_wave,guest_max_hp=r.guest_max_hp,reward_xp=r.reward_xp,reward_coins=r.reward_coins where id=r.id;');
 definition:=replace(definition,'and x.phase<>''finished'';',
 'and (x.phase<>''finished'' or (x.game_mode=''endless'' and x.match_winner=x.host and x.end_reason=''knockout''));');
 execute definition;
end;$$;
alter function public.chaos_action(text,text,text,integer,integer,integer) rename to chaos_action_v8;
alter function public.chaos_action_v8(text,text,text,integer,integer,integer) set schema chaos_private;

create function public.chaos_endless(action text default 'state') returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();p public.chaos_profiles;run chaos_private.endless_runs;r public.chaos_rooms;d jsonb;
begin
 select * into p from public.chaos_profiles where id=u;
 if p.id is null then raise exception 'Bitte zuerst dein Profil einrichten';end if;
 if action='start' then
  -- Session assignment serializes starts; another tab cannot reset surviving HP.
  select * into run from chaos_private.endless_runs where player=u and active;
  if run.id is not null then
   select * into r from public.chaos_rooms where id=run.room_id;
   if r.id is not null and r.updated_at>clock_timestamp()-interval '24 hours' then return public.chaos_action('ping',r.code);end if;
   update chaos_private.endless_runs set active=false,finished_at=clock_timestamp() where id=run.id;
  end if;
  d:=public.chaos_action('bot');select * into r from public.chaos_rooms where id=(d->'room'->>'id')::uuid;
  insert into chaos_private.endless_runs(player,room_id,previous_best) values(u,r.id,p.endless_best);
  update public.chaos_rooms set game_mode='endless',host_hp=10,host_max_hp=10,guest_hp=1,guest_max_hp=1,
   guest_name=chaos_private.endless_name(1),reward_coins=chaos_private.endless_coins(1),reward_xp=chaos_private.endless_xp(1) where id=r.id returning * into r;
  return public.chaos_action('state',r.code);
 elsif action<>'state' then raise exception 'Ungültige Aktion';end if;
 return jsonb_build_object('best',p.endless_best,
  'active',coalesce((select jsonb_build_object('code',x.code,'wave',x.endless_wave) from chaos_private.endless_runs er join public.chaos_rooms x on x.id=er.room_id where er.player=u and er.active),'null'::jsonb),
  'history',coalesce((select jsonb_agg(to_jsonb(history)) from (select current_wave as wave,defeated,coins,xp,final_hp,created_at,finished_at from chaos_private.endless_runs where player=u and not active order by created_at desc limit 10) history),'[]'::jsonb),
  'leaderboard',coalesce((select jsonb_agg(to_jsonb(ranked)) from (select id,name,appearance,frame,xp,endless_best as wave from public.chaos_profiles where endless_best>0 order by endless_best desc,name,id limit 50) ranked),'[]'::jsonb));
end;$$;

create function public.chaos_action(action text,room_code text default null,player_name text default null,choice integer default null,expected_round integer default null,expected_match integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();r public.chaos_rooms;
begin
 if action in('ready','leave') then
  select * into r from public.chaos_rooms where code=upper(trim(room_code)) for update;
  if r.game_mode='endless' then
   if u<>r.host then raise exception 'Kein Zugriff auf diesen Lauf';end if;
   if action='ready' then
    if r.phase<>'finished' then raise exception 'Der Lauf läuft noch';end if;
    if r.match_winner=r.host and r.end_reason='knockout' then return chaos_private.chaos_action_v8('state',r.code);end if;
    return public.chaos_endless('start');
   end if;
   -- Leaving an inter-wave victory closes the run without undoing earned drops.
   if r.phase='finished' and r.match_winner=r.host then
    update public.chaos_rooms set match_winner=null,end_reason='abandoned',updated_at=clock_timestamp() where id=r.id;
    update chaos_private.endless_runs set active=false,finished_at=clock_timestamp() where room_id=r.id and active;
   end if;
  end if;
 end if;
 return chaos_private.chaos_action_v8(action,room_code,player_name,choice,expected_round,expected_match);
end;$$;
revoke all on function public.chaos_action(text,text,text,integer,integer,integer),public.chaos_endless(text) from public,anon;
grant execute on function public.chaos_action(text,text,text,integer,integer,integer),public.chaos_endless(text) to authenticated;
revoke all on all functions in schema chaos_private from public,anon,authenticated;


-- 010_ranked_queue.sql

alter table public.chaos_profiles add column rating integer not null default 1000 check(rating>=0);
alter table public.chaos_profiles add column ranked_matches integer not null default 0;
alter table public.chaos_profiles add column ranked_wins integer not null default 0;
alter table public.chaos_rooms drop constraint chaos_rooms_game_mode_check;
alter table public.chaos_rooms add check(game_mode in('duel','endless','ranked'));
alter table public.chaos_rooms add column battle_starts_at timestamptz;
create table chaos_private.match_queue(
 player uuid primary key references public.chaos_profiles on delete cascade,
 rating integer not null,joined_at timestamptz not null default clock_timestamp(),
 heartbeat timestamptz not null default clock_timestamp(),room_id uuid references public.chaos_rooms on delete set null
);
create table chaos_private.rating_results(
 room_id uuid not null,match_no integer not null,host uuid not null,guest uuid not null,
 host_before integer not null,guest_before integer not null,host_after integer not null,guest_after integer not null,
 winner uuid,finished_at timestamptz not null default clock_timestamp(),primary key(room_id,match_no)
);
alter table chaos_private.match_queue enable row level security;
alter table chaos_private.rating_results enable row level security;
revoke all on chaos_private.match_queue,chaos_private.rating_results from public,anon,authenticated;
create index match_queue_waiting on chaos_private.match_queue(joined_at) where room_id is null;
create index ranked_results_host on chaos_private.rating_results(host,finished_at desc);
create index ranked_results_guest on chaos_private.rating_results(guest,finished_at desc);
create function chaos_private.rank_name(mmr integer) returns text language sql immutable set search_path='' as $$
 select case when mmr<1000 then 'Bronze' when mmr<1200 then 'Silber' when mmr<1400 then 'Gold' when mmr<1600 then 'Platin' when mmr<1800 then 'Diamant' when mmr<2000 then 'Meister' when mmr<2200 then 'Legende' else 'Chaos-Gott' end;
$$;
create function chaos_private.update_rating() returns trigger language plpgsql security definer set search_path='' as $$
declare h integer;g integer;delta integer;s numeric;
begin
 if new.game_mode<>'ranked' or new.phase<>'finished' or (old.phase='finished' and old.match_no=new.match_no) or new.end_reason='abandoned' then return new;end if;
 -- A match with no deliberate input has no rating or leaderboard significance.
 if not exists(select 1 from chaos_private.moves where room_id=new.id and match_no=new.match_no) then return new;end if;
 perform id from public.chaos_profiles where id in(new.host,new.guest) order by id for update;
 select rating into h from public.chaos_profiles where id=new.host;
 select rating into g from public.chaos_profiles where id=new.guest;
 s:=case when new.match_winner=new.host then 1 when new.match_winner=new.guest then 0 else .5 end;
 delta:=round(32*(s-1/(1+power(10::numeric,(g-h)/400::numeric))))::integer;
 insert into chaos_private.rating_results(room_id,match_no,host,guest,host_before,guest_before,host_after,guest_after,winner)
 values(new.id,new.match_no,new.host,new.guest,h,g,greatest(0,h+delta),greatest(0,g-delta),new.match_winner) on conflict do nothing;
 if found then
  update public.chaos_profiles set rating=greatest(0,rating+case when id=new.host then delta else -delta end),ranked_matches=ranked_matches+1,ranked_wins=ranked_wins+case when id=new.match_winner then 1 else 0 end where id in(new.host,new.guest);
 end if;return new;
end;$$;
create trigger ranked_match_rating after update on public.chaos_rooms for each row execute function chaos_private.update_rating();

-- Joining another mode cancels a waiting ticket. An assigned ranked room stays in sessions.
alter function chaos_private.claim_session(uuid,uuid) rename to claim_session_v9;
create function chaos_private.claim_session(u uuid,requested uuid default null) returns void language plpgsql set search_path='' as $$
begin perform chaos_private.claim_session_v9(u,requested);delete from chaos_private.match_queue where player=u and room_id is null;end;$$;

create function public.chaos_matchmaking(action text default 'poll') returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();mine chaos_private.match_queue;peer chaos_private.match_queue;
 r public.chaos_rooms;p public.chaos_profiles;q public.chaos_profiles;candidate text;waited integer;spread integer;i integer;j integer;
 alphabet text:='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
 if action not in('join','poll','cancel') then raise exception 'Ungültige Suchaktion';end if;
 -- A short global transaction lock makes matching/cancellation/assignment indivisible.
 perform pg_advisory_xact_lock(6014010);
 select * into p from public.chaos_profiles where id=u;if p.id is null then raise exception 'Bitte zuerst dein Profil einrichten';end if;
 select * into mine from chaos_private.match_queue where player=u;
 if mine.room_id is not null then
  select * into r from public.chaos_rooms where id=mine.room_id;
  if r.phase<>'finished' then return jsonb_build_object('status','matched','code',r.code,'starts_at',r.battle_starts_at);end if;
  delete from chaos_private.match_queue where player=u;mine:=null;
 end if;
 if action='cancel' then delete from chaos_private.match_queue where player=u;return jsonb_build_object('status','idle');end if;
 delete from chaos_private.match_queue where room_id is null and heartbeat<clock_timestamp()-interval '30 seconds';
 select * into mine from chaos_private.match_queue where player=u;
 if mine.player is null then
  if action='poll' then return jsonb_build_object('status','idle');end if;
  perform chaos_private.claim_session(u);
  insert into chaos_private.match_queue(player,rating) values(u,p.rating) returning * into mine;
 end if;
 update chaos_private.match_queue set heartbeat=clock_timestamp() where player=u;
 waited:=greatest(0,extract(epoch from(clock_timestamp()-mine.joined_at))::integer);
 spread:=least(2000,100+(waited/15)*100);
 select x.* into peer from chaos_private.match_queue x join public.chaos_profiles cp on cp.id=x.player where x.player<>u and x.room_id is null and x.heartbeat>clock_timestamp()-interval '30 seconds'
  and abs(x.rating-mine.rating)<=greatest(spread,least(2000,100+(extract(epoch from(clock_timestamp()-x.joined_at))::integer/15)*100))
  and abs(cp.xp/250-p.xp/250)<=3+greatest(waited,extract(epoch from(clock_timestamp()-x.joined_at))::integer)/30
  order by x.joined_at,abs(cp.xp/250-p.xp/250),x.player limit 1;
 if peer.player is null then return jsonb_build_object('status','waiting','joined_at',mine.joined_at,'range',spread,'rating',p.rating,'rank',chaos_private.rank_name(p.rating));end if;
 -- Reserve both real accounts before creating a room; stale tickets cannot steal an active player.
 insert into chaos_private.sessions(player) values(u),(peer.player) on conflict do nothing;
 perform player from chaos_private.sessions where player in(u,peer.player) order by player for update;
 if exists(select 1 from chaos_private.sessions s join public.chaos_rooms x on x.id=s.room_id where s.player in(u,peer.player) and x.phase<>'finished') then
  delete from chaos_private.match_queue x using chaos_private.sessions s,public.chaos_rooms z where x.player=s.player and s.room_id=z.id and z.phase<>'finished' and x.room_id is null;
  return jsonb_build_object('status','waiting','joined_at',mine.joined_at,'range',spread,'rating',p.rating,'rank',chaos_private.rank_name(p.rating));
 end if;
 select * into q from public.chaos_profiles where id=peer.player;
 for i in 1..20 loop
  candidate:='';for j in 1..6 loop candidate:=candidate||substr(alphabet,1+floor(random()*length(alphabet))::integer,1);end loop;
  begin
   insert into public.chaos_rooms(code,host,host_name,guest,guest_name,guest_seen,host_seen,game_mode,phase,battle_starts_at,select_until)
   values(candidate,peer.player,q.name,u,p.name,clock_timestamp(),clock_timestamp(),'ranked','select',clock_timestamp()+interval '4 seconds',clock_timestamp()+interval '14 seconds') returning * into r;exit;
  exception when unique_violation then null;end;
 end loop;
 if r.id is null then raise exception 'Arena konnte nicht reserviert werden';end if;
 update chaos_private.sessions set room_id=r.id where player in(u,peer.player);
 update chaos_private.match_queue set room_id=r.id where player in(u,peer.player);
 return jsonb_build_object('status','matched','code',r.code,'starts_at',r.battle_starts_at);
end;$$;

alter function public.chaos_action(text,text,text,integer,integer,integer) rename to chaos_action_v9;
alter function public.chaos_action_v9(text,text,text,integer,integer,integer) set schema chaos_private;
create function public.chaos_action(action text,room_code text default null,player_name text default null,choice integer default null,expected_round integer default null,expected_match integer default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.chaos_rooms;u uuid:=chaos_private.account_uid();
begin
 if action in('choose','confirm') then
  select * into r from public.chaos_rooms where code=upper(trim(room_code));
  if r.game_mode='ranked' and clock_timestamp()<r.battle_starts_at then
   if u<>r.host and u is distinct from r.guest then raise exception 'Kein Zugriff auf diesen Raum';end if;
   raise exception 'Der Kampf beginnt gleich';
  end if;
 end if;
 return chaos_private.chaos_action_v9(action,room_code,player_name,choice,expected_round,expected_match);
end;$$;

create function public.chaos_rankings(scope text default 'global') returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();p public.chaos_profiles;
begin
 if scope not in('global','friends') then raise exception 'Ungültige Rangliste';end if;
 select * into p from public.chaos_profiles where id=u;
 return jsonb_build_object('rating',p.rating,'rank',chaos_private.rank_name(p.rating),'matches',p.ranked_matches,'wins',p.ranked_wins,
 'players',coalesce((select jsonb_agg(to_jsonb(t)) from(select id,name,appearance,frame,xp,rating,ranked_wins,ranked_matches,chaos_private.rank_name(rating) rank from public.chaos_profiles x where ranked_matches>0 and (scope='global' or x.id=u or exists(select 1 from public.chaos_friends f where f.status='accepted' and ((f.requester=u and f.receiver=x.id) or(f.receiver=u and f.requester=x.id)))) order by rating desc,ranked_wins desc,id limit 100)t),'[]'::jsonb),
 'history',coalesce((select jsonb_agg(to_jsonb(t)) from(select room_id,match_no,case when host=u then host_before else guest_before end before,case when host=u then host_after else guest_after end after,winner=u won,finished_at from chaos_private.rating_results where u in(host,guest) order by finished_at desc limit 20)t),'[]'::jsonb));
end;$$;
revoke all on function public.chaos_matchmaking(text),public.chaos_rankings(text),public.chaos_action(text,text,text,integer,integer,integer) from public,anon;
grant execute on function public.chaos_matchmaking(text),public.chaos_rankings(text),public.chaos_action(text,text,text,integer,integer,integer) to authenticated;
revoke all on all functions in schema chaos_private from public,anon,authenticated;


-- 011_private_chat.sql

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


-- 012_chat_unblock.sql

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


-- 013_character_editor.sql

-- New free appearance fields; no inventory or account data is replaced.
create or replace function chaos_private.chaos_style_v6(action text,appearance jsonb default null,item_id text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();p public.chaos_profiles;s chaos_private.styles;k text;v text;normalized jsonb;slot_name text;
begin
 select * into p from public.chaos_profiles where id=u for update;
 if p.id is null then raise exception 'Bitte zuerst dein Profil einrichten'; end if;
 if action='appearance' then
  if appearance is null or jsonb_typeof(appearance)<>'object' or octet_length(appearance::text)>2048 then raise exception 'Aussehen ungültig'; end if;
  normalized:=p.appearance;
  for k,v in select key,value from jsonb_each_text(appearance) loop
   if k in ('skin','hairColor','eyes','outfitColor','lipColor','pantsColor','bootColor') then
    if v is null or v !~ '^#[a-fA-F0-9]{6}$' then raise exception 'Farbe ungültig'; end if;
   elsif k='body' then
    if v is null or v not in ('masculine','feminine','androgynous') then raise exception 'Körper ungültig'; end if;
   elsif k='hair' then
    if v is null or v not in ('swept','crop','curls','long','bob','braids','bun','bald','pixie','waves','ponytail','high-pony','twin-tails','mohawk','undercut','dreads','afro','sidebraid','shag','topknot') then raise exception 'Frisur ungültig'; end if;
   elsif k='face' then
    if v is null or v not in ('soft','angular','round') then raise exception 'Gesicht ungültig'; end if;
   elsif k='brows' then
    if v is null or v not in ('natural','bold','arched','straight') then raise exception 'Augenbrauen ungültig'; end if;
   elsif k='beard' then
    if v is null or v not in ('none','stubble','full','goatee','moustache') then raise exception 'Bart ungültig'; end if;
   elsif k='build' then if v is null or v not in('slim','athletic','broad') then raise exception 'Statur ungültig';end if;
   elsif k='height' then if v is null or v not in('short','average','tall') then raise exception 'Größe ungültig';end if;
   elsif k='eyeShape' then if v is null or v not in('almond','round','sharp') then raise exception 'Augenform ungültig';end if;
   elsif k='nose' then if v is null or v not in('small','straight','wide') then raise exception 'Nase ungültig';end if;
   elsif k='mouth' then if v is null or v not in('neutral','smile','serious','full') then raise exception 'Mund ungültig';end if;
   elsif k='freckles' then if v is null or v not in('none','light','many') then raise exception 'Sommersprossen ungültig';end if;
   elsif k='scar' then if v is null or v not in('none','cheek','brow') then raise exception 'Narbe ungültig';end if;
   elsif k='glasses' then if v is null or v not in('none','round','square') then raise exception 'Brille ungültig';end if;
   elsif k='earrings' then if v is null or v not in('none','studs','hoops') then raise exception 'Ohrringe ungültig';end if;
   elsif k in ('outfit','hat','aura') then
    -- Appearance editing cannot grant or equip paid cosmetics.
    if v is distinct from p.appearance->>k then raise exception 'Styles bitte über die Sammlung ausrüsten'; end if;
   else raise exception 'Unbekannte Aussehensoption'; end if;
   normalized:=jsonb_set(normalized,array[k],to_jsonb(v));
  end loop;
  update public.chaos_profiles set appearance=normalized where id=u;
 elsif action='buy' then
  select * into s from chaos_private.styles where id=item_id;
  if s.id is null then raise exception 'Shopartikel nicht gefunden'; end if;
  if exists(select 1 from chaos_private.inventory where player=u and item=item_id) then raise exception 'Artikel gehört dir bereits'; end if;
  if p.coins<s.price then raise exception 'Nicht genügend Coins'; end if;
  insert into chaos_private.inventory values(u,item_id);
  update public.chaos_profiles set coins=coins-s.price where id=u;
 elsif action='equip' then
  if item_id in ('outfit:reset','hat:reset','aura:reset') then
   slot_name:=split_part(item_id,':',1);
   update public.chaos_profiles set appearance=jsonb_set(public.chaos_profiles.appearance,array[slot_name],to_jsonb(case when slot_name='outfit' then 'starter' else 'none' end)) where id=u;
  elsif item_id='basic' then update public.chaos_profiles set frame='basic' where id=u;
  else
   select * into s from chaos_private.styles where id=item_id;
   if s.id is null or not exists(select 1 from chaos_private.inventory where player=u and item=item_id) then raise exception 'Diesen Style besitzt du nicht'; end if;
   if s.slot='frame' then update public.chaos_profiles set frame=s.id where id=u;
   else update public.chaos_profiles set appearance=jsonb_set(public.chaos_profiles.appearance,array[s.slot],to_jsonb(s.id)) where id=u; end if;
  end if;
 elsif action<>'state' then raise exception 'Ungültige Aktion'; end if;
 return public.chaos_social('state');
end;
$$;
revoke all on all functions in schema chaos_private from public,anon,authenticated;


-- 014_character_details.sql

-- Additional free appearance details; existing looks remain valid.
create or replace function chaos_private.chaos_style_v6(action text,appearance jsonb default null,item_id text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();p public.chaos_profiles;s chaos_private.styles;k text;v text;normalized jsonb;slot_name text;
begin
 select * into p from public.chaos_profiles where id=u for update;
 if p.id is null then raise exception 'Bitte zuerst dein Profil einrichten'; end if;
 if action='appearance' then
  if appearance is null or jsonb_typeof(appearance)<>'object' or octet_length(appearance::text)>2048 then raise exception 'Aussehen ungültig'; end if;
  normalized:=p.appearance;
  for k,v in select key,value from jsonb_each_text(appearance) loop
   if k in ('skin','hairColor','eyes','outfitColor','lipColor','trimColor','paintColor','pantsColor','bootColor') then
    if v is null or v !~ '^#[a-fA-F0-9]{6}$' then raise exception 'Farbe ungültig'; end if;
   elsif k='body' then
    if v is null or v not in ('masculine','feminine','androgynous') then raise exception 'Körper ungültig'; end if;
   elsif k='hair' then
    if v is null or v not in ('swept','crop','curls','long','bob','braids','bun','bald','pixie','waves','ponytail','high-pony','twin-tails','mohawk','undercut','dreads','afro','sidebraid','shag','topknot') then raise exception 'Frisur ungültig'; end if;
   elsif k='face' then
    if v is null or v not in ('soft','angular','round') then raise exception 'Gesicht ungültig'; end if;
   elsif k='brows' then
    if v is null or v not in ('natural','bold','arched','straight') then raise exception 'Augenbrauen ungültig'; end if;
   elsif k='beard' then
    if v is null or v not in ('none','stubble','full','goatee','moustache') then raise exception 'Bart ungültig'; end if;
   elsif k='build' then if v is null or v not in('slim','athletic','broad') then raise exception 'Statur ungültig';end if;
   elsif k='height' then if v is null or v not in('short','average','tall') then raise exception 'Größe ungültig';end if;
   elsif k='eyeShape' then if v is null or v not in('almond','round','sharp') then raise exception 'Augenform ungültig';end if;
   elsif k='nose' then if v is null or v not in('small','straight','wide') then raise exception 'Nase ungültig';end if;
   elsif k='mouth' then if v is null or v not in('neutral','smile','serious','full') then raise exception 'Mund ungültig';end if;
   elsif k='facePaint' then if v is null or v not in('none','warrior','runes','sun') then raise exception 'Bemalung ungültig';end if;
   elsif k='freckles' then if v is null or v not in('none','light','many') then raise exception 'Sommersprossen ungültig';end if;
   elsif k='scar' then if v is null or v not in('none','cheek','brow') then raise exception 'Narbe ungültig';end if;
   elsif k='glasses' then if v is null or v not in('none','round','square') then raise exception 'Brille ungültig';end if;
   elsif k='earrings' then if v is null or v not in('none','studs','hoops') then raise exception 'Ohrringe ungültig';end if;
   elsif k in ('outfit','hat','aura') then
    -- Appearance editing cannot grant or equip paid cosmetics.
    if v is distinct from p.appearance->>k then raise exception 'Styles bitte über die Sammlung ausrüsten'; end if;
   else raise exception 'Unbekannte Aussehensoption'; end if;
   normalized:=jsonb_set(normalized,array[k],to_jsonb(v));
  end loop;
  update public.chaos_profiles set appearance=normalized where id=u;
 elsif action='buy' then
  select * into s from chaos_private.styles where id=item_id;
  if s.id is null then raise exception 'Shopartikel nicht gefunden'; end if;
  if exists(select 1 from chaos_private.inventory where player=u and item=item_id) then raise exception 'Artikel gehört dir bereits'; end if;
  if p.coins<s.price then raise exception 'Nicht genügend Coins'; end if;
  insert into chaos_private.inventory values(u,item_id);
  update public.chaos_profiles set coins=coins-s.price where id=u;
 elsif action='equip' then
  if item_id in ('outfit:reset','hat:reset','aura:reset') then
   slot_name:=split_part(item_id,':',1);
   update public.chaos_profiles set appearance=jsonb_set(public.chaos_profiles.appearance,array[slot_name],to_jsonb(case when slot_name='outfit' then 'starter' else 'none' end)) where id=u;
  elsif item_id='basic' then update public.chaos_profiles set frame='basic' where id=u;
  else
   select * into s from chaos_private.styles where id=item_id;
   if s.id is null or not exists(select 1 from chaos_private.inventory where player=u and item=item_id) then raise exception 'Diesen Style besitzt du nicht'; end if;
   if s.slot='frame' then update public.chaos_profiles set frame=s.id where id=u;
   else update public.chaos_profiles set appearance=jsonb_set(public.chaos_profiles.appearance,array[s.slot],to_jsonb(s.id)) where id=u; end if;
  end if;
 elsif action<>'state' then raise exception 'Ungültige Aktion'; end if;
 return public.chaos_social('state');
end;
$$;
revoke all on all functions in schema chaos_private from public,anon,authenticated;


-- 015_cosmetic_catalog.sql

-- Private catalogue staging only: no existing table, purchase function or permission changes.
-- Items are not available for purchases or loot until a separately tested activation.
create table chaos_private.cosmetic_catalog(
 id text primary key,
 slot text not null check(slot in('outfit','hat','aura','frame','card','weapon','emote','card-aura','attack','victory')),
 name text not null,description text not null,color text not null check(color ~ '^#[a-fA-F0-9]{6}$'),
 price integer not null check(price between 1 and 10000),rarity integer not null check(rarity between 0 and 4),
 model text not null,power_index integer check(power_index between 0 and 6),theme text,
 check((slot='card' and power_index is not null and theme is not null) or(slot<>'card' and power_index is null))
);
alter table chaos_private.cosmetic_catalog enable row level security;
revoke all on chaos_private.cosmetic_catalog from public,anon,authenticated;
insert into chaos_private.cosmetic_catalog values
('outfit-umbra','outfit','Umbra-Mantel','Umbra-Mantel — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#71849e',650,2,'coat',null,null),('outfit-lumen','outfit','Lichtweber','Lichtweber — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#d5cba5',900,3,'robe',null,null),('outfit-runeguard','outfit','Runenpanzer','Runenpanzer — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#789da8',500,2,'armor',null,null),('outfit-nomad','outfit','Wanderer der Dünen','Wanderer der Dünen — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#ae8663',180,0,'poncho',null,null),('outfit-mist','outfit','Nebelkimono','Nebelkimono — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#a2adc7',350,1,'kimono',null,null),('outfit-ranger','outfit','Waldhüter','Waldhüter — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#7d9c75',400,1,'ranger',null,null),('outfit-orbit','outfit','Orbitaljacke','Orbitaljacke — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#a0b7d9',240,1,'bomber',null,null),('outfit-duelist','outfit','Klingenmeister','Klingenmeister — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#9b5368',1200,3,'duelist',null,null),('head-shade','hat','Schattenkapuze','Schattenkapuze — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#5e6b88',250,1,'hood',null,null),('head-witch','hat','Hexenkrone','Hexenkrone — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#9c80bf',600,2,'witch',null,null),('head-academy','hat','Akademie-Beret','Akademie-Beret — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#bc9f79',160,0,'beret',null,null),('head-visor','hat','Astralvisier','Astralvisier — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#8bd4e6',500,2,'visor',null,null),('head-antlers','hat','Geweih der Sterne','Geweih der Sterne — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#d9c49a',900,3,'antlers',null,null),('head-desert','hat','Wüstenturban','Wüstenturban — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#caa984',280,1,'turban',null,null),('aura-orbit','aura','Sternenbahn','Sternenbahn — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#a0c9f4',350,1,'orbit',null,null),('aura-runes','aura','Runenwache','Runenwache — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#b2a0e5',650,2,'runes',null,null),('aura-petals','aura','Blütenwirbel','Blütenwirbel — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#e9a5bc',450,1,'petals',null,null),('aura-storm','aura','Gewitterseele','Gewitterseele — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#9ae5ed',1100,3,'lightning',null,null),('aura-seraph','aura','Seraphenflügel','Seraphenflügel — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#f4dba5',1400,4,'wings',null,null),('weapon-lumen','weapon','Lumenklinge','Lumenklinge — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#e9d9ac',500,2,'sword',null,null),('weapon-archon','weapon','Archonstab','Archonstab — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#b7a4ed',800,3,'staff',null,null),('weapon-silver','weapon','Silberbogen','Silberbogen — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#a9c9dd',400,1,'bow',null,null),('weapon-night','weapon','Nachtdolch','Nachtdolch — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#798aa6',250,0,'dagger',null,null),('frame-runes','frame','Runensiegel','Runensiegel — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#96b6d2',350,1,'runes',null,null),('frame-solar','frame','Solarbogen','Solarbogen — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#e2c88e',700,2,'solar',null,null),('frame-prism','frame','Prismenring','Prismenring — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#d6a8e9',1500,4,'prism',null,null),('emote-greeting','emote','Sternengruß','Sternengruß — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#b4c8e2',120,0,'greeting',null,null),('emote-gg','emote','Ehrenvolles GG','Ehrenvolles GG — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#a6ceae',150,0,'gg',null,null),('emote-laugh','emote','Chaos-Lachen','Chaos-Lachen — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#c8a5e9',300,1,'laugh',null,null),('emote-crown','emote','Königlicher Gruß','Königlicher Gruß — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#e6ca93',600,2,'crown',null,null),('skin-relic-0','card','Relikt · Schere','Eine eigene Relikt-Grafik für Schere. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#b4a58e',140,0,'relic',0,'relic'),('skin-relic-1','card','Relikt · Stein','Eine eigene Relikt-Grafik für Stein. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#b4a58e',160,0,'relic',1,'relic'),('skin-relic-2','card','Relikt · Papier','Eine eigene Relikt-Grafik für Papier. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#b4a58e',140,0,'relic',2,'relic'),('skin-relic-3','card','Relikt · Zauberbrunnen','Eine eigene Relikt-Grafik für Zauberbrunnen. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#b4a58e',180,0,'relic',3,'relic'),('skin-relic-4','card','Relikt · Erzengel Michael','Eine eigene Relikt-Grafik für Erzengel Michael. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#b4a58e',220,0,'relic',4,'relic'),('skin-relic-5','card','Relikt · Himmlischer Colt','Eine eigene Relikt-Grafik für Himmlischer Colt. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#b4a58e',160,0,'relic',5,'relic'),('skin-relic-6','card','Relikt · Atombombe','Eine eigene Relikt-Grafik für Atombombe. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#b4a58e',180,0,'relic',6,'relic'),('skin-tide-0','card','Gezeiten · Schere','Eine eigene Gezeiten-Grafik für Schere. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#80cde2',280,1,'tide',0,'tide'),('skin-tide-1','card','Gezeiten · Stein','Eine eigene Gezeiten-Grafik für Stein. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#80cde2',300,1,'tide',1,'tide'),('skin-tide-2','card','Gezeiten · Papier','Eine eigene Gezeiten-Grafik für Papier. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#80cde2',280,1,'tide',2,'tide'),('skin-tide-3','card','Gezeiten · Zauberbrunnen','Eine eigene Gezeiten-Grafik für Zauberbrunnen. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#80cde2',320,1,'tide',3,'tide'),('skin-tide-4','card','Gezeiten · Erzengel Michael','Eine eigene Gezeiten-Grafik für Erzengel Michael. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#80cde2',360,1,'tide',4,'tide'),('skin-tide-5','card','Gezeiten · Himmlischer Colt','Eine eigene Gezeiten-Grafik für Himmlischer Colt. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#80cde2',300,1,'tide',5,'tide'),('skin-tide-6','card','Gezeiten · Atombombe','Eine eigene Gezeiten-Grafik für Atombombe. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#80cde2',320,1,'tide',6,'tide'),('skin-thorn-0','card','Dornenbund · Schere','Eine eigene Dornenbund-Grafik für Schere. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#b597e3',620,2,'thorn',0,'thorn'),('skin-thorn-1','card','Dornenbund · Stein','Eine eigene Dornenbund-Grafik für Stein. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#b597e3',640,2,'thorn',1,'thorn'),('skin-thorn-2','card','Dornenbund · Papier','Eine eigene Dornenbund-Grafik für Papier. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#b597e3',620,2,'thorn',2,'thorn'),('skin-thorn-3','card','Dornenbund · Zauberbrunnen','Eine eigene Dornenbund-Grafik für Zauberbrunnen. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#b597e3',660,2,'thorn',3,'thorn'),('skin-thorn-4','card','Dornenbund · Erzengel Michael','Eine eigene Dornenbund-Grafik für Erzengel Michael. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#b597e3',700,2,'thorn',4,'thorn'),('skin-thorn-5','card','Dornenbund · Himmlischer Colt','Eine eigene Dornenbund-Grafik für Himmlischer Colt. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#b597e3',640,2,'thorn',5,'thorn'),('skin-thorn-6','card','Dornenbund · Atombombe','Eine eigene Dornenbund-Grafik für Atombombe. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#b597e3',660,2,'thorn',6,'thorn'),('skin-solar-0','card','Sonnenpakt · Schere','Eine eigene Sonnenpakt-Grafik für Schere. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#e8c88d',1100,3,'solar',0,'solar'),('skin-solar-1','card','Sonnenpakt · Stein','Eine eigene Sonnenpakt-Grafik für Stein. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#e8c88d',1120,3,'solar',1,'solar'),('skin-solar-2','card','Sonnenpakt · Papier','Eine eigene Sonnenpakt-Grafik für Papier. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#e8c88d',1100,3,'solar',2,'solar'),('skin-solar-3','card','Sonnenpakt · Zauberbrunnen','Eine eigene Sonnenpakt-Grafik für Zauberbrunnen. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#e8c88d',1140,3,'solar',3,'solar'),('skin-solar-4','card','Sonnenpakt · Erzengel Michael','Eine eigene Sonnenpakt-Grafik für Erzengel Michael. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#e8c88d',1180,3,'solar',4,'solar'),('skin-solar-5','card','Sonnenpakt · Himmlischer Colt','Eine eigene Sonnenpakt-Grafik für Himmlischer Colt. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#e8c88d',1120,3,'solar',5,'solar'),('skin-solar-6','card','Sonnenpakt · Atombombe','Eine eigene Sonnenpakt-Grafik für Atombombe. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#e8c88d',1140,3,'solar',6,'solar'),('skin-prism-0','card','Prismenchaos · Schere','Eine eigene Prismenchaos-Grafik für Schere. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#deb1ef',1900,4,'prism',0,'prism'),('skin-prism-1','card','Prismenchaos · Stein','Eine eigene Prismenchaos-Grafik für Stein. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#deb1ef',1920,4,'prism',1,'prism'),('skin-prism-2','card','Prismenchaos · Papier','Eine eigene Prismenchaos-Grafik für Papier. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#deb1ef',1900,4,'prism',2,'prism'),('skin-prism-3','card','Prismenchaos · Zauberbrunnen','Eine eigene Prismenchaos-Grafik für Zauberbrunnen. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#deb1ef',1940,4,'prism',3,'prism'),('skin-prism-4','card','Prismenchaos · Erzengel Michael','Eine eigene Prismenchaos-Grafik für Erzengel Michael. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#deb1ef',1980,4,'prism',4,'prism'),('skin-prism-5','card','Prismenchaos · Himmlischer Colt','Eine eigene Prismenchaos-Grafik für Himmlischer Colt. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#deb1ef',1920,4,'prism',5,'prism'),('skin-prism-6','card','Prismenchaos · Atombombe','Eine eigene Prismenchaos-Grafik für Atombombe. Nur diese Macht erhält den Skin. Das Balancing bleibt gleich.','#deb1ef',1940,4,'prism',6,'prism'),('card-aura-shimmer','card-aura','Schimmer','Schimmer — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#b7bcc9',160,0,'glow',null,null),('card-aura-orbit','card-aura','Astralorbit','Astralorbit — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#89bfe8',320,1,'orbit',null,null),('card-aura-sigil','card-aura','Runenkreis','Runenkreis — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#b49de6',580,2,'sigil',null,null),('card-aura-flare','card-aura','Feuersaum','Feuersaum — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#e8c88d',950,3,'flare',null,null),('card-aura-nebula','card-aura','Nebelschleier','Nebelschleier — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#dfb0ef',1500,4,'nebula',null,null),('attack-flash','attack','Klingenblitz','Klingenblitz — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#b7bcc9',160,0,'flash',null,null),('attack-pulse','attack','Astralstoß','Astralstoß — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#89bfe8',320,1,'pulse',null,null),('attack-rift','attack','Dimensionsriss','Dimensionsriss — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#b49de6',580,2,'rift',null,null),('attack-meteor','attack','Sternenregen','Sternenregen — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#e8c88d',950,3,'meteor',null,null),('attack-nova','attack','Chaosnova','Chaosnova — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#dfb0ef',1500,4,'nova',null,null),('victory-dust','victory','Goldstaub','Goldstaub — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#b7bcc9',160,0,'confetti',null,null),('victory-laurel','victory','Lorbeerlicht','Lorbeerlicht — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#89bfe8',320,1,'laurel',null,null),('victory-bloom','victory','Runenblüte','Runenblüte — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#b49de6',580,2,'bloom',null,null),('victory-seraph','victory','Seraphenflug','Seraphenflug — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#e8c88d',950,3,'wings',null,null),('victory-prism','victory','Prismensupernova','Prismensupernova — ein eigener Fantasy-Style. Rein kosmetisch, ohne Kampfbonus.','#dfb0ef',1500,4,'nova',null,null);


-- 016_equipment.sql

alter table chaos_private.styles drop constraint styles_slot_check;
alter table chaos_private.styles add check(slot in('outfit','hat','aura','frame','card','weapon','emote','card-aura','attack','victory'));
alter table chaos_private.styles drop constraint styles_rarity_check;
alter table chaos_private.styles add check(rarity between 0 and 4);
alter table chaos_private.styles add column power_index integer check(power_index between 0 and 6);
insert into chaos_private.styles(id,slot,price,rarity,power_index) select id,slot,price,rarity,power_index from chaos_private.cosmetic_catalog;
alter table public.chaos_profiles add column card_loadouts jsonb not null default '{}';
alter table public.chaos_profiles drop constraint chaos_profiles_frame_check;
alter table public.chaos_profiles add check(length(frame) between 1 and 80);
do $$declare definition text;begin
 definition:=pg_get_functiondef('chaos_private.chaos_style_v6(text,jsonb,text)'::regprocedure);
 if position('elsif k in (''outfit'',''hat'',''aura'')' in definition)=0 then raise exception 'Unexpected appearance engine';end if;
 definition:=replace(definition,'k in (''outfit'',''hat'',''aura'')','k in (''outfit'',''hat'',''aura'',''weapon'',''emote'',''victory'')');
 definition:=replace(definition,'v is distinct from p.appearance->>k','v is distinct from coalesce(p.appearance->>k,case when k=''outfit'' then ''starter'' else ''none'' end)');execute definition;
end;$$;
alter function public.chaos_style(text,jsonb,text) rename to chaos_style_v7;
alter function public.chaos_style_v7(text,jsonb,text) set schema chaos_private;
revoke all on function chaos_private.chaos_style_v7(text,jsonb,text) from public,anon,authenticated;
create function public.chaos_style(action text,appearance jsonb default null,item_id text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();s chaos_private.styles;p public.chaos_profiles;k text;
begin
 if action='equip' then
  select * into s from chaos_private.styles where id=item_id;
  if item_id in('weapon:reset','emote:reset','victory:reset') then
   k:=split_part(item_id,':',1);update public.chaos_profiles set appearance=jsonb_set(public.chaos_profiles.appearance,array[k],'"none"') where id=u;return public.chaos_social('state');
  elsif s.slot in('weapon','emote','victory') then
   select * into p from public.chaos_profiles where id=u for update;
   if not exists(select 1 from chaos_private.inventory where player=u and item=s.id) then raise exception 'Diesen Style besitzt du nicht';end if;
   update public.chaos_profiles set appearance=jsonb_set(public.chaos_profiles.appearance,array[s.slot],to_jsonb(s.id)) where id=u;return public.chaos_social('state');
  elsif s.slot in('card-aura','attack') or(s.slot='card' and s.power_index is not null) then raise exception 'Bitte bei der gewünschten Macht in der Sammlung ausrüsten';end if;
 end if;
 return chaos_private.chaos_style_v7(action,appearance,item_id);
end;$$;
revoke all on function public.chaos_style(text,jsonb,text) from public,anon;
grant execute on function public.chaos_style(text,jsonb,text) to authenticated;
create function public.chaos_collection(action text,power_index integer default null,slot text default null,item_id text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();p public.chaos_profiles;s chaos_private.styles;entry jsonb;expected_slot text;
begin
 select * into p from public.chaos_profiles where id=u for update;if p.id is null then raise exception 'Bitte zuerst dein Profil einrichten';end if;
 if action='equip' then
  if power_index is null or power_index not between 0 and 6 or slot is null or slot not in('skin','aura','effect') then raise exception 'Ungültige Macht oder Ausrüstungsart';end if;
  if item_id is null then raise exception 'Style fehlt';end if;
  if item_id not in('classic','none') then
   select * into s from chaos_private.styles where id=item_id;
   expected_slot:=case slot when 'skin' then 'card' when 'aura' then 'card-aura' else 'attack' end;
   if s.id is null or s.slot<>expected_slot or(s.power_index is not null and s.power_index<>power_index) or not exists(select 1 from chaos_private.inventory where player=u and item=s.id) then raise exception 'Dieser Style ist für diese Macht nicht freigeschaltet';end if;
  elsif (slot='skin' and item_id<>'classic')or(slot<>'skin' and item_id<>'none') then raise exception 'Ungültiger Standardstyle';end if;
  entry:=coalesce(p.card_loadouts->power_index::text,'{}'::jsonb)||jsonb_build_object(slot,item_id);
  update public.chaos_profiles set card_loadouts=jsonb_set(card_loadouts,array[power_index::text],entry) where id=u;
 elsif action<>'state' then raise exception 'Ungültige Sammlungsaktion';end if;
 return public.chaos_social('state');
end;$$;
revoke all on function public.chaos_collection(text,integer,text,text) from public,anon;
grant execute on function public.chaos_collection(text,integer,text,text) to authenticated;
alter function chaos_private.life_snapshot(public.chaos_rooms,uuid) rename to life_snapshot_v14;
create function chaos_private.life_snapshot(r public.chaos_rooms,u uuid) returns jsonb language plpgsql set search_path='' as $$
declare d jsonb;begin
 d:=chaos_private.life_snapshot_v14(r,u);
 d:=jsonb_set(d,'{players,host,card_loadouts}',coalesce((select card_loadouts from public.chaos_profiles where id=r.host),'{}'::jsonb));
 d:=jsonb_set(d,'{players,guest,card_loadouts}',coalesce((select card_loadouts from public.chaos_profiles where id=r.guest),'{}'::jsonb));
 return d;
end;$$;
revoke all on function chaos_private.life_snapshot(public.chaos_rooms,uuid) from public,anon,authenticated;


-- 017_shop.sql

create table chaos_private.shop_receipts(id uuid primary key,player uuid not null references public.chaos_profiles on delete cascade,item text not null references chaos_private.styles,price integer not null check(price>0),created_at timestamptz not null default clock_timestamp());
alter table chaos_private.shop_receipts enable row level security;
revoke all on chaos_private.shop_receipts from public,anon,authenticated;
create index shop_receipts_player on chaos_private.shop_receipts(player,created_at desc);
create function chaos_private.store_price(item text,base integer) returns integer language sql volatile set search_path='' as $$
 select case when exists(select 1 from chaos_private.cosmetic_catalog where id=item) and get_byte(decode(md5(item||to_char(clock_timestamp() at time zone 'UTC','YYYYMMDD')),'hex'),0)%12=0 then base*4/5 else base end;
$$;
revoke all on function chaos_private.store_price(text,integer) from public,anon,authenticated;
create function public.chaos_store(action text,item_id text default null,quoted_price integer default null,request_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();p public.chaos_profiles;s chaos_private.styles;receipt chaos_private.shop_receipts;price integer;
begin
 if action='catalog' then
  return jsonb_build_object('day',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD'),'items',coalesce((select jsonb_agg(jsonb_build_object('id',catalog_item.id,'price',chaos_private.store_price(catalog_item.id,catalog_item.price),'base_price',catalog_item.price,'popularity',coalesce(owned.n,0))) from chaos_private.styles catalog_item left join(select item,count(*) n from chaos_private.inventory group by item)owned on owned.item=catalog_item.id),'[]'::jsonb));
 elsif action<>'buy' or action is null then raise exception 'Ungültige Shopaktion';end if;
 if request_id is null then raise exception 'Kauf-ID fehlt';end if;
 select * into p from public.chaos_profiles where id=u for update;if p.id is null then raise exception 'Bitte zuerst dein Profil einrichten';end if;
 select * into receipt from chaos_private.shop_receipts where id=request_id;
 if receipt.id is not null then
  if receipt.player<>u or receipt.item is distinct from item_id then raise exception 'Kauf-ID ungültig';end if;
  return public.chaos_social('state');
 end if;
 select * into s from chaos_private.styles where id=item_id;if s.id is null then raise exception 'Gegenstand nicht gefunden';end if;
 price:=chaos_private.store_price(s.id,s.price);
 if quoted_price is distinct from price then raise exception 'Das Angebot hat sich geändert. Bitte den Shop aktualisieren';end if;
 if exists(select 1 from chaos_private.inventory where player=u and item=s.id) then return public.chaos_social('state');end if;
 if p.coins<price then raise exception 'Nicht genug Chaos Coins';end if;
 insert into chaos_private.inventory values(u,s.id);update public.chaos_profiles set coins=coins-price where id=u;
 insert into chaos_private.shop_receipts values(request_id,u,s.id,price,clock_timestamp());
 return public.chaos_social('state');
end;$$;
revoke all on function public.chaos_store(text,text,integer,uuid) from public,anon;
grant execute on function public.chaos_store(text,text,integer,uuid) to authenticated;


-- 018_emotes.sql

alter table public.chaos_rooms add column host_emote text;
alter table public.chaos_rooms add column guest_emote text;
alter table public.chaos_rooms add column host_emote_at timestamptz;
alter table public.chaos_rooms add column guest_emote_at timestamptz;
create function public.chaos_emote(room_code text,emote_id text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();r public.chaos_rooms;last_sent timestamptz;
begin
 select * into r from public.chaos_rooms where code=upper(trim(room_code)) for update;
 if r.id is null or(u<>r.host and u is distinct from r.guest) or r.updated_at<clock_timestamp()-interval '24 hours' then raise exception 'Kein Zugriff auf diesen Raum';end if;
 if emote_id is null or (emote_id not in('wave','gg') and not exists(select 1 from chaos_private.inventory i join chaos_private.styles s on s.id=i.item where i.player=u and s.slot='emote' and s.id=emote_id)) then raise exception 'Emote nicht freigeschaltet';end if;
 last_sent:=case when u=r.host then r.host_emote_at else r.guest_emote_at end;
 if last_sent>clock_timestamp()-interval '3 seconds' then raise exception 'Bitte kurz warten';end if;
 if u=r.host then update public.chaos_rooms set host_emote=emote_id,host_emote_at=clock_timestamp(),host_seen=clock_timestamp(),updated_at=clock_timestamp() where id=r.id returning * into r;
 else update public.chaos_rooms set guest_emote=emote_id,guest_emote_at=clock_timestamp(),guest_seen=clock_timestamp(),updated_at=clock_timestamp() where id=r.id returning * into r;end if;
 return chaos_private.life_snapshot(r,u);
end;$$;
revoke all on function public.chaos_emote(text,text) from public,anon;
grant execute on function public.chaos_emote(text,text) to authenticated;


-- 019_packs.sql

alter table chaos_private.packs drop constraint packs_tier_check;
alter table chaos_private.packs add check(tier between 0 and 3);
create table chaos_private.pack_rules(tier integer primary key check(tier between 0 and 3),price integer not null check(price>0),weights integer[] not null check(array_length(weights,1)=7 and array_position(weights,null) is null and 0<=all(weights) and weights[1]+weights[2]+weights[3]+weights[4]+weights[5]+weights[6]+weights[7]=10000),coin_min integer not null check(coin_min>0),coin_max integer not null check(coin_max>=coin_min));
alter table chaos_private.pack_rules enable row level security;
revoke all on chaos_private.pack_rules from public,anon,authenticated;
insert into chaos_private.pack_rules values(0,150,array[2000,3500,2000,1800,500,180,20],40,100),(1,400,array[1000,3000,1000,2800,1700,450,50],100,250),(2,900,array[500,2500,0,2000,3000,1800,200],250,700),(3,1800,array[200,1800,0,1000,2500,3500,1000],450,1000);
create function chaos_private.loot_roll() returns integer language sql volatile set search_path='' as $$select floor(random()*10000)::integer;$$;
revoke all on function chaos_private.loot_roll() from public,anon,authenticated;
create or replace function public.chaos_loot(action text,pack_tier integer,request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();p public.chaos_profiles;receipt chaos_private.loot_receipts;rule chaos_private.pack_rules;roll integer;bucket integer;i integer;threshold integer:=0;draw_rarity integer;s chaos_private.styles;reward jsonb;amount integer;qty integer;
begin
 if request_id is null or pack_tier is null or pack_tier not between 0 and 3 then raise exception 'Truhe ungültig';end if;
 select * into p from public.chaos_profiles where id=u for update;if p.id is null then raise exception 'Bitte zuerst dein Profil einrichten';end if;
 select * into receipt from chaos_private.loot_receipts where id=request_id;
 if receipt.id is not null then
  if receipt.player<>u or receipt.action<>action or receipt.tier<>pack_tier then raise exception 'Anfrage ungültig';end if;
  return public.chaos_social('state')||jsonb_build_object('loot',receipt.reward);
 end if;
 select * into rule from chaos_private.pack_rules where tier=pack_tier;if rule.tier is null then raise exception 'Truhenkonfiguration fehlt';end if;
 if action='buy' then
  if p.coins<rule.price then raise exception 'Nicht genug Chaos Coins';end if;
  update public.chaos_profiles set coins=coins-rule.price where id=u;
  insert into chaos_private.packs values(u,pack_tier,1) on conflict(player,tier) do update set quantity=chaos_private.packs.quantity+1;
  reward:=jsonb_build_object('kind','purchased','tier',pack_tier);
 elsif action='open' then
  select quantity into qty from chaos_private.packs where player=u and tier=pack_tier for update;
  if coalesce(qty,0)<1 then raise exception 'Keine Truhe dieser Stufe vorhanden';end if;
  update chaos_private.packs set quantity=quantity-1 where player=u and tier=pack_tier;
  roll:=chaos_private.loot_roll();
  if roll not between 0 and 9999 or roll is null then raise exception 'Ungültiger Zufallswert';end if;
  for i in 1..7 loop threshold:=threshold+rule.weights[i];if roll<threshold then bucket:=i;exit;end if;end loop;
  if bucket is null then raise exception 'Truhenwahrscheinlichkeiten ungültig';end if;
  if bucket=1 then reward:=jsonb_build_object('kind','empty','tier',pack_tier);
  elsif bucket=2 then
   amount:=rule.coin_min+floor(random()*(rule.coin_max-rule.coin_min+1))::integer;
   update public.chaos_profiles set coins=coins+amount where id=u;
   reward:=jsonb_build_object('kind','coins','coins',amount,'tier',pack_tier);
  else
   draw_rarity:=bucket-3;
   select * into s from chaos_private.styles where rarity=draw_rarity order by random() limit 1;
   if s.id is null then raise exception 'Für diese Seltenheit fehlt ein Gegenstand';end if;
   if exists(select 1 from chaos_private.inventory where player=u and item=s.id) then
    amount:=s.price/5;update public.chaos_profiles set coins=coins+amount where id=u;
    reward:=jsonb_build_object('kind','duplicate','item',s.id,'coins',amount,'rarity',s.rarity,'tier',pack_tier);
   else
    insert into chaos_private.inventory values(u,s.id);
    reward:=jsonb_build_object('kind','item','item',s.id,'rarity',s.rarity,'tier',pack_tier);
   end if;
  end if;
 else raise exception 'Ungültige Truhenaktion';end if;
 insert into chaos_private.loot_receipts values(request_id,u,action,pack_tier,reward,clock_timestamp());
 return public.chaos_social('state')||jsonb_build_object('loot',reward);
end;$$;
create function public.chaos_packs() returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();
begin
 return jsonb_build_object('rules',(select jsonb_agg(jsonb_build_object('tier',tier,'price',price,'weights',weights,'coin_min',coin_min,'coin_max',coin_max) order by tier) from chaos_private.pack_rules),
 'history',coalesce((select jsonb_agg(to_jsonb(t)) from(select id,tier,reward,created_at from chaos_private.loot_receipts where player=u and action='open' order by created_at desc limit 30)t),'[]'::jsonb));
end;$$;
revoke all on function public.chaos_loot(text,integer,uuid),public.chaos_packs() from public,anon;
grant execute on function public.chaos_loot(text,integer,uuid),public.chaos_packs() to authenticated;


-- Migration 020: persistent journal, daily quests and achievements.

-- Additive journal: no changes to game outcomes, existing wallets or historical data.
create table chaos_private.match_journal(room_id uuid not null,match_no integer not null,player uuid not null references public.chaos_profiles on delete cascade,mode text not null,campaign_stage integer,wave integer,opponent_name text not null,outcome text not null check(outcome in('win','loss','draw')),rounds integer not null,hp integer not null,round_wins integer not null,xp integer not null,coins integer not null,choices integer[] not null,qualified boolean not null,created_at timestamptz not null default clock_timestamp(),primary key(room_id,match_no,player));
alter table chaos_private.match_journal enable row level security;
revoke all on chaos_private.match_journal from public,anon,authenticated;
create index match_journal_player_time on chaos_private.match_journal(player,created_at desc);
create table chaos_private.progress_rules(id text primary key,kind text not null check(kind in('daily','achievement')),name text not null,description text not null,metric text not null,target integer not null check(target>0),xp integer not null check(xp>=0),coins integer not null check(coins>=0),item text references chaos_private.styles);
alter table chaos_private.progress_rules enable row level security;
revoke all on chaos_private.progress_rules from public,anon,authenticated;
insert into chaos_private.progress_rules values
 ('daily-play','daily','Zurück in der Arena','Spiele drei vollständige Duelle.','play',3,50,0,null),
 ('daily-win','daily','Doppelter Triumph','Gewinne zwei Matches.','win',2,60,40,null),
 ('daily-campaign','daily','Auf Kapitelreise','Besiege fünf Kampagnengegner.','campaign',5,80,50,'emote-gg'),
 ('daily-rounds','daily','Zehn gute Züge','Gewinne zehn Runden.','rounds',10,50,20,null),
 ('daily-endless','daily','Tiefer ins Chaos','Erreiche Welle fünf in einem Endlos-Lauf.','wave',5,70,35,null),
 ('first-win','achievement','Erster Sieg','Gewinne dein erstes Match.','wins',1,75,30,null),
 ('ten-wins','achievement','Unaufhaltsam','Gewinne zehn Matches.','wins',10,150,100,null),
 ('collector','achievement','Sammler','Besitze zwanzig kosmetische Gegenstände.','items',20,150,0,null),
 ('legendary','achievement','Legendär','Besitze einen legendären oder mythischen Style.','legendary',1,100,0,null),
 ('endless-warrior','achievement','Endloser Krieger','Erreiche Welle fünfundzwanzig.','best-wave',25,300,100,null),
 ('chaos-master','achievement','Chaos-Meister','Gewinne hundert Ranglistenduelle.','ranked-wins',100,500,250,null);
create table chaos_private.progress_awards(player uuid not null references public.chaos_profiles on delete cascade,reward_id text not null references chaos_private.progress_rules,period date not null,unlocked_at timestamptz not null default clock_timestamp(),claimed_at timestamptz,primary key(player,reward_id,period));
alter table chaos_private.progress_awards enable row level security;
revoke all on chaos_private.progress_awards from public,anon,authenticated;
create function chaos_private.record_journal() returns trigger language plpgsql security definer set search_path='' as $$
declare p uuid;manual integer;chosen integer[];earned chaos_private.rewards;reward_xp integer;reward_coins integer;
begin
 if new.phase<>'finished' or(old.phase='finished' and old.match_no=new.match_no) or new.end_reason='abandoned' then return new;end if;
 for p in select id from(select new.host id union select new.guest where not new.is_bot)t order by id loop
  if p is null then continue;end if;
  select count(*) into manual from chaos_private.moves where room_id=new.id and match_no=new.match_no and player=p;
  if manual=0 then continue;end if;
  select array_agg(n order by power) into chosen from(select power,(select count(*)::integer from chaos_private.moves where room_id=new.id and match_no=new.match_no and player=p and choice=power)n from generate_series(0,6)power)t;
  select * into earned from chaos_private.rewards where room_id=new.id and match_no=new.match_no and player=p;
  if new.game_mode='endless' then
   reward_xp:=coalesce(earned.xp,case when new.end_reason='knockout' and new.host_hp=0 then 10 else 0 end);reward_coins:=coalesce(earned.coins,0);
  elsif earned.player is not null then
   reward_xp:=case when new.match_winner=p then new.reward_xp when new.match_winner is null then 60+coalesce(new.campaign_stage,0)*15 else 40+coalesce(new.campaign_stage,0)*10 end;
   reward_coins:=case when new.match_winner=p then new.reward_coins else 0 end;
  else reward_xp:=0;reward_coins:=0;end if;
  insert into chaos_private.match_journal values(new.id,new.match_no,p,new.game_mode,new.campaign_stage,new.endless_wave,case when p=new.host then coalesce(new.guest_name,'Chaos-Bot') else new.host_name end,case when new.match_winner=p then 'win' when new.match_winner is null then 'draw' else 'loss' end,new.round_no,case when p=new.host then coalesce(new.host_hp,0) else coalesce(new.guest_hp,0) end,case when p=new.host then new.host_score else new.guest_score end,reward_xp,reward_coins,chosen,coalesce(new.end_reason='knockout',false) and manual>=case when new.game_mode='endless' then 1 else 3 end,clock_timestamp()) on conflict do nothing;
 end loop;return new;
end;$$;
revoke all on function chaos_private.record_journal() from public,anon,authenticated;
-- Alphabetic ordering runs this after the existing award_match trigger.
create trigger z_record_journal after update on public.chaos_rooms for each row execute function chaos_private.record_journal();
create function chaos_private.progress_value(u uuid,metric text,daily boolean) returns integer language plpgsql set search_path='' as $$
declare n integer;day_start timestamptz:=(date_trunc('day',clock_timestamp() at time zone 'UTC') at time zone 'UTC');
begin
 if daily then
  select case metric when 'play' then count(*) filter(where mode<>'endless') when 'win' then count(*) filter(where outcome='win') when 'campaign' then count(*) filter(where outcome='win' and campaign_stage is not null) when 'rounds' then coalesce(sum(round_wins),0) when 'wave' then coalesce(max(wave),0) else 0 end into n from chaos_private.match_journal where player=u and qualified and created_at>=day_start;
 elsif metric='wins' then select wins into n from public.chaos_profiles where id=u;
 elsif metric='items' then select count(*) into n from chaos_private.inventory where player=u;
 elsif metric='legendary' then select count(*) into n from chaos_private.inventory i join chaos_private.styles s on s.id=i.item where i.player=u and s.rarity>=3;
 elsif metric='best-wave' then select endless_best into n from public.chaos_profiles where id=u;
 elsif metric='ranked-wins' then select ranked_wins into n from public.chaos_profiles where id=u;
 end if;return coalesce(n,0);
end;$$;
revoke all on function chaos_private.progress_value(uuid,text,boolean) from public,anon,authenticated;
create function public.chaos_journal(action text default 'state',reward_id text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();p public.chaos_profiles;rule chaos_private.progress_rules;a chaos_private.progress_awards;period_key date;progress integer;tasks jsonb:='[]';reward jsonb;history jsonb;stats jsonb;chapters jsonb;current_streak integer:=0;best_streak integer:=0;favorite integer;
begin
 select * into p from public.chaos_profiles where id=u for update;if p.id is null then raise exception 'Bitte zuerst dein Profil einrichten';end if;
 if action is null or action not in('state','claim') then raise exception 'Ungültige Fortschrittsaktion';end if;
 if action='claim' then
  select * into rule from chaos_private.progress_rules r where r.id=reward_id;if rule.id is null then raise exception 'Belohnung nicht gefunden';end if;
  period_key:=case when rule.kind='daily' then (clock_timestamp() at time zone 'UTC')::date else date '1970-01-01' end;
  progress:=chaos_private.progress_value(u,rule.metric,rule.kind='daily');
  if progress<rule.target then raise exception 'Aufgabe noch nicht abgeschlossen';end if;
  insert into chaos_private.progress_awards(player,reward_id,period) values(u,rule.id,period_key) on conflict do nothing;
  select * into a from chaos_private.progress_awards x where x.player=u and x.reward_id=rule.id and x.period=period_key for update;
  if a.claimed_at is null then
   update chaos_private.progress_awards x set claimed_at=clock_timestamp() where x.player=u and x.reward_id=rule.id and x.period=period_key;
   update public.chaos_profiles set xp=xp+rule.xp,coins=coins+rule.coins where id=u;
   if rule.item is not null then insert into chaos_private.inventory(player,item) values(u,rule.item) on conflict do nothing;end if;
   reward:=jsonb_build_object('id',rule.id,'xp',rule.xp,'coins',rule.coins,'item',rule.item);
  end if;
 end if;
 for rule in select * from chaos_private.progress_rules order by kind desc,id loop
  period_key:=case when rule.kind='daily' then (clock_timestamp() at time zone 'UTC')::date else date '1970-01-01' end;
  progress:=chaos_private.progress_value(u,rule.metric,rule.kind='daily');
  if progress>=rule.target then insert into chaos_private.progress_awards(player,reward_id,period) values(u,rule.id,period_key) on conflict do nothing;end if;
  select * into a from chaos_private.progress_awards x where x.player=u and x.reward_id=rule.id and x.period=period_key;
  tasks:=tasks||jsonb_build_array(to_jsonb(rule)||jsonb_build_object('progress',least(progress,rule.target),'unlocked_at',a.unlocked_at,'claimed_at',a.claimed_at));
 end loop;
 select coalesce(jsonb_agg(to_jsonb(t)),'[]') into history from(select opponent_name,mode,campaign_stage,wave,outcome,rounds,hp,xp,coins,created_at from chaos_private.match_journal where player=u order by created_at desc,room_id desc limit 30)t;
 select coalesce(jsonb_object_agg(campaign_stage::text,jsonb_build_object('rounds',rounds,'hp',hp,'wins',wins)),'{}') into chapters from(select distinct on(campaign_stage) campaign_stage,rounds,hp,count(*) over(partition by campaign_stage)::integer wins from chaos_private.match_journal where player=u and outcome='win' and campaign_stage is not null order by campaign_stage,rounds,hp desc)t;
 select coalesce(max(n),0) into best_streak from(select count(*) n from(select outcome,sum(case when outcome='win' then 0 else 1 end) over(order by created_at,room_id,match_no)grp from chaos_private.match_journal where player=u and mode<>'endless')t where outcome='win' group by grp)t;
 select count(*) into current_streak from chaos_private.match_journal j where player=u and mode<>'endless' and outcome='win' and not exists(select 1 from chaos_private.match_journal x where x.player=u and x.mode<>'endless' and x.outcome<>'win' and(x.created_at,x.room_id,x.match_no)>(j.created_at,j.room_id,j.match_no));
 select power into favorite from(select power,sum(choices[power+1]) n from chaos_private.match_journal cross join generate_series(0,6)power where player=u group by power)t where n>0 order by n desc,power limit 1;
 select jsonb_build_object('tracked_matches',count(*) filter(where mode<>'endless'),'tracked_wins',count(*) filter(where mode<>'endless' and outcome='win'),'losses',count(*) filter(where mode<>'endless' and outcome='loss'),'draws',count(*) filter(where mode<>'endless' and outcome='draw'),'streak',current_streak,'best_streak',best_streak,'favorite',favorite,'total_matches',p.matches,'total_wins',p.wins,'endless_best',p.endless_best) into stats from chaos_private.match_journal where player=u;
 return jsonb_build_object('tasks',tasks,'history',history,'chapters',chapters,'stats',stats,'reward',reward,'server_now',clock_timestamp(),'reset_at',(date_trunc('day',clock_timestamp() at time zone 'UTC')+interval '1 day') at time zone 'UTC','state',public.chaos_social('state'));
end;$$;
revoke all on function public.chaos_journal(text,text) from public,anon;
grant execute on function public.chaos_journal(text,text) to authenticated;

commit;

begin;
-- Opt-in protocol preserves existing clients and in-flight matches.
alter table public.chaos_rooms add column wager_enabled boolean not null default false;
alter table public.chaos_rooms add column wager_until timestamptz;
alter table public.chaos_rooms add column host_wager_ready boolean not null default false;
alter table public.chaos_rooms add column guest_wager_ready boolean not null default false;
create table chaos_private.round_wagers(
 room_id uuid not null,match_no integer not null,round_no integer not null,
 player uuid not null references public.chaos_profiles on delete cascade,
 stake integer not null check(stake in(0,10,25,50,100)),
 payout integer check(payout>=0),outcome text check(outcome in('win','loss','draw','refund')),
 created_at timestamptz not null default clock_timestamp(),settled_at timestamptz,
 primary key(room_id,match_no,round_no,player)
);
alter table chaos_private.round_wagers enable row level security;
revoke all on chaos_private.round_wagers from public,anon,authenticated;
create index round_wagers_player_time on chaos_private.round_wagers(player,created_at desc);
create function chaos_private.wager_round() returns trigger language plpgsql security definer set search_path='' as $$
declare w chaos_private.round_wagers;pay integer;outc text;active boolean;
begin
 if tg_op='DELETE' then
  perform id from public.chaos_profiles where id in(old.host,old.guest) order by id for update;
  for w in select * from chaos_private.round_wagers where room_id=old.id and payout is null for update loop
   update public.chaos_profiles set coins=coins+w.stake where id=w.player;
   update chaos_private.round_wagers set payout=w.stake,outcome='refund',settled_at=clock_timestamp() where room_id=w.room_id and match_no=w.match_no and round_no=w.round_no and player=w.player;
  end loop;return old;
 end if;
 if new.wager_enabled and new.phase='select' and (not old.wager_enabled or old.phase<>'select' or old.round_no<>new.round_no or old.match_no<>new.match_no) then
  new.wager_until:=greatest(clock_timestamp(),coalesce(new.battle_starts_at,clock_timestamp()))+interval '10 seconds';
  new.select_until:=new.wager_until+interval '10 seconds';
  new.host_wager_ready:=false;new.guest_wager_ready:=new.is_bot;
 end if;
 if old.phase='select' and new.phase in('result','finished') then
  perform id from public.chaos_profiles where id in(new.host,new.guest) order by id for update;
  active:=exists(select 1 from chaos_private.moves where room_id=new.id and match_no=old.match_no and round_no=old.round_no and player=new.host)
   and exists(select 1 from chaos_private.moves where room_id=new.id and match_no=old.match_no and round_no=old.round_no and player=new.guest);
  for w in select * from chaos_private.round_wagers where room_id=new.id and match_no=old.match_no and round_no=old.round_no and payout is null for update loop
   if not active or new.end_reason in('abandoned','forfeit','inactivity') then pay:=w.stake;outc:='refund';
   elsif new.winner is null then pay:=w.stake;outc:='draw';
   elsif new.winner=w.player then pay:=w.stake*2;outc:='win';
   else pay:=0;outc:='loss';end if;
   update public.chaos_profiles set coins=coins+pay where id=w.player;
   update chaos_private.round_wagers set payout=pay,outcome=outc,settled_at=clock_timestamp() where room_id=w.room_id and match_no=w.match_no and round_no=w.round_no and player=w.player;
  end loop;
 end if;
 return new;
end;$$;
create trigger a_wager_round before update or delete on public.chaos_rooms for each row execute function chaos_private.wager_round();
alter function chaos_private.advance_lives(public.chaos_rooms) rename to advance_lives_v20;
create function chaos_private.advance_lives(r public.chaos_rooms) returns public.chaos_rooms language plpgsql set search_path='' as $$
begin
 if r.wager_enabled and r.phase='select' and clock_timestamp()<r.wager_until then return r;end if;
 return chaos_private.advance_lives_v20(r);
end;$$;
alter function chaos_private.life_snapshot(public.chaos_rooms,uuid) rename to life_snapshot_v20;
create function chaos_private.life_snapshot(r public.chaos_rooms,u uuid) returns jsonb language plpgsql set search_path='' as $$
declare d jsonb;w chaos_private.round_wagers;p public.chaos_profiles;earned integer;
begin
 d:=chaos_private.life_snapshot_v20(r,u);select * into p from public.chaos_profiles where id=u;
 select * into w from chaos_private.round_wagers where room_id=r.id and match_no=r.match_no and round_no=r.round_no and player=u;
 select coalesce(sum(greatest(0,payout-stake)),0) into earned from chaos_private.round_wagers where player=u and created_at>=(date_trunc('day',clock_timestamp() at time zone 'UTC') at time zone 'UTC');
 return d||jsonb_build_object('wager',jsonb_build_object('active',r.wager_enabled and r.phase='select' and clock_timestamp()<r.wager_until,
 'until',r.wager_until,'ready',case when u=r.host then r.host_wager_ready else r.guest_wager_ready end,
 'other_ready',case when u=r.host then r.guest_wager_ready else r.host_wager_ready end,
 'stake',coalesce(w.stake,0),'payout',w.payout,'outcome',w.outcome,
 'limit',least(case when p.xp/250+1>=6 then 100 when p.xp/250+1>=4 then 50 when p.xp/250+1>=2 then 25 else 10 end,greatest(0,500-earned)),
 'history',coalesce((select jsonb_agg(to_jsonb(x)) from(select stake,payout,outcome,settled_at from chaos_private.round_wagers where player=u and payout is not null order by settled_at desc limit 10)x),'[]'::jsonb)));
end;$$;
alter function public.chaos_action(text,text,text,integer,integer,integer) rename to chaos_action_v20;
alter function public.chaos_action_v20(text,text,text,integer,integer,integer) set schema chaos_private;
create function public.chaos_action(action text,room_code text default null,player_name text default null,choice integer default null,expected_round integer default null,expected_match integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();r public.chaos_rooms;d jsonb;
begin
 if action in('choose','confirm') then
  select * into r from public.chaos_rooms where code=upper(trim(room_code)) for update;
  if r.id is null or(u<>r.host and u is distinct from r.guest) then raise exception 'Kein Zugriff auf diesen Raum';end if;
  if r.wager_enabled and r.phase='select' and clock_timestamp()<r.wager_until then raise exception 'Wähle zuerst deinen Einsatz oder spiele ohne Einsatz';end if;
 end if;
 d:=chaos_private.chaos_action_v20(action,room_code,player_name,choice,expected_round,expected_match);
 if d->'room'->>'id' is not null then
  select * into r from public.chaos_rooms where id=(d->'room'->>'id')::uuid;
  return chaos_private.life_snapshot(r,u)||jsonb_build_object('error',d->'error');
 end if;return d;
end;$$;
create function public.chaos_wager(action text,room_code text,amount integer default 0,expected_round integer default null,expected_match integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();r public.chaos_rooms;p public.chaos_profiles;earned integer;cap integer;
begin
 select * into r from public.chaos_rooms where code=upper(trim(room_code)) for update;
 if r.id is null or(u<>r.host and u is distinct from r.guest) or r.updated_at<clock_timestamp()-interval '24 hours' then raise exception 'Kein Zugriff auf diesen Raum';end if;
 if action='open' then
  if r.wager_enabled then return chaos_private.life_snapshot(r,u);end if;
  if r.rules_version<>2 or r.phase<>'select' or exists(select 1 from chaos_private.moves where room_id=r.id and match_no=r.match_no and round_no=r.round_no and (player=r.host or not r.is_bot)) then return chaos_private.life_snapshot(r,u);end if;
  update public.chaos_rooms set wager_enabled=true,updated_at=clock_timestamp() where id=r.id returning * into r;
 elsif action='ready' then
  if expected_round is distinct from r.round_no or expected_match is distinct from r.match_no then raise exception 'Runde hat sich geändert';end if;
  if not r.wager_enabled or r.phase<>'select' or clock_timestamp()>=r.wager_until then raise exception 'Einsatzzeit abgelaufen';end if;
  if (u=r.host and r.host_wager_ready) or(u=r.guest and r.guest_wager_ready) then return chaos_private.life_snapshot(r,u);end if;
  select * into p from public.chaos_profiles where id=u for update;
  select coalesce(sum(greatest(0,payout-stake)),0) into earned from chaos_private.round_wagers where player=u and created_at>=(date_trunc('day',clock_timestamp() at time zone 'UTC') at time zone 'UTC');
  cap:=least(case when p.xp/250+1>=6 then 100 when p.xp/250+1>=4 then 50 when p.xp/250+1>=2 then 25 else 10 end,greatest(0,500-earned));
  if amount is null or amount not in(0,10,25,50,100) or amount>cap or amount>p.coins then raise exception 'Einsatz über deinem Guthaben oder Limit';end if;
  insert into chaos_private.round_wagers(room_id,match_no,round_no,player,stake) values(r.id,r.match_no,r.round_no,u,amount);
  update public.chaos_profiles set coins=coins-amount where id=u;
  if u=r.host then r.host_wager_ready:=true;else r.guest_wager_ready:=true;end if;
  if r.host_wager_ready and r.guest_wager_ready then r.wager_until:=clock_timestamp();r.select_until:=clock_timestamp()+interval '10 seconds';end if;
  update public.chaos_rooms set host_wager_ready=r.host_wager_ready,guest_wager_ready=r.guest_wager_ready,wager_until=r.wager_until,select_until=r.select_until,updated_at=clock_timestamp() where id=r.id returning * into r;
 elsif action<>'state' then raise exception 'Ungültige Einsatzaktion';end if;
 return chaos_private.life_snapshot(r,u);
end;$$;
revoke all on function public.chaos_action(text,text,text,integer,integer,integer),public.chaos_wager(text,text,integer,integer,integer) from public,anon;
grant execute on function public.chaos_action(text,text,text,integer,integer,integer),public.chaos_wager(text,text,integer,integer,integer) to authenticated;
revoke all on all functions in schema chaos_private from public,anon,authenticated;
commit;

begin;
alter table public.chaos_profiles add column emote_loadout text[] not null default array['gg','luck','wave','thanks','oops'];
alter table public.chaos_profiles add constraint emote_loadout_length check(cardinality(emote_loadout)=5);
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-salt','emote','Salzstreuer','Eine Prise Salz fürs Chaos.','#b9d6ea',220,0,'salt');
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-clown','emote','Zirkusreif','Die Manege ist eröffnet.','#eda5aa',350,1,'clown');
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-coffee','emote','Erst mal Kaffee','Ganz entspannt. Du bist noch am Aufwärmen.','#dbbc91',180,0,'coffee');
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-cool','emote','Zu cool','Sonnenbrille auf, Chaos an.','#8fd7d4',500,2,'cool');
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-sleep','emote','Schon fertig?','Ein kleines Nickerchen zwischen zwei Zügen.','#a6b8e9',300,1,'sleep');
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-rage','emote','Kurz vorm Ausrasten','Wenn selbst die Arena kurz die Luft anhält.','#eda882',600,2,'rage');
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-love','emote','Chaos mit Herz','Ein Herz für gute Gegner.','#e9a8c2',220,0,'heart');
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-toast','emote','Auf dich!','Ein Toast auf dieses völlig normale Duell.','#e6ca93',400,1,'toast');
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-mind','emote','Gehirn explodiert','Wenn der nächste Zug alle Dimensionen sprengt.','#cdb3ee',900,3,'mind');
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-mic','emote','Mic Drop','Das letzte Wort fällt auf den Arenaboden.','#eccb8f',1500,4,'mic');
insert into chaos_private.styles(id,slot,price,rarity,power_index) select id,slot,price,rarity,power_index from chaos_private.cosmetic_catalog where id in('emote-salt','emote-clown','emote-coffee','emote-cool','emote-sleep','emote-rage','emote-love','emote-toast','emote-mind','emote-mic');
create function public.chaos_emote_loadout(items text[]) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();emote_key text;
begin
 perform 1 from public.chaos_profiles where public.chaos_profiles.id=u for update;
 if not found then raise exception 'Bitte zuerst dein Profil einrichten';end if;
 if items is null or cardinality(items)<>5 or array_ndims(items)<>1 or (select count(distinct x) from unnest(items)x)<>5 then raise exception 'Wähle fünf verschiedene Emotes';end if;
 foreach emote_key in array items loop
  if emote_key is null or(emote_key not in('gg','luck','wave','thanks','oops') and not exists(select 1 from chaos_private.inventory i join chaos_private.styles s on s.id=i.item where i.player=u and s.slot='emote' and s.id=emote_key)) then raise exception 'Emote nicht freigeschaltet';end if;
 end loop;
 update public.chaos_profiles set emote_loadout=items where public.chaos_profiles.id=u;
 return public.chaos_social('state');
end;$$;
do $$declare definition text;begin
 definition:=pg_get_functiondef('public.chaos_emote(text,text)'::regprocedure);
 if position('not in(''wave'',''gg'')' in definition)=0 then raise exception 'Unerwartete Emote-Funktion';end if;
 execute replace(definition,'not in(''wave'',''gg'')','not in(''wave'',''gg'',''luck'',''thanks'',''oops'')');
end;$$;
revoke all on function public.chaos_emote_loadout(text[]) from public,anon;
grant execute on function public.chaos_emote_loadout(text[]) to authenticated;
revoke all on all functions in schema chaos_private from public,anon,authenticated;
commit;

begin;
-- Preserve settled round-bet history, refund pending legacy escrow once, and
-- disable legacy per-round windows. Already chosen cards and earned XP stay intact.
do $$declare r public.chaos_rooms;w chaos_private.round_wagers;begin
 for r in select x.* from public.chaos_rooms x where x.wager_enabled or exists(select 1 from chaos_private.round_wagers b where b.room_id=x.id and b.payout is null) order by x.id for update loop
  perform id from public.chaos_profiles where id in(r.host,r.guest) order by id for update;
  for w in select * from chaos_private.round_wagers where room_id=r.id and payout is null for update loop
   update public.chaos_profiles set coins=coins+w.stake where id=w.player;
   update chaos_private.round_wagers set payout=w.stake,outcome='refund',settled_at=clock_timestamp() where room_id=w.room_id and match_no=w.match_no and round_no=w.round_no and player=w.player;
  end loop;
  update public.chaos_rooms set wager_enabled=false,wager_until=null,host_wager_ready=false,guest_wager_ready=false,
   select_until=case when phase='select' and wager_until>clock_timestamp() then clock_timestamp()+interval '10 seconds' else select_until end,
   updated_at=clock_timestamp() where id=r.id;
 end loop;
end;$$;
create table chaos_private.match_wagers(
 room_id uuid not null,match_no integer not null,
 player uuid not null references public.chaos_profiles on delete cascade,
 stake integer not null check(stake in(0,10,25,50,100)),
 payout integer check(payout>=0),outcome text check(outcome in('win','loss','draw','refund')),
 created_at timestamptz not null default clock_timestamp(),settled_at timestamptz,
 primary key(room_id,match_no,player)
);
alter table chaos_private.match_wagers enable row level security;
revoke all on chaos_private.match_wagers from public,anon,authenticated;
create index match_wagers_player_time on chaos_private.match_wagers(player,created_at desc);
create function chaos_private.wager_profit(u uuid) returns integer language sql volatile set search_path='' as $$
 select (coalesce((select sum(greatest(0,payout-stake)) from chaos_private.match_wagers where player=u and created_at>=(date_trunc('day',clock_timestamp() at time zone 'UTC') at time zone 'UTC')),0)
 +coalesce((select sum(greatest(0,payout-stake)) from chaos_private.round_wagers where player=u and created_at>=(date_trunc('day',clock_timestamp() at time zone 'UTC') at time zone 'UTC')),0))::integer;
$$;
create or replace function chaos_private.wager_round() returns trigger language plpgsql security definer set search_path='' as $$
declare w chaos_private.match_wagers;pay integer;outc text;active boolean;eligible boolean;
begin
 if tg_op='DELETE' then
  perform id from public.chaos_profiles where id in(old.host,old.guest) order by id for update;
  for w in select * from chaos_private.match_wagers where room_id=old.id and payout is null for update loop
   update public.chaos_profiles set coins=coins+w.stake where id=w.player;
   update chaos_private.match_wagers set payout=w.stake,outcome='refund',settled_at=clock_timestamp() where room_id=w.room_id and match_no=w.match_no and player=w.player;
  end loop;return old;
 end if;
 eligible:=not new.is_bot and new.campaign_stage is null and new.game_mode in('duel','ranked') and new.guest is not null;
 if not eligible then new.wager_enabled:=false;new.wager_until:=null;end if;
 if eligible and new.wager_enabled and new.phase='select' and new.round_no=1 and (not old.wager_enabled or old.match_no<>new.match_no) then
  new.wager_until:=greatest(clock_timestamp(),coalesce(new.battle_starts_at,clock_timestamp()))+interval '10 seconds';
  new.select_until:=new.wager_until+interval '10 seconds';
  new.host_wager_ready:=false;new.guest_wager_ready:=false;
 elsif new.phase='select' and new.round_no>1 then new.wager_until:=null;end if;
 if new.phase='finished' and (old.phase<>'finished' or old.match_no<>new.match_no) then
  perform id from public.chaos_profiles where id in(new.host,new.guest) order by id for update;
  active:=(select count(*)>=3 from chaos_private.moves where room_id=new.id and match_no=new.match_no and player=new.host)
   and (select count(*)>=3 from chaos_private.moves where room_id=new.id and match_no=new.match_no and player=new.guest);
  for w in select * from chaos_private.match_wagers where room_id=new.id and match_no=new.match_no and payout is null for update loop
   if not eligible or not active or new.end_reason is null or new.end_reason in('abandoned','inactivity') then pay:=w.stake;outc:='refund';
   elsif new.match_winner is null then pay:=w.stake;outc:='draw';
   elsif new.match_winner=w.player then pay:=w.stake*2;outc:='win';
   else pay:=0;outc:='loss';end if;
   update public.chaos_profiles set coins=coins+pay where id=w.player;
   update chaos_private.match_wagers set payout=pay,outcome=outc,settled_at=clock_timestamp() where room_id=w.room_id and match_no=w.match_no and player=w.player;
  end loop;
 end if;
 return new;
end;$$;
create or replace function chaos_private.life_snapshot(r public.chaos_rooms,u uuid) returns jsonb language plpgsql set search_path='' as $$
declare d jsonb;w chaos_private.match_wagers;eligible boolean;
begin
 d:=chaos_private.life_snapshot_v20(r,u);
 eligible:=not r.is_bot and r.campaign_stage is null and r.game_mode in('duel','ranked') and r.guest is not null;
 select * into w from chaos_private.match_wagers where room_id=r.id and match_no=r.match_no and player=u;
 return d||jsonb_build_object('wager',jsonb_build_object('mode','match','eligible',eligible,
 'active',eligible and r.wager_enabled and r.phase='select' and r.round_no=1 and clock_timestamp()<r.wager_until,
 'until',r.wager_until,'ready',case when u=r.host then r.host_wager_ready else r.guest_wager_ready end,
 'other_ready',case when u=r.host then r.guest_wager_ready else r.host_wager_ready end,
 'stake',coalesce(w.stake,0),'payout',w.payout,'outcome',w.outcome,
 'limit',least(100,greatest(0,500-chaos_private.wager_profit(u))),
 'history',coalesce((select jsonb_agg(to_jsonb(x)) from(select stake,payout,outcome,settled_at from chaos_private.match_wagers where player=u and payout is not null order by settled_at desc limit 10)x),'[]'::jsonb)));
end;$$;
create or replace function public.chaos_wager(action text,room_code text,amount integer default 0,expected_round integer default null,expected_match integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();r public.chaos_rooms;p public.chaos_profiles;cap integer;eligible boolean;
begin
 select * into r from public.chaos_rooms where code=upper(trim(room_code)) for update;
 if r.id is null or(u<>r.host and u is distinct from r.guest) or r.updated_at<clock_timestamp()-interval '24 hours' then raise exception 'Kein Zugriff auf diesen Raum';end if;
 eligible:=not r.is_bot and r.campaign_stage is null and r.game_mode in('duel','ranked') and r.guest is not null;
 if action='open' then
  if not eligible or r.wager_enabled or r.rules_version<>2 or r.phase<>'select' or r.round_no<>1
   or exists(select 1 from chaos_private.moves where room_id=r.id and match_no=r.match_no and player in(r.host,r.guest)) then return chaos_private.life_snapshot(r,u);end if;
  update public.chaos_rooms set wager_enabled=true,updated_at=clock_timestamp() where id=r.id returning * into r;
 elsif action='ready' then
  if not eligible then raise exception 'Einsätze gibt es nur in PvP-Duellen';end if;
  if expected_match is distinct from r.match_no then raise exception 'Match hat sich geändert';end if;
  if exists(select 1 from chaos_private.match_wagers where room_id=r.id and match_no=r.match_no and player=u) then return chaos_private.life_snapshot(r,u);end if;
  if expected_round is distinct from 1 or r.round_no<>1 then raise exception 'Einsatz nur vor der ersten Runde';end if;
  if not r.wager_enabled or r.phase<>'select' or clock_timestamp()>=r.wager_until then raise exception 'Einsatzzeit abgelaufen';end if;
  select * into p from public.chaos_profiles where id=u for update;
  cap:=least(100,greatest(0,500-chaos_private.wager_profit(u)));
  if amount is null or amount not in(0,10,25,50,100) or amount>cap or amount>p.coins then raise exception 'Nicht genug Coins oder Tageslimit erreicht';end if;
  insert into chaos_private.match_wagers(room_id,match_no,player,stake) values(r.id,r.match_no,u,amount);
  update public.chaos_profiles set coins=coins-amount where id=u;
  if u=r.host then r.host_wager_ready:=true;else r.guest_wager_ready:=true;end if;
  if r.host_wager_ready and r.guest_wager_ready then r.wager_until:=clock_timestamp();r.select_until:=clock_timestamp()+interval '10 seconds';end if;
  update public.chaos_rooms set host_wager_ready=r.host_wager_ready,guest_wager_ready=r.guest_wager_ready,wager_until=r.wager_until,select_until=r.select_until,updated_at=clock_timestamp() where id=r.id returning * into r;
 elsif action<>'state' then raise exception 'Ungültige Einsatzaktion';end if;
 return chaos_private.life_snapshot(r,u);
end;$$;
revoke all on function public.chaos_wager(text,text,integer,integer,integer) from public,anon;
grant execute on function public.chaos_wager(text,text,integer,integer,integer) to authenticated;
revoke all on all functions in schema chaos_private from public,anon,authenticated;
commit;

begin;
-- Existing matches retain seven-card rules; new matches use the balanced eight.
alter table public.chaos_rooms add column power_count integer not null default 7 check(power_count in(7,8));
alter table public.chaos_rooms alter column power_count set default 8;
create function chaos_private.beats_for(a integer,b integer,n integer) returns boolean language sql immutable set search_path='' as $$
 select case when n=7 then chaos_private.beats(a,b) else case a
 when 0 then b in(2,5,7) when 1 then b in(0,6,7) when 2 then b in(1,3,7)
 when 3 then b in(0,1,4) when 4 then b in(1,2,6) when 5 then b in(2,3,4)
 when 6 then b in(0,3,5) when 7 then b in(4,5,6) else false end end;
$$;
do $$declare c record;definition text;begin
 for c in select n.nspname,t.relname,x.conname,pg_get_constraintdef(x.oid) d from pg_constraint x join pg_class t on t.oid=x.conrelid join pg_namespace n on n.oid=t.relnamespace where x.contype='c' and (n.nspname,t.relname) in(('public','chaos_rooms'),('chaos_private','moves'),('chaos_private','styles'),('chaos_private','cosmetic_catalog')) loop
  if c.d like '%<= 6%' then
   execute format('alter table %I.%I drop constraint %I',c.nspname,c.relname,c.conname);
   execute format('alter table %I.%I add constraint %I %s',c.nspname,c.relname,c.conname,replace(c.d,'<= 6','<= 7'));
  end if;
 end loop;
 definition:=pg_get_functiondef('chaos_private.advance_lives_v8(public.chaos_rooms)'::regprocedure);
 if position('if a<>b then' in definition)=0 then raise exception 'Unexpected round engine';end if;
 definition:=replace(definition,'random()*7','random()*r.power_count');
 definition:=replace(definition,'if a<>b then','if chaos_private.beats_for(a,b,r.power_count) or chaos_private.beats_for(b,a,r.power_count) then');
 definition:=replace(definition,'chaos_private.beats(a,b)','chaos_private.beats_for(a,b,r.power_count)');execute definition;
 definition:=pg_get_functiondef('chaos_private.chaos_action_v8(text,text,text,integer,integer,integer)'::regprocedure);
 if position('choice not between 0 and 6' in definition)=0 then raise exception 'Unexpected choice validation';end if;
 definition:=replace(definition,'choice not between 0 and 6','choice not between 0 and (r.power_count-1)');
 definition:=replace(definition,'r.phase:=''select'';','r.power_count:=8;r.phase:=''select'';');execute definition;
 definition:=pg_get_functiondef('chaos_private.advance_lives_v20(public.chaos_rooms)'::regprocedure);
 definition:=replace(definition,'r.match_no:=r.match_no+1;','r.power_count:=8;r.match_no:=r.match_no+1;');execute definition;
 definition:=pg_get_functiondef('chaos_private.bot_choice(public.chaos_rooms)'::regprocedure);
 definition:=replace(definition,'generate_series(0,6)','generate_series(0,r.power_count-1)');
 definition:=replace(definition,'chaos_private.beats(n,predicted)','chaos_private.beats_for(n,predicted,r.power_count)');
 definition:=replace(definition,'random()*7','random()*r.power_count');execute definition;
 definition:=pg_get_functiondef('public.chaos_collection(text,integer,text,text)'::regprocedure);
 definition:=replace(definition,'power_index not between 0 and 6','power_index not between 0 and 7');execute definition;
 definition:=pg_get_functiondef('chaos_private.record_journal()'::regprocedure);
 definition:=replace(definition,'generate_series(0,6)','generate_series(0,7)');execute definition;
 definition:=pg_get_functiondef('public.chaos_journal(text,text)'::regprocedure);
 definition:=replace(definition,'generate_series(0,6)','generate_series(0,7)');execute definition;
end;$$;
create function chaos_private.match_card_rules() returns trigger language plpgsql set search_path='' as $$
begin
 if new.rules_version=2 and ((old.phase='lobby' and new.phase='select') or old.match_no<>new.match_no) then new.power_count:=8;end if;
 return new;
end;$$;
create trigger a0_match_card_rules before update on public.chaos_rooms for each row execute function chaos_private.match_card_rules();
revoke all on all functions in schema chaos_private from public,anon,authenticated;
commit;

begin;
-- Additive cosmetic catalogue only; existing ownership, prices and combat rules are unchanged.
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model,power_index,theme) values
('skin-sniper-frost','card','Frostjäger','Frostjäger — eigenes Sniper-Design. Rein kosmetisch, gleiche Kampfregeln.','#83d9f6',320,1,'sniper',7,'sniper-frost'),
('skin-sniper-jade','card','Jadedrache','Jadedrache — eigenes Sniper-Design. Rein kosmetisch, gleiche Kampfregeln.','#7be2b4',650,2,'sniper',7,'sniper-jade'),
('skin-sniper-seraph','card','Seraphenschuss','Seraphenschuss — eigenes Sniper-Design. Rein kosmetisch, gleiche Kampfregeln.','#f2d693',1100,3,'sniper',7,'sniper-seraph'),
('skin-sniper-void','card','Leerenjäger','Leerenjäger — eigenes Sniper-Design. Rein kosmetisch, gleiche Kampfregeln.','#c6a1f3',1900,4,'sniper',7,'sniper-void'),
('outfit-asc-paladin','outfit','Solaris-Wache','Solaris-Wache — neue Silhouette mit eigener Rüstung und Stoffdetails. Rein kosmetisch.','#d5b67a',950,3,'paladin',null,null),
('outfit-asc-ronin','outfit','Schattenronin','Schattenronin — neue Silhouette mit eigener Rüstung und Stoffdetails. Rein kosmetisch.','#944b60',850,3,'ronin',null,null),
('outfit-asc-astral','outfit','Astralweber','Astralweber — neue Silhouette mit eigener Rüstung und Stoffdetails. Rein kosmetisch.','#6795ba',750,2,'astral',null,null),
('outfit-asc-specter','outfit','Nachtklinge','Nachtklinge — neue Silhouette mit eigener Rüstung und Stoffdetails. Rein kosmetisch.','#6b8b88',1400,4,'specter',null,null)
on conflict(id) do nothing;
insert into chaos_private.styles(id,slot,price,rarity,power_index) select id,slot,price,rarity,power_index from chaos_private.cosmetic_catalog where id in('skin-sniper-frost','skin-sniper-jade','skin-sniper-seraph','skin-sniper-void','outfit-asc-paladin','outfit-asc-ronin','outfit-asc-astral','outfit-asc-specter') on conflict(id) do nothing;
commit;
