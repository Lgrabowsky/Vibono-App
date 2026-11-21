# Anbindung an vibono.de: sicher einführen, sicher entfernen

Stand: November 2026. Gilt für das Plugin „Vibono App API & Punkte“ ab dieser Version.

## Kurzfassung

- Das Plugin ist **eigenständig**: eigene Tabellen (`wp_vibono_…`), eigene Einstellungen (`vibono_api_…`), eigene Meta-Felder (`_vibono_…`) und ein eigener Schnittstellen-Bereich `/wp-json/vibono/v1`. Es ändert keine Theme-Dateien, keine WooCommerce-Einstellungen, keine Preise, Inhalte, Bestellungen oder echten Gutscheine.
- Alles, was auf der Website sichtbar ist oder Daten anderer Systeme berührt, steckt in **Modulen, die nach der Installation ausgeschaltet sind**. Nach dem Aktivieren ändert sich auf vibono.de nichts, nur die App kann sich anmelden.
- **Fehlerschutz**: Jeder Eingriff des Plugins in WordPress und WooCommerce läuft durch einen Schutz. Ein Fehler im Plugin wird protokolliert, Seite, Warenkorb und Kasse laufen normal weiter.
- **Notabschaltung** ohne Backend: `define( 'VIBONO_API_DISABLE', true );` in `wp-config.php`.
- **Entfernen**: Deaktivieren stoppt alles sofort und hinterlässt keine aktiven Spuren. Löschen behält standardmäßig die Punktestände (Guthaben der Kund*innen), auf Wunsch wird alles entfernt.

## 1. Voraussetzungen

| Was | Warum |
|---|---|
| WordPress ≥ 6.2, PHP ≥ 8.1 | WordPress verhindert die Aktivierung bei älteren Versionen |
| HTTPS und sprechende Permalinks | Die App spricht `https://www.vibono.de/wp-json/vibono/v1` an |
| WooCommerce | nur für die Module „Punkte im Shop“, „Freunde werben“ und die Prämie „Rabatt auf die Verlängerung“ |
| WooCommerce Memberships | Prüfung, welche Coaching-Inhalte freigeschaltet sind |
| Zugang zu `wp-config.php` (SFTP/SSH), ideal WP-CLI | Schlüssel eintragen, Befehle `wp vibono …` |
| Staging-Kopie von vibono.de | **Alles zuerst dort testen** |

## 2. Installation (zuerst auf der Staging-Kopie)

1. **Plugin-Ordner vorbereiten**: Im Ordner `vibono-app-api` einmal `composer install --no-dev` ausführen (lädt das SDK für die Bildauswertung), dann den Ordner nach `wp-content/plugins/` hochladen oder als ZIP über „Plugins → Installieren → Hochladen“ einspielen.
2. **Schlüssel in `wp-config.php`** (nicht ins Repository, nicht in Chats):
   ```php
   define( 'VIBONO_JWT_SECRET', '…' );          // z. B. mit "openssl rand -hex 32" erzeugen
   define( 'VIBONO_ANTHROPIC_API_KEY', '…' );   // optional, nur für Rezept-Scan und Foto
   ```
3. **Aktivieren.** Dabei passiert genau das: 6 Tabellen anlegen, Einstellungen mit sicheren Standardwerten anlegen, einen stündlichen Cron-Job planen. Sonst nichts.
4. **Systemprüfung** ansehen: Backend → **Vibono-Punkte → Module & Anbindung** (oder `wp vibono check`). Rote Punkte zuerst beheben.
5. **App-Login testen** (mit einem Testkonto):
   ```bash
   curl -s -X POST https://staging.vibono.de/wp-json/vibono/v1/auth/login \
     -H 'Content-Type: application/json' -d '{"username":"test@…","password":"…"}'
   curl -s https://staging.vibono.de/wp-json/vibono/v1/me -H "Authorization: Bearer <access_token>"
   ```
   Liefert der zweite Aufruf `401`, reicht der Server den `Authorization`-Header nicht an PHP weiter. Bei Apache in `.htaccess` ergänzen: `SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=$1`
6. **Sicherheits- und Cache-Plugins** prüfen: `/wp-json/vibono/` darf nicht gecacht werden und muss ohne Website-Login erreichbar sein (Login, Registrierung, Konfiguration). Plugins, die die REST-API für Gäste sperren, brauchen dafür eine Ausnahme. Die Antworten des Plugins tragen bereits `Cache-Control: no-store` (nur `/config` darf 5 Minuten zwischengespeichert werden).

## 3. Schrittweise einschalten

