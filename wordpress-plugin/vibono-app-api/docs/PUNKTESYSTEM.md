# Vibono-Punkte: Konzept

Ein zentrales Punktekonto pro Vibono-Konto, das in der App und im Shop auf vibono.de gleich funktioniert. Technisch ist es ein Hauptbuch (Tabelle `wp_vibono_points_ledger`) im WordPress-Plugin `vibono-app-api`. App und Shop lesen und schreiben nur über dieses Plugin.

## Punkte verdienen

Festgelegt von Vibono am 21.11.2026: Punkte gibt es für **Coaching-Fortschritt, Neukunden werben, die App-öffnen-Serie und komplett gelesene Artikel**. Einkäufe bringen keine Punkte mehr (siehe „Früher: Einkäufe und Guthaben an der Kasse“).

| Anlass | Startwert (Vorschlag) | Regeln |
|---|---|---|
| App täglich öffnen (Serie) | 5 bis 12 je Tag | einmal pro Kalendertag (Europe/Berlin), `POST /points/app-open`. Punkte steigen mit der Serie, siehe unten |
| Artikel komplett gelesen | 10 | einmal je Artikel, höchstens 3 Artikel pro Tag, Lese-Nachweis siehe unten. Gilt in App **und** auf der Website |
| Coaching-Lektion erledigt | 10 | einmal je Lektion, höchstens 5 Lektionen pro Tag (einstellbar, 0 = unbegrenzt) |
| Coaching-Kurs abgeschlossen | 50 | einmal je Kurs, sobald alle veröffentlichten Lektionen erledigt sind |
| Kund*in geworben | 500 | wenn die geworbene Person ihre erste bezahlte Bestellung ab 15 € macht. Vorgemerkt bis 14 Tage nach "Abgeschlossen". Nur mit Modul „Freunde werben“ |
| Willkommensbonus für Geworbene | 200 | mit der ersten Bestellung, ebenfalls vorgemerkt |

Alle Werte sind im Backend unter **Vibono-Punkte → Kurs & Regeln** änderbar. Die Startwerte sind Vorschläge, keine Vorgabe von Vibono, und sollten vor dem Start kalkuliert werden. Ein Wert von 0 schaltet den Anlass ab; er erscheint dann auch nicht mehr in der App unter „So sammelst du Punkte“.

## Coaching-Fortschritt

- Eine Lektion zählt als erledigt, wenn sie in der App oder auf der Website (MyVibono-Haken) abgehakt wird. Das Plugin bucht beim ersten Setzen des Hakens (`lesson_done:<user>:<lektion>`), Abhaken und wieder Anhaken bringt nichts.
- Belohnt werden nur veröffentlichte Lektionen, die die Person sehen darf (Mitgliedschaft).
- **Kursbonus** (`course_done:<user>:<kurs>`): wenn alle veröffentlichten Lektionen des Kurses erledigt sind, egal ob die letzte in der App oder auf der Website abgehakt wurde.
- **Keine Punkte für die Vergangenheit:** Haken, die schon vor dem Update auf der Website gesetzt waren, werden beim ersten Abgleich als Ausgangsstand übernommen (Nutzer-Meta `_vibono_coaching_baseline`) und bringen keine Punkte. Sonst bekämen Bestandskund*innen auf einen Schlag mehrere tausend Punkte.
- Tageslimit gegen Durchklicken: Standard 5 belohnte Lektionen pro Tag. Weitere Lektionen werden normal gespeichert, nur ohne Punkte.

## Serie (Streak) fürs tägliche Öffnen

Wer die App mehrere Tage in Folge öffnet, bekommt pro Tag mehr Punkte. Einstellungen unter **Vibono-Punkte → Kurs & Regeln → Serie fürs tägliche Öffnen** (alles Vorschläge):

| Tage in Folge | Punkte pro Tag |
|---|---|
| 1–2 | 5 (Wert „App täglich öffnen“) |
| ab 3 | 6 |
| ab 7 | 8 |
| ab 14 | 10 |
| ab 30 | 12 |

