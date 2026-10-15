-- Temporary accounts/messages/challenges only. The complete test is rolled back.
begin;
do $test$
declare h uuid:=gen_random_uuid();g uuid:=gen_random_uuid();nonce uuid:=gen_random_uuid();d jsonb;c uuid;m uuid;code text;
begin
 insert into auth.users(id,is_anonymous,email_confirmed_at) values(h,false,clock_timestamp()),(g,false,clock_timestamp());
 perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_social('profile','Chat QA A',0);
 perform set_config('request.jwt.claim.sub',g::text,true);perform public.chaos_social('profile','Chat QA B',0);
 insert into public.chaos_friends(requester,receiver,status) values(h,g,'accepted');
 perform set_config('request.jwt.claim.sub',h::text,true);d:=public.chaos_chat('send',g,'Hallo aus dem Test 👋',nonce);m:=(d->'messages'->0->>'id')::uuid;
 perform public.chaos_chat('send',g,'Hallo aus dem Test 👋',nonce);
 if (select count(*) from public.chaos_messages where sender=h)<>1 then raise exception 'Duplicate message';end if;
 perform set_config('request.jwt.claim.sub',g::text,true);d:=public.chaos_community();
 if (d->'friends'->0->>'unread')::integer<>1 then raise exception 'Unread count missing';end if;
 d:=public.chaos_chat('state',h);if d->'messages'->0->>'read_at' is null then raise exception 'Read acknowledgement missing';end if;
 perform public.chaos_chat('report',null,'spam',null,m);perform public.chaos_chat('block',h);
 if public.chaos_chat_visible(h,g) then raise exception 'Blocked message visible';end if;
 perform public.chaos_chat('unblock',h);
 perform set_config('request.jwt.claim.sub',h::text,true);perform public.chaos_social('challenge',null,null,null,g);
 perform set_config('request.jwt.claim.sub',g::text,true);d:=public.chaos_community();c:=(d->'challenges'->0->>'id')::uuid;
 d:=public.chaos_social('accept_challenge',null,null,null,c);
 if d->'game'->'room'->>'phase'<>'select' then raise exception 'Invite did not start match';end if;
 if (d->'game'->'room'->>'guest')::uuid<>g then raise exception 'Wrong invite guest';end if;
end;$test$;
select 'PASS: persistent private chat, once-only send, unread/read, report/block, invitation and automatic shared match. Test data rolled back.' as verification;
rollback;
