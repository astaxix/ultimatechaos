import {ArrowRight,Bot,Flame,ShieldCheck,Swords,Trophy,Users,Zap} from 'lucide-react';
import {Avatar} from './Avatar';
import {Traveler} from './Traveler';
import {CoinGlyph} from './Artwork';
import {level,type Friend,type Profile} from './social';

type Props={profile:Profile;friends:Friend[];busy:boolean;onBot:()=>void;onDuel:()=>void;onFriends:()=>void;onProfile:()=>void;onEndless:()=>void;onShop:()=>void};
export function HomeArena({profile,friends,busy,onBot,onDuel,onFriends,onProfile,onShop,onEndless}:Props){
 const progress=profile.xp%250;
 return <>
  <section className="command-hero" aria-label="Deine Arena">
   <div className="command-copy"><span className="chapter-label"><Flame size={15}/> DIE HIMMLISCHE ARENA</span><h3>Sieben Mächte.<br/><em>Dein Moment.</em></h3><p>Wähle deine Macht.<br/>Jeder Zug entscheidet.</p><div className="hero-rule-strip"><span><Zap size={15}/> 10 Sekunden pro Zug</span><span><ShieldCheck size={15}/> Gleiche Chancen</span></div></div>
   <div className="command-guardian" aria-hidden="true"><div className="guardian-halo"/><Traveler look={profile.appearance}/><div className="guardian-floor"/></div>
   <div className="hero-bottom-bar"><span>Göttliche Eskalation</span><span>Schere, Stein, Papier. Und vier schlechte Ideen mehr.</span></div>
  </section>
  <div className="home-play-actions"><button className="btn primary" disabled={busy} onClick={onDuel}><Swords size={20}/> JETZT KÄMPFEN <ArrowRight size={16}/></button><button className="btn secondary" disabled={busy} onClick={onEndless}>ENDLOS-ARENA <ArrowRight size={16}/></button></div><div className="play-heading"><h3>Wie willst du spielen?</h3><span>Deine Arena. Deine Entscheidung.</span></div>
  <div className="mode-grid">
   <button className="mode-card mode-bot" onClick={onBot} disabled={busy}><div className="mode-icon"><Bot size={26}/></div><div><span className="mode-kicker">SOLO</span><h4>Kampagne</h4><p>Acht Gegner. Zwei Bosse. Dein Weg.</p><span className="mode-reward"><Trophy size={13}/> Mehr XP & Coins je nach Kapitel</span></div><ArrowRight className="mode-arrow" size={22}/></button>
   <button className="mode-card mode-friend" onClick={onDuel} disabled={busy}><div className="mode-icon"><Swords size={26}/></div><div><span className="mode-kicker">PRIVATES 1V1</span><h4>Gegen einen Freund</h4><p>Raum erstellen, Code teilen, Chaos starten.</p><span className="mode-reward"><Users size={13}/> Nur du und dein Rivale</span></div><ArrowRight className="mode-arrow" size={22}/></button>
  </div>
  <div className="arena-dashboard">
   <section className="progress-card panel"><div className="progress-profile"><Avatar appearance={profile.appearance} index={profile.avatar} frame={profile.frame}/><div><span className="mode-kicker">DEIN FORTSCHRITT</span><h3>{profile.name}</h3></div><button className="text-btn" onClick={onProfile} aria-label="Profil bearbeiten"><ArrowRight size={19}/></button></div><div className="level-progress"><strong>Level {level(profile.xp)}</strong><span>{progress} / 250 XP</span></div><div className="xp-bar" role="progressbar" aria-label="Erfahrung bis zum nächsten Level" aria-valuemin={0} aria-valuemax={250} aria-valuenow={progress}><i style={{width:`${progress/2.5}%`}}/></div><div className="career-stats"><div><b>{profile.matches}</b><span>DUELLE</span></div><div><b>{profile.wins}</b><span>SIEGE</span></div><div><b>{profile.coins}</b><span>CHAOS COINS</span></div></div></section>
   <section className="rivals-card panel"><div className="section-top"><h3>Deine Rivalen</h3><button onClick={onFriends}>Freunde <ArrowRight size={14}/></button></div>{friends.length?<div className="rival-stack">{friends.slice(0,4).map(friend=><Avatar appearance={friend.profile.appearance} key={friend.id} index={friend.profile.avatar} frame={friend.profile.frame}/>)}</div>:<div className="rival-empty"><Users size={32}/><p>Ein guter Freund.<br/>Ein noch besserer Gegner.</p></div>}<button className="text-btn" onClick={onFriends}>{friends.length?'FREUND HERAUSFORDERN':'FREUNDE HINZUFÜGEN'} <ArrowRight size={14}/></button></section>
   <button className="treasury-card panel" onClick={onShop}><span className="mode-kicker">DIE SCHATZKAMMER</span><CoinGlyph/><h3>Dein Sieg.<br/><em>Dein Glanz.</em></h3><p>Kleidung, Auren und Signature-Styles.<br/>Coins für Siege – je nach Spielmodus.</p><span className="text-btn">SHOP ÖFFNEN <ArrowRight size={14}/></span></button>
  </div>
 </>;
}
