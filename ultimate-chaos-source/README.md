# Ultimate Chaos
A responsive dark fantasy browser game built with React, TypeScript, Vite and Supabase.

## Play
- Five lives in standard duels; ten seconds for each secret choice. Both players can confirm to resolve immediately. A round winner deals one damage to the opponent; draws deal no damage.
- Eight campaign chapters with distinct opponents, adaptive strategies based only on previous rounds, and bosses with eight or eleven lives.
- Endless Arena starts with ten lives. Enemy lives increase with the wave, while the player's remaining lives carry over.
- Real rating-based matchmaking, private rooms, friend challenges, private chat and battle emotes.
- A detailed character editor, individual eight-card loadouts, 97 cosmetic items, daily server-priced offers, four chest tiers, opening history and duplicate conversion.
- Daily quests, permanent achievements and a private match journal. Old account balances and progression are retained; detailed journal statistics begin with the journal migration.
- Music and effects have separate volume controls. Graphics always use High quality; reduced motion remains available.
- Installable PWA with local app icons. Online match documents, API responses and authentication are never stored by the service worker. Offline navigation shows a connection screen.

Cosmetics never change the eight-power rule matrix. Currency is earned in game, with no real-money purchases or cash-out.

## Development
Use Node.js 24, then:
```sh
npm ci
cp .env.example .env.local
npm run dev
```
Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` to the project's public client configuration. Never use an administrator or service-role key in a Vite variable.

```sh
npm test
npm run build
```
Database integration tests run the actual SQL using PGlite. Development-only visual fixtures are available at `/__visual`, `/__auth` and `/__account`; migration inspection is at `/__migration`. These inspection routes are not included in production.

## Database
For a **fresh** database, run `supabase/setup-fresh.sql`; it aborts if the game is already installed. For an existing database, apply only the missing numbered migration files in order. Migration 002 is an optional scheduled cleanup and requires pg_cron.

Private moves, inventories, purchase receipts, progress awards and journal records remain in the unexposed `chaos_private` schema. Client mutations use authenticated RPCs. Purchases, chest outcomes, game results, rewards and claims are decided and committed on the server, with locks and unique receipts.

The `tests/live-*-smoke.sql` scripts use generated temporary accounts and roll back their changes. Full auth, mail delivery and device testing require separate real test accounts; local SQL tests are not a substitute for those checks.

## Deployment
The repository contains the app in `ultimate-chaos-source`. In Vercel use:
- Root Directory: `ultimate-chaos-source`
- Framework: Vite
- Install: `npm ci`
- Build: `npm run build`
- Output: `dist`
- Node.js: 24.x

Connect the GitHub repository and use `main` as the production branch. Configure the two public Supabase client variables in Vercel and add the final URL to Supabase Auth's site/redirect settings.

## Artwork
All game art, music and fonts are served locally. Original generated image prompts and source paths are documented in [ARTWORK.md](ARTWORK.md). The crest, character layers and effects extend the project's native SVG/CSS artwork. Font license files are in `public/fonts`.

PvP match stakes use only free, nontransferable, nonredeemable game coins. One ten-second stake phase precedes the entire match; both ready ends it early. Campaign, endless and bot matches have no stakes. The server reserves the stake once, settles it after the match, pays 2× for an eligible match win and refunds draws, abandonment or inactivity. Wallet balance and daily profit limit apply; there is no level gate.

Emote loadouts hold five different free or owned reactions. Five are included; additional illustrated emotes are cosmetic shop or mystery-pack rewards.

Eight-card balance: each power beats three, loses to three, and draws with one distinct power. Equal choices also draw. The original scissors–rock–paper triangle stays intact. In-progress seven-card matches retain their original rules; new matches use eight powers after migration 024. The demonic sniper is free to every player.

## Ascension visual update (2026-10-17)
Campaign and endless entry use focused, keyboard-accessible dialogs with all primary choices in a mobile viewport. The profile separates identity, statistics and journal from the character editor. Layered SVG avatars keep all existing appearance options; four new garment silhouettes, four independent sniper skins and a padded sniper illustration are cosmetic only. Migration `025_ascension_cosmetics.sql` adds these eight items to the existing shop and pack pool without changing rules, ownership or payouts.

Original 48-second lobby and battle music loops and fourteen effects are generated by `scripts/compose_ascension.py` (NumPy). Encode the intermediate WAV tracks using macOS `afconvert -f m4af -d aac -r 44100 outputs/audio/asc-lobby.wav public/audio/asc-lobby.m4a` and the equivalent battle paths. Music starts only after a user gesture, crossfades between scenes, ducks under combat effects, and respects existing mute/volume/background settings.

Validation: `npm test` includes the additive catalogue migration, real server-priced purchases, idempotency and ownership checks. `tests/live-ascension-smoke.sql` runs with generated identities inside a rolled-back transaction. Responsive visual review uses development-only `/__account` and `/__visual` routes; these inspection routes are excluded from production.

## Atelier & Nocturne (2026-10-17)
Original transparent material atlases now render the three avatar body variants, detailed garments, sculpted faces, nineteen hair styles and matching equipment. Existing appearance fields and owned items retain their IDs. SVG source-space clips isolate every sprite; the browser caches the shared WebP sheets. A dedicated mobile scoreboard slot replaces the floating emote button. Combat uses a short localized hit cue and the transparent −1 heart indicator, without the previous full-screen attack clouds.

`compose_nocturne.py` creates two original 113-second felt-piano / warm-pad loops and fourteen quieter cues. No recordings or third-party music are used. The existing gesture unlock, scene transitions, mute, separate levels and background pause remain in place. Versioned `nocturne-*` filenames avoid stale audio caches.

Migration `026_coin_treasures.sql` adds rare and mythic coin prizes inside the existing coin bucket. Main loot probabilities and style draws stay unchanged. Per-pack bonus odds and exact ranges are shown before opening. The highest tier can award 20,000–35,000 mythic coins with a 0.54% overall probability. Server receipts preserve payout idempotency. These are earned game coins with no cash purchase or withdrawal. `tests/live-treasure-smoke.sql` verifies a real jackpot credit and retry inside a rolled-back transaction.

## Character loading (2026-10-18)
The primary battle lobby is included in the initial application bundle and stays mounted, hidden from layout and keyboard navigation while another account tab is active. Returning to Kämpfen reuses the existing character DOM. A bounded, shared image-preparation cache keeps decoded avatar sheets referenced across navigation, coalesces concurrent loads, retries failed requests and starts with the last selected body hint during authentication. Once the current character is ready, the other two body sheets warm at low priority for opponents. Preparation failures do not block login. Existing appearance, skin ownership and game rules are unchanged.

### Arkanum and combat items
Apply `027_battle_items.sql`, then `028_arsenal_packs.sql` to existing installations. New installations use `setup-fresh.sql`. Existing active rooms retain their original rules. New campaign, endless and private matches allow up to three consumables per match, with one Joker maximum; ranked matches disable items. Selecting an item replaces the card, confirming locks the turn, and stock is consumed only on resolution. Card selection cancels an unconfirmed item. Starter inventory is granted exactly once.

Items are bought with earned coins or found in packs. Arkanum costs 650 coins and guarantees 3–5 of one consumable; rarity weights are displayed in the shop. Other packs have a 20% consumable share within their cosmetic rarity buckets (9%, 12%, 14%, 16% overall respectively). Consumables stack rather than convert into duplicate coins. Existing cosmetic duplicate conversion and coin jackpots remain unchanged.

`tests/battle-items.test.mjs` exercises actual RPCs, private selection, purchase/open idempotency, stock consumption, use limits, protection/healing/burn, ranked restrictions and legacy rooms. `tests/live-arsenal-smoke.sql` uses a generated identity inside a rolled-back transaction.
