import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config.dart';
import '../data/models/home_feed.dart';
import '../data/models/json.dart';
import '../data/models/sync_item.dart';
import '../domain/coaching_plan.dart';
import '../domain/food_suggestions.dart';
import '../domain/home_progress.dart';
import '../services/weather_service.dart';
import 'day_checks.dart';
import 'providers.dart';

/// Einstellungen der Startseite, nur auf dem Gerät.
class HomeSettings {
  const HomeSettings({
    this.weatherOn = true,
    this.weatherPlace,
    this.keywords = const [],
    this.prefsCheckedOn,
  });

  final bool weatherOn;

  /// Ort fürs Wetter, z. B. „Köln“ oder eine Postleitzahl.
  final String? weatherPlace;

  /// Eigene Stichwörter („Worauf hast du Lust?“).
  final List<String> keywords;

  /// Zuletzt bestätigt, dass die Vorlieben noch passen.
  final DateTime? prefsCheckedOn;

  HomeSettings copyWith({bool? weatherOn, String? weatherPlace, List<String>? keywords, DateTime? prefsCheckedOn}) =>
      HomeSettings(
        weatherOn: weatherOn ?? this.weatherOn,
        weatherPlace: weatherPlace ?? this.weatherPlace,
        keywords: keywords ?? this.keywords,
        prefsCheckedOn: prefsCheckedOn ?? this.prefsCheckedOn,
      );

  Json toJson() => {
        'weather_on': weatherOn,
        'weather_place': weatherPlace,
        'keywords': keywords,
        'prefs_checked_on': prefsCheckedOn == null ? null : dayKey(prefsCheckedOn!),
      };

  factory HomeSettings.fromJson(Json? j) => j == null
      ? const HomeSettings()
      : HomeSettings(
          weatherOn: j['weather_on'] == null ? true : asBool(j['weather_on']),
          weatherPlace: asString(j['weather_place']),
          keywords: asStringList(j['keywords']),
          prefsCheckedOn: DateTime.tryParse(asString(j['prefs_checked_on']) ?? ''),
        );
}

class HomeSettingsNotifier extends Notifier<HomeSettings> {
  static const _k = 'u.home.settings';

  @override
  HomeSettings build() {
    ref.watch(sessionProvider.select((s) => s.me?.id));
    final s = HomeSettings.fromJson(asMap(ref.read(storeProvider).readJson(_k)));
    // Beim ersten Mal gilt heute als bestätigt, nachgefragt wird später.
    if (s.prefsCheckedOn == null) Future.microtask(confirmPreferences);
    return s;
  }

  Future<void> _save(HomeSettings s) async {
    state = s;
    await ref.read(storeProvider).writeJson(_k, s.toJson());
  }

  Future<void> setWeather({required bool on, String? place}) =>
      _save(HomeSettings(weatherOn: on, weatherPlace: place?.trim(), keywords: state.keywords, prefsCheckedOn: state.prefsCheckedOn));

  Future<void> setKeywords(List<String> keywords) => _save(state.copyWith(
        keywords: [
          for (final k in keywords)
            if (k.trim().isNotEmpty) k.trim(),
        ],
      ));

  Future<void> confirmPreferences() => _save(state.copyWith(prefsCheckedOn: CoachingPlan.dateOnly(DateTime.now())));

  /// Alle so vielen Tage fragt die App, ob die Vorlieben noch passen.
  static const checkEveryDays = 30;
}

extension HomeSettingsX on HomeSettings {
  bool get preferencesCheckDue {
    final last = prefsCheckedOn;
    return last != null &&
        CoachingPlan.daysBetween(last, CoachingPlan.dateOnly(DateTime.now())) >= HomeSettingsNotifier.checkEveryDays;
  }
}

final homeSettingsProvider = NotifierProvider<HomeSettingsNotifier, HomeSettings>(HomeSettingsNotifier.new);

/// Startseite vom Server. Ohne Verbindung (oder mit älterem Plugin) leer,
/// die App zeigt dann nur, was sie selbst berechnen kann.
final homeFeedProvider = FutureProvider.family<HomeFeed, DateTime>((ref, date) async {
  try {
    return await ref.watch(apiProvider).home(date, platformName);
  } catch (_) {
    return HomeFeed.empty;
  }
});

final weatherSourceProvider = Provider<WeatherSource>(
  (ref) => AppConfig.useMocks ? const DemoWeather() : OpenMeteoWeather(),
);

