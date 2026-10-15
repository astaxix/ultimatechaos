begin;
create table chaos_private.shop_receipts(id uuid primary key,player uuid not null references public.chaos_profiles on delete cascade,item text not null references chaos_private.styles,price integer not null check(price>0),created_at timestamptz not null default clock_timestamp());
alter table chaos_private.shop_receipts enable row level security;
revoke all on chaos_private.shop_receipts from public,anon,authenticated;
create index shop_receipts_player on chaos_private.shop_receipts(player,created_at desc);
create function chaos_private.store_price(item text,base integer) returns integer language sql volatile set search_path='' as $$
 select case when exists(select 1 from chaos_private.cosmetic_catalog where id=item) and get_byte(decode(md5(item||to_char(clock_timestamp() at time zone 'UTC','YYYYMMDD')),'hex'),0)%12=0 then base*4/5 else base end;
$$;
revoke all on function chaos_private.store_price(text,integer) from public,anon,authenticated;
create function public.chaos_store(action text,item_id text default null,quoted_price integer default null,request_id uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();p public.chaos_profiles;s chaos_private.styles;receipt chaos_private.shop_receipts;price integer;
begin
 if action='catalog' then
  return jsonb_build_object('day',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD'),'items',coalesce((select jsonb_agg(jsonb_build_object('id',catalog_item.id,'price',chaos_private.store_price(catalog_item.id,catalog_item.price),'base_price',catalog_item.price,'popularity',coalesce(owned.n,0))) from chaos_private.styles catalog_item left join(select item,count(*) n from chaos_private.inventory group by item)owned on owned.item=catalog_item.id),'[]'::jsonb));
 elsif action<>'buy' or action is null then raise exception 'Ungültige Shopaktion';end if;
 if request_id is null then raise exception 'Kauf-ID fehlt';end if;
 select * into p from public.chaos_profiles where id=u for update;if p.id is null then raise exception 'Bitte zuerst dein Profil einrichten';end if;
 select * into receipt from chaos_private.shop_receipts where id=request_id;
 if receipt.id is not null then
  if receipt.player<>u or receipt.item is distinct from item_id then raise exception 'Kauf-ID ungültig';end if;
  return public.chaos_social('state');
 end if;
 select * into s from chaos_private.styles where id=item_id;if s.id is null then raise exception 'Gegenstand nicht gefunden';end if;
 price:=chaos_private.store_price(s.id,s.price);
 if quoted_price is distinct from price then raise exception 'Das Angebot hat sich geändert. Bitte den Shop aktualisieren';end if;
 if exists(select 1 from chaos_private.inventory where player=u and item=s.id) then return public.chaos_social('state');end if;
 if p.coins<price then raise exception 'Nicht genug Chaos Coins';end if;
 insert into chaos_private.inventory values(u,s.id);update public.chaos_profiles set coins=coins-price where id=u;
 insert into chaos_private.shop_receipts values(request_id,u,s.id,price,clock_timestamp());
 return public.chaos_social('state');
end;$$;
revoke all on function public.chaos_store(text,text,integer,uuid) from public,anon;
grant execute on function public.chaos_store(text,text,integer,uuid) to authenticated;
commit;
