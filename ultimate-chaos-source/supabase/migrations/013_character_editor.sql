begin;
-- New free appearance fields; no inventory or account data is replaced.
create or replace function chaos_private.chaos_style_v6(action text,appearance jsonb default null,item_id text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();p public.chaos_profiles;s chaos_private.styles;k text;v text;normalized jsonb;slot_name text;
begin
 select * into p from public.chaos_profiles where id=u for update;
 if p.id is null then raise exception 'Bitte zuerst dein Profil einrichten'; end if;
 if action='appearance' then
  if appearance is null or jsonb_typeof(appearance)<>'object' or octet_length(appearance::text)>2048 then raise exception 'Aussehen ungültig'; end if;
  normalized:=p.appearance;
  for k,v in select key,value from jsonb_each_text(appearance) loop
   if k in ('skin','hairColor','eyes','outfitColor','lipColor','pantsColor','bootColor') then
    if v is null or v !~ '^#[a-fA-F0-9]{6}$' then raise exception 'Farbe ungültig'; end if;
   elsif k='body' then
    if v is null or v not in ('masculine','feminine','androgynous') then raise exception 'Körper ungültig'; end if;
   elsif k='hair' then
    if v is null or v not in ('swept','crop','curls','long','bob','braids','bun','bald','pixie','waves','ponytail','high-pony','twin-tails','mohawk','undercut','dreads','afro','sidebraid','shag','topknot') then raise exception 'Frisur ungültig'; end if;
   elsif k='face' then
    if v is null or v not in ('soft','angular','round') then raise exception 'Gesicht ungültig'; end if;
   elsif k='brows' then
    if v is null or v not in ('natural','bold','arched','straight') then raise exception 'Augenbrauen ungültig'; end if;
   elsif k='beard' then
    if v is null or v not in ('none','stubble','full','goatee','moustache') then raise exception 'Bart ungültig'; end if;
   elsif k='build' then if v is null or v not in('slim','athletic','broad') then raise exception 'Statur ungültig';end if;
   elsif k='height' then if v is null or v not in('short','average','tall') then raise exception 'Größe ungültig';end if;
   elsif k='eyeShape' then if v is null or v not in('almond','round','sharp') then raise exception 'Augenform ungültig';end if;
   elsif k='nose' then if v is null or v not in('small','straight','wide') then raise exception 'Nase ungültig';end if;
   elsif k='mouth' then if v is null or v not in('neutral','smile','serious','full') then raise exception 'Mund ungültig';end if;
   elsif k='freckles' then if v is null or v not in('none','light','many') then raise exception 'Sommersprossen ungültig';end if;
   elsif k='scar' then if v is null or v not in('none','cheek','brow') then raise exception 'Narbe ungültig';end if;
   elsif k='glasses' then if v is null or v not in('none','round','square') then raise exception 'Brille ungültig';end if;
   elsif k='earrings' then if v is null or v not in('none','studs','hoops') then raise exception 'Ohrringe ungültig';end if;
   elsif k in ('outfit','hat','aura') then
    -- Appearance editing cannot grant or equip paid cosmetics.
    if v is distinct from p.appearance->>k then raise exception 'Styles bitte über die Sammlung ausrüsten'; end if;
   else raise exception 'Unbekannte Aussehensoption'; end if;
   normalized:=jsonb_set(normalized,array[k],to_jsonb(v));
  end loop;
  update public.chaos_profiles set appearance=normalized where id=u;
 elsif action='buy' then
  select * into s from chaos_private.styles where id=item_id;
  if s.id is null then raise exception 'Shopartikel nicht gefunden'; end if;
  if exists(select 1 from chaos_private.inventory where player=u and item=item_id) then raise exception 'Artikel gehört dir bereits'; end if;
  if p.coins<s.price then raise exception 'Nicht genügend Coins'; end if;
  insert into chaos_private.inventory values(u,item_id);
  update public.chaos_profiles set coins=coins-s.price where id=u;
 elsif action='equip' then
  if item_id in ('outfit:reset','hat:reset','aura:reset') then
   slot_name:=split_part(item_id,':',1);
   update public.chaos_profiles set appearance=jsonb_set(public.chaos_profiles.appearance,array[slot_name],to_jsonb(case when slot_name='outfit' then 'starter' else 'none' end)) where id=u;
  elsif item_id='basic' then update public.chaos_profiles set frame='basic' where id=u;
  else
   select * into s from chaos_private.styles where id=item_id;
   if s.id is null or not exists(select 1 from chaos_private.inventory where player=u and item=item_id) then raise exception 'Diesen Style besitzt du nicht'; end if;
   if s.slot='frame' then update public.chaos_profiles set frame=s.id where id=u;
   else update public.chaos_profiles set appearance=jsonb_set(public.chaos_profiles.appearance,array[s.slot],to_jsonb(s.id)) where id=u; end if;
  end if;
 elsif action<>'state' then raise exception 'Ungültige Aktion'; end if;
 return public.chaos_social('state');
end;
$$;
revoke all on all functions in schema chaos_private from public,anon,authenticated;
commit;
