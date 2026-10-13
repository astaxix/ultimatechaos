# ULTIMATE CHAOS · Göttliche Eskalation

Ein Browsergame für private Freundesduelle: Konto erstellen/anmelden → Profilbild wählen → Home mit Level, XP, Coins, Freunden und Shop → Raum erstellen, Raum beitreten oder Freund herausfordern.

Ein Duell hat **genau zehn Runden**. In jeder Runde bleiben **fünf Sekunden zum Auswählen**. Kartenklick speichert sofort; Änderungen sind bis zum serverseitigen Zeitlimit erlaubt. Danach werden die letzten gespeicherten Figuren gleichzeitig enthüllt und kämpfen mit Animationen. Nach sechs Sekunden Kampf/Ergebnis beginnt automatisch die nächste Runde. Unentschieden zählen als Runde, bringen aber keinen Punkt. Ohne Auswahl verliert man die Runde; fehlen beide Auswahlen, erhält niemand einen Punkt. Nach zehn Runden gewinnt der höhere Punktestand, Gleichstand ist ein Match-Unentschieden. Rematch erst nach Zustimmung beider Spieler.

Das Profilbild ist rein kosmetisch. Es legt die Figur im Duell **nicht** fest. Figurenauswahl gibt es nur im Match. Alle sieben Figuren bleiben frei verfügbar; kein Pay-to-win, keine Bots und kein öffentliches Matchmaking.

## Verifizierter Stand

- TypeScript und Produktionsbuild erfolgreich.
- **17 PostgreSQL-Integrationstests** mit PGlite/WASM bestehen: 21 Figurenpaarungen, sieben Unentschieden, 5-Sekunden-Frist, Änderbarkeit/Geheimhaltung, späte Anfragen, automatische zehn Runden, Rematch, Identität, Profil, Freundesanfragen, Herausforderungen, reservierte Räume, Coins, Inventar, serverseitige Preise, Belohnungen und RLS.
- Die lokalen Tests simulieren die Supabase-Auth-Benutzertabelle. Sie testen die echte SQL-Spiellogik, **nicht** Supabase-E-Mailzustellung oder den kompletten Auth-Dienst.
- Die lokale Build-Konfiguration verwendet das Supabase-Projekt `pzfqjfcmvzddvtcmlbbn`. Auth-Settings antworteten erfolgreich (E-Mail aktiv, Bestätigung erforderlich); die Spiel-RPC `chaos_social` fehlt noch (PGRST202). Migrationen und Online-Duelle sind **noch nicht live getestet**. Vercel verweigerte die neue Projektanlage mit 403.
- Die bei fehlender Servereinrichtung verfügbare Home-Vorschau benutzt ein ausdrücklich gekennzeichnetes Beispielprofil. Sie simuliert keine echte Anmeldung oder Servertransaktionen.
- Automatisierte Browserprüfung war in dieser Umgebung nicht verfügbar. Mobile-/Desktop-Ansicht, Fokus, Passwort-Recovery, Sound und Animationen brauchen noch Browser-Abnahme.

## Installation

Node.js 22 oder 24 verwenden:

```bash
npm ci
cp .env.example .env
```

In `.env` setzen:

```dotenv
VITE_SUPABASE_URL=https://DEIN-PROJEKT.supabase.co
VITE_SUPABASE_ANON_KEY=DEIN-OEFFENTLICHER-ANON-ODER-PUBLISHABLE-KEY
```

**Keinen Service-Role-/Secret-Key im Frontend verwenden.** VITE-Variablen sind im Browser sichtbar. Passwörter werden an Supabase Auth übergeben; die App speichert sie nicht selbst.

## Supabase einrichten

1. Projekt erstellen, vorzugsweise EU-Region.
2. Unter Authentication den **E-Mail-/Passwort-Provider** aktivieren und die E-Mailbestätigung einschalten. Anonyme Anmeldungen werden nicht mehr benutzt und können deaktiviert werden.
3. Die veröffentlichte App-URL als **Site URL** und als erlaubte Redirect-URL für Bestätigung und Passwort-Recovery hinterlegen. Lokale URL bei Bedarf separat erlauben.
4. SMTP für E-Mailzustellung konfigurieren und Bestätigungs-/Recovery-Flows prüfen. Auth-Limits nach Bedarf einstellen.
5. SQL-Migrationen in dieser Reihenfolge ausführen:
   - `001_game.sql`: Grundspiel und geheime Züge
   - `003_timed_rounds.sql`: Zeitlimit und genau zehn Runden
   - `004_accounts_social.sql`: Konten, Profile, Freunde, Shop und Belohnungen
   - `002_cleanup.sql`: Cleanup; vorher `pg_cron` in Database → Extensions aktivieren
