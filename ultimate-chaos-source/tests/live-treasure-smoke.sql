-- Coin reward acceptance, generated identity only. All test writes and RNG overrides roll back.
begin;
create sequence chaos_private.treasure_qa_roll;
create or replace function chaos_private.loot_roll() returns integer language sql volatile set search_path='' as $$select case when nextval('chaos_private.treasure_qa_roll')%2=1 then 2000 else 0 end;$$;
do $test$
declare u uuid:=gen_random_uuid();r uuid:=gen_random_uuid();a jsonb;b jsonb;balance integer;t integer;
begin
 for t in 0..3 loop
  a:=chaos_private.coin_prize(t,0,0);if a->>'coin_kind'<>'mythic' or (a->>'coins')::int<2500 then raise exception 'Missing mythic coins';end if;
  a:=chaos_private.coin_prize(t,400,0);if a->>'coin_kind'<>'rare' then raise exception 'Missing rare coins';end if;
  a:=chaos_private.coin_prize(t,9999,.999999);if (a->>'coins')::int<>(array[100,250,700,1000])[t+1] then raise exception 'Standard bounds changed';end if;
 end loop;
 insert into auth.users(id,is_anonymous,email_confirmed_at) values(u,false,clock_timestamp());
 perform set_config('request.jwt.claim.sub',u::text,true);perform public.chaos_social('profile','Treasure QA',0);
 insert into chaos_private.packs values(u,0,1) on conflict(player,tier) do update set quantity=chaos_private.packs.quantity+1;
 select coins into balance from public.chaos_profiles where id=u;
 a:=public.chaos_loot('open',0,r);
 if a->'loot'->>'coin_kind'<>'mythic' then raise exception 'Jackpot not returned';end if;
 if(select coins from public.chaos_profiles where id=u)<>balance+(a->'loot'->>'coins')::int then raise exception 'Incorrect wallet credit';end if;
 select coins into balance from public.chaos_profiles where id=u;
 b:=public.chaos_loot('open',0,r);
 if a->'loot'<>b->'loot' or(select coins from public.chaos_profiles where id=u)<>balance then raise exception 'Duplicate credit';end if;
 if has_function_privilege('authenticated','chaos_private.coin_prize(integer,integer,double precision)','EXECUTE') then raise exception 'Private payout exposed';end if;
end;$test$;
select 'PASS: rare/mythic coin bounds, real jackpot RPC, exact wallet credit, idempotent retry and private helper. All test data rolled back.' as verification;
rollback;
