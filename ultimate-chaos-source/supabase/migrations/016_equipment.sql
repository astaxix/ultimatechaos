begin;
alter table chaos_private.styles drop constraint styles_slot_check;
alter table chaos_private.styles add check(slot in('outfit','hat','aura','frame','card','weapon','emote','card-aura','attack','victory'));
alter table chaos_private.styles drop constraint styles_rarity_check;
alter table chaos_private.styles add check(rarity between 0 and 4);
alter table chaos_private.styles add column power_index integer check(power_index between 0 and 6);
insert into chaos_private.styles(id,slot,price,rarity,power_index) select id,slot,price,rarity,power_index from chaos_private.cosmetic_catalog;
alter table public.chaos_profiles add column card_loadouts jsonb not null default '{}';
alter table public.chaos_profiles drop constraint chaos_profiles_frame_check;
alter table public.chaos_profiles add check(length(frame) between 1 and 80);
do $$declare definition text;begin
 definition:=pg_get_functiondef('chaos_private.chaos_style_v6(text,jsonb,text)'::regprocedure);
 if position('elsif k in (''outfit'',''hat'',''aura'')' in definition)=0 then raise exception 'Unexpected appearance engine';end if;
 definition:=replace(definition,'k in (''outfit'',''hat'',''aura'')','k in (''outfit'',''hat'',''aura'',''weapon'',''emote'',''victory'')');
 definition:=replace(definition,'v is distinct from p.appearance->>k','v is distinct from coalesce(p.appearance->>k,case when k=''outfit'' then ''starter'' else ''none'' end)');execute definition;
end;$$;
alter function public.chaos_style(text,jsonb,text) rename to chaos_style_v7;
alter function public.chaos_style_v7(text,jsonb,text) set schema chaos_private;
revoke all on function chaos_private.chaos_style_v7(text,jsonb,text) from public,anon,authenticated;
create function public.chaos_style(action text,appearance jsonb default null,item_id text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();s chaos_private.styles;p public.chaos_profiles;k text;
begin
 if action='equip' then
  select * into s from chaos_private.styles where id=item_id;
  if item_id in('weapon:reset','emote:reset','victory:reset') then
   k:=split_part(item_id,':',1);update public.chaos_profiles set appearance=jsonb_set(public.chaos_profiles.appearance,array[k],'"none"') where id=u;return public.chaos_social('state');
  elsif s.slot in('weapon','emote','victory') then
   select * into p from public.chaos_profiles where id=u for update;
   if not exists(select 1 from chaos_private.inventory where player=u and item=s.id) then raise exception 'Diesen Style besitzt du nicht';end if;
   update public.chaos_profiles set appearance=jsonb_set(public.chaos_profiles.appearance,array[s.slot],to_jsonb(s.id)) where id=u;return public.chaos_social('state');
  elsif s.slot in('card-aura','attack') or(s.slot='card' and s.power_index is not null) then raise exception 'Bitte bei der gewünschten Macht in der Sammlung ausrüsten';end if;
 end if;
 return chaos_private.chaos_style_v7(action,appearance,item_id);
end;$$;
revoke all on function public.chaos_style(text,jsonb,text) from public,anon;
grant execute on function public.chaos_style(text,jsonb,text) to authenticated;
create function public.chaos_collection(action text,power_index integer default null,slot text default null,item_id text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();p public.chaos_profiles;s chaos_private.styles;entry jsonb;expected_slot text;
begin
 select * into p from public.chaos_profiles where id=u for update;if p.id is null then raise exception 'Bitte zuerst dein Profil einrichten';end if;
 if action='equip' then
  if power_index is null or power_index not between 0 and 6 or slot is null or slot not in('skin','aura','effect') then raise exception 'Ungültige Macht oder Ausrüstungsart';end if;
  if item_id is null then raise exception 'Style fehlt';end if;
  if item_id not in('classic','none') then
   select * into s from chaos_private.styles where id=item_id;
   expected_slot:=case slot when 'skin' then 'card' when 'aura' then 'card-aura' else 'attack' end;
   if s.id is null or s.slot<>expected_slot or(s.power_index is not null and s.power_index<>power_index) or not exists(select 1 from chaos_private.inventory where player=u and item=s.id) then raise exception 'Dieser Style ist für diese Macht nicht freigeschaltet';end if;
  elsif (slot='skin' and item_id<>'classic')or(slot<>'skin' and item_id<>'none') then raise exception 'Ungültiger Standardstyle';end if;
  entry:=coalesce(p.card_loadouts->power_index::text,'{}'::jsonb)||jsonb_build_object(slot,item_id);
  update public.chaos_profiles set card_loadouts=jsonb_set(card_loadouts,array[power_index::text],entry) where id=u;
 elsif action<>'state' then raise exception 'Ungültige Sammlungsaktion';end if;
 return public.chaos_social('state');
end;$$;
revoke all on function public.chaos_collection(text,integer,text,text) from public,anon;
grant execute on function public.chaos_collection(text,integer,text,text) to authenticated;
alter function chaos_private.life_snapshot(public.chaos_rooms,uuid) rename to life_snapshot_v14;
create function chaos_private.life_snapshot(r public.chaos_rooms,u uuid) returns jsonb language plpgsql set search_path='' as $$
declare d jsonb;begin
 d:=chaos_private.life_snapshot_v14(r,u);
 d:=jsonb_set(d,'{players,host,card_loadouts}',coalesce((select card_loadouts from public.chaos_profiles where id=r.host),'{}'::jsonb));
 d:=jsonb_set(d,'{players,guest,card_loadouts}',coalesce((select card_loadouts from public.chaos_profiles where id=r.guest),'{}'::jsonb));
 return d;
end;$$;
revoke all on function chaos_private.life_snapshot(public.chaos_rooms,uuid) from public,anon,authenticated;
commit;
