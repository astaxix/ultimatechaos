import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
let db;const h='11111111-1111-4111-8111-111111111111',g='22222222-2222-4222-8222-222222222222',stranger='33333333-3333-4333-8333-333333333333';
const wins=[[2,5,4],[0,5,6],[1,3,6],[0,1,4],[1,2,6],[2,3,4],[0,3,5]];
before(async()=>{db=new PGlite();await db.exec("create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,is_anonymous boolean not null default false,email_confirmed_at timestamptz default now());create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;");await db.exec((await readFile('supabase/migrations/001_game.sql','utf8')).replace('alter publication supabase_realtime add table public.chaos_rooms;',''));await db.exec(await readFile('supabase/migrations/003_timed_rounds.sql','utf8'));await db.exec((await readFile('supabase/migrations/004_accounts_social.sql','utf8')).replace('alter publication supabase_realtime add table public.chaos_friends,public.chaos_challenges;',''));await db.exec(await readFile('supabase/migrations/005_bot_rewards.sql','utf8'));await db.exec(await readFile('supabase/migrations/006_character_atelier.sql','utf8'));await db.exec(await readFile('supabase/migrations/007_campaign_packs.sql','utf8'));for(const id of [h,g,stranger])await db.query('insert into auth.users(id) values($1)',[id]);for(const id of [h,g,stranger]){await as(id);await db.query("select public.chaos_social('profile','Tester',4)");}});
after(async()=>db.close());
async function style(user,action,appearance=null,item=null){await as(user);return (await db.query('select public.chaos_style($1,$2::jsonb,$3) as data',[action,appearance===null?null:JSON.stringify(appearance),item])).rows[0].data;}
async function as(user){await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user??'']);}
async function raw(user,action,room=null,choice=null,name='Tester'){await as(user);const r=await db.query('select public.chaos_action($1,$2,$3,$4,$5,$6) as data',[action,room?.code??null,name,choice,room?.round_no??null,room?.match_no??null]);return r.rows[0].data;}
async function act(...args){const d=await raw(...args);if(d.error)throw new Error(d.error);return d;}
async function fresh(){await db.exec('delete from public.chaos_rooms;delete from chaos_private.limits;');const r=(await act(h,'create')).room;return (await act(g,'join',r)).room;}
async function started(){return (await act(h,'start',await fresh())).room;}
async function finish(r){await db.query("update public.chaos_rooms set select_until=clock_timestamp()-interval '1 second' where id=$1",[r.id]);return (await act(h,'state',r)).room;}
async function advance(r){await db.query("update public.chaos_rooms set next_round_at=clock_timestamp()-interval '1 second' where id=$1",[r.id]);return (await act(g,'state',r)).room;}
async function pair(r,a,b){if(a!==null)await act(h,'choose',r,a);if(b!==null)await act(g,'choose',r,b);return finish(r);}

