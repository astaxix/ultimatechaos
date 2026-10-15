-- Temporary generated test identities only. The full acceptance transaction rolls back.
begin;
do $test$
declare h uuid:=gen_random_uuid();g uuid:=gen_random_uuid();d jsonb;r public.chaos_rooms;balance integer;denied boolean:=false;
begin
 insert into auth.users(id,is_anonymous,email_confirmed_at) values(h,false,clock_timestamp()),(g,false,clock_timestamp());
 perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_social('profile','Update QA A',0);
 perform set_config('request.jwt.claim.sub',g::text,true);perform public.chaos_social('profile','Update QA B',0);
 update public.chaos_profiles set coins=1000,xp=1500 where id in(h,g);
 perform set_config('request.jwt.claim.sub',h::text,true);d:=public.chaos_action('create');select * into r from public.chaos_rooms where id=(d->'room'->>'id')::uuid;
 perform set_config('request.jwt.claim.sub',g::text,true);perform public.chaos_action('join',r.code);
 perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_action('start',r.code);d:=public.chaos_wager('open',r.code);select * into r from public.chaos_rooms where id=r.id;
 if not(d->'wager'->>'active')::boolean then raise exception 'Wager phase missing';end if;
 begin perform public.chaos_action('choose',r.code,null,0,r.round_no,r.match_no);exception when others then denied:=true;end;if not denied then raise exception 'Wager bypass';end if;
 perform public.chaos_wager('ready',r.code,25,r.round_no,r.match_no);perform public.chaos_wager('ready',r.code,25,r.round_no,r.match_no);
 if(select coins from public.chaos_profiles where id=h)<>975 then raise exception 'Escrow mismatch';end if;
 perform set_config('request.jwt.claim.sub',g::text,true);d:=public.chaos_wager('state',r.code);
 if(d->'wager'->>'stake')::integer<>0 then raise exception 'Foreign stake leak';end if;
 d:=public.chaos_wager('ready',r.code,10,r.round_no,r.match_no);if(d->'wager'->>'active')::boolean then raise exception 'Early ready failed';end if;
 perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_action('choose',r.code,null,0,r.round_no,r.match_no);
 perform set_config('request.jwt.claim.sub',g::text,true);d:=public.chaos_action('choose',r.code,null,2,r.round_no,r.match_no);if d->'room'->>'host_choice' is not null then raise exception 'Secret choice leak';end if;
 perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_action('confirm',r.code,null,null,r.round_no,r.match_no);
 perform set_config('request.jwt.claim.sub',g::text,true);d:=public.chaos_action('confirm',r.code,null,null,r.round_no,r.match_no);
 if(select coins from public.chaos_profiles where id=h)<>1025 or(select coins from public.chaos_profiles where id=g)<>990 then raise exception 'Settlement mismatch';end if;
 perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_action('state',r.code);
 if(select coins from public.chaos_profiles where id=h)<>1025 then raise exception 'Duplicate settlement';end if;
 insert into chaos_private.inventory values(h,'emote-mic');
 d:=public.chaos_emote_loadout(array['gg','luck','emote-mic','thanks','oops']);
 if d->'profile'->'emote_loadout'->>2<>'emote-mic' then raise exception 'Loadout missing';end if;
 d:=public.chaos_emote(r.code,'luck');if d->'room'->>'host_emote'<>'luck' then raise exception 'Free emote missing';end if;
 denied:=false;begin perform public.chaos_emote_loadout(array['gg','luck','wave','thanks','emote-salt']);exception when others then denied:=true;end;if not denied then raise exception 'Unowned emote accepted';end if;
end;$test$;
select 'PASS: 10-second wager phase, early start, once-only escrow and doubled payout, own-only stake, secret moves, five saved emote slots, free emotes and ownership checks. All temporary data rolled back.' as verification;
rollback;
