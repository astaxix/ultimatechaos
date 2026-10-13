// Real Supabase acceptance checks. Uses confirmed test accounts and public API keys.
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
const url=process.env.VITE_SUPABASE_URL,key=process.env.VITE_SUPABASE_ANON_KEY;
if(!url||!key){console.error('Supabase fehlt. .env mit URL und öffentlichem Key einrichten.');process.exit(1);}
const opts={auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}};
const a=createClient(url,key,opts),b=createClient(url,key,opts),outsider=createClient(url,key,opts);
const wait=ms=>new Promise(r=>setTimeout(r,ms));let room,channel;
async function rpc(client,type,choice=null){const {data,error}=await client.rpc('chaos_action',{action:type,room_code:room?.code??null,player_name:client===a?'Online-Test A':'Online-Test B',choice,expected_round:room?.round_no??null,expected_match:room?.match_no??null});if(error)throw error;if(data.error)throw new Error(data.error);return data;}
async function afterDeadline(field){await wait(Math.max(0,Date.parse(room[field])+120-Date.now()));room=(await rpc(a,'state')).room;return room;}
async function nextRound(){if(room.phase==='finished'){await afterDeadline('next_round_at');await rpc(a,'ready');room=(await rpc(b,'ready')).room;}else await afterDeadline('next_round_at');}
try{
 for(const [index,client] of [a,b,outsider].entries()){const email=process.env[`TEST_EMAIL_${index+1}`],password=process.env[`TEST_PASSWORD_${index+1}`];if(!email||!password)throw new Error('Drei bestätigte Testkonten als TEST_EMAIL_1..3 und TEST_PASSWORD_1..3 konfigurieren.');const r=await client.auth.signInWithPassword({email,password});if(r.error)throw r.error;const state=await client.rpc('chaos_social',{action:'state'});if(state.error)throw state.error;if(!state.data.profile){const profile=await client.rpc('chaos_social',{action:'profile',display_name:`Online-Test ${index+1}`,avatar_id:index});if(profile.error)throw profile.error;}}
 room=(await rpc(a,'create')).room;room=(await rpc(b,'join')).room;
 const updates=[];channel=b.channel(`timed-test:${room.id}`).on('postgres_changes',{event:'UPDATE',schema:'public',table:'chaos_rooms',filter:`id=eq.${room.id}`},e=>updates.push(e.new));
 await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new Error('Realtime timeout')),15000);channel.subscribe(s=>{if(s==='SUBSCRIBED'){clearTimeout(timer);resolve();}if(s==='CHANNEL_ERROR'){clearTimeout(timer);reject(new Error('Realtime failed'));}});});
 room=(await rpc(a,'start')).room;
 await rpc(a,'choose',0);await rpc(a,'choose',4);await rpc(b,'choose',6);
 const secretState=(await rpc(b,'state')).room;assert.equal(secretState.phase,'select');assert.equal(secretState.host_choice,null);assert.equal(secretState.guest_choice,null);
 await afterDeadline('select_until');assert.equal(room.host_choice,4);assert.equal(room.guest_choice,6);assert.equal(room.host_score,1);
 assert.ok(updates.some(r=>r.host_locked&&r.phase==='select'&&r.host_choice===null),'Realtime keeps choices secret');
 assert.equal((await outsider.from('chaos_rooms').select('*').eq('id',room.id)).data.length,0);
 assert.ok((await b.schema('chaos_private').from('moves').select('*')).error);
 assert.ok((await b.from('chaos_rooms').update({guest_score:10}).eq('id',room.id)).error);
 await nextRound();
 const wins=[[2,5,4],[0,5,6],[1,3,6],[0,1,4],[1,2,6],[2,3,4],[0,3,5]];
 const pairs=[];for(let x=0;x<7;x++)for(let y=x;y<7;y++)pairs.push([x,y]);pairs.push([null,0],[1,null],[null,null]);
 let finished=0;
 for(const [x,y] of pairs){
  const old={...room};await Promise.all([x===null?Promise.resolve():rpc(a,'choose',x),y===null?Promise.resolve():rpc(b,'choose',y)]);await afterDeadline('select_until');
  const w=x===null?(y===null?0:2):y===null?1:x===y?0:wins[x].includes(y)?1:2;
  assert.equal(room.host_score,old.host_score+(w===1?1:0));assert.equal(room.guest_score,old.guest_score+(w===2?1:0));
  assert.equal(room.phase,room.round_no===10?'finished':'result');
  if(room.phase==='finished'){finished++;assert.equal(room.match_winner,room.host_score===room.guest_score?null:room.host_score>room.guest_score?room.host:room.guest);}
  await nextRound();
  assert.equal(room.round_no,old.round_no===10?1:old.round_no+1);assert.equal(room.host_choice,null);
  if(old.round_no===10)assert.equal(room.host_score+room.guest_score,0);
 }
 assert.ok(finished>=2);await a.auth.refreshSession();const resumed=await rpc(a,'ping');assert.equal(resumed.room.id,room.id);
 console.log('PASS: echte Realtime, geheime 5-Sekunden-Auswahl, Änderungen vor Ablauf, 21 Paarungen, 7 Unentschieden, Zeitüberschreitungen, automatische Runden, genau 10 Runden, Rematches, RLS und Wiederaufnahme.');
 console.log('Zusätzlich manuell: zwei physische Geräte, Netzwerkabbruch, Hoch-/Querformat, Audio und Animationen.');
}catch(e){console.error('FAIL:',e.message);process.exitCode=1;}
finally{if(channel)await b.removeChannel(channel);if(room)try{await rpc(a,'leave');}catch{}for(const c of [a,b,outsider])await c.auth.signOut();}
