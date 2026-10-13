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
