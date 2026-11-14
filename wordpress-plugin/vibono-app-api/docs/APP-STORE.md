# Keine In-App-Käufe: Wie wir Provisionsansprüche von Apple und Google vermeiden

Stand: November 2026, nach meinem Wissensstand. **Kein Rechtsrat.** Die Regeln von Apple und Google und die Auslegung des EU-Gesetzes über digitale Märkte (DMA) ändern sich häufig. Vor dem Einreichen der App bitte von einer auf App-Recht spezialisierten Kanzlei prüfen lassen.

## Grundprinzip

Provision fällt an, wenn **in der App** digitale Inhalte gekauft werden oder die App Nutzer*innen gezielt zum Kauf digitaler Inhalte auf eine Website leitet. Die Vibono-App ist deshalb eine reine **Login- und Begleit-App**:

- Kein Kauf in der App, keine Preise, keine Kauf-Buttons, keine Hinweise wie „Jetzt günstiger auf vibono.de“ für digitale Inhalte.
- Mitgliedschaften (WooCommerce Memberships) werden ausschließlich auf vibono.de verkauft. Die App prüft beim Login nur, ob eine Mitgliedschaft besteht (`GET /me` → `has_coaching_access`).
- Gesperrte Inhalte zeigt die App neutral an („Dieser Inhalt ist Teil einer Vibono-Mitgliedschaft.“), standardmäßig ohne Link.

## Was erlaubt ist

| Inhalt | Apple App Store | Google Play | Umsetzung |
|---|---|---|---|
| **Physische Produkte** (Shop-Artikel) | Kauf außerhalb erlaubt, In-App-Kauf darf dafür sogar nicht genutzt werden (Richtlinie 3.1.3(e)/3.1.5) | ausgenommen von der Abrechnungspflicht | Link zum Shop erlaubt (`shop_links.physical_products = true`) |
| **Punkte einlösen** im Shop | Punkte werden nicht gekauft, sondern verdient; Einlösung für physische Produkte | wie links | Link „Punkte im Shop einlösen“ erlaubt (`points_redemption = true`). Einlösung für Mitgliedschaften nur auf der Website, nicht aus der App beworben |
| **Mitgliedschaften** (digital) | Verkauf/Link aus der App nur mit In-App-Kauf oder mit Apples Sonderprogrammen und Gebühren (EU: alternative Bedingungen; USA: externe Links seit 2025 provisionsfrei möglich) | Google Play Billing oder Programme für alternative Abrechnung mit reduzierter Gebühr | **Aus** (`memberships = false`). Login für bereits gekaufte Mitgliedschaften ist erlaubt (Multiplattform-Zugriff) |
| Empfehlungslink teilen | erlaubt | erlaubt | Teilen-Button mit Link auf vibono.de |

## Technische Absicherung im Plugin

- `GET /config?platform=ios|android` liefert die Schalter `shop_links.physical_products`, `.points_redemption`, `.memberships`. Die App zeigt Links nur, wenn der Schalter an ist. So kann Vibono bei Rückfragen von Apple oder Google Links **ohne neues App-Update** abschalten.
- Einstellbar im Backend unter **Vibono-Punkte → App-Schnittstelle → App-Store-Regeln**.
- `POST /auth/web-session` öffnet vibono.de eingeloggt im **externen Browser** (kein eingebetteter Kaufablauf in der App).

## Pflichten, die trotzdem gelten

- **Konto löschen in der App** (Apple 5.1.1(v)): `DELETE /me` stößt die Löschung an.
- **Anmeldung mit Apple**: nicht nötig, solange nur das eigene Vibono-Konto (E-Mail/Passwort) angeboten wird und kein Login über Google/Facebook in der App.
- **Gesundheitsdaten** (Gewicht, Ziele): Datenschutzerklärung der App, App-Store-Datenschutzangaben („Nutrition Labels“), Einwilligung bei der Registrierung (`accept_privacy`).
- **Review-Zugang**: Apple braucht ein Testkonto mit Mitgliedschaft und den Hinweis, dass Mitgliedschaften nur auf der Website verkauft werden.

## Empfehlung für den Start

1. iOS und Android mit `physical_products = true`, `points_redemption = true`, `memberships = false` einreichen.
2. In der App-Store-Beschreibung keine Preise oder Kaufaufforderungen für Mitgliedschaften.
3. Nach der Zulassung prüfen lassen, ob für den US-Store ein Mitgliedschafts-Link sinnvoll ist (dort derzeit provisionsfrei möglich).
