begin;
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
commit;
