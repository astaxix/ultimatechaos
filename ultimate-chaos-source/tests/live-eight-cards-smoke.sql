begin;
do $test$
declare h uuid:=gen_random_uuid();g uuid:=gen_random_uuid();d jsonb;r public.chaos_rooms;a integer;b integer;w integer;l integer;t integer;
begin
 for a in 0..7 loop
  w:=0;l:=0;t:=0;
  for b in 0..7 loop
   if a<>b then
    if chaos_private.beats_for(a,b,8) then w:=w+1;
    elsif chaos_private.beats_for(b,a,8) then l:=l+1;else t:=t+1;end if;
   end if;
  end loop;
  if w<>3 or l<>3 or t<>1 then raise exception 'Unbalanced card %',a;end if;
 end loop;
 insert into auth.users(id,is_anonymous,email_confirmed_at) values(h,false,clock_timestamp()),(g,false,clock_timestamp());
 perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_social('profile','Sniper QA A',0);
 perform set_config('request.jwt.claim.sub',g::text,true);perform public.chaos_social('profile','Sniper QA B',0);
 perform set_config('request.jwt.claim.sub',h::text,true);d:=public.chaos_action('create');select * into r from public.chaos_rooms where id=(d->'room'->>'id')::uuid;
 perform set_config('request.jwt.claim.sub',g::text,true);perform public.chaos_action('join',r.code);
 perform set_config('request.jwt.claim.sub',h::text,true);d:=public.chaos_action('start',r.code);
 if(d->'room'->>'power_count')::integer<>8 then raise exception 'Eight-card rules missing';end if;
 perform public.chaos_action('choose',r.code,null,7,1,1);
 perform set_config('request.jwt.claim.sub',g::text,true);perform public.chaos_action('choose',r.code,null,4,1,1);perform public.chaos_action('confirm',r.code,null,null,1,1);
 perform set_config('request.jwt.claim.sub',h::text,true);d:=public.chaos_action('confirm',r.code,null,null,1,1);
 if d->'room'->>'winner' is distinct from h::text or (d->'room'->>'guest_hp')::integer<>4 then raise exception 'Sniper damage failed';end if;
 update public.chaos_rooms set next_round_at=clock_timestamp()-interval '1 second' where id=r.id;
 d:=public.chaos_action('state',r.code);
 perform public.chaos_action('choose',r.code,null,7,2,1);perform public.chaos_action('confirm',r.code,null,null,2,1);
 perform set_config('request.jwt.claim.sub',g::text,true);perform public.chaos_action('choose',r.code,null,3,2,1);d:=public.chaos_action('confirm',r.code,null,null,2,1);
 if d->'room'->>'winner' is not null or (d->'room'->>'host_hp')::integer<>5 or (d->'room'->>'guest_hp')::integer<>4 then raise exception 'Distinct draw damaged player';end if;
 perform public.chaos_collection('equip',7,'skin','classic');
end;$test$;
select 'PASS: all eight cards have 3 wins, 3 losses and 1 distinct draw; real PvP sniper hit and distinct draw preserve correct HP; power 7 loadout saves. Temporary data rolled back.' as verification;
rollback;
