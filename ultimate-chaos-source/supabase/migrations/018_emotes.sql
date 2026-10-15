begin;
alter table public.chaos_rooms add column host_emote text;
alter table public.chaos_rooms add column guest_emote text;
alter table public.chaos_rooms add column host_emote_at timestamptz;
alter table public.chaos_rooms add column guest_emote_at timestamptz;
create function public.chaos_emote(room_code text,emote_id text) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=chaos_private.account_uid();r public.chaos_rooms;last_sent timestamptz;
begin
 select * into r from public.chaos_rooms where code=upper(trim(room_code)) for update;
 if r.id is null or(u<>r.host and u is distinct from r.guest) or r.updated_at<clock_timestamp()-interval '24 hours' then raise exception 'Kein Zugriff auf diesen Raum';end if;
 if emote_id is null or (emote_id not in('wave','gg') and not exists(select 1 from chaos_private.inventory i join chaos_private.styles s on s.id=i.item where i.player=u and s.slot='emote' and s.id=emote_id)) then raise exception 'Emote nicht freigeschaltet';end if;
 last_sent:=case when u=r.host then r.host_emote_at else r.guest_emote_at end;
 if last_sent>clock_timestamp()-interval '3 seconds' then raise exception 'Bitte kurz warten';end if;
 if u=r.host then update public.chaos_rooms set host_emote=emote_id,host_emote_at=clock_timestamp(),host_seen=clock_timestamp(),updated_at=clock_timestamp() where id=r.id returning * into r;
 else update public.chaos_rooms set guest_emote=emote_id,guest_emote_at=clock_timestamp(),guest_seen=clock_timestamp(),updated_at=clock_timestamp() where id=r.id returning * into r;end if;
 return chaos_private.life_snapshot(r,u);
end;$$;
revoke all on function public.chaos_emote(text,text) from public,anon;
grant execute on function public.chaos_emote(text,text) to authenticated;
commit;
