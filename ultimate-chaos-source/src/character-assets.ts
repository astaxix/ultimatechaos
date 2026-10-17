import materials from './avatar-materials.json';
import type {Look} from './appearance';
const pending=new Map<string,Promise<void>>();
// Keep decoded images referenced across navigation, instead of requesting each sheet on entry.
const decoded=new Map<string,HTMLImageElement>();
const bodies=['masculine','feminine','androgynous'] as const;
export function characterAssets(look?:Partial<Look>|null){const body=bodies.find(b=>b===look?.body)??'masculine';return [materials['body-'+body as keyof typeof materials].src,materials.faces.src,...(look?.hair==='bald'?[]:[materials.hair.src]),...(look?.hat&&look.hat!=='none'||look?.weapon&&look.weapon!=='none'?[materials.equipment.src]:[])];}
function prepare(src:string,priority:'high'|'low'){const existing=pending.get(src);if(existing)return existing;const task=new Promise<void>((resolve,reject)=>{const image=new Image();image.decoding='async';image.fetchPriority=priority;image.onload=()=>{void image.decode().catch(()=>{}).then(()=>{image.onload=null;image.onerror=null;decoded.set(src,image);resolve();});};image.onerror=()=>{image.onload=null;image.onerror=null;reject(new Error('Character image unavailable'));};image.src=src;});pending.set(src,task);void task.catch(()=>{pending.delete(src);decoded.delete(src);});return task;}
/** Preparation never blocks login or turns an image outage into an account error. */
export function warmCharacterAssets(look?:Partial<Look>|null,priority:'high'|'low'='high'){return Promise.allSettled(characterAssets(look).map(src=>prepare(src,priority)));}
export function primeCharacterAssets(){let body:Look['body']='masculine';try{const saved=localStorage.getItem('chaos-character-body');if(bodies.includes(saved as Look['body']))body=saved as Look['body'];}catch{}return warmCharacterAssets({body});}
export function rememberCharacterBody(look?:Partial<Look>|null){try{localStorage.setItem('chaos-character-body',look?.body??'masculine');}catch{}}
export function warmOpponentAssets(){return Promise.allSettled(bodies.map(body=>prepare(materials['body-'+body as keyof typeof materials].src,'low')));}
