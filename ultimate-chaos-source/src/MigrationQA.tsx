import eightSmoke from '../tests/live-eight-cards-smoke.sql?raw';
import migration24 from '../supabase/migrations/024_demonic_sniper.sql?raw';
import migration23 from '../supabase/migrations/023_pvp_match_wagers.sql?raw';
import updateSmoke from '../tests/live-update-smoke.sql?raw';
import migration21 from '../supabase/migrations/021_round_wagers.sql?raw';
import migration22 from '../supabase/migrations/022_emote_loadouts.sql?raw';
import journalSmoke from '../tests/live-journal-smoke.sql?raw';
import migration20 from '../supabase/migrations/020_journal_progress.sql?raw';
import collectionSmoke from '../tests/live-collection-smoke.sql?raw';
import migration15 from '../supabase/migrations/015_cosmetic_catalog.sql?raw';
import migration16 from '../supabase/migrations/016_equipment.sql?raw';
import migration17 from '../supabase/migrations/017_shop.sql?raw';
import migration18 from '../supabase/migrations/018_emotes.sql?raw';
import migration19 from '../supabase/migrations/019_packs.sql?raw';
import editorSmoke from '../tests/live-atelier-smoke.sql?raw';
import editorDetails from '../supabase/migrations/014_character_details.sql?raw';
import editor from '../supabase/migrations/013_character_editor.sql?raw';
import communityFix from '../supabase/migrations/012_chat_unblock.sql?raw';
import communitySmoke from '../tests/live-community-smoke.sql?raw';
import community from '../supabase/migrations/011_private_chat.sql?raw';
import rankedSmoke from '../tests/live-ranked-smoke.sql?raw';
import ranked from '../supabase/migrations/010_ranked_queue.sql?raw';
import migration from '../supabase/migrations/008_life_duels.sql?raw';import endless from '../supabase/migrations/009_endless_arena.sql?raw';import endlessSmoke from '../tests/live-endless-smoke.sql?raw';import smoke from '../tests/live-core-smoke.sql?raw';
/** Development-only inspection page. Never reachable in the production bundle. */
export default function MigrationQA(){const sql=location.search.includes('eight-smoke')?eightSmoke:location.search.includes('m24')?migration24:location.search.includes('m23')?migration23:location.search.includes('update-smoke')?updateSmoke:location.search.includes('m21')?migration21:location.search.includes('m22')?migration22:location.search.includes('journal-smoke')?journalSmoke:location.search.includes('m20')?migration20:location.search.includes('collection-smoke')?collectionSmoke:location.search.includes('m15')?migration15:location.search.includes('m16')?migration16:location.search.includes('m17')?migration17:location.search.includes('m18')?migration18:location.search.includes('m19')?migration19:location.search.includes('editor-smoke')?editorSmoke:location.search.includes('editor-details')?editorDetails:location.search.includes('editor')?editor:location.search.includes('community-fix')?communityFix:location.search.includes('community-smoke')?communitySmoke:location.search.includes('community')?community:location.search.includes('ranked-smoke')?rankedSmoke:location.search.includes('ranked')?ranked:location.search.includes('endless-smoke')?endlessSmoke:location.search.includes('endless')?endless:location.search.includes('smoke')?smoke:migration;return <main style={{padding:24,background:'#101a29',color:'#e7dfcc'}}><h1>{location.search.includes("endless")?"Migration 009 — Endless Arena":"Migration 008 — Life Duels"}</h1><p>{sql.length} Zeichen · additive Migration · bestehende Matches behalten ihre Regeln.</p><textarea aria-label="Geprüfte SQL-Migration" readOnly value={sql} style={{width:'100%',height:'75vh',fontFamily:'monospace'}}/></main>;}
