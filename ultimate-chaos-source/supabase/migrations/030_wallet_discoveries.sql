begin;
-- Discoveries are private per player and acknowledged with an exact version.
create table chaos_private.discoveries(player uuid not null references public.chaos_profiles on delete cascade,key text not null,version bigint not null default 1,acquired_at timestamptz not null default clock_timestamp(),primary key(player,key));
alter table chaos_private.discoveries enable row level security;
revoke all on chaos_private.discoveries from public,anon,authenticated;
create function chaos_private.discover() returns trigger language plpgsql set search_path='' as $$
declare k text;
begin
 if tg_table_name='inventory' then k:='style:'||new.item;
 elsif tg_table_name='item_stock' then if new.quantity<=0 or(tg_op='UPDATE' and new.quantity<=old.quantity)then return new;end if;k:='item:'||new.item;
 else if new.quantity<=0 or(tg_op='UPDATE' and new.quantity<=old.quantity)then return new;end if;k:='pack:'||new.tier;end if;
 insert into chaos_private.discoveries(player,key)values(new.player,k)on conflict(player,key)do update set version=chaos_private.discoveries.version+1,acquired_at=clock_timestamp();return new;
end;$$;
create trigger discovery_style after insert on chaos_private.inventory for each row execute function chaos_private.discover();
create trigger discovery_item after insert or update of quantity on chaos_private.item_stock for each row execute function chaos_private.discover();
create trigger discovery_pack after insert or update of quantity on chaos_private.packs for each row execute function chaos_private.discover();
create function public.chaos_discoveries(action text default 'state',entries jsonb default '[]')returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();e jsonb;
begin
 if action='seen' then
 if jsonb_typeof(entries)<>'array' or jsonb_array_length(entries)>100 then raise exception 'Ungültige Markierungen';end if;
 for e in select value from jsonb_array_elements(entries)loop delete from chaos_private.discoveries where player=u and key=e->>'key' and version=(e->>'version')::bigint;end loop;
 elsif action<>'state' then raise exception 'Ungültige Aktion';end if;
 return jsonb_build_object('entries',coalesce((select jsonb_agg(jsonb_build_object('key',key,'version',version,'at',acquired_at)order by acquired_at desc)from chaos_private.discoveries where player=u),'[]'));
end;$$;
-- Gift codes are single-use grants, never purchases. No payment endpoint exists.
create table chaos_private.coin_admins(player uuid primary key references auth.users on delete cascade);
create table chaos_private.coin_gifts(id uuid primary key default gen_random_uuid(),request_id uuid not null unique,code text not null unique check(code~'^[23456789ABCDEFGHJKMNPQRSTVWXYZ]{10}$'),amount integer not null check(amount between 1 and 100000),creator uuid not null references auth.users,created_at timestamptz not null default clock_timestamp(),expires_at timestamptz not null default(clock_timestamp()+interval '90 days'),redeemed_by uuid references auth.users,redeemed_at timestamptz,revoked boolean not null default false);
create table chaos_private.wallet_limits(player uuid not null references auth.users on delete cascade,action text not null,window_at timestamptz not null default clock_timestamp(),attempts integer not null default 0,primary key(player,action));
alter table chaos_private.coin_admins enable row level security;alter table chaos_private.coin_gifts enable row level security;alter table chaos_private.wallet_limits enable row level security;
revoke all on chaos_private.coin_admins,chaos_private.coin_gifts,chaos_private.wallet_limits from public,anon,authenticated;
create function chaos_private.wallet_limit(u uuid,a text,max_attempts integer)returns boolean language plpgsql set search_path='' as $$
declare n integer;
begin
 insert into chaos_private.wallet_limits(player,action,attempts)values(u,a,1)on conflict(player,action)do update set attempts=case when chaos_private.wallet_limits.window_at<clock_timestamp()-interval '1 minute' then 1 else chaos_private.wallet_limits.attempts+1 end,window_at=case when chaos_private.wallet_limits.window_at<clock_timestamp()-interval '1 minute' then clock_timestamp()else chaos_private.wallet_limits.window_at end returning attempts into n;return n<=max_attempts;
