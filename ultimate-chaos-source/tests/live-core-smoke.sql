-- Real PostgreSQL acceptance check. All test accounts and state are rolled back.
begin;
do $test$
declare
 h uuid:=gen_random_uuid();g uuid:=gen_random_uuid();d jsonb;r public.chaos_rooms;i integer;
 bot integer;winning integer;before_coins integer;after_coins integer;
begin
 insert into auth.users(id,is_anonymous,email_confirmed_at) values(h,false,clock_timestamp()),(g,false,clock_timestamp());
 perform set_config('request.jwt.claim.sub',h::text,true);
 perform public.chaos_social('profile','QA rollback A',0);
 perform set_config('request.jwt.claim.sub',g::text,true);
 perform public.chaos_social('profile','QA rollback B',0);
 perform set_config('request.jwt.claim.sub',h::text,true);
 d:=public.chaos_action('create');select * into r from public.chaos_rooms where id=(d->'room'->>'id')::uuid;
 perform set_config('request.jwt.claim.sub',g::text,true);perform public.chaos_action('join',r.code);
 perform set_config('request.jwt.claim.sub',h::text,true);d:=public.chaos_action('start',r.code);
 select * into r from public.chaos_rooms where id=r.id;
 if r.rules_version<>2 or r.host_hp<>5 or r.guest_hp<>5 or r.select_until-clock_timestamp()<interval '9 seconds' then raise exception 'HP/timer mismatch';end if;
 for i in 1..5 loop
  perform set_config('request.jwt.claim.sub',h::text,true);
  perform public.chaos_action('choose',r.code,null,0,r.round_no,r.match_no);
  perform set_config('request.jwt.claim.sub',g::text,true);
  perform public.chaos_action('choose',r.code,null,2,r.round_no,r.match_no);
  d:=public.chaos_action('state',r.code);
  if d->'room'->>'host_choice' is not null or d->'room'->>'guest_choice' is not null then raise exception 'Secret choice leaked';end if;
  perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_action('confirm',r.code,null,null,r.round_no,r.match_no);
  perform set_config('request.jwt.claim.sub',g::text,true);d:=public.chaos_action('confirm',r.code,null,null,r.round_no,r.match_no);
  select * into r from public.chaos_rooms where id=r.id;
  if r.host_hp<>5 or r.guest_hp<>5-i then raise exception 'Incorrect damage';end if;
  if i<5 then
   update public.chaos_rooms set next_round_at=clock_timestamp()-interval '1 second' where id=r.id;
   d:=public.chaos_action('state',r.code);select * into r from public.chaos_rooms where id=r.id;
  end if;
 end loop;
 if r.phase<>'finished' or r.match_winner<>h then raise exception 'Match did not finish';end if;
 select coins into before_coins from public.chaos_profiles where id=h;
 perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_action('state',r.code);perform public.chaos_action('state',r.code);
 select coins into after_coins from public.chaos_profiles where id=h;
 if before_coins<>100 or after_coins<>before_coins then raise exception 'Rewards not idempotent';end if;
 update chaos_private.limits set created='epoch' where player=h;
 d:=public.chaos_campaign(0);select * into r from public.chaos_rooms where id=(d->'room'->>'id')::uuid;
 if r.guest_name<>'Milo' or r.host_hp<>5 or r.guest_hp<>5 then raise exception 'Campaign init failed';end if;
 for i in 1..5 loop
  select choice into bot from chaos_private.moves where room_id=r.id and match_no=r.match_no and round_no=r.round_no and player=r.guest;
  select n into winning from generate_series(0,6) n where chaos_private.beats(n,bot) limit 1;
  perform public.chaos_action('choose',r.code,null,winning,r.round_no,r.match_no);
  d:=public.chaos_action('confirm',r.code,null,null,r.round_no,r.match_no);
  select * into r from public.chaos_rooms where id=r.id;
  if i<5 then
   update public.chaos_rooms set next_round_at=clock_timestamp()-interval '1 second' where id=r.id;
   perform public.chaos_action('state',r.code);select * into r from public.chaos_rooms where id=r.id;
  end if;
 end loop;
 if r.match_winner<>h or (select campaign_unlocked from public.chaos_profiles where id=h)<>1 or (select coins from public.chaos_profiles where id=h)<>200 then raise exception 'Campaign progression or rewards failed';end if;
end;
$test$;
select 'PASS: 5 HP, 10s, secret moves, ready, damage, rewards once, campaign start/win/unlock. Test data rolled back.' as verification;
rollback;
