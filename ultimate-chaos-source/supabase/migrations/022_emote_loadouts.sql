begin;
alter table public.chaos_profiles add column emote_loadout text[] not null default array['gg','luck','wave','thanks','oops'];
alter table public.chaos_profiles add constraint emote_loadout_length check(cardinality(emote_loadout)=5);
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-salt','emote','Salzstreuer','Eine Prise Salz fürs Chaos.','#b9d6ea',220,0,'salt');
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-clown','emote','Zirkusreif','Die Manege ist eröffnet.','#eda5aa',350,1,'clown');
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-coffee','emote','Erst mal Kaffee','Ganz entspannt. Du bist noch am Aufwärmen.','#dbbc91',180,0,'coffee');
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-cool','emote','Zu cool','Sonnenbrille auf, Chaos an.','#8fd7d4',500,2,'cool');
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-sleep','emote','Schon fertig?','Ein kleines Nickerchen zwischen zwei Zügen.','#a6b8e9',300,1,'sleep');
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-rage','emote','Kurz vorm Ausrasten','Wenn selbst die Arena kurz die Luft anhält.','#eda882',600,2,'rage');
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-love','emote','Chaos mit Herz','Ein Herz für gute Gegner.','#e9a8c2',220,0,'heart');
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-toast','emote','Auf dich!','Ein Toast auf dieses völlig normale Duell.','#e6ca93',400,1,'toast');
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-mind','emote','Gehirn explodiert','Wenn der nächste Zug alle Dimensionen sprengt.','#cdb3ee',900,3,'mind');
insert into chaos_private.cosmetic_catalog(id,slot,name,description,color,price,rarity,model) values('emote-mic','emote','Mic Drop','Das letzte Wort fällt auf den Arenaboden.','#eccb8f',1500,4,'mic');
insert into chaos_private.styles(id,slot,price,rarity,power_index) select id,slot,price,rarity,power_index from chaos_private.cosmetic_catalog where id in('emote-salt','emote-clown','emote-coffee','emote-cool','emote-sleep','emote-rage','emote-love','emote-toast','emote-mind','emote-mic');
create function public.chaos_emote_loadout(items text[]) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();emote_key text;
begin
 perform 1 from public.chaos_profiles where public.chaos_profiles.id=u for update;
 if not found then raise exception 'Bitte zuerst dein Profil einrichten';end if;
 if items is null or cardinality(items)<>5 or array_ndims(items)<>1 or (select count(distinct x) from unnest(items)x)<>5 then raise exception 'Wähle fünf verschiedene Emotes';end if;
 foreach emote_key in array items loop
  if emote_key is null or(emote_key not in('gg','luck','wave','thanks','oops') and not exists(select 1 from chaos_private.inventory i join chaos_private.styles s on s.id=i.item where i.player=u and s.slot='emote' and s.id=emote_key)) then raise exception 'Emote nicht freigeschaltet';end if;
 end loop;
 update public.chaos_profiles set emote_loadout=items where public.chaos_profiles.id=u;
 return public.chaos_social('state');
end;$$;
do $$declare definition text;begin
 definition:=pg_get_functiondef('public.chaos_emote(text,text)'::regprocedure);
 if position('not in(''wave'',''gg'')' in definition)=0 then raise exception 'Unerwartete Emote-Funktion';end if;
 execute replace(definition,'not in(''wave'',''gg'')','not in(''wave'',''gg'',''luck'',''thanks'',''oops'')');
end;$$;
revoke all on function public.chaos_emote_loadout(text[]) from public,anon;
grant execute on function public.chaos_emote_loadout(text[]) to authenticated;
revoke all on all functions in schema chaos_private from public,anon,authenticated;
commit;
