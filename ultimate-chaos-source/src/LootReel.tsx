import {useEffect,useMemo,useRef} from 'react';
import {Gift} from 'lucide-react';
import {normalizeLook} from './appearance';import {allCosmetics as styleCatalog,rarityColors,rarityNames,type Cosmetic as StyleItem} from './cosmetics';import {CosmeticPreview} from './CosmeticArtwork';
import {Traveler} from './Traveler';import {Character} from './Character';import {Avatar} from './Avatar';import {CoinGlyph} from './Artwork';import {tick,unlock} from './audio';import type {Loot,Profile} from './social';
type Drop={item?:StyleItem;kind:string;coins?:number};
const WINNER=34,STEP=144,DURATION=6200;
export function LootReel({loot,profile,onFinish}:{loot:Loot;profile:Profile;onFinish:()=>void}){
 const done=useRef(false),track=useRef<HTMLDivElement>(null),finish=useRef(onFinish);finish.current=onFinish;const complete=()=>{if(done.current)return;done.current=true;finish.current();};
 const drops=useMemo(()=>{const random=new Uint32Array(42);crypto.getRandomValues(random);const entries:Drop[]=Array.from(random,n=>n%6===0?{kind:'coins',coins:100}:n%11===0?{kind:'empty'}:{kind:'item',item:styleCatalog[n%styleCatalog.length]});entries[WINNER]={kind:loot.kind,item:styleCatalog.find(s=>s.id===loot.item),coins:loot.coins};return entries;},[loot]);
 useEffect(()=>{const el=track.current;if(!el)return;unlock();let volume=.65;try{volume=Number(JSON.parse(localStorage.getItem('chaos-volume')??'.65'));}catch{}
 const reduce=matchMedia('(prefers-reduced-motion: reduce)').matches;const target=WINNER*STEP+STEP/2;const animation=el.animate([{transform:'translateX(-72px)'},{transform:'translateX(-'+target+'px)'}],{duration:reduce?0:DURATION,easing:'cubic-bezier(.12,.66,.12,1)',fill:'forwards'});let frame=0,last=-1,cancelled=false;
 function click(){if(cancelled)return;const x=new DOMMatrix(getComputedStyle(el!).transform).m41;const index=Math.floor((-x)/STEP);if(index!==last){last=index;tick(volume*.7);}frame=requestAnimationFrame(click);}
 if(!reduce)frame=requestAnimationFrame(click);void animation.finished.then(()=>{cancelAnimationFrame(frame);if(!cancelled)complete();}).catch(()=>{});
 return()=>{cancelled=true;cancelAnimationFrame(frame);animation.cancel();};
 },[]);
 const look=normalizeLook(profile.appearance);
 return <div className="loot-roll"><span className="eyebrow">MYSTERY PACK · WIRD GEÖFFNET</span><h2 id="pack-dialog-title">Was wartet auf dich?</h2><div className="loot-window" aria-hidden="true"><div className="loot-marker"/><div className="loot-track" ref={track}>{drops.map((drop,i)=><div key={i} className="reel-item" style={{'--loot-color':drop.item?rarityColors[drop.item.rarity]:drop.kind==='coins'?'#eac879':'#83b4d1'} as React.CSSProperties}><div className="reel-art">{drop.item?<CosmeticPreview item={drop.item} look={look}/>:drop.kind==='coins'?<CoinGlyph/>:<Gift size={38}/>}</div><b>{drop.item?.name??(drop.kind==='coins'?'Chaos Coins':'Sternenstaub')}</b><small>{drop.item?rarityNames[drop.item.rarity]:(drop.kind==='coins'?'COIN-FUND':'LEERER FUND')}</small></div>)}</div></div><p role="status">Das Band läuft aus …</p><button className="text-btn roll-skip" onClick={complete}>Animation überspringen</button><small className="roll-note">Die Mitte zeigt deinen Fund. Andere Items sind eine Vorschau.</small></div>;
}
