# Ultimate Chaos

Fantasy-Duelle für Browser, iPhone und PC. Wähle aus sieben Figuren, spiele zehn Runden mit je fünf Sekunden Auswahlzeit und automatischen Kämpfen. Gegen den Chaos-Bot kannst du sofort allein spielen; Freunde treten über private Raumcodes oder Herausforderungen bei.

## Fortschritt und Chaos Coins
- Sieg: 120 XP und 100 Chaos Coins.
- Unentschieden: 60 XP, keine Coins.
- Niederlage: 40 XP, keine Coins.
- Ein Level benötigt 250 XP.
- Neue Profile beginnen mit 0 Coins. Bereits vorhandene Guthaben bleiben bestehen.
- Nur abgeschlossene Duelle mit mindestens einem eigenen Spielzug geben Belohnungen. Vollständig inaktive Spieler bekommen nichts.
- Der Server verbucht Belohnungen pro Spieler und Match nur einmal. Bot-Spiele geben dieselben Belohnungen.
- Coins kaufen ausschließlich kosmetische Rahmen; alle sieben Figuren sind jederzeit verfügbar.

## Bot und Fairness
Der Server legt die zufällige Bot-Figur vor deiner Auswahl fest. Sie liegt im privaten Datenbankschema und wird erst nach Ablauf der fünf Sekunden aufgedeckt. Änderungen deiner Auswahl beeinflussen den Bot nicht. Bot-Räume können von anderen Konten weder betreten noch gelesen werden. Das Rematch benötigt nur deine Zustimmung.

## Entwicklung
Node.js 24 verwenden. `npm ci`, dann `npm run dev`. `npm run build` erstellt die Vite-Produktion in `dist/`; `npm test` führt 20 PostgreSQL-Integrationstests mit PGlite aus.

Die Frontend-Variablen sind `VITE_SUPABASE_URL` und `VITE_SUPABASE_ANON_KEY`. Ausschließlich öffentliche Publishable-/Anon-Keys verwenden; niemals Service-Role-Schlüssel ins Frontend schreiben. Lokale Umgebungsdateien sind von Git und Deployments ausgeschlossen.

## Datenbank
Für eine neue Installation `supabase/setup-fresh.sql` im Supabase SQL Editor ausführen. Das Skript bricht ab, wenn Spieltabellen bereits existieren. Bestehende Installationen aus Version 1 benötigen nur `supabase/migrations/005_bot_rewards.sql`; sie erhalten Bot-Duelle, die neuen Belohnungen und serverseitige Belohnungsbelege. Bestehende Konten, Profile und Guthaben bleiben erhalten.

E-Mailbestätigung ist erforderlich. Supabase Site URL und Redirect URLs müssen die endgültige App-Adresse zulassen. Das private Schema `chaos_private` darf nicht über die Data API exponiert werden. Profile, Freunde, Herausforderungen und Räume werden mit RLS geschützt; die neuen Bot-Funktionen prüfen die Identität serverseitig.

## Gestaltung und Audio
Die Oberfläche verwendet selbst gehostete Cinzel- und Manrope-Schriften (OFL-Lizenzen in `public/fonts/`), bestehende Figurenbilder und einen neu generierten Arena-Hintergrund. Details und Bildprompt: `ARTWORK.md`. Effekte, Auswahl-, Ergebnis- und Level-Sounds werden lokal mit Web Audio erzeugt. Stummschaltung und reduzierte Bewegung sind verfügbar; die Arena respektiert die Systemeinstellung für reduzierte Animationen.

## Prüfung
Die automatisierten Tests prüfen Spielregeln, Geheimhaltung, Zeitfenster, zehn Runden, Rematches, Authentifizierung, RLS, Freunde, Inventar, Bot-Verhalten und einmalige Belohnungen. Responsive Ansichten werden bei 320, 390, 768 und 1440 Pixeln geprüft. Ein realer Zwei-Geräte-Test ist zusätzlich sinnvoll.


## Kampagne, Charaktere und Inventar
Die Migrationen `006_character_atelier.sql` und `007_campaign_packs.sql` nach 005 einmalig ausführen. Für neue Installationen enthält `setup-fresh.sql` alle Änderungen. Migration 006 ist auf der Live-Datenbank bereits eingerichtet.

Der Charakter ersetzt die Helden-Profilbilder. Körper, Haut, acht Frisuren, freie Haar-/Augenfarben, Gesicht, Brauen, Bart und Basis-Kleidungsfarbe sind kostenlos. Looks werden im Konto gespeichert und nur Match-Teilnehmern sowie bestätigten Freunden gezeigt. Im Kampf stehen die eigenen Trainer am Spielfeldrand.

Acht Kampagnengegner mit eigenen Looks. Spätere Gegner sagen Züge aus abgeschlossenen Runden voraus; die aktuelle Auswahl wird niemals gelesen. Seraphine: 14 Runden, mindestens 8 Siege. Veyr: 18 Runden, mindestens 11 Siege. Belohnungen steigen von 120 XP / 100 Coins bis 600 XP / 600 Coins bei Sieg. Verluste bringen XP, keine Match-Coins. Siege öffnen das nächste Kapitel.

17 Styles in fünf Slots: Kleidung, Kopfbedeckung, Aura, Rahmen und Karten-Designs. Anprobe verändert die Ausrüstung nicht. Preise, Besitz, Käufe und Kampagnenfortschritt sind serverseitig geprüft. Keine Echtgeldkäufe oder Kampfboni.

Mystery Packs: pro Levelaufstieg ein Sternenfund; drei kaufbare Packstufen für 150, 400 oder 900 erspielte Coins. Die im UI sichtbaren Chancen stimmen mit dem Server überein. Ein Pack enthält entweder nichts, Coins oder einen Style. Doppelte Styles werden mit einer Animation in 20% ihres Shoppreises als Coins umgewandelt. Anfragen mit gleicher ID erzeugen keine zweite Abbuchung oder Belohnung. Inventar zeigt Styles und Packs.

Match-Fläche und Auswahlkarten behalten ihre Position während Auswahl, Enthüllung und Ergebnis. Level, XP-Ring und Coins erscheinen im Account- und Match-Header. Die lokale Testseite `/__visual` ist nur im Entwicklungsmodus aktiv und aus dem Produktionsbuild entfernt.

30 Integrationstests: `npm test`. Build: `npm run build`.