Jede Stufe einzeln einschalten, auf Staging prüfen, dann auf vibono.de wiederholen. Zwischen den Stufen auf der Live-Seite ein paar Tage beobachten (Systemprüfung → „Abgefangene Fehler“).

| Stufe | Schalter | Was sich auf der Website ändert | So prüfen |
|---|---|---|---|
| 1 | **App-Schnittstelle** (nach Aktivierung an) | Nichts. MyVibono-Felder des Themes werden nur gelesen. | App-Login, Tagesübersicht, Favoriten aus der Website erscheinen in der App |
| 2 | Tab **App-Schnittstelle**: Inhaltstypen, Kurse je Phase, MyVibono-Speicherorte | Nichts | Braucht den Theme-Code (`wp-content/themes/vibono`). Werte stehen in der README unter „Annahmen“ |
| 3 | **MyVibono-Daten auf die Website schreiben** | App-Änderungen erscheinen in MyVibono | Testkonto: Favorit in der App setzen → auf der Website sichtbar und MyVibono funktioniert normal. Der alte Wert wird vorher automatisch gesichert |
| 4 | **Punkte im Shop** | Reiter „Vibono-Punkte“ in Mein Konto. Punkte für Einkäufe und Guthaben an der Kasse sind seit 21.11.2026 zusätzlich einzeln abgeschaltet (Kurs & Regeln → „Früher: Einkäufe und Guthaben an der Kasse“) | Mein Konto → Vibono-Punkte zeigt Kontostand und Verlauf. Nur falls Kasse wieder an: Punkte einlösen, bestellen, stornieren → Punkte zurück |
| 4a | **Prämien** | Reiter „Vibono-Punkte“ in Mein Konto mit „Punkte einlösen“. Beiträge, die als exklusive Prämie angelegt sind, zeigen nur noch einen Anriss mit Einlöse-Kasten. Gutscheine `VP-…` für die Verlängerung | Erst Prämien unter **Vibono-Punkte → Prämien** anlegen (dabei noch aus), dann einschalten. Testkonto: Prämie einlösen, Beitrag lesen, PDF laden, Gutschein im Warenkorb des Verlängerungs-Produkts |
| 5 | **Lesepunkte auf der Website** | Kleines Skript auf belohnten Beitragsseiten, nur für eingeloggte Nutzer*innen | Artikel lesen → Hinweis „+10 Punkte“ |
| 6 | **Freunde werben** | Empfehlungslinks `?vref=…` setzen ein Cookie | Erst nach der Übernahme aus Refer a Friend (siehe `MIGRATION-REFER-A-FRIEND.md`): `wp vibono migrate-raf --dry-run`, dann ohne `--dry-run`, Refer a Friend deaktivieren, Modul einschalten |

Die App liest über `GET /config` → `features`, welche Module an sind, und blendet ausgeschaltete Funktionen aus.

## 4. Alle Berührungspunkte mit dem bestehenden System

