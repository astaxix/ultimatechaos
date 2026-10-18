import {ItemArt} from './ItemArt';
const special=new Set(['laura-mice','tyson-cloud','wet-rosette','maniac','epstein-flute']);
export function ItemCast({id,side}:{id?:string|null;side:'own'|'other'}){if(!id||!special.has(id))return null;return <div className={'item-cast cast-'+id+' cast-'+side} aria-hidden="true">{Array.from({length:id==='laura-mice'?3:1},(_,i)=><span key={i} style={{animationDelay:i*.13+'s'}}><ItemArt id={id}/></span>)}</div>;}
