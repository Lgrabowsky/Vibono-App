#!/usr/bin/env python3
"""Selbsttest der Testumgebung: ruft alle Funktionen des Plugins über die Schnittstelle auf und prüft die Ergebnisse.

Aufruf (Testumgebung muss laufen, am besten frisch zurückgesetzt):
    python3 selbsttest.py [http://localhost:8080]

Dauert gut eine Minute, weil der Lese-Nachweis echte Lesezeit verlangt.
Verändert die Testdaten (neue Konten, Bestellungen, Punkte). Danach Zuruecksetzen.bat ausführen.
"""
import base64
import sys
import time
import uuid

import requests

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080").rstrip("/")
API = BASE + "/wp-json/vibono/v1"
TEST = BASE + "/wp-json/vibono-test/v1"
PW = "vibono-test"
fehler = []


def check(name, bedingung, info=""):
    print(("  ✓ " if bedingung else "  ✗ ") + name + ("" if bedingung else f"  → {info}"))
    if not bedingung:
        fehler.append(name)


class App:
    """Verhält sich wie die App: Bearer-Token, JSON."""

    def __init__(self, email, password=PW):
        r = requests.post(API + "/auth/login", json={"username": email, "password": password, "device_name": "Selbsttest"})
        r.raise_for_status()
        self.t = r.json()
        self.user = self.t["user"]

    def req(self, m, path, body=None):
        r = requests.request(m, API + path, json=body, headers={"Authorization": "Bearer " + self.t["access_token"]})
        try:
            return r.status_code, r.json()
        except ValueError:
            return r.status_code, r.text


def helfer(m, path, body=None):
    r = requests.request(m, TEST + path, json=body)
    return r.status_code, r.json()


def ledger(app):
    return app.req("GET", "/points/ledger?per_page=100")[1]["items"]


def lesen(app, post_id, quiz=None, scroll=1.0):
    """Lese-Session wie die App: Start, Heartbeats mit echter Wartezeit, Abschluss."""
    s, d = app.req("POST", "/reading/start", {"post_id": post_id, "channel": "app"})
    if s != 200:
        return s, d, None
    sid, need, iv = d["session_id"], d["min_active_seconds"], d["heartbeat_interval_seconds"]
    total = 0
    while True:
        time.sleep(iv)
        total += iv
        _, hb = app.req("POST", "/reading/heartbeat", {"session_id": sid, "active_seconds": total, "scroll_depth": scroll})
        if hb.get("ready_to_complete") or total > need + 3 * iv:
            break
    s, r = app.req("POST", "/reading/complete", {"session_id": sid, "quiz_answer": quiz})
    return s, r, sid


print(f"Selbsttest gegen {BASE}\n")

print("Grundlagen")
s, cfg = requests.get(API + "/config?platform=android").status_code, requests.get(API + "/config?platform=android").json()
check("GET /config", s == 200 and cfg["features"]["referral"] and "localhost" in cfg["shop_url"] or BASE in cfg["shop_url"], cfg)
r = requests.post(API + "/auth/login", json={"username": "anna@vibono-test.local", "password": "falsch"})
check("Falsches Passwort wird abgelehnt", r.status_code in (401, 403), r.text[:200])
anna = App("anna@vibono-test.local")
ben = App("ben@vibono-test.local")
clara = App("clara@vibono-test.local")
r = requests.post(API + "/auth/refresh", json={"refresh_token": anna.t["refresh_token"]})
check("Token erneuern", r.status_code == 200, r.text[:200])
anna.t = r.json()
r2 = requests.post(API + "/auth/refresh", json={"refresh_token": anna.t["refresh_token"]})
anna.t = r2.json() if r2.status_code == 200 else anna.t
s, me = anna.req("GET", "/me")
check("GET /me", s == 200 and me["first_name"] == "Anna" and me["has_coaching_access"], me)

