import {supabase,rpcMessage} from './backend';
export type Profile={id:string;name:string;friend_code:string;avatar:number;frame:string;xp:number;coins:number;matches:number;wins:number;last_seen:string};
export type Friend={id:string;status:'pending'|'accepted';incoming:boolean;profile:Pick<Profile,'id'|'name'|'avatar'|'frame'|'xp'|'last_seen'>};
export type Challenge={id:string;incoming:boolean;name:string;status:'pending'|'accepted';room_code:string;expires_at:string};
export type SocialState={profile:Profile|null;friends:Friend[];challenges:Challenge[];inventory:string[];game?:import('./backend').GameData|null};
export const shop=[{id:'violet',name:'Arkaner Kreis',rarity:'SELTEN',price:150,description:'Ein violetter Runenrahmen für dein Profil.',color:'#b18afa'},{id:'gold',name:'Goldene Krone',rarity:'EPISCH',price:350,description:'Goldene Flügel für die Herrscher des Chaos.',color:'#e3bf78'},{id:'celestial',name:'Himmlische Aura',rarity:'LEGENDÄR',price:700,description:'Ein leuchtender Sternenkranz aus dem Himmel.',color:'#9bdded'}];
export async function social(action:string,params:{name?:string;avatar?:number;code?:string;target?:string;item?:string}={}){
 if(!supabase)throw new Error('Der Online-Server ist noch nicht verbunden.');
 const {data,error}=await supabase.rpc('chaos_social',{action,display_name:params.name??null,avatar_id:params.avatar??null,friend_code:params.code??null,target_id:params.target??null,item_id:params.item??null});
 if(error)throw new Error(rpcMessage(error));return data as SocialState;
}
export const level=(xp:number)=>Math.floor(xp/250)+1;