- Stufen frei einstellbar (beliebig viele, „ab Tag X: Y Punkte“). Die Serie lässt sich ganz ausschalten, dann gibt es jeden Tag den Grundwert.
- **Schutztage:** Verpasst jemand einen Tag, hält die Serie, solange im laufenden Kalendermonat Schutztage übrig sind (Start: 2 pro Monat). Verpasste Tage zählen nicht mit und bringen keine Punkte.
- **Wenn die Serie reißt** (mehr Lücken als Schutztage), einstellbar: *eine Stufe zurückfallen* (Start, z. B. von Tag 20 auf Tag 7, also weiter mit 8 statt 10 Punkten) oder *neu bei Tag 1 beginnen*.
- Aktionen für „App geöffnet“ multiplizieren die Punkte der Stufe (z. B. dreifach: Tag 7 → 24 Punkte).
- Kosten im Blick: Wer 30 Tage am Stück öffnet, bekommt mit den Startwerten 5+5+6×4+8×7+10×16+12 = 262 Punkte (2,62 €) im ersten Monat, danach 12 Punkte pro Tag (ca. 3,60 € im Monat).
- Tag = Kalendertag in der Zeitzone der Website. Der Stand liegt im Nutzer-Meta `_vibono_app_streak` (wird mit dem Konto gelöscht, ist im Datenexport enthalten). Beim ersten Öffnen nach dem Update wird eine laufende Serie aus den bisherigen Öffnen-Buchungen übernommen.
- Die App bekommt den Stand bei `POST /points/app-open`, `GET /points` und `GET /today` (Feld `streak`, siehe openapi.yaml). Die Übersicht im Backend zeigt, wie viele Personen gerade eine Serie haben und auf welcher Stufe.

## Punkte einlösen: Prämien

Festgelegt von Vibono am 21.11.2026: Punkte werden gegen **exklusive Inhalte (Rezepte, Tipps, Lektionen), exklusive eBooks/PDFs und Rabatt auf die Verlängerung** eingelöst. Punkte lassen sich nicht kaufen und nicht auszahlen.

Einschalten unter **Vibono-Punkte → Allgemein → Prämien**, pflegen unter **Vibono-Punkte → Prämien**.

| Art | Was passiert beim Einlösen | Wo einlösbar (Standard) |
|---|---|---|
| **Exklusiver Inhalt** | Ein Beitrag (Rezept, Tipp, Lektion) wird für diese Person dauerhaft freigeschaltet. Ohne Freischaltung sehen alle nur Titel, Bild und einen kurzen Anriss, auch auf der Website, in der WP-REST-API und im Feed | App und Website |
| **eBook/PDF** | Die Datei aus der Mediathek kann danach jederzeit geladen werden. Der Download läuft über einen signierten Link, der 15 Minuten gilt (einstellbar); die Datei selbst wird nicht öffentlich verlinkt | App und Website |
| **Rabatt auf die Verlängerung** | Es entsteht ein persönlicher WooCommerce-Gutschein (`VP-XXXX-XXXX`), fester Betrag oder Prozent, nur für die hinterlegten Verlängerungs-Produkte, nur mit der E-Mail-Adresse der Person, einmal nutzbar, mit Ablaufdatum (Standard-Vorschlag 90 Tage) | **nur Website** (Mein Konto → Vibono-Punkte). In der App aus, siehe `APP-STORE.md` |

Einstellungen je Prämie: Titel, Beschreibung, Bild, Punkte, Beitrag/Datei/Rabatt, Gültigkeit des Gutscheins, wie oft eine Person sie einlösen darf (Inhalte und Dateien immer einmal), aktiv ja/nein. Eine schon eingelöste Prämie lässt sich nicht löschen, nur deaktivieren; Freischaltungen bleiben dann bestehen.

Vorschläge in der Testumgebung: exklusives Rezept 300, exklusiver Tipp 200, eBook 500, 10 € Rabatt auf die Verlängerung 1000 Punkte (einmal je Person).

