import {preferences} from './preferences';
let context:AudioContext|null=null;
const buffers=new Map<string,Promise<AudioBuffer|null>>();
const playing=new Set<AudioBufferSourceNode>();
let musicWanted=false,musicVolume=0,scene:'lobby'|'battle'='lobby',soundtrack:HTMLAudioElement|null=null,fade:number|undefined,duckUntil=0,unlocked=false;
function buffer(name:string){if(!context)return Promise.resolve(null);if(!buffers.has(name)){const c=context;buffers.set(name,fetch(`/audio/nocturne-${name}.wav`).then(r=>r.ok?r.arrayBuffer():Promise.reject()).then(b=>c.decodeAudioData(b)).catch(()=>null));}return buffers.get(name)!;}
function targetVolume(){return musicWanted&&!preferences().muted&&!document.hidden?Math.min(.36,musicVolume*.28)*(performance.now()<duckUntil?.48:1):0;}
function envelope(){if(fade!==undefined)return;let previous=performance.now();const step=(now:number)=>{const dt=Math.min(.1,(now-previous)/1000);previous=now;if(soundtrack){const target=targetVolume(),delta=target-soundtrack.volume;soundtrack.volume=Math.max(0,Math.min(1,soundtrack.volume+Math.sign(delta)*Math.min(Math.abs(delta),dt*.32)));if(!musicWanted&&soundtrack.volume===0)soundtrack.pause();if(Math.abs(delta)>.001||performance.now()<duckUntil){fade=requestAnimationFrame(step);return;}}fade=undefined;};fade=requestAnimationFrame(step);}
export function unlock(){try{unlocked=true;const Constructor=window.AudioContext??(window as Window&{webkitAudioContext?:typeof AudioContext}).webkitAudioContext;if(Constructor){context??=new Constructor();if(context.state==='suspended')void context.resume().catch(()=>{});void buffer('select');void buffer('tick');}if(musicWanted)music(true,musicVolume);}catch{}}
function play(name:string,volume:number){if(volume<=0||preferences().muted||document.hidden)return;unlock();const c=context;if(!c)return;void buffer(name).then(b=>{if(!b||c.state!=='running'||document.hidden||preferences().muted)return;while(playing.size>=6){const oldest=playing.values().next().value;if(!oldest)break;try{oldest.stop();}catch{}playing.delete(oldest);}const source=c.createBufferSource(),gain=c.createGain();source.buffer=b;gain.gain.value=Math.min(1,volume)*.65;source.connect(gain).connect(c.destination);playing.add(source);source.onended=()=>{playing.delete(source);source.disconnect();gain.disconnect();};source.start();});}
export function sound(fighter:number,volume:number){if(fighter<0||fighter>7)return;duckUntil=performance.now()+750;envelope();play(`power-${fighter}`,volume);}
export function tick(volume:number){play('tick',volume*.3);}
export function cue(kind:'select'|'win'|'lose'|'draw'|'level',volume:number){play(kind,volume);}
export function setMusicScene(next:'lobby'|'battle'){if(next===scene)return;scene=next;if(soundtrack){const outgoing=soundtrack;soundtrack=null;let value=outgoing.volume;const id=window.setInterval(()=>{value=Math.max(0,value-.025);outgoing.volume=value;if(value===0){outgoing.pause();outgoing.removeAttribute('src');window.clearInterval(id);}},45);}if(musicWanted)music(true,musicVolume);}
export function music(on:boolean,volume:number){musicWanted=on&&volume>0;musicVolume=volume;if(!musicWanted){if(soundtrack){soundtrack.pause();soundtrack.volume=0;}return;}if(!unlocked||document.hidden||preferences().muted)return;if(!soundtrack){soundtrack=new Audio(`/audio/nocturne-${scene}.m4a`);soundtrack.loop=true;soundtrack.preload='none';soundtrack.volume=0;}void soundtrack.play().catch(()=>{});envelope();}
document.addEventListener('visibilitychange',()=>{if(document.hidden){soundtrack?.pause();for(const source of playing){try{source.stop();}catch{}}playing.clear();}else if(musicWanted)music(true,musicVolume);});

const firstGesture=()=>{if(!preferences().muted)unlock();};
document.addEventListener('pointerdown',firstGesture,{once:true});
document.addEventListener('keydown',firstGesture,{once:true});
