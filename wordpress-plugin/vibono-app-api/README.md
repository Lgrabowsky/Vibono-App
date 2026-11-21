# Vibono App API & Punkte (WordPress-Plugin)

Verbindet die App „Vibono“ mit vibono.de und stellt ein zentrales Punktesystem für App und Shop bereit.

- **Login** mit dem bestehenden Vibono-Konto (Token für die App, Registrierung mit Empfehlungscode, Passwort vergessen, Konto löschen)
- **Zwei-Wege-Synchronisation** von MyVibono-Daten: Lieblingsrezepte, erledigte Lektionen und Kurse, Gewicht, Sport, Wochenplan (ohne Uhrzeiten), Onboarding-Angaben und Wunschgewicht nach 3, 6 und 12 Monaten
- **Tagesübersicht** für den Startbildschirm: Phase und Tag im Coaching, Fortschritt, nächster Schritt, Essen/Bewegung/Wissen/Sonstiges, 3 Rezepte, Vibono-Tipp, Tipp des Tages
- **Vibono-Punkte**: tägliches Öffnen mit Serie (je mehr Tage in Folge, desto mehr Punkte; Stufen einstellbar), nachweislich gelesene Artikel (App und Website), Kundenwerbung, Einkäufe; Einlösen im WooCommerce-Shop; Umrechnungskurs und Aktionen im Backend
- **Energiedichte-Rechner**: Lebensmittelsuche, Rezept-Scan und Foto-Schätzung über die Claude API (Schlüssel nur auf dem Server)

API-Vertrag: [`docs/openapi.yaml`](docs/openapi.yaml) (Basis `https://www.vibono.de/wp-json/vibono/v1`).

**Anbindung an vibono.de, Module, Notfall und Entfernen: [docs/ANBINDUNG.md](docs/ANBINDUNG.md)**

Konzepte: [Punktesystem und Lese-Nachweis](docs/PUNKTESYSTEM.md) · [Umstellung von Refer a Friend](docs/MIGRATION-REFER-A-FRIEND.md) · [Keine In-App-Käufe / App-Store-Regeln](docs/APP-STORE.md)

## Installation

Voraussetzungen: WordPress ≥ 6.2, PHP ≥ 8.1, WooCommerce (für Shop-Punkte), WooCommerce Memberships (für den Paywall-Abgleich).

1. Im Plugin-Ordner `composer install --no-dev` ausführen (lädt das Anthropic PHP SDK für den Energiedichte-Rechner). Ohne diesen Schritt funktioniert alles außer Rezept-Scan und Foto-Schätzung.
2. Ordner `vibono-app-api` nach `wp-content/plugins/` kopieren und aktivieren. Die Datenbanktabellen werden angelegt.
3. In `wp-config.php` ergänzen:
   ```php
   define( 'VIBONO_JWT_SECRET', '…mindestens 32 zufällige Zeichen…' );
   define( 'VIBONO_ANTHROPIC_API_KEY', '…' ); // optional, für den Energiedichte-Rechner
   ```
4. Unbedingt zuerst auf einer **Staging-Kopie** testen.
5. Backend → **Vibono-Punkte → Module & Anbindung**: Systemprüfung ansehen. Nach der Aktivierung ist nur die App-Schnittstelle an; Shop, Freunde werben, Lesepunkte auf der Website und das Schreiben in MyVibono-Felder sind aus und werden schrittweise eingeschaltet (siehe [ANBINDUNG.md](docs/ANBINDUNG.md)).
6. Backend → **Vibono-Punkte → App-Schnittstelle**: Inhaltstypen, Kurs-Zuordnung zu den Phasen und MyVibono-Speicherorte prüfen (siehe „Annahmen“).
7. Backend → **Vibono-Punkte → Kurs & Regeln**: Punktwerte und Stufen der Serie fürs tägliche Öffnen festlegen. Start: 1 Punkt = 1 Cent.
8. Falls der Server den `Authorization`-Header nicht an PHP durchreicht (manche Apache-Setups), in `.htaccess` ergänzen:
   `SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=$1`

## Annahmen (Theme-Code von vibono.de liegt noch nicht vor)

Aus dem Quelltext von „Mein Coaching“ abgeleitet, im Backend änderbar:

| Annahme | Standard | Prüfen |
|---|---|---|
| Inhaltstypen | Lektionen `my_coaching`, Rezepte `rezepte`, Vibono-Tipps `post`, Tipp des Tages `apptipps`, Lebensmittel `energiedichte` | Post-Typen im Theme |
| Lektionsart (wichtig, lesen, aufgaben …) | unbekanntes Meta-Feld | Wo speichert das Theme `data-type`? |
| Kurse je Phase | leer | Kurs-IDs (z. B. 247, 248) den Phasen zuordnen |
| Speicherorte MyVibono (Favoriten, Gewicht, Sport, Wochenplan, Häkchen) | nur im Plugin | Nutzer-Meta-Schlüssel und Format aus `vibono-ajax.js`/Theme. Für andere Formate gibt es den Filter `vibono_api_myvibono_adapter` |
| Rezept-Zutaten und Portionen (Einkaufsliste) | automatisch: WP Recipe Maker, sonst Felder `zutaten`/`ingredients` und `portionen`/`servings` (ACF-Wiederholer oder Text, eine Zutat je Zeile) | Wo speichert vibono.de die Zutaten? Systemprüfung zeigt die Trefferquote. Für andere Formate gibt es den Filter `vibono_api_recipe_ingredients` |
| Rezept-Merkmale | Begriffe `vegetarisch`, `vegan`, `ut-geeignet`, `laktosefrei` … | Taxonomien der Rezepte |
| Bewegungstipps | Kategorie `bewegung` | |
| Startseite „Heute“ (`GET /home`) | Coaching-Briefe `coaching_briefe`, eBooks = Produktkategorie `ebooks`, Blog = `post` | Inhaltstyp der Coaching-Briefe und eBook-Kategorie prüfen. Challenges und eigene Meldungen (Club, Gruppe, Aktionen) im Backend unter „App: Challenges“ und „App: Meldungen“, Stichwörter und „Probier mal was aus mit …“ unter Vibono-Punkte → App-Schnittstelle. Quizfragen per Filter `vibono_api_quiz_questions` |
| Refer a Friend | Nutzer-Meta `gens_referral_id`, Parameter `raf` | siehe Migrationskonzept |

Solange die Speicherorte nicht eingetragen sind, speichert das Plugin App-Daten selbst; die Website sieht sie dann noch nicht. Sobald die Meta-Schlüssel eingetragen sind, werden bestehende Website-Daten beim nächsten Abgleich übernommen. In die Theme-Felder geschrieben wird erst, wenn „MyVibono-Daten auf die Website schreiben“ eingeschaltet ist; der alte Wert wird vorher gesichert.

## Entwicklung

```bash
composer install
composer test        # Unit-Tests der Rechenregeln (Token, Punkte, Aktionen, Serie, Lese-Nachweis, Sync, Coaching-Kalender)
```

WP-CLI: `wp vibono check`, `wp vibono migrate-raf --dry-run`, `wp vibono confirm-pending`, `wp vibono balance <email>`, `wp vibono export-points > punkte.csv`, `wp vibono reconcile-orders --dry-run`, `wp vibono restore-myvibono --dry-run`.

### Aufbau

```
includes/Core/      reine Logik ohne WordPress (getestet)
includes/Rest/      REST-Controller (ein Controller je Bereich)
includes/           Dienste: Auth, SyncStore, MyVibonoBridge, Points, Campaigns, Reading, Referral, WooCommerce, Content, Profile, Vision, Privacy, Health, Admin, Cli
assets/             reading-tracker.js (Lese-Nachweis auf der Website)
docs/               OpenAPI-Vertrag und Konzepte
uninstall.php       Aufräumen beim Löschen (Daten standardmäßig behalten)
```

### Datenbank

| Tabelle | Inhalt |
|---|---|
| `wp_vibono_tokens` | Refresh-Tokens (nur Hash) |
| `wp_vibono_sync` | Sync-Stand je Nutzer/Sammlung/Schlüssel, `seq` = Cursor |
| `wp_vibono_points_ledger` | Punkte-Hauptbuch |
| `wp_vibono_campaigns` | Aktionen |
| `wp_vibono_reading` | Lese-Sessions (werden nach 2 Tagen gelöscht) |
| `wp_vibono_devices` | Push-Tokens |
