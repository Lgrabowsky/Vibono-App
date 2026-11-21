import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

import '../../domain/app_streak_rules.dart';
import '../../domain/coaching_plan.dart';
import '../../domain/food_database.dart';
import '../../domain/recipe_picker.dart';
import '../local/local_store.dart';
import '../models/app_config.dart';
import '../models/coaching_day.dart';
import '../models/content.dart';
import '../models/energy.dart';
import '../models/home_feed.dart';
import '../models/json.dart';
import '../models/points.dart';
import '../models/profile.dart';
import '../models/sync_item.dart';
import 'api_exception.dart';
import 'mock_data.dart';
import 'vibono_api.dart';

/// Simuliert das WordPress-Plugin vollständig auf dem Gerät, inklusive
/// MyVibono-Daten, Punktesystem und Lese-Nachweis. Aktiv, solange
/// `VIBONO_MOCK=true` (Standard) gesetzt ist.
class MockVibonoApi implements VibonoApi {
  MockVibonoApi(this._store, {this.latency = const Duration(milliseconds: 250)});

  final LocalStore _store;
  final Duration latency;
  final _rnd = Random();
  List<Course>? _courses;
  final Map<String, ({int postId, DateTime started, DateTime lastBeat, int accepted, double depth, int min, int? quizCorrect})>
      _sessions = {};

  // ---------- Hilfen ----------

  Future<void> _wait([Duration? d]) => Future<void>.delayed(d ?? latency);

  Json get _me => asMap(_store.readJson('mock.me')) ?? _seedMe();

  Json _seedMe() => {
        'id': 4711,
        'email': 'sabine@example.com',
        'first_name': 'Sabine',
        'display_name': 'Sabine',
        'memberships': [
          {'plan': 'komplett-paket', 'name': 'Komplett-Paket', 'status': 'active'},
        ],
        'has_coaching_access': true,
        'onboarding': {'completed': false},
        'goals': <String, dynamic>{},
        'points_balance': 240,
        'referral_code': 'SABINE7K',
      };

  Future<void> _saveMe(Json me) => _store.writeJson('mock.me', me);

  int get _balance => asInt(_me['points_balance']) ?? 0;

