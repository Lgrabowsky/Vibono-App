import 'package:flutter_test/flutter_test.dart';
import 'package:vibono/data/models/points.dart';
import 'package:vibono/domain/app_streak_rules.dart';
import 'package:vibono/ui/widgets/streak.dart';

/// Gleiche Fälle wie tests/Unit/StreakMathTest.php im Plugin.
void main() {
  const rules = AppStreakRules();
  Map<String, dynamic> state(int days, String last, {String? month, int used = 0}) =>
      {'days': days, 'best': days, 'last_date': last, 'grace_month': month, 'grace_used': used};

  test('erstes Öffnen und Folgetage', () {
    var (s, e, _) = rules.advance(null, '2026-11-18');
    expect(e, 'first');
    expect(s['days'], 1);
    (s, e, _) = rules.advance(s, '2026-11-19');
    expect(e, 'continued');
    expect(s['days'], 2);
    final (same, e2, _) = rules.advance(s, '2026-11-19');
    expect(e2, 'same_day');
    expect(same['days'], 2);
  });

  test('Schutztag überbrückt eine Lücke', () {
    final (s, e, bridged) = rules.advance(state(6, '2026-11-16'), '2026-11-18');
    expect(e, 'bridged');
    expect(bridged, 1);
    expect(s['days'], 7);
    expect(rules.graceLeft(s, '2026-11-18'), 1);
    expect(rules.graceLeft(s, '2026-12-01'), 2);
  });

  test('Serie reißt: eine Stufe zurück bzw. neu', () {
    final (s, e, _) = rules.advance(state(20, '2026-11-10'), '2026-11-18');
    expect(e, 'broken');
    expect(s['days'], 7);
    expect(s['best'], 20);
    const reset = AppStreakRules(onBreak: 'reset');
    expect(reset.advance(state(20, '2026-11-10'), '2026-11-18').$1['days'], 1);
  });

  test('Ansicht wird zu AppStreak', () {
    final v = AppStreak.fromJson(rules.view(state(6, '2026-11-17'), '2026-11-18'));
    expect(v.enabled, isTrue);
    expect(v.alive, isTrue);
    expect(v.openedToday, isFalse);
    expect(v.todayDay, 7);
    expect(v.todayPoints, 8);
    expect(v.stage?.fromDay, 7);
    expect(v.stageIndex, 2);
    expect(v.nextStage?.fromDay, 14);
    expect(v.daysToNextStage, 7);
    expect(v.levels.length, 5);
    expect(streakHint(v), 'Noch 7 Tage bis 10 Punkte pro Tag.');
    expect(AppStreak.fromJson({'enabled': false}).enabled, isFalse);
    expect(AppStreak.fromJson(null).enabled, isFalse);
  });

  test('Meldung beim Öffnen', () {
    final neu = AppStreak.fromJson({...rules.view(state(7, '2026-11-18'), '2026-11-18'), 'event': 'continued'});
    expect(streakToastText(neu), 'Tag 7 in Folge. Ab heute 8 Punkte pro Tag!');
    final b = AppStreak.fromJson({...rules.view(state(5, '2026-11-18'), '2026-11-18'), 'event': 'bridged', 'bridged_days': 1});
    expect(streakToastText(b), contains('Schutztag'));
    expect(streakToastText(null), 'Schön, dass du heute da bist!');
  });
}
