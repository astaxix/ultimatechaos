begin;
create table chaos_private.consumables(id text primary key,name text not null,price integer not null check(price>0),rarity integer not null check(rarity between 0 and 4));
insert into chaos_private.consumables values('potion','Heiltrank',60,0),('elixir','Großer Heiltrank',120,1),('joker','Chaos-Joker',600,4),('fireball','Feuerball',200,2),('frost','Frostbombe',140,1),('antidote','Gegengift',70,0),('barrier','Sternenbarriere',220,2),('mirror','Spiegelsiegel',350,3);
create table chaos_private.item_accounts(player uuid primary key references public.chaos_profiles on delete cascade);
create table chaos_private.item_stock(player uuid not null references public.chaos_profiles on delete cascade,item text not null references chaos_private.consumables,quantity integer not null check(quantity between 0 and 1000000),primary key(player,item));
create table chaos_private.item_purchases(id uuid primary key,player uuid not null references public.chaos_profiles on delete cascade,item text not null references chaos_private.consumables,quantity integer not null check(quantity between 1 and 10),price integer not null check(price>0));
create table chaos_private.item_moves(room_id uuid not null references public.chaos_rooms on delete cascade,match_no integer not null,round_no integer not null,player uuid not null,item text not null references chaos_private.consumables,consumed boolean not null default false,primary key(room_id,match_no,round_no,player));
alter table chaos_private.consumables enable row level security;alter table chaos_private.item_accounts enable row level security;alter table chaos_private.item_stock enable row level security;alter table chaos_private.item_purchases enable row level security;alter table chaos_private.item_moves enable row level security;
revoke all on chaos_private.consumables,chaos_private.item_accounts,chaos_private.item_stock,chaos_private.item_purchases,chaos_private.item_moves from public,anon,authenticated;
alter table public.chaos_rooms add column items_enabled boolean not null default false;
alter table public.chaos_rooms alter column items_enabled set default true;
alter table public.chaos_rooms add column host_item text;alter table public.chaos_rooms add column guest_item text;
alter table public.chaos_rooms add column host_burn integer not null default 0 check(host_burn between 0 and 3);alter table public.chaos_rooms add column guest_burn integer not null default 0 check(guest_burn between 0 and 3);
alter table public.chaos_rooms add column host_shield integer not null default 0 check(host_shield between 0 and 1);alter table public.chaos_rooms add column guest_shield integer not null default 0 check(guest_shield between 0 and 1);
alter table public.chaos_rooms add column item_effects jsonb not null default '{}';
create function chaos_private.ensure_items(u uuid) returns void language plpgsql set search_path='' as $$begin
 insert into chaos_private.item_accounts values(u) on conflict do nothing;
 if found then insert into chaos_private.item_stock values(u,'potion',2),(u,'antidote',1) on conflict(player,item) do update set quantity=chaos_private.item_stock.quantity+excluded.quantity;end if;
