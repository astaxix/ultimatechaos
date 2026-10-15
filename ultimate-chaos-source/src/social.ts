import {supabase,rpcMessage} from './backend';
export type Profile={emote_loadout?:string[];id:string;name:string;friend_code:string;avatar:number;frame:string;xp:number;coins:number;matches:number;wins:number;last_seen:string;appearance?:import('./appearance').Look;endless_best?:number;rating?:number;ranked_matches?:number;ranked_wins?:number;campaign_unlocked?:number;card_skin?:string;card_loadouts?:import('./cosmetics').CardLoadouts};
export type Friend={id:string;status:'pending'|'accepted';incoming:boolean;profile:Pick<Profile,'id'|'name'|'avatar'|'frame'|'xp'|'last_seen'|'appearance'>};
export type Challenge={id:string;incoming:boolean;name:string;status:'pending'|'accepted';room_code:string;expires_at:string};
export type Loot={kind:'empty'|'coins'|'item'|'duplicate'|'purchased';tier:number;rarity?:number;coins?:number;item?:string};
export type SocialState={profile:Profile|null;friends:Friend[];challenges:Challenge[];inventory:string[];packs?:Record<string,number>;loot?:Loot;game?:import('./backend').GameData|null};
export const shop=[{id:'violet',name:'Arkaner Kreis',rarity:'SELTEN',price:150,description:'Ein violetter Runenrahmen für dein Profil.',color:'#b18afa'},{id:'gold',name:'Goldene Krone',rarity:'EPISCH',price:350,description:'Goldene Flügel für die Herrscher des Chaos.',color:'#e3bf78'},{id:'celestial',name:'Himmlische Aura',rarity:'LEGENDÄR',price:700,description:'Ein leuchtender Sternenkranz aus dem Himmel.',color:'#9bdded'}];
export async function social(action:string,params:{name?:string;avatar?:number;code?:string;target?:string;item?:string;appearance?:import('./appearance').Look}={}){
 if(!supabase)throw new Error('Der Online-Server ist noch nicht verbunden.');
 const {data,error}=await supabase.rpc('chaos_social',{action,display_name:params.name??null,avatar_id:params.avatar??null,friend_code:params.code??null,target_id:params.target??null,item_id:params.item??null});
 if(error)throw new Error(rpcMessage(error));
 if(action==='profile'&&params.appearance){const saved=await supabase.rpc('chaos_style',{action:'appearance',appearance:params.appearance,item_id:null});if(saved.error)throw new Error(rpcMessage(saved.error));return saved.data as SocialState;}
 return data as SocialState;
}
export async function styleAction(action:string,item:string){if(!supabase)throw new Error('Bitte zuerst anmelden.');const {data,error}=await supabase.rpc('chaos_style',{action,appearance:null,item_id:item});if(error)throw new Error(rpcMessage(error));return data as SocialState;}
export async function lootAction(action:string,tier:number,requestId:string){if(!supabase)throw new Error('Bitte zuerst anmelden.');const {data,error}=await supabase.rpc('chaos_loot',{action,pack_tier:tier,request_id:requestId});if(error)throw new Error(rpcMessage(error));return data as SocialState;}
export const level=(xp:number)=>Math.floor(xp/250)+1;

export async function equipCard(power:number,slot:string,item:string){if(!supabase)throw new Error('Bitte zuerst anmelden.');const {data,error}=await supabase.rpc('chaos_collection',{action:'equip',power_index:power,slot,item_id:item});if(error)throw new Error(rpcMessage(error));return data as SocialState;}
