import '../data/models/json.dart';

/// Regeln der Serie fürs tägliche Öffnen, wie im Plugin (Core/StreakMath.php).
/// Die echte App bekommt den Stand vom Server; diese Kopie braucht nur der
/// Demo-Modus (Mock-API), damit die Serie dort genauso funktioniert.
class AppStreakRules {
  const AppStreakRules({
    this.levels = const [(1, 5), (3, 6), (7, 8), (14, 10), (30, 12)],
    this.gracePerMonth = 2,
    this.onBreak = 'drop_level',
  });

  /// (ab Tag, Punkte pro Tag), aufsteigend, erste Stufe ab Tag 1.
  final List<(int, int)> levels;
  final int gracePerMonth;
  final String onBreak;

  static String day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static int daysBetween(String from, String to) {
    final a = DateTime.parse(from);
    final b = DateTime.parse(to);
    return DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
  }

  int stageIndex(int days) {
    var i = 0;
    for (var k = 0; k < levels.length; k++) {
      if (days >= levels[k].$1) i = k;
    }
    return i;
  }

  int graceLeft(Json s, String today) {
    final used = s['grace_month'] == today.substring(0, 7) ? (asInt(s['grace_used']) ?? 0) : 0;
    return (gracePerMonth - used).clamp(0, gracePerMonth);
  }

  /// Öffnen am Tag [today] verbuchen. Gibt neuen Zustand und Ereignis zurück.
  (Json, String, int) advance(Json? state, String today) {
    final s = Json.from(state ?? const {});
    final prev = asInt(s['days']) ?? 0;
    final last = asString(s['last_date']);
    var event = 'same_day';
    var bridged = 0;
    if (last == null || prev <= 0) {
      s['days'] = 1;
      event = 'first';
    } else {
      final gap = daysBetween(last, today);
      if (gap <= 0) return (s, 'same_day', 0);
      if (gap == 1) {
        s['days'] = prev + 1;
        event = 'continued';
      } else {
        final missed = gap - 1;
        if (missed <= graceLeft(s, today)) {
          final month = today.substring(0, 7);
          s['grace_used'] = (s['grace_month'] == month ? (asInt(s['grace_used']) ?? 0) : 0) + missed;
          s['grace_month'] = month;
          s['days'] = prev + 1;
          event = 'bridged';
          bridged = missed;
        } else {
          final i = stageIndex(prev);
          s['days'] = onBreak == 'drop_level' && i > 0 ? levels[i - 1].$1 : 1;
          event = 'broken';
        }
      }
    }
    s['last_date'] = today;
    s['best'] = [asInt(s['best']) ?? 0, s['days'] as int].reduce((a, b) => a > b ? a : b);
    return (s, event, bridged);
  }

  /// Antwort im Format von GET /points → streak.
  Json view(Json? state, String today) {
    final s = state ?? const {};
    final last = asString(s['last_date']);
    final opened = last != null && daysBetween(last, today) <= 0;
    final (preview, event, _) = advance(state, today);
    final days = asInt(s['days']) ?? 0;
    final alive = opened || (days > 0 && (event == 'continued' || event == 'bridged'));
    final todayDay = preview['days'] as int;
    final i = stageIndex(todayDay);
    final next = i + 1 < levels.length ? levels[i + 1] : null;
    return {
      'enabled': true,
      'days': opened || alive ? days : 0,
      'best': asInt(s['best']) ?? 0,
      'opened_today': opened,
      'alive': alive,
      'today': {'day': todayDay, 'points': levels[i].$2},
      'stage': {'from_day': levels[i].$1, 'points': levels[i].$2},
      'next_stage': next == null ? null : {'from_day': next.$1, 'points': next.$2, 'days_left': next.$1 - todayDay},
      'levels': [for (final l in levels) {'from_day': l.$1, 'points': l.$2}],
      'grace_per_month': gracePerMonth,
      'grace_left': graceLeft(opened ? Json.from(s) : preview, today),
      'on_break': onBreak,
    };
  }
}
