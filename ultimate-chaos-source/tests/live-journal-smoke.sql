-- Real server acceptance; generated temporary accounts only. No test data survives rollback.
begin;
do $test$
declare h uuid:=gen_random_uuid();g uuid:=gen_random_uuid();d jsonb;r public.chaos_rooms;i integer;balance integer;experience integer;denied boolean:=false;
begin
 insert into auth.users(id,is_anonymous,email_confirmed_at) values(h,false,clock_timestamp()),(g,false,clock_timestamp());
 perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_social('profile','Journal QA A',0);
 perform set_config('request.jwt.claim.sub',g::text,true);perform public.chaos_social('profile','Journal QA B',0);
 perform set_config('request.jwt.claim.sub',h::text,true);d:=public.chaos_action('create');select * into r from public.chaos_rooms where id=(d->'room'->>'id')::uuid;
 perform set_config('request.jwt.claim.sub',g::text,true);perform public.chaos_action('join',r.code);
 perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_action('start',r.code);select * into r from public.chaos_rooms where id=r.id;
 for i in 1..5 loop
  perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_action('choose',r.code,null,0,r.round_no,r.match_no);
  perform set_config('request.jwt.claim.sub',g::text,true);perform public.chaos_action('choose',r.code,null,2,r.round_no,r.match_no);
  perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_action('confirm',r.code,null,null,r.round_no,r.match_no);
  perform set_config('request.jwt.claim.sub',g::text,true);perform public.chaos_action('confirm',r.code,null,null,r.round_no,r.match_no);select * into r from public.chaos_rooms where id=r.id;
  if i<5 then update public.chaos_rooms set next_round_at=clock_timestamp()-interval '1 second' where id=r.id;perform public.chaos_action('state',r.code);select * into r from public.chaos_rooms where id=r.id;end if;
 end loop;
 perform set_config('request.jwt.claim.sub',h::text,true);d:=public.chaos_journal('state');
 if jsonb_array_length(d->'history')<>1 or d->'history'->0->>'outcome'<>'win' or(d->'history'->0->>'coins')::integer<>100 or(d->'stats'->>'favorite')::integer<>0 then raise exception 'Journal mismatch';end if;
 if(select (x->>'progress')::integer from jsonb_array_elements(d->'tasks')x where x->>'id'='daily-rounds')<>5 then raise exception 'Task mismatch';end if;
 d:=public.chaos_journal('claim','first-win');select coins,xp into balance,experience from public.chaos_profiles where id=h;
 if(d->'reward'->>'coins')::integer<>30 then raise exception 'Achievement missing';end if;
 d:=public.chaos_journal('claim','first-win');if d->'reward'<>'null'::jsonb or(select coins from public.chaos_profiles where id=h)<>balance or(select xp from public.chaos_profiles where id=h)<>experience then raise exception 'Duplicate claim';end if;
 begin perform public.chaos_journal('claim','daily-play');exception when others then denied:=true;end;if not denied then raise exception 'Unfinished task claimed';end if;
 perform set_config('request.jwt.claim.sub',g::text,true);d:=public.chaos_journal('state');if jsonb_array_length(d->'history')<>1 or d->'history'->0->>'outcome'<>'loss' or(d->'state'->'profile'->>'id')::uuid<>g then raise exception 'Private journal mismatch';end if;
end;$test$;
select 'PASS: actual match journal, secret player choices retained, daily round progress, permanent achievement, exactly-once claim and own-only history. Temporary data rolled back.' as verification;
rollback;
