begin;
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model,power_index,theme) values
('outfit-umbra-drift','outfit','Umbra Drift','Neuer Premium-Style. Rein kosmetisch.','#716195',950,3,'umbra',null,null),
('outfit-solar-archon','outfit','Sonnenarchon','Neuer Premium-Style. Rein kosmetisch.','#cda965',1600,4,'archon',null,null),
('outfit-mistblade','outfit','Nebelklinge','Neuer Premium-Style. Rein kosmetisch.','#6b9d9c',850,2,'mistblade',null,null),
('outfit-astral-monarch','outfit','Astral Monarch','Neuer Premium-Style. Rein kosmetisch.','#8b78bc',1800,4,'monarch',null,null),
('weapon-moonreaper','weapon','Mondsichel','Neuer Premium-Style. Rein kosmetisch.','#b4c8e6',1100,3,'scythe',null,null),
('weapon-twilight-pair','weapon','Zwielicht-Zwillinge','Neuer Premium-Style. Rein kosmetisch.','#b297e0',950,3,'twins',null,null),
('weapon-star-lance','weapon','Sternenlanze','Neuer Premium-Style. Rein kosmetisch.','#88cfd9',800,2,'spear',null,null),
('weapon-astral-grimoire','weapon','Astral-Grimoire','Neuer Premium-Style. Rein kosmetisch.','#c6a3e7',1400,4,'grimoire',null,null)
on conflict(id) do nothing;
insert into chaos_private.styles(id,slot,price,rarity,power_index) select id,slot,price,rarity,power_index from chaos_private.cosmetic_catalog where id in('outfit-umbra-drift','outfit-solar-archon','outfit-mistblade','outfit-astral-monarch','weapon-moonreaper','weapon-twilight-pair','weapon-star-lance','weapon-astral-grimoire') on conflict(id) do nothing;
alter table chaos_private.packs drop constraint packs_tier_check;alter table chaos_private.packs add check(tier between 0 and 4);
alter table chaos_private.pack_rules drop constraint pack_rules_tier_check;alter table chaos_private.pack_rules add check(tier between 0 and 4);
insert into chaos_private.pack_rules values(4,650,array[0,0,3500,3000,2000,1000,500],150,350);
create or replace function public.chaos_loot(action text,pack_tier integer,request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();p public.chaos_profiles;receipt chaos_private.loot_receipts;rule chaos_private.pack_rules;roll integer;bucket integer;i integer;threshold integer:=0;draw_rarity integer;s chaos_private.styles;reward jsonb;amount integer;qty integer;item_draw chaos_private.consumables;stack integer;
begin
 if request_id is null or pack_tier is null or pack_tier not between 0 and 4 then raise exception 'Truhe ungültig';end if;
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
   reward:=chaos_private.coin_prize(pack_tier,chaos_private.loot_roll(),random());
   amount:=(reward->>'coins')::integer;
   update public.chaos_profiles set coins=coins+amount where id=u;
  else
   draw_rarity:=bucket-3;
   if pack_tier=4 or random()<.2 then
    select * into item_draw from chaos_private.consumables where rarity=draw_rarity order by random() limit 1;
    if item_draw.id is null then raise exception 'Item-Seltenheit nicht eingerichtet';end if;
    stack:=case when pack_tier=4 then 3+floor(random()*3)::int else 1+floor(random()*(1+pack_tier/2))::int end;
    insert into chaos_private.item_stock values(u,item_draw.id,stack) on conflict(player,item) do update set quantity=chaos_private.item_stock.quantity+excluded.quantity;
    reward:=jsonb_build_object('kind','consumable','item',item_draw.id,'quantity',stack,'rarity',draw_rarity,'tier',pack_tier);
   else
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
  end if;
 else raise exception 'Ungültige Truhenaktion';end if;
 insert into chaos_private.loot_receipts values(request_id,u,action,pack_tier,reward,clock_timestamp());
 return public.chaos_social('state')||jsonb_build_object('loot',reward);
end;$$;
revoke all on function public.chaos_loot(text,integer,uuid) from public,anon;grant execute on function public.chaos_loot(text,integer,uuid) to authenticated;
commit;