6. Für vorhandene Projekte nur **noch nicht ausgeführte** Migrationen ausführen. Migration 003 setzt vorhandene laufende Spiele in die Lobby zurück. Migration 004 verlangt künftig bestätigte Konten mit Profilen.
7. `chaos_private` niemals als Data-API-Schema exponieren. Nur Räume, Freundesanfragen und Herausforderungen werden für Realtime veröffentlicht; geheime Züge und Inventar bleiben privat.

## Lokal starten

```bash
npm run dev
npm test
npm run build
```

## Vercel

Als Vite-Projekt importieren: Install `npm ci`, Build `npm run build`, Output `dist`, Node 22 oder 24. Beide `VITE_SUPABASE_*`-Variablen für die gewünschten Umgebungen setzen und neu deployen. `vercel.json` enthält das Rewrite für direkte `/room/ABC123`-Links.

Vercel konnte in der Erstellungssitzung wegen fehlender Kontoberechtigung (403) kein neues Projekt anlegen. Die ausgelieferte Konfiguration ist für die Veröffentlichung vorbereitet. Die hier bereitgestellte Gestaltungsvorschau ist privat.

## Konto, Freunde und Shop

- Registrierung per E-Mail und Passwort, Anmeldung, Passwort-Reset/Recovery, Abmeldung und bestehende Sitzungen.
- Nach Anmeldung mit neuem Konto: Spielername und eines von sieben eigenen Avatar-Motiven auswählen. Danach Home.
- Einmalig **250 Start-Coins**, Level 1. Namens-/Avataränderungen geben keine erneuten Start-Coins.
- Level = `floor(XP / 250) + 1`. XP und Coins sind serverseitig geschützt.
- Freund hinzufügen mit achtstelligem Freundescode. Empfänger bestätigt die Anfrage. Anfragen werden dedupliziert; fremde Anfragen sind nicht lesbar.
- Nur bestätigte Freunde können direkt herausgefordert werden. Die Herausforderung erstellt eine echte Lobby und reserviert den zweiten Platz für diesen Freund. Einladungen laufen nach zehn Minuten ab. Annahme führt in die gemeinsame Lobby.
- Shop: Arkaner Kreis (150 Coins), Goldene Krone (350), Himmlische Aura (700). Ausschließlich kosmetische Profilrahmen. Preis, Kontostand, Besitz und Ausrüsten werden auf dem Server geprüft. Eine Kaufbestätigung zeigt den konkreten Preis.
- Wer in **allen zehn Runden aktiv gewählt hat**, bekommt nach dem Match genau einmal: Sieg 100 Coins/120 XP, Unentschieden 60/80, Niederlage 40/60. Inaktive Teilnehmer erhalten keine Matchbelohnung. Volle private Freundesduelle können wiederholt gespielt werden; kein Ranked-/Anti-Collusion-System.

## Echte Online-Abnahme

Drei bestätigte Testkonten in Supabase erstellen. Ihre Zugangsdaten ausschließlich lokal in `.env` setzen (nicht teilen/committen):

```dotenv
TEST_EMAIL_1=...
TEST_PASSWORD_1=...
TEST_EMAIL_2=...
TEST_PASSWORD_2=...
TEST_EMAIL_3=...
TEST_PASSWORD_3=...
```

```bash
npm run test:online
```

Der Test meldet die Konten getrennt an, legt bei Bedarf Profile an und erstellt einen temporären Raum. Er prüft tatsächliche API-/Realtime-Geheimhaltung, Änderbarkeit, 21 Paarungen, sieben Unentschieden, Timeouts, automatische Runden, zwei Rematches, RLS und Token-Erneuerung. Dauer etwa sechs Minuten; Raum wird abschließend gelöscht. Konten/Profile bleiben bestehen. Erspielte Belohnungen bleiben auf den Testkonten.

Zusätzliche manuelle Abnahme:

1. Registrierung, Bestätigungs-E-Mail, Login, Abmeldung, falsches Passwort, Passwort-Recovery prüfen.
2. Erst Avatar wählen, dann Home. Profilbildwechsel darf die Duellfigur nicht festlegen.
3. Zwei Konten auf PC/Handy: Freundesanfrage senden, annehmen, Herausforderung senden und annehmen.
4. Raum zusätzlich über Code/Link erstellen und beitreten. Ein drittes Konto darf weder geheime Züge lesen noch einen reservierten Platz belegen.
5. Pro Runde fünf Sekunden: Wahl ändern, keine frühe Enthüllung, zuletzt gespeicherte Wahl verwenden. Gleichzeitige Animationen und identische Ergebnisse prüfen.
6. Genau zehn Runden, automatischer Wechsel, verpasste Auswahl und Gleichstand prüfen. Rematch setzt Punkte/Runden zurück.
7. Wiederverbindung/Reload/Tab-Hintergrund vor und nach Timerende prüfen; Frist darf nicht neu anfangen. Verpasste Runden werden serverseitig abgeschlossen.
8. Coins/XP nach aktiven Matches genau einmal; Shopkäufe, fehlende Coins, bereits gekaufter Artikel und Ausrüsten prüfen.
9. iPhone/Android/Tablet/Desktop, Hoch-/Querformat, Safe Areas, Touch, Tastatur-/Modalfokus, Sound und reduzierte Animationen abnehmen.

