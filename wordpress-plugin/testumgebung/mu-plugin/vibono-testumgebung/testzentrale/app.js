/* Vibono Testzentrale: ruft die Schnittstelle des Plugins so auf wie die App (Token-Anmeldung, /wp-json/vibono/v1/…).
 * Testhelfer (/wp-json/vibono-test/v1/…) stellen nach, was sonst von außen passiert: Bestellungen, Zeit, Mitgliedschaft. */
(function () {
	'use strict';

	// ------------------------------------------------------------ Zustand
	const S = {
		bereich: 'start',
		status: null,
		nutzer: [],
		person: null, // aktuell gewählte Person (Objekt aus /nutzer)
		tokens: {},   // user_id -> { access_token, refresh_token }
		protokoll: [],
		lesen: null,  // laufende Lese-Session
	};
	try { S.bereich = localStorage.getItem('vt_bereich') || 'start'; } catch (e) { /* egal */ }

	const BEREICHE = [
		['start', '🏠', 'Start'],
		['-', '', 'Punkte'],
		['punkte', '⭐', 'Punktekonto'],
		['lesen', '📖', 'Lesen & Lesepunkte'],
		['werben', '🤝', 'Freunde werben'],
		['shop', '🛒', 'Shop & Bestellungen'],
		['aktionen', '🎉', 'Aktionen'],
		['-', '', 'App-Funktionen'],
		['heute', '📅', 'Coaching heute'],
		['inhalte', '🥗', 'Inhalte & Rezepte'],
		['daten', '🔄', 'Meine Daten (Sync)'],
		['profil', '👤', 'Profil & Konto'],
		['energie', '⚖️', 'Energiedichte'],
		['config', '⚙️', 'App-Einstellungen'],
		['-', '', 'Werkzeuge'],
		['mails', '✉️', 'E-Mails'],
		['protokoll', '🧾', 'Protokoll & API-Konsole'],
	];

	// ------------------------------------------------------------ Hilfen
	const $ = (sel, el) => (el || document).querySelector(sel);
	const $$ = (sel, el) => Array.from((el || document).querySelectorAll(sel));
	const h = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
	const euro = (cent) => (cent / 100).toLocaleString('de-DE', { style: 'currency', currency: 'EUR' });
	const zahl = (n) => Number(n || 0).toLocaleString('de-DE');
	const heute = () => { const d = new Date(); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); };
	const datum = (iso) => iso ? new Date(iso).toLocaleString('de-DE', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '–';
	const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : 'id-' + Date.now() + '-' + Math.random().toString(16).slice(2));
	const GRUENDE = { app_open: 'App geöffnet', article_read: 'Artikel gelesen', referral: 'Kund*in geworben', referral_friend: 'Willkommensbonus', purchase: 'Einkauf', redeem: 'Eingelöst', redeem_refund: 'Einlösung zurück', admin: 'Manuelle Buchung', migration: 'Übernahme Refer-a-friend', expire: 'Verfallen' };
	const STATUS = { confirmed: ['bestätigt', 'gruen'], pending: ['vorgemerkt', 'gelb'], void: ['storniert', 'rot'] };

	function hinweis(text, fehler) {
		const el = $('#hinweis');
		el.textContent = text;
		el.className = 'hinweis' + (fehler ? ' fehler' : '');
		el.hidden = false;
		clearTimeout(hinweis.t);
		hinweis.t = setTimeout(() => { el.hidden = true; }, 4500);
	}

	// ------------------------------------------------------------ Anfragen
	async function anfrage(basis, methode, pfad, body, opt) {
		opt = opt || {};
		const url = basis + pfad;
		const headers = { Accept: 'application/json' };
		if (body !== undefined) headers['Content-Type'] = 'application/json';
		if (opt.token) headers.Authorization = 'Bearer ' + opt.token;
		const start = performance.now();
		let status = 0, data = null, gesamt = null;
		try {
			// credentials: 'omit' – wie die App: keine Website-Cookies, nur das Token.
			const res = await fetch(url, { method: methode, headers, body: body === undefined ? undefined : JSON.stringify(body), credentials: 'omit' });
			status = res.status;
			gesamt = res.headers.get('X-WP-Total');
			const text = await res.text();
			try { data = text ? JSON.parse(text) : null; } catch (e) { data = { roh: text.slice(0, 2000) }; }
		} catch (e) {
			data = { message: 'Keine Verbindung zur Testumgebung. Läuft das Fenster „Vibono-Testumgebung“ noch?' };
		}
		const eintrag = { zeit: new Date(), methode, pfad: url.replace(location.origin, ''), status, ms: Math.round(performance.now() - start), anfrage: body, antwort: data, person: opt.person || null, helfer: basis === VT.test };
		S.protokoll.unshift(eintrag);
		S.protokoll.length = Math.min(S.protokoll.length, 200);
		return { ok: status >= 200 && status < 300, status, data, gesamt: gesamt === null ? null : Number(gesamt) };
	}

	const helfer = (methode, pfad, body) => anfrage(VT.test, methode, pfad, body);

	async function anmelden(p) {
		const r = await anfrage(VT.api, 'POST', '/auth/login', { username: p.email, password: p.testpasswort || 'vibono-test', device_name: 'Testzentrale' }, { person: p.name });
		if (r.ok) S.tokens[p.id] = r.data;
		return r;
	}

	/** Aufruf als gewählte Person – wie die App mit Bearer-Token, bei Ablauf mit Refresh-Token. */
	async function api(methode, pfad, body, opt) {
		opt = opt || {};
		if (opt.ohneAnmeldung) return anfrage(VT.api, methode, pfad, body);
		const p = S.person;
		if (!p) return { ok: false, status: 0, data: { message: 'Bitte oben eine Person wählen.' } };
		if (!S.tokens[p.id]) {
			const l = await anmelden(p);
			if (!l.ok) return l;
		}
		let r = await anfrage(VT.api, methode, pfad, body, { token: S.tokens[p.id].access_token, person: p.name });
		if (r.status === 401 && S.tokens[p.id] && S.tokens[p.id].refresh_token) {
			const f = await anfrage(VT.api, 'POST', '/auth/refresh', { refresh_token: S.tokens[p.id].refresh_token }, { person: p.name });
			if (f.ok) {
				S.tokens[p.id] = f.data;
				r = await anfrage(VT.api, methode, pfad, body, { token: S.tokens[p.id].access_token, person: p.name });
			} else {
				delete S.tokens[p.id];
			}
		}
		return r;
	}

	function meldung(r) {
		if (!r) return '';
		const d = r.data || {};
		return d.message || (d.code ? d.code : '') || (r.ok ? 'OK' : 'Fehler ' + r.status);
	}

	/** Ergebnis-Box: Klartext + aufklappbare Rohdaten. */
	function ergebnis(r, text) {
		const ok = r && r.ok;
		const txt = text || (ok ? 'Erfolgreich.' : meldung(r));
		return '<div class="ergebnis' + (ok ? '' : ' fehler') + '"><strong>' + (ok ? '✅ ' : '⚠️ ') + h(txt) + '</strong>' +
			(r ? ' <small>HTTP ' + h(r.status) + '</small><details><summary>Antwort der Schnittstelle</summary><pre>' + h(JSON.stringify(r.data, null, 2)) + '</pre></details>' : '') + '</div>';
	}

	function zeige(ziel, html) {
		const el = typeof ziel === 'string' ? $(ziel) : ziel;
		if (el) el.innerHTML = html;
	}

	// ------------------------------------------------------------ Kopf: Person
	async function nutzerLaden() {
		const r = await helfer('GET', '/nutzer');
		if (!r.ok) return;
		S.nutzer = r.data.filter((u) => !u.admin);
		const gemerkt = (() => { try { return Number(localStorage.getItem('vt_person')); } catch (e) { return 0; } })();
		const id = S.person ? S.person.id : gemerkt;
		S.person = S.nutzer.find((u) => u.id === id) || S.nutzer[0] || null;
		kopf();
	}

	function kopf() {
		const p = S.person;
		zeige('#person',
			'<label style="margin:0"><select id="personwahl" title="Als wer soll die Testzentrale die App bedienen?">' +
			S.nutzer.map((u) => '<option value="' + u.id + '"' + (p && u.id === p.id ? ' selected' : '') + '>' + h(u.name) + ' · ' + h(u.email) + '</option>').join('') +
			'</select></label>' +
			(p ? '<span class="marke ' + (p.mitglied ? 'gruen' : '') + '">' + (p.mitglied ? 'Coaching-Mitglied' : 'ohne Mitgliedschaft') + '</span>' +
				'<span class="marke blau">' + zahl(p.punkte) + ' Punkte</span>' +
				(p.vorgemerkt ? '<span class="marke gelb">' + zahl(p.vorgemerkt) + ' vorgemerkt</span>' : '') : ''));
		const sel = $('#personwahl');
		if (sel) sel.onchange = () => {
			S.person = S.nutzer.find((u) => u.id === Number(sel.value));
			try { localStorage.setItem('vt_person', String(S.person.id)); } catch (e) { /* egal */ }
			stopLesen();
			kopf();
			zeichnen();
		};
	}

	async function personAktualisieren() {
		await nutzerLaden();
	}

	// ------------------------------------------------------------ Menü
	function menue() {
		zeige('#menue', BEREICHE.map((b) => b[0] === '-' ? '<div class="trenner">' + h(b[2]) + '</div>' :
			'<button data-b="' + b[0] + '" class="' + (S.bereich === b[0] ? 'aktiv' : '') + '"><span>' + b[1] + '</span>' + h(b[2]) + '</button>').join(''));
		$$('#menue button').forEach((b) => b.onclick = () => {
			S.bereich = b.dataset.b;
			try { localStorage.setItem('vt_bereich', S.bereich); } catch (e) { /* egal */ }
			stopLesen();
			menue();
			zeichnen();
			window.scrollTo(0, 0);
		});
	}

	function zeichnen() {
		const f = SEITEN[S.bereich] || SEITEN.start;
		const el = $('#inhalt');
		el.innerHTML = '<p class="leise">Lädt …</p>';
		Promise.resolve(f(el)).catch((e) => { el.innerHTML = '<div class="ergebnis fehler">Fehler in der Testzentrale: ' + h(e.message) + '</div>'; console.error(e); });
	}

	function personName() { return S.person ? h(S.person.name) : '–'; }

	// ============================================================ Seiten
	const SEITEN = {};

	// ------------------------------------------------------------ Start
	SEITEN.start = async (el) => {
		const r = await helfer('GET', '/status');
		if (!r.ok) { el.innerHTML = ergebnis(r, 'Status konnte nicht geladen werden. Ist das Plugin aktiv?'); return; }
		const s = S.status = r.data;
		const m = s.module;
		const modul = (k, t) => '<tr><td>' + h(t) + '</td><td>' + (m[k] ? '<span class="marke gruen">an</span>' : '<span class="marke">aus</span>') + '</td></tr>';
		const w = s.werte;
		el.innerHTML = `
			<h1>Willkommen in der Testzentrale</h1>
			<p>Hier probierst du alle Funktionen des WordPress-Plugins aus, ohne vibono.de zu berühren. Alles läuft in einem kleinen WordPress auf deinem Rechner, mit Testkonten, Rezepten, Lektionen und einem Test-Shop.</p>
			<div class="karte gruen">
				<h2>So funktioniert es</h2>
				<ol>
					<li><strong>Oben rechts eine Person wählen</strong> (Anna, Ben, Clara oder neu registrierte Konten). Die Testzentrale meldet sich als diese Person an, genau wie die App.</li>
					<li><strong>Links einen Bereich öffnen</strong> und Knöpfe drücken. Jeder Knopf ruft die echte Schnittstelle des Plugins auf. Unter „Antwort der Schnittstelle“ siehst du, was die App bekommen würde.</li>
					<li>Dinge, die sonst von außen passieren (jemand bestellt im Shop, 14 Tage Widerrufsfrist vergehen, ein neuer Tag beginnt), stellen gelb markierte <span class="marke gelb">Testhelfer</span> nach.</li>
					<li>Einstellungen wie Punktwerte, Umrechnungskurs und Aktionen änderst du im echten Backend des Plugins: <a href="${h(s.links.punkte)}" target="_blank">Vibono-Punkte</a> (Anmeldung: <code>admin</code> / <code>vibono-test</code>).</li>
					<li>Alles wieder auf Anfang: Testumgebung schließen und <code>Zuruecksetzen.bat</code> starten.</li>
				</ol>
			</div>
			<div class="raster">
				<div class="karte"><h2>Testkonten</h2>
					<table><tbody>${S.nutzer.map((u) => `<tr><td><strong>${h(u.name)}</strong><br><small>${h(u.email)}</small></td><td><small>${h(u.beschreibung || '')}</small></td></tr>`).join('')}</tbody></table>
					<p class="leise" style="margin-top:.5rem">Passwort für alle Testkonten: <code>vibono-test</code></p>
				</div>
				<div class="karte"><h2>Plugin</h2>
					<table><tbody>
						<tr><td>Version</td><td>${h(s.plugin.version)}</td></tr>
						${modul('module_api', 'App-Schnittstelle')}
						${modul('module_shop', 'Punkte im Shop')}
						${modul('module_referral', 'Freunde werben')}
						${modul('module_web_reading', 'Lesepunkte auf der Website')}
						${modul('points_enabled', 'Punktesystem')}
					</tbody></table>
					<div class="knopfreihe"><a class="knopf zweit klein" href="${h(s.links.module)}" target="_blank">Module ein-/ausschalten</a><a class="knopf zweit klein" href="${h(s.links.regeln)}" target="_blank">Punktwerte ändern</a></div>
					${s.letzter_fehler ? '<div class="ergebnis fehler">Letzter abgefangener Fehler: ' + h(s.letzter_fehler) + '</div>' : ''}
				</div>
				<div class="karte"><h2>Aktuelle Punktwerte</h2>
					<table><tbody>
						<tr><td>1 Punkt</td><td>${h(w.cents_per_point)} Cent</td></tr>
						<tr><td>App täglich öffnen</td><td>${h(w.earn_app_open)} Punkte</td></tr>
						<tr><td>Artikel gelesen</td><td>${h(w.earn_article_read)} Punkte (max. ${h(w.article_read_daily_cap)} pro Tag)</td></tr>
						<tr><td>Kund*in geworben</td><td>${h(w.earn_referral)} Punkte, Geworbene ${h(w.earn_referral_friend)} (ab ${euro(w.referral_min_order_cents)})</td></tr>
						<tr><td>Einkauf</td><td>${h(w.earn_purchase_per_euro)} Punkte je Euro</td></tr>
						<tr><td>Widerrufsfrist</td><td>${h(w.pending_days)} Tage</td></tr>
						<tr><td>Einlösen</td><td>ab ${h(w.min_redeem_points)} Punkten, max. ${h(w.max_redeem_percent)} % des Warenkorbs</td></tr>
					</tbody></table>
					<p class="leise">Vorschläge, noch nicht von Vibono bestätigt.</p>
				</div>
				<div class="karte"><h2>Mit dem Handy verbinden</h2>
					<p>Am PC: <a href="${h(s.adressen.pc)}/testzentrale/">${h(s.adressen.pc)}</a></p>
					${(s.adressen.wlan || []).length ? '<p>Im selben WLAN (Handy, Tablet):<br>' + s.adressen.wlan.map((a) => '<code>' + h(a) + '</code>').join('<br>') + '</p><p class="leise">Schnittstelle für die App: <code>' + h((s.adressen.wlan || [])[0]) + '/wp-json/vibono/v1</code>. Fragt Windows beim Start nach dem Netzwerkzugriff, „Zugriff zulassen“ wählen.</p>' : '<p class="leise">Keine WLAN-Adresse gefunden.</p>'}
				</div>
				<div class="karte"><h2>Schnell öffnen</h2>
					<div class="knopfreihe">
						<a class="knopf zweit klein" href="${h(s.links.backend)}" target="_blank">Backend</a>
						<a class="knopf zweit klein" href="${h(s.links.punkte)}" target="_blank">Vibono-Punkte</a>
						<a class="knopf zweit klein" href="${h(s.links.aktionen)}" target="_blank">Aktionen</a>
						<a class="knopf zweit klein" href="${h(s.links.buchen)}" target="_blank">Punkte buchen</a>
						<a class="knopf zweit klein" href="${h(s.links.schnittstelle)}" target="_blank">App-Schnittstelle</a>
						<a class="knopf zweit klein" href="${h(s.links.bestellungen)}" target="_blank">Bestellungen</a>
						<a class="knopf zweit klein" href="${h(s.links.shop)}" target="_blank">Shop</a>
						<a class="knopf zweit klein" href="${h(s.links.tipps)}" target="_blank">Vibono-Tipps (Website)</a>
					</div>
				</div>
			</div>`;
	};

	// ------------------------------------------------------------ Punkte
	SEITEN.punkte = async (el) => {
		const [sum, led] = await Promise.all([api('GET', '/points'), api('GET', '/points/ledger?per_page=50')]);
		if (!sum.ok) { el.innerHTML = '<h1>Punktekonto</h1>' + ergebnis(sum); return; }
		const s = sum.data;
		const regeln = Object.entries(s.earn_rules || {}).map(([k, v]) => '<tr><td>' + h(GRUENDE[k] || k) + '</td><td class="zahl-rechts">' + zahl(v) + (k === 'purchase' ? ' je €' : '') + '</td></tr>').join('');
		const akt = (s.campaigns || []).map((c) => '<li><span>' + (c.active ? '<span class="marke gruen">läuft</span> ' : '<span class="marke">demnächst</span> ') + h(c.name) + ' <small>×' + h(c.multiplier) + '</small></span><small>' + datum(c.starts_at) + ' – ' + datum(c.ends_at) + '</small></li>').join('');
		el.innerHTML = `
			<h1>Punktekonto von ${personName()}</h1>
			<div class="zahlen">
				<div class="zahl gruen"><b>${zahl(s.balance)}</b><span>Punkte verfügbar</span></div>
				<div class="zahl"><b>${zahl(s.pending)}</b><span>vorgemerkt (Widerrufsfrist)</span></div>
				<div class="zahl"><b>${euro(s.value_cents)}</b><span>Wert im Shop</span></div>
				<div class="zahl"><b>${h(s.effective_cents_per_point)} ct</b><span>Wert je Punkt${s.effective_cents_per_point !== s.cents_per_point ? ' (Aktion!)' : ''}</span></div>
			</div>
			<div class="raster">
				<div class="karte"><h2>App täglich öffnen</h2>
					<p>Die App meldet beim Öffnen <code>POST /points/app-open</code>. Pro Tag gibt es einmal Punkte, ein zweiter Aufruf bringt nichts.</p>
					<div class="knopfreihe"><button id="oeffnen">📱 App öffnen</button></div>
					<div class="knopfreihe"><button class="zweit klein" id="tag">⏩ Einen Tag vorspulen</button><span class="marke gelb">Testhelfer</span></div>
					<p class="leise">„Einen Tag vorspulen“ legt die heutigen Buchungen dieser Person auf gestern und zählt den Coaching-Tag eins weiter. Danach gibt es wieder Punkte fürs Öffnen und neue Lesepunkte.</p>
					<div id="oeffnen-erg"></div>
				</div>
				<div class="karte"><h2>So viele Punkte gibt es gerade</h2><table><tbody>${regeln}</tbody></table>
					<h3>Aktionen</h3>${akt ? '<ul class="liste">' + akt + '</ul>' : '<p class="leise">Keine laufende oder geplante Aktion.</p>'}
				</div>
			</div>
			<div class="karte"><h2>Buchungen</h2>
				<div class="knopfreihe"><button class="zweit klein" id="frist">⏩ Widerrufsfrist überspringen</button><span class="marke gelb">Testhelfer</span><small class="leise">Bestätigt vorgemerkte Punkte, deren Frist läuft (Einkäufe erst nach „abgeschlossen“).</small></div>
				${led.ok ? tabelleBuchungen(led.data.items || []) : ergebnis(led)}
			</div>`;
		$('#oeffnen').onclick = async () => {
			const r = await api('POST', '/points/app-open');
			const d = r.data || {};
			const text = r.ok ? (d.already_awarded ? 'Heute schon belohnt – keine weiteren Punkte.' : '+' + d.awarded_points + ' Punkte' + (d.multiplier > 1 ? ' (×' + d.multiplier + ' durch Aktion)' : '') + '. Neuer Kontostand: ' + zahl(d.balance)) : null;
			await personAktualisieren();
			await SEITEN.punkte(el);
			zeige('#oeffnen-erg', ergebnis(r, text));
		};
		$('#tag').onclick = async () => {
			const r = await helfer('POST', '/nutzer/' + S.person.id + '/tag-vorspulen');
			hinweis(r.ok ? 'Einen Tag weiter. ' + r.data.verschoben + ' Buchungen von heute liegen jetzt auf gestern.' : meldung(r), !r.ok);
			await personAktualisieren();
			SEITEN.punkte(el);
		};
		$('#frist').onclick = async () => {
			const r = await helfer('POST', '/frist-ueberspringen', { user_id: S.person.id });
			hinweis(r.ok ? r.data.bestaetigt + ' Buchungen bestätigt.' : meldung(r), !r.ok);
			await personAktualisieren();
			SEITEN.punkte(el);
		};
	};

	function tabelleBuchungen(items) {
		if (!items.length) return '<p class="leise">Noch keine Buchungen.</p>';
		return '<table><thead><tr><th>Datum</th><th>Was</th><th>Grund</th><th>Status</th><th class="zahl-rechts">Punkte</th></tr></thead><tbody>' +
			items.map((e) => {
				const st = STATUS[e.status] || [e.status, ''];
				return '<tr><td>' + datum(e.created_at) + '</td><td>' + h(e.label) + (e.multiplier > 1 ? ' <span class="marke gruen">×' + h(e.multiplier) + ' Aktion</span>' : '') + '</td><td>' + h(GRUENDE[e.reason] || e.reason) + '</td><td><span class="marke ' + st[1] + '">' + h(st[0]) + '</span>' + (e.status === 'pending' && e.confirms_at ? '<br><small>bis ' + datum(e.confirms_at) + '</small>' : '') + '</td><td class="zahl-rechts"><strong>' + (e.points > 0 ? '+' : '') + zahl(e.points) + '</strong></td></tr>';
			}).join('') + '</tbody></table>';
	}

	// ------------------------------------------------------------ Lesen
	function stopLesen() {
		if (S.lesen && S.lesen.timer) clearInterval(S.lesen.timer);
		S.lesen = null;
	}

	SEITEN.lesen = async (el) => {
		const [tips, lessons, recipes] = await Promise.all([api('GET', '/content/tips?per_page=50'), api('GET', '/content/lessons?per_page=50'), api('GET', '/content/recipes?per_page=50')]);
		const alle = [].concat(tips.ok ? tips.data.items : [], lessons.ok ? lessons.data.items : [], recipes.ok ? recipes.data.items : []);
		const typ = { tip: 'Tipp', lesson: 'Lektion', recipe: 'Rezept' };
		el.innerHTML = `
			<h1>Lesen & Lesepunkte</h1>
			<p>So prüft das Plugin, ob ${personName()} einen Artikel wirklich gelesen hat: Die App startet eine Lese-Session, meldet alle paar Sekunden, dass der Artikel sichtbar ist und wie weit gescrollt wurde, und schließt dann ab. Der Server zählt nur Zeit, die wirklich vergangen ist. Wo hinterlegt, kommt eine Quizfrage.</p>
			${!tips.ok ? ergebnis(tips) : ''}
			<div class="zweispaltig">
				<div class="karte"><h2>Artikel wählen</h2>
					<ul class="liste liste-klick">${alle.map((a) => `<li data-id="${a.id}"><span><span class="marke">${h(typ[a.type] || a.type)}</span> ${h(a.title)} ${a.locked ? '<span class="marke rot">🔒 nur Mitglieder</span>' : ''}</span><span>${a.points_for_reading ? '<span class="marke gruen">+' + a.points_for_reading + '</span>' : '<span class="marke">schon gelesen</span>'}</span></li>`).join('')}</ul>
				</div>
				<div class="karte" id="leser"><h2>Lese-Simulator</h2><p class="leise">Links einen Artikel wählen.</p></div>
			</div>
			<div class="karte gelb"><strong>Auf der Website:</strong> Lesepunkte gibt es auch beim Lesen auf der Website (Modul „Lesepunkte auf der Website“). Öffne dazu einen Tipp unter <a href="/tipps/" target="_blank">Vibono-Tipps</a>, während du als Testperson im Browser angemeldet bist (Shop-Bereich → „Im Shop als … anmelden“), und lies bis zum Ende.</div>`;
		$$('#inhalt .liste-klick li').forEach((li) => li.onclick = () => leseStart(Number(li.dataset.id)));
	};

	async function leseStart(id) {
		stopLesen();
		const box = $('#leser');
		box.innerHTML = '<h2>Lese-Simulator</h2><p class="leise">Lädt …</p>';
		const item = await api('GET', '/content/item/' + id);
		if (!item.ok) { box.innerHTML = '<h2>Lese-Simulator</h2>' + ergebnis(item); return; }
		const st = await api('POST', '/reading/start', { post_id: id, channel: 'app' });
		const d = st.data || {};
		box.innerHTML = `<h2>${h(item.data.title)}</h2>
			${st.ok ? '' : ergebnis(st)}
			<div class="artikel" id="artikeltext">${item.data.content_html || ''}</div>
			${st.ok ? `
			<div style="margin-top:.75rem">
				<small>Aktive Lesezeit (vom Server anerkannt): <b id="zeit">0</b> von ${d.min_active_seconds} s</small>
				<div class="balken"><i id="zeitbalken" style="width:0"></i></div>
				<small>Scrolltiefe: <b id="scroll">0</b> % von ${Math.round(d.min_scroll_depth * 100)} %</small>
				<div class="balken"><i id="scrollbalken" style="width:0"></i></div>
			</div>
			<div class="knopfreihe">
				<label class="check"><input type="checkbox" id="sichtbar" checked> Artikel ist sichtbar (App im Vordergrund)</label>
				<small class="leise">Meldung alle ${d.heartbeat_interval_seconds} s · ${d.word_count} Wörter · ${d.points} Punkte möglich</small>
			</div>
			${d.quiz ? '<div class="karte gelb"><strong>Quizfrage:</strong> ' + h(d.quiz.question) + '<div>' + d.quiz.answers.map((a, i) => '<label class="check"><input type="radio" name="quiz" value="' + i + '"> ' + h(a) + '</label>').join('<br>') + '</div></div>' : ''}
			<div class="knopfreihe"><button id="fertig">✅ Lesen abschließen</button><small class="leise">Zu früh abschließen ist erlaubt – dann siehst du die Ablehnung des Servers.</small></div>
			<div id="lese-erg"></div>` : ''}`;
		if (!st.ok) return;
		const txt = $('#artikeltext');
		S.lesen = { id: d.session_id, tiefe: 0, letzte: Date.now(), aktiv: 0 };
		const tiefe = () => {
			const max = txt.scrollHeight - txt.clientHeight;
			const t = max <= 0 ? 1 : (txt.scrollTop + txt.clientHeight) / txt.scrollHeight;
			S.lesen.tiefe = Math.max(S.lesen.tiefe, Math.min(1, t));
			$('#scroll').textContent = Math.round(S.lesen.tiefe * 100);
			$('#scrollbalken').style.width = Math.round(Math.min(1, S.lesen.tiefe / d.min_scroll_depth) * 100) + '%';
		};
		txt.onscroll = tiefe;
		tiefe();
		S.lesen.timer = setInterval(async () => {
			if (!S.lesen || !$('#sichtbar') || !$('#sichtbar').checked || document.hidden) { if (S.lesen) S.lesen.letzte = Date.now(); return; }
			// Die App meldet die gesamte aktive Lesezeit seit Start; der Server erkennt nur an, was wirklich vergangen ist.
			S.lesen.aktiv += Math.round((Date.now() - S.lesen.letzte) / 1000);
			S.lesen.letzte = Date.now();
			const r = await api('POST', '/reading/heartbeat', { session_id: S.lesen.id, active_seconds: S.lesen.aktiv, scroll_depth: Math.round(S.lesen.tiefe * 1000) / 1000 });
			if (r.ok && $('#zeit')) {
				$('#zeit').textContent = r.data.accepted_active_seconds;
				$('#zeitbalken').style.width = Math.min(100, Math.round(r.data.accepted_active_seconds / d.min_active_seconds * 100)) + '%';
				if (r.data.ready_to_complete) $('#fertig').textContent = '✅ Lesen abschließen – alles erfüllt';
			}
		}, d.heartbeat_interval_seconds * 1000);
		$('#fertig').onclick = async () => {
			const q = $('input[name=quiz]:checked');
			const r = await api('POST', '/reading/complete', { session_id: S.lesen.id, quiz_answer: q ? Number(q.value) : null });
			const x = r.data || {};
			let text = null;
			if (r.ok) text = x.already_awarded ? 'Für diesen Artikel gab es schon Punkte.' : '+' + x.awarded_points + ' Punkte' + (x.multiplier > 1 ? ' (×' + x.multiplier + ' durch „' + (x.campaign ? x.campaign.name : 'Aktion') + '“)' : '') + '. Neuer Kontostand: ' + zahl(x.balance);
			else if (x.data && x.data.progress) text = x.message + ' Es fehlt: ' + x.data.progress.missing.map((m) => ({ active_time: 'Lesezeit', scroll_depth: 'bis zum Ende scrollen', heartbeats: 'mindestens zwei Lebenszeichen der App' }[m] || m)).join(', ') + '.';
			zeige('#lese-erg', ergebnis(r, text));
			if (r.ok || (x.code && x.code !== 'vibono_reading_incomplete' && x.code !== 'vibono_quiz_wrong')) { stopLesen(); await personAktualisieren(); }
		};
	}

	// ------------------------------------------------------------ Werben
	SEITEN.werben = async (el) => {
		const r = await api('GET', '/referral');
		const d = r.data || {};
		el.innerHTML = `
			<h1>Freunde werben</h1>
			${!r.ok ? ergebnis(r, r.status === 403 ? 'Das Modul „Freunde werben“ ist im Backend ausgeschaltet.' : null) : `
			<div class="zahlen">
				<div class="zahl"><b>${h(d.code)}</b><span>Empfehlungscode von ${personName()}</span></div>
				<div class="zahl"><b>${zahl(d.invited)}</b><span>geworben</span></div>
				<div class="zahl"><b>${zahl(d.converted)}</b><span>haben bestellt</span></div>
				<div class="zahl gruen"><b>${zahl(d.points_earned)}</b><span>Punkte verdient</span></div>
			</div>
			<div class="karte"><h2>Was die App zum Teilen anzeigt</h2>
				<p><strong>Link:</strong> <a href="${h(d.link)}" target="_blank">${h(d.link)}</a></p>
				<p><strong>Text:</strong> ${h(d.share_text)}</p>
				<p class="leise">${h(d.points_per_referral)} Punkte für ${personName()}, ${h(d.friend_bonus_points)} Bonuspunkte für die geworbene Person – sobald deren erste Bestellung bezahlt ist und die Widerrufsfrist abgelaufen ist.</p>
			</div>`}
			<div class="raster">
				<div class="karte"><h2>1. Code prüfen</h2>
					<p class="leise">So prüft die App einen eingegebenen Code bei der Registrierung (<code>GET /referral/validate</code>, ohne Anmeldung).</p>
					<div class="knopfreihe"><input id="code" value="${h(d.code || '')}" size="12"><button class="zweit" id="pruefen">Prüfen</button></div>
					<div id="pruef-erg"></div>
				</div>
				<div class="karte"><h2>2. Neues Konto mit Code registrieren</h2>
					<p class="leise">Wie die Registrierung in der App (<code>POST /auth/register</code>).</p>
					<div class="formular">
						<label><span>Vorname</span><input id="r-name" value="Freundin"></label>
						<label><span>E-Mail</span><input id="r-mail" value="freundin-${Math.random().toString(36).slice(2, 6)}@vibono-test.local"></label>
						<label><span>Passwort</span><input id="r-pass" value="vibono-test"></label>
						<label><span>Empfehlungscode</span><input id="r-code" value="${h(d.code || '')}"></label>
					</div>
					<button id="registrieren">Registrieren</button>
					<div id="reg-erg"></div>
				</div>
			</div>
			<div class="karte gelb"><h2>3. Erste Bestellung der geworbenen Person</h2>
				<p>Wechsle oben zur neuen Person und simuliere im Bereich <a href="#" data-geh="shop">Shop & Bestellungen</a> eine Bestellung ab ${S.status ? euro(S.status.werte.referral_min_order_cents) : '15 €'}. Dann sind die Empfehlungspunkte für beide vorgemerkt. Nach „Bestellung abschließen“ und „Widerrufsfrist überspringen“ sind sie bestätigt. Wird die Bestellung storniert oder erstattet, verfallen sie.</p>
				<p class="leise">Schutzregeln, die du ausprobieren kannst: kein Werben mit eigener E-Mail oder gleicher Adresse, nur die erste Bestellung zählt, Mindestbestellwert.</p>
			</div>`;
		$$('[data-geh]').forEach((a) => a.onclick = (e) => { e.preventDefault(); S.bereich = a.dataset.geh; menue(); zeichnen(); });
		$('#pruefen').onclick = async () => {
			const x = await api('GET', '/referral/validate?code=' + encodeURIComponent($('#code').value), undefined, { ohneAnmeldung: true });
			zeige('#pruef-erg', ergebnis(x, x.ok ? (x.data.valid ? 'Gültig – geworben von ' + (x.data.referrer_first_name || '?') + ', Bonus ' + x.data.friend_bonus_points + ' Punkte.' : 'Code ungültig.') : null));
		};
		$('#registrieren').onclick = async () => {
			const body = { email: $('#r-mail').value.trim(), password: $('#r-pass').value, first_name: $('#r-name').value.trim(), referral_code: $('#r-code').value.trim() || null, accept_privacy: true, device_name: 'Testzentrale' };
			const x = await api('POST', '/auth/register', body, { ohneAnmeldung: true });
			if (x.ok) {
				const neu = x.data.user;
				await helfer('POST', '/nutzer/' + neu.id + '/passwort-merken', { passwort: body.password, beschreibung: 'In der Testzentrale registriert' + (body.referral_code ? ' mit Code ' + body.referral_code : '') });
				S.tokens[neu.id] = x.data;
				await nutzerLaden();
				zeige('#reg-erg', ergebnis(x, 'Konto angelegt: ' + neu.first_name + ' (' + neu.email + '). ') + '<button id="wechseln">Zu ' + h(neu.first_name) + ' wechseln und Bestellung simulieren</button>');
				$('#wechseln').onclick = () => {
					S.person = S.nutzer.find((u) => u.id === neu.id);
					try { localStorage.setItem('vt_person', String(neu.id)); } catch (e) { /* egal */ }
					S.bereich = 'shop'; kopf(); menue(); zeichnen();
				};
			} else {
				zeige('#reg-erg', ergebnis(x));
			}
		};
	};

	// ------------------------------------------------------------ Shop
	SEITEN.shop = async (el) => {
		const [prod, best] = await Promise.all([helfer('GET', '/produkte'), helfer('GET', '/bestellungen?user_id=' + (S.person ? S.person.id : 0))]);
		const produkte = prod.ok ? prod.data : [];
		el.innerHTML = `
			<h1>Shop & Bestellungen</h1>
			<div class="raster">
				<div class="karte"><h2>Im echten Test-Shop einkaufen</h2>
					<p>Öffnet den Shop im Browser, angemeldet als ${personName()} – so wie der Knopf in der App (<code>POST /auth/web-session</code>). Im Warenkorb erscheint das Feld zum Punkte-Einlösen.</p>
					<div class="knopfreihe"><button id="shop">🛒 Shop als ${personName()} öffnen</button><button class="zweit" id="warenkorb">Warenkorb</button><button class="zweit" id="konto">Mein Konto → Vibono-Punkte</button></div>
					<p class="leise">Bist du in diesem Browser gerade als admin oder jemand anderes angemeldet, bleibt das so (Schutzregel des Plugins). Dann vorher <a href="${S.status ? h(S.status.links.abmelden) : '/wp-login.php?action=logout'}" target="_blank">abmelden</a> oder ein privates Fenster nutzen und dort <a href="/mein-konto/" target="_blank">anmelden</a>.</p>
					<div id="shop-erg"></div>
				</div>
				<div class="karte"><h2>Bestellung simulieren <span class="marke gelb">Testhelfer</span></h2>
					<p class="leise">Legt für ${personName()} eine bezahlte Bestellung an, wie sie aus der Kasse käme. Die Punkte bucht das Plugin selbst.</p>
					<label><span>Produkt</span><select id="b-prod"><option value="">Freier Betrag</option>${produkte.map((p) => '<option value="' + p.id + '">' + h(p.name) + ' – ' + euro(p.preis * 100) + '</option>').join('')}</select></label>
					<div class="formular">
						<label><span>Menge</span><input id="b-menge" type="number" min="1" value="1"></label>
						<label><span>oder Betrag in €</span><input id="b-betrag" type="number" min="1" step="0.01" value="39.90"></label>
						<label><span>Status</span><select id="b-status"><option value="processing">bezahlt / in Bearbeitung</option><option value="completed">abgeschlossen</option><option value="on-hold">wartend (nicht bezahlt)</option></select></label>
					</div>
					<button id="bestellen">Bestellung anlegen</button>
					<div id="best-erg"></div>
				</div>
			</div>
			<div class="karte"><h2>Bestellungen von ${personName()}</h2>
				<div class="knopfreihe"><button class="zweit klein" id="frist">⏩ Widerrufsfrist überspringen</button><span class="marke gelb">Testhelfer</span><small class="leise">Punkte aus Einkäufen werden erst nach „abgeschlossen“ + Frist bestätigt.</small></div>
				<div id="bestellungen">${best.ok ? tabelleBestellungen(best.data) : ergebnis(best)}</div>
			</div>`;
		const webSession = async (ziel) => {
			const r = await api('POST', '/auth/web-session', { redirect: ziel });
			if (r.ok) { window.open(r.data.url, '_blank'); zeige('#shop-erg', ergebnis(r, 'Einmal-Link erzeugt und geöffnet (2 Minuten gültig).')); } else zeige('#shop-erg', ergebnis(r));
		};
		$('#shop').onclick = () => webSession('/shop/');
		$('#warenkorb').onclick = () => webSession('/warenkorb/');
		$('#konto').onclick = () => webSession('/mein-konto/vibono-punkte/');
		$('#bestellen').onclick = async () => {
			const pid = $('#b-prod').value;
			const body = { user_id: S.person.id, status: $('#b-status').value };
			if (pid) body.positionen = [{ product_id: Number(pid), menge: Number($('#b-menge').value || 1) }]; else body.betrag_eur = Number($('#b-betrag').value);
			const r = await helfer('POST', '/bestellungen', body);
			zeige('#best-erg', ergebnis(r, r.ok ? 'Bestellung ' + r.data.nummer + ' über ' + euro(r.data.summe * 100) + ' angelegt. ' + punkteText(r.data.punkte) : null));
			await personAktualisieren();
			bestellungenNeu();
		};
		$('#frist').onclick = async () => {
			const r = await helfer('POST', '/frist-ueberspringen', { user_id: 0 });
			hinweis(r.ok ? r.data.bestaetigt + ' vorgemerkte Buchungen bestätigt (alle Personen).' : meldung(r), !r.ok);
			await personAktualisieren();
			bestellungenNeu();
		};
		verdrahteBestellungen();
	};

	function punkteText(p) {
		if (!p || !p.length) return 'Keine Punkte gebucht.';
		return 'Punkte: ' + p.map((x) => x.wer + ' ' + (x.punkte > 0 ? '+' : '') + x.punkte + ' (' + (GRUENDE[x.grund] || x.grund) + ', ' + (STATUS[x.status] || [x.status])[0] + ')').join(' · ');
	}

	function tabelleBestellungen(list) {
		if (!list.length) return '<p class="leise">Noch keine Bestellungen.</p>';
		return '<table><thead><tr><th>Nr.</th><th>Datum</th><th>Inhalt</th><th>Summe</th><th>Status</th><th>Punkte dazu</th><th></th></tr></thead><tbody>' +
			list.map((o) => '<tr><td><a href="' + h(o.bearbeiten) + '" target="_blank">' + h(o.nummer) + '</a></td><td>' + h(o.datum) + '</td><td>' + o.positionen.map(h).join('<br>') + (o.eingeloest ? '<br><span class="marke blau">' + o.eingeloest + ' Punkte eingelöst</span>' : '') + '</td><td>' + euro(o.summe * 100) + '</td><td>' + h(o.status_text) + '</td><td><small>' + h(punkteText(o.punkte)) + '</small></td><td style="white-space:nowrap">' +
				(o.status !== 'completed' && o.status !== 'cancelled' && o.status !== 'refunded' ? '<button class="klein" data-o="' + o.id + '" data-s="completed">abschließen</button> ' : '') +
				(o.status === 'on-hold' ? '<button class="klein zweit" data-o="' + o.id + '" data-s="processing">bezahlt</button> ' : '') +
				(o.status !== 'cancelled' && o.status !== 'refunded' ? '<button class="klein gefahr" data-o="' + o.id + '" data-s="cancelled">stornieren</button> <button class="klein gefahr" data-o="' + o.id + '" data-s="refunded">erstatten</button>' : '') +
				'</td></tr>').join('') + '</tbody></table>';
	}

	function verdrahteBestellungen() {
		$$('#bestellungen [data-o]').forEach((b) => b.onclick = async () => {
			const r = await helfer('POST', '/bestellungen/' + b.dataset.o + '/status', { status: b.dataset.s });
			hinweis(r.ok ? 'Bestellung ' + r.data.nummer + ': ' + r.data.status_text + '. ' + punkteText(r.data.punkte) : meldung(r), !r.ok);
			await personAktualisieren();
			bestellungenNeu();
		});
	}

	async function bestellungenNeu() {
		const r = await helfer('GET', '/bestellungen?user_id=' + S.person.id);
		zeige('#bestellungen', r.ok ? tabelleBestellungen(r.data) : ergebnis(r));
		verdrahteBestellungen();
	}

	// ------------------------------------------------------------ Aktionen
	SEITEN.aktionen = async (el) => {
		const [oeff, alle] = await Promise.all([api('GET', '/points/campaigns', undefined, { ohneAnmeldung: true }), helfer('GET', '/aktionen')]);
		const liste = alle.ok ? alle.data : [];
		const now = Date.now() / 1000;
		el.innerHTML = `
			<h1>Aktionen</h1>
			<p>Aktionen vervielfachen für einen Zeitraum die Punkte für bestimmte Aktivitäten (Art „Verdienen“) oder den Wert der Punkte im Shop (Art „Einlösen“). Überschneiden sich Aktionen, gilt die mit dem höchsten Multiplikator.</p>
			<div class="karte"><h2>Alle Aktionen</h2>
				<table><thead><tr><th>Name</th><th>Art</th><th>Für</th><th>×</th><th>Zeitraum</th><th>Status</th><th></th></tr></thead><tbody>
				${liste.map((c) => `<tr><td><strong>${h(c.name)}</strong><br><small>${h(c.description)}</small></td><td>${c.kind === 'earn' ? 'Verdienen' : 'Einlösen'}</td><td>${c.kind === 'earn' ? (c.reasons.length ? c.reasons.map((r) => h(GRUENDE[r] || r)).join(', ') : 'alles') : 'Punktwert im Shop'}</td><td>${h(c.multiplier)}</td><td><small>${h(c.starts_local)} –<br>${h(c.ends_local)}</small></td><td>${!c.enabled ? '<span class="marke">aus</span>' : c.active ? '<span class="marke gruen">läuft</span>' : (new Date(c.ends_at).getTime() / 1000 < now ? '<span class="marke">vorbei</span>' : '<span class="marke gelb">geplant</span>')}</td><td><button class="klein gefahr" data-del="${c.id}">löschen</button></td></tr>`).join('') || '<tr><td colspan="7" class="leise">Keine Aktionen.</td></tr>'}
				</tbody></table>
				<div class="knopfreihe"><a class="knopf zweit klein" href="${S.status ? h(S.status.links.aktionen) : '#'}" target="_blank">Im Backend bearbeiten</a></div>
			</div>
			<div class="raster">
				<div class="karte"><h2>Schnell anlegen</h2>
					<p class="leise">Startet sofort, läuft eine Stunde. Gespeichert über dieselbe Funktion wie im Backend.</p>
					<div class="knopfreihe" style="flex-direction:column;align-items:flex-start">
						<button class="zweit" data-preset="lesen">Doppelte Lesepunkte</button>
						<button class="zweit" data-preset="oeffnen">Dreifache Punkte fürs App-Öffnen</button>
						<button class="zweit" data-preset="werben">Doppelte Punkte fürs Werben</button>
						<button class="zweit" data-preset="alles">Alles ×1,5</button>
						<button class="zweit" data-preset="wert">Punktwert verdoppeln (1 Punkt = 2 Cent)</button>
					</div>
				</div>
				<div class="karte"><h2>Eigene Aktion</h2>
					<label><span>Name (sehen die Kund*innen)</span><input id="a-name" value="Testaktion"></label>
					<div class="formular">
						<label><span>Art</span><select id="a-art"><option value="earn">Verdienen (mehr Punkte)</option><option value="redeem">Einlösen (Punkte mehr wert)</option></select></label>
						<label><span>Multiplikator</span><input id="a-mult" type="number" step="0.1" min="0.1" max="20" value="2"></label>
						<label><span>Beginn</span><input id="a-von" type="datetime-local"></label>
						<label><span>Ende</span><input id="a-bis" type="datetime-local"></label>
					</div>
					<div id="a-gruende">${['app_open', 'article_read', 'referral', 'referral_friend', 'purchase'].map((g) => '<label class="check"><input type="checkbox" value="' + g + '"> ' + h(GRUENDE[g]) + '</label>').join('')}<br><small class="leise">Keine Auswahl = für alles. Gilt nur für „Verdienen“.</small></div>
					<button id="a-speichern">Aktion anlegen</button>
					<div id="a-erg"></div>
				</div>
			</div>
			<div class="karte"><h2>Was die App sieht</h2><p class="leise"><code>GET /points/campaigns</code> – laufende und in den nächsten 14 Tagen startende Aktionen.</p>${ergebnis(oeff, oeff.ok ? oeff.data.length + ' Aktion(en) sichtbar.' : null)}</div>`;
		const vorlagen = {
			lesen: { name: 'Doppelte Lesepunkte', art: 'earn', gruende: ['article_read'], multiplikator: 2 },
			oeffnen: { name: 'Dreifache Punkte fürs Öffnen', art: 'earn', gruende: ['app_open'], multiplikator: 3 },
			werben: { name: 'Doppelte Punkte fürs Werben', art: 'earn', gruende: ['referral'], multiplikator: 2 },
			alles: { name: 'Alles ×1,5', art: 'earn', gruende: [], multiplikator: 1.5 },
			wert: { name: 'Punktwert verdoppelt', art: 'redeem', gruende: [], multiplikator: 2 },
		};
		$$('[data-preset]').forEach((b) => b.onclick = async () => {
			const v = vorlagen[b.dataset.preset];
			const r = await helfer('POST', '/aktionen', Object.assign({ beschreibung: 'In der Testzentrale angelegt', stunden: 1 }, v));
			hinweis(r.ok ? 'Aktion „' + v.name + '“ läuft jetzt eine Stunde.' : meldung(r), !r.ok);
			SEITEN.aktionen(el);
		});
		$$('[data-del]').forEach((b) => b.onclick = async () => {
			const r = await helfer('DELETE', '/aktionen/' + b.dataset.del);
			hinweis(r.ok ? 'Aktion gelöscht.' : meldung(r), !r.ok);
			SEITEN.aktionen(el);
		});
		const jetzt = new Date(); jetzt.setSeconds(0, 0);
		const lokal = (d) => new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
		$('#a-von').value = lokal(jetzt);
		$('#a-bis').value = lokal(new Date(jetzt.getTime() + 7 * 864e5));
		$('#a-speichern').onclick = async () => {
			const body = { name: $('#a-name').value, art: $('#a-art').value, multiplikator: Number($('#a-mult').value), von: $('#a-von').value, bis: $('#a-bis').value, gruende: $$('#a-gruende input:checked').map((i) => i.value), beschreibung: '' };
			const r = await helfer('POST', '/aktionen', body);
			if (r.ok) { hinweis('Aktion angelegt.'); SEITEN.aktionen(el); } else zeige('#a-erg', ergebnis(r));
		};
	};

	// ------------------------------------------------------------ Coaching heute
	SEITEN.heute = async (el, datumWert) => {
		const tag = datumWert || heute();
		const r = await api('GET', '/coaching/today?date=' + tag);
		const d = r.data || {};
		const karteninhalt = (s) => s ? `<li><span>${h(s.title)} ${s.lesson_kind ? '<span class="marke">' + h(s.lesson_kind) + '</span>' : ''} ${s.locked ? '<span class="marke rot">🔒</span>' : ''}</span>${s.points_for_reading ? '<span class="marke gruen">+' + s.points_for_reading + '</span>' : ''}</li>` : '';
		const abschnitt = (titel, list) => '<div class="karte"><h2>' + titel + '</h2>' + (list && list.length ? '<ul class="liste">' + list.map(karteninhalt).join('') + '</ul>' : '<p class="leise">Nichts für heute.</p>') + '</div>';
		el.innerHTML = `
			<h1>Coaching heute</h1>
			<p>Der Startbildschirm der App (<code>GET /coaching/today</code>): Phase, Tag, nächster Schritt, Rezepte und Tipps für ${personName()}.</p>
			<div class="knopfreihe">
				<label class="check">Datum <input type="date" id="tag" value="${tag}"></label>
				<label class="check"><input type="checkbox" id="mitglied" ${S.person && S.person.mitglied ? 'checked' : ''}> Coaching-Mitgliedschaft</label><span class="marke gelb">Testhelfer</span>
			</div>
			${!r.ok ? ergebnis(r) : `
			<div class="zahlen">
				<div class="zahl gruen"><b>${h(d.phase.label)}</b><span>${h(d.phase.day_label)}${d.phase.coaching_day ? ' · Coaching-Tag ' + d.phase.coaching_day : ''}</span></div>
				<div class="zahl"><b>${Math.round(d.progress.overall * 100)} %</b><span>Gesamtfortschritt</span><div class="balken"><i style="width:${Math.round(d.progress.overall * 100)}%"></i></div></div>
				<div class="zahl"><b>${Math.round(d.progress.phase * 100)} %</b><span>Fortschritt in der Phase</span><div class="balken"><i style="width:${Math.round(d.progress.phase * 100)}%"></i></div></div>
				<div class="zahl"><b>${zahl(d.points.balance)}</b><span>Punkte · heute geöffnet: ${d.points.app_open_awarded_today ? 'ja' : 'nein'}</span></div>
			</div>
			<div class="karte gruen"><h2>Nächster Schritt</h2>${d.next_step ? '<ul class="liste">' + karteninhalt(d.next_step) + '</ul>' : '<p class="leise">Alles erledigt oder kein Startdatum gesetzt (Profil & Konto).</p>'}</div>
			<div class="raster">
				${abschnitt('🥗 Essen', d.sections.essen)}
				${abschnitt('🏃 Bewegung', d.sections.bewegung)}
				${abschnitt('💡 Wissen', d.sections.wissen)}
				${abschnitt('📌 Sonstiges', d.sections.sonstiges)}
			</div>
			<div class="raster">
				<div class="karte"><h2>Rezepte ${d.recipes_source === 'weekplan' ? '<span class="marke blau">aus dem Wochenplan</span>' : '<span class="marke">Vorschläge</span>'}</h2><ul class="liste">${d.recipes.map(karteninhalt).join('') || '<li class="leise">Keine.</li>'}</ul>
					${d.planned_meals && d.planned_meals.length ? '<small class="leise">Geplant: ' + d.planned_meals.map((m) => h(m.slot) + (m.portions ? ' (' + m.portions + ' Port.)' : '')).join(', ') + '</small>' : ''}</div>
				<div class="karte"><h2>Tipps</h2><p><strong>Tipp des Tages:</strong> ${h(d.tip_of_the_day.text)}</p>${d.vibono_tip ? '<p><strong>Vibono-Tipp:</strong> ' + h(d.vibono_tip.title) + '</p>' : ''}</div>
				<div class="karte"><h2>Etappenziele</h2>${(d.progress.milestones || []).map((m) => '<p>' + h(m.key.replace('m', '')) + ' Monate (' + h(m.date) + '): ' + (m.target_weight_kg ? h(m.target_weight_kg) + ' kg' : '–') + ' ' + (m.reached ? '<span class="marke gruen">erreicht</span>' : '') + '</p>').join('') || '<p class="leise">Kein Startdatum.</p>'}</div>
			</div>
			<details class="karte"><summary>Antwort der Schnittstelle</summary><pre>${h(JSON.stringify(d, null, 2))}</pre></details>`}`;
		$('#tag').onchange = () => SEITEN.heute(el, $('#tag').value);
		$('#mitglied').onchange = async () => {
			const x = await helfer('POST', '/nutzer/' + S.person.id + '/mitgliedschaft', { aktiv: $('#mitglied').checked });
			hinweis(x.ok ? (x.data.mitglied ? 'Mitgliedschaft aktiv: Inhalte sind freigeschaltet.' : 'Mitgliedschaft beendet: Inhalte ab Phase 2 sind gesperrt.') : meldung(x), !x.ok);
			await personAktualisieren();
			SEITEN.heute(el, $('#tag').value);
		};
	};

	// ------------------------------------------------------------ Inhalte
	SEITEN.inhalte = async (el) => {
		el.innerHTML = `
			<h1>Inhalte & Rezepte</h1>
			<p>Die Listen und Detailansichten der App (<code>GET /content/…</code>). Gesperrte Inhalte (🔒) sieht nur, wer eine Coaching-Mitgliedschaft hat.</p>
			<div class="knopfreihe">
				<select id="typ"><option value="recipes">Rezepte</option><option value="lessons">Lektionen</option><option value="tips">Vibono-Tipps</option><option value="tips-of-the-day">Tipps des Tages</option></select>
				<input id="suche" placeholder="Suche"><input id="tags" placeholder="Merkmale, z. B. vegan,schnell" size="24">
				<button class="zweit" id="laden">Anzeigen</button>
			</div>
			<div class="zweispaltig"><div class="karte" id="liste"></div><div class="karte" id="detail"><p class="leise">Eintrag wählen.</p></div></div>`;
		const laden = async () => {
			const q = new URLSearchParams({ per_page: 50 });
			if ($('#suche').value) q.set('search', $('#suche').value);
			if ($('#tags').value) q.set('tags', $('#tags').value);
			const r = await api('GET', '/content/' + $('#typ').value + '?' + q);
			zeige('#liste', r.ok ? '<small class="leise">' + (r.gesamt != null ? r.gesamt : r.data.items.length) + ' Treffer</small><ul class="liste liste-klick">' + r.data.items.map((i) => '<li data-id="' + i.id + '"><span>' + h(i.title) + ' ' + (i.locked ? '<span class="marke rot">🔒</span>' : '') + (i.done ? ' <span class="marke gruen">erledigt</span>' : '') + '</span><small>' + (i.energy_density != null ? 'ED ' + h(i.energy_density) : '') + (i.tags.length ? ' ' + i.tags.slice(0, 3).map(h).join(', ') : '') + '</small></li>').join('') + '</ul>' : ergebnis(r));
			$$('#liste li').forEach((li) => li.onclick = () => detail(Number(li.dataset.id)));
		};
		const detail = async (id) => {
			const r = await api('GET', '/content/item/' + id);
			if (!r.ok) { zeige('#detail', ergebnis(r, r.status === 403 ? '🔒 ' + meldung(r) + ' Mitgliedschaft im Bereich „Coaching heute“ einschalten.' : null)); return; }
			const d = r.data;
			zeige('#detail', `<h2>${h(d.title)}</h2>
				<p>${d.tags.map((t) => '<span class="marke">' + h(t) + '</span>').join(' ')} ${d.reading_minutes ? '<small>' + d.reading_minutes + ' Min. Lesezeit</small>' : ''} ${d.points_for_reading ? '<span class="marke gruen">+' + d.points_for_reading + ' Lesepunkte</span>' : ''}</p>
				${d.ingredients ? '<h3>Zutaten für ' + h(d.servings || '?') + ' Portionen</h3><table><tbody>' + d.ingredients.map((i) => '<tr><td class="zahl-rechts">' + h(i.amount != null ? i.amount : '') + ' ' + h(i.unit || '') + '</td><td>' + h(i.name) + '</td></tr>').join('') + '</tbody></table><p class="leise">Zutatenblock im Text entfernt: ' + (d.ingredients_stripped ? 'ja' : 'nein') + '</p>' : ''}
				${d.energy_density != null ? '<p><strong>Energiedichte:</strong> ' + h(d.energy_density) + ' kcal/g</p>' : ''}
				<div class="artikel">${d.content_html}</div>
				<details><summary>Antwort der Schnittstelle</summary><pre>${h(JSON.stringify(d, null, 2))}</pre></details>`);
		};
		$('#laden').onclick = laden;
		$('#typ').onchange = laden;
		laden();
	};

	// ------------------------------------------------------------ Meine Daten
	const SAMMLUNGEN = [['favorites', 'Lieblingsrezepte'], ['lessons-done', 'Erledigte Lektionen'], ['courses-done', 'Erledigte Kurse'], ['weight', 'Gewicht'], ['sport', 'Sport'], ['weekplan', 'Wochenplan']];
	SEITEN.daten = async (el) => {
		const [rez, lek] = await Promise.all([api('GET', '/content/recipes?per_page=50'), api('GET', '/content/lessons?per_page=50')]);
		S.rezepte = rez.ok ? rez.data.items : [];
		S.lektionen = lek.ok ? lek.data.items : [];
		const rezOpt = S.rezepte.map((r) => '<option value="' + r.id + '">' + h(r.title) + '</option>').join('');
		el.innerHTML = `
			<h1>Meine Daten (Zwei-Wege-Sync)</h1>
			<p>MyVibono-Daten von ${personName()}, die App und Website teilen. Änderungen schickt die App mit Zeitstempel; bei Konflikten gewinnt die neuere Änderung.</p>
			<div class="knopfreihe">${SAMMLUNGEN.map((s, i) => '<button class="' + (i ? 'zweit ' : '') + 'klein" data-s="' + s[0] + '">' + h(s[1]) + '</button>').join('')}<button class="zweit klein" id="sync">🔄 Abgleich wie die App (GET /sync)</button></div>
			<div class="zweispaltig">
				<div class="karte" id="sammlung"></div>
				<div class="karte"><h2>Eintragen</h2>
					<h3>Gewicht</h3><div class="knopfreihe"><input type="date" id="w-tag" value="${heute()}"><input type="number" id="w-kg" step="0.1" value="80.2" style="width:6em"> kg <button class="klein" id="w-ok">Speichern</button></div>
					<h3>Sport</h3><div class="knopfreihe"><input type="date" id="s-tag" value="${heute()}"><input id="s-akt" value="Spaziergang" size="12"><input type="number" id="s-min" value="30" style="width:5em"> Min. <button class="klein" id="s-ok">Speichern</button></div>
					<h3>Lieblingsrezept</h3><div class="knopfreihe"><select id="f-rez">${rezOpt}</select><button class="klein" id="f-ok">Merken</button><button class="klein zweit" id="f-del">Entfernen</button></div>
					<h3>Wochenplan</h3><div class="knopfreihe"><input type="date" id="p-tag" value="${heute()}"><select id="p-slot"><option value="fruehstueck">Frühstück</option><option value="mittag">Mittag</option><option value="abend">Abend</option><option value="snack">Snack</option></select><select id="p-rez"><option value="">(bewusst frei)</option>${rezOpt}</select><input type="number" id="p-port" min="1" max="12" value="2" style="width:4em"> Port. <button class="klein" id="p-ok">Eintragen</button></div>
					<h3>Lektion erledigt</h3><div class="knopfreihe"><select id="l-lek">${S.lektionen.map((l) => '<option value="' + l.id + '">' + h(l.title) + '</option>').join('')}</select><button class="klein" id="l-ok">Abhaken</button><button class="klein zweit" id="l-del">Haken entfernen</button></div>
					<div id="d-erg"></div>
				</div>
			</div>`;
		let aktuell = 'favorites';
		const zeigeSammlung = async (name) => {
			aktuell = name;
			$$('[data-s]').forEach((b) => b.className = (b.dataset.s === name ? '' : 'zweit ') + 'klein');
			const r = await api('GET', '/me/' + name);
			const titel = SAMMLUNGEN.find((s) => s[0] === name)[1];
			zeige('#sammlung', '<h2>' + h(titel) + '</h2>' + (r.ok ? (r.data.items.length ? '<table><tbody>' + r.data.items.map((i) => '<tr><td><code>' + h(i.key) + '</code></td><td><small>' + h(JSON.stringify(i.data)) + '</small></td><td><small>' + datum(i.updated_at) + '</small></td></tr>').join('') + '</tbody></table>' : '<p class="leise">Leer.</p>') + '<small class="leise">Cursor: ' + h(r.data.cursor) + '</small>' : ergebnis(r)));
		};
		const senden = async (sammlung, aenderungen, nach) => {
			const r = await api('PUT', '/me/' + sammlung, { changes: aenderungen.map((c) => Object.assign({ updated_at: new Date().toISOString() }, c)) });
			const res = r.ok ? r.data.results : [];
			zeige('#d-erg', ergebnis(r, r.ok ? res.map((x) => x.key + ': ' + x.status + (x.error ? ' (' + x.error + ')' : '')).join(', ') : null));
			zeigeSammlung(nach || sammlung);
		};
		$$('[data-s]').forEach((b) => b.onclick = () => zeigeSammlung(b.dataset.s));
		$('#w-ok').onclick = () => senden('weight', [{ key: $('#w-tag').value, op: 'upsert', data: { kg: Number($('#w-kg').value) } }]);
		$('#s-ok').onclick = () => senden('sport', [{ key: uuid(), op: 'upsert', data: { date: $('#s-tag').value, activity: $('#s-akt').value, minutes: Number($('#s-min').value) } }]);
		$('#f-ok').onclick = () => senden('favorites', [{ key: 'recipe:' + $('#f-rez').value, op: 'upsert' }]);
		$('#f-del').onclick = () => senden('favorites', [{ key: 'recipe:' + $('#f-rez').value, op: 'delete' }]);
		$('#p-ok').onclick = () => senden('weekplan', [{ key: $('#p-tag').value + ':' + $('#p-slot').value, op: 'upsert', data: { recipe_id: $('#p-rez').value ? Number($('#p-rez').value) : null, portions: Number($('#p-port').value) } }]);
		$('#l-ok').onclick = () => senden('lessons-done', [{ key: $('#l-lek').value, op: 'upsert' }]);
		$('#l-del').onclick = () => senden('lessons-done', [{ key: $('#l-lek').value, op: 'delete' }]);
		$('#sync').onclick = async () => {
			const r = await api('GET', '/sync');
			zeige('#sammlung', '<h2>Abgleich (alle Sammlungen)</h2>' + ergebnis(r, r.ok ? r.data.changes.length + ' Einträge, Cursor ' + r.data.cursor + (r.data.has_more ? ' (weitere vorhanden)' : '') : null));
		};
		zeigeSammlung(aktuell);
	};

	// ------------------------------------------------------------ Profil
	SEITEN.profil = async (el) => {
		const r = await api('GET', '/me');
		if (!r.ok) { el.innerHTML = '<h1>Profil & Konto</h1>' + ergebnis(r); return; }
		const d = r.data;
		const o = d.onboarding || {}, n = o.nutrition || {}, g = d.goals || {};
		const opt = (werte, aktiv) => werte.map((w) => '<option' + (w === aktiv ? ' selected' : '') + '>' + w + '</option>').join('');
		el.innerHTML = `
			<h1>Profil & Konto</h1>
			<div class="raster">
				<div class="karte"><h2>${h(d.display_name)}</h2>
					<p>${h(d.email)} · Code <code>${h(d.referral_code)}</code></p>
					<p>Mitgliedschaften: ${(d.memberships || []).map((m) => '<span class="marke gruen">' + h(m.name) + '</span>').join(' ') || '<span class="marke">keine</span>'} · Coaching-Zugang: ${d.has_coaching_access ? 'ja' : 'nein'}</p>
					<p>Onboarding abgeschlossen: ${o.completed ? 'ja' : 'nein'}</p>
					<div class="knopfreihe">
						<button class="zweit klein" id="refresh">Token erneuern</button>
						<button class="zweit klein" id="logout">Abmelden (dieses Gerät)</button>
						<button class="zweit klein" id="pw">Passwort vergessen</button>
						<button class="zweit klein" id="geraet">Push-Gerät anmelden</button>
						<button class="gefahr klein" id="loeschen">Konto löschen beantragen</button>
					</div>
					<div id="k-erg"></div>
				</div>
				<div class="karte"><h2>Onboarding & Ziele ändern</h2>
					<div class="formular">
						<label><span>Vorname</span><input id="p-name" value="${h(d.first_name)}"></label>
						<label><span>Ernährung</span><select id="p-diet">${opt(['alles', 'flexitarisch', 'vegetarisch', 'vegan'], n.diet)}</select></label>
						<label><span>Aktivität</span><select id="p-akt">${opt(['sportmuffel', 'eingerostet', 'moderat_aktiv', 'sehr_aktiv'], o.activity_level)}</select></label>
						<label><span>Unverträglichkeiten (Komma)</span><input id="p-unv" value="${h((n.intolerances || []).join(','))}" placeholder="laktose,gluten"></label>
						<label><span>Mag ich nicht (Komma)</span><input id="p-dis" value="${h((n.dislikes || []).join(','))}"></label>
						<label><span>Größe (cm)</span><input id="p-gr" type="number" value="${h(g.height_cm || '')}"></label>
						<label><span>Startgewicht</span><input id="p-sw" type="number" step="0.1" value="${h(g.start_weight_kg || '')}"></label>
						<label><span>Ziel 3 Monate</span><input id="p-z3" type="number" step="0.1" value="${h(g.target_weight_3m_kg || '')}"></label>
						<label><span>Ziel 6 Monate</span><input id="p-z6" type="number" step="0.1" value="${h(g.target_weight_6m_kg || '')}"></label>
						<label><span>Ziel 12 Monate</span><input id="p-z12" type="number" step="0.1" value="${h(g.target_weight_12m_kg || '')}"></label>
						<label><span>Coaching-Start</span><input id="p-start" type="date" value="${h(g.coaching_start_date || '')}"></label>
					</div>
					<button id="p-speichern">Speichern (PUT /me/profile)</button>
					<div id="p-erg"></div>
				</div>
			</div>
			<details class="karte"><summary>Antwort von GET /me</summary><pre>${h(JSON.stringify(d, null, 2))}</pre></details>`;
		const num = (id) => $(id).value === '' ? null : Number($(id).value);
		const liste = (id) => $(id).value.split(',').map((s) => s.trim()).filter(Boolean);
		$('#p-speichern').onclick = async () => {
			const body = {
				first_name: $('#p-name').value,
				onboarding: { nutrition: { diet: $('#p-diet').value, intolerances: liste('#p-unv'), dislikes: liste('#p-dis') }, activity_level: $('#p-akt').value, completed: true },
				goals: { height_cm: num('#p-gr'), start_weight_kg: num('#p-sw'), target_weight_3m_kg: num('#p-z3'), target_weight_6m_kg: num('#p-z6'), target_weight_12m_kg: num('#p-z12'), coaching_start_date: $('#p-start').value || null },
			};
			const x = await api('PUT', '/me/profile', body);
			zeige('#p-erg', ergebnis(x, x.ok ? 'Gespeichert.' : (x.data && x.data.data && x.data.data.fields ? meldung(x) + ' Felder: ' + x.data.data.fields.join(', ') : null)));
			if (x.ok) await personAktualisieren();
		};
		$('#refresh').onclick = async () => {
			const t = S.tokens[S.person.id];
			const x = await anfrage(VT.api, 'POST', '/auth/refresh', { refresh_token: t ? t.refresh_token : '' }, { person: S.person.name });
			if (x.ok) S.tokens[S.person.id] = x.data;
			zeige('#k-erg', ergebnis(x, x.ok ? 'Neues Token erhalten (das alte Refresh-Token ist jetzt ungültig).' : null));
		};
		$('#logout').onclick = async () => {
			const t = S.tokens[S.person.id];
			const x = await api('POST', '/auth/logout', { refresh_token: t ? t.refresh_token : '' });
			delete S.tokens[S.person.id];
			zeige('#k-erg', ergebnis(x, x.ok ? 'Abgemeldet. Beim nächsten Aufruf meldet sich die Testzentrale neu an.' : null));
		};
		$('#pw').onclick = async () => {
			const x = await api('POST', '/auth/password-reset', { email: S.person.email }, { ohneAnmeldung: true });
			zeige('#k-erg', ergebnis(x, x.ok ? 'Angefordert. Die E-Mail steht im Bereich „E-Mails“.' : null));
		};
		$('#geraet').onclick = async () => {
			const x = await api('POST', '/me/devices', { token: 'test-push-' + uuid(), platform: 'android', app_version: '1.0.0', locale: 'de_DE' });
			zeige('#k-erg', ergebnis(x));
		};
		$('#loeschen').onclick = async () => {
			if (!confirm('Kontolöschung für ' + S.person.name + ' beantragen? (Nur Testdaten. Ausgeführt wird sie im Backend unter Werkzeuge → Personenbezogene Daten löschen.)')) return;
			const x = await api('DELETE', '/me');
			zeige('#k-erg', ergebnis(x, x.ok ? 'Löschung beantragt (Status 202). Im Backend unter Werkzeuge → „Personenbezogene Daten löschen“ ausführen.' : null));
		};
	};

	// ------------------------------------------------------------ Energiedichte
	SEITEN.energie = async (el) => {
		const st = S.status || (await helfer('GET', '/status')).data;
		el.innerHTML = `
			<h1>Energiedichte-Rechner</h1>
			<div class="raster">
				<div class="karte"><h2>Lebensmittel suchen</h2>
					<p class="leise"><code>GET /foods</code> – Daten aus den Lebensmittel-Beiträgen (kcal je 100 g).</p>
					<div class="knopfreihe"><input id="q" value="Gur"><button class="zweit" id="suchen">Suchen</button></div>
					<div id="f-erg"></div>
				</div>
				<div class="karte"><h2>Foto oder Rezept auswerten</h2>
					<p>${st && st.claude_schluessel ? '<span class="marke gruen">Claude-Schlüssel hinterlegt</span> Bilder werden echt ausgewertet (kostet API-Guthaben).' : '<span class="marke gelb">Simulation</span> Ohne Claude-Schlüssel liefert die Testumgebung eine markierte Beispiel-Antwort. Die Bildprüfung läuft trotzdem durch das Plugin.'}</p>
					<label><span>Bild (JPEG, PNG oder WebP, max. 5 MB)</span><input type="file" id="bild" accept="image/jpeg,image/png,image/webp"></label>
					<label><span>Beschreibung (optional, nur Foto)</span><input id="beschr" placeholder="z. B. mit Hähnchen und Reis"></label>
					<div class="knopfreihe"><button id="foto">📷 Gericht schätzen</button><button class="zweit" id="scan">📄 Rezept scannen</button></div>
					<div id="v-erg"></div>
				</div>
				<div class="karte"><h2>Claude-Schlüssel</h2>
					<p class="leise">Optional. Wird nur in dieser Testumgebung gespeichert. Leer lassen und speichern entfernt ihn.</p>
					<div class="knopfreihe"><input id="key" type="password" placeholder="sk-ant-…" size="28"><button class="zweit" id="key-ok">Speichern</button></div>
				</div>
			</div>`;
		$('#suchen').onclick = async () => {
			const r = await api('GET', '/foods?q=' + encodeURIComponent($('#q').value));
			zeige('#f-erg', r.ok ? '<table><tbody>' + r.data.items.map((i) => { const ed = i.kcal_per_100g / 100; return '<tr><td>' + h(i.name) + '</td><td class="zahl-rechts">' + h(i.kcal_per_100g) + ' kcal</td><td class="zahl-rechts">' + ed.toFixed(2).replace('.', ',') + ' kcal/g</td><td><span class="marke ' + (ed < 1.5 ? 'gruen' : ed <= 2.4 ? 'gelb' : 'rot') + '">' + (ed < 1.5 ? 'grün' : ed <= 2.4 ? 'gelb' : 'rot') + '</span></td></tr>'; }).join('') + '</tbody></table>' + (r.data.items.length ? '' : '<p class="leise">Nichts gefunden.</p>') : ergebnis(r));
		};
		const lesen = () => new Promise((ok, nein) => {
			const f = $('#bild').files[0];
			if (!f) { nein(new Error('Bitte zuerst ein Bild wählen.')); return; }
			const fr = new FileReader();
			fr.onload = () => ok({ image_base64: String(fr.result).split(',')[1], mime: f.type });
			fr.onerror = () => nein(new Error('Bild konnte nicht gelesen werden.'));
			fr.readAsDataURL(f);
		});
		const auswerten = async (pfad, extra) => {
			let bild;
			try { bild = await lesen(); } catch (e) { hinweis(e.message, true); return; }
			zeige('#v-erg', '<p class="leise">Wird ausgewertet …</p>');
			const r = await api('POST', pfad, Object.assign(bild, extra || {}));
			const d = r.data || {};
			let text = null;
			if (r.ok && d.dish) text = d.dish + ': ' + d.portion_g + ' g, ' + d.kcal_total + ' kcal → ' + d.kcal_per_g + ' kcal/g';
			if (r.ok && d.ingredients) text = (d.title || 'Rezept') + ': ' + d.ingredients.length + ' Zutaten, ' + (d.kcal_per_g != null ? d.kcal_per_g + ' kcal/g' : 'Energiedichte unvollständig');
			zeige('#v-erg', (d.simulation ? '<div class="ergebnis" style="background:var(--gelb-hell);border-color:#F1E3A0">' + h(d.simulation) + '</div>' : '') + ergebnis(r, text));
		};
		$('#foto').onclick = () => auswerten('/energy-density/analyze-photo', { description: $('#beschr').value });
		$('#scan').onclick = () => auswerten('/energy-density/scan-recipe');
		$('#key-ok').onclick = async () => {
			const r = await helfer('POST', '/claude-schluessel', { schluessel: $('#key').value });
			if (S.status) S.status.claude_schluessel = r.ok && r.data.claude_schluessel;
			hinweis(r.ok ? (r.data.claude_schluessel ? 'Schlüssel gespeichert.' : 'Schlüssel entfernt, Simulation aktiv.') : meldung(r), !r.ok);
			SEITEN.energie(el);
		};
	};

	// ------------------------------------------------------------ App-Einstellungen
	SEITEN.config = async (el) => {
		const [a, i] = await Promise.all([api('GET', '/config?platform=android', undefined, { ohneAnmeldung: true }), api('GET', '/config?platform=ios', undefined, { ohneAnmeldung: true })]);
		const zeile = (d) => d ? `<table><tbody>
			<tr><td>Mindestversion der App</td><td>${h(d.min_app_version)}</td></tr>
			<tr><td>Punktesystem</td><td>${d.points_enabled ? 'an' : 'aus'} · 1 Punkt = ${h(d.cents_per_point)} Cent</td></tr>
			<tr><td>Funktionen</td><td>${Object.entries(d.features || {}).map(([k, v]) => '<span class="marke ' + (v ? 'gruen' : '') + '">' + h(k) + ': ' + (v ? 'an' : 'aus') + '</span>').join(' ')}</td></tr>
			<tr><td>Shop-Links</td><td>${Object.entries(d.shop_links || {}).map(([k, v]) => '<span class="marke ' + (v ? 'gruen' : '') + '">' + h(k) + ': ' + (v ? 'an' : 'aus') + '</span>').join(' ')}</td></tr>
			<tr><td>Shop</td><td>${h(d.shop_url)}</td></tr>
		</tbody></table>` : '';
		el.innerHTML = `
			<h1>App-Einstellungen</h1>
			<p>Was die App beim Start lädt (<code>GET /config</code>, ohne Anmeldung). Hier steuert das Backend, welche Module die App zeigt und ob sie auf den Shop verlinken darf (iOS und Android getrennt, wegen der Store-Regeln).</p>
			<div class="raster"><div class="karte"><h2>Android</h2>${a.ok ? zeile(a.data) : ergebnis(a)}</div><div class="karte"><h2>iOS</h2>${i.ok ? zeile(i.data) : ergebnis(i)}</div></div>
			<p><a class="knopf zweit" href="${S.status ? h(S.status.links.schnittstelle) : '#'}" target="_blank">Im Backend ändern (App-Schnittstelle)</a> <a class="knopf zweit" href="${S.status ? h(S.status.links.module) : '#'}" target="_blank">Module</a></p>`;
	};

	// ------------------------------------------------------------ E-Mails
	SEITEN.mails = async (el) => {
		const r = await helfer('GET', '/mails');
		const list = r.ok ? r.data : [];
		el.innerHTML = `
			<h1>E-Mails</h1>
			<p>Die Testumgebung verschickt keine E-Mails. Alles, was WordPress, WooCommerce oder das Plugin senden würden, landet hier.</p>
			<div class="knopfreihe"><button class="zweit klein" id="neu">Aktualisieren</button><button class="gefahr klein" id="leeren">Alle löschen</button></div>
			${list.length ? list.map((m, i) => `<details class="karte" ${i === 0 ? 'open' : ''}><summary><strong>${h(m.subject)}</strong> · an ${h(m.to)} · <small>${h(m.zeit)}</small></summary>
				${m.html ? '<iframe sandbox="" style="width:100%;height:420px;border:1px solid var(--grau-200);border-radius:8px" srcdoc="' + h(m.message) + '"></iframe>' : '<pre style="white-space:pre-wrap;background:#fff;color:var(--grau-900);border:1px solid var(--grau-200)">' + h(m.message) + '</pre>'}</details>`).join('') : '<p class="leise">Noch keine E-Mails.</p>'}`;
		$('#neu').onclick = () => SEITEN.mails(el);
		$('#leeren').onclick = async () => { await helfer('DELETE', '/mails'); SEITEN.mails(el); };
	};

	// ------------------------------------------------------------ Protokoll
	SEITEN.protokoll = async (el) => {
		const fehler = await helfer('GET', '/fehlerprotokoll');
		el.innerHTML = `
			<h1>Protokoll & API-Konsole</h1>
			<div class="karte"><h2>Eigene Anfrage</h2>
				<p class="leise">Für Entwickler: beliebige Anfrage an <code>${h(VT.api)}</code> als ${personName()} (mit Token).</p>
				<div class="knopfreihe"><select id="k-m"><option>GET</option><option>POST</option><option>PUT</option><option>DELETE</option></select><input id="k-p" value="/me" size="40"><label class="check"><input type="checkbox" id="k-ohne"> ohne Anmeldung</label><button id="k-los">Senden</button></div>
				<textarea id="k-b" placeholder='Body als JSON, z. B. {"post_id": 12}'></textarea>
				<div id="k-erg"></div>
			</div>
			<div class="karte"><h2>Letzte Anfragen dieser Sitzung</h2>
				${S.protokoll.length ? S.protokoll.map((e) => `<details class="protokoll-eintrag"><summary class="zeile"><span class="marke ${e.status >= 200 && e.status < 300 ? 'gruen' : 'rot'}">${e.status || '–'}</span><b>${h(e.methode)}</b> ${h(e.pfad)} <small class="leise">${e.ms} ms · ${e.zeit.toLocaleTimeString('de-DE')}${e.person ? ' · ' + h(e.person) : ''}${e.helfer ? ' · Testhelfer' : ''}</small></summary>${e.anfrage !== undefined ? '<small>Anfrage</small><pre>' + h(JSON.stringify(e.anfrage, null, 2)) + '</pre>' : ''}<small>Antwort</small><pre>${h(JSON.stringify(e.antwort, null, 2))}</pre></details>`).join('') : '<p class="leise">Noch keine Anfragen.</p>'}
			</div>
			<div class="karte"><h2>PHP-Fehlerprotokoll</h2><p class="leise">Letzte Einträge aus <code>wp-content/fehlerprotokoll.log</code>. Fehler des Plugins beginnen mit „Vibono App API“.</p>
				<pre>${fehler.ok && fehler.data.zeilen.length ? h(fehler.data.zeilen.join('\n')) : 'Keine Einträge.'}</pre>
			</div>`;
		$('#k-los').onclick = async () => {
			let body;
			const raw = $('#k-b').value.trim();
			if (raw) { try { body = JSON.parse(raw); } catch (e) { hinweis('Body ist kein gültiges JSON.', true); return; } }
			const pfad = '/' + $('#k-p').value.replace(/^\/+/, '');
			const r = await api($('#k-m').value, pfad, body, { ohneAnmeldung: $('#k-ohne').checked });
			zeige('#k-erg', ergebnis(r));
		};
	};

	// ------------------------------------------------------------ Start
	(async function init() {
		if (!VT.plugin) {
			$('#inhalt').innerHTML = '<div class="ergebnis fehler">Das Plugin „Vibono App API & Punkte“ ist nicht aktiv. Im Backend unter Plugins aktivieren.</div>';
			return;
		}
		menue();
		await nutzerLaden();
		const st = await helfer('GET', '/status');
		if (st.ok) S.status = st.data;
		zeichnen();
	})();
})();
