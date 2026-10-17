"""Original felt-piano score, warm chamber pads and restrained game Foley.
No samples or external music; deterministic offline synthesis at 32 kHz.
"""
from pathlib import Path
import numpy as np
import wave,subprocess,json
SR=32000
rng=np.random.default_rng(20261017)
out=Path('public/audio');tmp=Path('outputs/audio');tmp.mkdir(parents=True,exist_ok=True)
def hz(n):return 440*2**((n-69)/12)
def piano(note,d=3.5,velocity=.6):
 t=np.arange(int(SR*d))/SR;f=hz(note);a=np.zeros(len(t))
 for h in range(1,8):
  decay=np.exp(-t*(.85+h*.26));a+=np.sin(2*np.pi*f*h*(1+.00012*h*h)*t)*decay/(h**2.4)
 a*=np.minimum(t/.012,1)*np.minimum((d-t)/.18,1)*velocity
 return a

def pad(note,d):
 t=np.arange(int(SR*d))/SR;f=hz(note)
 a=sum(np.sin(2*np.pi*f*(1+detune)*t+np.sin(t*.7)*.018) for detune in [-.0015,0,.0015])/3
 a+=np.sin(2*np.pi*f*2*t)*.14
 return a*np.minimum(t/1.2,1)*np.minimum((d-t)/1.8,1)
report={}
def write(path,a,peak=.65):
 a=np.nan_to_num(a);a-=a.mean(axis=0);a*=min(1,peak/max(.0001,np.max(np.abs(a))))
 ramp=min(int(SR*.009),len(a)//2);e=np.linspace(0,1,ramp);a[:ramp]*=e[:,None] if a.ndim==2 else e;a[-ramp:]*=e[::-1,None] if a.ndim==2 else e[::-1]
 report[path.name]={'peak':round(float(np.max(np.abs(a))),4),'rms':round(float(np.sqrt(np.mean(a*a))),4),'seconds':round(len(a)/SR,2)}
 with wave.open(str(path),'w') as w:w.setnchannels(2 if a.ndim==2 else 1);w.setsampwidth(2);w.setframerate(SR);w.writeframes((a*32767).astype('<i2').tobytes())
# D minor 9, B-flat major 7, F major 9, C suspended / A minor.
progression=[[50,57,60,64,69],[46,53,57,62,65],[48,55,57,60,67],[45,52,55,59,64]]
melody=[[76,74,69,72],[74,72,69,65],[72,76,79,76],[71,69,67,64]]
beat=60/68;bars=32;duration=bars*4*beat
for scene in ['lobby','battle']:
 length=int(duration*SR);mix=np.zeros((length+int(6*SR),2))
 def add(a,at,gain,pan=0):
  j=int(at*SR);n=min(len(a),len(mix)-j)
  if n>0:
   mix[j:j+n,0]+=a[:n]*gain*np.sqrt((1-pan)/2);mix[j:j+n,1]+=a[:n]*gain*np.sqrt((1+pan)/2)
 for bar in range(bars):
  chord=progression[(bar//2)%4];at=bar*4*beat
  if bar%2==0:
   for i,n in enumerate(chord):add(pad(n,8*beat+2),at,.035,[-.6,-.3,0,.3,.6][i])
  for i,n in enumerate(chord[:4]):add(piano(n+12,3.7,.48),at+[0,1.45,2.5,3.25][i]*beat,.14,(-.35+i*.22))
  if bar%2==1:
   for i,n in enumerate(melody[(bar//2)%4]):add(piano(n,3.2,.45),at+[.25,1.25,2.5,3.5][i]*beat,.11,.2)
  if scene=='battle':
   # Soft plucked low strings, no drums or repetitive alarm tones.
   for k in [0,2]:add(piano(chord[0],1.8,.4),at+k*beat,.13,-.2)
 dry=mix.copy()
 for delay,gain in [(.137,.13),(.283,.1),(.431,.075),(.677,.045),(.997,.025)]:
  k=int(delay*SR);mix[k:]+=dry[:-k,::-1]*gain
 # Fold reverb tail onto the beginning for a continuous musical loop.
 mix[:len(mix)-length]+=mix[length:];mix=mix[:length]
 write(tmp/('nocturne-'+scene+'.wav'),mix,.58)
 subprocess.run(['afconvert','-f','m4af','-d','aac','-b','160000',str(tmp/('nocturne-'+scene+'.wav')),str(out/('nocturne-'+scene+'.m4a'))],check=True)
for name,notes in [('select',[69]),('tick',[62]),('win',[62,65,69,74]),('lose',[65,62,57]),('draw',[62,69]),('level',[62,69,74,77,81])]:
 d=.09 if name=='tick' else .22 if name=='select' else 2.1;a=np.zeros(int(d*SR))
 for i,n in enumerate(notes):
  j=int(i*.13*SR);tone=piano(n,(len(a)-j)/SR,.2 if name=='tick' else .42);a[j:]+=tone*.14
 write(out/('nocturne-'+name+'.wav'),a,.3)
for i in range(8):
 d=[.32,.48,.38,.7,.85,.34,.78,.4][i];t=np.arange(int(d*SR))/SR
 noise=rng.normal(size=len(t));noise=np.convolve(noise,np.ones(28)/28,'same')
 swell=np.sin(np.pi*np.minimum(1,t/(d*.6)))**2*np.exp(-t*7)
 a=noise*swell*.1+piano([62,38,65,74,77,50,33,45][i],d,.4)*.16
 # Distinct material cues: clipped shears, stone thud, paper brush, water, choir,
 # metallic click, low pressure pulse, and a dry sniper bolt. No loud blast.
 if i in [0,5,7]:a+=noise*np.exp(-t*35)*.14
 if i in [3,4]:a+=piano([81,86][i-3],d,.25)*.08
 write(out/('nocturne-power-'+str(i)+'.wav'),a,.32)
(tmp/'nocturne-report.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
