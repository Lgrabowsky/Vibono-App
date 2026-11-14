# Vibono

App „Vibono“ für iOS und Android: Schritt für Schritt zum Wunschgewicht mit dem Vibono-Konzept
(Vorbereitung → Phase 1 Umstellungstage → Phase 2 Gewohnheiten ändern → Phase 3 Satt essen & genießen).

Inhalt des Repositorys:

- `/` Flutter-App „Vibono“ (dieses README)
- `wordpress-plugin/` WordPress-Plugin `vibono-app-api` (Synchronisation mit MyVibono, Punktesystem), eigener Pull Request

## Schnellstart

```bash
flutter pub get
flutter run                                   # Demo-Modus mit Beispieldaten (Standard)
flutter run --dart-define=VIBONO_MOCK=false   # gegen vibono.de
flutter run --dart-define=VIBONO_MOCK=false \
  --dart-define=VIBONO_API=https://staging.vibono.de/wp-json/vibono/v1
flutter test
```

Im Demo-Modus funktioniert die Anmeldung mit beliebiger E-Mail und einem Passwort ab 4 Zeichen. Der Mock
(`lib/data/api/mock_vibono_api.dart`) bildet den kompletten API-Vertrag nach, inklusive MyVibono-Daten,
Punkten, Lese-Nachweis und Energiedichte-Analyse.

Getestet mit Flutter 3.50 / Dart 3.14. Material-Widgets kommen aus `package:material_ui`.

### Test-APK für Android

Bei jedem Push auf `main` oder einen `claude/…`-Branch baut der Workflow `.github/workflows/android-apk.yml`
eine installierbare APK (Demo-Modus, mit Debug-Schlüssel signiert). Sie liegt im jeweiligen Lauf unter
**Actions → Android-APK → Artifacts**. Lokal geht es mit `flutter build apk --release`.

## Was die App kann

| Bereich | Umsetzung |
|---|---|
| **Heute** | Entwurf Variante A: Logo, Datum mit ‹ › zum Blättern, Begrüßung, Punktestand, Phasen-Fortschrittsbalken (Start · UT · Phase 2 · Phase 3), „Als Nächstes“-Karte mit genau einem nächsten Schritt, Kacheln Essen/Bewegung/Wissen/Wichtig, 3 Rezepte (Frühstück, Mittag, Abend), Vibono-Tipp, Tipp des Tages, „Mehr Rezepte“/„Mehr Tipps“. **Keine Uhrzeiten an den Tagen.** |
| **Rezepte** | Suche, Filter (Lieblingsrezepte, grün, vegetarisch, vegan, UT-geeignet, Frühstück), Energiedichte-Plakette, Detailseite mit Ampel, Merken (synchron), „In den Plan“ |
| **Coaching** (Vibono-V) | Kurse und Lektionen aus „Mein Coaching“, aktuelle Phase zuerst, Abhaken synchron mit der Website, Filter nach Art, Etappenziele 3/6/12 Monate |
| **Wochenplan** | 7 Tage × 3 Mahlzeiten, die App füllt leere Plätze passend zu Phase und Vorlieben, Tauschen, Einkaufsliste; synchron mit „Mein Wochenplan“ |
| **Mehr** | Punkte, Freunde einladen, Energiedichte-Rechner, Gewicht & Ziele, Vibono-Tipps, Benachrichtigungen, Meine Angaben, Abgleich, Datenschutz/Impressum, Abmelden, Konto löschen |
| **Onboarding** | Duolingo-Stil, eine Frage pro Bildschirm: Ernährung, Unverträglichkeiten, Abneigungen, Bewegungsniveau, Geschlecht, Altersgruppe, Haushalt/Kinder, Gewicht, Wunschgewicht nach 3/6/12 Monaten (mit Tempo-Rückmeldung), Starttag, Benachrichtigungen |
| **Energiedichte-Rechner** | 1) Zutaten eingeben (eingebaute Liste + `GET /foods`), 2) Rezept mit der Kamera scannen, 3) Foto eines fertigen Gerichts (auch Restaurant) mit optionaler Beschreibung schätzen lassen, mit Genauigkeitsanzeige. Ergebnis immer kcal/g mit Vibono-Ampel (grün ≤ 1,5, gelb ≤ 2,5, rot darüber). Die Bildauswertung läuft serverseitig über die Claude API, der Schlüssel liegt nie in der App. |
| **Benachrichtigungen** | 0 bis 10 pro Tag, nach Themen (Aufgaben, Rezepte, Motivation, Bewegung, Wissen), gleichmäßig verteilt außerhalb der Ruhezeit, lokal geplant (`lib/domain/notification_planner.dart`), Antippen öffnet den Inhalt |
| **Punkte** | Tägliches Öffnen, nachweislich gelesene Beiträge, Freunde werben, Einkäufe im Shop (Gutschrift serverseitig), Aktionen mit Multiplikator, Verlauf |