/// Aktuelles Wetter am eingestellten Ort, höchstens stündlich neu.
final weatherProvider = FutureProvider<WeatherInfo?>((ref) async {
  final s = ref.watch(homeSettingsProvider);
  if (!s.weatherOn) return null;
  final store = ref.read(storeProvider);
  const k = 'u.home.weather';
  final cached = asMap(store.readJson(k));
  final at = DateTime.tryParse(asString(cached?['at']) ?? '');
  if (cached != null &&
      asString(cached['place']) == s.weatherPlace &&
      at != null &&
      DateTime.now().difference(at) < const Duration(hours: 1)) {
    final t = asDouble(cached['temp']);
    final kind = WeatherKind.values.where((w) => w.name == asString(cached['kind'])).firstOrNull;
    if (t != null && kind != null) return WeatherInfo(tempC: t, kind: kind, place: asString(cached['label']));
  }
  final w = await ref.read(weatherSourceProvider).current(s.weatherPlace);
  if (w != null) {
    await store.writeJson(k, {
      'at': DateTime.now().toIso8601String(),
      'place': s.weatherPlace,
      'temp': w.tempC,
      'kind': w.kind.name,
      'label': w.place,
    });
  }
  return w;
});

// ---------------------------------------------------------------------------
// Challenges
// ---------------------------------------------------------------------------

/// Teilnahmen aus der Sync-Sammlung `challenges` (ID → Eintrag).
final challengeEntriesProvider = Provider<Map<int, ChallengeEntry>>((ref) {
  final sync = ref.watch(syncProvider);
  return {
    for (final i in sync.items(SyncCollection.challenges))
      if (int.tryParse(i.key) != null && ChallengeEntry.fromJson(i.data) != null)
        int.parse(i.key): ChallengeEntry.fromJson(i.data)!,
  };
});

/// Alle Gewichtseinträge als (Datum, kg).
final weightEntriesProvider = Provider<List<(DateTime, double)>>((ref) {
  final sync = ref.watch(syncProvider);
  return [
    for (final i in sync.items(SyncCollection.weight))
      if (DateTime.tryParse(i.key) != null && asDouble(i.data['kg']) != null)
        (DateTime.parse(i.key), asDouble(i.data['kg'])!),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
});

Future<void> joinChallenge(WidgetRef ref, Challenge c) {
  final weights = ref.read(weightEntriesProvider);
  final entry = ChallengeEntry(
    joinedOn: CoachingPlan.dateOnly(DateTime.now()),
    startKg: c.kind == ChallengeKind.weightLoss && weights.isNotEmpty ? weights.last.$2 : null,
  );
  return ref.read(syncProvider).upsert(SyncCollection.challenges, '${c.id}', entry.toJson());
}

Future<void> leaveChallenge(WidgetRef ref, Challenge c) =>
    ref.read(syncProvider).remove(SyncCollection.challenges, '${c.id}');

Future<void> saveChallengeEntry(WidgetRef ref, Challenge c, ChallengeEntry e) =>
    ref.read(syncProvider).upsert(SyncCollection.challenges, '${c.id}', e.toJson());

// ---------------------------------------------------------------------------
// Quiz des Tages
// ---------------------------------------------------------------------------

/// Gegebene Antwort auf das Quiz eines Tages (nur auf dem Gerät).
class QuizAnswers extends Notifier<Map<String, int>> {
  static const _k = 'u.home.quiz';

  @override
  Map<String, int> build() {
    final raw = asMap(ref.read(storeProvider).readJson(_k)) ?? const {};
    return {for (final e in raw.entries) if (asInt(e.value) != null) e.key: asInt(e.value)!};
  }

  static String key(DateTime date, QuizQuestion q) => '${dayKey(date)}|${q.id}';

  Future<void> answer(DateTime date, QuizQuestion q, int index) async {
    // Nur die letzten 30 Antworten behalten.
    final next = {...state, key(date, q): index};
    final keys = next.keys.toList()..sort();
    for (final k in keys.take((keys.length - 30).clamp(0, keys.length))) {
      next.remove(k);
    }
    state = next;
    await ref.read(storeProvider).writeJson(_k, next);
  }
}

final quizAnswersProvider = NotifierProvider<QuizAnswers, Map<String, int>>(QuizAnswers.new);

// ---------------------------------------------------------------------------
// Motivationsschub
// ---------------------------------------------------------------------------

/// Letzte gelesene Lektion, ersatzweise der Beginn des Coachings.
final lastLessonActivityProvider = Provider<DateTime?>((ref) {
  final sync = ref.watch(syncProvider);
  DateTime? last;
  for (final i in sync.items(SyncCollection.lessonsDone)) {
    final t = i.updatedAt.toLocal();
    if (last == null || t.isAfter(last)) last = t;
  }
  if (last != null) return last;
  final start = ref.watch(sessionProvider.select((s) => s.profile.coachingStartDate));
  if (start == null || start.isAfter(DateTime.now())) return null;
  return start;
});
