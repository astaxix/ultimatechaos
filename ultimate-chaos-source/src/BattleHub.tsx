import {useEffect,useState} from 'react';
import {createPortal} from 'react-dom';
import {ArrowRight,Infinity as InfinityIcon,Link2,Map,Plus,ShieldCheck,Swords,Users,X} from 'lucide-react';
import {Traveler} from './Traveler';
import {DialogFocus} from './DialogFocus';
import type {Profile} from './social';
type Props={active?:boolean;profile:Profile;busy:boolean;onCreate:()=>void;onJoin:()=>void;onCampaign:()=>void;onEndless:()=>void;onFriends:()=>void;onRanked:()=>void};
export function BattleHub({active=true,profile,busy,onCreate,onJoin,onCampaign,onEndless,onFriends,onRanked}:Props){
 const [open,setOpen]=useState(false);
 useEffect(()=>{if(!active)setOpen(false);},[active]);
 const choose=(action:()=>void)=>{setOpen(false);action();};
 const modes=[{name:'Kampagne',text:'Deine Reise. Acht Kapitel. Zwei Bosse.',icon:Map,art:'campaign',action:onCampaign},{name:'Endloskampf',text:'Wie weit kommst du mit zehn Herzen?',icon:InfinityIcon,art:'endless',action:onEndless},{name:'Online-PvP',text:'Echte Rivalen. Dein Weg an die Spitze.',icon:Swords,art:'ranked',action:onRanked},{name:'Mit Freunden',text:'Fordere deine Freunde zum Duell.',icon:Users,art:'friends',action:onFriends}];
 return <section className="battle-lobby" aria-label="Deine Kampflobby"><div className="lobby-stage"><div className="lobby-halo" aria-hidden="true"/><div className="lobby-character"><Traveler look={profile.appearance} label={'Dein Charakter: '+profile.name}/></div><div className="lobby-identity"><span>DEINE ARENA</span><h1>{profile.name}</h1></div></div><div className="lobby-action"><button className="lobby-fight" disabled={busy} onClick={()=>setOpen(true)} aria-haspopup="dialog"><Swords size={23}/><span>Jetzt kämpfen</span><ArrowRight size={20}/></button><p><ShieldCheck size={12}/> Dein Style. Gleiche Chancen.</p></div>
 {open&&createPortal(<div className="mode-backdrop" onClick={()=>setOpen(false)}><section className="mode-sheet" role="dialog" aria-modal="true" aria-labelledby="mode-title" onClick={e=>e.stopPropagation()}><DialogFocus selector=".mode-sheet" onClose={()=>setOpen(false)}/><button className="icon-btn mode-close" aria-label="Spielmodi schließen" onClick={()=>setOpen(false)}><X size={19}/></button><h2 id="mode-title">Dein nächster Kampf.</h2><p className="mode-intro">Wähle deine Arena.</p><div className="mode-grid">{modes.map(mode=><button className={'mode-choice mode-'+mode.art} key={mode.art} disabled={busy} onClick={()=>choose(mode.action)}><mode.icon size={26}/><span><b>{mode.name}</b><small>{mode.text}</small></span><ArrowRight size={16}/></button>)}</div><div className="mode-private"><button disabled={busy} onClick={()=>choose(onCreate)}><Plus size={15}/> Raum erstellen</button><button disabled={busy} onClick={()=>choose(onJoin)}><Link2 size={15}/> Code eingeben</button></div></section></div>,document.body)}
 </section>;
}
