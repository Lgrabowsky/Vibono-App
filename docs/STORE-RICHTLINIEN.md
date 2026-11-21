# Keine Provision an Apple und Google: Rechtslage kurz

Stand 14. November 2026. **Keine Rechtsberatung.** Die Regeln ändern sich gerade schnell; vor der Einreichung bitte
von einer auf App-Recht spezialisierten Kanzlei prüfen lassen. Die ausführliche Umsetzung im Backend steht in
`wordpress-plugin/vibono-app-api/docs/APP-STORE.md`.

## Der Grundsatz

Apple und Google verlangen Provision, wenn **in der App** digitale Inhalte verkauft werden (Mitgliedschaften,
Coaching-Zugang) oder wenn die App auf einen Kauf solcher Inhalte im Web verlinkt und dafür ein Gebührenprogramm
greift. Physische Produkte und Dienstleistungen außerhalb der App sind ausgenommen: Dafür darf Apples In-App-Kauf
gar nicht genutzt werden (App Review Guidelines 3.1.3(e), 3.1.5(a)); Google nimmt physische Waren von der
Abrechnungspflicht aus.

## Aktuelle Lage nach Region

| Region | Apple | Google |
|---|---|---|
| **EU / Deutschland** | Seit 1. Oktober 2026 neue einheitliche Bedingungen (Anhang 14 der Developer Program License Agreement). Links auf externe Käufe digitaler Inhalte sind erlaubt, kosten aber 15 % Provision auf Käufe innerhalb von 7 Tagen nach dem Antippen; In-App-Kauf 26 %. | Programme für alternative Abrechnung und externe Angebote mit reduzierten Gebühren. |
| **USA** | Nach dem Epic-Urteil (April 2025) sind Links und Buttons zum Webkauf erlaubt und derzeit **provisionsfrei**. Das Berufungsgericht hat das komplette Provisionsverbot aufgehoben und die Höhe an das Bezirksgericht zurückverwiesen; Apple hat im August 2026 15 % (5 % im Small Business Program) beantragt, Entscheidung voraussichtlich 2027. | Seit Oktober 2025 darf auf externe Zahlungen verlinkt werden. Laut Berichten werden ab 1. Oktober 2026 Servicegebühren für die US-Programme fällig (je nach Programm etwa 10 bis 20 %). |
| **Übrige Länder** | Keine Kaufaufforderungen oder Links zu Webkäufen digitaler Inhalte ohne In-App-Kauf („Anti-Steering“). | Ebenso, außer in Ländern mit eigenen Programmen. |

Erlaubt bleibt überall: Mitgliedschaften, die auf vibono.de gekauft wurden, in der App per Login zu nutzen
(Multiplattform-Zugriff), solange die App selbst nicht zum Kauf auffordert.

## Was die App deshalb macht

- **Keine In-App-Käufe, keine Preise, keine Kauf-Buttons** für Mitgliedschaften oder Coaching.
- Gesperrte Inhalte werden neutral angezeigt, ohne Hinweis, wo man sie kaufen kann.
- Punkte werden verdient, nie gekauft. Der Euro-Gegenwert und der Link „Im Vibono-Shop einlösen“ erscheinen nur,
  wenn `GET /config` `shop_links.points_redemption` für die Plattform freigibt. Ohne Verbindung gilt „aus“.
- „Einkauf im Vibono-Shop“ als Punkte-Quelle erscheint nur bei `shop_links.physical_products`.
- Webseiten öffnen immer im externen Browser, nie als eingebetteter Kaufablauf.
- **Prämien** (seit 21.11.2026): Verdiente Punkte schalten in der App exklusive Rezepte, Tipps und eBooks/PDFs frei.
  Es fließt kein Geld und Punkte lassen sich nicht kaufen, deshalb ist das kein In-App-Kauf. Die Prämie
  „Rabatt auf die Verlängerung“ ist ein Gutschein für eine Mitgliedschaft und zeigt die App deshalb nicht
  (`features.reward_kinds` aus `GET /config`, je Plattform im Backend schaltbar). Sie ist nur auf vibono.de
  einlösbar, ohne Hinweis darauf in der App.
- Punkte für Einkäufe und Punkte als Guthaben an der Kasse sind seit 21.11.2026 standardmäßig aus.
- Teilen des Empfehlungslinks ist erlaubt (er richtet sich an Freunde, nicht an die Person in der App).
- Konto löschen ist in der App möglich (Apple 5.1.1(v)).

## Empfehlung

1. Zum Start iOS und Android mit `memberships = false` einreichen, `physical_products = true`.
2. `points_redemption` auf iOS und Android außerhalb der USA nur einschalten, wenn der Link auf eine Seite führt,
   die ausschließlich physische Produkte zeigt; sonst kann Apple das als Lenkung zu digitalen Käufen werten.
3. In der Store-Beschreibung keine Preise oder Kaufaufforderungen für Mitgliedschaften.
4. Für Apples Review ein Testkonto mit Mitgliedschaft hinterlegen und erklären, dass Mitgliedschaften nur auf
   der Website verkauft werden.
5. Die US-Entscheidung zur Link-Provision 2027 beobachten; ein Mitgliedschafts-Link im US-Store ist nach
   heutigem Stand provisionsfrei, kann aber rückwirkend gebührenpflichtig werden.

## Quellen

- MacRumors, 13.08.2026: Apple beantragt bis zu 15 % auf US-Link-outs – https://www.macrumors.com/2026/08/13/app-store-fees-apple-link-outs/
- Legal500: Update zu externen Käufen bei Apple und Google – https://www.legal500.com/intelligence/united-states/media-telecoms-it-entertainment/update-your-app-external-purchase-developments-for-apple-google
- Apple Developer: Zahlungsoptionen im App Store in der EU – https://developer.apple.com/support/communication-and-promotion-of-offers-on-the-app-store-in-the-eu/
- Daring Fireball, 08/2026: Einigung Apple und EU-Kommission – https://daringfireball.net/2026/08/apple_eu_business_terms_conceding_little
- Playio, Gebühren 2026 (Google-US-Programme) – https://blog.playio.co/app-store-fees-2026-games
- Appcharge: Epic v. Google, Vergleich zurückgezogen – https://www.appcharge.com/blog/epic-v-google-the-settlement-is-off-the-table
