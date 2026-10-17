"""Original, reproducible stereo score and layered SFX; no third-party samples."""
from pathlib import Path
import numpy as np
import wave
SR=22050
rng=np.random.default_rng(20261017)
out=Path('public/audio');tmp=Path('outputs/audio');out.mkdir(exist_ok=True);tmp.mkdir(parents=True,exist_ok=True)
def write(path,a,peak=.72):
 a=np.nan_to_num(a);a-=a.mean(axis=0);a=np.tanh(a*1.2);a*=min(1,peak/max(.001,np.max(np.abs(a))))
 ramp=min(int(SR*.012),len(a)//2);edge=np.linspace(0,1,ramp);a[:ramp]*=edge[:,None] if a.ndim==2 else edge;a[-ramp:]*=edge[::-1,None] if a.ndim==2 else edge[::-1]
 with wave.open(str(path),'w') as w:w.setnchannels(2 if a.ndim==2 else 1);w.setsampwidth(2);w.setframerate(SR);w.writeframes((a*32767).astype('<i2').tobytes())
def tone(f,d,attack=.03,release=.3,rich=5):
 t=np.arange(int(SR*d))/SR;env=np.minimum(t/attack,1)*np.minimum((d-t)/release,1)
 return sum(np.sin(2*np.pi*f*h*t+np.sin(2*np.pi*4.6*t)*.009*h)/h**1.8 for h in range(1,rich+1))*env
chords=[[146.832,174.614,220,329.628],[116.541,146.832,174.614,261.626],[130.813,174.614,220,293.665],[110,130.813,164.814,246.942]]
for mode in ['lobby','battle']:
 beat=.75;length=int(SR*48);mix=np.zeros((length+int(SR*3),2))
 def add(a,at,gain=.12,pan=0):
  j=int(at*SR);n=min(len(a),len(mix)-j)
  if n>0:mix[j:j+n,0]+=a[:n]*gain*np.sqrt((1-pan)/2);mix[j:j+n,1]+=a[:n]*gain*np.sqrt((1+pan)/2)
 for bar in range(16):
  chord=chords[(bar//2)%4];at=bar*beat*4
  for i,f in enumerate(chord):add(tone(f,3.7,.65,.9,8),at,.075,[-.7,-.25,.25,.7][i])
  add(tone(chord[0]/2,2.9,.2,.8,3),at,.15)
  if bar%2==0:add(tone(chord[2]*2,2.8,.18,1.6,3),at+beat,.04,.3)
  for i in range(8 if mode=='battle' else 4):
   f=chord[[0,2,1,3,2,1,3,2][i]]*(2 if i%3==2 else 1)
   add(tone(f,1.1,.018,.75,4),at+i*beat*(.5 if mode=='battle' else 1),.055 if mode=='battle' else .025,(-.4 if i%2 else .4))
  if mode=='battle':
   for pulse in [0,2]:
    t=np.arange(int(.7*SR))/SR;drum=np.sin(2*np.pi*(42*t+1.5*(1-np.exp(-t*18))))*np.exp(-t*7)
    add(drum,at+pulse*beat,.2)
   t=np.arange(int(.32*SR))/SR;n=rng.normal(0,1,len(t));n=np.convolve(n,np.ones(12)/12,'same')*np.exp(-t*14)
   add(n,at+3*beat,.09,-.2)
 for delay,gain in [(.09,.1),(.19,.08),(.32,.055),(.53,.025)]:
  n=int(delay*SR);mix[n:]+=mix[:-n,::-1]*gain
 mix[:len(mix)-length]+=mix[length:];mix=mix[:length];write(tmp/('asc-'+mode+'.wav'),mix,.56)
for i in range(8):
 dur=[.55,.9,.55,1.2,1.4,.65,1.6,1.1][i];t=np.arange(int(dur*SR))/SR;n=rng.normal(0,1,len(t));smooth=np.convolve(n,np.ones([4,30,16,45,60,5,36,7][i])/[4,30,16,45,60,5,36,7][i],'same')
 if i in [0,2]:a=smooth*np.sin(np.pi*t/dur)**2*np.exp(-t*8)*.55+tone(160 if i==0 else 230,dur,.005,.4,2)*.06
 elif i in [1,5,6,7]:
  a=smooth*np.exp(-t*(7 if i!=6 else 3))*.7+np.sin(2*np.pi*(38*t+3*(1-np.exp(-t*22))))*np.exp(-t*7)*.45
  if i==7:a+=tone(112,dur,.003,.8,4)*.15
 else:a=sum(tone(f,dur,.025,.8,3)*.07 for f in [146.832,220,293.665,440]) + smooth*np.sin(np.pi*t/dur)**2*.13
 # A spacious, low-volume reflection adds impact without a harsh transient.
 for delay,gain in [(.075,.18),(.16,.09)]:
  k=int(delay*SR);a[k:]+=a[:-k]*gain
 write(out/('asc-power-'+str(i)+'.wav'),a,.62)
for name,notes in [('select',[440,660]),('tick',[330]),('win',[293.665,349.228,440,587.33]),('lose',[293.665,261.626,220]),('draw',[293.665,349.228]),('level',[293.665,349.228,440,587.33,698.456])]:
 d=.12 if name=='tick' else .25 if name=='select' else 1.8;a=np.zeros(int(SR*d))
 for i,f in enumerate(notes):
  j=int(i*(.035 if name=='select' else .12)*SR);n=len(a)-j
  if n>0:a[j:]+=tone(f,n/SR,.007,.7,3)*(.025 if name=='tick' else .1)
 write(out/('asc-'+name+'.wav'),a,.45)
print('Original lobby/battle scores and 14 sound effects composed.')
