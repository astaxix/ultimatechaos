export function Character({index,className=''}:{index:number;className?:string}){
 const x=(index%4)*100/3,y=index>=4?100:0;
 return <span aria-hidden="true" className={`character generated-character ${className}`}><span className="sprite-image" style={{backgroundPosition:`${x}% ${y}%`}}/></span>;
}
