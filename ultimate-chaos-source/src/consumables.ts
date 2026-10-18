import raw from './consumables-data.json';
import {supabase,rpcMessage,type GameData} from './backend';
import type {SocialState} from './social';
export const consumables=raw;
export const consumable=(id?:string|null)=>consumables.find(i=>i.id===id);
export type ItemState={stock:Record<string,number>;state:SocialState};
export async function itemRequest(action:'state'|'buy'|'choose',args:{item_id?:string;quantity?:number;quoted_price?:number;request_id?:string;room_code?:string;expected_round?:number;expected_match?:number}={}){if(!supabase)throw new Error('Bitte zuerst anmelden.');const {data,error}=await supabase.rpc('chaos_items',{action,...args});if(error)throw new Error(rpcMessage(error));return data as ItemState&GameData;}
