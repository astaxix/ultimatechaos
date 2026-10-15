begin;
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
commit;
