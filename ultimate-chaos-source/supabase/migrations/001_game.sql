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
