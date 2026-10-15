import {useSyncExternalStore} from 'react';
export type Preferences={effects:number;music:number;musicOn:boolean;muted:boolean;graphics:'auto'|'low'|'medium'|'high';reduced:boolean};
const defaults:Preferences={effects:.65,music:.5,musicOn:false,muted:false,graphics:'high',reduced:false};
function read(){try{const saved=JSON.parse(localStorage.getItem('chaos-preferences')??'null');const old=Number(JSON.parse(localStorage.getItem('chaos-volume')??'.65'));return {...defaults,effects:Number.isFinite(old)?Math.max(0,Math.min(1,old)):.65,musicOn:localStorage.getItem('chaos-music')==='true',...saved,graphics:'high'} as Preferences;}catch{return defaults;}}
let current=read();const listeners=new Set<()=>void>();
export function preferences(){return current;}
export function updatePreferences(patch:Partial<Preferences>){current={...current,...patch,graphics:'high'};for(const key of ['effects','music'] as const)current[key]=Math.max(0,Math.min(1,current[key]));try{localStorage.setItem('chaos-preferences',JSON.stringify(current));localStorage.setItem('chaos-volume',JSON.stringify(current.muted?0:current.effects));localStorage.setItem('chaos-music',JSON.stringify(current.musicOn));}catch{}for(const listener of listeners)listener();}
export function usePreferences(){return useSyncExternalStore(callback=>{listeners.add(callback);return()=>{listeners.delete(callback);};},()=>current);}
window.addEventListener('storage',e=>{if(e.key==='chaos-preferences'){current=read();for(const listener of listeners)listener();}});
export function autoQuality(){const n=navigator as Navigator&{deviceMemory?:number;connection?:{saveData?:boolean}};return n.connection?.saveData||(n.deviceMemory!=null&&n.deviceMemory<=2)||navigator.hardwareConcurrency<=2?'low':matchMedia('(max-width: 767px)').matches?'medium':'high';}
