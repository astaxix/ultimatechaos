import {Component,type ReactNode} from 'react';
/** A failed lazy view must never leave the player on a blank screen. */
export class GameBoundary extends Component<{children:ReactNode},{failed:boolean}>{
 state={failed:false};
 static getDerivedStateFromError(){return {failed:true};}
 render(){return this.state.failed?<main className="session-loading" role="alert"><div><h2>Deine Ansicht konnte nicht geladen werden.</h2><p>Bitte lade das Spiel erneut. Dein gespeicherter Fortschritt bleibt erhalten.</p><button className="btn primary" onClick={()=>location.reload()}>Spiel neu laden</button></div></main>:this.props.children;}
}
/** Old open tabs can request a chunk removed by a new deployment. Retry once. */
export function recoverUpdatedAssets(event:Event){
 event.preventDefault();
 try{const key='chaos-asset-reload',previous=Number(sessionStorage.getItem(key));if(Date.now()-previous<30000)return;sessionStorage.setItem(key,String(Date.now()));location.reload();}catch{/* The boundary keeps a manual retry available when storage is unavailable. */}
}
