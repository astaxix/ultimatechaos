"""Original deterministic score and sound design; no third-party recordings."""
from pathlib import Path
import numpy as np
import wave
SR=22050
rng=np.random.default_rng(20261013)
out=Path('public/audio');out.mkdir(parents=True,exist_ok=True)
def tone(freq,duration,kind='harp'):
 t=np.arange(int(SR*duration))/SR
 if kind=='strings':
  env=np.minimum(t/.25,1)*np.minimum((duration-t)/.35,1)*.4
  a=sum(np.sin(2*np.pi*freq*h*t+np.sin(2*np.pi*4.7*t)*.015*h)/(h*h) for h in range(1,7))
 elif kind=='bell':
  env=np.exp(-t*3);a=sum(np.sin(2*np.pi*freq*h*t)*v for h,v in [(1,1),(2.01,.3),(3.98,.12)])
 else:
  env=np.minimum(t/.006,1)*np.exp(-t*4.5);a=sum(np.sin(2*np.pi*freq*h*t)/(h*h) for h in range(1,7))
 return a*env*np.minimum((duration-t)/.04,1)
def noise(dur,low=8):
 n=rng.normal(0,1,int(SR*dur));return np.convolve(n,np.ones(low)/low,'same')
def save(name,a,peak=.65):
 a=np.nan_to_num(a);a=a/max(1,np.max(np.abs(a))/peak)
 with wave.open(str(out/(name+'.wav')),'w') as w:
  w.setnchannels(1 if a.ndim==1 else 2);w.setsampwidth(2);w.setframerate(SR);w.writeframes((a*32767).astype('<i2').tobytes())
def phrase(notes,step=.13,kind='harp'):
 a=np.zeros(int(SR*(len(notes)*step+1.5)))
 for i,f in enumerate(notes):
  v=tone(f,1.25,kind)*.2;j=int(i*step*SR);a[j:j+len(v)]+=v
 return a
beat=.625;duration=16*4*beat
mix=np.zeros((int(SR*(duration+3)),2))
def add(a,start,gain=.1,pan=0):
 j=int(start*SR);n=min(len(a),len(mix)-j)
 if n<=0:return
 mix[j:j+n,0]+=a[:n]*gain*np.sqrt((1-pan)/2);mix[j:j+n,1]+=a[:n]*gain*np.sqrt((1+pan)/2)
chords=[[146.83,174.61,220,293.66],[116.54,146.83,174.61,233.08],[130.81,174.61,220,261.63],[130.81,164.81,196,261.63]]
melody=[440,349.23,392,293.66,349.23,440,523.25,392,440,523.25,587.33,523.25,392,349.23,329.63,293.66]
for bar in range(16):
 c=chords[bar%4];start=bar*4*beat
 for j,f in enumerate(c):add(tone(f,4*beat+.5,'strings'),start,.075,(-.55+j*.35))
 add(tone(c[0]/2,2.2,'harp'),start,.18,-.1)
 for eighth in range(8):add(tone(c[[0,2,1,3,2,1,3,2][eighth]]*(2 if bar>=8 else 1),1.5),start+eighth*beat/2,.12,-.35 if eighth%2 else .35)
 if bar>=4:
  add(tone(melody[bar],1.5,'bell'),start+beat,.07,.15)
  add(tone(melody[(bar+3)%16],1.5,'bell'),start+3*beat,.055,-.15)
 for b in [0,2]:
  t=np.arange(int(SR*.5))/SR;k=np.sin(2*np.pi*(48*t+8*(1-np.exp(-t*20))))*np.exp(-t*12)
  add(k,start+b*beat,.09)
 if bar>=8:
  t=np.arange(int(SR*.13))/SR;add(noise(.13,3)*np.exp(-t*38),start+3*beat,.03,.3)
for delay,gain in [(.071,.12),(.149,.09),(.281,.06),(.431,.04)]:
 n=int(delay*SR);mix[n:]+=mix[:-n,::-1]*gain
length=int(duration*SR);mix[:len(mix)-length]+=mix[length:];mix=mix[:length]
save('atelier-score',mix,.55)
save('select',phrase([587.33,880],.035,'harp')[:int(.25*SR)]*.65,.3)
save('tick',tone(440,.08,'harp')*.055,.1)
for i in range(7):
 dur=[.45,.85,.55,1.1,1.1,.6,1.4][i];t=np.arange(int(dur*SR))/SR
 if i in (0,2):a=noise(dur,2 if i==0 else 14)*np.sin(np.pi*t/dur)**2*np.exp(-t*9)*.6
 elif i in (1,5,6):
  a=noise(dur,18 if i!=5 else 4)*np.exp(-t*(7 if i!=6 else 3))*.6+np.sin(2*np.pi*(45*t+10*(1-np.exp(-t*15))))*np.exp(-t*6)*.35
 else:
  a=np.zeros(len(t))
  for n,f in enumerate([293.66,440,587.33,880]):
   v=tone(f,dur-n*.06,'bell')*.13;j=int(n*.06*SR);a[j:j+len(v)]+=v[:len(a)-j]
 save('power-'+str(i),a,.55)
save('win',phrase([293.66,369.99,440,587.33],.14,'bell'),.5)
save('level',phrase([293.66,369.99,440,587.33,739.99,880],.12,'bell'),.5)
save('draw',phrase([293.66,392,440],.16,'harp'),.35)
save('lose',phrase([293.66,261.63,220],.16,'harp'),.35)
