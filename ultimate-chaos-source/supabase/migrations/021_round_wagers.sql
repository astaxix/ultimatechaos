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
