import {useEffect,useState} from 'react';
import {createPortal} from 'react-dom';
import {ArrowLeft,ArrowRight,Crown,Heart,Infinity as InfinityIcon,LoaderCircle,LockKeyhole,Map,Trophy,X} from 'lucide-react';
import {campaign,enemyLook} from './campaign';
import {chapterArena,arenas} from './arenas';
import {Traveler} from './Traveler';
import {Avatar} from './Avatar';
import {DialogFocus} from './DialogFocus';
import {CoinGlyph} from './Artwork';
import {endlessStats,type EndlessStats} from './backend';
import type {Profile} from './social';
type Props={mode:'campaign'|'endless';profile:Profile;busy:boolean;preview:boolean;error:string;onClose:()=>void;onCampaign:(stage:number)=>void;onEndless:()=>void};
export function ArenaPortal({mode,profile,busy,preview,error,onClose,onCampaign,onEndless}:Props){
 const [stage,setStage]=useState(Math.min(profile.campaign_unlocked??0,7)),[tab,setTab]=useState<'overview'|'ranking'|'history'>('overview'),[page,setPage]=useState(0),[stats,setStats]=useState<EndlessStats|null>(null),[statsError,setStatsError]=useState('');
 useEffect(()=>{if(mode!=='endless'||preview)return;let alive=true;void endlessStats().then(d=>{if(alive)setStats(d);}).catch(()=>{if(alive)setStatsError('Statistiken gerade nicht erreichbar. Du kannst trotzdem starten.');});return()=>{alive=false;};},[mode,preview]);
 const foe=campaign[stage],locked=stage>(profile.campaign_unlocked??0),best=stats?.best??profile.endless_best??0;
 const rows=tab==='ranking'?stats?.leaderboard??[]:stats?.history??[],pages=Math.max(1,Math.ceil(rows.length/4));
 return createPortal(<div className="arena-portal-backdrop" onClick={onClose}><section className={'arena-portal '+mode} role="dialog" aria-modal="true" aria-labelledby="arena-portal-title" onClick={e=>e.stopPropagation()}>
  <DialogFocus selector=".arena-portal" onClose={onClose}/>
  <header className="portal-header"><div><span>{mode==='campaign'?'ACHT KAPITEL · DEINE GESCHICHTE':'ZEHN HERZEN · KEIN LIMIT'}</span><h2 id="arena-portal-title">{mode==='campaign'?'Die Chroniken':'Endloskampf'}</h2></div><button className="icon-btn" aria-label="Arena schließen" onClick={onClose}><X size={20}/></button></header>
  {mode==='campaign'?<>
   <div className="chapter-focus" style={{backgroundImage:`linear-gradient(90deg,#0a1421e8,#0a142155),url('${arenas[chapterArena[stage]].image}')`}}><div className="chapter-copy"><span>{foe.target?<><Crown size={12}/> BOSS</>:foe.difficulty} · KAPITEL {stage+1}</span><h3>{foe.name}</h3><p>{foe.title}</p><div className="chapter-vitals"><span><Heart size={13}/> Du 5 · Gegner {foe.target||5}</span><span>10 Sek. pro Zug</span></div><div className="chapter-prize"><span>+{foe.xp} XP</span><span><CoinGlyph/> +{foe.coins}</span></div></div><Traveler look={enemyLook(stage)} label={foe.name}/></div>
   <div className="chapter-picker" aria-label="Alle acht Kampagnenkapitel">{campaign.map((enemy,i)=><button key={enemy.name} aria-pressed={stage===i} aria-label={`Kapitel ${i+1}: ${enemy.name}${i>(profile.campaign_unlocked??0)?' — gesperrt':''}`} className={i>(profile.campaign_unlocked??0)?'locked':''} onClick={()=>setStage(i)}><Avatar index={0} appearance={enemyLook(i)} size="small"/><b>{enemy.name}</b><span>{i>(profile.campaign_unlocked??0)?<LockKeyhole size={10}/>:enemy.target?<Crown size={10}/>:<Map size={10}/>} {i+1}</span></button>)}</div>
   <p className="portal-hint">Wähle ein Kapitel. Kosmetische Styles geben keine Kampfboni.</p>
  </>:<>
   <nav className="portal-tabs" aria-label="Endloskampf-Ansichten">{([['overview','Übersicht'],['ranking','Bestenliste'],['history','Meine Läufe']] as const).map(([id,label])=><button key={id} aria-pressed={tab===id} onClick={()=>{setTab(id);setPage(0);}}>{label}</button>)}</nav>
   {tab==='overview'?<><div className="endless-portal-hero"><div><InfinityIcon size={34}/><h3>Ein Lauf.<br/>Alles geben.</h3><p>Gegner werden stärker.<br/>Deine Herzen bleiben.</p></div><Traveler look={profile.appearance} label="Dein Charakter"/></div><div className="portal-stat-grid"><div><Heart size={17}/><b>10</b><span>Startleben</span></div><div><Trophy size={17}/><b>{best}</b><span>Dein Rekord</span></div><div><CoinGlyph/><b>25–125</b><span>Coins pro Gegner</span></div></div><p className="portal-hint">19–120 XP pro Gegner. Gewinne werden nach jeder Welle gespeichert. Keine Wetteinsätze.</p></>:<div className="portal-stats-page">{!stats&&!preview&&!statsError?<p role="status"><LoaderCircle size={18} className="spin"/> Statistik wird geladen …</p>:!rows.length?<p>{preview?'Melde dich für deine Statistiken an.':'Noch keine Einträge. Dein nächster Lauf zählt.'}</p>:rows.slice(page*4,page*4+4).map((row,i)=>'name'in row?<div className="portal-rank-row" key={row.id}><span>{page*4+i+1}</span><Avatar index={0} appearance={row.appearance} size="small"/><b>{row.name}</b><strong>Welle {row.wave}</strong></div>:<div className="portal-run-row" key={row.created_at}><b>Welle {row.wave}</b><span>{row.defeated} besiegt · +{row.xp} XP</span><strong>+{row.coins} Coins</strong></div>)}{pages>1&&<div className="portal-pagination"><button aria-label="Vorherige Statistikseite" disabled={page===0} onClick={()=>setPage(p=>p-1)}><ArrowLeft size={17}/></button><span>{page+1} / {pages}</span><button aria-label="Nächste Statistikseite" disabled={page+1>=pages} onClick={()=>setPage(p=>p+1)}><ArrowRight size={17}/></button></div>}</div>}
   {statsError&&<p className="portal-hint" role="status">{statsError}</p>}
  </>}
  {error&&<p className="portal-error" role="alert">{error}</p>}
  <footer className="portal-footer"><button className="btn primary full" disabled={busy||preview||(mode==='campaign'&&locked)} onClick={()=>mode==='campaign'?onCampaign(stage):onEndless()}>{busy?<LoaderCircle size={17} className="spin"/>:<ArrowRight size={17}/>} {busy?'Arena wird vorbereitet …':mode==='campaign'?locked?'Vorheriges Kapitel gewinnen':'Kapitel '+(stage+1)+' starten':stats?.active?'Lauf fortsetzen · Welle '+stats.active.wave:'Jetzt starten'}</button><small>{preview?'Vorschau · Melde dich zum Spielen an.':mode==='campaign'?`Niederlage: +${40+stage*10} XP · Coins nur bei Sieg`:'Bei null Herzen endet dein Lauf. Dein Rekord bleibt.'}</small></footer>
 </section></div>,document.body);
}