Technik:
- Einlösen bucht eine negative Zeile mit Grund `reward` ins Hauptbuch. Schlägt das Anlegen des Gutscheins fehl, wird sofort mit `reward_refund` zurückgebucht.
- Ein Sperr-Eintrag je Konto verhindert, dass zwei gleichzeitige Einlösungen den Kontostand unter null drücken (Antwort 429 `vibono_busy`).
- Freischaltungen liegen in der Tabelle `wp_vibono_reward_unlocks`, werden mit dem Konto gelöscht und sind im Datenexport enthalten.
- Redaktion und Admins sehen exklusive Beiträge immer vollständig.
- Nach dem Einlösen löst das Plugin die Aktion `vibono_reward_redeemed` aus (z. B. für eine Bestätigungs-E-Mail). Gutschein-Einstellungen lassen sich über den Filter `vibono_reward_coupon_args` anpassen.
- App: `GET /rewards`, `POST /rewards/{id}/redeem`, `GET /rewards/{id}/download` (siehe openapi.yaml). Gesperrte Beiträge liefern bei `GET /content/{id}` den Fehler 403 `vibono_reward_required` mit Prämie und Punkten, damit die App direkt das Einlösen anbieten kann.
- Exklusive Rezepte werden nie automatisch in Tagesplan oder Wochenplan vorgeschlagen.

Kund*innen sehen Kontostand, Verlauf, ihre Prämien und den Empfehlungslink unter **Mein Konto → Vibono-Punkte**.

## Früher: Einkäufe und Guthaben an der Kasse

Bis 21.11.2026 gab es Punkte für Einkäufe (5 je Euro) und man konnte Punkte im Warenkorb als Guthaben einlösen (1 Punkt = 1 Cent, höchstens 50 % des Warenwerts, mindestens 100 Punkte, technisch der virtuelle Gutschein `vibono-punkte`). Beides ist jetzt **standardmäßig aus**, aber nicht entfernt:

- Schalter unter **Vibono-Punkte → Kurs & Regeln → Früher: Einkäufe und Guthaben an der Kasse**: `earn_purchases` (Punkte für Einkäufe) und `redeem_at_checkout` (Punkte an der Kasse einlösen). Beide wirken nur zusammen mit dem Modul „Shop“.
- Ist das Guthaben an der Kasse aus, liefert `GET /config` `shop_links.points_redemption = false`, und App und Website zeigen keinen Euro-Gegenwert mehr. Der „Wert eines Punktes“ bleibt für Aktionen und die Buchhaltung bestehen.
- Schon gebuchte Kaufpunkte bleiben auf dem Konto. Vorgemerkte Kaufpunkte werden wie bisher nach 14 Tagen bestätigt oder bei Storno storniert.

## Aktionen

Unter **Vibono-Punkte → Aktionen** legt das Team Aktionen mit Zeitraum und Multiplikator an:

| Beispiel | Art | Gilt für | Multiplikator |
|---|---|---|---|
| Doppelte Punkte beim Anwerben, nächste 2 Wochen | Punkte verdienen | Kund*in geworben | 2 |
| Doppelte Punkte für erledigte Lektionen | Punkte verdienen | Lektion erledigt | 2 |
| Lese-Woche: dreifache Lesepunkte | Punkte verdienen | Artikel gelesen | 3 |

- Verdien-Aktionen wirken auf den Zeitpunkt, an dem die Punkte entstehen (bei Empfehlungen: Zahlungseingang). Der Multiplikator wird an der Buchung gespeichert.
- Einlöse-Aktionen („Einlösewert“) wirken nur auf das Guthaben an der Kasse und sind damit derzeit ohne Wirkung. Prämien kosten immer die eingestellten Punkte.
- Überschneiden sich Aktionen, gilt die stärkste, es wird nicht multipliziert (verhindert ungewollte 6-fach-Punkte).
- Laufende und in den nächsten 14 Tagen startende Aktionen liefert `GET /points/campaigns` an App und Website.

## Lese-Nachweis: Wie wir prüfen, ob ein Artikel wirklich gelesen wurde

Punkte nur für Lesen sind anfällig für "Öffnen und sofort schließen". Vorgeschlagen und umgesetzt ist eine Kombination, weil jedes Signal allein umgehbar ist:

