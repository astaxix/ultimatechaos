import type {CSSProperties} from 'react';
/** One short, non-flashing hit sequence per resolved round. */
export function CombatAtmosphere({side,color,power}:{side:'own'|'other';color:string;power:number}){return <div className={'combat-impact strike-'+side+' strike-power-'+power} style={{'--strike-color':color} as CSSProperties} aria-hidden="true"><i className="strike-ring"/><i className="strike-trail"/>{Array.from({length:3},(_,i)=><b key={i} style={{'--a':i*120+'deg','--d':(18+i%3*8)+'px','--delay':i%3*.025+'s'} as CSSProperties}/>)}</div>;}