print("App öffnen und Serie")
s, d = anna.req("POST", "/points/app-open")
st = d.get("streak", {})
check("Anna: erstes Öffnen ist Tag 7 der Serie, 8 Punkte (Stufe ab Tag 7)", s == 200 and d["awarded_points"] == 8 and not d["already_awarded"] and st.get("days") == 7 and st.get("event") == "continued", d)
s, d2 = anna.req("POST", "/points/app-open")
check("Zweites Öffnen am selben Tag bringt nichts, Serie bleibt", d2["awarded_points"] == 0 and d2["already_awarded"] and d2["streak"]["days"] == 7 and d2["streak"]["event"] == "same_day", d2)
s, x = helfer("POST", f"/nutzer/{anna.user['id']}/tag-vorspulen")
s, d3 = anna.req("POST", "/points/app-open")
check("Nach einem Tag Tag 8, wieder 8 Punkte", d3["awarded_points"] == 8 and d3["streak"]["days"] == 8, d3)
s, t = anna.req("GET", "/coaching/today")
check("Coaching heute enthält die Serie", t["points"]["streak"]["days"] == 8 and t["points"]["streak"]["opened_today"], t["points"])
s, cfg2 = 0, requests.get(API + "/config?platform=android").json()
check("GET /config meldet features.app_streak", cfg2["features"].get("app_streak") is True, cfg2["features"])

s, d = clara.req("POST", "/points/app-open")
check("Clara: erster Tag, 5 Punkte", d["awarded_points"] == 5 and d["streak"]["days"] == 1 and d["streak"]["event"] == "first", d)
for erwartet_tag, erwartet_pkt in ((2, 5), (3, 6)):
    helfer("POST", f"/nutzer/{clara.user['id']}/tag-vorspulen")
    s, d = clara.req("POST", "/points/app-open")
    check(f"Clara: Tag {erwartet_tag}, {erwartet_pkt} Punkte", d["awarded_points"] == erwartet_pkt and d["streak"]["days"] == erwartet_tag, d)
check("Nächste Stufe: ab Tag 7, noch 4 Tage", d["streak"]["next_stage"] == {"from_day": 7, "points": 8, "days_left": 4}, d["streak"])
helfer("POST", f"/nutzer/{clara.user['id']}/tag-vorspulen")
helfer("POST", f"/nutzer/{clara.user['id']}/tag-vorspulen")
s, d = clara.req("POST", "/points/app-open")
check("Ein verpasster Tag: Schutztag hält die Serie (Tag 4)", d["streak"]["event"] == "bridged" and d["streak"]["days"] == 4 and d["streak"]["bridged_days"] == 1 and d["streak"]["grace_left"] == 1, d["streak"])
s, x = helfer("POST", f"/nutzer/{clara.user['id']}/serie", {"tage": 20})
check("Testhelfer: Serie auf 20 Tage setzen", s == 200 and x["serie"]["days"] == 20 and not x["serie"]["opened_today"], x)
for _ in range(4):
    helfer("POST", f"/nutzer/{clara.user['id']}/tag-vorspulen")
s, d = clara.req("POST", "/points/app-open")
check("Drei verpasste Tage (nur 2 Schutztage): eine Stufe zurück auf Tag 7, 8 Punkte", d["streak"]["event"] == "broken" and d["streak"]["days"] == 7 and d["awarded_points"] == 8 and d["streak"]["best"] >= 20, d)
s, p = clara.req("GET", "/points")
check("GET /points enthält Serie mit Stufen", p["streak"]["enabled"] and len(p["streak"]["levels"]) == 5 and p["streak"]["stage"]["from_day"] == 7, p.get("streak"))
led = ledger(clara)
check("Buchung nennt die Serie", any("7 Tage in Folge" in e["label"] for e in led), [e["label"] for e in led][:3])

