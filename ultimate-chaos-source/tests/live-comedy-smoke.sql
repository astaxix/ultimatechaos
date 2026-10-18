-- Generated identity, all player and purchase writes roll back.
begin;
do $test$
declare u uuid:=gen_random_uuid();r uuid:=gen_random_uuid();i record;a jsonb;b jsonb;d jsonb;
begin
 if(select count(*)from chaos_private.consumables where id in('laura-mice','tyson-cloud','wet-rosette','maniac','epstein-flute'))<>5 then raise exception 'Comedy catalog missing';end if;
 d:=chaos_private.item_outcome('{"hp":3,"max":5,"burn":3,"shield":0,"card":0,"item":"wet-rosette"}','{"hp":5,"max":5,"burn":0,"shield":0,"card":1}',8,.1,.1);
 if(d->>'host_hp')::int<>4 or(d->>'host_burn')::int<>0 then raise exception 'Rosette resolver mismatch';end if;
 d:=chaos_private.item_outcome('{"hp":5,"max":5,"burn":0,"shield":0,"card":0,"item":"laura-mice"}','{"hp":5,"max":5,"burn":0,"shield":0,"card":1,"item":"fireball"}',8,.99,.99);
 if(d->>'guest_damage')::int<>3 then raise exception 'Mice resolver mismatch';end if;
 insert into auth.users(id,is_anonymous,email_confirmed_at)values(u,false,clock_timestamp());perform set_config('request.jwt.claim.sub',u::text,true);perform public.chaos_social('profile','Comedy item QA',0);update public.chaos_profiles set coins=5000 where id=u;
 for i in select * from chaos_private.consumables where id in('laura-mice','tyson-cloud','wet-rosette','maniac','epstein-flute')loop
 r:=gen_random_uuid();a:=public.chaos_items('buy',i.id,1,i.price,r);b:=public.chaos_items('buy',i.id,1,i.price,r);if a->'stock'<>b->'stock' or(a->'stock'->>i.id)::int<>1 then raise exception 'Purchase receipt mismatch: %',i.id;end if;
 end loop;
end;$test$;
select 'COMEDY_ITEMS_OK' as verification;
rollback;
