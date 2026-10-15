import {test,before,after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
const h='11111111-1111-4111-8111-111111111111',g='22222222-2222-4222-8222-222222222222',outsider='33333333-3333-4333-8333-333333333333';
const wins=[[2,5,4],[0,5,6],[1,3,6],[0,1,4],[1,2,6],[2,3,4],[0,3,5]];
let db,legacy;
async function as(u){await db.query("select set_config('request.jwt.claim.sub',$1,false)",[u??'']);}
async function raw(u,action,r=null,choice=null){await as(u);return (await db.query('select public.chaos_action($1,$2,null,$3,$4,$5) d',[action,r?.code??null,choice,r?.round_no??null,r?.match_no??null])).rows[0].d;}
async function act(...args){const d=await raw(...args);if(d.error)throw Error(d.error);return d;}
async function state(u){await as(u);return (await db.query("select public.chaos_social('state') d")).rows[0].d;}
async function reset(){await db.exec("delete from chaos_private.endless_runs;delete from public.chaos_rooms;delete from chaos_private.limits;update public.chaos_profiles set coins=250,xp=0,matches=0,wins=0,campaign_unlocked=0,endless_best=0;delete from chaos_private.packs;");}
async function room(){await reset();let r=(await act(h,'create')).room;r=(await act(g,'join',r)).room;return (await act(h,'start',r)).room;}
async function next(r){await db.query("update public.chaos_rooms set next_round_at=clock_timestamp()-interval '1 second' where id=$1",[r.id]);return (await act(h,'state',r)).room;}
async function finish(r){await db.query("update public.chaos_rooms set select_until=clock_timestamp()-interval '1 second' where id=$1",[r.id]);return (await act(h,'state',r)).room;}
async function pair(r,a,b){await act(h,'choose',r,a);await act(g,'choose',r,b);await act(h,'confirm',r);return (await act(g,'confirm',r)).room;}
async function botMove(r){return (await db.query('select choice from chaos_private.moves where room_id=$1 and match_no=$2 and round_no=$3 and player=$4',[r.id,r.match_no,r.round_no,r.guest])).rows[0].choice;}
async function campaign(stage){await as(h);return (await db.query('select public.chaos_campaign($1) d',[stage])).rows[0].d.room;}
before(async()=>{
 db=new PGlite();await db.exec("create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,is_anonymous boolean not null default false,email_confirmed_at timestamptz default now());create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;");
 for(const file of ['001_game','003_timed_rounds','004_accounts_social','005_bot_rewards','006_character_atelier','007_campaign_packs']){
  const sql=(await readFile('supabase/migrations/'+file+'.sql','utf8')).replace(/alter publication supabase_realtime add table[^;]+;/g,'');await db.exec(sql);
 }
 for(const id of [h,g,outsider]){await db.query('insert into auth.users(id) values($1)',[id]);await as(id);await db.query("select public.chaos_social('profile','Tester',0)");}
 legacy=(await act(h,'create')).room;legacy=(await act(g,'join',legacy)).room;
 await db.exec(await readFile('supabase/migrations/008_life_duels.sql','utf8'));
 await db.exec(await readFile('supabase/migrations/009_endless_arena.sql','utf8'));
 for(const name of ['010_ranked_queue','011_private_chat','012_chat_unblock','013_character_editor','014_character_details','015_cosmetic_catalog','016_equipment','017_shop','018_emotes','019_packs'])await db.exec((await readFile('supabase/migrations/'+name+'.sql','utf8')).replace(/alter publication supabase_realtime add table[^;]+;/g,''));
});
after(async()=>db.close());
test('migration preserves existing profiles, inventory and the old match rules',async()=>{
 assert.equal((await state(h)).profile.name,'Tester');assert.equal((await state(h)).profile.coins,0);
 const r=(await act(h,'start',legacy)).room;assert.equal(r.rules_version,1);
 assert.ok(Date.parse(r.select_until)-Date.parse(r.updated_at)<5100);
 await act(h,'choose',r,0);await act(g,'choose',r,2);const result=await finish(r);assert.equal(result.host_score,1);assert.equal(result.phase,'result');
});
test('new duels start at 5 hearts and a server-controlled 10-second window',async()=>{
 const r=await room();assert.equal(r.rules_version,2);assert.equal(r.host_hp,5);assert.equal(r.guest_hp,5);
 assert.ok(Date.parse(r.select_until)-Date.parse(r.updated_at)>9900);
 await act(h,'choose',r,0);await act(g,'choose',r,2);
 const d=await act(g,'state',r);assert.equal(d.room.phase,'select');assert.equal(d.room.host_choice,null);assert.equal(d.room.guest_choice,null);assert.equal(d.my_choice,2);
});
test('both ready resolves immediately; one ready does not reveal; confirmed choices cannot change',async()=>{
 let r=await room();await act(h,'choose',r,0);await act(g,'choose',r,2);
 const first=await act(h,'confirm',r);assert.equal(first.room.phase,'select');assert.equal(first.room.guest_choice,null);
 await assert.rejects(act(h,'choose',r,1),/bestätigt/);
 r=(await act(g,'confirm',r)).room;assert.equal(r.phase,'result');assert.equal(r.host_hp,5);assert.equal(r.guest_hp,4);assert.equal(r.host_score,1);
 assert.equal(r.host_choice,0);assert.equal(r.guest_choice,2);
 await act(g,'state',r);assert.equal((await act(h,'state',r)).room.guest_hp,4);
});
test('all seven draws preserve both players lives; all 21 unequal pairs damage only the loser',async()=>{
 for(let a=0;a<7;a++){
  let r=await pair(await room(),a,a);assert.equal(r.host_hp,5);assert.equal(r.guest_hp,5);assert.equal(r.winner,null);
  for(let b=a+1;b<7;b++){r=await pair(await room(),a,b);const hostWins=wins[a].includes(b);assert.equal(r.host_hp,hostWins?5:4);assert.equal(r.guest_hp,hostWins?4:5);}
 }
});
test('five wins finish immediately, rewards pay once, history remains and a new match is allowed',async()=>{
 let r=await room();for(let i=1;i<=5;i++){r=await pair(r,0,2);assert.equal(r.guest_hp,5-i);assert.equal(r.host_hp,5);assert.equal(r.phase,i===5?'finished':'result');if(i<5)r=await next(r);}
 assert.equal(r.match_winner,h);assert.equal(r.end_reason,'knockout');
 const d=await act(h,'state',r);assert.equal(d.rewards.coins,100);assert.equal((await state(h)).profile.coins,350);
 await act(h,'state',r);await act(g,'ping',r);assert.equal((await state(h)).profile.xp,120);
 await db.exec("update chaos_private.limits set created='epoch'");
 const another=(await act(h,'create')).room;assert.notEqual(another.id,r.id);
 assert.equal((await db.query('select phase from public.chaos_rooms where id=$1',[r.id])).rows[0].phase,'finished');
});
test('rematch restores all hearts and confirmation flags; moves from prior matches stay historical',async()=>{
 let r=await room();for(let i=0;i<5;i++){r=await pair(r,0,2);if(i<4)r=await next(r);}
 r=await next(r);await act(h,'ready',r);r=(await act(g,'ready',r)).room;
 assert.equal(r.match_no,2);assert.equal(r.host_hp,5);assert.equal(r.guest_hp,5);assert.equal(r.host_confirmed,false);assert.equal(r.guest_confirmed,false);
 assert.equal((await db.query('select count(*)::int n from chaos_private.moves where room_id=$1 and match_no=1',[r.id])).rows[0].n,10);
});
test('missing choices use valid random powers for either side; three AFK rounds abort without farming XP',async()=>{
 let r=await room();for(let i=0;i<3;i++){r=await finish(r);assert.ok(Number.isInteger(r.host_choice)&&r.host_choice>=0&&r.host_choice<7);assert.ok(Number.isInteger(r.guest_choice)&&r.guest_choice>=0&&r.guest_choice<7);if(i<2)r=await next(r);}
 assert.equal(r.phase,'finished');assert.equal(r.end_reason,'inactivity');assert.equal(r.match_winner,null);assert.equal((await state(h)).profile.xp,0);assert.equal((await state(g)).profile.coins,250);
});
test('stale moves, foreign access, direct health writes and private selections are denied',async()=>{
 let r=await room();await assert.rejects(act(h,'confirm',r),/zuerst/);
 const old=r;r=await pair(r,0,2);r=await next(r);await assert.rejects(act(h,'choose',old,4),/Runde hat sich geändert/);
 await assert.rejects(act(outsider,'state',r),/Zugriff/);
 await act(h,'choose',r,4);await as(g);await db.exec('set role authenticated');
 assert.equal((await db.query('select host_choice from public.chaos_rooms where id=$1',[r.id])).rows[0].host_choice,null);
 await assert.rejects(db.query('update public.chaos_rooms set host_hp=999 where id=$1',[r.id]),/permission denied/);
 await assert.rejects(db.query('select * from chaos_private.sessions'),/permission denied/);await db.exec('reset role');
});
test('active session prevents multiple starts; resume restores the exact hidden choice',async()=>{
 let r=await room();await act(h,'choose',r,6);await assert.rejects(act(h,'bot'),/laufenden Kampf/);
 const d=await act(h,'resume');assert.equal(d.room.id,r.id);assert.equal(d.my_choice,6);assert.equal(d.room.guest_choice,null);
 await act(h,'leave',r);assert.equal((await act(h,'resume')).room,null);
 assert.equal((await db.query('select end_reason from public.chaos_rooms where id=$1',[r.id])).rows[0].end_reason,'forfeit');
});
test('stale sessions can start afresh; historical rooms no longer trigger a three-room error',async()=>{
 await reset();let r=(await act(h,'bot')).room;
 await db.query("update public.chaos_rooms set host_seen=clock_timestamp()-interval '2 minutes' where id=$1",[r.id]);await db.exec("update chaos_private.limits set created='epoch'");
 const fresh=(await act(h,'bot')).room;assert.notEqual(fresh.id,r.id);assert.equal((await db.query('select end_reason from public.chaos_rooms where id=$1',[r.id])).rows[0].end_reason,'abandoned');
 for(let i=0;i<4;i++){await act(h,'leave',fresh);await db.exec("update chaos_private.limits set created='epoch'");r=(await act(h,'create')).room;await act(h,'leave',r);}
 assert.ok((await db.query('select count(*)::int n from public.chaos_rooms')).rows[0].n>=5);assert.equal((await state(h)).profile.xp,0);
});
test('campaign chapters 0–7 use correct bosses, survive resume, unlock and grant rewards once',async()=>{
 await reset();
 for(let stage=0;stage<8;stage++){
  await db.exec("update chaos_private.limits set created='epoch'");let r=await campaign(stage);
  const target=stage===3?8:stage===7?11:5;assert.equal(r.guest_max_hp,target);assert.equal(r.host_hp,5);
  while(r.phase!=='finished'){
   const b=await botMove(r);await act(h,'choose',r,wins.findIndex(a=>a.includes(b)));
   assert.equal((await act(h,'resume')).room.id,r.id);r=(await act(h,'confirm',r)).room;
   if(r.phase!=='finished')r=await next(r);
  }
  assert.equal(r.host_hp,5);assert.equal(r.guest_hp,0);assert.equal(r.host_score,target);
  const d=await state(h);assert.equal(d.profile.campaign_unlocked,stage+1);
  const before=d.profile.coins;await act(h,'state',r);assert.equal((await state(h)).profile.coins,before);
 }
 assert.equal((await state(h)).profile.wins,8);
});
test('bot precommits before input; confirmation gives a single-player fast start',async()=>{
 await reset();let r=(await act(h,'bot')).room;assert.equal(r.guest_confirmed,true);const committed=await botMove(r);
 await act(h,'choose',r,0);await act(h,'choose',r,4);assert.equal(await botMove(r),committed);assert.equal((await act(h,'state',r)).room.guest_choice,null);
 r=(await act(h,'confirm',r)).room;assert.equal(r.phase,'result');
});
test('defeat XP persists once; leaving a bot run grants no additional coins or XP',async()=>{
 await reset();let r=(await act(h,'bot')).room;
 for(let i=0;i<5;i++){const b=await botMove(r);await act(h,'choose',r,wins[b][0]);r=(await act(h,'confirm',r)).room;if(i<4)r=await next(r);}
 assert.equal(r.host_hp,0);assert.equal(r.guest_hp,5);assert.equal((await state(h)).profile.xp,40);assert.equal((await state(h)).profile.coins,250);
 await act(h,'ping',r);assert.equal((await state(h)).profile.matches,1);
 await db.exec("update chaos_private.limits set created='epoch'");r=(await act(h,'bot')).room;await act(h,'choose',r,0);await act(h,'leave',r);
 assert.equal((await state(h)).profile.xp,40);assert.equal((await state(h)).profile.matches,1);
});
test('two tabs cannot join different rooms for the same player',async()=>{
 await reset();const a=(await act(h,'create')).room,b=(await act(outsider,'create')).room;
 await act(g,'join',a);await assert.rejects(act(g,'join',b),/laufenden Kampf/);
 assert.equal((await act(g,'resume')).room.id,a.id);
});
test('expired participation forfeits to a still-active opponent and preserves recorded results',async()=>{
 let r=await room();await act(h,'choose',r,0);await act(g,'choose',r,2);
 await db.query("update public.chaos_rooms set host_seen=clock_timestamp()-interval '2 minutes' where id=$1",[r.id]);
 await db.exec("update chaos_private.limits set created='epoch'");
 await act(h,'create');const previous=(await db.query('select * from public.chaos_rooms where id=$1',[r.id])).rows[0];
 assert.equal(previous.end_reason,'forfeit');assert.equal(previous.match_winner,g);
 assert.equal((await state(g)).profile.coins,350);assert.equal((await state(h)).profile.coins,250);
});
test('live smoke script passes and rolls back every temporary account and match',async()=>{
 const before=(await db.query('select (select count(*) from auth.users)::int users,(select count(*) from public.chaos_rooms)::int rooms')).rows[0];
 await db.exec(await readFile('tests/live-core-smoke.sql','utf8'));
 const after=(await db.query('select (select count(*) from auth.users)::int users,(select count(*) from public.chaos_rooms)::int rooms')).rows[0];
 assert.deepEqual(after,before);
});
async function endless(user=h,action='start'){await as(user);return (await db.query('select public.chaos_endless($1) d',[action])).rows[0].d;}
async function winBotRound(r){const move=await botMove(r);await act(h,'choose',r,wins.findIndex(a=>a.includes(move)));return (await act(h,'confirm',r)).room;}
test('endless starts at ten lives against one, hides choices and preserves the same run on repeated start',async()=>{
 await reset();let d=await endless(),r=d.room;assert.equal(r.host_hp,10);assert.equal(r.guest_hp,1);assert.equal(r.game_mode,'endless');assert.equal(r.guest_choice,null);
 assert.equal(d.endless.wave,1);assert.equal(d.endless.defeated,0);const again=await endless();assert.equal(again.room.id,r.id);assert.equal(again.endless.id,d.endless.id);
 await assert.rejects(act(h,'create'),/laufenden Kampf/);
});
test('endless victory grants configured reward once and automatically advances to enemy two',async()=>{
 await reset();let r=(await endless()).room;r=await winBotRound(r);assert.equal(r.phase,'finished');const d=await act(h,'state',r);
 assert.equal(d.endless.defeated,1);assert.equal(d.endless.coins,25);assert.equal(d.endless.xp,19);
 assert.equal((await state(h)).profile.coins,275);await act(h,'state',r);assert.equal((await state(h)).profile.coins,275);
 assert.equal((await act(h,'resume')).room.id,r.id);await assert.rejects(act(h,'create'),/laufenden Kampf/);
 r=await next(r);assert.equal(r.endless_wave,2);assert.equal(r.match_no,2);assert.equal(r.guest_hp,2);assert.equal(r.host_hp,10);assert.equal(r.phase,'select');assert.equal((await state(h)).profile.endless_best,2);
});
test('surviving player lives carry over after a damaged wave; advancing never heals them',async()=>{
 await reset();let r=(await endless()).room;r=await winBotRound(r);r=await next(r);
 const b=await botMove(r);await act(h,'choose',r,wins[b][0]);r=(await act(h,'confirm',r)).room;assert.equal(r.host_hp,9);
 r=await next(r);r=await winBotRound(r);r=await next(r);r=await winBotRound(r);assert.equal(r.guest_hp,0);
 r=await next(r);assert.equal(r.endless_wave,3);assert.equal(r.guest_hp,3);assert.equal(r.host_hp,9);
 const d=await act(h,'state',r);assert.equal(d.endless.defeated,2);assert.equal(d.endless.coins,55);assert.equal(d.endless.xp,42);
});
test('endless rewards cap per opponent and waves beyond eighteen have no score constraint',async()=>{
 await reset();let r=(await endless()).room;
 await db.query('update public.chaos_rooms set endless_wave=21,guest_hp=21,guest_max_hp=21,reward_coins=125,reward_xp=99 where id=$1',[r.id]);
 await db.query('update chaos_private.endless_runs set current_wave=21 where room_id=$1',[r.id]);r=(await act(h,'state',r)).room;
 for(let i=0;i<21;i++){r=await winBotRound(r);if(i<20)r=await next(r);}
 assert.equal(r.host_score,21);assert.equal(r.guest_hp,0);assert.equal((await act(h,'state',r)).endless.coins,125);
 r=await next(r);assert.equal(r.endless_wave,22);assert.equal(r.guest_hp,22);
 const caps=(await db.query('select chaos_private.endless_coins(2147483647) coins,chaos_private.endless_xp(2147483647) xp')).rows[0];
 assert.deepEqual(caps,{coins:125,xp:120});
});
test('zero lives closes the run, stores history and record and never repeats a defeat reward',async()=>{
 await reset();let r=(await endless()).room;
 for(let i=0;i<10;i++){const b=await botMove(r);await act(h,'choose',r,wins[b][0]);r=(await act(h,'confirm',r)).room;if(i<9)r=await next(r);}
 assert.equal(r.host_hp,0);assert.equal(r.phase,'finished');let d=await act(h,'state',r);assert.equal(d.endless.active,false);assert.equal(d.endless.coins,0);
 const stats=await endless(h,'state');assert.equal(stats.history[0].wave,1);assert.equal(stats.history[0].final_hp,0);assert.equal(stats.history[0].xp,10);assert.equal(stats.best,1);
 await act(h,'state',r);assert.equal((await state(h)).profile.matches,1);assert.equal((await state(h)).profile.coins,250);
 await db.exec("update chaos_private.limits set created='epoch'");r=(await act(h,'ready',r)).room;assert.equal(r.host_hp,10);assert.equal(r.endless_wave,1);
});
test('leaving between waves closes the run while keeping already earned coins and XP',async()=>{
 await reset();let r=(await endless()).room;r=await winBotRound(r);await act(h,'leave',r);
 const d=await endless(h,'state');assert.equal(d.active,null);assert.equal(d.history[0].coins,25);assert.equal((await state(h)).profile.xp,19);
 await db.exec("update chaos_private.limits set created='epoch'");r=(await endless()).room;assert.equal(r.host_hp,10);assert.equal(r.endless_wave,1);assert.equal((await state(h)).profile.coins,275);
});
test('endless history is private; leaderboard exposes only the limited public player projection',async()=>{
 await reset();let r=(await endless()).room;r=await winBotRound(r);r=await next(r);
 const mine=await endless(h,'state'),theirs=await endless(g,'state');assert.equal(theirs.history.length,0);assert.equal(theirs.active,null);
 const entry=mine.leaderboard.find(p=>p.id===h);assert.equal(entry.wave,2);assert.equal(entry.friend_code,undefined);assert.equal(entry.coins,undefined);
 await assert.rejects(act(g,'state',r),/Zugriff/);await as(g);await db.exec('set role authenticated');
 await assert.rejects(db.query('select * from chaos_private.endless_runs'),/permission denied/);await db.exec('reset role');
});
test('AFK runs cannot farm rewards or loop through automatic victories',async()=>{
 await reset();let r=(await endless()).room;
 for(let i=0;i<3;i++){r=await finish(r);if(r.phase==='finished'&&r.match_winner!==r.host)break;r=await next(r);}
 assert.equal(r.phase,'finished');assert.equal((await act(h,'state',r)).endless.active,false);
 assert.equal((await state(h)).profile.xp,0);assert.equal((await state(h)).profile.coins,250);
});
test('room cleanup keeps run history and allows a fresh run without an orphan active record',async()=>{
 await reset();const r=(await endless()).room;await db.query('delete from public.chaos_rooms where id=$1',[r.id]);
 await db.exec("update chaos_private.limits set created='epoch'");const fresh=(await endless()).room;assert.notEqual(fresh.id,r.id);
 assert.equal((await endless(h,'state')).history.length,1);
});
test('automatic wave wins receive zero reward and do not reset the three-round inactivity counter',async()=>{
 await reset();let r=(await endless()).room;await db.exec('select setseed(0.17)');
 const auto=(await db.query('select floor(random()*7)::int a')).rows[0].a;await db.exec('select setseed(0.17)');
 await db.query('update chaos_private.moves set choice=$1 where room_id=$2',[wins[auto][0],r.id]);
 r=await finish(r);assert.equal(r.match_winner,h);assert.equal(r.host_missed,1);
 const d=await act(h,'state',r);assert.equal(d.rewards.coins,0);assert.equal(d.rewards.xp,0);assert.equal(d.endless.active,true);
 r=await next(r);assert.equal(r.host_missed,1);assert.equal(r.endless_wave,2);assert.equal((await state(h)).profile.endless_best,0);
});
test('fresh installation includes the same current migrations and can start an endless run',async()=>{
 const clean=new PGlite();
 try{
  await clean.exec("create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,is_anonymous boolean not null default false,email_confirmed_at timestamptz default now());create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;");
  await clean.exec((await readFile('supabase/setup-fresh.sql','utf8')).replace(/alter publication supabase_realtime add table[^;]+;/g,''));
  await clean.query('insert into auth.users(id) values($1)',[h]);await clean.query("select set_config('request.jwt.claim.sub',$1,false)",[h]);
  await clean.query("select public.chaos_social('profile','Fresh hero',0)");
  const d=(await clean.query("select public.chaos_endless('start') d")).rows[0].d;
  assert.equal(d.room.host_hp,10);assert.equal(d.room.guest_hp,1);assert.equal(d.endless.wave,1);
 }finally{await clean.close();}
});
test('live endless acceptance script proves carryover and rollback on the current schema',async()=>{
 const before=(await db.query('select (select count(*) from auth.users)::int users,(select count(*) from public.chaos_rooms)::int rooms')).rows[0];
 await db.exec(await readFile('tests/live-endless-smoke.sql','utf8'));
 assert.deepEqual((await db.query('select (select count(*) from auth.users)::int users,(select count(*) from public.chaos_rooms)::int rooms')).rows[0],before);
});
