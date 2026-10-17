import {primeCharacterAssets} from './character-assets';
import {GameBoundary,recoverUpdatedAssets} from './GameBoundary';

import {PwaRuntime} from './InstallGame';


import {PreferencesRuntime} from './GameSettings';
import React from 'react';import ReactDOM from 'react-dom/client';import AccountShell from './AccountShell';import './styles.css';import './premium.css';import './atelier.css';import './campaign.css';import './life-duels.css';import './endless.css';import './ranked.css';import './community.css';import './cosmetics.css';import './preferences.css';import './arenas.css';import './journal.css';import './tutorial.css';import './updates.css';import './auth.css';import './lobby.css';import './ascension.css';
void primeCharacterAssets();
window.addEventListener('vite:preloadError',recoverUpdatedAssets);
const root=ReactDOM.createRoot(document.getElementById('root')!);
if(import.meta.env.DEV&&location.pathname==='/__migration'){void import('./MigrationQA').then(({default:MigrationQA})=>root.render(<MigrationQA/>));}
else if(import.meta.env.DEV&&location.pathname==='/__materials'){void import('./MaterialQA').then(({default:MaterialQA})=>root.render(<MaterialQA/>));}
else if(import.meta.env.DEV&&location.pathname==='/__visual'){void import('./VisualQA').then(({default:VisualQA})=>root.render(<VisualQA/>));}
else root.render(<React.StrictMode><PreferencesRuntime/><PwaRuntime/><React.Suspense fallback={<div className="session-loading" role="status">Deine Arena wird geladen …</div>}><GameBoundary><AccountShell/></GameBoundary></React.Suspense></React.StrictMode>);

import './atelier-render.css';
