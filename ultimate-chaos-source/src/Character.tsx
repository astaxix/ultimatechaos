import {useEffect,useId,useRef,useState} from 'react';import {cardAtlas,cosmetic} from './cosmetics';import atlasCells from './atlas-cells.json';
export function Character({index,className='',skin='classic',aura='none'}:{index:number;className?:string;skin?:string;aura?:string}){

 const item=cosmetic(skin),atlas=cardAtlas(skin,index),auraItem=cosmetic(aura),cell=item?.theme?atlasCells[item.theme as keyof typeof atlasCells]:undefined;
 const root=useRef<HTMLSpanElement>(null),[visible,setVisible]=useState(false),clipId='card-crop-'+useId().replace(/[^a-zA-Z0-9_-]/g,'');
 const source=atlas??(skin==='card-frost'||skin==='card-ember'||skin==='card-eclipse'?'/art/frost-atlas.webp':'/art/fighters-atlas.webp');
 const frost=source.includes('frost');
 const legacyCells=frost?[[0,0,443.5,418],[443.5,0,443.5,440],[887,0,443.5,443.5],[1330.5,0,443.5,443.5],[0,425,443.5,462],[443.5,455,443.5,432],[887,460,443.5,427]]:[[0,0,443.5,425],[443.5,0,443.5,430],[887,0,443.5,443.5],[1330.5,0,443.5,443.5],[0,428,443.5,459],[443.5,455,443.5,432],[887,460,443.5,427]];
 const rect=cell?.cells[index]??legacyCells[index];
 useEffect(()=>{if(visible)return;if(!('IntersectionObserver'in window)){setVisible(true);return;}const observer=new IntersectionObserver(entries=>{if(entries.some(e=>e.isIntersecting)){setVisible(true);observer.disconnect();}},{rootMargin:'120px'});if(root.current)observer.observe(root.current);return()=>observer.disconnect();},[visible]);
 return <span ref={root} aria-hidden="true" className={`character generated-character skin-${skin} original-card-art ${auraItem?'card-aura aura-model-'+auraItem.model:''} ${className}`} style={auraItem?{'--card-aura':auraItem.color} as React.CSSProperties:undefined}>{auraItem&&<span className="card-aura-orbit"/>}<span className="sprite-image" style={{backgroundImage:'none',maskImage:'none'}}>{<svg className="original-card-svg" viewBox={rect.join(' ')} preserveAspectRatio="xMidYMid meet" overflow="hidden"><defs><clipPath id={clipId} clipPathUnits="userSpaceOnUse"><rect x={rect[0]} y={rect[1]} width={rect[2]} height={rect[3]}/></clipPath></defs><image clipPath={'url(#'+clipId+')'} href={visible?source:undefined} width={cell?.width??1774} height={cell?.height??887}/></svg>}</span></span>;
}
