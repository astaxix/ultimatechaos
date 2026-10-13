let ctx:AudioContext|null=null;let drone:OscillatorNode|null=null;let musicGain:GainNode|null=null;
export function unlock(){ctx??=new AudioContext();void ctx.resume();}
export function sound(fighter:number,volume:number){
 if(volume===0)return;unlock();const c=ctx!;const t=c.currentTime;
 const freq=[880,65,420,110,660,240,45][fighter];
 for(let i=0;i<3;i++){const o=c.createOscillator();const g=c.createGain();o.type=fighter===4?'sine':fighter===0?'triangle':'sawtooth';o.frequency.setValueAtTime(freq*(1+i*.5),t);o.frequency.exponentialRampToValueAtTime(Math.max(20,freq*.25),t+1.1);g.gain.setValueAtTime(0,t+i*.09);g.gain.linearRampToValueAtTime(volume*.09,t+.02+i*.09);g.gain.exponentialRampToValueAtTime(.001,t+1.2);o.connect(g).connect(c.destination);o.start(t+i*.09);o.stop(t+1.3);}
 if(fighter===1||fighter===6||fighter===5){const buffer=c.createBuffer(1,c.sampleRate*1.5,c.sampleRate);const d=buffer.getChannelData(0);for(let i=0;i<d.length;i++)d[i]=(Math.random()*2-1)*Math.exp(-i/(c.sampleRate*.3));const s=c.createBufferSource();s.buffer=buffer;const f=c.createBiquadFilter();f.type='lowpass';f.frequency.value=fighter===5?2400:400;const g=c.createGain();g.gain.value=volume*.25;s.connect(f).connect(g).connect(c.destination);s.start();}
}
export function tick(volume:number){if(!volume)return;unlock();const c=ctx!,o=c.createOscillator(),g=c.createGain();o.frequency.value=560;g.gain.setValueAtTime(.08*volume,c.currentTime);g.gain.exponentialRampToValueAtTime(.001,c.currentTime+.12);o.connect(g).connect(c.destination);o.start();o.stop(c.currentTime+.15);}
export function music(on:boolean,volume:number){if(!on||volume===0){if(musicGain)musicGain.gain.value=0;return;}unlock();if(!drone){drone=ctx!.createOscillator();musicGain=ctx!.createGain();drone.type='sine';drone.frequency.value=82.41;drone.connect(musicGain).connect(ctx!.destination);drone.start();}musicGain!.gain.value=.024*volume;}
