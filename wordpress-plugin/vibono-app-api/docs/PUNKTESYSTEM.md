# Vibono-Punkte: Konzept

Ein zentrales Punktekonto pro Vibono-Konto, das in der App und im Shop auf vibono.de gleich funktioniert. Technisch ist es ein Hauptbuch (Tabelle `wp_vibono_points_ledger`) im WordPress-Plugin `vibono-app-api`. App und Shop lesen und schreiben nur über dieses Plugin.

## Punkte verdienen

| Anlass | Startwert (Vorschlag) | Regeln |
|---|---|---|
| App täglich öffnen | 5 | einmal pro Kalendertag (Europe/Berlin), `POST /points/app-open` |
| Artikel nachweislich gelesen | 10 | einmal je Artikel, höchstens 3 Artikel pro Tag, Lese-Nachweis siehe unten. Gilt in App **und** auf der Website |
| Kund*in geworben | 500 (= 5 €) | wenn die geworbene Person ihre erste bezahlte Bestellung ab 15 € macht. Vorgemerkt bis 14 Tage nach "Abgeschlossen" |
| Willkommensbonus für Geworbene | 200 | mit der ersten Bestellung, ebenfalls vorgemerkt |
| Einkauf im Shop | 5 je Euro | Warenwert ohne Versand, nach Rabatten und Punkte-Einlösung. Vorgemerkt bis 14 Tage nach "Abgeschlossen", bei Storno/Erstattung verfallen sie |

Alle Werte sind im Backend unter **Vibono-Punkte → Kurs & Regeln** änderbar. Die Startwerte sind Vorschläge, keine Vorgabe von Vibono, und sollten vor dem Start kalkuliert werden (5 Punkte je Euro sind 5 % Rabatt bei 1 Cent je Punkt).

## Punkte einlösen

- Nur im Shop auf vibono.de, im Warenkorb und an der Kasse ("Punkte einlösen"). In der App gibt es keine Käufe.
- Umrechnung: **1 Punkt = 1 Cent** (Einstellung "Wert eines Punktes"). Jede Kursänderung wird protokolliert (Option `vibono_points_rate_log`).
- Technisch als virtueller Gutschein `vibono-punkte`. Dadurch verteilt WooCommerce den Rabatt korrekt auf die Steuersätze (wichtig bei 7 % / 19 % gemischten Warenkörben).
- Grenzen (einstellbar): höchstens 50 % des Warenwerts, mindestens 100 Punkte.
- Abbuchung beim Anlegen der Bestellung. Wird die Bestellung storniert, schlägt die Zahlung fehl oder wird sie erstattet, gehen die Punkte automatisch zurück.
- Kund*innen sehen Kontostand, Verlauf und Empfehlungslink unter **Mein Konto → Vibono-Punkte**.

## Aktionen

Unter **Vibono-Punkte → Aktionen** legt das Team Aktionen mit Zeitraum und Multiplikator an:

| Beispiel | Art | Gilt für | Multiplikator |
|---|---|---|---|
| Doppelte Punkte beim Anwerben, nächste 2 Wochen | Punkte verdienen | Kund*in geworben | 2 |
| Punkte sind eine Woche im Shop doppelt so viel wert | Einlösewert | Shop | 2 |
| Lese-Woche: dreifache Lesepunkte | Punkte verdienen | Artikel gelesen | 3 |

- Verdien-Aktionen wirken auf den Zeitpunkt, an dem die Punkte entstehen (bei Empfehlungen und Käufen: Zahlungseingang). Der Multiplikator wird an der Buchung gespeichert.
- Einlöse-Aktionen wirken auf den Zeitpunkt der Einlösung.
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
- Kauf- und Empfehlungspunkte verfallen bei Storno/Erstattung.
- Login-Bremse (5 Fehlversuche / 15 min), Ratenbegrenzung für Registrierung, Code-Prüfung und Lese-Sessions.
- Manuelle Korrekturen nur im Backend mit Begründung, protokolliert mit Benutzer-ID.

## Offene Punkte für Vibono

1. **Rechtliches**: Bonusprogramm-Bedingungen (Teilnahmebedingungen, Verfall, Ausschluss von Barauszahlung), Hinweis in AGB und Datenschutzerklärung. Wir empfehlen eine kurze Prüfung durch eine Fachanwältin/einen Fachanwalt.
2. **Verfall**: Sollen Punkte verfallen (z. B. 24 Monate nach Gutschrift)? Ist im Hauptbuch vorbereitet (Grund `expire`), aber noch nicht automatisiert.
3. **Buchhaltung**: Offene Punkte sind eine Verbindlichkeit. Die Übersicht im Backend zeigt den aktuellen Gegenwert.
4. **Teilerstattungen**: Bei einer Teilerstattung bleiben Kaufpunkte derzeit unverändert; bei vollständiger Erstattung verfallen sie.
