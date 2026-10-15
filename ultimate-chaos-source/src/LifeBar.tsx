import {Heart} from 'lucide-react';
export function LifeBar({value,max,damaged=false}:{value:number;max:number;damaged?:boolean}){
 return <div className="life-bar" role="meter" aria-label="Verbleibende Leben" aria-valuemin={0} aria-valuemax={max} aria-valuenow={value}>
  {max>12?<i className='life-track' aria-hidden='true'><i style={{width:(value/max*100)+'%'}}/></i>:Array.from({length:Math.min(max,12)},(_,i)=><Heart aria-hidden="true" key={i} size={15} className={(i<value?'heart-full':'heart-empty')+(damaged&&i===value?' heart-breaking':'')}/>)}
  <span>{value}/{max}</span>
 </div>;
}
