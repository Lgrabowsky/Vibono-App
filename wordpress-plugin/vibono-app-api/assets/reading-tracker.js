/**
 * Vibono Lese-Nachweis auf vibono.de (eingeloggte Nutzer, belohnbare Beiträge).
 * Zählt aktive Lesezeit nur, wenn der Tab sichtbar und das Fenster fokussiert ist und der
 * Nutzer in den letzten 60 s gescrollt, getippt oder die Maus bewegt hat.
 */
(function () {
	'use strict';
	var cfg = window.vibonoReading;
	if (!cfg || !window.fetch) { return; }

	var content = document.querySelector(cfg.content) || document.body;
	var session = null, active = 0, maxScroll = 0, lastInput = Date.now(), done = false, timer = null;

	function api(path, body) {
		return fetch(cfg.root + path, {
			method: 'POST',
			credentials: 'same-origin',
			headers: { 'Content-Type': 'application/json', 'X-WP-Nonce': cfg.nonce },
			body: JSON.stringify(body)
		}).then(function (r) { return r.json().then(function (j) { return { ok: r.ok, body: j }; }); });
	}

	function scrollDepth() {
		var rect = content.getBoundingClientRect();
		var bottom = rect.top + window.scrollY + rect.height;
		var seen = window.scrollY + window.innerHeight;
		var top = rect.top + window.scrollY;
		return Math.max(0, Math.min(1, (seen - top) / Math.max(1, bottom - top)));
	}

	function isActive() {
		return document.visibilityState === 'visible' && document.hasFocus() && Date.now() - lastInput < 60000;
	}

	['scroll', 'mousemove', 'keydown', 'touchstart', 'wheel'].forEach(function (ev) {
		window.addEventListener(ev, function () {
			lastInput = Date.now();
			maxScroll = Math.max(maxScroll, scrollDepth());
		}, { passive: true });
	});

	function toast(text) {
		var el = document.createElement('div');
		el.setAttribute('role', 'status');
		el.textContent = text;
		el.style.cssText = 'position:fixed;left:50%;bottom:24px;transform:translateX(-50%);background:#9cc536;color:#fff;padding:12px 20px;border-radius:50px;font-weight:bold;z-index:99999;box-shadow:0 4px 16px rgba(0,0,0,.2)';
		document.body.appendChild(el);
		setTimeout(function () { el.remove(); }, 5000);
	}

	function askQuiz(quiz) {
		var box = document.createElement('div');
		box.className = 'vibono-quiz';
		box.style.cssText = 'margin:24px 0;padding:16px;border:2px solid #9cc536;border-radius:8px;background:#F4F8E7';
		var h = document.createElement('p');
		h.style.fontWeight = 'bold';
		h.textContent = 'Punkte sichern: ' + quiz.question;
		box.appendChild(h);
		quiz.answers.forEach(function (a, i) {
			var b = document.createElement('button');
			b.type = 'button';
			b.textContent = a;
			b.style.cssText = 'display:block;margin:6px 0;padding:8px 16px;border-radius:50px;border:1px solid #9cc536;background:#fff;cursor:pointer';
			b.onclick = function () { complete(i, box); };
			box.appendChild(b);
		});
		content.appendChild(box);
	}

	function complete(answer, quizBox) {
		var body = { session_id: session.session_id };
		if (answer !== undefined) { body.quiz_answer = answer; }
		api('reading/complete', body).then(function (r) {
			if (r.ok) {
				done = true;
				clearInterval(timer);
				if (quizBox) { quizBox.remove(); }
				if (r.body.awarded_points > 0) { toast('+' + r.body.awarded_points + ' Vibono-Punkte fürs Lesen!'); }
			} else if (r.body && r.body.code === 'vibono_quiz_wrong') {
				toast(r.body.message);
			} else if (r.body && r.body.code === 'vibono_daily_cap_reached') {
				done = true;
				clearInterval(timer);
				if (quizBox) { quizBox.remove(); }
			}
		});
	}

	api('reading/start', { post_id: cfg.postId, channel: 'web' }).then(function (r) {
		if (!r.ok) { return; }
		session = r.body;
		var step = session.heartbeat_interval_seconds || 10;
		var tick = 0;
		var quizShown = false;
		timer = setInterval(function () {
			if (done) { return; }
			if (isActive()) { active += 1; }
			maxScroll = Math.max(maxScroll, scrollDepth());
			tick += 1;
			if (tick % step !== 0) { return; }
			api('reading/heartbeat', { session_id: session.session_id, active_seconds: active, scroll_depth: maxScroll }).then(function (hb) {
				if (!hb.ok || !hb.body.ready_to_complete || done) { return; }
				if (session.quiz) {
					if (!quizShown) { quizShown = true; askQuiz(session.quiz); }
				} else {
					complete();
				}
			});
		}, 1000);
	});
})();
