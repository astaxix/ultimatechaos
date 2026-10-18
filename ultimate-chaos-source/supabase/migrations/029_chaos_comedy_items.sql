begin;
-- Five server-authoritative consumables; existing ownership, receipts and match limits retained.
insert into chaos_private.consumables(id,name,price,rarity)values
('laura-mice','Lauras Mäuseangriff',300,2),
('tyson-cloud','Tyson Duftwolke',100,0),
('wet-rosette','Die feuchte Rosette',180,1),
('maniac','Der Maniac',280,2),
('epstein-flute','Epsteins Flöte',380,3)
on conflict(id)do update set name=excluded.name,price=excluded.price,rarity=excluded.rarity;
create or replace function chaos_private.item_outcome(h jsonb,g jsonb,powers integer,hr double precision,gr double precision) returns jsonb language plpgsql immutable set search_path='' as $$
declare hi text:=h->>'item';gi text:=g->>'item';hp integer:=(h->>'hp')::int;gp integer:=(g->>'hp')::int;hm integer:=(h->>'max')::int;gm integer:=(g->>'max')::int;hb integer:=(h->>'burn')::int;gb integer:=(g->>'burn')::int;hs integer:=(h->>'shield')::int;gs integer:=(g->>'shield')::int;hh integer:=0;gh integer:=0;hd integer:=0;gd integer:=0;raw_h integer;raw_g integer;hg boolean;gg boolean;w integer:=0;hf boolean:=false;gf boolean:=false;
begin
 if hr is null or gr is null or not(hr>=0 and hr<1 and gr>=0 and gr<1) then raise exception 'Ungültiger Effekt-Zufallswert';end if;
 hh:=least(hm-hp,case hi when 'potion' then 1 when 'elixir' then 2 when 'antidote' then 1 when 'wet-rosette' then 1 else 0 end);gh:=least(gm-gp,case gi when 'potion' then 1 when 'elixir' then 2 when 'antidote' then 1 when 'wet-rosette' then 1 else 0 end);hp:=hp+hh;gp:=gp+gh;
 hg:=hs>0 or coalesce(hi in('potion','elixir','barrier','mirror','joker','wet-rosette','epstein-flute'),false);gg:=gs>0 or coalesce(gi in('potion','elixir','barrier','mirror','joker','wet-rosette','epstein-flute'),false);
 if hi in('antidote','wet-rosette') then hb:=0;end if;if gi in('antidote','wet-rosette') then gb:=0;end if;
 if hi='joker' and gi is distinct from 'joker' then gd:=1;w:=1;
 elsif gi='joker' and hi is distinct from 'joker' then hd:=1;w:=2;
 elsif hi='joker' and gi='joker' then null;
 elsif hi is null and gi is null then
  if chaos_private.beats_for((h->>'card')::int,(g->>'card')::int,powers) then gd:=1;elsif chaos_private.beats_for((g->>'card')::int,(h->>'card')::int,powers) then hd:=1;end if;
 else
  if hi is null then gd:=1;elsif hi='frost' and hr<.5 then gd:=2;hf:=true;
  elsif hi='laura-mice' then gd:=mod(floor(hr*8)::int,2)+mod(floor(hr*4)::int,2)+mod(floor(hr*2)::int,2);hf:=gd>0;
  elsif hi='tyson-cloud' then gd:=1;hf:=true;
  elsif hi='maniac' then gd:=case when hr<.25 then 3 when hr<.75 then 1 else 0 end;hf:=gd>0;
  elsif hi='epstein-flute' and hr<.5 then gd:=1;hf:=true;end if;
  if gi is null then hd:=1;elsif gi='frost' and gr<.5 then hd:=2;gf:=true;
  elsif gi='laura-mice' then hd:=mod(floor(gr*8)::int,2)+mod(floor(gr*4)::int,2)+mod(floor(gr*2)::int,2);gf:=hd>0;
  elsif gi='tyson-cloud' then hd:=1;gf:=true;
  elsif gi='maniac' then hd:=case when gr<.25 then 3 when gr<.75 then 1 else 0 end;gf:=hd>0;
  elsif gi='epstein-flute' and gr<.5 then hd:=1;gf:=true;end if;
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

revoke all on function chaos_private.item_outcome(jsonb,jsonb,integer,double precision,double precision)from public,anon,authenticated;
commit;
