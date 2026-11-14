# Umstellung von „Refer a Friend“ (WPGens) auf das Vibono-Punktesystem

Auf vibono.de läuft derzeit **WPGens Refer a Friend Premium 2.4.2** (im Quelltext von „Mein Coaching“ sichtbar, Cookie-Laufzeit 30 Tage). Das Plugin belohnt mit WooCommerce-Gutscheinen. Ziel ist, Empfehlungen künftig mit Vibono-Punkten zu belohnen, die in App und Shop gleich funktionieren.

## Was sich ändert

| | Refer a Friend (heute) | Vibono-Punkte (neu) |
|---|---|---|
| Belohnung | Gutschein je erfolgreicher Empfehlung | Punkte auf dem zentralen Konto |
| Geworbene | Rabatt-Gutschein | Willkommensbonus in Punkten |
| Link | `?raf=CODE` | `?vref=CODE`, alte `?raf=`-Links funktionieren weiter |
| Sichtbar | Mein Konto (Website) | App (Teilen-Button) und Mein Konto → Vibono-Punkte |
| Aktionen | – | z. B. doppelte Punkte fürs Werben für 2 Wochen |
| Missbrauchsschutz | Basis | keine Selbstwerbung, nur Neukund*innen, Prämie erst nach Widerrufsfrist, Storno-Rückbuchung |

## Empfohlener Ablauf

**Vorbereitung (Staging)**
1. Plugin `vibono-app-api` auf einer Staging-Kopie installieren und aktivieren.
2. In der Datenbank prüfen, wo Refer a Friend speichert. **ANNAHME**, bitte bestätigen:
   - Nutzer-Meta `gens_referral_id` = Empfehlungscode der Person.
   - URL-Parameter `raf`.
   - Gutscheine: `shop_coupon` mit E-Mail-Beschränkung auf die werbende Person; das kennzeichnende Meta-Feld vorher ermitteln, z. B. mit
     `wp db query "SELECT DISTINCT meta_key FROM wp_postmeta pm JOIN wp_posts p ON p.ID = pm.post_id WHERE p.post_type = 'shop_coupon' AND meta_key LIKE '%raf%'"`
3. Falls abweichend: unter **Vibono-Punkte → App-Schnittstelle** bzw. in den Einstellungen `referral_legacy_meta_key` und `referral_legacy_params` anpassen.

**Probelauf**
```bash
wp vibono migrate-raf --dry-run
wp vibono migrate-raf --dry-run --coupon-meta=<ermitteltes_meta_feld>
```
Zeigt, wie viele Codes übernommen und welche offenen Gutscheine in wie viele Punkte umgewandelt würden.

**Umstellung (Live, ruhige Uhrzeit)**
1. Kund*innen vorab informieren (Newsletter/Mein Konto): „Aus Empfehlungs-Gutscheinen werden Vibono-Punkte.“
2. Plugin aktivieren, Einstellungen übernehmen, Aktion „Start: doppelte Punkte fürs Werben“ anlegen (optional). Das Modul **Freunde werben** bleibt bis Schritt 4 aus.
3. `wp vibono migrate-raf --coupon-meta=<…>` ausführen:
   - Alte Codes werden die neuen Codes. Alte Links bleiben gültig.
   - Offene Refer-a-friend-Gutscheine mit festem Betrag werden 1:1 in Punkte umgewandelt (bei 1 Cent je Punkt: 5 € = 500 Punkte) und der Gutschein beendet. Prozent-Gutscheine bleiben unverändert bis zu ihrem Ablauf.
4. In Refer a Friend die Belohnungen abschalten (keine neuen Gutscheine mehr), dann unter **Vibono-Punkte → Module & Anbindung** das Modul **Freunde werben** einschalten. Refer a Friend noch **30 Tage aktiv lassen**: Cookies und laufende Empfehlungen bleiben so nachvollziehbar. Das Vibono-Plugin liest das `raf`-Cookie nicht, wertet aber neue Klicks auf `?raf=`-Links selbst aus.
5. Nach 30 Tagen Refer a Friend deaktivieren und löschen. Die eigenen Empfehlungs-Seiten/Shortcodes im Theme durch den Block in **Mein Konto → Vibono-Punkte** ersetzen.

**Kontrolle**
- `wp vibono balance kundin@example.com` für Stichproben.
- Backend → Vibono-Punkte → Übersicht: offene Punkte und Buchungen nach Grund.

## Was nicht automatisch übernommen wird

- Historische Empfehlungs-Statistiken aus Refer a Friend (wer wen geworben hat). Die neuen Zähler starten bei 0. Falls gewünscht, lässt sich das nachrüsten, sobald klar ist, wo Refer a Friend die Zuordnung speichert.
- Bereits eingelöste Gutscheine (bleiben in den Bestellungen sichtbar).

## Risiken

- Werden alte Codes nicht gefunden (anderes Meta-Feld), entstehen neue Codes; alte Links führen dann ins Leere. Deshalb erst den Probelauf prüfen.
- Doppelte Belohnung in der Übergangszeit, falls Refer a Friend noch Gutscheine erzeugt. Deshalb Belohnungen in Refer a Friend **vor** der Umstellung abschalten.
