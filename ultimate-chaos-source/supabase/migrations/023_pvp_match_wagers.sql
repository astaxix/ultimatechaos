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
