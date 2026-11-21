import '../data/models/home_feed.dart';
import '../data/models/json.dart';
import 'coaching_plan.dart';

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Teilnahme an einer Challenge (Sync-Sammlung `challenges`, Schlüssel = ID).
class ChallengeEntry {
  const ChallengeEntry({required this.joinedOn, this.startKg, this.days = const {}, this.items = const []});

  final DateTime joinedOn;

  /// Gewicht beim Mitmachen (nur Abnehmziel).
  final double? startKg;

  /// Tagesziel: erreichte Menge je Tag (`YYYY-MM-DD` → Anzahl).
  final Map<String, int> days;

  /// Sammeln: eingetragene Dinge, z. B. neue Lebensmittel.
  final List<String> items;

  static ChallengeEntry? fromJson(Json? j) {
    if (j == null) return null;
    final joined = DateTime.tryParse(asString(j['joined_on']) ?? '');
    if (joined == null) return null;
    final raw = asMap(j['days']) ?? const {};
    return ChallengeEntry(
      joinedOn: joined,
      startKg: asDouble(j['start_kg']),
      days: {for (final e in raw.entries) if ((asInt(e.value) ?? 0) > 0) e.key: asInt(e.value)!},
      items: asStringList(j['items']),
    );
  }

  Json toJson() => {
        'joined_on': _day(joinedOn),
        'start_kg': startKg,
        'days': days,
        'items': items,
      };

  int countOn(DateTime d) => days[_day(d)] ?? 0;

  ChallengeEntry withCount(DateTime d, int n) => ChallengeEntry(
        joinedOn: joinedOn,
        startKg: startKg,
        days: {...days, _day(d): n}..removeWhere((_, v) => v <= 0),
        items: items,
      );

  ChallengeEntry withItems(List<String> next) =>
      ChallengeEntry(joinedOn: joinedOn, startKg: startKg, days: days, items: next);
}

/// Stand einer Challenge, wie ihn die Karte zeigt. Bewusst ohne Countdown.
class ChallengeStatus {
  const ChallengeStatus({
    required this.value,
    required this.target,
    required this.label,
    required this.done,
    required this.ended,
    this.todayCount,
    this.hint,
  });

  final double value;
  final double target;
  final String label;
  final bool done;
  final bool ended;

  /// Tagesziel: heute schon erreicht.
  final int? todayCount;

  /// Kurzer Hinweis, z. B. „Trag dein Gewicht ein“.
  final String? hint;

  double get progress => target <= 0 ? 0 : (value / target).clamp(0, 1).toDouble();
}

String formatNumber(double v, {int digits = 1}) {
  final s = v.toStringAsFixed(digits);
  final trimmed = s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  return trimmed.replaceAll('.', ',');
}

abstract final class ChallengeProgress {
  /// [weights]: alle Gewichtseinträge (Datum, kg).
  static ChallengeStatus status(
    Challenge c,
    ChallengeEntry e,
    DateTime today, {
    List<(DateTime, double)> weights = const [],
  }) {
    final t = CoachingPlan.dateOnly(today);
    final ended = c.endsOn != null && t.isAfter(c.endsOn!);
    switch (c.kind) {
      case ChallengeKind.weightLoss:
        final sorted = [...weights]..sort((a, b) => a.$1.compareTo(b.$1));
        final latest = sorted.isEmpty ? null : sorted.last.$2;
        // Startgewicht: beim Mitmachen gemerkt, sonst der letzte Wert davor bzw. der erste danach.
        final before = sorted.where((w) => !w.$1.isAfter(e.joinedOn)).toList();
        final start = e.startKg ?? (before.isNotEmpty ? before.last.$2 : (sorted.isEmpty ? null : sorted.first.$2));
        final lost = start == null || latest == null ? 0.0 : (start - latest).clamp(0, 200).toDouble();
        return ChallengeStatus(
          value: lost,
          target: c.target,
          label: '${formatNumber(lost)} von ${formatNumber(c.target)} ${c.unit}',
          done: lost >= c.target,
          ended: ended,
          hint: start == null ? 'Trag dein Gewicht ein, dann geht es los.' : null,
        );
      case ChallengeKind.dailyGoal:
        final goal = c.dailyTarget ?? 1;
        final reached = e.days.values.where((n) => n >= goal).length;
        return ChallengeStatus(
          value: reached.toDouble(),
          target: c.target,
          label: '$reached von ${c.target.round()} Tagen',
          done: reached >= c.target,
          ended: ended,
          todayCount: e.countOn(t),
        );
      case ChallengeKind.collect:
        final n = e.items.length;
        return ChallengeStatus(
          value: n.toDouble(),
          target: c.target,
          label: '$n von ${c.target.round()} ${c.unit}',
          done: n >= c.target,
          ended: ended,
        );
    }
  }
}

/// Motivationsschub, wenn eine Weile keine Lektion gelesen wurde.
class Nudge {
  const Nudge({required this.days, required this.title, required this.text});
  final int days;
  final String title;
  final String text;
}

abstract final class InactivityNudge {
  /// Ab so vielen Tagen ohne Lektion gibt es einen Schubs.
  static const minDays = 2;

  /// [lastActivity]: letzte gelesene Lektion, ersatzweise Beginn des Coachings.
  static Nudge? forDays(DateTime? lastActivity, DateTime today) {
    if (lastActivity == null) return null;
    final days = CoachingPlan.daysBetween(CoachingPlan.dateOnly(lastActivity), CoachingPlan.dateOnly(today));
    if (days < minDays) return null;
    if (days <= 3) {
      return Nudge(
        days: days,
        title: 'Kleiner Schubs',
        text: 'Seit $days Tagen keine Lektion. Drei Minuten reichen, um wieder reinzukommen.',
      );
    }
    if (days <= 7) {
      return Nudge(
        days: days,
        title: 'Hey, dein Coaching wartet auf dich',
        text: '$days Tage Pause sind okay. Heute ist ein guter Tag, um weiterzumachen. Die nächste Lektion liegt schon bereit.',
      );
    }
    return Nudge(
      days: days,
      title: 'Zeit für einen Neustart',
      text: 'Ganz ohne schlechtes Gewissen: Fang einfach mit einer Lektion an. Jeder Tag ist eine neue Chance.',
    );
  }
}
