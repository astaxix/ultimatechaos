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
  <svg viewBox={portrait?'72 20 116 130':'0 0 260 440'} role="img" aria-label={label} className="traveler-art">
   <defs>
    <linearGradient id={`${id}-skin`} x1="0" x2="1" y2=".7"><stop stopColor={a.skin}/><stop offset=".6" stopColor={a.skin}/><stop offset="1" stopColor="#492d28" stopOpacity=".75"/></linearGradient>
    <linearGradient id={`${id}-cloth`} x1="0" x2="1"><stop stopColor={cloth}/><stop offset=".42" stopColor={cloth}/><stop offset="1" stopColor="#080e1b"/></linearGradient>
    <linearGradient id={`${id}-hair`} x1="0" x2=".8" y2="1"><stop stopColor={a.hairColor}/><stop offset=".6" stopColor={a.hairColor}/><stop offset="1" stopColor="#090c12"/></linearGradient>
    <linearGradient id={`${id}-metal`} x1="0" y1="0" x2="1" y2="1"><stop stopColor="#fff1c3"/><stop offset=".3" stopColor={trim}/><stop offset=".55" stopColor="#64523d"/><stop offset=".72" stopColor={trim}/><stop offset="1" stopColor="#847054"/></linearGradient>
    <radialGradient id={`${id}-face`} cx=".35" cy=".2" r=".9"><stop stopColor="#fff3d8" stopOpacity=".27"/><stop offset="1" stopColor="#291a21" stopOpacity=".17"/></radialGradient>
   </defs>
   <ellipse cx="132" cy="421" rx="68" ry="12" fill="#030710" opacity=".45"/>
   {(coat||armor||robe)&&<path d="M91 123 Q126 109 168 128 L207 374 Q165 395 127 369 Q102 404 58 380Z" fill={armor?'#591e2e':url('cloth')} stroke="#0b1020" strokeWidth="3"/>}
   {long&&<path d={a.hair==='bob'?'M98 50Q130 15 163 48L174 122Q132 149 87 121Z':'M98 48Q127 16 165 48L180 176Q158 196 139 172L128 119 109 189 78 174Z'} fill={url('hair')} stroke="#11151f" strokeWidth="2"/>}
   {['ponytail','high-pony'].includes(a.hair)&&<path d={a.hair==='high-pony'?'M149 33Q190 3 196 56L185 157 164 176 174 94 159 62Z':'M154 57Q186 43 188 80L181 170 164 182 170 107Z'} fill={url('hair')} stroke="#11151f" strokeWidth="2"/>}
   {a.hair==='twin-tails'&&<path d="M99 57Q67 38 66 85L77 171 98 160 84 100 106 72M158 55Q188 37 192 83L184 168 163 161 176 99 151 73" fill={url('hair')} stroke="#11151f" strokeWidth="2"/>}
   <g className="traveler-body" transform={`translate(${130*(1-width)} 0) scale(${width} 1)`} stroke="#101722" strokeWidth="2.5" strokeLinejoin="round">
    <path d="M99 233L132 239 125 327 111 397 82 395 92 324Z" fill={a.pantsColor??'#263344'}/>
    <path d="M132 239L161 231 165 321 183 395 155 402 137 330Z" fill={a.pantsColor??'#1b2636'}/>
    <path d="M104 253L103 315 92 368M151 250L153 321 170 370" fill="none" stroke="#718397" opacity=".35"/>
    <path d="M83 369L113 373 111 405 116 417Q95 426 71 419L74 405Z" fill={a.bootColor??'#17202c'}/>
    <path d="M153 376L178 367 186 401 202 414Q181 429 155 420L153 404Z" fill={a.bootColor??'#17202c'}/>
    <path d="M78 395L110 399M157 401L184 393M74 414L113 414M160 415L194 412" stroke={trim} strokeWidth="2"/>
    <path d={`M${slim?103:96} 119Q129 109 ${slim?156:165} 122L172 169 ${slim?'154 201':'160 205'} 164 246Q132 260 95 245L${slim?106:101} 199 87 169Z`} fill={url('cloth')}/>
    <path d="M98 122Q80 119 74 140L63 204 74 234 88 225 84 196 102 156M160 123Q180 121 187 142L198 198 188 227 175 220 178 193 158 156" fill={url('cloth')}/>
    <path d="M73 217L87 220 89 246 82 261 70 259 66 249Z M177 218L190 221 194 246 188 259 178 258 173 248Z" fill={url('skin')}/>
    <path d="M73 240L81 243 82 253M180 240L187 243 185 252" fill="none" stroke="#5e3f36" strokeWidth="1.2"/>
    <path d="M115 104L115 126 130 139 146 125 145 102" fill={url('skin')}/>
    <path d="M109 121L129 140 115 161 98 132M151 121L129 140 145 161 163 132" fill={armor?url('metal'):'#111e2d'} stroke={trim} strokeWidth="1.2"/>
    <path d="M130 143L131 231M103 230L157 230" stroke={trim} strokeWidth="1" opacity=".6"/>
    <path d="M98 230Q132 242 162 230L164 244Q130 255 96 244Z" fill="#161c27"/>
    <rect x="122" y="234" width="18" height="13" rx="2" fill={url('metal')}/><path d="M127 240H135" stroke="#483b2b"/>
    {female&&<path d="M103 165Q116 177 128 168Q144 179 158 165" fill="none" stroke="#ffffff" strokeOpacity=".09"/>}
    {armor&&<><path d="M77 135L98 119 114 142 95 157 74 150Z M153 138L168 120 187 136 190 150 169 157Z" fill={url('metal')}/><path d="M108 156L128 148 151 155 154 187 132 212 108 186Z" fill={url('metal')}/><path d="M131 157L142 175 131 192 120 175Z" fill="#3f7788"/><path d="M77 186L91 190 87 222 69 215 M179 187L193 184 196 215 178 224" fill={url('metal')}/></>}
    {coat&&<><path d="M100 147L117 170 124 237 95 335 77 321 89 214Z M160 148L145 170 138 238 160 333 181 318 168 211Z" fill={url('cloth')} stroke={trim} strokeWidth="1.4"/><path d="M97 179L112 184M150 185L165 180" stroke={trim}/><circle cx="115" cy="197" r="2" fill={trim}/><circle cx="147" cy="197" r="2" fill={trim}/></>}
    {robe&&<><path d="M99 213L164 213 182 375Q132 404 78 373Z" fill={url('cloth')} stroke={trim}/><path d="M132 241L131 387M106 249L96 366M157 251L168 366" stroke={trim} strokeWidth="1.3"/><path d="M84 365L130 383 176 366" fill="none" stroke={trim}/></>}
    {street&&<><path d="M93 123L109 127 119 144 111 218 91 220 83 156Z M150 126L166 122 180 151 172 220 146 218 140 145Z" fill={url('cloth')} stroke="#d9c9ee" strokeWidth="1.1"/><path d="M94 185L111 183M150 183L169 185" stroke="#b6a2ce" strokeWidth="3"/><path d="M91 211L170 211" stroke="#131b2b" strokeWidth="5"/></>}
    {outfit?.model==='poncho'&&<><path d="M105 120L147 120 185 222 133 259 78 222Z" fill={url('cloth')} stroke={trim}/><path d="M87 208L132 235 174 207M92 196L132 221 169 196" stroke="#e1c5a3" strokeWidth="4" fill="none"/><path d="M119 168L132 151 145 168 132 188Z" fill="#504737" stroke={trim}/><path d="M81 223L80 237M91 231L90 244M101 238L100 252M166 233L168 247M178 224L181 237" stroke={trim}/></>}
    {outfit?.model==='kimono'&&<><path d="M103 121L131 151 158 121 168 246 133 295 94 246Z" fill={url('cloth')} stroke={trim}/><path d="M107 122L151 197M153 127L109 203" stroke={trim} strokeWidth="5"/><path d="M97 200L165 201 165 226 98 224Z" fill="#252c43" stroke={trim}/><path d="M134 203L146 214 135 229 124 214Z" fill={trim}/><path d="M106 246L132 264 156 244" fill="none" stroke="#d1c7dc"/></>}
    {outfit?.model==='ranger'&&<><path d="M96 124L107 120 162 225 152 232Z" fill="#615645" stroke={trim}/><path d="M80 132L106 119 117 144 91 167 74 152Z" fill="#45553f" stroke={trim}/><path d="M143 172L166 163 171 200 149 209Z" fill="#354336" stroke={trim}/><path d="M151 179L164 174M153 187L166 182" stroke={trim}/><path d="M88 245L97 232 108 245 104 271 89 268Z" fill="#5b4b38"/></>}
    {outfit?.model==='bomber'&&<><path d="M92 125L112 122 130 148 149 122 171 128 180 210 166 231 93 230 81 210Z" fill={url('cloth')} stroke={trim}/><path d="M130 147V226M92 216H170" stroke="#192333" strokeWidth="5"/><path d="M93 229H166" stroke={trim} strokeWidth="7"/><path d="M98 168L115 168 115 184 98 184Z" fill="#283e5a" stroke={trim}/><path d="M103 172L111 180M111 172L103 180" stroke={trim}/></>}
    {outfit?.model==='duelist'&&<><path d="M151 120L184 136 188 292 154 333 140 229Z" fill="#583348" stroke={trim}/><path d="M107 122L128 145 118 228 96 260 91 204Z" fill="#282b39" stroke={trim}/><path d="M103 151L119 162M101 163L117 173M99 175L115 184" stroke={trim} strokeWidth="2"/><path d="M154 120L171 123 182 148 163 153 151 139Z" fill={url('metal')}/><circle cx="143" cy="153" r="7" fill={url('metal')}/></>}
    {outfit?.model==='coat'&&<path d="M123 170Q139 161 139 177Q129 184 123 170Z" fill={trim}/>} {outfit?.model==='robe'&&<path d="M96 125L126 143 111 200 88 172Z" fill="#d9d3b9" fillOpacity=".4" stroke={trim}/>} {outfit?.model==='armor'&&<path d="M115 170L130 158 146 170 131 199Z" fill="#67a7bf" stroke={trim}/>} 
    {weapon?.model&&<g stroke={weapon.color} strokeWidth="2" fill="#26364a">{weapon.model==='sword'?<><path d="M188 247L198 247 207 350 197 373 189 351Z" fill="#d8e1e7"/><path d="M178 245L207 243 207 251 178 253Z" fill={weapon.color}/><path d="M190 221L195 244" strokeWidth="6"/><circle cx="190" cy="218" r="5" fill={weapon.color}/></>:weapon.model==='staff'?<><path d="M189 221L202 386" strokeWidth="6"/><path d="M181 210L188 189 200 206 193 225Z" fill={weapon.color}/><ellipse cx="190" cy="207" rx="17" ry="22" fill="none"/></>:weapon.model==='bow'?<><path d="M195 195Q238 257 204 322M195 195L204 322" fill="none" strokeWidth="4"/><path d="M191 251L237 248M230 244L238 248 231 253" fill="none" strokeWidth="2"/></>:<><path d="M187 249L198 249 208 298 199 316 190 298Z" fill="#bccad7"/><path d="M181 244L206 245M190 222L193 242" strokeWidth="5"/></>}</g>}
   </g>
   <g className="traveler-head"><g stroke="#563c34" strokeWidth="1.2">
    <ellipse cx="99" cy="79" rx="7" ry="12" fill={url('skin')}/><ellipse cx="161" cy="79" rx="7" ry="12" fill={url('skin')}/>
    <path d={a.face==='angular'?'M101 53Q129 34 158 53L158 88 146 108 131 118 111 108 101 91Z':a.face==='round'?'M100 53Q130 34 160 54L161 86Q158 114 131 118Q103 114 100 87Z':'M101 53Q130 34 159 53L157 89Q151 114 131 119Q110 114 103 90Z'} fill={url('skin')}/>
    <path d="M101 53Q130 34 159 53L157 89Q151 114 131 119Q110 114 103 90Z" fill={url('face')} stroke="none"/>
    <path d={a.brows==='straight'?'M108 74L124 75M138 75L154 74':a.brows==='arched'?'M108 76Q117 66 124 75M137 75Q146 66 154 76':'M108 76Q116 71 124 76M137 76Q146 71 154 76'} fill="none" stroke={a.hairColor} strokeWidth={a.brows==='bold'?4:2.3}/>
    <g className="traveler-eyes">
    <path d={a.eyeShape==='round'?'M108 84Q116 74 124 83Q121 92 112 89Z M137 83Q145 74 154 84Q150 92 141 89Z':a.eyeShape==='sharp'?'M108 80L124 83 121 87 112 87Z M137 83L154 80 150 87 141 87Z':'M108 83Q116 79 124 83L121 88 112 88Z M137 83Q146 79 153 83L150 88 141 88Z'} fill="#e6e8e6" strokeWidth=".8"/>
    <ellipse cx="117" cy="84" rx="3.3" ry="4" fill={a.eyes}/><ellipse cx="145" cy="84" rx="3.3" ry="4" fill={a.eyes}/><circle cx="117" cy="84" r="1.7" fill="#17202c"/><circle cx="145" cy="84" r="1.7" fill="#17202c"/><circle cx="118" cy="82" r="1" fill="white"/><circle cx="146" cy="82" r="1" fill="white"/>
    </g>
    <path d={a.nose==='small'?'M130 91L128 97 132 98':a.nose==='wide'?'M130 86L125 97Q131 103 138 97':'M131 84L127 98 134 99'} fill="none" strokeOpacity=".5"/><path d={a.mouth==='smile'?'M119 104Q130 119 143 103Q130 110 119 104Z':a.mouth==='serious'?'M120 107L141 107':a.mouth==='full'?'M119 106Q126 101 131 105Q137 101 143 106Q131 116 119 106Z':'M120 106Q131 110 141 105'} fill={a.mouth==='smile'?'#f2e7dd':a.mouth==='full'?a.lipColor:'none'} stroke={a.lipColor??'#975f56'} strokeWidth={a.mouth==='full'?1:1.7}/>
    {a.freckles!=='none'&&[[-1,0],[1,0]].flatMap(([side])=>Array.from({length:a.freckles==='many'?8:4},(_,i)=><circle key={side+'-'+i} cx={131+side*(12+i%4*4)} cy={94+Math.floor(i/4)*5+i%2*2} r=".9" fill="#68412e" stroke="none" opacity=".65"/>))}
    {a.facePaint==='warrior'&&<path d="M105 91L120 96M141 96L156 91" fill="none" stroke={a.paintColor} strokeWidth="5" strokeLinecap="round" opacity=".8"/>}{a.facePaint==='runes'&&<g fill="none" stroke={a.paintColor} strokeWidth="1.7"><path d="M107 90V102L115 96 107 92M149 90V102L157 96 149 92M125 66L131 59 137 66 131 72Z"/></g>}{a.facePaint==='sun'&&<g fill="none" stroke={a.paintColor} strokeWidth="1.6"><circle cx="131" cy="66" r="5"/><path d="M131 56V53M131 76V79M121 66H118M141 66H144M124 59L122 57M138 59L140 57"/></g>}
    {a.scar==='cheek'&&<path d="M146 93L154 104M147 95L151 93M150 100L154 98" stroke="#bd8778" fill="none"/>}{a.scar==='brow'&&<path d="M146 70L141 84" stroke="#ddb69c" strokeWidth="2"/>}
    {['full','stubble','goatee'].includes(a.beard)&&<path d={a.beard==='full'?'M103 91L115 99 119 104 131 102 142 104 148 98 157 91 151 112 132 124 111 112Z':a.beard==='goatee'?'M121 111Q131 116 141 111L138 122 130 127 122 121Z':'M105 98Q131 121 155 98L150 112Q130 125 111 112Z'} fill={a.hairColor} opacity={a.beard==='stubble'?.3:.95} stroke="none"/>}{a.beard==='moustache'&&<path d="M119 103Q125 96 131 102Q137 96 144 103L138 107 131 104 124 107Z" fill={a.hairColor} stroke="none"/>}
    {a.earrings==='studs'&&<g fill={trim}><circle cx="99" cy="89" r="2.5"/><circle cx="162" cy="89" r="2.5"/></g>}{a.earrings==='hoops'&&<g stroke={trim} strokeWidth="2" fill="none"><ellipse cx="98" cy="95" rx="5" ry="8"/><ellipse cx="163" cy="95" rx="5" ry="8"/></g>}
    {a.glasses!=='none'&&<g stroke="#adadba" strokeWidth="1.7" fill="#cde8f409">{a.glasses==='round'?<><circle cx="116" cy="84" r="11"/><circle cx="146" cy="84" r="11"/></>:<><rect x="104" y="76" width="24" height="17" rx="3"/><rect x="134" y="76" width="24" height="17" rx="3"/></>}<path d="M127 82Q131 79 135 82M104 81L99 78M158 81L163 78" fill="none"/></g>}
   </g>
   {a.hair!=='bald'&&<g fill={url('hair')} stroke="#13151e" strokeWidth="1.3">
    {a.hair==='swept'&&<path d="M98 82L94 59Q96 26 128 29L153 25 166 45 159 80 150 65 147 48Q128 65 106 61Z"/>}
    {a.hair==='crop'&&<path d="M100 77L96 54Q99 31 130 31Q159 31 164 55L159 77 153 57Q130 65 106 57Z"/>}
    {a.hair==='curls'&&<g className="hair-curls"><path d="M99 80Q91 70 95 56Q89 41 101 35Q101 24 114 24Q126 16 137 24Q151 20 157 32Q172 36 167 51L160 80 153 63Q131 69 107 62Z"/>{[[101,43,8],[113,32,9],[128,29,9],[143,31,9],[156,39,8],[162,51,7],[98,56,7],[109,51,9],[123,44,10],[139,46,9],[152,55,8],[118,59,7],[134,58,8]].map(([x,y,r],i)=><g key={i}><circle cx={x} cy={y} r={r} stroke="#14121a" strokeOpacity=".35" strokeWidth=".8"/><path d={`M${x-r*.5} ${y}q0 ${-r*.65} ${r*.6} ${-r*.55}q${r*.65} ${r*.1} ${r*.4} ${r*.65}q${-r*.2} ${r*.4} ${-r*.55} ${r*.2}`} fill="none" stroke={a.hairColor} strokeWidth="1.6" strokeLinecap="round" style={{filter:'brightness(1.5)'}} opacity=".7"/></g>)}</g>}
    {a.hair==='long'&&<path d="M97 85L93 54Q97 24 130 25Q163 24 169 55L163 102 154 73 145 45Q131 65 106 66Z"/>}
    {a.hair==='bob'&&<path d="M94 99L94 55Q97 26 132 28Q164 27 168 59L170 116 156 111 153 58 132 64 107 57 105 115 91 113Z"/>}
    {a.hair==='braids'&&<><path d="M98 77L96 52Q101 28 130 29Q159 26 165 53L160 80 151 57 108 58Z"/>{[99,161].map(x=><g key={x}>{Array.from({length:11},(_,i)=><ellipse key={i} cx={x+(i%2?2:-2)} cy={82+i*8} rx="6" ry="6" fill={url('hair')}/>)}</g>)}</>}
    {a.hair==='bun'&&<><circle cx="137" cy="27" r="19"/><path d="M98 80L95 57Q97 30 131 32Q160 29 166 57L161 79 153 56 110 55Z"/></>}
    {a.hair==='pixie'&&<path d="M99 76L94 53 105 31 128 25 156 33 164 55 155 69 147 46 134 63 117 52 105 72Z"/>}
    {a.hair==='waves'&&<><path d="M96 84Q82 61 101 41Q104 22 132 27Q165 23 170 54L162 104 155 80 150 48Q130 72 109 62Z"/><path d="M100 77Q113 99 95 119Q79 141 98 166M163 77Q149 100 169 122Q182 148 164 172" fill="none" stroke={a.hairColor} strokeWidth="12"/></>}
    {['ponytail','high-pony','twin-tails'].includes(a.hair)&&<><path d="M99 78L96 52Q99 27 130 28Q163 26 167 55L160 78 153 53 110 57Z"/>{a.hair==='high-pony'&&<path d="M139 27L152 15 168 28 160 43"/>}{a.hair==='twin-tails'&&<path d="M105 58L101 75M156 57L160 75" stroke={trim} strokeWidth="3"/>}</>}
    {a.hair==='mohawk'&&<path d="M114 53L110 29 120 10 129 19 141 5 146 24 154 34 147 59 132 51Z"/>}
    {a.hair==='undercut'&&<><path d="M99 59L102 39 130 24 156 29 167 45 155 58 128 48 109 66Z"/><path d="M100 66L102 80M158 62L160 79" fill="none" stroke={a.hairColor} strokeWidth="5" opacity=".5"/></>}
    {a.hair==='dreads'&&<><path d="M99 71L95 49Q100 24 132 27Q165 26 167 55L160 77 150 54 110 58Z"/>{[98,108,118,142,152,163].map((x,i)=><path key={x} d={'M'+x+' 42Q'+(x+(i%2?12:-12))+' 63 '+x+' 81L'+(x+(x<130?-12:12))+' '+(x<110||x>155?172:99)} fill="none" stroke={a.hairColor} strokeWidth="9" strokeLinecap="round"/>)}</>}
    {a.hair==='afro'&&<><path d="M98 80Q77 75 83 55Q72 36 93 27Q97 7 118 16Q132 2 149 17Q170 8 179 32Q193 45 179 63Q184 78 162 84L152 58 108 59Z"/>{[96,111,130,150,169].map((x,i)=><circle key={x} cx={x} cy={31+(i%2)*11} r="10" fill="none" stroke="#ffffff" strokeOpacity=".1"/>)}</>}
    {a.hair==='sidebraid'&&<><path d="M98 80L94 54Q99 25 132 28Q165 27 167 57L160 78 151 51 125 64 108 58Z"/>{Array.from({length:13},(_,i)=><ellipse key={i} cx={163+i*.8+(i%2?2:-2)} cy={80+i*8} rx="7" ry="6"/>)}</>}
    {a.hair==='shag'&&<path d="M98 104L88 92 94 72 86 56 99 39 103 24 124 29 140 20 155 30 171 48 165 70 174 92 160 107 151 72 145 49 130 64 119 50 109 72Z"/>}
    {a.hair==='topknot'&&<><path d="M113 29Q109 11 128 9Q146 5 153 22L144 35Z"/><path d="M99 75L96 54Q99 32 132 32Q163 32 165 55L160 77 153 55 108 57Z"/><path d="M119 31L145 31" stroke={trim} strokeWidth="3"/></>}
    <path d="M106 45Q125 34 143 39" fill="none" stroke="white" strokeOpacity=".12" strokeWidth="2"/>
   </g>}
   {a.hat==='hat-beanie'&&<g><path d="M94 58Q91 20 129 19Q165 18 168 58Z" fill="#75628d" stroke="#b4a0c9"/><path d="M93 51Q130 44 168 51L168 65Q130 58 93 66Z" fill="#5b4b71" stroke="#c4b3d7"/>{[103,113,123,133,143,153].map(x=><path key={x} d={`M${x} 31v16`} stroke="#a18ab9" opacity=".7"/>)}</g>}
   {a.hat==='hat-crown'&&<g fill={url('metal')} stroke="#ac8846"><path d="M96 47L92 21 112 36 129 12 146 35 166 21 160 50Z"/><path d="M98 46Q129 38 160 46L160 55Q131 47 98 55Z"/><path d="M129 29L135 38 129 46 123 38Z" fill="#67b7c8"/></g>}
   {a.hat==='hat-cap'&&<g fill="#1a2636" stroke="#7990a6"><path d="M96 57Q94 26 130 27Q166 25 168 57Z"/><path d="M96 55Q135 45 171 56L187 65Q157 72 127 60L97 65Z"/><path d="M133 34L139 42 132 50 126 42Z" fill={trim}/></g>}
   {a.hat==='hat-halo'&&<g fill="none" stroke="#f6dfa0"><ellipse cx="130" cy="12" rx="40" ry="8" strokeWidth="4"/><ellipse cx="130" cy="12" rx="45" ry="10" opacity=".3"/></g>}
   {hat?.model&&<g fill={hat.color} stroke="#d6d1ba" strokeWidth="1.3">{hat.model==='hood'?<path d="M92 123Q77 35 128 15Q183 28 174 124L158 116 160 60Q131 35 104 61L107 118Z"/>:hat.model==='witch'?<><path d="M86 54L128 3 146 24 158 52Z"/><ellipse cx="131" cy="54" rx="55" ry="10"/><path d="M111 32L150 44" stroke="#e9d3a2" strokeWidth="6"/></>:hat.model==='beret'?<><path d="M93 52Q79 21 125 21Q170 9 174 40L158 57Z"/><path d="M96 51L157 51" stroke="#746451" strokeWidth="6"/></>:hat.model==='visor'?<><path d="M101 76Q131 67 160 76L157 90Q131 95 104 90Z" fill="#80cee766"/><path d="M102 78L93 75M159 78L168 75M107 80L153 80" fill="none" strokeWidth="3"/></>:hat.model==='antlers'?<g fill="none" strokeWidth="4"><path d="M107 49L92 29 87 5M94 32L76 22 72 9M90 20L103 7M151 49L167 28 171 5M165 31L184 21 188 8M169 20L157 7"/><path d="M101 47Q130 36 157 47" strokeWidth="6"/></g>:<><path d="M95 55Q88 23 131 22Q174 22 168 58Z"/><path d="M97 43Q131 54 166 31M95 34Q130 47 164 26M100 55Q132 37 167 52" fill="none" stroke="#f1dfbd" strokeWidth="3"/><path d="M162 54L173 111 159 108 153 56Z"/></>}</g>}
   </g>
  </svg>
 </div>;
}