test('five-second server window; both selections stay secret until expiry',async()=>{const r=await started();const duration=Date.parse(r.select_until)-Date.parse(r.updated_at);assert.ok(duration>4900&&duration<=5010);await act(h,'choose',r,4);await act(g,'choose',r,6);const before=await act(g,'state',r);assert.equal(before.room.phase,'select');assert.equal(before.room.host_choice,null);assert.equal(before.room.guest_choice,null);assert.equal(before.my_choice,6);assert.equal(before.room.host_score,0);const after=await finish(r);assert.equal(after.host_choice,4);assert.equal(after.guest_choice,6);assert.equal(after.host_score,1);assert.equal(after.phase,'result');});
test('all 21 pairs match the rule matrix after timeout',async()=>{for(let a=0;a<7;a++){assert.equal(wins[a].length,3);for(let b=a+1;b<7;b++){assert.notEqual(wins[a].includes(b),wins[b].includes(a));const r=await pair(await started(),a,b);assert.equal(r.winner,wins[a].includes(b)?h:g,`pair ${a},${b}`);assert.equal(r.host_score+r.guest_score,1);}}});
test('seven draws count as rounds, without awarding points',async()=>{for(let a=0;a<7;a++){let r=await pair(await started(),a,a);assert.equal(r.winner,null);assert.equal(r.host_score+r.guest_score,0);r=await advance(r);assert.equal(r.round_no,2);}});
test('choice can change until deadline; last saved choice wins; duplicate writes do not multiply points',async()=>{let r=await started();await act(h,'choose',r,0);await act(h,'choose',r,4);await act(h,'choose',r,4);await act(g,'choose',r,6);assert.equal((await act(h,'state',r)).my_choice,4);r=await finish(r);assert.equal(r.host_choice,4);assert.equal(r.host_score,1);await assert.rejects(act(h,'choose',r,0),/abgelaufen/);assert.equal((await act(h,'state',r)).room.host_score,1);});
test('late moves cannot enter a finished window, even when they trigger its resolution',async()=>{let r=await started();await act(h,'choose',r,0);await db.query("update public.chaos_rooms set select_until=clock_timestamp()-interval '1 second' where id=$1",[r.id]);const late=await raw(g,'choose',r,1);assert.match(late.error,/abgelaufen/);assert.equal(late.room.guest_choice,null);assert.equal(late.room.host_score,1);assert.equal((await act(h,'state',r)).room.phase,'result');});
test('one missed selection forfeits; two missed selections give no point',async()=>{let r=await pair(await started(),null,2);assert.equal(r.winner,g);assert.equal(r.guest_score,1);r=await pair(await started(),1,null);assert.equal(r.winner,h);r=await pair(await started(),null,null);assert.equal(r.winner,null);assert.equal(r.host_score+r.guest_score,0);});
test('round progression automatic after 6 seconds, without ready clicks; stale/invalid moves blocked',async()=>{let r=await pair(await started(),0,2);assert.equal(Date.parse(r.next_round_at)-Date.parse(r.reveal_at),6000);await assert.rejects(act(h,'ready',r),/zehn Runden/);const old=r;r=await advance(r);assert.equal(r.phase,'select');assert.equal(r.round_no,2);assert.equal(r.host_choice,null);assert.equal((await act(h,'state',r)).my_choice,null);await assert.rejects(act(h,'choose',old,0),/Runde hat sich geändert/);await assert.rejects(act(g,'choose',r,8),/Ungültiger/);});
test('exactly ten rounds even after three wins; totals can reach ten; two-sided rematch resets all',async()=>{let r=await started();for(let i=1;i<=10;i++){r=await pair(r,0,2);assert.equal(r.round_no,i);assert.equal(r.host_score,i);assert.equal(r.phase,i===10?'finished':'result');if(i<10)r=await advance(r);}assert.equal(r.match_winner,h);await assert.rejects(act(h,'ready',r),/Kampf läuft/);await db.query("update public.chaos_rooms set next_round_at=clock_timestamp()-interval '1 second' where id=$1",[r.id]);assert.equal((await act(h,'ready',r)).room.phase,'finished');r=(await act(g,'ready',r)).room;assert.equal(r.match_no,2);assert.equal(r.round_no,1);assert.equal(r.host_score+r.guest_score,0);assert.equal(r.match_winner,null);assert.equal(r.phase,'select');assert.equal(r.host_ready,false);assert.equal((await act(h,'state',r)).my_choice,null);});
test('equal overall points are a match draw; final-round winner need not be match winner',async()=>{let r=await started();for(let i=1;i<=10;i++){r=await pair(r,i%2?0:2,i%2?2:0);if(i<10)r=await advance(r);}assert.equal(r.host_score,5);assert.equal(r.guest_score,5);assert.equal(r.winner,g);assert.equal(r.match_winner,null);});
test('RPC and RLS conceal moves; foreign room access and direct score manipulation blocked',async()=>{const r=await started();await act(h,'choose',r,4);assert.equal((await act(g,'state',r)).room.host_choice,null);await assert.rejects(act(stranger,'state',r),/Kein Zugriff/);await as(g);await db.exec('set role authenticated');assert.equal((await db.query('select host_choice from public.chaos_rooms where id=$1',[r.id])).rows[0].host_choice,null);await assert.rejects(db.query('select * from chaos_private.moves'),/permission denied/);await assert.rejects(db.query('update public.chaos_rooms set host_score=10 where id=$1',[r.id]),/permission denied/);await db.exec('reset role');await as(stranger);await db.exec('set role authenticated');assert.equal((await db.query('select * from public.chaos_rooms')).rows.length,0);await db.exec('reset role');});
test('host-only start, full rooms, presence checks and reconnect during timed selection',async()=>{let r=await fresh();await assert.rejects(act(g,'start',r),/Gastgeber/);assert.match((await raw(stranger,'join',r)).error,/voll/);await db.query("update public.chaos_rooms set guest_seen=clock_timestamp()-interval '2 minutes' where id=$1",[r.id]);await assert.rejects(act(h,'start',r),/verbunden/);await act(g,'ping',r);r=(await act(h,'start',r)).room;await act(h,'choose',r,6);const resumed=await act(h,'ping',r);assert.equal(resumed.my_choice,6);assert.equal(resumed.room.select_until,r.select_until);await assert.rejects(act(null,'state',r),/anmelden/);});
test('room creation and join guessing limits, expiry and deletion cascade still apply',async()=>{await db.exec('delete from public.chaos_rooms;delete from chaos_private.limits;');let r=(await act(h,'create')).room;assert.match(r.code,/^[A-Z0-9]{6}$/);await assert.rejects(act(h,'create'),/warten/);for(let i=0;i<15;i++)assert.match((await raw(stranger,'join',{...r,code:'XXXXXX'})).error,/nicht gefunden/);assert.match((await raw(stranger,'join',r)).error,/Zu viele/);r=(await act(g,'join',r)).room;r=(await act(h,'start',r)).room;await act(h,'choose',r,0);await act(h,'leave',r);assert.equal((await db.query('select count(*)::int as n from chaos_private.moves')).rows[0].n,0);r=await fresh();await db.query("update public.chaos_rooms set updated_at=clock_timestamp()-interval '25 hours' where id=$1",[r.id]);await assert.rejects(act(h,'state',r),/abgelaufen/);});