print("Aktionen")
s, c = helfer("POST", "/aktionen", {"name": "Test ×3 Öffnen", "art": "earn", "gruende": ["app_open"], "multiplikator": 3, "stunden": 1})
check("Aktion anlegen", s == 200, c)
helfer("POST", f"/nutzer/{anna.user['id']}/tag-vorspulen")
s, d = anna.req("POST", "/points/app-open")
check("Öffnen während ×3-Aktion bringt 3 × 8 = 24 Punkte (Stufe der Serie × Aktion)", d["awarded_points"] == 24 and d["multiplier"] == 3 and d["campaign"], d)
helfer("DELETE", f"/aktionen/{c['id']}")
s, c2 = helfer("POST", "/aktionen", {"name": "Punktwert ×2", "art": "redeem", "multiplikator": 2, "stunden": 1})
s, p = anna.req("GET", "/points")
check("Einlöse-Aktion verdoppelt den Punktwert", p["effective_cents_per_point"] == 2 and p["value_cents"] == p["balance"] * 2, p)
helfer("DELETE", f"/aktionen/{c2['id']}")
s, pub = requests.get(API + "/points/campaigns").status_code, requests.get(API + "/points/campaigns").json()
check("GET /points/campaigns (öffentlich)", s == 200 and any(a["kind"] == "earn" for a in pub), pub)

print("Inhalte und Mitgliedschaft")
s, lessons = ben.req("GET", "/content/lessons?per_page=50")
locked = [l for l in lessons["items"] if l["locked"]]
check("Ben (ohne Mitgliedschaft) sieht gesperrte Lektionen", s == 200 and len(locked) > 0, lessons)
s, d = ben.req("GET", f"/content/item/{locked[0]['id']}")
check("Gesperrte Lektion liefert 403", s == 403 and d["code"] == "vibono_membership_required", d)
helfer("POST", f"/nutzer/{ben.user['id']}/mitgliedschaft", {"aktiv": True})
s, d = ben.req("GET", f"/content/item/{locked[0]['id']}")
check("Nach Mitgliedschaft freigeschaltet", s == 200 and d["content_html"], d)
helfer("POST", f"/nutzer/{ben.user['id']}/mitgliedschaft", {"aktiv": False})
s, rec = anna.req("GET", "/content/recipes?tags=vegan")
check("Rezepte nach Merkmal filtern", s == 200 and len(rec["items"]) >= 2 and all("vegan" in r["tags"] for r in rec["items"]), rec)
s, d = anna.req("GET", f"/content/item/{rec['items'][0]['id']}")
check("Rezept mit Zutaten und Portionen, Zutatenblock entfernt", s == 200 and d["ingredients"] and d["servings"] and d["ingredients_stripped"], d)
s, t = anna.req("GET", "/coaching/today")
check("Coaching heute (Anna, Phase 2, Rezepte aus dem Wochenplan)", s == 200 and t["phase"]["key"] == "phase2" and t["recipes_source"] == "weekplan" and t["next_step"], t)
s, t = ben.req("GET", "/coaching/today")
check("Coaching heute (Ben, Vorbereitung)", s == 200 and t["phase"]["key"] == "vorbereitung", t)
s, t = clara.req("GET", "/coaching/today")
check("Coaching heute (Clara, ohne Startdatum)", s == 200 and t["phase"]["day_label"] == "Startdatum festlegen", t)
s, tod = anna.req("GET", "/content/tips-of-the-day")
check("Tipps des Tages", s == 200 and len(tod["items"]) == 7, tod)

print("Profil")
s, d = clara.req("PUT", "/me/profile", {"onboarding": {"nutrition": {"diet": "vegan"}}, "goals": {"start_weight_kg": 75, "coaching_start_date": time.strftime("%Y-%m-%d")}})
check("Profil speichern", s == 200 and d["onboarding"]["nutrition"]["diet"] == "vegan" and d["goals"]["start_weight_kg"] == 75, d)
s, d = clara.req("PUT", "/me/profile", {"onboarding": {"nutrition": {"diet": "fleisch"}}, "goals": {"height_cm": 20}})
check("Ungültige Angaben → 400 mit Feldern", s == 400 and "nutrition.diet" in d["data"]["fields"] and "goals.height_cm" in d["data"]["fields"], d)
s, t = clara.req("GET", "/coaching/today")
check("Clara nach Startdatum in Phase 1", t["phase"]["key"] == "phase1", t["phase"])

