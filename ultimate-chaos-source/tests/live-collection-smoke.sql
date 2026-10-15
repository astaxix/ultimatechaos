-- Server acceptance test. Only generated temporary users/data; everything is rolled back.
begin;
do $test$
declare h uuid:=gen_random_uuid();g uuid:=gen_random_uuid();purchase uuid:=gen_random_uuid();opened uuid:=gen_random_uuid();d jsonb;catalog jsonb;reward jsonb;r public.chaos_rooms;price integer;balance integer;qty integer;denied boolean:=false;
begin
 insert into auth.users(id,is_anonymous,email_confirmed_at) values(h,false,clock_timestamp()),(g,false,clock_timestamp());
 perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_social('profile','Collection QA A',0);
 perform set_config('request.jwt.claim.sub',g::text,true);perform public.chaos_social('profile','Collection QA B',0);
 update public.chaos_profiles set coins=10000 where id=h;
 perform set_config('request.jwt.claim.sub',h::text,true);catalog:=public.chaos_store('catalog');
 select (x->>'price')::integer into price from jsonb_array_elements(catalog->'items') x where x->>'id'='skin-solar-0';
 perform public.chaos_store('buy','skin-solar-0',price,purchase);select coins into balance from public.chaos_profiles where id=h;
 perform public.chaos_store('buy','skin-solar-0',price,purchase);if(select coins from public.chaos_profiles where id=h)<>balance then raise exception 'Purchase charged twice';end if;
 d:=public.chaos_collection('equip',0,'skin','skin-solar-0');if d->'profile'->'card_loadouts'->'0'->>'skin'<>'skin-solar-0' then raise exception 'Loadout missing';end if;
 begin perform public.chaos_collection('equip',1,'skin','skin-solar-0');exception when others then denied:=true;end;if not denied then raise exception 'Wrong power accepted';end if;
 select (x->>'price')::integer into price from jsonb_array_elements(catalog->'items') x where x->>'id'='weapon-lumen';perform public.chaos_store('buy','weapon-lumen',price,gen_random_uuid());perform public.chaos_style('equip',null,'weapon-lumen');
 d:=public.chaos_style('appearance','{"hair":"afro"}');if d->'profile'->'appearance'->>'weapon'<>'weapon-lumen' then raise exception 'Editor erased paid equipment';end if;
 d:=public.chaos_action('create');select * into r from public.chaos_rooms where id=(d->'room'->>'id')::uuid;
 perform set_config('request.jwt.claim.sub',g::text,true);perform public.chaos_action('join',r.code);
 perform set_config('request.jwt.claim.sub',h::text,true);d:=public.chaos_action('start',r.code);select * into r from public.chaos_rooms where id=r.id;
 perform public.chaos_action('choose',r.code,null,0,r.round_no,r.match_no);perform public.chaos_emote(r.code,'wave');
 perform set_config('request.jwt.claim.sub',g::text,true);d:=public.chaos_action('state',r.code);
 if d->'room'->>'host_choice' is not null or d->>'my_choice' is not null then raise exception 'Hidden choice exposed';end if;
 if d->'players'->'host'->'card_loadouts'->'0'->>'skin'<>'skin-solar-0' then raise exception 'Battle loadout missing';end if;
 perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_loot('buy',3,gen_random_uuid());
 d:=public.chaos_loot('open',3,opened);reward:=d->'loot';select coins into balance from public.chaos_profiles where id=h;select quantity into qty from chaos_private.packs where player=h and tier=3;
 d:=public.chaos_loot('open',3,opened);if d->'loot'<>reward or(select coins from public.chaos_profiles where id=h)<>balance or(select quantity from chaos_private.packs where player=h and tier=3)<>qty then raise exception 'Repeated chest opening changed state';end if;
 d:=public.chaos_packs();if jsonb_array_length(d->'history')<>1 then raise exception 'Own chest history missing';end if;
 perform set_config('request.jwt.claim.sub',g::text,true);d:=public.chaos_packs();if jsonb_array_length(d->'history')<>0 then raise exception 'Foreign chest history exposed';end if;
end;$test$;
select 'PASS: server-priced purchase once, independent owned loadout, wrong power denied, paid equipment retained, real multiplayer appearance with hidden moves, emote, fourth chest once and private history. Test data rolled back.' as verification;
rollback;
