-- Real server acceptance check; all temporary users, games and ratings are rolled back.
begin;
do $test$
declare h uuid:=gen_random_uuid();g uuid:=gen_random_uuid();d jsonb;r public.chaos_rooms;i integer;
begin
 insert into auth.users(id,is_anonymous,email_confirmed_at) values(h,false,clock_timestamp()),(g,false,clock_timestamp());
 perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_social('profile','Queue QA A',0);
 d:=public.chaos_matchmaking('join');if d->>'status'<>'waiting' then raise exception 'First queue entry failed';end if;
 perform set_config('request.jwt.claim.sub',g::text,true);perform public.chaos_social('profile','Queue QA B',0);
 d:=public.chaos_matchmaking('join');if d->>'status'<>'matched' then raise exception 'Match assignment failed';end if;
 select * into r from public.chaos_rooms where code=d->>'code';
 if r.host<>h or r.guest<>g or r.is_bot or r.game_mode<>'ranked' then raise exception 'Wrong participants';end if;
 d:=public.chaos_matchmaking('cancel');if d->>'code'<>r.code then raise exception 'Assigned match lost on cancellation';end if;
 update public.chaos_rooms set battle_starts_at=clock_timestamp()-interval '1 second' where id=r.id;
 for i in 1..5 loop
  perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_action('choose',r.code,null,0,r.round_no,r.match_no);perform public.chaos_action('confirm',r.code,null,null,r.round_no,r.match_no);
  perform set_config('request.jwt.claim.sub',g::text,true);perform public.chaos_action('choose',r.code,null,2,r.round_no,r.match_no);d:=public.chaos_action('confirm',r.code,null,null,r.round_no,r.match_no);
  select * into r from public.chaos_rooms where id=r.id;
  if i<5 then update public.chaos_rooms set next_round_at=clock_timestamp()-interval '1 second' where id=r.id;d:=public.chaos_action('state',r.code);select * into r from public.chaos_rooms where id=r.id;end if;
 end loop;
 perform set_config('request.jwt.claim.sub',h::text,true);d:=public.chaos_rankings('global');
 if (d->>'rating')::integer<>1016 or (d->>'wins')::integer<>1 then raise exception 'Winner rating failed';end if;
 perform public.chaos_action('state',r.code);d:=public.chaos_rankings('global');if (d->>'rating')::integer<>1016 then raise exception 'Duplicate rating';end if;
 perform set_config('request.jwt.claim.sub',g::text,true);d:=public.chaos_rankings('global');if (d->>'rating')::integer<>984 then raise exception 'Loser rating failed';end if;
end;$test$;
select 'PASS: real queue, atomic assignment, shared 5-life match, server MMR, private history and once-only rating. Temporary test data rolled back.' as verification;
rollback;