## Sicherheitsmodell

`chaos_action` prüft bestätigte registrierte Konten und abgeschlossene Profile. Es verwendet den serverseitigen Profilnamen; ein Client kann keinen fremden Namen erzwingen. Der getestete Spielkern läuft in `chaos_private.play` und ist nicht direkt öffentlich aufrufbar. Der Raum wird vor jeder Aktion mit `FOR UPDATE` gesperrt. Die Spielzeit wird nach der Sperre mit `clock_timestamp()` geprüft.

`chaos_private.moves` ist vom Data API getrennt. Bis zur Frist sind Figurenfelder in `chaos_rooms` NULL. Nur der eigene Zug wird über RPC zurückgegeben. Erst nach Ablauf werden beide Figuren und die autorisierte Auswertung atomar veröffentlicht. Zeitbasierte Übergänge passieren auf autorisierten Zustand-/Heartbeat-Aufrufen. Ohne aktive Clients pausiert die Darstellung; beim Wiederverbinden wird die überfällige Runde aufgelöst und die nächste Auswahl erhält eine frische Fünf-Sekunden-Frist.

RLS gewährt nur Mitgliedern Raumzugriff. Profile sind direkt nur vom Besitzer lesbar; Freunde bekommen über RPC nur die benötigten Profildaten, keine E-Mail oder Passwörter. Mutationen laufen über Funktionen mit leerem `search_path` und vollständig qualifizierten Tabellen. Direkte Updates auf Profilen, Scores, Coins, XP, Freundschaft und Challenges sind gesperrt.

Shopkäufe sperren das eigene Profil, bestimmen den Preis serverseitig und schreiben Inventar/Coin-Abzug in einer Transaktion. Der Match-Trigger schreibt Belohnungen mit einem Unique Constraint, sodass Realtime, Polling und Rematches keine doppelten Coins erzeugen. Inaktive Räume werden nach 24 Stunden gelöscht, Cleanup alle 15 Minuten.

## Eigene Grafiken

`public/art/fighters-atlas.webp`: eigenes generiertes 4×2-Atlas mit Schere, Stein, Papier, Brunnen, Michael, Colt, Bombe und Coins. `public/art/celestial-arena.webp`: eigene Fantasy-Arena. Alle Grafiken werden lokal ausgeliefert, keine externen Medien-/Font-CDNs. Profilrahmen, Logo-Emblem und Kampfeffekte sind eigene SVG-/CSS-Grafiken. Details und Bildprompts: `ARTWORK.md`.

## Mobile-Anpassung

Die Profilnavigation sitzt auf Smartphones am unteren Bildschirmrand. Safe Areas, Touch-Ziele ab 44 px und Formularschrift mit 16 px vermeiden kleine Trefferflächen und iPhone-Autozoom. Die Auswahlphase zeigt einen kompakten Timer und sieben Karten in zwei Reihen. Im Querformat stehen Timer/Arena neben der Kartenwahl. Reduzierte Animationen und Stummschaltung bleiben verfügbar. Eine echte Geräteprüfung steht noch aus.

## Dieses Supabase-Projekt aktivieren

Der öffentliche Projektkey steht in der lokal vorbereiteten `.env.local`; diese Datei ist von Git ausgeschlossen. Er ist kein Datenbank-Administratorzugang. Die bereitgestellte Datenbank-URL enthält lediglich `[YOUR-PASSWORD]` und kann nicht zur Anmeldung verwendet werden.

Für ein **frisches** Projekt kann `supabase/setup-fresh.sql` im Supabase SQL Editor ausgeführt werden. Die Datei führt alle vier Migrationen in einer Transaktion aus und bricht ab, wenn das Spiel bereits eingerichtet ist. Bei vorhandenen Spieltabellen nur die fehlenden Einzelmigrationen anwenden. Anschließend Site URL und Redirect URLs auf die endgültige Deployment-URL setzen und die echte Online-Abnahme durchführen.

Die sichere Dashboard-Anmeldung wurde gestartet; Supabase verlangt aktuell eine CAPTCHA-Prüfung. Es wurden noch keine SQL-Migrationen im Projekt ausgeführt.
