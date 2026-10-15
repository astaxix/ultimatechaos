begin;
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
