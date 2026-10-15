begin;
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
commit;