| Bereich | Wann | Was das Plugin tut | Was es nicht tut |
|---|---|---|---|
| Datenbank | immer | 6 eigene Tabellen mit Präfix `vibono_` | Keine Änderungen an WordPress- oder WooCommerce-Tabellen |
| Einstellungen | immer | `vibono_api_settings`, `vibono_api_jwt_secret` (nur ohne Konstante), `vibono_api_db_version`, `vibono_api_removed`, `vibono_points_rate_log` | Keine fremden Einstellungen |
| Nutzerkonten | App-Schnittstelle | Eigene Meta-Felder `_vibono_…` (Profil, Ziele, Einwilligung, Empfehlungscode, Token-Version). Registrierung in der App legt ein normales WooCommerce-Kundenkonto an (inkl. der üblichen Willkommens-Mail von WooCommerce). Vorname aus dem App-Profil wird ins Konto übernommen | Keine Rollen- oder Rechteänderungen, keine Admin-Logins über die App |
| Website-Login | App-Schnittstelle | App-Token gelten nur für `/wp-json/vibono/v1`. „Im Browser öffnen“ aus der App nutzt einen Einmal-Link `?vibono_login=…` (2 Minuten gültig, nie für Konten mit Admin-Rechten). Passwort ändern auf der Website meldet die App ab | Website-Login, Cookies und andere REST-Bereiche bleiben unverändert |
| MyVibono-Felder des Themes | nur wenn Speicherort eingetragen | Lesen; schreiben nur mit Schalter „MyVibono-Daten auf die Website schreiben“; vorher einmalige Sicherung in `_vibono_bak_<feld>`; Speicherformat (Array, JSON, Komma-Liste) bleibt | Keine Theme-Dateien, keine anderen Felder |
| Beiträge | Lesepunkte | Meta `_vibono_quiz` (nur wenn die Redaktion eine Quizfrage pflegt), `_vibono_word_count` (Zwischenspeicher). Box „Quizfrage“ im Editor | Inhalte und Änderungsdatum bleiben unverändert |
| Bestellungen | Punkte im Shop / Freunde werben | Meta `_vibono_points_redeemed`, `_vibono_points_value_cents`, `_vibono_referrer`. Eingelöste Punkte erscheinen als Gutschein-Zeile „vibono-punkte“ | Keine Änderung an Preisen, Steuern, Status, Zahlungen oder E-Mails. Kein erneutes Speichern der ganzen Bestellung |
| Gutscheine | Punkte im Shop (Kasse), Prämien | Virtueller Gutschein „vibono-punkte“, existiert nur im Warenkorb. Prämie „Rabatt auf die Verlängerung“: echter, persönlicher Einmal-Gutschein `VP-…` (an E-Mail und Produkte gebunden, mit Ablaufdatum) | Legt sonst keine echten Gutscheine an. Ausnahme auf ausdrücklichen Befehl: `wp vibono migrate-raf --coupon-meta=…` beendet alte Refer-a-Friend-Gutscheine und merkt sich das alte Ablaufdatum |
| Shop-Seiten | Punkte im Shop | Hinweis am Produkt, Einlösefeld im klassischen Warenkorb, Info-Zeile an der Kasse (ohne eigenes Formular), Reiter in Mein Konto | Löscht keine Shop-Hinweise anderer Plugins, verschachtelt keine Formulare |
| Beiträge (exklusiv) | Prämien | Beiträge, die in einer Inhalts-Prämie hinterlegt sind, zeigen ohne Freischaltung nur Anriss und Einlöse-Kasten (Seite, WP-REST, Feed). Tabellen `vibono_rewards`, `vibono_reward_unlocks` | Ändert keine Beiträge, Rechte oder Mitgliedschaften. Andere Beiträge bleiben unberührt |
| Cookies | Freunde werben | `vibono_ref` (30 Tage), nur nach Klick auf einen Empfehlungslink | Im Cookie-Banner und in der Datenschutzerklärung ergänzen, wie bisher beim Cookie von Refer a Friend |
| Refer a Friend | Freunde werben | Wertet auch alte `?raf=`-Links aus und übernimmt alte Codes (`wp vibono migrate-raf`). Läuft Refer a Friend noch, warnt die Systemprüfung: dort Belohnungen abschalten | Ändert nichts an Refer a Friend selbst |
| Cron | immer | `vibono_points_daily`, stündlich: vorgemerkte Punkte bestätigen, alte Lese-Sessions löschen | |
| Datenschutz-Werkzeuge | immer | Export und Löschung unter Werkzeuge → Personenbezogene Daten. Wird ein Konto gelöscht, werden die Vibono-Daten mitgelöscht | |
| Externe Dienste | nur Rezept-Scan/Foto | Bild geht an die Claude API von Anthropic (Datenschutzerklärung und Auftragsverarbeitung prüfen) | Kein Laden externer Skripte auf der Website |
| Bibliotheken (`vendor/`) | nur Rezept-Scan/Foto | Werden nur in diesen Anfragen geladen | Können beim normalen Seitenaufbau nicht mit Bibliotheken anderer Plugins kollidieren |

## 5. Schutzmechanismen im Code

- **Module mit sicheren Standardwerten** (`Settings::defaults()`): Shop, Werben, Lesepunkte, Prämien, Schreiben ins Theme und Datenlöschung sind aus. Punkte für Einkäufe und Guthaben an der Kasse sind auch bei eingeschaltetem Shop aus.
- **Prämien**: Einlösen unter Sperre je Konto, Rückbuchung bei Fehler. Exklusive Beiträge sind nur gesperrt, solange das Modul an ist; ausschalten macht sie wieder normal sichtbar.
- **Fehlerschutz** (`Plugin::hook()`): Alle Hooks laufen in `try/catch`. Ein Fehler landet im PHP-Fehlerlog und in der Systemprüfung, Filter geben den unveränderten Wert zurück.
- **Shop**: Der Punkte-Gutschein wird leise angemeldet (keine „Gutschein angewendet“-Meldung, keine gelöschten fremden Hinweise). Ist die Einlösung nicht mehr gedeckt oder liegt ein Gutschein „nur allein gültig“ im Warenkorb, wird sie still zurückgenommen. Abbuchung und Rückbuchung sind je Bestellung nur einmal möglich, zurückgebucht wird nur, was wirklich abgebucht wurde.
- **Buchhaltung läuft immer**: Stornos und abgeschlossene Bestellungen werden auch bei ausgeschalteten Modulen korrekt verbucht.
- **MyVibono**: standardmäßig nur lesen, Sicherung vor dem ersten Schreiben, Rückbau per `wp vibono restore-myvibono`.
- **Datenschutz**: Export, Löschung und Aufräumen beim Löschen eines Kontos.