| Methode | Was sie verhindert | Aufwand für Nutzer*innen | Umgesetzt |
|---|---|---|---|
| **Mindest-Lesezeit nach Wortzahl** (40 % der erwarteten Lesezeit bei 220 Wörtern/Minute, mind. 20 s, max. 5 min) | sofortiges Schließen | keiner | ja |
| **Aktive Zeit statt Verweildauer**: Zeit zählt nur, wenn der Artikel sichtbar ist (App im Vordergrund bzw. Browser-Tab sichtbar und fokussiert) und in den letzten 60 s gescrollt oder getippt wurde | Artikel offen lassen und weggehen | keiner | ja |
| **Server-Heartbeats mit Wanduhr-Prüfung**: App/Website melden alle 10 s; der Server erkennt nur so viel Zeit an, wie zwischen zwei Meldungen tatsächlich vergangen ist | manipulierte App/Skripte, die "10 Minuten gelesen" behaupten | keiner | ja |
| **Scrolltiefe** bis 90 % des Artikels | nur den Anfang lesen | keiner | ja |
| **Quizfrage** (eine Frage, drei Antworten, im Beitrag pflegbar) | Durchscrollen ohne Lesen | gering, macht aber oft Spaß | ja, optional je Beitrag oder als Pflicht einstellbar |
| Tageslimit (3 belohnte Artikel) und einmal je Artikel | Punkte-Farmen | keiner | ja |
| Augen-/Aufmerksamkeitserkennung per Kamera | – | hoch, datenschutzrechtlich heikel | nein, nicht empfohlen |

Empfehlung: Mit Zeit + Scrolltiefe + Heartbeats starten (unsichtbar für Nutzer*innen). Quizfragen für die wichtigsten Coaching-Lektionen pflegen; das festigt zusätzlich das Wissen. Wenn Missbrauch auffällt, Quiz-Modus auf "Pflicht" stellen.

Ablauf in der App: `POST /reading/start` → alle 10 s `POST /reading/heartbeat` (nur im Vordergrund) → bei `ready_to_complete: true` ggf. Quiz anzeigen → `POST /reading/complete`. Auf der Website erledigt das Skript `assets/reading-tracker.js` dasselbe automatisch für eingeloggte Nutzer*innen.

## Missbrauchsschutz

- Idempotenz-Schlüssel je Anlass (z. B. `app_open:<user>:<datum>`, `article_read:<user>:<post>`, `referral:<geworbene Person>`): Doppelbuchungen sind technisch ausgeschlossen.
- Empfehlungen: keine Selbstwerbung (gleiches Konto, gleiche E-Mail, gleiche Lieferadresse), nur Neukund*innen (keine frühere bezahlte Bestellung), nur eine Prämie je geworbener Person, Prämie erst nach Widerrufsfrist.
- Empfehlungspunkte (und Kaufpunkte, falls wieder eingeschaltet) verfallen bei Storno/Erstattung.
- Coaching-Punkte: einmal je Lektion und Kurs, Tageslimit, keine Punkte für alte Haken.
- Prämien: Kontostand wird unter Sperre geprüft, Download-Links sind signiert und laufen ab.
- Login-Bremse (5 Fehlversuche / 15 min), Ratenbegrenzung für Registrierung, Code-Prüfung und Lese-Sessions.
- Manuelle Korrekturen nur im Backend mit Begründung, protokolliert mit Benutzer-ID.

## Offene Punkte für Vibono

1. **Rechtliches**: Bonusprogramm-Bedingungen (Teilnahmebedingungen, Verfall, Ausschluss von Barauszahlung), Hinweis in AGB und Datenschutzerklärung. Wir empfehlen eine kurze Prüfung durch eine Fachanwältin/einen Fachanwalt.
2. **Verfall**: Sollen Punkte verfallen (z. B. 24 Monate nach Gutschrift)? Ist im Hauptbuch vorbereitet (Grund `expire`), aber noch nicht automatisiert.
3. **Buchhaltung**: Offene Punkte sind eine Verbindlichkeit. Die Übersicht im Backend zeigt den aktuellen Gegenwert.
4. **Punktwerte und Prämienpreise bestätigen**: Lektion 10 (max. 5/Tag), Kurs 50, Prämien 200 bis 1000 Punkte sind Vorschläge.
5. **Verlängerungs-Produkt**: Welche Produkte gelten als Verlängerung? Muss je Rabatt-Prämie hinterlegt werden, sonst gilt der Gutschein für den ganzen Warenkorb.