end;$$;
create function chaos_private.item_inventory(u uuid) returns jsonb language sql set search_path='' as $$select coalesce(jsonb_object_agg(item,quantity),'{}') from chaos_private.item_stock where player=u and quantity>0;$$;
-- Pure resolver: random rolls are server arguments, never chosen by a client.
create function chaos_private.item_outcome(h jsonb,g jsonb,powers integer,hr double precision,gr double precision) returns jsonb language plpgsql immutable set search_path='' as $$
declare hi text:=h->>'item';gi text:=g->>'item';hp integer:=(h->>'hp')::int;gp integer:=(g->>'hp')::int;hm integer:=(h->>'max')::int;gm integer:=(g->>'max')::int;hb integer:=(h->>'burn')::int;gb integer:=(g->>'burn')::int;hs integer:=(h->>'shield')::int;gs integer:=(g->>'shield')::int;hh integer:=0;gh integer:=0;hd integer:=0;gd integer:=0;raw_h integer;raw_g integer;hg boolean;gg boolean;w integer:=0;hf boolean:=false;gf boolean:=false;
begin
 if hr is null or gr is null or not(hr>=0 and hr<1 and gr>=0 and gr<1) then raise exception 'Ungültiger Effekt-Zufallswert';end if;
 hh:=least(hm-hp,case hi when 'potion' then 1 when 'elixir' then 2 when 'antidote' then 1 else 0 end);gh:=least(gm-gp,case gi when 'potion' then 1 when 'elixir' then 2 when 'antidote' then 1 else 0 end);hp:=hp+hh;gp:=gp+gh;
 hg:=hs>0 or coalesce(hi in('potion','elixir','barrier','mirror','joker'),false);gg:=gs>0 or coalesce(gi in('potion','elixir','barrier','mirror','joker'),false);
 if hi='antidote' then hb:=0;end if;if gi='antidote' then gb:=0;end if;
 if hi='joker' and gi is distinct from 'joker' then gd:=1;w:=1;
 elsif gi='joker' and hi is distinct from 'joker' then hd:=1;w:=2;
 elsif hi='joker' and gi='joker' then null;
 elsif hi is null and gi is null then
  if chaos_private.beats_for((h->>'card')::int,(g->>'card')::int,powers) then gd:=1;elsif chaos_private.beats_for((g->>'card')::int,(h->>'card')::int,powers) then hd:=1;end if;
 else
  if hi is null then gd:=1;elsif hi='frost' and hr<.5 then gd:=2;hf:=true;end if;
  if gi is null then hd:=1;elsif gi='frost' and gr<.5 then hd:=2;gf:=true;end if;
 end if;
 raw_h:=hd;raw_g:=gd;
 if hi='mirror' and raw_h>0 and gi is distinct from 'joker' then gd:=gd+1;end if;if gi='mirror' and raw_g>0 and hi is distinct from 'joker' then hd:=hd+1;end if;
 if hg and gi is distinct from 'joker' then hd:=0;end if;if gg and hi is distinct from 'joker' then gd:=0;end if;
 if hb>0 then if not hg then hd:=hd+1;end if;hb:=hb-1;end if;if gb>0 then if not gg then gd:=gd+1;end if;gb:=gb-1;end if;
 if hi='fireball' and hr<.5 and not gg then gb:=3;hf:=true;end if;if gi='fireball' and gr<.5 and not hg then hb:=3;gf:=true;end if;
 hs:=case when hi='barrier' then 1 else greatest(0,hs-1) end;gs:=case when gi='barrier' then 1 else greatest(0,gs-1) end;
 hd:=least(hp,hd);gd:=least(gp,gd);
 if hi is distinct from 'joker' and gi is distinct from 'joker' then w:=case when gd>hd then 1 when hd>gd then 2 else 0 end;end if;
 return jsonb_build_object('host_hp',hp-hd,'guest_hp',gp-gd,'host_burn',hb,'guest_burn',gb,'host_shield',hs,'guest_shield',gs,'host_damage',hd,'guest_damage',gd,'host_heal',hh,'guest_heal',gh,'host_item',hi,'guest_item',gi,'host_proc',hf,'guest_proc',gf,'winner',w);
end;$$;
create function chaos_private.resolve_items(r public.chaos_rooms,a integer,b integer) returns public.chaos_rooms language plpgsql set search_path='' as $$
declare hi text;gi text;im chaos_private.item_moves;d jsonb;
begin
 for im in select * from chaos_private.item_moves where room_id=r.id and match_no=r.match_no and round_no=r.round_no order by player for update loop
  if not im.consumed and (select count(*) from chaos_private.item_moves where room_id=r.id and match_no=r.match_no and player=im.player and consumed)<3 and (im.item<>'joker' or not exists(select 1 from chaos_private.item_moves where room_id=r.id and match_no=r.match_no and player=im.player and item='joker' and consumed)) then
   update chaos_private.item_stock set quantity=quantity-1 where player=im.player and item=im.item and quantity>0;
   if found then update chaos_private.item_moves set consumed=true where room_id=r.id and match_no=r.match_no and round_no=r.round_no and player=im.player;if im.player=r.host then hi:=im.item;else gi:=im.item;end if;end if;
  end if;
 end loop;
 d:=chaos_private.item_outcome(jsonb_build_object('hp',r.host_hp,'max',r.host_max_hp,'burn',r.host_burn,'shield',r.host_shield,'card',a,'item',hi),jsonb_build_object('hp',r.guest_hp,'max',r.guest_max_hp,'burn',r.guest_burn,'shield',r.guest_shield,'card',b,'item',gi),r.power_count,random(),random());
 r.host_hp:=(d->>'host_hp')::int;r.guest_hp:=(d->>'guest_hp')::int;r.host_burn:=(d->>'host_burn')::int;r.guest_burn:=(d->>'guest_burn')::int;r.host_shield:=(d->>'host_shield')::int;r.guest_shield:=(d->>'guest_shield')::int;r.host_item:=hi;r.guest_item:=gi;r.item_effects:=d;
 r.winner:=case(d->>'winner')::int when 1 then r.host when 2 then r.guest else null end;if r.winner=r.host then r.host_score:=r.host_score+1;elsif r.winner=r.guest then r.guest_score:=r.guest_score+1;end if;
 return r;
