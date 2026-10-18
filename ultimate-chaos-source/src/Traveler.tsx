import {RenderedWardrobe,RenderedHead,RenderedHair,RenderedHat,RenderedWeapon} from './AvatarMaterials';
import {useId} from 'react';
import {normalizeLook,type Look} from './appearance';
import {cosmetic} from './cosmetics';

/** Original layered character artwork. Appearance stays independent of combat powers. */
export function Traveler({look,portrait=false,pose='idle',label='Dein Charakter'}:{look?:Partial<Look>|null;portrait?:boolean;pose?:'idle'|'battle'|'hurt'|'victory'|'defeat';label?:string}){
 const a=normalizeLook(look),id=useId().replace(/:/g,''),url=(s:string)=>`url(#${id}-${s})`;
 const outfit=cosmetic(a.outfit),hat=cosmetic(a.hat),weapon=cosmetic(a.weapon),auraItem=cosmetic(a.aura);
 const female=a.body==='feminine',slim=a.body!=='masculine',armor=a.outfit==='armor-solstice'||outfit?.model==='armor',coat=a.outfit==='coat-nocturne'||outfit?.model==='coat',robe=a.outfit==='robe-astral'||outfit?.model==='robe',street=a.outfit==='jacket-street';
 const cloth=outfit?.model?outfit.color:armor?'#ba8b3d':coat?'#172a43':robe?'#16474f':street?'#504269':a.outfitColor,trim=outfit?.model?'#d9d3b9':armor?'#ffe4a3':robe?'#7de2da':coat?'#a9c7df':a.trimColor??'#c0b3a0';
 const long=['long','braids','bob','waves','dreads','sidebraid','shag'].includes(a.hair),aura=auraItem?.color??(a.aura==='aura-ember'?'#ff9856':a.aura==='aura-frost'?'#6eddf8':'#ba9fff');
 const width=a.build==='slim'?.88:a.build==='broad'?1.13:1,height=a.height==='short'?.94:a.height==='tall'?1.04:1;
 return <div className={`traveler ${portrait?'traveler-portrait':''} pose-${pose} aura-${a.aura} aura-shape-${auraItem?.model??'standard'}`} style={{'--aura-color':aura,'--traveler-height':height} as React.CSSProperties}>
  {!portrait&&a.aura!=='none'&&<div className="traveler-aura"><i/><i/><i/><i/><i/><i/><i/><i/></div>}
  {!portrait&&auraItem?.model==='wings'&&<svg className="aura-wings" viewBox="0 0 260 440" aria-hidden="true"><path d="M130 180Q67 84 14 139L40 184 22 203 82 238 126 210M130 180Q193 84 246 139L220 184 238 203 178 238 134 210" fill="var(--aura-color)" fillOpacity=".14" stroke="var(--aura-color)" strokeOpacity=".6"/></svg>}
  <svg viewBox={portrait?(a.hat==='none'&&!['afro','bun','mohawk','topknot','high-pony'].includes(a.hair)?'90 16 80 104':'70 -8 120 138'):'0 0 260 440'} role="img" aria-label={label} className="traveler-art">
   <defs>
    <linearGradient id={`${id}-skin`} x1="0" x2="1" y2=".7"><stop stopColor={a.skin}/><stop offset=".32" stopColor={a.skin}/><stop offset=".7" stopColor={a.skin} stopOpacity=".91"/><stop offset="1" stopColor="#3b2834" stopOpacity=".9"/></linearGradient>
    <linearGradient id={`${id}-cloth`} x1="0" x2="1"><stop stopColor="#091423"/><stop offset=".16" stopColor={cloth}/><stop offset=".4" stopColor={cloth}/><stop offset=".56" stopColor={cloth} stopOpacity=".82"/><stop offset=".78" stopColor={cloth}/><stop offset="1" stopColor="#080e1b"/></linearGradient>
    <linearGradient id={`${id}-hair`} x1="0" x2=".8" y2="1"><stop stopColor={a.hairColor}/><stop offset=".6" stopColor={a.hairColor}/><stop offset="1" stopColor="#090c12"/></linearGradient>
    <linearGradient id={`${id}-metal`} x1="0" y1="0" x2="1" y2="1"><stop stopColor="#fff1c3"/><stop offset=".3" stopColor={trim}/><stop offset=".55" stopColor="#64523d"/><stop offset=".72" stopColor={trim}/><stop offset="1" stopColor="#847054"/></linearGradient>
    <radialGradient id={`${id}-face`} cx=".35" cy=".2" r=".9"><stop stopColor="#fff3d8" stopOpacity=".27"/><stop offset="1" stopColor="#291a21" stopOpacity=".17"/></radialGradient>
   </defs>
   <ellipse cx="132" cy="421" rx="68" ry="12" fill="#030710" opacity=".45"/>
   {!portrait&&<g className="traveler-body" transform={`translate(${130*(1-width)} 0) scale(${width} 1)`}><RenderedWardrobe look={a} id={id} cloth={cloth}/><RenderedWeapon look={a} id={id}/></g>}
   <g transform="translate(130 72) scale(.84) translate(-130 -80)"><g className="traveler-head"><RenderedHair look={a} id={id} back/><RenderedHead look={a} id={id}/><g transform="translate(131 0) scale(.82 1) translate(-131 0)" stroke="#69493e" strokeWidth=".8">
    <path d={a.brows==='straight'?'M108 74L124 75M138 75L154 74':a.brows==='arched'?'M108 76Q117 66 124 75M137 75Q146 66 154 76':'M108 76Q116 71 124 76M137 76Q146 71 154 76'} fill="none" stroke={a.hairColor} strokeWidth={a.brows==='bold'?2.5:1.7}/>
    <g className="traveler-eyes">
    <path d={a.eyeShape==='round'?'M108 84Q116 74 124 83Q121 92 112 89Z M137 83Q145 74 154 84Q150 92 141 89Z':a.eyeShape==='sharp'?'M108 80L124 83 121 87 112 87Z M137 83L154 80 150 87 141 87Z':'M108 83Q116 79 124 83L121 88 112 88Z M137 83Q146 79 153 83L150 88 141 88Z'} fill="#e6e8e6" strokeWidth=".8"/>
    <ellipse cx="117" cy="84" rx="3.6" ry="4.3" fill={a.eyes}/><ellipse cx="145" cy="84" rx="3.6" ry="4.3" fill={a.eyes}/><circle cx="117" cy="84" r="1.7" fill="#17202c"/><circle cx="145" cy="84" r="1.7" fill="#17202c"/><circle cx="118" cy="82" r="1" fill="white"/><circle cx="146" cy="82" r="1" fill="white"/>
    </g>
    <path d={a.nose==='small'?'M130 91L128 97 132 98':a.nose==='wide'?'M130 86L125 97Q131 103 138 97':'M131 84L127 98 134 99'} fill="none" strokeOpacity=".5"/><path d={a.mouth==='smile'?'M119 104Q130 119 143 103Q130 110 119 104Z':a.mouth==='serious'?'M120 107L141 107':a.mouth==='full'?'M119 106Q126 101 131 105Q137 101 143 106Q131 116 119 106Z':'M120 106Q131 110 141 105'} fill={a.mouth==='smile'?'#f2e7dd':a.mouth==='full'?a.lipColor:'none'} stroke={a.lipColor??'#975f56'} strokeWidth={a.mouth==='full'?1:1.7}/>
    {a.freckles!=='none'&&[[-1,0],[1,0]].flatMap(([side])=>Array.from({length:a.freckles==='many'?8:4},(_,i)=><circle key={side+'-'+i} cx={131+side*(12+i%4*4)} cy={94+Math.floor(i/4)*5+i%2*2} r=".9" fill="#68412e" stroke="none" opacity=".65"/>))}
    {a.facePaint==='warrior'&&<path d="M105 91L120 96M141 96L156 91" fill="none" stroke={a.paintColor} strokeWidth="5" strokeLinecap="round" opacity=".8"/>}{a.facePaint==='runes'&&<g fill="none" stroke={a.paintColor} strokeWidth="1.7"><path d="M107 90V102L115 96 107 92M149 90V102L157 96 149 92M125 66L131 59 137 66 131 72Z"/></g>}{a.facePaint==='sun'&&<g fill="none" stroke={a.paintColor} strokeWidth="1.6"><circle cx="131" cy="66" r="5"/><path d="M131 56V53M131 76V79M121 66H118M141 66H144M124 59L122 57M138 59L140 57"/></g>}
    {a.scar==='cheek'&&<path d="M146 93L154 104M147 95L151 93M150 100L154 98" stroke="#bd8778" fill="none"/>}{a.scar==='brow'&&<path d="M146 70L141 84" stroke="#ddb69c" strokeWidth="2"/>}
    {['full','stubble','goatee'].includes(a.beard)&&<path d={a.beard==='full'?'M103 91L115 99 119 104 131 102 142 104 148 98 157 91 151 112 132 124 111 112Z':a.beard==='goatee'?'M121 111Q131 116 141 111L138 122 130 127 122 121Z':'M105 98Q131 121 155 98L150 112Q130 125 111 112Z'} fill={a.hairColor} opacity={a.beard==='stubble'?.3:.95} stroke="none"/>}{a.beard==='moustache'&&<path d="M119 103Q125 96 131 102Q137 96 144 103L138 107 131 104 124 107Z" fill={a.hairColor} stroke="none"/>}
    {a.earrings==='studs'&&<g fill={trim}><circle cx="99" cy="89" r="2.5"/><circle cx="162" cy="89" r="2.5"/></g>}{a.earrings==='hoops'&&<g stroke={trim} strokeWidth="2" fill="none"><ellipse cx="98" cy="95" rx="5" ry="8"/><ellipse cx="163" cy="95" rx="5" ry="8"/></g>}
    {a.glasses!=='none'&&<g stroke="#adadba" strokeWidth="1.7" fill="#cde8f409">{a.glasses==='round'?<><circle cx="116" cy="84" r="11"/><circle cx="146" cy="84" r="11"/></>:<><rect x="104" y="76" width="24" height="17" rx="3"/><rect x="134" y="76" width="24" height="17" rx="3"/></>}<path d="M127 82Q131 79 135 82M104 81L99 78M158 81L163 78" fill="none"/></g>}
   </g>
   <RenderedHair look={a} id={id}/><RenderedHat look={a} id={id}/>
   </g></g>
  </svg>
 </div>;
}
