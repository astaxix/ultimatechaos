-- Additive cosmetic acceptance. Generated identities only; all writes roll back.
begin;
do $test$
declare h uuid:=gen_random_uuid();g uuid:=gen_random_uuid();receipt uuid:=gen_random_uuid();catalog jsonb;d jsonb;i text;quote integer;balance integer;denied boolean:=false;
begin
 if(select count(*) from chaos_private.styles where id in('skin-sniper-frost','skin-sniper-jade','skin-sniper-seraph','skin-sniper-void','outfit-asc-paladin','outfit-asc-ronin','outfit-asc-astral','outfit-asc-specter'))<>8 then raise exception 'Ascension pack pool incomplete';end if;
 insert into auth.users(id,is_anonymous,email_confirmed_at) values(h,false,clock_timestamp()),(g,false,clock_timestamp());
 perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_social('profile','Ascension QA A',0);
 perform set_config('request.jwt.claim.sub',g::text,true);perform public.chaos_social('profile','Ascension QA B',0);
 perform set_config('request.jwt.claim.sub',h::text,true);update public.chaos_profiles set coins=20000 where id=h;
 catalog:=public.chaos_store('catalog');
 foreach i in array array['skin-sniper-frost','skin-sniper-jade','skin-sniper-seraph','skin-sniper-void','outfit-asc-paladin','outfit-asc-ronin','outfit-asc-astral','outfit-asc-specter'] loop
  select (x->>'price')::int into quote from jsonb_array_elements(catalog->'items') x where x->>'id'=i;
  if quote is null or quote<=0 then raise exception 'Missing price for %',i;end if;
  receipt:=gen_random_uuid();perform public.chaos_store('buy',i,quote,receipt);select coins into balance from public.chaos_profiles where id=h;
  perform public.chaos_store('buy',i,quote,receipt);if(select coins from public.chaos_profiles where id=h)<>balance then raise exception 'Double charge';end if;
  if i like 'skin-%' then
   d:=public.chaos_collection('equip',7,'skin',i);if d->'profile'->'card_loadouts'->'7'->>'skin'<>i then raise exception 'Sniper equip failed';end if;
   denied:=false;begin perform public.chaos_collection('equip',0,'skin',i);exception when others then denied:=true;end;if not denied then raise exception 'Wrong power accepted';end if;
  else
   d:=public.chaos_style('equip',null,i);if d->'profile'->'appearance'->>'outfit'<>i then raise exception 'Outfit equip failed';end if;
  end if;
 end loop;
 perform set_config('request.jwt.claim.sub',g::text,true);
 denied:=false;begin perform public.chaos_collection('equip',7,'skin','skin-sniper-void');exception when others then denied:=true;end;if not denied then raise exception 'Unowned sniper skin accepted';end if;
 denied:=false;begin perform public.chaos_style('equip',null,'outfit-asc-paladin');exception when others then denied:=true;end;if not denied then raise exception 'Unowned outfit accepted';end if;
end;$test$;
select 'PASS: eight new shop and pack cosmetics; server-priced purchases charge once; all four sniper skins and outfits equip; wrong-card and unowned items denied. All test data rolled back.' as verification;
rollback;