print("Sync")
now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
s, d = anna.req("PUT", "/me/weight", {"changes": [{"key": time.strftime("%Y-%m-%d"), "op": "upsert", "data": {"kg": 80.1}, "updated_at": now}]})
check("Gewicht speichern", s == 200 and d["results"][0]["status"] == "applied", d)
s, d = anna.req("PUT", "/me/weight", {"changes": [{"key": time.strftime("%Y-%m-%d"), "op": "upsert", "data": {"kg": 99}, "updated_at": "2020-01-01T00:00:00Z"}]})
check("Ältere Änderung verliert (stale)", d["results"][0]["status"] == "stale", d)
s, d = anna.req("PUT", "/me/weight", {"changes": [{"key": "gestern", "op": "upsert", "data": {"kg": 80}, "updated_at": now}]})
check("Ungültiger Schlüssel wird abgelehnt", d["results"][0]["status"] == "rejected", d)
s, d = anna.req("PUT", "/me/sport", {"changes": [{"key": str(uuid.uuid4()), "op": "upsert", "data": {"date": time.strftime("%Y-%m-%d"), "activity": "Joggen", "minutes": 25}, "updated_at": now}]})
check("Sport speichern", d["results"][0]["status"] == "applied", d)
s, d = anna.req("GET", "/sync")
check("GET /sync liefert Änderungen und Cursor", s == 200 and len(d["changes"]) > 5 and d["cursor"].startswith("v1."), d)
s, d2 = anna.req("GET", "/sync?cursor=" + d["cursor"])
check("Sync mit Cursor liefert nur Neues", s == 200 and len(d2["changes"]) == 0, d2)

