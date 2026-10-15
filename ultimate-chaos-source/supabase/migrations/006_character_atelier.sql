begin;
alter table public.chaos_profiles add column if not exists appearance jsonb not null default '{"body":"masculine","skin":"#dba77d","hair":"swept","hairColor":"#30251f","eyes":"#63b5bd","face":"soft","brows":"natural","beard":"none","outfitColor":"#344761","outfit":"starter","hat":"none","aura":"none"}';
alter table chaos_private.inventory drop constraint if exists inventory_item_check;
create table if not exists chaos_private.styles(id text primary key,slot text not null check(slot in ('outfit','hat','aura','frame')),price integer not null check(price>0));
insert into chaos_private.styles values
 ('coat-nocturne','outfit',450),('armor-solstice','outfit',900),('jacket-street','outfit',250),('robe-astral','outfit',550),
 ('hat-beanie','hat',150),('hat-crown','hat',650),('hat-cap','hat',200),('hat-halo','hat',400),
 ('aura-ember','aura',500),('aura-frost','aura',500),('aura-void','aura',1000),
 ('violet','frame',150),('gold','frame',350),('celestial','frame',700) on conflict(id) do nothing;
revoke all on chaos_private.styles from public,anon,authenticated;
alter table chaos_private.inventory add constraint inventory_style_fk foreign key(item) references chaos_private.styles(id);

-- Keep the proven social engine and enrich only already-authorized friend records.
alter function public.chaos_social(text,text,integer,text,uuid,text) rename to chaos_social_v4;
alter function public.chaos_social_v4(text,text,integer,text,uuid,text) set schema chaos_private;
do $$begin execute replace(pg_get_functiondef('chaos_private.chaos_social_v4(text,text,integer,text,uuid,text)'::regprocedure),'chaos_social.friend_code','chaos_social_v4.friend_code');end;$$;
revoke all on function chaos_private.chaos_social_v4(text,text,integer,text,uuid,text) from public,anon,authenticated;
create function public.chaos_social(action text,display_name text default null,avatar_id integer default null,friend_code text default null,target_id uuid default null,item_id text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d jsonb;
begin
 d:=chaos_private.chaos_social_v4(action,display_name,avatar_id,friend_code,target_id,item_id);
 return jsonb_set(d,'{friends}',coalesce((select jsonb_agg(jsonb_set(f,'{profile,appearance}',p.appearance)) from jsonb_array_elements(d->'friends') f join public.chaos_profiles p on p.id=(f->'profile'->>'id')::uuid),'[]'::jsonb));
end;
$$;
revoke all on function public.chaos_social(text,text,integer,text,uuid,text) from public,anon;
grant execute on function public.chaos_social(text,text,integer,text,uuid,text) to authenticated;

create function public.chaos_style(action text,appearance jsonb default null,item_id text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();p public.chaos_profiles;s chaos_private.styles;k text;v text;normalized jsonb;slot_name text;
begin
 select * into p from public.chaos_profiles where id=u for update;
 if p.id is null then raise exception 'Bitte zuerst dein Profil einrichten'; end if;
 if action='appearance' then
  if appearance is null or jsonb_typeof(appearance)<>'object' or octet_length(appearance::text)>2048 then raise exception 'Aussehen ungültig'; end if;
  normalized:=p.appearance;
  for k,v in select key,value from jsonb_each_text(appearance) loop
   if k in ('skin','hairColor','eyes','outfitColor') then
    if v is null or v !~ '^#[a-fA-F0-9]{6}$' then raise exception 'Farbe ungültig'; end if;
   elsif k='body' then
    if v is null or v not in ('masculine','feminine','androgynous') then raise exception 'Körper ungültig'; end if;
   elsif k='hair' then
    if v is null or v not in ('swept','crop','curls','long','bob','braids','bun','bald') then raise exception 'Frisur ungültig'; end if;
   elsif k='face' then
    if v is null or v not in ('soft','angular','round') then raise exception 'Gesicht ungültig'; end if;
   elsif k='brows' then
    if v is null or v not in ('natural','bold') then raise exception 'Augenbrauen ungültig'; end if;
   elsif k='beard' then
    if v is null or v not in ('none','stubble','full') then raise exception 'Bart ungültig'; end if;
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
revoke all on function public.chaos_style(text,jsonb,text) from public,anon;
grant execute on function public.chaos_style(text,jsonb,text) to authenticated;

alter function public.chaos_action(text,text,text,integer,integer,integer) rename to chaos_action_v5;
alter function public.chaos_action_v5(text,text,text,integer,integer,integer) set schema chaos_private;
revoke all on function chaos_private.chaos_action_v5(text,text,text,integer,integer,integer) from public,anon,authenticated;
create function public.chaos_action(action text,room_code text default null,player_name text default null,choice integer default null,expected_round integer default null,expected_match integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d jsonb;h public.chaos_profiles;g public.chaos_profiles;u uuid:=chaos_private.account_uid();
begin
 d:=chaos_private.chaos_action_v5(action,room_code,player_name,choice,expected_round,expected_match);
 if d->>'left'='true' or d->'room' is null then return d; end if;
 select * into h from public.chaos_profiles where id=(d->'room'->>'host')::uuid;
 select * into g from public.chaos_profiles where id=(d->'room'->>'guest')::uuid;
 return d||jsonb_build_object('players',jsonb_build_object('host',jsonb_build_object('appearance',h.appearance,'frame',h.frame,'xp',h.xp),'guest',jsonb_build_object('appearance',g.appearance,'frame',g.frame,'xp',g.xp)),
  'wallet',(select jsonb_build_object('xp',xp,'coins',coins) from public.chaos_profiles where id=u));
end;
$$;
revoke all on function public.chaos_action(text,text,text,integer,integer,integer) from public,anon;
grant execute on function public.chaos_action(text,text,text,integer,integer,integer) to authenticated;
commit;