end;$$;
-- Extend the versioned engine, retaining every old match's original rules.
do $$declare def text;old_block text;st integer;en integer;begin
 def:=pg_get_functiondef('chaos_private.advance_lives_v8(public.chaos_rooms)'::regprocedure);
 st:=position('  if chaos_private.beats_for(a,b,r.power_count)' in def);en:=position('  r.reveal_at:=resolution' in def);if st=0 or en<=st then raise exception 'Unexpected round engine';end if;
 old_block:=substr(def,st,en-st);def:=replace(def,old_block,'  if r.items_enabled then r:=chaos_private.resolve_items(r,a,b);else'||chr(10)||old_block||'  end if;'||chr(10));
 def:=replace(def,'r.match_winner:=case when r.guest_hp=0 then r.host else r.guest end;','r.match_winner:=case when r.guest_hp=0 and r.host_hp=0 then null when r.guest_hp=0 then r.host else r.guest end;');
 def:=replace(def,'r.round_no:=r.round_no+1;','r.host_item:=null;r.guest_item:=null;r.item_effects:=''{}'';r.round_no:=r.round_no+1;');execute def;
 def:=pg_get_functiondef('chaos_private.chaos_action_v8(text,text,text,integer,integer,integer)'::regprocedure);
 def:=replace(def,'host_hp=r.host_hp,','host_item=r.host_item,guest_item=r.guest_item,host_burn=r.host_burn,guest_burn=r.guest_burn,host_shield=r.host_shield,guest_shield=r.guest_shield,item_effects=r.item_effects,items_enabled=r.items_enabled,host_hp=r.host_hp,');
 def:=replace(def,'r.host_hp:=r.host_max_hp;','r.items_enabled:=r.game_mode<>''ranked'';r.host_burn:=0;r.guest_burn:=0;r.host_shield:=0;r.guest_shield:=0;r.host_item:=null;r.guest_item:=null;r.item_effects:=''{}'';r.host_hp:=r.host_max_hp;');execute def;
 def:=pg_get_functiondef('chaos_private.advance_lives_v20(public.chaos_rooms)'::regprocedure);def:=replace(def,'r.endless_wave:=r.endless_wave+1;','r.items_enabled:=true;r.host_burn:=0;r.guest_burn:=0;r.host_shield:=0;r.guest_shield:=0;r.host_item:=null;r.guest_item:=null;r.item_effects:=''{}'';r.endless_wave:=r.endless_wave+1;');execute def;
end;$$;
create function chaos_private.item_room_policy() returns trigger language plpgsql set search_path='' as $$begin if new.game_mode='ranked' then new.items_enabled:=false;end if;return new;end;$$;
create trigger a1_item_room_policy before insert or update on public.chaos_rooms for each row execute function chaos_private.item_room_policy();
alter function chaos_private.life_snapshot(public.chaos_rooms,uuid) rename to life_snapshot_v26;
create function chaos_private.life_snapshot(r public.chaos_rooms,u uuid) returns jsonb language plpgsql set search_path='' as $$declare d jsonb;mine text;used integer;joker_used boolean;begin
 d:=chaos_private.life_snapshot_v26(r,u);perform chaos_private.ensure_items(u);
 select item into mine from chaos_private.item_moves where room_id=r.id and match_no=r.match_no and round_no=r.round_no and player=u;
 select count(*)::int,coalesce(bool_or(item='joker'),false) into used,joker_used from chaos_private.item_moves where room_id=r.id and match_no=r.match_no and player=u and consumed;
 return d||jsonb_build_object('items',chaos_private.item_inventory(u),'my_item',case when r.phase='select' then mine else null end,'items_used',used,'joker_used',joker_used);
end;$$;
alter function public.chaos_action(text,text,text,integer,integer,integer) rename to chaos_action_v26;
alter function public.chaos_action_v26(text,text,text,integer,integer,integer) set schema chaos_private;
create function public.chaos_action(action text,room_code text default null,player_name text default null,choice integer default null,expected_round integer default null,expected_match integer default null) returns jsonb language plpgsql security definer set search_path='' as $$declare d jsonb;r public.chaos_rooms;u uuid:=chaos_private.account_uid();begin
 d:=chaos_private.chaos_action_v26(action,room_code,player_name,choice,expected_round,expected_match);
 if action='choose' and d->>'error' is null and d->'room'->>'phase'='select' then
  select * into r from public.chaos_rooms where id=(d->'room'->>'id')::uuid for update;
  delete from chaos_private.item_moves where room_id=r.id and match_no=r.match_no and round_no=r.round_no and player=u and not consumed;
  d:=chaos_private.life_snapshot(r,u);
 end if;return d;
