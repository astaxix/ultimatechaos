import {Volume2,VolumeX} from 'lucide-react';
import {tick,unlock} from './audio';import {updatePreferences,usePreferences} from './preferences';
export function SoundToggle(){const p=usePreferences();return <button className="icon-btn sound-control" aria-label={p.muted?'Sound einschalten':'Sound ausschalten'} aria-pressed={!p.muted} onClick={()=>{unlock();updatePreferences({muted:!p.muted});if(p.muted)tick(p.effects);}}>{p.muted?<VolumeX size={18}/>:<Volume2 size={18}/>}</button>;}
