begin;
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
commit;
