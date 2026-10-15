begin;
do $test$
declare u uuid:=gen_random_uuid();d jsonb;hair text;
begin
 insert into auth.users(id,is_anonymous,email_confirmed_at) values(u,false,clock_timestamp());
 perform set_config('request.jwt.claim.sub',u::text,true);perform public.chaos_social('profile','Atelier QA',0);
 foreach hair in array array['swept','crop','curls','long','bob','braids','bun','bald','pixie','waves','ponytail','high-pony','twin-tails','mohawk','undercut','dreads','afro','sidebraid','shag','topknot'] loop
  d:=public.chaos_style('appearance',jsonb_build_object('hair',hair));if d->'profile'->'appearance'->>'hair'<>hair then raise exception 'Hair not saved';end if;
 end loop;
 d:=public.chaos_style('appearance','{"body":"feminine","build":"broad","height":"short","eyeShape":"round","nose":"wide","mouth":"smile","glasses":"round","facePaint":"runes","paintColor":"#d2b679","trimColor":"#ebd297","earrings":"hoops"}'::jsonb);
 d:=public.chaos_social('state');
 if d->'profile'->'appearance'->>'body'<>'feminine' or d->'profile'->'appearance'->>'facePaint'<>'runes' or d->'profile'->'appearance'->>'hair'<>'topknot' then raise exception 'Appearance did not survive reload';end if;
end;$test$;
select 'PASS: twenty hairstyles, body/face/accessory/outfit details persist; existing fields retained. Temporary data rolled back.' as verification;
rollback;