end;$$;
create function public.chaos_wallet(action text,gift_code text default null,coin_amount integer default null,request_id uuid default null)returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();g chaos_private.coin_gifts;generated_code text;secret bytea;i integer;alphabet text:='23456789ABCDEFGHJKMNPQRSTVWXYZ';balance integer;is_admin boolean;
begin
 select exists(select 1 from chaos_private.coin_admins where player=u)into is_admin;
 if action='admin-state' or action='create' or action='revoke' then if not is_admin then raise exception 'Kein Admin-Zugriff';end if;end if;
 if action='create' then
 if coin_amount is null or coin_amount not between 1 and 100000 or request_id is null then raise exception 'Betrag zwischen 1 und 100.000 Coins erforderlich';end if;
 select * into g from chaos_private.coin_gifts where coin_gifts.request_id=chaos_wallet.request_id;
 if g.id is not null then if g.creator<>u or g.amount<>coin_amount then raise exception 'Kauf-ID ungültig';end if;return jsonb_build_object('gift',to_jsonb(g)-'redeemed_by');end if;
 if not chaos_private.wallet_limit(u,'create',10)then return jsonb_build_object('error','Bitte eine Minute warten.');end if;
 -- Rejection sampling avoids alphabet bias, while UUID entropy stays on the server.
 loop
 generated_code:='';while length(generated_code)<10 loop secret:=uuid_send(gen_random_uuid());for i in 0..4 loop if get_byte(secret,i)<240 then generated_code:=generated_code||substr(alphabet,1+mod(get_byte(secret,i),30),1);exit when length(generated_code)=10;end if;end loop;end loop;
 begin insert into chaos_private.coin_gifts(request_id,code,amount,creator)values(request_id,generated_code,coin_amount,u)returning * into g;exit;exception when unique_violation then if exists(select 1 from chaos_private.coin_gifts where coin_gifts.request_id=chaos_wallet.request_id)then select * into g from chaos_private.coin_gifts where coin_gifts.request_id=chaos_wallet.request_id;if g.creator<>u or g.amount<>coin_amount then raise exception 'Anfrage ungültig';end if;exit;end if;end;
 end loop;return jsonb_build_object('gift',to_jsonb(g)-'redeemed_by');
 elsif action='revoke' then
 update chaos_private.coin_gifts set revoked=true where coin_gifts.code=upper(trim(gift_code)) and redeemed_at is null;return jsonb_build_object('ok',true);
 elsif action='admin-state' then
 return jsonb_build_object('gifts',coalesce((select jsonb_agg(x)from(select id,code,amount,created_at,expires_at,redeemed_at,revoked from chaos_private.coin_gifts order by created_at desc limit 100)x),'[]'));
 elsif action='redeem' then
 if not chaos_private.wallet_limit(u,'redeem',8)then return jsonb_build_object('error','Zu viele Versuche. Bitte eine Minute warten.');end if;
 generated_code:=upper(regexp_replace(coalesce(gift_code,''),'[\s-]','','g'));
 if generated_code!~'^[23456789ABCDEFGHJKMNPQRSTVWXYZ]{10}$'then return jsonb_build_object('error','Code ungültig oder nicht mehr verfügbar.');end if;
 perform 1 from public.chaos_profiles where id=u for update;if not found then return jsonb_build_object('error','Bitte zuerst dein Profil einrichten.');end if;
 select * into g from chaos_private.coin_gifts where coin_gifts.code=generated_code for update;
 if g.id is null or g.revoked or g.redeemed_at is not null or g.expires_at<=clock_timestamp()then return jsonb_build_object('error','Code ungültig oder nicht mehr verfügbar.');end if;
 select coins into balance from public.chaos_profiles where id=u;if balance>2147383647 then return jsonb_build_object('error','Dein Guthaben ist derzeit zu hoch.');end if;
 update public.chaos_profiles set coins=coins+g.amount where id=u returning coins into balance;
 update chaos_private.coin_gifts set redeemed_by=u,redeemed_at=clock_timestamp()where id=g.id;
 return jsonb_build_object('amount',g.amount,'coins',balance,'state',public.chaos_social('state'));
 elsif action='checkout' then return jsonb_build_object('error','Zahlung fehlgeschlagen: Der Zahlungsanbieter ist noch nicht eingerichtet. Es wurde nichts abgebucht.','payments_enabled',false);
 else raise exception 'Ungültige Wallet-Aktion';end if;
end;$$;
revoke all on function chaos_private.discover(),chaos_private.wallet_limit(uuid,text,integer)from public,anon,authenticated;
revoke all on function public.chaos_wallet(text,text,integer,uuid),public.chaos_discoveries(text,jsonb)from public,anon;
grant execute on function public.chaos_wallet(text,text,integer,uuid),public.chaos_discoveries(text,jsonb)to authenticated;
commit;