## 6. Notfall

1. **Einzelnes Modul ausschalten**: Backend → Vibono-Punkte → Module & Anbindung. Wirkt sofort.
2. **Kein Backend erreichbar**: `define( 'VIBONO_API_DISABLE', true );` in `wp-config.php`, oder den Ordner `wp-content/plugins/vibono-app-api` per SFTP umbenennen (WordPress deaktiviert das Plugin dann selbst).
3. **MyVibono-Felder zurücksetzen** (nur wenn das angenommene Format falsch war): `wp vibono restore-myvibono --dry-run`, danach ohne `--dry-run`. Achtung: Änderungen in diesen Feldern seit dem ersten Schreiben gehen verloren.
4. **Nach einer Abschaltung** Bestellungen nachbuchen, deren Status sich in der Zeit geändert hat: `wp vibono reconcile-orders --days=60` (erst mit `--dry-run`).
5. **Fehler ansehen**: Systemprüfung „Abgefangene Fehler“ und das PHP-Fehlerlog (Einträge beginnen mit „Vibono App API“).

## 7. Entfernen

### Deaktivieren (Plugins → Deaktivieren)

| Was | Danach |
|---|---|
| App | Kann sich nicht mehr verbinden (die App zeigt dann ihre Fehlermeldung). Nach erneutem Aktivieren geht es mit denselben Zugängen weiter |
| Shop | Einlösefeld, Produkthinweis und Reiter „Vibono-Punkte“ verschwinden. Hat jemand gerade Punkte im Warenkorb, entfernt WooCommerce den Gutschein beim nächsten Seitenaufruf mit einem kurzen Hinweis; die Person zahlt den normalen Preis, abgebucht wurde nichts |
| Bestellungen | Bleiben vollständig, inklusive der Gutschein-Zeile „vibono-punkte“ als korrekter Beleg |
| Empfehlungslinks | `?vref=…` wird ignoriert, die Seite lädt normal. Das Cookie läuft von selbst ab |
| MyVibono | Die Website zeigt weiter den zuletzt gespeicherten Stand |
| Cron, Permalinks | Cron-Job entfernt, Permalink-Regeln werden ohne den Reiter neu aufgebaut |
| Daten | Bleiben erhalten. Erneutes Aktivieren macht nahtlos weiter (danach `wp vibono reconcile-orders`) |

### Löschen (Plugins → Löschen)

- **Standard: Daten behalten.** Tabellen und Punktestände bleiben, weil sie Guthaben der Kund*innen sind. Nur Cron-Job, Permalink-Zwischenspeicher und kurzlebige Zwischenspeicher werden entfernt.
- **Alles entfernen**: vorher unter Module & Anbindung „Beim Löschen des Plugins alle Daten entfernen“ einschalten. Dann werden Tabellen, Einstellungen, Vibono-Meta-Felder an Konten, Quizfragen und Wortzahlen gelöscht.
- **Nie gelöscht**: Bestellungen und deren Vibono-Meta (Buchhaltung), Nutzerkonten, Inhalte und die MyVibono-Felder des Themes.
- **Vorher sichern**: `wp vibono export-points > punkte.csv` (Konto, E-Mail, Punkte, vorgemerkt, Gegenwert in Euro). Kund*innen rechtzeitig informieren, bevor Punkte verfallen.

### Danach prüfen

Startseite, ein Produkt, Warenkorb, Kasse und Mein Konto aufrufen. Optional Einstellungen → Permalinks → Speichern.

## 8. Noch offen für die Anbindung

- Theme-Code `wp-content/themes/vibono` für die MyVibono-Speicherorte, die Lektionsart und die Kurse je Phase.
- Wo die Rezept-Zutaten und Portionen gespeichert sind (für die Einkaufsliste der App). Das Plugin liest sie nur.
- Nutzt vibono.de den klassischen Warenkorb oder den Block-Warenkorb? Das Einlösefeld erscheint im klassischen Warenkorb (`[woocommerce_cart]`). Für den Block-Warenkorb wäre eine Erweiterung nötig.
- Liste der aktiven Sicherheits- und Cache-Plugins (Ausnahme für `/wp-json/vibono/`).
- Cookie-Banner und Datenschutzerklärung (Cookie `vibono_ref`, App, Bildauswertung).
