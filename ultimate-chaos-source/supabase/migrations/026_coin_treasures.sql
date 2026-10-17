begin;
-- Bonus coin rewards are nested inside the existing coin bucket. Main odds stay unchanged.
create function chaos_private.coin_prize(tier integer,roll integer,amount_roll double precision) returns jsonb language plpgsql immutable set search_path='' as $$
declare cfg jsonb;lo integer;hi integer;rarity integer:=0;kind text:='standard';
begin
 if tier is null or tier not between 0 and 3 or roll is null or roll not between 0 and 9999 or amount_roll is null or not(amount_roll>=0 and amount_roll<1) then raise exception 'Ungültiger Coin-Zufallswert';end if;
 cfg:='[{"rare_weight":800,"mythic_weight":40,"rare":[300,650],"mythic":[2500,5000]},{"rare_weight":1200,"mythic_weight":80,"rare":[700,1400],"mythic":[5000,9000]},{"rare_weight":1800,"mythic_weight":150,"rare":[1600,3200],"mythic":[10000,18000]},{"rare_weight":2500,"mythic_weight":300,"rare":[3500,6500],"mythic":[20000,35000]}]'::jsonb->tier;
 if roll<(cfg->>'mythic_weight')::integer then
  kind:='mythic';rarity:=4;lo:=(cfg->'mythic'->>0)::integer;hi:=(cfg->'mythic'->>1)::integer;
 elsif roll<(cfg->>'mythic_weight')::integer+(cfg->>'rare_weight')::integer then
  kind:='rare';rarity:=1;lo:=(cfg->'rare'->>0)::integer;hi:=(cfg->'rare'->>1)::integer;
 else lo:=(array[40,100,250,450])[tier+1];hi:=(array[100,250,700,1000])[tier+1];end if;
 return jsonb_build_object('kind','coins','tier',tier,'coin_kind',kind,'rarity',rarity,'coins',lo+floor(amount_roll*(hi-lo+1))::integer);
end;$$;
revoke all on function chaos_private.coin_prize(integer,integer,double precision) from public,anon,authenticated;
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
   reward:=chaos_private.coin_prize(pack_tier,chaos_private.loot_roll(),random());
   amount:=(reward->>'coins')::integer;
   update public.chaos_profiles set coins=coins+amount where id=u;
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
-- Preserve the existing authenticated-only RPC and receipt/idempotency rules.
revoke all on function public.chaos_loot(text,integer,uuid) from public,anon;
grant execute on function public.chaos_loot(text,integer,uuid) to authenticated;
commit;