end;$$;
create function public.chaos_items(action text,item_id text default null,quantity integer default 1,quoted_price integer default null,request_id uuid default null,room_code text default null,expected_round integer default null,expected_match integer default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();p public.chaos_profiles;r public.chaos_rooms;c chaos_private.consumables;receipt chaos_private.item_purchases;d jsonb;price integer;
begin
 if not exists(select 1 from public.chaos_profiles where id=u) then raise exception 'Bitte zuerst dein Profil einrichten';end if;perform chaos_private.ensure_items(u);
 if action='choose' then
  select * into r from public.chaos_rooms where code=upper(trim(room_code)) for update;
  if r.id is null or(u<>r.host and u is distinct from r.guest) then raise exception 'Kein Zugriff auf diesen Raum';end if;
  d:=public.chaos_action('ping',r.code);select * into r from public.chaos_rooms where id=r.id for update;
  if not r.items_enabled or r.game_mode='ranked' then raise exception 'Items sind in diesem Match nicht verfügbar';end if;
  if r.phase<>'select' or clock_timestamp()>=r.select_until or expected_round is distinct from r.round_no or expected_match is distinct from r.match_no then raise exception 'Runde hat sich geändert';end if;
  if coalesce((d->'wager'->>'active')::boolean,false) then raise exception 'Wähle zuerst deinen Einsatz';end if;
  if(u=r.host and r.host_confirmed)or(u=r.guest and r.guest_confirmed) then raise exception 'Auswahl bereits bestätigt';end if;
  if not exists(select 1 from chaos_private.item_stock where player=u and item=item_id and item_stock.quantity>0) then raise exception 'Dieses Item besitzt du nicht';end if;
  if(select count(*) from chaos_private.item_moves where room_id=r.id and match_no=r.match_no and player=u and consumed)>=3 then raise exception 'Drei Items pro Match sind bereits verbraucht';end if;
  if item_id='joker' and exists(select 1 from chaos_private.item_moves where room_id=r.id and match_no=r.match_no and player=u and item='joker' and consumed) then raise exception 'Joker bereits in diesem Match verwendet';end if;
  insert into chaos_private.item_moves values(r.id,r.match_no,r.round_no,u,item_id,false) on conflict(room_id,match_no,round_no,player) do update set item=excluded.item;
  insert into chaos_private.moves values(r.id,r.match_no,r.round_no,u,0) on conflict(room_id,match_no,round_no,player) do update set choice=0;
  update public.chaos_rooms set host_locked=case when host=u then true else host_locked end,guest_locked=case when guest=u then true else guest_locked end,host_seen=case when host=u then clock_timestamp() else host_seen end,guest_seen=case when guest=u then clock_timestamp() else guest_seen end,updated_at=clock_timestamp() where id=r.id returning * into r;
  return chaos_private.life_snapshot(r,u);
 elsif action='buy' then
  if request_id is null or quantity is null or quantity not between 1 and 10 then raise exception 'Ungültiger Item-Kauf';end if;
  select * into p from public.chaos_profiles where id=u for update;
  select * into receipt from chaos_private.item_purchases where id=request_id;
  if receipt.id is not null then if receipt.player<>u or receipt.item is distinct from item_id or receipt.quantity<>quantity then raise exception 'Kauf-ID ungültig';end if;
  else
   select * into c from chaos_private.consumables where id=item_id;if c.id is null then raise exception 'Item nicht gefunden';end if;price:=c.price*quantity;
   if quoted_price is distinct from price then raise exception 'Preis hat sich geändert';end if;if p.coins<price then raise exception 'Nicht genug Chaos Coins';end if;
   update public.chaos_profiles set coins=coins-price where id=u;
   insert into chaos_private.item_stock values(u,item_id,quantity) on conflict(player,item) do update set quantity=chaos_private.item_stock.quantity+excluded.quantity;
   insert into chaos_private.item_purchases values(request_id,u,item_id,quantity,price);
  end if;
 elsif action is distinct from 'state' then raise exception 'Ungültige Item-Aktion';end if;
 return jsonb_build_object('stock',chaos_private.item_inventory(u),'catalog',(select jsonb_agg(to_jsonb(x) order by x.price) from chaos_private.consumables x),'state',public.chaos_social('state'));
end;$$;
-- Consumable placeholders are manual participation, but are not Schere plays.
do $$declare def text;old_clause text:='from chaos_private.moves where room_id=new.id and match_no=new.match_no and player=p and choice=power';begin
 def:=pg_get_functiondef('chaos_private.record_journal()'::regprocedure);
 if position(old_clause in def)=0 then raise exception 'Unexpected journal engine';end if;
 def:=replace(def,old_clause,'from chaos_private.moves m where m.room_id=new.id and m.match_no=new.match_no and m.player=p and m.choice=power and not exists(select 1 from chaos_private.item_moves im where im.room_id=m.room_id and im.match_no=m.match_no and im.round_no=m.round_no and im.player=m.player and im.consumed)');execute def;
end;$$;
revoke all on all functions in schema chaos_private from public,anon,authenticated;
revoke all on function public.chaos_action(text,text,text,integer,integer,integer),public.chaos_items(text,text,integer,integer,uuid,text,integer,integer) from public,anon;
grant execute on function public.chaos_action(text,text,text,integer,integer,integer),public.chaos_items(text,text,integer,integer,uuid,text,integer,integer) to authenticated;
commit;
