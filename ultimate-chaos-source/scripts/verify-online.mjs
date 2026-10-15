// Acceptance test against a real Supabase deployment, using dedicated confirmed test accounts.
import assert from 'node:assert/strict';import {createClient} from '@supabase/supabase-js';
const url=process.env.VITE_SUPABASE_URL,key=process.env.VITE_SUPABASE_ANON_KEY;
if(!url||!key)throw Error('Supabase-Testkonfiguration fehlt.');
const clients=[0,1,2].map(()=>createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}}));
const [a,b,outsider]=clients;let room,channel;
const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function rpc(client,action,choice=null,expected=room){const {data,error}=await client.rpc('chaos_action',{action,room_code:expected?.code??null,choice,expected_round:expected?.round_no??null,expected_match:expected?.match_no??null});if(error)throw Error(error.message);if(data?.error)throw Error(data.error);return data;}
async function deadline(field){await wait(Math.max(0,Date.parse(room[field])+150-Date.now()));room=(await rpc(a,'state')).room;}
async function next(){await deadline('next_round_at');if(room.phase==='finished'){await Promise.all([rpc(a,'ready'),rpc(b,'ready')]);room=(await rpc(a,'state')).room;assert.equal(room.host_hp,5);assert.equal(room.guest_hp,5);}assert.equal(room.phase,'select');}
const matrix=[[2,5,4],[0,5,6],[1,3,6],[0,1,4],[1,2,6],[2,3,4],[0,3,5]];
try{
 for(const [i,client] of clients.entries()){
  const email=process.env['TEST_EMAIL_'+(i+1)],password=process.env['TEST_PASSWORD_'+(i+1)];
  if(!email||!password)throw Error('Drei dedizierte bestätigte Testkonten unter TEST_EMAIL_1..3 / TEST_PASSWORD_1..3 konfigurieren.');
  const signed=await client.auth.signInWithPassword({email,password});if(signed.error)throw Error(signed.error.message);
  const d=await client.rpc('chaos_social',{action:'state'});if(d.error)throw Error(d.error.message);
  if(!d.data.profile)throw Error('Testkonten müssen bereits ein Profil besitzen.');
  const current=await rpc(client,'resume',null,null);if(current.room)throw Error('Ein Testkonto hat bereits einen aktiven Kampf; dieser wird nicht überschrieben.');
 }
 room=(await rpc(a,'create')).room;room=(await rpc(b,'join')).room;
 const events=[];channel=b.channel('life-acceptance:'+room.id).on('postgres_changes',{event:'UPDATE',schema:'public',table:'chaos_rooms',filter:'id=eq.'+room.id},event=>events.push(event.new));
 await new Promise((resolve,reject)=>{const timeout=setTimeout(()=>reject(Error('Realtime-Verbindung läuft in Timeout')),15000);channel.subscribe(status=>{if(status==='SUBSCRIBED'){clearTimeout(timeout);resolve();}else if(status==='CHANNEL_ERROR'){clearTimeout(timeout);reject(Error('Realtime-Kanal fehlgeschlagen'));}});});
 room=(await rpc(a,'start')).room;assert.equal(room.rules_version,2);assert.equal(room.host_hp,5);assert.equal(room.guest_hp,5);
 assert.ok(Date.parse(room.select_until)-Date.parse(room.updated_at)>9500);
 let completed=0;
 const pairs=[];for(let x=0;x<7;x++)for(let y=x;y<7;y++)pairs.push([x,y]);
 for(const [x,y] of pairs){
  const old={...room};await Promise.all([rpc(a,'choose',x),rpc(b,'choose',y)]);
  await rpc(a,'confirm');const secret=await rpc(b,'state');assert.equal(secret.room.phase,'select');assert.equal(secret.room.host_choice,null);assert.equal(secret.room.guest_choice,null);
  room=(await rpc(b,'confirm')).room;assert.ok(['result','finished'].includes(room.phase));
  const win=x===y?0:matrix[x].includes(y)?1:2;
  assert.equal(room.host_hp,old.host_hp-(win===2?1:0));assert.equal(room.guest_hp,old.guest_hp-(win===1?1:0));
  if(room.phase==='finished'){completed++;assert.ok(room.host_hp===0||room.guest_hp===0);const one=await rpc(a,'state'),two=await rpc(a,'state');assert.equal(one.wallet.coins,two.wallet.coins);assert.equal(one.wallet.xp,two.wallet.xp);}
  await next();
 }
 assert.ok(completed>0);assert.ok(events.some(e=>e.host_confirmed&&e.phase==='select'&&e.host_choice===null),'Realtime veröffentlicht keine vorzeitige Auswahl');
 assert.equal((await outsider.from('chaos_rooms').select('*').eq('id',room.id)).data.length,0);
 assert.ok((await b.from('chaos_rooms').update({host_hp:999}).eq('id',room.id)).error);
 assert.ok((await b.schema('chaos_private').from('moves').select('*')).error);
 await rpc(a,'choose',4);await a.auth.refreshSession();const resumed=await rpc(a,'resume',null,null);assert.equal(resumed.room.id,room.id);assert.equal(resumed.my_choice,4);assert.equal(resumed.room.guest_choice,null);
 // Both clients racing to confirm cannot resolve the same round twice.
 await rpc(b,'choose',6);await Promise.all([rpc(a,'confirm'),rpc(b,'confirm')]);const result=await rpc(a,'state');assert.equal(result.room.host_hp,room.host_hp);assert.equal(result.room.guest_hp,room.guest_hp-1);
 console.log('PASS: echte Realtime, 10s Auswahl, 28 Paarungen inklusive Unentschieden, sofortiges Bereit, Schaden nur am Verlierer, Matchende/Rematch, private Auswahlen, RLS, Wiederaufnahme und simultane Bestätigungen.');
 console.log('Separat erforderlich: physische iOS-/Android-Geräte und Offline-/Reconnect-Abnahme.');
}catch(error){console.error('FAIL:',error.message);process.exitCode=1;}
finally{if(channel)await b.removeChannel(channel);if(room)try{await rpc(a,'leave');}catch{}for(const client of clients)await client.auth.signOut();}
