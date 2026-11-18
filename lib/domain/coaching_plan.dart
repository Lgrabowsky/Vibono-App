import '../data/models/coaching_day.dart';

/// Das strukturierte Vibono-Konzept als Abfolge von Tagen:
/// Vorbereitung → Phase 1 (2 Umstellungstage) → Phase 2 (10 Tage
/// „Gewohnheiten ändern“) → Phase 3 („Satt essen & genießen“, dauerhaft).
abstract final class CoachingPlan {
  static const utDays = 2;
  static const phase2Days = 10;

  /// Tage ohne Uhrzeit vergleichen.
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static int daysBetween(DateTime a, DateTime b) =>
      dateOnly(b).difference(dateOnly(a)).inHours ~/ 24;

  static Phase phaseFor(DateTime start, DateTime date) {
    final diff = daysBetween(start, date);
    if (diff < 0) {
      final left = -diff;
      return Phase(
        key: PhaseKey.vorbereitung,
        label: 'Vorbereitung',
        dayInPhase: 1,
        dayLabel: left == 1 ? 'Morgen geht es los' : 'Noch $left Tage bis zum Start',
        coachingDay: 0,
      );
    }
    if (diff < utDays) {
      return Phase(
        key: PhaseKey.phase1,
        label: 'Phase 1: Umstellungstage',
        dayInPhase: diff + 1,
        dayLabel: '${diff + 1}. Umstellungstag',
        coachingDay: diff + 1,
      );
    }
    if (diff < utDays + phase2Days) {
      final d = diff - utDays + 1;
      return Phase(
        key: PhaseKey.phase2,
        label: 'Phase 2: Gewohnheiten ändern',
        dayInPhase: d,
        dayLabel: 'Tag $d/$phase2Days',
        coachingDay: diff + 1,
      );
    }
    final d = diff - utDays - phase2Days + 1;
    return Phase(
      key: PhaseKey.phase3,
      label: 'Phase 3: Satt essen & genießen',
      dayInPhase: d,
      dayLabel: 'Tag $d',
      coachingDay: diff + 1,
    );
  }

  /// Füllstand der aktuellen Phase (0..1) für den Fortschrittsbalken.
  /// Phase 3 läuft bis zum 12-Monats-Ziel.
  static double phaseProgress(Phase p) => switch (p.key) {
        PhaseKey.vorbereitung => 0.5,
        PhaseKey.phase1 => p.dayInPhase / utDays,
        PhaseKey.phase2 => p.dayInPhase / phase2Days,
        PhaseKey.phase3 => (p.dayInPhase / (365 - utDays - phase2Days)).clamp(0.02, 1.0),
      };

  /// Kurzer Text unter dem Balken, z. B. „Phase 2 · Tag 3/10“.
  static String shortLabel(Phase p) => switch (p.key) {
        PhaseKey.vorbereitung => 'Vorbereitung',
        PhaseKey.phase1 => 'Phase 1 · ${p.dayLabel}',
        PhaseKey.phase2 => 'Phase 2 · ${p.dayLabel}',
        PhaseKey.phase3 => 'Phase 3 · ${p.dayLabel}',
      };
}