async function soc(user,action,params={}){await as(user);const r=await db.query('select public.chaos_social($1,$2,$3,$4,$5,$6) as data',[action,params.name??null,params.avatar??null,params.code??null,params.target??null,params.item??null]);return r.rows[0].data;}
async function resetSocial(){await db.exec("delete from public.chaos_rooms;delete from public.chaos_friends;delete from chaos_private.limits;delete from chaos_private.inventory;delete from chaos_private.packs;delete from chaos_private.loot_receipts;update public.chaos_profiles set xp=0,coins=250,matches=0,wins=0,frame='basic';");}
async function friendship(){await resetSocial();const code=(await soc(g,'state')).profile.friend_code;await soc(h,'add_friend',{code});const incoming=(await soc(g,'state')).friends[0];await soc(g,'accept_friend',{target:incoming.id});return incoming.id;}

test('account onboarding requires confirmed registered identity; profile creation does not mint repeated starter coins',async()=>{
 await resetSocial();const newId='44444444-4444-4444-8444-444444444444';await db.query('insert into auth.users(id,is_anonymous,email_confirmed_at) values($1,true,null)',[newId]);await assert.rejects(soc(newId,'profile',{name:'New hero',avatar:4}),/bestätigten Konto/);await db.query('update auth.users set is_anonymous=false where id=$1',[newId]);await assert.rejects(soc(newId,'state'),/bestätigten Konto/);await db.query('update auth.users set email_confirmed_at=now() where id=$1',[newId]);assert.equal((await soc(newId,'state')).profile,null);await assert.rejects(act(newId,'create'),/Profil einrichten/);const d=await soc(newId,'profile',{name:'New hero',avatar:3});assert.equal(d.profile.coins,0);assert.match(d.profile.friend_code,/^[A-F0-9]{8}$/);const edited=await soc(newId,'profile',{name:'Edited hero',avatar:6});assert.equal(edited.profile.coins,0);assert.equal(edited.profile.avatar,6);await assert.rejects(soc(newId,'profile',{name:'X',avatar:10}),/ungültig/);await db.query('delete from auth.users where id=$1',[newId]);
});
test('friend requests deduplicated, private, recipient-only acceptance and removal authorized',async()=>{
 await resetSocial();const code=(await soc(g,'state')).profile.friend_code;await soc(h,'add_friend',{code});await soc(h,'add_friend',{code});assert.equal((await soc(h,'state')).friends.length,1);assert.equal((await soc(stranger,'state')).friends.length,0);const f=(await soc(h,'state')).friends[0];assert.equal(f.incoming,false);await assert.rejects(soc(h,'accept_friend',{target:f.id}),/Empfänger/);await assert.rejects(soc(stranger,'accept_friend',{target:f.id}),/Kein Zugriff/);await soc(g,'accept_friend',{target:f.id});assert.equal((await soc(h,'state')).friends[0].status,'accepted');await soc(h,'remove_friend',{target:f.id});assert.equal((await soc(g,'state')).friends.length,0);await assert.rejects(soc(h,'add_friend',{code:(await soc(h,'state')).profile.friend_code}),/eigener Code/);
});
test('friend challenges reserve guest slot, reject outsiders and create real joined lobbies',async()=>{
 await assert.rejects(soc(h,'challenge',{target:g}),/bestätigte Freunde/);await friendship();const created=await soc(h,'challenge',{target:g});assert.ok(created.game.room.code);const incoming=(await soc(g,'state')).challenges[0];assert.equal(incoming.incoming,true);assert.equal((await soc(stranger,'state')).challenges.length,0);await assert.rejects(act(stranger,'join',created.game.room),/reserviert/);await assert.rejects(soc(stranger,'accept_challenge',{target:incoming.id}),/nicht verfügbar/);await assert.rejects(soc(h,'challenge',{target:g}),/bereits offen/);const accepted=await soc(g,'accept_challenge',{target:incoming.id});assert.equal(accepted.game.room.guest,g);assert.equal(accepted.game.room.phase,'lobby');await assert.rejects(soc(g,'accept_challenge',{target:incoming.id}),/nicht verfügbar/);
});
test('cosmetic purchases atomic, server-priced, immutable currency and owned-only equipping',async()=>{
 await resetSocial();await assert.rejects(soc(h,'buy',{item:'gold'}),/Nicht genügend/);await assert.rejects(soc(h,'equip',{item:'celestial'}),/besitzt du nicht/);await assert.rejects(soc(h,'buy',{item:'free-coins'}),/nicht gefunden/);let d=await soc(h,'buy',{item:'violet'});assert.equal(d.profile.coins,100);assert.deepEqual(d.inventory,['violet']);await assert.rejects(soc(h,'buy',{item:'violet'}),/bereits/);assert.equal((await soc(h,'state')).profile.coins,100);d=await soc(h,'equip',{item:'violet'});assert.equal(d.profile.frame,'violet');d=await soc(h,'equip',{item:'basic'});assert.equal(d.profile.frame,'basic');await as(h);await db.exec('set role authenticated');await assert.rejects(db.query('update public.chaos_profiles set coins=999999 where id=$1',[h]),/permission denied/);await assert.rejects(db.query('select * from chaos_private.inventory'),/permission denied/);assert.equal((await db.query('select * from public.chaos_profiles')).rows.length,1);await db.exec('reset role');
});
test('match rewards and XP granted once, activity required; profile names are authoritative',async()=>{
 await resetSocial();let r=await started();assert.equal(r.host_name,'Tester');for(let i=1;i<=10;i++){r=await pair(r,0,2);if(i<10)r=await advance(r);}let a=(await soc(h,'state')).profile,b=(await soc(g,'state')).profile;assert.equal(a.coins,350);assert.equal(a.xp,120);assert.equal(a.matches,1);assert.equal(a.wins,1);assert.equal(b.coins,250);assert.equal(b.xp,40);await act(h,'state',r);await act(g,'ping',r);a=(await soc(h,'state')).profile;assert.equal(a.coins,350);await resetSocial();r=await started();for(let i=1;i<=10;i++){r=await pair(r,null,2);if(i<10)r=await advance(r);}assert.equal((await soc(h,'state')).profile.coins,250);assert.equal((await soc(h,'state')).profile.xp,0);assert.equal((await soc(g,'state')).profile.coins,350);
});

