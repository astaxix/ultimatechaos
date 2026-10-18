-- Generated identities and codes only; everything rolls back.
begin;
do $test$
declare admin_uid uuid:=gen_random_uuid();player_uid uuid:=gen_random_uuid();request_uid uuid:=gen_random_uuid();gift jsonb;again jsonb;result jsonb;code text;before_balance integer;seen jsonb;
begin
 insert into auth.users(id,is_anonymous,email_confirmed_at)values(admin_uid,false,clock_timestamp()),(player_uid,false,clock_timestamp());
 perform set_config('request.jwt.claim.sub',admin_uid::text,true);perform public.chaos_social('profile','Wallet Admin QA',0);insert into chaos_private.coin_admins values(admin_uid);
 gift:=public.chaos_wallet('create',null,777,request_uid);again:=public.chaos_wallet('create',null,777,request_uid);code:=gift->'gift'->>'code';if length(code)<>10 or code<>again->'gift'->>'code' then raise exception 'Code retry mismatch';end if;
 perform set_config('request.jwt.claim.sub',player_uid::text,true);perform public.chaos_social('profile','Wallet Player QA',0);select coins into before_balance from public.chaos_profiles where id=player_uid;
 result:=public.chaos_wallet('redeem',code);if(result->>'coins')::int<>before_balance+777 then raise exception 'Gift credit mismatch';end if;
 result:=public.chaos_wallet('redeem',code);if result->>'error' is null then raise exception 'Gift double-spend protection missing';end if;
 result:=public.chaos_wallet('checkout');if(result->>'payments_enabled')::boolean then raise exception 'Payments must remain disabled';end if;
 insert into chaos_private.inventory values(player_uid,'outfit-resonance-jade');seen:=public.chaos_discoveries('state');if not exists(select 1 from jsonb_array_elements(seen->'entries')e where e->>'key'='style:outfit-resonance-jade')then raise exception 'New style marker missing';end if;
 result:=public.chaos_discoveries('seen',seen->'entries');if jsonb_array_length(result->'entries')<>0 then raise exception 'Marker did not clear';end if;
 if(select count(*)from chaos_private.cosmetic_catalog where id like '%-resonance-%')<>10 then raise exception 'Resonance catalog missing';end if;
end;$test$;
select 'WALLET_DISCOVERIES_OK' as verification;
rollback;
