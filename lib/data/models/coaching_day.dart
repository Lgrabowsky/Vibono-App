import 'content.dart';
import 'json.dart';
import 'points.dart';

enum PhaseKey { vorbereitung, phase1, phase2, phase3 }

PhaseKey phaseKeyFrom(String? s) => switch (s) {
      'phase1' => PhaseKey.phase1,
      'phase2' => PhaseKey.phase2,
      'phase3' => PhaseKey.phase3,
      _ => PhaseKey.vorbereitung,
    };

class Phase {
  const Phase({
    required this.key,
    required this.label,
    required this.dayInPhase,
    required this.dayLabel,
    required this.coachingDay,
  });

  final PhaseKey key;
  final String label;
  final int dayInPhase;
  final String dayLabel;
  final int coachingDay;

  factory Phase.fromJson(Json j) => Phase(
        key: phaseKeyFrom(asString(j['key'])),
        label: asString(j['label']) ?? '',
        dayInPhase: asInt(j['day_in_phase']) ?? 0,
        dayLabel: asString(j['day_label']) ?? '',
        coachingDay: asInt(j['coaching_day']) ?? 0,
      );
}

class Milestone {
  const Milestone({required this.key, required this.date, this.targetWeightKg, this.reached = false});
  final String key;
  final DateTime date;
  final double? targetWeightKg;
  final bool reached;

  factory Milestone.fromJson(Json j) => Milestone(
        key: asString(j['key']) ?? '',
        date: DateTime.tryParse(asString(j['date']) ?? '') ?? DateTime.now(),
        targetWeightKg: asDouble(j['target_weight_kg']),
        reached: asBool(j['reached']),
      );
}

/// Tagesübersicht (`GET /coaching/today`). Bewusst ohne Uhrzeiten.
class CoachingDay {
  const CoachingDay({
    required this.date,
    required this.phase,
    required this.overallProgress,
    required this.phaseProgress,
    required this.milestones,
    required this.nextStep,
    required this.essen,
    required this.bewegung,
    required this.wissen,
    required this.sonstiges,
    required this.recipes,
    required this.vibonoTip,
    required this.tipOfTheDay,
    required this.pointsBalance,
    required this.appOpenAwardedToday,
    this.streak = AppStreak.disabled,
  });

  final DateTime date;
  final Phase phase;
  final double overallProgress;
  final double phaseProgress;
  final List<Milestone> milestones;
  final ContentItem? nextStep;
  final List<ContentItem> essen;
  final List<ContentItem> bewegung;
  final List<ContentItem> wissen;
  final List<ContentItem> sonstiges;
  final List<ContentItem> recipes;
  final ContentItem? vibonoTip;
  final String tipOfTheDay;
  final int pointsBalance;
  final bool appOpenAwardedToday;
  final AppStreak streak;

  factory CoachingDay.fromJson(Json j) {
    final sections = asMap(j['sections']) ?? const {};
    final progress = asMap(j['progress']) ?? const {};
    final points = asMap(j['points']) ?? const {};
    ContentItem? item(Object? v) => v is Map ? ContentItem.fromJson(Json.from(v)) : null;
    return CoachingDay(
      date: DateTime.tryParse(asString(j['date']) ?? '') ?? DateTime.now(),
      phase: Phase.fromJson(asMap(j['phase']) ?? const {}),
      overallProgress: asDouble(progress['overall']) ?? 0,
      phaseProgress: asDouble(progress['phase']) ?? 0,
      milestones: asList(progress['milestones'], Milestone.fromJson),
      nextStep: item(j['next_step']),
      essen: asList(sections['essen'], ContentItem.fromJson),
      bewegung: asList(sections['bewegung'], ContentItem.fromJson),
      wissen: asList(sections['wissen'], ContentItem.fromJson),
      sonstiges: asList(sections['sonstiges'], ContentItem.fromJson),
      recipes: asList(j['recipes'], ContentItem.fromJson),
      vibonoTip: item(j['vibono_tip']),
      tipOfTheDay: asString(asMap(j['tip_of_the_day'])?['text']) ?? '',
      pointsBalance: asInt(points['balance']) ?? 0,
      appOpenAwardedToday: asBool(points['app_open_awarded_today']),
      streak: AppStreak.fromJson(asMap(points['streak'])),
    );
  }
}