async function botNext(r){await db.query("update public.chaos_rooms set next_round_at=clock_timestamp()-interval '1 second' where id=$1",[r.id]);return (await act(h,'state',r)).room;}
async function botMove(r){return (await db.query('select choice from chaos_private.moves where room_id=$1 and match_no=$2 and round_no=$3 and player=$4',[r.id,r.match_no,r.round_no,r.guest])).rows[0].choice;}
test('bot commits a hidden move before input, cannot be joined, and survives polling without changing it',async()=>{
 await resetSocial();let r=(await act(h,'bot')).room;assert.equal(r.is_bot,true);assert.equal(r.phase,'select');assert.equal(r.guest_name,'Chaos-Bot');assert.equal(r.guest_choice,null);const move=await botMove(r);
 await assert.rejects(act(g,'join',r),/Bot/);await assert.rejects(act(stranger,'state',r),/Zugriff/);
 await act(h,'choose',r,0);await act(h,'choose',r,1);const state=await act(h,'state',r);assert.equal(state.room.guest_choice,null);assert.equal(state.my_choice,1);assert.equal(await botMove(r),move);
 const updated=state.room.updated_at;assert.equal((await act(h,'state',r)).room.updated_at,updated);
 r=await finish(r);assert.equal(r.guest_choice,move);assert.equal(r.host_choice,1);
});
test('bot has ten rounds, awards a real victory once, returns receipts, and supports a one-player rematch',async()=>{
 await resetSocial();let r=(await act(h,'bot')).room;
 for(let round=1;round<=10;round++){const move=await botMove(r);const win=wins.findIndex(list=>list.includes(move));await act(h,'choose',r,win);r=await finish(r);assert.equal(r.round_no,round);assert.equal(r.host_score,round);if(round<10)r=await botNext(r);}
 assert.equal(r.phase,'finished');assert.equal(r.match_winner,h);const receipt=await act(h,'state',r);assert.deepEqual(receipt.rewards,{xp:120,coins:100,total_xp:120});assert.equal((await soc(h,'state')).profile.coins,350);
 await act(h,'ping',r);assert.equal((await soc(h,'state')).profile.xp,120);assert.equal((await db.query('select count(*)::int as n from chaos_private.rewards where room_id=$1',[r.id])).rows[0].n,1);
 await db.query("update public.chaos_rooms set next_round_at=clock_timestamp()-interval '1 second' where id=$1",[r.id]);r=(await act(h,'ready',r)).room;assert.equal(r.match_no,2);assert.equal(r.round_no,1);assert.equal(r.phase,'select');assert.equal(r.host_score+r.guest_score,0);assert.equal(r.guest_choice,null);assert.ok(Number.isInteger(await botMove(r)));
});
test('defeats and draws earn XP but never Chaos Coins; partial active participation still earns XP',async()=>{
 for(const outcome of ['loss','draw','partial']){
  await resetSocial();let r=(await act(h,'bot')).room;
  for(let round=1;round<=10;round++){const move=await botMove(r);if(outcome!=='partial'||round===1)await act(h,'choose',r,outcome==='draw'?move:wins[move][0]);r=await finish(r);if(round<10)r=await botNext(r);}
  const profile=(await soc(h,'state')).profile;assert.equal(profile.coins,250);assert.equal(profile.xp,outcome==='draw'?60:40);assert.equal(profile.matches,1);const d=await act(h,'state',r);assert.equal(d.rewards.coins,0);
 }
});

