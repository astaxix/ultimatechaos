import {createClient} from '@supabase/supabase-js';
import type {Room} from './game';
const env=import.meta.env;
export const configured=Boolean(env.VITE_SUPABASE_URL && env.VITE_SUPABASE_ANON_KEY && !env.VITE_SUPABASE_URL.includes('YOUR-PROJECT'));
export const supabase=configured?createClient(env.VITE_SUPABASE_URL,env.VITE_SUPABASE_ANON_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}}):null;
let identityPromise:Promise<string>|null=null;
export function identify(){
 identityPromise??=identifyOnce().finally(()=>{identityPromise=null;});
 return identityPromise;
}
async function identifyOnce(){
 if(!supabase)throw new Error('Der Online-Modus ist noch nicht verbunden.');
 const {data,error}=await supabase.auth.getSession(); if(error)throw error;
 if(data.session)return data.session.user.id;
 throw new Error('Bitte zuerst anmelden.');
}
export function rpcMessage(error:{code?:string;message:string}){return error.code==='PGRST202'?'Supabase ist erreichbar. Die Spiel-Datenbank muss noch eingerichtet werden.':error.message;}
export type GameData={room:Room;my_choice:number|null;server_now:string;left?:boolean};
export async function action(type:string,code?:string,name?:string,choice?:number,room?:Room){
 if(!supabase)throw new Error('Der Online-Modus ist noch nicht verbunden.');
 const {data,error}=await supabase.rpc('chaos_action',{action:type,room_code:code??null,player_name:name??null,choice:choice??null,expected_round:room?.round_no??null,expected_match:room?.match_no??null});
 if(error)throw new Error(rpcMessage(error));
 if(data?.error)throw new Error(data.error);
 return data as GameData;
}
