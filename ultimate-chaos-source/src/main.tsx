import './arenas.css';
import {PreferencesRuntime} from './GameSettings';import './preferences.css';
import React from 'react';import ReactDOM from 'react-dom/client';import AccountShell from './AccountShell';import './styles.css';import './premium.css';import './atelier.css';import './campaign.css';import './life-duels.css';import './endless.css';import './ranked.css';import './community.css';import './cosmetics.css';
const root=ReactDOM.createRoot(document.getElementById('root')!);
if(import.meta.env.DEV&&location.pathname==='/__migration'){void import('./MigrationQA').then(({default:MigrationQA})=>root.render(<MigrationQA/>));}
else if(import.meta.env.DEV&&location.pathname==='/__visual'){void import('./VisualQA').then(({default:VisualQA})=>root.render(<VisualQA/>));}
else root.render(<React.StrictMode><PreferencesRuntime/><AccountShell/></React.StrictMode>);