test('appearance persists and rejects arbitrary values, paid equipment and cross-account writes',async()=>{
 await resetSocial();let d=await style(h,'appearance',{body:'feminine',hair:'braids',skin:'#704733',hairColor:'#30251f',eyes:'#63b5bd',face:'angular',beard:'none',brows:'bold',outfitColor:'#35665d'});
 assert.equal(d.profile.appearance.body,'feminine');assert.equal((await soc(h,'state')).profile.appearance.hair,'braids');
 assert.equal((await soc(g,'state')).profile.appearance.hair,'swept');
 await assert.rejects(style(h,'appearance',{skin:'url(evil)'}),/Farbe/);
 await assert.rejects(style(h,'appearance',{hair:'hacked'}),/Frisur/);
 await assert.rejects(style(h,'appearance',{coins:'99999'}),/Unbekannte/);
 await assert.rejects(style(h,'appearance',{outfit:'armor-solstice'}),/Sammlung/);
 await assert.rejects(style(null,'appearance',{}),/anmelden/);
});
test('wardrobe prices and equipment are server-controlled, purchases deduct once and slots preserve each other',async()=>{
 await resetSocial();await assert.rejects(style(h,'equip',null,'armor-solstice'),/besitzt/);
 await assert.rejects(style(h,'buy',null,'aura-void'),/Nicht genügend/);
 let d=await style(h,'buy',null,'hat-beanie');assert.equal(d.profile.coins,100);
 await assert.rejects(style(h,'buy',null,'hat-beanie'),/bereits/);
 d=await style(h,'equip',null,'hat-beanie');assert.equal(d.profile.appearance.hat,'hat-beanie');
 await db.query('update public.chaos_profiles set coins=2000 where id=$1',[h]);
 await style(h,'buy',null,'robe-astral');await style(h,'equip',null,'robe-astral');
 await style(h,'buy',null,'aura-frost');d=await style(h,'equip',null,'aura-frost');
 assert.equal(d.profile.appearance.outfit,'robe-astral');assert.equal(d.profile.appearance.hat,'hat-beanie');assert.equal(d.profile.appearance.aura,'aura-frost');
 assert.equal(d.profile.coins,950);d=await style(h,'equip',null,'hat:reset');assert.equal(d.profile.appearance.hat,'none');assert.equal(d.profile.appearance.aura,'aura-frost');
 await assert.rejects(style(h,'buy',null,'free-coins'),/nicht gefunden/);
 await as(h);await db.exec('set role authenticated');
 await assert.rejects(db.query("update public.chaos_profiles set appearance='{}' where id=$1",[h]),/permission denied/);
 await assert.rejects(db.query('select * from chaos_private.styles'),/permission denied/);
 await db.exec('reset role');
});
test('authorized friends and match participants see character looks; private choices and wallet stay scoped',async()=>{
 await friendship();await style(h,'appearance',{hair:'long'});const friends=(await soc(g,'state')).friends;assert.equal(friends[0].profile.appearance.hair,'long');
 const r=await started();await act(h,'choose',r,4);const state=await act(g,'state',r);
 assert.equal(state.players.host.appearance.hair,'long');assert.equal(state.my_choice,null);assert.equal(state.room.host_choice,null);
 assert.equal(state.wallet.coins,(await soc(g,'state')).profile.coins);
 await assert.rejects(act(stranger,'state',r),/Zugriff/);
 await as(h);await db.exec('set role authenticated');await assert.rejects(db.query("select chaos_private.chaos_action_v5('state',$1)",[r.code]),/permission denied/);await db.exec('reset role');
});

