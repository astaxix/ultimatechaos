begin;
alter table public.chaos_rooms add column if not exists is_bot boolean not null default false;
alter table public.chaos_profiles alter column coins set default 0;

create or replace function chaos_private.reward_match() returns trigger
language plpgsql security definer set search_path='' as $$
declare p uuid; inserted integer; coin_reward integer; xp_reward integer;
begin
 if new.phase='finished' and (old.phase is distinct from new.phase or old.match_no<>new.match_no) then
  for p in select id from (select new.host as id union select new.guest as id where not new.is_bot) players order by id loop
   -- A completed match with at least one move earns XP. AFK sessions earn nothing.
   if p is not null and exists(select 1 from chaos_private.moves where room_id=new.id and match_no=new.match_no and player=p) then
    insert into chaos_private.rewards values(new.id,new.match_no,p) on conflict do nothing;
    get diagnostics inserted=row_count;
    if inserted=1 then
     coin_reward:=case when new.match_winner=p then 100 else 0 end;
     xp_reward:=case when new.match_winner=p then 120 when new.match_winner is null then 60 else 40 end;
     update public.chaos_profiles set coins=coins+coin_reward,xp=xp+xp_reward,matches=matches+1,wins=wins+case when new.match_winner=p then 1 else 0 end where id=p;
    end if;
   end if;
  end loop;
 end if;
 return new;
end;
$$;
revoke all on function chaos_private.reward_match() from public,anon,authenticated;

create or replace function public.chaos_action(action text,room_code text default null,player_name text default null,choice integer default null,expected_round integer default null,expected_match integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid(); p public.chaos_profiles; r public.chaos_rooms; d jsonb; reserved uuid; bot_move integer;
begin
 select * into p from public.chaos_profiles where id=u;
 if p.id is null then raise exception 'Bitte zuerst dein Profil einrichten'; end if;
 if action='bot' then
  d:=chaos_private.play('create',null,p.name,null,null,null);
  select * into r from public.chaos_rooms where id=(d->'room'->>'id')::uuid for update;
  update public.chaos_rooms set is_bot=true,guest=gen_random_uuid(),guest_name='Chaos-Bot',guest_seen=clock_timestamp(),phase='select',select_until=clock_timestamp()+interval '5 seconds',guest_locked=true,updated_at=clock_timestamp() where id=r.id returning * into r;
  -- Commit the random bot move before the player receives the selection screen.
  insert into chaos_private.moves values(r.id,r.match_no,r.round_no,r.guest,floor(random()*7)::integer);
  return chaos_private.play('state',r.code,p.name,null,null,null);
 end if;
 select * into r from public.chaos_rooms where code=upper(trim(room_code)) for update;
 if action='join' then
  reserved:=r.reserved_guest;
  if r.is_bot and u<>r.host then raise exception 'Dies ist ein Duell gegen den Bot'; end if;
  if reserved is not null and reserved<>u and u<>r.host then raise exception 'Dieser Raum ist für einen herausgeforderten Freund reserviert'; end if;
 end if;
 if r.is_bot then
  if u<>r.host then raise exception 'Kein Zugriff auf dieses Bot-Duell'; end if;
  update public.chaos_rooms set guest_seen=clock_timestamp(),guest_ready=case when action='ready' then true else guest_ready end where id=r.id and (guest_seen<clock_timestamp()-interval '20 seconds' or (action='ready' and not guest_ready));
 end if;
 d:=chaos_private.play(action,room_code,p.name,choice,expected_round,expected_match);
 if d->>'left'='true' then return d; end if;
 if r.is_bot then
  select * into r from public.chaos_rooms where id=r.id;
  if r.phase='select' then
   -- Repeated reads cannot replace the precommitted choice. No client choice is read.
   bot_move:=floor(random()*7)::integer;
   insert into chaos_private.moves values(r.id,r.match_no,r.round_no,r.guest,bot_move) on conflict do nothing;
   update public.chaos_rooms set guest_locked=true where id=r.id and not guest_locked;
   select * into r from public.chaos_rooms where id=r.id;
  end if;
  d:=jsonb_set(d,'{room}',to_jsonb(r));
 end if;
 if d->'room'->>'phase'='finished' and exists(select 1 from chaos_private.rewards where room_id=(d->'room'->>'id')::uuid and match_no=(d->'room'->>'match_no')::integer and player=u) then
  d:=d||jsonb_build_object('rewards',jsonb_build_object('xp',case when d->'room'->>'match_winner'=u::text then 120 when d->'room'->>'match_winner' is null then 60 else 40 end,'coins',case when d->'room'->>'match_winner'=u::text then 100 else 0 end,'total_xp',(select xp from public.chaos_profiles where id=u)));
 end if;
 return d;
end;
$$;
revoke all on function public.chaos_action(text,text,text,integer,integer,integer) from public,anon;
grant execute on function public.chaos_action(text,text,text,integer,integer,integer) to authenticated;
commit;
