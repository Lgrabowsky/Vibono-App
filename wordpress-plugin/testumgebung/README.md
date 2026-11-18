# Vibono-Testumgebung

Lokale Sandbox, um das Plugin [`vibono-app-api`](../vibono-app-api/) mit allen Funktionen auszuprobieren, ohne vibono.de anzufassen. Für Windows als ZIP zum Entpacken und Doppelklicken; Anleitung für Anwender: [`dateien/LIESMICH.txt`](dateien/LIESMICH.txt).

Getestet wird **der echte Plugin-Code** in einem echten WordPress (7.1.4) mit WooCommerce (11.3.0). Statt MySQL dient eine SQLite-Datei ([SQLite Database Integration](https://github.com/WordPress/sqlite-database-integration)), als Webserver der eingebaute PHP-Server (PHP 8.3 für Windows liegt bei). Es gibt nichts zu installieren.

## Was die Sandbox ergänzt

Nur in `mu-plugin/` und nur aktiv, wenn `wp-config.php` die Konstante `VIBONO_TESTUMGEBUNG` setzt. Am Plugin selbst ist nichts verändert.

| Datei | Zweck |
|---|---|
| `inhaltstypen.php` | Inhaltstypen, die auf vibono.de das Theme liefert: `my_coaching` (Taxonomie `kurs`), `rezepte` (`rezeptmerkmal`), `apptipps`, `energiedichte` |
| `mitgliedschaften.php` | Ersatz für WooCommerce Memberships (kostenpflichtig): genau die Funktionen, die `includes/Membership.php` aufruft. Mitglied = Nutzer-Meta `_vt_mitglied`, gesperrter Inhalt = Beitrags-Meta `_vt_nur_mitglieder` |
| `umgebung.php` | Demo-Serien beim ersten Aufruf auf das heutige Datum nachziehen (die Datenbank entsteht beim Bauen), E-Mails abfangen (Testzentrale → E-Mails), keine Verbindungen nach außen außer `api.anthropic.com`, `shop_url`/`support_url`/`privacy_url` auf die lokale Seite, Hinweise im Backend, stündliche Plugin-Aufgabe ohne WP-Cron, Beispielantwort für Foto/Rezept-Scan ohne Claude-Schlüssel |
| `helfer.php` | Testhelfer unter `/wp-json/vibono-test/v1/`: Bestellungen anlegen und Status ändern (über WooCommerce, die Punkte bucht das Plugin über seine Hooks), Widerrufsfrist überspringen, einen Tag vorspulen (verschiebt auch den letzten Tag der Serie), Serie fürs Öffnen setzen, Mitgliedschaft umschalten, Aktionen (über `Campaigns::save`) |
| `testzentrale/` | Oberfläche unter `/testzentrale/`. Ruft `/wp-json/vibono/v1/` wie die App auf (Login mit Token, `credentials: omit`), zeigt jede Antwort und protokolliert alle Anfragen |

Demodaten (`demodaten.php`): 9 Lektionen in 4 Kursen (ab Phase 2 nur für Mitglieder, zwei mit Quizfrage), 8 Rezepte mit Zutaten und Portionen, 5 Vibono-Tipps, 7 Tipps des Tages, 30 Lebensmittel, 4 Produkte, Konten Anna (Mitglied, Tag 5, Punkteverlauf, 6 Tage Serie bis gestern), Ben (von Anna geworben, erste Bestellung offen), Clara (neu), zwei Aktionen. Alle Module sind eingeschaltet.

## Bauen

```bash
./build.sh            # → dist/Vibono-Test.zip (ca. 90 MB)
```

Benötigt `php` (≥ 8.1 mit pdo_sqlite), `composer`, `git`, `curl`, `zip`. Lädt PHP für Windows, WordPress, WooCommerce und den SQLite-Treiber (Cache in `.cache/`), installiert alles mit dem PHP des Build-Rechners und legt die fertige Datenbank als `system/grundzustand.sqlite` bei (für `Zuruecksetzen.bat`). Nach Änderungen am Plugin einfach neu bauen.

Unter Linux/macOS lässt sich das Ergebnis direkt starten:

```bash
cd dist/Vibono-Test/system && php -S 127.0.0.1:8080 -t wp router.php
```

## Selbsttest

```bash
python3 selbsttest.py http://localhost:8080   # gegen eine frisch gebaute bzw. zurückgesetzte Umgebung, ca. 2,5 Minuten
```

Prüft über die Schnittstelle: Login/Refresh/Logout, App-Öffnen inkl. Tageslimit, Serie (Stufen, Schutztag, Abreißen mit „eine Stufe zurück“), Aktionen (Verdienen und Einlösen), Paywall, Inhalte und Filter, Zutaten, Coaching-Tag, Profil inkl. Validierung, Sync (Konflikte, Cursor), Freunde werben (Mindestwert, nur erste Bestellung, Selbstwerbung per Adresse, Storno), Einkaufspunkte (Frist ab „abgeschlossen“, Storno), Lese-Nachweis (zu früh, nicht gescrollt, doppelt, Quiz falsch/richtig), Energiedichte, Passwort-Mail, Kontolöschung, Token-Schutz.

Zusätzlich im Browser geprüft (Playwright): Punkte im klassischen Warenkorb einlösen und mit Nachnahme bestellen, Lesepunkte auf der Website über `reading-tracker.js`, Module im Backend aus- und einschalten, alle Bereiche der Testzentrale.

## Beobachtung für die Entwicklung

Empfehlungspunkte (`referral`, `referral_friend`) bekommen beim Bezahlen eine Frist von `pending_days` ab Zahlung. Einkaufspunkte warten dagegen auf „abgeschlossen“. Wird eine Bestellung erst nach Ablauf der 14 Tage storniert, sind die Empfehlungspunkte schon bestätigt (und werden dann per `void_ref` nachträglich storniert, auch wenn sie inzwischen eingelöst wurden). Der Selbsttest gibt das als Hinweis aus.
