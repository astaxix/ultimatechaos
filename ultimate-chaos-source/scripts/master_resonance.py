"""Master the original offline score and encode the website loop (macOS afconvert)."""
from pathlib import Path
import subprocess,wave,json
import numpy as np
root=Path('outputs/polish');root.mkdir(parents=True,exist_ok=True)
subprocess.run(['swift','scripts/compose_resonance.swift',str(root/'resonance-master.caf')],check=True)
subprocess.run(['afconvert','-f','WAVE','-d','LEI16',str(root/'resonance-master.caf'),str(root/'resonance-master.wav')],check=True)
sr=32000;length=int((48*4*60/74)*sr)
with wave.open(str(root/'resonance-master.wav'))as f:a=np.frombuffer(f.readframes(f.getnframes()),dtype='<i2').astype(np.float64).reshape(-1,2)/32768
b=a[:length].copy();tail=a[length:];b[:len(tail)]+=tail;b-=b.mean(axis=0)
b*=min(.1/max(float(np.sqrt(np.mean(b*b))),1e-6),.65/max(float(np.max(np.abs(b))),1e-6))
n=160;b[:n]*=np.linspace(.05,1,n)[:,None];b[-n:]*=np.linspace(1,.05,n)[:,None]
with wave.open(str(root/'resonance-loop.wav'),'wb')as f:f.setnchannels(2);f.setsampwidth(2);f.setframerate(sr);f.writeframes((b*32767).astype('<i2').tobytes())
subprocess.run(['afconvert','-f','m4af','-d','aac','-b','192000',str(root/'resonance-loop.wav'),'public/audio/resonance-lounge.m4a'],check=True)
(root/'music-report.json').write_text(json.dumps({'title':'Astral Afterhours','duration':len(b)/sr,'bpm':74,'rms':float(np.sqrt(np.mean(b*b))),'peak':float(np.max(np.abs(b))),'loop_tail_seconds':len(tail)/sr},indent=2))
