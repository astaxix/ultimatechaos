-- Server acceptance test; temporary account, run and rewards are rolled back.
begin;
do $test$
declare u uuid:=gen_random_uuid();d jsonb;r public.chaos_rooms;bot integer;win integer;i integer;
begin
 insert into auth.users(id,is_anonymous,email_confirmed_at) values(u,false,clock_timestamp());
 perform set_config('request.jwt.claim.sub',u::text,true);perform public.chaos_social('profile','Endless QA rollback',0);
 d:=public.chaos_endless('start');select * into r from public.chaos_rooms where id=(d->'room'->>'id')::uuid;
 if r.host_hp<>10 or r.guest_hp<>1 or r.endless_wave<>1 then raise exception 'Incorrect starting lives';end if;
 select choice into bot from chaos_private.moves where room_id=r.id and match_no=r.match_no and round_no=r.round_no and player=r.guest;
 select n into win from generate_series(0,6) n where chaos_private.beats(n,bot) limit 1;
 perform public.chaos_action('choose',r.code,null,win,r.round_no,r.match_no);d:=public.chaos_action('confirm',r.code,null,null,r.round_no,r.match_no);
 select * into r from public.chaos_rooms where id=r.id;
 if r.phase<>'finished' or (select coins from public.chaos_profiles where id=u)<>25 then raise exception 'Wave one reward incorrect';end if;
 perform public.chaos_action('state',r.code);
 if (select coins from public.chaos_profiles where id=u)<>25 then raise exception 'Duplicate reward';end if;
 update public.chaos_rooms set next_round_at=clock_timestamp()-interval '1 second' where id=r.id;
 perform public.chaos_action('state',r.code);select * into r from public.chaos_rooms where id=r.id;
 if r.endless_wave<>2 or r.guest_hp<>2 or r.host_hp<>10 then raise exception 'Automatic enemy two failed';end if;
 select choice into bot from chaos_private.moves where room_id=r.id and match_no=r.match_no and round_no=r.round_no and player=r.guest;
 select n into win from generate_series(0,6) n where chaos_private.beats(bot,n) limit 1;
 perform public.chaos_action('choose',r.code,null,win,r.round_no,r.match_no);perform public.chaos_action('confirm',r.code,null,null,r.round_no,r.match_no);
 select * into r from public.chaos_rooms where id=r.id;if r.host_hp<>9 then raise exception 'Player damage failed';end if;
 for i in 1..2 loop
  update public.chaos_rooms set next_round_at=clock_timestamp()-interval '1 second' where id=r.id;
  perform public.chaos_action('state',r.code);select * into r from public.chaos_rooms where id=r.id;
  select choice into bot from chaos_private.moves where room_id=r.id and match_no=r.match_no and round_no=r.round_no and player=r.guest;
  select n into win from generate_series(0,6) n where chaos_private.beats(n,bot) limit 1;
  perform public.chaos_action('choose',r.code,null,win,r.round_no,r.match_no);perform public.chaos_action('confirm',r.code,null,null,r.round_no,r.match_no);
  select * into r from public.chaos_rooms where id=r.id;
 end loop;
 update public.chaos_rooms set next_round_at=clock_timestamp()-interval '1 second' where id=r.id;
 perform public.chaos_action('state',r.code);select * into r from public.chaos_rooms where id=r.id;
 if r.endless_wave<>3 or r.guest_hp<>3 or r.host_hp<>9 then raise exception 'Lives did not carry over';end if;
 update public.chaos_rooms set host_hp=1 where id=r.id;
 select choice into bot from chaos_private.moves where room_id=r.id and match_no=r.match_no and round_no=r.round_no and player=r.guest;
 select n into win from generate_series(0,6) n where chaos_private.beats(bot,n) limit 1;
 perform public.chaos_action('choose',r.code,null,win,r.round_no,r.match_no);perform public.chaos_action('confirm',r.code,null,null,r.round_no,r.match_no);
 select * into r from public.chaos_rooms where id=r.id;
 d:=public.chaos_endless('state');
 if r.host_hp<>0 or r.phase<>'finished' or d->'active'<>'null'::jsonb or (d->'history'->0->>'defeated')::integer<>2 or (d->>'best')::integer<>3 then raise exception 'Run finalization/history/record failed';end if;
 if (select coins from public.chaos_profiles where id=u)<>55 or (select xp from public.chaos_profiles where id=u)<>52 then raise exception 'Run totals incorrect';end if;
 perform public.chaos_action('state',r.code);
 if (select xp from public.chaos_profiles where id=u)<>52 then raise exception 'Repeated defeat payment';end if;
end;$test$;
select 'PASS: 10 lives, automatic waves, surviving lives retained, rewards once, zero-life end, history and record. Test data rolled back.' as verification;
rollback;
