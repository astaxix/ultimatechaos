import {useEffect,useRef,useState} from 'react';import {cardAtlas,cosmetic} from './cosmetics';import atlasCells from './atlas-cells.json';
export function Character({index,className='',skin='classic',aura='none'}:{index:number;className?:string;skin?:string;aura?:string}){
 const x=(index%4)*100/3,y=index>=4?100:0;
 const item=cosmetic(skin),atlas=cardAtlas(skin,index),auraItem=cosmetic(aura),cell=item?.theme?atlasCells[item.theme as keyof typeof atlasCells]:undefined;
 const root=useRef<HTMLSpanElement>(null),[visible,setVisible]=useState(false);
 useEffect(()=>{if(!atlas||visible)return;if(!('IntersectionObserver'in window)){setVisible(true);return;}const observer=new IntersectionObserver(entries=>{if(entries.some(e=>e.isIntersecting)){setVisible(true);observer.disconnect();}},{rootMargin:'120px'});if(root.current)observer.observe(root.current);return()=>observer.disconnect();},[atlas,visible]);
 return <span ref={root} aria-hidden="true" className={`character generated-character skin-${skin} ${atlas?'original-card-art':''} ${auraItem?'card-aura aura-model-'+auraItem.model:''} ${className}`} style={auraItem?{'--card-aura':auraItem.color} as React.CSSProperties:undefined}>{auraItem&&<span className="card-aura-orbit"/>}<span className="sprite-image" style={{backgroundPosition:`${x}% ${y}%`,...(atlas?{backgroundImage:'none',maskImage:'none'}:{})}}>{atlas&&cell&&<svg className="original-card-svg" viewBox={cell.cells[index].join(' ')} preserveAspectRatio="xMidYMid meet"><image href={visible?atlas:undefined} width={cell.width} height={cell.height}/></svg>}</span></span>;
}
