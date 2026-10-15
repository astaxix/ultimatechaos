begin;
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
commit;