async function campaignStart(user,stage){await as(user);return (await db.query('select public.chaos_campaign($1) as data',[stage])).rows[0].data;}
async function loot(user,action,tier,id){await as(user);return (await db.query('select public.chaos_loot($1,$2,$3) as data',[action,tier,id])).rows[0].data;}
test('campaign gates chapters; a victory unlocks the next and pays the configured reward once',async()=>{
 await resetSocial();await db.exec('update public.chaos_profiles set campaign_unlocked=0');
 await assert.rejects(campaignStart(h,1),/gesperrt/);let r=(await campaignStart(h,0)).room;
 assert.equal(r.guest_name,'Milo');assert.equal(r.round_limit,10);
 for(let i=1;i<=10;i++){const b=await botMove(r);await act(h,'choose',r,wins.findIndex(a=>a.includes(b)));r=await finish(r);if(i<10)r=await botNext(r);}
 let d=await soc(h,'state');assert.equal(d.profile.campaign_unlocked,1);assert.equal(d.profile.xp,120);assert.equal(d.profile.coins,350);
 const receipt=await act(h,'state',r);assert.equal(receipt.rewards.coins,100);assert.equal((await soc(h,'state')).profile.xp,120);
});
test('bosses run their full round count and require the stated number of wins',async()=>{
 await resetSocial();await db.query('update public.chaos_profiles set campaign_unlocked=7 where id=$1',[h]);
 let r=(await campaignStart(h,3)).room;assert.equal(r.round_limit,14);assert.equal(r.required_wins,8);
 for(let i=1;i<=14;i++){const b=await botMove(r);await act(h,'choose',r,i<=7?wins.findIndex(a=>a.includes(b)):b);r=await finish(r);if(i<14){assert.notEqual(r.phase,'finished');r=await botNext(r);}}
 assert.equal(r.host_score,7);assert.equal(r.guest_score,0);assert.equal(r.match_winner,r.guest);assert.equal((await soc(h,'state')).profile.coins,250);
 await db.exec('delete from public.chaos_rooms;delete from chaos_private.limits');
 r=(await campaignStart(h,7)).room;
 for(let i=1;i<=18;i++){const b=await botMove(r);await act(h,'choose',r,wins.findIndex(a=>a.includes(b)));r=await finish(r);if(i<18)r=await botNext(r);}
 assert.equal(r.host_score,18);const d=await act(h,'state',r);assert.equal(d.rewards.xp,600);assert.equal(d.rewards.coins,600);assert.equal((await soc(h,'state')).profile.campaign_unlocked,8);
});
test('level crossings grant exactly one standard pack per new level; repeated reads do not grant more',async()=>{
 await resetSocial();await db.query('update public.chaos_profiles set xp=240 where id=$1',[h]);
 let r=(await act(h,'bot')).room;for(let i=1;i<=10;i++){const b=await botMove(r);await act(h,'choose',r,wins.findIndex(a=>a.includes(b)));r=await finish(r);if(i<10)r=await botNext(r);}
 assert.equal((await soc(h,'state')).packs['0'],1);await act(h,'state',r);assert.equal((await soc(h,'state')).packs['0'],1);
 await db.query('update public.chaos_profiles set xp=xp+500 where id=$1',[h]);assert.equal((await soc(h,'state')).packs['0'],3);
});
test('pack purchases and openings are idempotent, private, server-priced and require owned packs',async()=>{
 await resetSocial();const id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 await assert.rejects(loot(h,'open',0,id),/Kein Pack/);let d=await loot(h,'buy',0,id);assert.equal(d.profile.coins,100);assert.equal(d.packs['0'],1);
 d=await loot(h,'buy',0,id);assert.equal(d.profile.coins,100);assert.equal(d.packs['0'],1);
 await assert.rejects(loot(g,'buy',0,id),/ungültig/);await assert.rejects(loot(h,'buy',2,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),/Nicht genügend/);
 const openId='cccccccc-cccc-4ccc-8ccc-cccccccccccc';d=await loot(h,'open',0,openId);const reward=d.loot;assert.equal(d.packs['0'],0);
 const repeat=await loot(h,'open',0,openId);assert.deepEqual(repeat.loot,reward);assert.equal(repeat.profile.coins,d.profile.coins);
 await assert.rejects(loot(h,'open',0,'dddddddd-dddd-4ddd-8ddd-dddddddddddd'),/Kein Pack/);
 await as(h);await db.exec('set role authenticated');await assert.rejects(db.query('select * from chaos_private.packs'),/permission denied/);await assert.rejects(db.query('select * from chaos_private.loot_receipts'),/permission denied/);await db.exec('reset role');
});
test('loot grants actual items and coins, empty packs consume one, duplicates convert and card designs equip separately',async()=>{
 await resetSocial();await db.query('insert into chaos_private.packs values($1,0,200)',[h]);await db.exec('select setseed(0.42)');
 const kinds=new Set();for(let i=0;i<200;i++){const id='eeeeeeee-eeee-4eee-8eee-'+String(i).padStart(12,'0');const d=await loot(h,'open',0,id);kinds.add(d.loot.kind);if(d.loot.kind==='item')assert.ok(d.inventory.includes(d.loot.item));}
 assert.ok(kinds.has('empty'));assert.ok(kinds.has('coins'));assert.ok(kinds.has('item'));assert.ok(kinds.has('duplicate'));
 await db.query("insert into chaos_private.inventory values($1,'card-frost') on conflict do nothing",[h]);let d=await style(h,'equip',null,'card-frost');assert.equal(d.profile.card_skin,'card-frost');assert.equal(d.profile.appearance.outfit,'robe-astral');
 d=await style(h,'equip',null,'card:reset');assert.equal(d.profile.card_skin,'classic');
});

