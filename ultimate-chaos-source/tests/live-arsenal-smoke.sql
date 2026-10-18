-- Generated test identity only; all mutations roll back.
begin;
do $test$
declare u uuid:=gen_random_uuid();receipt uuid:=gen_random_uuid();a jsonb;b jsonb;balance integer;qty integer;d jsonb;
begin
 d:=chaos_private.item_outcome('{"hp":2,"max":5,"burn":0,"shield":0,"card":0,"item":"elixir"}','{"hp":5,"max":5,"burn":0,"shield":0,"card":1}',8,.1,.1);
 if(d->>'host_hp')::int<>4 or(d->>'host_damage')::int<>0 then raise exception 'Potion resolver failed';end if;
 insert into auth.users(id,is_anonymous,email_confirmed_at) values(u,false,clock_timestamp());perform set_config('request.jwt.claim.sub',u::text,true);perform public.chaos_social('profile','Arsenal QA',0);
 a:=public.chaos_items('state');b:=public.chaos_items('state');if a->'stock'<>b->'stock' or(a->'stock'->>'potion')::int<>2 then raise exception 'Starter grant failed';end if;
 update public.chaos_profiles set coins=1000 where id=u;
 a:=public.chaos_items('buy','potion',1,60,receipt);b:=public.chaos_items('buy','potion',1,60,receipt);
 if a->'stock'<>b->'stock' or(a->'state'->'profile'->>'coins')::int<>940 then raise exception 'Purchase retry failed';end if;
 insert into chaos_private.packs values(u,4,1);receipt:=gen_random_uuid();a:=public.chaos_loot('open',4,receipt);b:=public.chaos_loot('open',4,receipt);
 if a->'loot'<>b->'loot' or a->'loot'->>'kind'<>'consumable' or(a->'loot'->>'quantity')::int not between 3 and 5 then raise exception 'Arkanum failed';end if;
 if has_function_privilege('authenticated','chaos_private.resolve_items(public.chaos_rooms,integer,integer)','EXECUTE') or has_table_privilege('authenticated','chaos_private.item_stock','SELECT') then raise exception 'Private inventory exposed';end if;
 if(select count(*)from chaos_private.cosmetic_catalog where id in('outfit-umbra-drift','outfit-solar-archon','outfit-mistblade','outfit-astral-monarch','weapon-moonreaper','weapon-twilight-pair','weapon-star-lance','weapon-astral-grimoire'))<>8 then raise exception 'Missing styles';end if;
end;$test$;
select 'PASS: healing/block, one-time starter, purchase retry, Arkanum 3–5 items, eight styles, private storage. Test data rolled back.' as verification;
rollback;