print("Freunde werben")
s, info = anna.req("GET", "/referral")
check("GET /referral", s == 200 and info["code"] == "ANNA7K", info)
r = requests.get(API + "/referral/validate?code=ANNA7K").json()
check("Code prüfen", r["valid"] and r["referrer_first_name"] == "Anna", r)
mail = f"freundin-{uuid.uuid4().hex[:6]}@vibono-test.local"
r = requests.post(API + "/auth/register", json={"email": mail, "password": PW, "first_name": "Frieda", "referral_code": "ANNA7K", "accept_privacy": True})
check("Registrierung mit Code", r.status_code == 201, r.text[:300])
frieda = App(mail)
s, o = helfer("POST", "/bestellungen", {"user_id": frieda.user["id"], "betrag_eur": 10})
check("Bestellung unter Mindestwert: keine Empfehlungspunkte", not any(x["grund"] == "referral" for x in o["punkte"]), o)
mail2 = f"freund-{uuid.uuid4().hex[:6]}@vibono-test.local"
requests.post(API + "/auth/register", json={"email": mail2, "password": PW, "first_name": "Fritz", "referral_code": "ANNA7K", "accept_privacy": True})
fritz = App(mail2)
s, o = helfer("POST", "/bestellungen", {"user_id": fritz.user["id"], "betrag_eur": 40})
gr = {x["grund"]: x for x in o["punkte"]}
check("Erste Bestellung ≥ 15 €: 500 für Anna, 200 für Fritz, vorgemerkt", gr.get("referral", {}).get("punkte") == 500 and gr.get("referral_friend", {}).get("punkte") == 200 and gr["referral"]["status"] == "pending", o)
check("Einkaufspunkte für Fritz (5 je €) vorgemerkt", gr.get("purchase", {}).get("punkte") == 200 and gr["purchase"]["status"] == "pending", o)
s, o2 = helfer("POST", "/bestellungen", {"user_id": fritz.user["id"], "betrag_eur": 40})
check("Zweite Bestellung: keine weiteren Empfehlungspunkte", not any(x["grund"] in ("referral", "referral_friend") for x in o2["punkte"]), o2)
helfer("POST", "/frist-ueberspringen", {})
s, o2b = helfer("POST", f"/bestellungen/{o2['id']}/status", {"status": "completed"})
s, x = helfer("GET", f"/bestellungen?user_id={fritz.user['id']}")
still = [b for b in x if b["id"] == o["id"]][0]
check("Einkaufspunkte bleiben vorgemerkt, solange die Bestellung nicht abgeschlossen ist", all(p["status"] == "pending" for p in still["punkte"] if p["grund"] == "purchase"), still)
# Beobachtung für den Entwickler: Empfehlungspunkte zählen die Frist ab Zahlung, Einkaufspunkte ab "abgeschlossen".
ref = [p["status"] for p in still["punkte"] if p["grund"] in ("referral", "referral_friend")]
print(f"  ℹ Empfehlungspunkte nach Fristablauf bei nicht abgeschlossener Bestellung: {', '.join(ref)} (Frist läuft ab Zahlung)")
helfer("POST", f"/bestellungen/{o['id']}/status", {"status": "completed"})
helfer("POST", "/frist-ueberspringen", {})
s, x = helfer("GET", f"/bestellungen?user_id={fritz.user['id']}")
done = [b for b in x if b["id"] == o["id"]][0]
check("Abgeschlossen + Frist vorbei: alles bestätigt", all(p["status"] == "confirmed" for p in done["punkte"]), done)
s, info2 = anna.req("GET", "/referral")
check("Statistik zählt Werbung", info2["converted"] >= 2 and info2["invited"] >= 3, info2)
s, o3 = helfer("POST", f"/bestellungen/{o['id']}/status", {"status": "refunded"})
check("Erstattung storniert alle Punkte der Bestellung", all(p["status"] == "void" for p in o3["punkte"]), o3)
mail3 = f"selbst-{uuid.uuid4().hex[:6]}@vibono-test.local"
requests.post(API + "/auth/register", json={"email": mail3, "password": PW, "first_name": "Selbst", "referral_code": "ANNA7K", "accept_privacy": True})
selbst = App(mail3)
s, o4 = helfer("POST", "/bestellungen", {"user_id": selbst.user["id"], "betrag_eur": 50, "adresse": ["Lindenweg 3", "50667", "Köln"]})
check("Gleiche Adresse wie Anna gilt als Selbstwerbung: keine Empfehlungspunkte", not any(x["grund"] in ("referral", "referral_friend") for x in o4["punkte"]), o4)

print("Einkaufen")
s, o = helfer("POST", "/bestellungen", {"user_id": ben.user["id"], "betrag_eur": 39.90, "status": "on-hold"})
check("Unbezahlte Bestellung: keine Punkte", not o["punkte"], o)
s, o = helfer("POST", f"/bestellungen/{o['id']}/status", {"status": "processing"})
check("Bezahlt: 199 Punkte vorgemerkt", any(p["grund"] == "purchase" and p["punkte"] == 199 and p["status"] == "pending" for p in o["punkte"]), o)
s, o = helfer("POST", f"/bestellungen/{o['id']}/status", {"status": "cancelled"})
check("Storniert: Punkte verfallen", all(p["status"] == "void" for p in o["punkte"]), o)