test('advanced campaign prediction uses previous rounds and never replaces the already committed active choice',async()=>{
 await resetSocial();await db.query('update public.chaos_profiles set campaign_unlocked=7 where id=$1',[h]);let r=(await campaignStart(h,7)).room;
 await act(h,'choose',r,0);r=await finish(r);r=await botNext(r);const committed=await botMove(r);await act(h,'choose',r,4);await act(h,'choose',r,6);assert.equal(await botMove(r),committed);
 const state=await act(h,'state',r);assert.equal(state.room.guest_choice,null);
 await db.exec('select setseed(0.18)');const predictions=await db.query('select chaos_private.bot_choice(r) choice from public.chaos_rooms r cross join generate_series(1,100) where r.id=$1',[r.id]);
 assert.ok(predictions.rows.filter(x=>wins[x.choice].includes(0)).length>=70);
});
test('all displayed wardrobe and card-set prices match the authoritative server catalog',async()=>{
 const {styleCatalog}=await import('../src/appearance.ts');const stored=(await db.query('select id,slot,price,rarity from chaos_private.styles')).rows;
 assert.equal(styleCatalog.length,stored.length);for(const item of styleCatalog){const server=stored.find(x=>x.id===item.id);assert.equal(server.price,item.price);assert.equal(server.slot,item.slot);assert.equal(server.rarity,{SELTEN:1,EPISCH:2,LEGENDÄR:3}[item.rarity]);}
});
