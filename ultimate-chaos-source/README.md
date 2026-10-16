# Ultimate Chaos
A responsive dark fantasy browser game built with React, TypeScript, Vite and Supabase.

## Play
- Five lives in standard duels; ten seconds for each secret choice. Both players can confirm to resolve immediately. A round winner deals one damage to the opponent; draws deal no damage.
- Eight campaign chapters with distinct opponents, adaptive strategies based only on previous rounds, and bosses with eight or eleven lives.
- Endless Arena starts with ten lives. Enemy lives increase with the wave, while the player's remaining lives carry over.
- Real rating-based matchmaking, private rooms, friend challenges, private chat and battle emotes.
- A detailed character editor, individual seven-card loadouts, 97 cosmetic items, daily server-priced offers, four chest tiers, opening history and duplicate conversion.
- Daily quests, permanent achievements and a private match journal. Old account balances and progression are retained; detailed journal statistics begin with the journal migration.
- Music and effects have separate volume controls. Graphics always use High quality; reduced motion remains available.
- Installable PWA with local app icons. Online match documents, API responses and authentication are never stored by the service worker. Offline navigation shows a connection screen.

Cosmetics never change the seven-power rule matrix. Currency is earned in game, with no real-money purchases or cash-out.

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