print("Lesen (dauert etwa eine Minute)")
s, tips = anna.req("GET", "/content/tips?per_page=50")
ohne_quiz = [t for t in tips["items"] if t["title"].startswith("Spazierengehen")][0]
mit_quiz = [t for t in tips["items"] if t["title"].startswith("Abnehmen in 3 Phasen")][0]
s, st = anna.req("POST", "/reading/start", {"post_id": ohne_quiz["id"]})
s, early = anna.req("POST", "/reading/complete", {"session_id": st["session_id"]})
check("Sofort abschließen wird abgelehnt (422)", s == 422 and early["code"] == "vibono_reading_incomplete", early)
s, r, _ = lesen(anna, ohne_quiz["id"], scroll=0.5)
check("Nicht zu Ende gescrollt wird abgelehnt", s == 422 and "scroll_depth" in r["data"]["progress"]["missing"], r)
s, r, _ = lesen(anna, ohne_quiz["id"])
check("Zu Ende gelesen: 10 Punkte ×2 (Lesewoche) = 20", s == 200 and r["awarded_points"] == 20 and r["multiplier"] == 2, r)
s, r = anna.req("POST", "/reading/start", {"post_id": ohne_quiz["id"]})
check("Derselbe Artikel nicht zweimal", s == 409, r)
s, r, sid = lesen(anna, mit_quiz["id"], quiz=0)
check("Falsche Quizantwort wird abgelehnt", s == 422 and r["code"] == "vibono_quiz_wrong", r)
time.sleep(31)
s, r = anna.req("POST", "/reading/complete", {"session_id": sid, "quiz_answer": 1})
check("Richtige Quizantwort nach Wartezeit: Punkte", s == 200 and r["awarded_points"] == 20, r)

print("Energiedichte")
s, f = anna.req("GET", "/foods?q=Gur")
check("Lebensmittelsuche", s == 200 and f["items"] and f["items"][0]["kcal_per_100g"] == 12, f)
png = base64.b64encode(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")).decode()
s, d = anna.req("POST", "/energy-density/analyze-photo", {"image_base64": png, "mime": "image/png"})
check("Foto-Schätzung (Simulation ohne Schlüssel)", s == 200 and d["kcal_per_g"] == 1.1, d)
s, d = anna.req("POST", "/energy-density/scan-recipe", {"image_base64": png, "mime": "image/png"})
check("Rezept-Scan (Simulation)", s == 200 and d["kcal_per_g"] is not None, d)
s, d = anna.req("POST", "/energy-density/analyze-photo", {"image_base64": png, "mime": "image/gif"})
check("Falsches Bildformat → 400", s == 400, d)

print("Konto")
helfer("DELETE", "/mails")
requests.post(API + "/auth/password-reset", json={"email": "clara@vibono-test.local"})
s, m = helfer("GET", "/mails")
check("Passwort vergessen: E-Mail abgefangen", len(m) == 1 and "clara@vibono-test.local" in m[0]["to"], m)
s, d = clara.req("POST", "/me/devices", {"token": "push-" + uuid.uuid4().hex, "platform": "android"})
check("Push-Gerät anmelden", s in (200, 201), d)
s, d = clara.req("POST", "/auth/web-session", {"redirect": "/warenkorb/"})
check("Einmal-Link für die Website", s == 200 and "vibono_login=" in d["url"], d)
s, d = clara.req("DELETE", "/me")
check("Kontolöschung beantragen (202)", s == 202, d)
s, d = clara.req("POST", "/auth/logout", {"refresh_token": clara.t["refresh_token"]})
r = requests.post(API + "/auth/refresh", json={"refresh_token": clara.t["refresh_token"]})
check("Nach Abmelden ist das Refresh-Token ungültig", r.status_code in (401, 403), r.text[:200])

print("Schutz")
r = requests.get(API + "/me")
check("Ohne Token kein Zugriff", r.status_code == 401, r.text[:200])
r = requests.get(API + "/me", headers={"Authorization": "Bearer abc.def.ghi"})
check("Gefälschtes Token wird abgelehnt", r.status_code in (401, 403), r.text[:200])
r = requests.get(BASE + "/wp-content/database/.ht.sqlite")
check("Datenbankdatei ist nicht abrufbar", r.status_code == 403)

print()
if fehler:
    print(f"{len(fehler)} Prüfung(en) fehlgeschlagen:")
    for f in fehler:
        print("  - " + f)
    sys.exit(1)
print("Alle Prüfungen bestanden.")
