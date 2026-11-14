import 'package:flutter_test/flutter_test.dart';
import 'package:vibono/data/models/coaching_day.dart';
import 'package:vibono/data/models/content.dart';
import 'package:vibono/data/models/energy.dart';
import 'package:vibono/data/models/profile.dart';
import 'package:vibono/domain/coaching_plan.dart';
import 'package:vibono/domain/energy_density.dart';
import 'package:vibono/domain/goals.dart';
import 'package:vibono/domain/notification_planner.dart';
import 'package:vibono/domain/recipe_picker.dart';

ContentItem recipe(int id, List<String> tags) =>
    ContentItem(id: id, type: ContentType.recipe, title: 'Rezept $id', tags: tags);

void main() {
  group('Energiedichte', () {
    test('Ampel-Grenzen 1,5 und 2,5 kcal/g', () {
      expect(EnergyDensity.ampel(0.6), Ampel.gruen);
      expect(EnergyDensity.ampel(1.5), Ampel.gruen);
      expect(EnergyDensity.ampel(1.51), Ampel.gelb);
      expect(EnergyDensity.ampel(2.5), Ampel.gelb);
      expect(EnergyDensity.ampel(2.6), Ampel.rot);
    });

    test('rechnet kcal pro Gramm über alle vollständigen Zutaten', () {
      // Beispiel aus dem Entwurf: 867 kcal auf 1.100 g = 0,79 kcal/g
      final r = EnergyDensity.compute(const [
        Ingredient(name: 'Zucchini', grams: 300, kcalPer100g: 19),
        Ingredient(name: 'Passierte Tomaten', grams: 400, kcalPer100g: 30),
        Ingredient(name: 'Rinderhack', grams: 150, kcalPer100g: 210),
        Ingredient(name: 'Nudeln, gekocht', grams: 250, kcalPer100g: 150),
        Ingredient(name: 'Unklar', grams: null, kcalPer100g: 100),
      ]);
      expect(r.grams, 1100);
      expect(r.kcal, closeTo(867, 0.01));
      expect(r.density, closeTo(0.788, 0.001));
      expect(EnergyDensity.format(r.density!), '0,79');
    });

    test('unsichere Scan-Zeilen werden zum Prüfen markiert', () {
      expect(const Ingredient(name: 'x', grams: 100, kcalPer100g: 20, confidence: 0.5).needsReview, isTrue);
      expect(const Ingredient(name: 'x', grams: 100, kcalPer100g: 20, confidence: 0.9).needsReview, isFalse);
    });
  });

  group('Coaching-Ablauf', () {
    final start = DateTime(2026, 11, 16);

    test('Vorbereitung, Umstellungstage, Phase 2, Phase 3', () {
      expect(CoachingPlan.phaseFor(start, DateTime(2026, 11, 15)).key, PhaseKey.vorbereitung);
      final ut1 = CoachingPlan.phaseFor(start, DateTime(2026, 11, 16));
      expect(ut1.key, PhaseKey.phase1);
      expect(ut1.dayLabel, '1. Umstellungstag');
      expect(CoachingPlan.phaseFor(start, DateTime(2026, 11, 17)).dayLabel, '2. Umstellungstag');
      final p2 = CoachingPlan.phaseFor(start, DateTime(2026, 11, 20));
      expect(p2.key, PhaseKey.phase2);
      expect(CoachingPlan.shortLabel(p2), 'Phase 2 · Tag 3/10');
      expect(CoachingPlan.phaseFor(start, DateTime(2026, 11, 28)).key, PhaseKey.phase3);
    });

    test('Tageswechsel über Sommerzeit bleibt korrekt', () {
      final s = DateTime(2027, 3, 27);
      expect(CoachingPlan.daysBetween(s, DateTime(2027, 3, 29)), 2);
    });

    test('Etappenziele mit gesundem Tempo', () {
      final g = Goals.suggest(98.4);
      expect(g.m3, lessThan(98.4));
      expect(g.m6, lessThan(g.m3));
      expect(g.m12, lessThan(g.m6));
      expect(Goals.feedback(98.4, g.m3, g.m12), startsWith('Realistisch'));
      expect(Goals.feedback(100, 80, 70), contains('sportlich'));
    });
  });

  group('Rezeptauswahl', () {
    final recipes = [
      recipe(1, ['fruehstueck', 'vegetarisch']),
      recipe(2, ['mittag', 'abend', 'fleisch', 'ut-geeignet']),
      recipe(3, ['mittag', 'abend', 'vegan']),
      recipe(4, ['mittag', 'abend', 'vegetarisch']),
    ];

    test('vegan bekommt nur vegane Rezepte', () {
      final r = RecipePicker.forDate(DateTime(2026, 11, 14), recipes, const Profile(diet: Diet.vegan), PhaseKey.phase2);
      expect(r.values.every((x) => x.tags.contains('vegan')), isTrue);
    });

    test('in den Umstellungstagen nur UT-geeignete Rezepte', () {
      final r = RecipePicker.forDate(DateTime(2026, 11, 14), recipes, const Profile(), PhaseKey.phase1);
      expect(r.values.every((x) => x.tags.contains('ut-geeignet')), isTrue);
    });

    test('Abneigungen werden ausgeschlossen', () {
      expect(
        RecipePicker.fits(
          const ContentItem(id: 9, type: ContentType.recipe, title: 'Pilzpfanne mit Pilzen', tags: ['mittag']),
          const Profile(dislikes: ['Pilz']),
          PhaseKey.phase3,
        ),
        isFalse,
      );
    });
  });

  group('Benachrichtigungen', () {
    CoachingDay day(DateTime d) => CoachingDay(
          date: d,
          phase: const Phase(key: PhaseKey.phase2, label: '', dayInPhase: 3, dayLabel: '', coachingDay: 5),
          overallProgress: 0,
          phaseProgress: 0.3,
          milestones: const [],
          nextStep: const ContentItem(id: 1, type: ContentType.lesson, title: 'Die Energiedichte'),
          essen: const [],
          bewegung: const [ContentItem(id: -2, type: ContentType.lesson, title: '20 Min. gehen')],
          wissen: const [ContentItem(id: 2, type: ContentType.lesson, title: 'Grüne Lebensmittel')],
          sonstiges: const [ContentItem(id: -3, type: ContentType.lesson, title: 'Gewicht eintragen')],
          recipes: [recipe(10, []), recipe(11, []), recipe(12, [])],
          vibonoTip: const ContentItem(id: 5, type: ContentType.tip, title: 'Schweinehund'),
          tipOfTheDay: 'Teller zur Hälfte mit Gemüse',
          pointsBalance: 0,
          appOpenAwardedToday: false,
        );

    test('höchstens die eingestellte Anzahl, nie in der Ruhezeit', () {
      final d = DateTime(2030, 1, 10);
      for (final n in [1, 5, 10]) {
        final plans = NotificationPlanner.plan(
          day(d),
          Profile(notificationsPerDay: n, notificationTopics: const [], quietStart: '21:00', quietEnd: '07:30'),
          now: DateTime(2030, 1, 10, 0, 1),
        );
        expect(plans.length, n);
        for (final p in plans) {
          final minutes = p.at.hour * 60 + p.at.minute;
          expect(minutes, greaterThanOrEqualTo(7 * 60 + 30));
          expect(minutes, lessThanOrEqualTo(21 * 60));
        }
      }
    });

    test('0 Nachrichten und Themenfilter', () {
      final d = DateTime(2030, 1, 10);
      expect(NotificationPlanner.plan(day(d), const Profile(notificationsPerDay: 0)), isEmpty);
      final onlyRecipes = NotificationPlanner.plan(
        day(d),
        const Profile(notificationsPerDay: 10, notificationTopics: ['rezepte']),
        now: DateTime(2030, 1, 10),
      );
      expect(onlyRecipes.every((p) => p.topic == 'rezepte'), isTrue);
      expect(onlyRecipes.length, 3);
    });

    test('vergangene Zeitpunkte werden nicht geplant', () {
      final d = DateTime(2030, 1, 10);
      final plans = NotificationPlanner.plan(day(d), const Profile(notificationsPerDay: 10, notificationTopics: []),
          now: DateTime(2030, 1, 10, 15));
      expect(plans.every((p) => p.at.isAfter(DateTime(2030, 1, 10, 15))), isTrue);
    });
  });
}
