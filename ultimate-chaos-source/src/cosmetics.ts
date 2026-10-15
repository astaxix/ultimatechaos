import raw from './cosmetics-data.json';import {styleCatalog,type Look} from './appearance';
export type CosmeticSlot='outfit'|'hat'|'aura'|'weapon'|'frame'|'emote'|'card'|'card-aura'|'attack'|'victory';
export type Cosmetic={id:string;slot:CosmeticSlot;name:string;rarity:number;price:number;color:string;description:string;model?:string;power?:number;theme?:string};
export const rarityNames=['GEWÖHNLICH','SELTEN','EPISCH','LEGENDÄR','MYTHISCH'] as const;
export const rarityColors=['#aeb6c6','#85bde9','#b59be9','#e8c88d','#e4a6ed'] as const;
export const newCosmetics=raw as Cosmetic[];
export const allCosmetics:Cosmetic[]=[...styleCatalog.map(i=>({...i,rarity:i.rarity==='LEGENDÄR'?3:i.rarity==='EPISCH'?2:1})),...newCosmetics];
const lookup=new Map(allCosmetics.map(i=>[i.id,i]));export const cosmetic=(id?:string|null)=>id?lookup.get(id):undefined;
export type CardLoadout={skin?:string;aura?:string;effect?:string};export type CardLoadouts=Record<string,CardLoadout>;
export function cardLook(loadouts:CardLoadouts|undefined,power:number,fallback='classic'):Required<CardLoadout>{return {skin:loadouts?.[power]?.skin??fallback,aura:loadouts?.[power]?.aura??'none',effect:loadouts?.[power]?.effect??'none'};}
export function previewCosmetic(look:Look,item:Cosmetic):Look{return ['outfit','hat','aura','weapon','emote','victory'].includes(item.slot)?{...look,[item.slot]:item.id}:look;}
export function cardAtlas(id:string,index:number){const item=cosmetic(id);return item?.slot==='card'&&item.power===index&&item.theme?'/art/cards-'+item.theme+'-atlas.webp':undefined;}
export const cosmeticCategories:Record<CosmeticSlot,string>={outfit:'Kleidung',hat:'Kopfbedeckung',aura:'Charakteraura',weapon:'Waffen',frame:'Profilrahmen',emote:'Emotes',card:'Kartenskins','card-aura':'Kartenauren',attack:'Angriffseffekte',victory:'Siegeseffekte'};