  Future<AwardResult> _award(int points, String reason, String label, {double multiplier = 1}) async {
    final me = _me;
    final balance = _balance + points;
    me['points_balance'] = balance;
    await _saveMe(me);
    final ledger = (_store.readJson('mock.ledger') as List?) ?? _seedLedger();
    ledger.insert(0, {
      'id': DateTime.now().millisecondsSinceEpoch,
      'points': points,
      'reason': reason,
      'status': 'confirmed',
      'label': label,
      'multiplier': multiplier,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    await _store.writeJson('mock.ledger', ledger);
    return AwardResult(awardedPoints: points, alreadyAwarded: false, balance: balance, multiplier: multiplier);
  }

  List<dynamic> _seedLedger() {
    final now = DateTime.now().toUtc();
    String ago(int d) => now.subtract(Duration(days: d)).toIso8601String();
    return [
      {'id': 3, 'points': 120, 'reason': 'purchase', 'status': 'confirmed', 'label': 'Einkauf im Vibono-Shop', 'created_at': ago(3)},
      {'id': 2, 'points': 100, 'reason': 'migration', 'status': 'confirmed', 'label': 'Übernommen aus „Freunde werben“', 'created_at': ago(20)},
      {'id': 1, 'points': 20, 'reason': 'article_read', 'status': 'confirmed', 'label': 'Artikel gelesen: Mit 3 Phasen zum Erfolg', 'created_at': ago(21)},
    ];
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ---------- „Server“-Seite der Synchronisation ----------

  Map<String, Json> get _server {
    final raw = asMap(_store.readJson('mock.server'));
    if (raw != null) return raw.map((k, v) => MapEntry(k, Json.from(v as Map)));
    return _seedServer();
  }

  /// Daten, die schon in MyVibono auf der Website stehen.
  Map<String, Json> _seedServer() {
    final t = DateTime.now().toUtc().subtract(const Duration(days: 30)).toIso8601String();
    final today = DateTime.now();
    Json item(String c, String k, Json data) =>
        {'collection': c, 'key': k, 'data': data, 'updated_at': t, 'deleted': false};
    final m = <String, Json>{
      'favorites|recipe:9002': item('favorites', 'recipe:9002', {'post_id': 9002, 'kind': 'recipe'}),
      'favorites|recipe:9005': item('favorites', 'recipe:9005', {'post_id': 9005, 'kind': 'recipe'}),
      'favorites|tip:9101': item('favorites', 'tip:9101', {'post_id': 9101, 'kind': 'tip'}),
    };
    for (var i = 1; i <= 3; i++) {
      final d = _day(today.subtract(Duration(days: i * 3)));
      m['weight|$d'] = item('weight', d, {'date': d, 'kg': 98.4 + i * 0.4});
    }
    return m;
  }

  Future<void> _saveServer(Map<String, Json> s) => _store.writeJson('mock.server', s);

  Set<int> get _doneLessons => {
        for (final v in _server.values)
          if (v['collection'] == 'lessons_done' && v['deleted'] != true) int.tryParse('${v['key']}') ?? 0,
      };

  // ---------- System & Auth ----------

  @override
  bool get hasSession => _store.readBool('mock.session') ?? false;

  @override
  Future<RemoteConfig> config(String platform) async {
    await _wait();
    // Wie im Vertrag vorgesehen: physische Produkte dürfen verlinkt werden,
    // digitale Inhalte und Punkte-Einlösung in den Store-Apps vorerst nicht.
    final web = platform == 'web';
    // Die Demo zeigt alle Module. Auf vibono.de sind sie anfangs aus und
    // werden schrittweise eingeschaltet (`features`).
    return RemoteConfig(
      featureReferral: true,
      featureShopPoints: true,
      linkPhysicalProducts: true,
      linkDigitalProducts: platform != 'ios',
      linkMemberships: web,
      linkPointsRedemption: web,
      shopUrl: 'https://www.vibono.de/shop/',
      centsPerPoint: 1,
    );
  }

  @override
  Future<Me> login(String username, String password, {String? deviceName}) async {
    await _wait(const Duration(milliseconds: 600));
    if (password.length < 4) {
      throw const ApiException(401, 'vibono_invalid_credentials', 'E-Mail oder Passwort ist falsch.');
    }
    await _store.writeBool('mock.session', true);
    final me = _me;
    if (username.contains('@')) me['email'] = username;
    await _saveMe(me);
    return Me.fromJson(me);
  }

  @override
  Future<Me> register({required String email, required String password, String? firstName, String? referralCode}) async {
    await _wait(const Duration(milliseconds: 600));
    if (password.length < 8) {
      throw const ApiException(400, 'vibono_weak_password', 'Das Passwort braucht mindestens 8 Zeichen.');
    }
    final me = _seedMe()
      ..['email'] = email
      ..['first_name'] = firstName ?? ''
      ..['points_balance'] = referralCode == null ? 0 : 100;
    await _saveMe(me);
    await _store.writeBool('mock.session', true);
    return Me.fromJson(me);
  }

  @override
  Future<void> logout() async => _store.writeBool('mock.session', false);

  @override
  Future<void> requestPasswordReset(String email) => _wait();

  @override
  Future<Me> me() async {
    await _wait();
    return Me.fromJson(_me);
  }

  @override
  Future<Me> updateProfile(Profile profile) async {
    await _wait();
    final me = _me..addAll(profile.toApiJson());
    await _saveMe(me);
    return Me.fromJson(me);
  }

  @override
  Future<void> deleteAccount() async {
    await _wait();
    await _store.writeJson('mock.me', null);
    await _store.writeJson('mock.server', null);
    await _store.writeJson('mock.ledger', null);
    await _store.writeBool('mock.session', false);
  }

  @override
  Future<void> registerDevice(String token, String platform) => _wait();

  // ---------- Synchronisation ----------

  @override
  Future<SyncPull> syncPull({String? cursor}) async {
    await _wait();
    final since = cursor == null ? null : DateTime.tryParse(cursor);
    final all = _server.values.map(SyncItem.fromJson).whereType<SyncItem>();
    final changes = since == null ? all.toList() : all.where((i) => i.updatedAt.isAfter(since)).toList();
    return SyncPull(
      cursor: DateTime.now().toUtc().toIso8601String(),
      hasMore: false,
      full: since == null,
      changes: changes,
    );
  }

  @override
  Future<SyncPushResult> syncPush(List<Json> changes) async {
    await _wait();
    final s = _server;
    final stale = <SyncItem>[];
    for (final c in changes) {
      final id = '${c['collection']}|${c['key']}';
      final existing = s[id] == null ? null : SyncItem.fromJson(s[id]!);
      final at = DateTime.parse(c['updated_at'] as String);
      if (existing != null && existing.updatedAt.isAfter(at)) {
        stale.add(existing);
        continue;
      }
      s[id] = {
        'collection': c['collection'],
        'key': c['key'],
        'data': c['data'] ?? <String, dynamic>{},
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'deleted': c['op'] == 'delete',
      };
    }
    await _saveServer(s);
    return SyncPushResult(cursor: null, serverItems: stale);
  }

  // ---------- Inhalte ----------

  List<ContentItem> get _recipes => [
        for (final r in mockRecipes)
          ContentItem.fromJson({
            ...r,
            'type': 'recipe',
            'excerpt': 'Energiedichte ${(r['energy_density'] as num).toString().replaceAll('.', ',')} kcal/g',
            'url': 'https://www.vibono.de/rezepte/',
            'content_html': mockRecipeHtml(r),
          }),
      ];

  List<ContentItem> get _tips => [
        for (final t in mockTips)
          ContentItem.fromJson({
            ...t,
            'type': 'tip',
            'excerpt': 'Ein Vibono-Tipp',
            'points_for_reading': 10,
            'url': 'https://www.vibono.de/tipps/',
          }),
      ];

  @override
  Future<List<Course>> courses() async {
    if (_courses != null) return _markDone(_courses!);
    final raw = jsonDecode(await rootBundle.loadString('assets/mock/courses.json')) as List;
    _courses = [
      for (final c in raw.cast<Map>())
        Course(
          id: c['id'] as int,
          title: c['title'] as String,
          lessons: [
            for (final l in (c['lessons'] as List).cast<Map>())
              ContentItem(
                id: l['id'] as int,
                type: ContentType.lesson,
                title: l['title'] as String,
                url: l['url'] as String,
                lessonKind: l['type'] as String,
                courseId: c['id'] as int,
                readingMinutes: 2 + (l['id'] as int) % 4,
                pointsForReading: 10,
              ),
          ],
        ),
    ];
    return _markDone(_courses!);
  }

  List<Course> _markDone(List<Course> cs) {
    final done = _doneLessons;
    return [
      for (final c in cs)
        Course(id: c.id, title: c.title, lessons: [
          for (final l in c.lessons)
            ContentItem.fromJson({...l.toJson(), 'done': done.contains(l.id)}),
        ]),
    ];
  }

  @override
  Future<List<ContentItem>> content(String type, {String? search, List<String>? tags, int? course, int page = 1}) async {
    await _wait();
    var items = switch (type) {
      'recipes' => _recipes,
      'tips' => _tips,
      'lessons' => [for (final c in await courses()) if (course == null || c.id == course) ...c.lessons],
      _ => <ContentItem>[],
    };
    if (search != null && search.trim().isNotEmpty) {
      final s = search.toLowerCase();
      items = items.where((i) => i.title.toLowerCase().contains(s)).toList();
    }
    if (tags != null && tags.isNotEmpty) {
      items = items.where((i) => tags.every(i.tags.contains)).toList();
    }
    return items;
  }

  @override
  Future<ContentItem> contentItem(int id) async {
    await _wait();
    final r = _recipes.where((r) => r.id == id).firstOrNull;
    if (r != null) return r;
    final all = [..._tips, for (final c in await courses()) ...c.lessons];
    final item = all.where((i) => i.id == id).firstOrNull;
    if (item == null) throw const ApiException(404, 'rest_post_invalid_id', 'Beitrag nicht gefunden.');
    final html = mockArticleHtml(item.title);
    return ContentItem.fromJson({
      ...item.toJson(),
      'content_html': html,
      'word_count': html.split(RegExp(r'\s+')).length,
    });
  }

  // Ablauf der Kurse je Phase (Kurs-IDs aus „Mein Coaching“).
  static const _phaseCourses = {
    PhaseKey.vorbereitung: [247, 248, 219],
    PhaseKey.phase1: [220, 251, 252],
    PhaseKey.phase2: [253, 221, 254, 256, 255],
    PhaseKey.phase3: [222, 257, 258, 260, 261],
  };

  @override
  Future<CoachingDay> coachingDay(DateTime date) async {
    await _wait();
    final me = _me;
    final profile = Profile.fromApiJson(me);
    final start = profile.coachingStartDate ?? CoachingPlan.dateOnly(DateTime.now()).add(const Duration(days: 1));
    final phase = CoachingPlan.phaseFor(start, date);
    final courses = await this.courses();
    final order = _phaseCourses[phase.key]!;
    final open = [
      for (final id in order)
        ...courses.where((c) => c.id == id).expand((c) => c.lessons).where((l) => l.done != true),
    ];
    final reading = open.where((l) => l.lessonKind == 'wichtig' || l.lessonKind == 'lesen').toList();
    final wissen = reading.isEmpty ? open.take(1).toList() : reading.take(2).toList();

    final level = profile.activityLevel ?? ActivityLevel.eingerostet;
    final baseMin = switch (level) {
      ActivityLevel.sportmuffel => 10,
      ActivityLevel.eingerostet => 15,
      ActivityLevel.moderatAktiv => 25,
      ActivityLevel.sehrAktiv => 40,
    };
    final minutes = min(baseMin + phase.coachingDay * (level == ActivityLevel.sehrAktiv ? 2 : 1), baseMin * 3);

    ContentItem task(int id, String title, String excerpt, String tag) => ContentItem(
        id: id, type: ContentType.lesson, title: title, excerpt: excerpt, lessonKind: 'aufgaben', tags: ['task:$tag']);

    final essen = switch (phase.key) {
      PhaseKey.vorbereitung => task(-1, 'Normal essen', 'Noch keine Umstellung nötig', 'essen'),
      PhaseKey.phase1 => task(-1, 'Ohne Kohlenhydrate', 'Eiweiß und Gemüse, 3× satt', 'essen'),
      PhaseKey.phase2 => task(-1, '3× satt essen', 'Grüne Energiedichte bevorzugen', 'essen'),
      PhaseKey.phase3 => task(-1, 'Satt essen & genießen', '3 Mahlzeiten, grün bevorzugt', 'essen'),
    };
    final bewegung = task(-2, '$minutes Min. gehen', 'Zügig, gern nach dem Essen', 'bewegung:$minutes');
    final sonstiges = <ContentItem>[
      if (phase.key == PhaseKey.vorbereitung)
        task(-4, 'Für die UT einkaufen', 'Einkaufsliste im Wochenplan', 'einkaufen'),
      task(-3, 'Gewicht eintragen', 'Morgens vor dem Frühstück', 'gewicht'),
    ];

    final recipesAll = _recipes;
    final plan = _server;
    final picked = RecipePicker.forDate(date, recipesAll, profile, phase.key);
    final recipes = <ContentItem>[];
    for (final s in MealSlot.values) {
      final key = 'weekplan|${_day(date)}:${s.wire}';
      final planned = plan[key];
      final rid = planned != null && planned['deleted'] != true ? asInt(asMap(planned['data'])?['recipe_id']) : null;
      recipes.add(recipesAll.where((r) => r.id == rid).firstOrNull ?? picked[s]!);
    }

    final dayIndex = CoachingPlan.daysBetween(DateTime(2026), date).abs();
    final tip = _tips[dayIndex % _tips.length];

    final milestones = [
      for (final (key, months, kg) in [
        ('m3', 3, profile.target3m),
        ('m6', 6, profile.target6m),
        ('m12', 12, profile.target12m),
      ])
        {'key': key, 'date': _day(DateTime(start.year, start.month + months, start.day)), 'target_weight_kg': kg, 'reached': false},
    ];
    final appOpenToday = (_store.readString('mock.appopen') ?? '') == _day(DateTime.now());
    final next = wissen.isNotEmpty ? wissen.first : sonstiges.first;

    return CoachingDay.fromJson({
      'date': _day(date),
      'phase': {
        'key': phase.key.name,
        'label': phase.label,
        'day_in_phase': phase.dayInPhase,
        'day_label': phase.dayLabel,
        'coaching_day': phase.coachingDay,
      },
      'progress': {
        'overall': (phase.coachingDay / 365).clamp(0, 1),
        'phase': CoachingPlan.phaseProgress(phase),
        'milestones': milestones,
      },
      'next_step': next.toJson(),
      'sections': {
        'essen': [essen.toJson()],
        'bewegung': [bewegung.toJson()],
        'wissen': [for (final w in wissen) w.toJson()],
        'sonstiges': [for (final s in sonstiges) s.toJson()],
      },
      'recipes': [for (final r in recipes) r.toJson()],
      'vibono_tip': tip.toJson(),
      'tip_of_the_day': {'id': null, 'text': mockTipsOfTheDay[dayIndex % mockTipsOfTheDay.length]},
      'points': {'balance': _balance, 'app_open_awarded_today': appOpenToday, 'streak': _streakView},
    });
  }

  @override
  Future<HomeFeed> home(DateTime date, String platform) async {
    await _wait();
    final today = CoachingPlan.dateOnly(DateTime.now());
    final day = DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/ 86400000;
    return HomeFeed.fromJson({
      'date': _day(date),
      'food': {
        // Vorgabe vom Vibono-Team (im Backend unter „Startseite Heute“ einstellbar).
        'keywords': ['Kürbis'],
        'spotlight': null,
      },
      'plan': {'quiz': mockQuiz[day % mockQuiz.length]},
      'challenges': mockChallenges(today),
      'news': [
        for (final n in mockNews(today))
          if (!(platform == 'ios' && n['kind'] == 'ebook')) n,
      ],
    });
  }

  // ---------- Punkte ----------

  static final _campaignEnd = DateTime.now().add(const Duration(days: 12));

  List<Json> get _campaigns => [
        {
          'id': 1,
          'name': 'Freunde-Wochen',
          'description': 'Doppelte Punkte für jede erfolgreiche Empfehlung.',
          'kind': 'earn',
          'reasons': ['referral'],
          'multiplier': 2,
          'starts_at': DateTime.now().subtract(const Duration(days: 2)).toUtc().toIso8601String(),
          'ends_at': _campaignEnd.toUtc().toIso8601String(),
          'active': true,
        },
      ];

  @override
  Future<PointsSummary> points() async {
    await _wait();
    return PointsSummary.fromJson({
      'balance': _balance,
      'pending': 45,
      'cents_per_point': 1,
      'effective_cents_per_point': 1,
      'value_cents': _balance,
      'earn_rules': {'app_open': 5, 'article_read': 10, 'referral': 1000, 'referral_friend': 200, 'purchase_per_euro': 1},
      'campaigns': _campaigns,
      'streak': _streakView,
    });
  }

  @override
  Future<List<LedgerEntry>> ledger({int page = 1}) async {
    await _wait();
    final l = (_store.readJson('mock.ledger') as List?) ?? _seedLedger();
    return asList(l, LedgerEntry.fromJson);
  }

  // ---------- Serie fürs tägliche Öffnen ----------

  static const _streakRules = AppStreakRules();

  /// Demo-Start: 6 Tage in Folge bis gestern, damit heute Stufe „ab Tag 7“ erreicht wird.
  Json get _streakState {
    final stored = asMap(_store.readJson('mock.streak'));
    if (stored != null) return stored;
    return {
      'days': 6,
      'best': 6,
      'last_date': _day(DateTime.now().subtract(const Duration(days: 1))),
      'grace_month': null,
      'grace_used': 0,
    };
  }

  Json get _streakView => _streakRules.view(_streakState, _day(DateTime.now()));

  @override
  Future<AwardResult> reportAppOpen() async {
    await _wait();
    final today = _day(DateTime.now());
    final (state, event, bridged) = _streakRules.advance(_streakState, today);
    final previous = asInt(_streakState['days']) ?? 0;
    await _store.writeJson('mock.streak', state);
    final view = {..._streakRules.view(state, today), 'event': event, 'bridged_days': bridged, 'previous_days': previous};
    final streak = AppStreak.fromJson(view);
    if (_store.readString('mock.appopen') == today) {
      return AwardResult(awardedPoints: 0, alreadyAwarded: true, balance: _balance, streak: streak);
    }
    await _store.writeString('mock.appopen', today);
    final day = streak.todayDay;
    final r = await _award(streak.todayPoints, 'app_open', day > 1 ? 'App heute geöffnet · $day Tage in Folge' : 'App heute geöffnet');
    return AwardResult(awardedPoints: r.awardedPoints, alreadyAwarded: false, balance: r.balance, streak: streak);
  }

  Set<int> get _rewardedReads => {...((_store.readJson('mock.reads') as List?) ?? const []).cast<int>()};

  @override
  Future<ReadingSession> startReading(int postId) async {
    await _wait();
    if (_rewardedReads.contains(postId)) {
      throw const ApiException(409, 'vibono_already_rewarded', 'Für diesen Artikel gab es schon Punkte.');
    }
    final item = await contentItem(postId);
    final words = item.wordCount ?? 300;
    // Mindestzeit: halbe normale Lesezeit (200 Wörter/Minute), mindestens 20 s.
    final minSec = max(20, (words / 200 * 60 * 0.5).round());
    final id = 'rs_${DateTime.now().microsecondsSinceEpoch}_${_rnd.nextInt(9999)}';
    final withQuiz = postId.isEven;
    _sessions[id] = (
      postId: postId,
      started: DateTime.now(),
      lastBeat: DateTime.now(),
      accepted: 0,
      depth: 0,
      min: minSec,
      quizCorrect: withQuiz ? 1 : null,
    );
    return ReadingSession.fromJson({
      'session_id': id,
      'post_id': postId,
      'word_count': words,
      'min_active_seconds': minSec,
      'min_scroll_depth': 0.9,
      'heartbeat_interval_seconds': 10,
      'points': 10,
      'quiz': withQuiz
          ? {
              'question': 'Was macht laut Beitrag lange satt?',
              'answers': ['Lebensmittel mit hoher Energiedichte', 'Lebensmittel mit niedriger Energiedichte', 'Viele kleine Snacks'],
            }
          : null,
    });
  }

  @override
  Future<ReadingProgress> readingHeartbeat(String sessionId, int activeSeconds, double scrollDepth) async {
    final s = _sessions[sessionId];
    if (s == null) throw const ApiException(404, 'vibono_reading_session_not_found', 'Lese-Session nicht gefunden.');
    // Server erkennt höchstens so viel Aktivzeit an, wie seit Start
    // tatsächlich vergangen ist (Wanduhr), plus kleine Toleranz.
    final wall = DateTime.now().difference(s.started).inSeconds + 2;
    final accepted = min(activeSeconds, wall);
    final depth = max(s.depth, scrollDepth.clamp(0.0, 1.0));
    _sessions[sessionId] = (
      postId: s.postId,
      started: s.started,
      lastBeat: DateTime.now(),
      accepted: accepted,
      depth: depth,
      min: s.min,
      quizCorrect: s.quizCorrect,
    );
    return ReadingProgress(
      acceptedActiveSeconds: accepted,
      scrollDepth: depth,
      readyToComplete: accepted >= s.min && depth >= 0.9,
    );
  }

  @override
  Future<AwardResult> completeReading(String sessionId, {int? quizAnswer}) async {
    await _wait();
    final s = _sessions[sessionId];
    if (s == null) throw const ApiException(404, 'vibono_reading_session_not_found', 'Lese-Session nicht gefunden.');
    if (s.accepted < s.min || s.depth < 0.9) {
      throw ApiException(422, 'vibono_reading_incomplete', 'Noch nicht fertig gelesen.', {
        'progress': {'accepted_active_seconds': s.accepted, 'min_active_seconds': s.min, 'scroll_depth': s.depth},
      });
    }
    if (s.quizCorrect != null && quizAnswer != s.quizCorrect) {
      throw const ApiException(422, 'vibono_quiz_wrong', 'Leider falsch.');
    }
    _sessions.remove(sessionId);
    await _store.writeJson('mock.reads', [..._rewardedReads, s.postId]);
    final item = await contentItem(s.postId);
    return _award(10, 'article_read', 'Artikel gelesen: ${item.title}');
  }

  @override
  Future<ReferralInfo> referral() async {
    await _wait();
    final code = asString(_me['referral_code']) ?? 'VIBONO';
    return ReferralInfo(
      code: code,
      link: 'https://www.vibono.de/?vref=$code',
      shareText: 'Ich nehme mit Vibono ab und werde dabei satt. Mit meinem Link bekommst du einen Willkommensbonus:',
      invited: 3,
      converted: 1,
      pointsEarned: 1000,
      pointsPerReferral: 2000,
      friendBonusPoints: 200,
    );
  }

  @override
  Future<Uri> webSession(String redirectPath) async {
    await _wait();
    return Uri.parse('https://www.vibono.de$redirectPath');
  }

  // ---------- Energiedichte ----------

  @override
  Future<List<Food>> foods(String query) async {
    await _wait(const Duration(milliseconds: 120));
    return FoodDatabase.search(query);
  }

  @override
  Future<RecipeScanResult> scanRecipe(String imageBase64, String mime) async {
    await _wait(const Duration(milliseconds: 1600));
    return RecipeScanResult.fromJson({
      'title': 'Linsen-Kokos-Curry',
      'servings': 2,
      'ingredients': [
        {'name': 'Rote Linsen, trocken', 'amount_g': 150, 'kcal_per_100g': 340, 'confidence': 0.95, 'raw_text': '150 g rote Linsen'},
        {'name': 'Kokosmilch', 'amount_g': 200, 'kcal_per_100g': 180, 'confidence': 0.9, 'raw_text': '200 ml Kokosmilch'},
        {'name': 'Tomaten aus der Dose', 'amount_g': 400, 'kcal_per_100g': 22, 'confidence': 0.55, 'raw_text': '1 Dose Tomaten'},
        {'name': 'Spinat', 'amount_g': 200, 'kcal_per_100g': 23, 'confidence': 0.92, 'raw_text': '200 g Blattspinat'},
        {'name': 'Gemüsebrühe', 'amount_g': 400, 'kcal_per_100g': 5, 'confidence': 0.85, 'raw_text': '400 ml Gemüsebrühe'},
      ],
    });
  }

  @override
  Future<PhotoAnalysisResult> analyzePhoto(String imageBase64, String mime, {String? description}) async {
    await _wait(const Duration(milliseconds: 1800));
    final hint = description?.trim();
    return PhotoAnalysisResult.fromJson({
      'dish': hint == null || hint.isEmpty ? 'Gemüsegulasch mit Kartoffeln' : hint,
      'portion_g': 450,
      'kcal_total': 270,
      'kcal_per_g': 0.6,
      'components': [
        {'name': 'Gemüse', 'share_pct': 62},
        {'name': 'Kartoffeln', 'share_pct': 28},
        {'name': 'Soße', 'share_pct': 10},
      ],
      'confidence': hint == null || hint.isEmpty ? 0.6 : 0.75,
      'notes': 'Restaurant-Aufschlag für Öl eingerechnet.',
    });
  }
}
