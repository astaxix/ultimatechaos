import type {CSSProperties} from 'react';
/** One short, non-flashing hit sequence per resolved round. */
export function CombatAtmosphere({side,color,power}:{side:'own'|'other';color:string;power:number}){return <div className={'combat-impact strike-'+side+' strike-power-'+power} style={{'--strike-color':color} as CSSProperties} aria-hidden="true"><i className="strike-ring"/><i className="strike-trail"/>{Array.from({length:12},(_,i)=><b key={i} style={{'--a':i*30+'deg','--d':(44+i%4*12)+'px','--delay':i%3*.025+'s'} as CSSProperties}/>)}</div>;}