## Lese-Nachweis für Punkte

Punkte für einen Beitrag gibt es nur, wenn er wirklich gelesen wurde (`lib/ui/screens/article_screen.dart`):

1. **Aktive Lesezeit:** zählt nur, solange die App im Vordergrund ist, der Beitrag sichtbar ist und in den letzten 45 Sekunden gescrollt oder getippt wurde. Mindestzeit vom Server, abhängig von der Wortzahl.
2. **Scrolltiefe:** Das Ende des Beitrags muss erreicht sein (Standard 90 %).
3. **Serverprüfung:** Lese-Session mit Heartbeats (`/reading/start`, `/reading/heartbeat`, `/reading/complete`). Der Server erkennt höchstens so viel Aktivzeit an, wie laut Wanduhr vergangen ist, und vergibt pro Beitrag nur einmal Punkte, mit Tageslimit.
4. **Optional Quizfrage** bei längeren Beiträgen.

Die Website kann dieselbe Session-API per JavaScript nutzen (Sichtbarkeit über die Page Visibility API, Scrolltiefe über einen Intersection Observer am Artikelende).

## Synchronisation mit MyVibono

Offline-first (`lib/data/sync/sync_repository.dart`): Änderungen an Lieblingsrezepten, erledigten Lektionen, Gewicht,
Sport und Wochenplan landen sofort lokal und in einem Ausgang. Beim Abgleich schickt die App den Ausgang
(`POST /sync`) und holt danach alle Änderungen seit dem letzten Cursor (`GET /sync`), auch die auf der Website.
Konflikte: je Eintrag gewinnt die jüngste Änderung. Abgeglichen wird beim Start, beim Zurückkehren in die App,
nach jeder Änderung und per Pull-to-refresh.

## Keine In-App-Käufe

Die App verkauft nichts, zeigt keine Preise und keine Kauf-Buttons. Shop-Links und der Euro-Gegenwert der Punkte
erscheinen nur, wenn `GET /config` sie für die Plattform freigibt; ohne Verbindung gilt „aus“.
Zusammenfassung der Store-Regeln: [docs/STORE-RICHTLINIEN.md](docs/STORE-RICHTLINIEN.md).

## Aufbau

```
lib/
  core/config.dart            API-Adresse, Demo-Modus, Links
  theme/                      Vibono Design-System (Farben, Schriften, Komponenten)
  data/api/                   API-Vertrag (vibono_api.dart), HTTP-Client, Mock
  data/models/                Modelle passend zu docs/api/openapi.yaml
  data/sync/                  Zwei-Wege-Synchronisation
  domain/                     Coaching-Ablauf, Energiedichte, Rezeptauswahl, Benachrichtigungsplan, Ziele
  services/                   Benachrichtigungen, externe Links
  state/                      Riverpod-Provider (Sitzung, Tag, Punkte)
  ui/                         Bildschirme und Bausteine
assets/                       Logo, App-Icon, Push-Icon, Fotos aus dem Design-System, Source Sans 3
```

## Offen

- Live-Anbindung: Netzwerkzugang zu vibono.de bzw. Staging und ein Testkonto fehlen noch; bis dahin Demo-Modus.
- Echte Texte für Aufgaben, Tipps des Tages und Nachrichten pflegt das Vibono-Team in WordPress.
- Strukturierte Zutaten je Rezept (für eine echte Einkaufsliste und „Rezept nachrechnen“) liefert die API noch nicht.
- Mahlzeiten-Häkchen („3× satt“) werden lokal gespeichert, bis es dafür eine MyVibono-Sammlung gibt.
- Store-Einreichung: Signierung, Bundle-IDs (`de.vibono.vibono`), Datenschutzangaben, Review-Testkonto.
