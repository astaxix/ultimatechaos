import {preferences} from './preferences';
let context:AudioContext|null=null;
const buffers=new Map<string,Promise<AudioBuffer|null>>();
let soundtrack:HTMLAudioElement|null=null,musicWanted=false,musicVolume=0;
const playing=new Set<AudioBufferSourceNode>();
function buffer(name:string){if(!context)return Promise.resolve(null);if(!buffers.has(name)){const c=context;buffers.set(name,fetch(`/audio/${name}.wav`).then(r=>r.ok?r.arrayBuffer():Promise.reject()).then(b=>c.decodeAudioData(b)).catch(()=>null));}return buffers.get(name)!;}
export function unlock(){try{const Constructor=window.AudioContext??(window as Window&{webkitAudioContext?:typeof AudioContext}).webkitAudioContext;if(!Constructor)return;context??=new Constructor();if(context.state==='suspended')void context.resume().catch(()=>{});void buffer('select');void buffer('tick');if(musicWanted)music(true,musicVolume);}catch{}}
function play(name:string,volume:number){if(volume<=0||preferences().muted||document.hidden)return;unlock();const c=context;if(!c)return;void buffer(name).then(b=>{if(!b||c.state!=='running'||document.hidden)return;while(playing.size>=6){const oldest=playing.values().next().value;if(!oldest)break;oldest.stop();playing.delete(oldest);}const source=c.createBufferSource(),gain=c.createGain();source.buffer=b;gain.gain.value=Math.min(1,volume)*.7;source.connect(gain).connect(c.destination);playing.add(source);source.onended=()=>{playing.delete(source);source.disconnect();gain.disconnect();};source.start();});}
export function sound(fighter:number,volume:number){play(`power-${fighter}`,volume);}
export function tick(volume:number){play('tick',volume*.45);}
export function cue(kind:'select'|'win'|'lose'|'draw'|'level',volume:number){play(kind,volume);}
export function music(on:boolean,volume:number){musicWanted=on&&volume>0;musicVolume=volume;if(!musicWanted){soundtrack?.pause();return;}if(!soundtrack){soundtrack=new Audio('/audio/atelier-score.mp3');soundtrack.loop=true;soundtrack.preload='none';}soundtrack.volume=Math.min(.42,volume*.32);if(!document.hidden)void soundtrack.play().catch(()=>{});}
document.addEventListener('visibilitychange',()=>{if(document.hidden){soundtrack?.pause();for(const source of playing){try{source.stop();}catch{}}playing.clear();}else if(musicWanted)music(true,musicVolume);});
