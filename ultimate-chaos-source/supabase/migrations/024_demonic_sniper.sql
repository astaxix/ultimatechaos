begin;
-- Existing matches retain seven-card rules; new matches use the balanced eight.
alter table public.chaos_rooms add column power_count integer not null default 7 check(power_count in(7,8));
alter table public.chaos_rooms alter column power_count set default 8;
create function chaos_private.beats_for(a integer,b integer,n integer) returns boolean language sql immutable set search_path='' as $$
 select case when n=7 then chaos_private.beats(a,b) else case a
 when 0 then b in(2,5,7) when 1 then b in(0,6,7) when 2 then b in(1,3,7)
 when 3 then b in(0,1,4) when 4 then b in(1,2,6) when 5 then b in(2,3,4)
 when 6 then b in(0,3,5) when 7 then b in(4,5,6) else false end end;
$$;
do $$declare c record;definition text;begin
 for c in select n.nspname,t.relname,x.conname,pg_get_constraintdef(x.oid) d from pg_constraint x join pg_class t on t.oid=x.conrelid join pg_namespace n on n.oid=t.relnamespace where x.contype='c' and (n.nspname,t.relname) in(('public','chaos_rooms'),('chaos_private','moves'),('chaos_private','styles'),('chaos_private','cosmetic_catalog')) loop
  if c.d like '%<= 6%' then
   execute format('alter table %I.%I drop constraint %I',c.nspname,c.relname,c.conname);
   execute format('alter table %I.%I add constraint %I %s',c.nspname,c.relname,c.conname,replace(c.d,'<= 6','<= 7'));
  end if;
 end loop;
 definition:=pg_get_functiondef('chaos_private.advance_lives_v8(public.chaos_rooms)'::regprocedure);
 if position('if a<>b then' in definition)=0 then raise exception 'Unexpected round engine';end if;
 definition:=replace(definition,'random()*7','random()*r.power_count');
 definition:=replace(definition,'if a<>b then','if chaos_private.beats_for(a,b,r.power_count) or chaos_private.beats_for(b,a,r.power_count) then');
 definition:=replace(definition,'chaos_private.beats(a,b)','chaos_private.beats_for(a,b,r.power_count)');execute definition;
 definition:=pg_get_functiondef('chaos_private.chaos_action_v8(text,text,text,integer,integer,integer)'::regprocedure);
 if position('choice not between 0 and 6' in definition)=0 then raise exception 'Unexpected choice validation';end if;
 definition:=replace(definition,'choice not between 0 and 6','choice not between 0 and (r.power_count-1)');
 definition:=replace(definition,'r.phase:=''select'';','r.power_count:=8;r.phase:=''select'';');execute definition;
 definition:=pg_get_functiondef('chaos_private.advance_lives_v20(public.chaos_rooms)'::regprocedure);
 definition:=replace(definition,'r.match_no:=r.match_no+1;','r.power_count:=8;r.match_no:=r.match_no+1;');execute definition;
 definition:=pg_get_functiondef('chaos_private.bot_choice(public.chaos_rooms)'::regprocedure);
 definition:=replace(definition,'generate_series(0,6)','generate_series(0,r.power_count-1)');
 definition:=replace(definition,'chaos_private.beats(n,predicted)','chaos_private.beats_for(n,predicted,r.power_count)');
 definition:=replace(definition,'random()*7','random()*r.power_count');execute definition;
 definition:=pg_get_functiondef('public.chaos_collection(text,integer,text,text)'::regprocedure);
 definition:=replace(definition,'power_index not between 0 and 6','power_index not between 0 and 7');execute definition;
 definition:=pg_get_functiondef('chaos_private.record_journal()'::regprocedure);
 definition:=replace(definition,'generate_series(0,6)','generate_series(0,7)');execute definition;
 definition:=pg_get_functiondef('public.chaos_journal(text,text)'::regprocedure);
 definition:=replace(definition,'generate_series(0,6)','generate_series(0,7)');execute definition;
end;$$;
create function chaos_private.match_card_rules() returns trigger language plpgsql set search_path='' as $$
begin
 if new.rules_version=2 and ((old.phase='lobby' and new.phase='select') or old.match_no<>new.match_no) then new.power_count:=8;end if;
 return new;
end;$$;
create trigger a0_match_card_rules before update on public.chaos_rooms for each row execute function chaos_private.match_card_rules();
revoke all on all functions in schema chaos_private from public,anon,authenticated;
commit;
