import 'package:flutter_test/flutter_test.dart';
import 'package:vibono/data/models/app_config.dart';
import 'package:vibono/data/models/coaching_day.dart';
import 'package:vibono/data/models/content.dart';
import 'package:vibono/data/models/energy.dart';
import 'package:vibono/data/models/profile.dart';
import 'package:vibono/domain/coaching_plan.dart';
import 'package:vibono/domain/coaching_progress.dart';
import 'package:vibono/domain/energy_density.dart';
import 'package:vibono/domain/goals.dart';
import 'package:vibono/domain/notification_planner.dart';
import 'package:vibono/domain/recipe_picker.dart';
import 'package:vibono/domain/shopping.dart';
import 'package:vibono/domain/week_plan.dart';
import 'package:vibono/ui/screens/recipe_detail_screen.dart' show stripIngredientSection;

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

  group('Remote-Config', () {
    test('ohne features sind alle Module aus', () {
      final c = RemoteConfig.fromJson({
        'shop_links': {'physical_products': true, 'points_redemption': true},
      });
      expect(c.featureReferral, isFalse);
      expect(c.featureShopPoints, isFalse);
      expect(c.linkPhysicalProducts, isTrue);
      // Ohne Shop-Punkte keine Einlösung, auch wenn der Link-Schalter an ist.
      expect(c.linkPointsRedemption, isFalse);
    });

    test('features werden gelesen', () {
      final c = RemoteConfig.fromJson({
        'features': {'referral': true, 'shop_points': true, 'web_reading': false},
        'shop_links': {'points_redemption': true},
      });
      expect(c.featureReferral, isTrue);
      expect(c.featureShopPoints, isTrue);
      expect(c.featureWebReading, isFalse);
      expect(c.linkPointsRedemption, isTrue);
    });

    test('sicherer Standard zeigt nichts', () {
      const c = RemoteConfig.safeDefault;
      expect(c.featureReferral || c.featureShopPoints || c.linkPointsRedemption || c.linkPhysicalProducts, isFalse);
    });
  });

  group('Wochenplan', () {
    final recipes = [
      recipe(1, ['fruehstueck']),
      recipe(2, ['mittag', 'abend']),
      recipe(3, ['mittag', 'abend']),
      recipe(4, ['mittag', 'abend']),
    ];
    final date = DateTime(2026, 11, 16);

    test('ohne Planung füllt die App alle drei Plätze mit Haushaltsportionen', () {
      final day = WeekPlan.day(
        date: date,
        recipes: recipes,
        profile: const Profile(householdSize: 3),
        phase: PhaseKey.phase3,
        stored: (_) => null,
      );
      expect(day.map((m) => m.slot), MealSlot.values);
      expect(day.every((m) => m.recipe != null && m.portions == 3 && !m.planned), isTrue);
    });

    test('gesperrte Rezepte (exklusiv gegen Punkte) werden nie automatisch vorgeschlagen', () {
      final locked = [
        for (final r in recipes)
          ContentItem(id: r.id + 100, type: ContentType.recipe, title: 'Exklusiv', tags: r.tags, locked: true, exclusive: true),
      ];
      final day = WeekPlan.day(
        date: date,
        recipes: [...locked, ...recipes],
        profile: const Profile(),
        phase: PhaseKey.phase3,
        stored: (_) => null,
      );
      expect(day.every((m) => m.recipe != null && !m.recipe!.locked), isTrue);
    });

    test('gespeicherte Planung gewinnt, ohne recipe_id bleibt der Platz frei', () {
      final day = WeekPlan.day(
        date: date,
        recipes: recipes,
        profile: const Profile(),
        phase: PhaseKey.phase3,
        stored: (k) => switch (k) {
          '2026-11-16:mittag' => {'recipe_id': 4, 'portions': 2},
          '2026-11-16:abend' => {'portions': 1},
          _ => null,
        },
      );
      expect(day[1].recipe?.id, 4);
      expect(day[1].portions, 2);
      expect(day[2].isEmpty, isTrue);
      expect(day[2].suggestion, isNotNull);
    });

    test('Schlüssel hin und zurück', () {
      final k = WeekPlan.key(date, MealSlot.abend);
      expect(k, '2026-11-16:abend');
      expect(WeekPlan.parseKey(k), (date, MealSlot.abend));
      expect(WeekPlan.parseKey('kaputt'), isNull);
    });

    test('Tages-ED aus Zutaten, gewichtet nach Tellergröße', () {
      const light = ContentItem(id: 1, type: ContentType.recipe, title: 'Suppe', servings: 1, ingredients: [
        RecipeIngredient(name: 'Brühe', amount: 500, kcalPer100g: 10),
      ]);
      const heavy = ContentItem(id: 2, type: ContentType.recipe, title: 'Nudeln', servings: 1, ingredients: [
        RecipeIngredient(name: 'Nudeln', amount: 100, kcalPer100g: 150),
      ]);
      final meals = [
        PlannedMeal(date: date, slot: MealSlot.mittag, recipe: light, portions: 1),
        PlannedMeal(date: date, slot: MealSlot.abend, recipe: heavy, portions: 1),
      ];
      // (50 + 150) kcal / 600 g
      expect(WeekPlan.dayDensity(meals), closeTo(0.333, 0.001));
    });
  });

  group('Einkaufsliste', () {
    const quark = ContentItem(id: 1, type: ContentType.recipe, title: 'Quark', servings: 2, ingredients: [
      RecipeIngredient(name: 'Magerquark', amount: 200),
      RecipeIngredient(name: 'Heidelbeeren', amount: 80),
    ]);
    const gulasch = ContentItem(id: 2, type: ContentType.recipe, title: 'Gulasch', servings: 2, ingredients: [
      RecipeIngredient(name: 'magerquark', amount: 0.1, unit: 'kg'),
      RecipeIngredient(name: 'Tomaten aus der Dose', amount: 400),
    ]);
    const ohne = ContentItem(id: 3, type: ContentType.recipe, title: 'Salat');
    final d = DateTime(2026, 11, 16);

    test('fasst gleiche Zutaten zusammen und rechnet auf Portionen um', () {
      final list = Shopping.aggregate([
        PlannedMeal(date: d, slot: MealSlot.fruehstueck, recipe: quark, portions: 1),
        PlannedMeal(date: d, slot: MealSlot.mittag, recipe: gulasch, portions: 4),
        PlannedMeal(date: d, slot: MealSlot.abend, portions: 2),
      ]);
      final q = list.firstWhere((e) => e.name == 'Magerquark');
      expect(q.amount, 100 + 200); // 200 g für 2 → 1 Portion, 100 g für 2 → 4 Portionen
      expect(q.group, Shopping.kuehlregal);
      expect(q.recipes, ['Quark', 'Gulasch']);
      expect(list.firstWhere((e) => e.name.startsWith('Tomaten')).group, Shopping.vorrat);
      expect(list.firstWhere((e) => e.name == 'Heidelbeeren').group, Shopping.obstGemuese);
    });

    test('Rezepte ohne Zutatenliste erscheinen als eigener Eintrag', () {
      final list = Shopping.aggregate([PlannedMeal(date: d, slot: MealSlot.mittag, recipe: ohne, portions: 2)]);
      expect(list.single.recipeId, 3);
      expect(list.single.group, Shopping.ohneListe);
    });

    test('Mengen lesbar gerundet', () {
      expect(Shopping.formatAmount(1234, 'g'), '1,2 kg');
      expect(Shopping.formatAmount(347, 'g'), '350 g');
      expect(Shopping.formatAmount(42, 'g'), '40 g');
      expect(Shopping.formatAmount(1.3, 'el'), '1,5 EL');
      expect(Shopping.formatAmount(2, 'stück'), '2');
    });

    test('Zutaten aus der Schnittstelle und aus Beispieldaten', () {
      final r = ContentItem.fromJson({
        'id': 5,
        'type': 'recipe',
        'title': 'Test',
        'servings': 2,
        'ingredients': [
          ['Paprika', 300, 31],
          {'name': 'Olivenöl', 'amount': 1, 'unit': 'EL', 'group': 'Für die Soße'},
          {'name': 'Zwiebeln', 'amount': 2, 'unit': null, 'group': null},
          {'name': ''},
        ],
      });
      expect(r.servings, 2);
      expect(r.ingredients.length, 3);
      expect(r.ingredients.first.grams, 300);
      expect(r.ingredients[1].unit, 'el');
      expect(r.ingredients[1].grams, isNull);
      expect(r.ingredients[2].unit, '');
      expect(ContentItem.fromJson(r.toJson()).ingredients.length, 3);
      // Die Zwischenüberschrift im Rezept ist kein Regal.
      final list = Shopping.aggregate([PlannedMeal(date: d, slot: MealSlot.abend, recipe: r, portions: 2)]);
      expect(list.firstWhere((e) => e.name == 'Olivenöl').group, Shopping.vorrat);
      expect(list.firstWhere((e) => e.name == 'Zwiebeln').amountLabel, '2');
    });
  });

  group('Coaching-Fortschritt', () {
    ContentItem lesson(int id, [String kind = 'lesen']) =>
        ContentItem(id: id, type: ContentType.lesson, title: 'L$id', lessonKind: kind);
    final courses = [
      Course(id: 1, title: 'A', lessons: [lesson(1, 'wichtig'), lesson(2), lesson(3)]),
      Course(id: 2, title: 'B', lessons: [for (var i = 10; i < 20; i++) lesson(i)]),
    ];
    final today = DateTime(2026, 11, 14, 18);

    test('Level, Serie und Abzeichen', () {
      final p = CoachingProgress.compute(
        courses: courses,
        doneAt: {
          1: DateTime(2026, 11, 12, 9),
          2: DateTime(2026, 11, 13, 9),
          3: DateTime(2026, 11, 14, 9),
          10: DateTime(2026, 11, 14, 10),
          11: DateTime(2026, 11, 1),
        },
        today: today,
        phase: PhaseKey.phase2,
        phaseCourseIds: const [1],
      );
      expect(p.lessonsDone, 5);
      expect(p.level.name, 'Entdecker');
      expect(p.toNext, 10);
      expect(p.streak, 3);
      expect(p.bestStreak, 3);
      expect(p.coursesDone, 1);
      final earned = {for (final b in p.badges) if (b.earned) b.id};
      expect(earned, containsAll(['erste', 'serie3', 'kurs', 'wichtig', 'ut']));
      expect(earned.contains('serie7'), isFalse);
    });

    test('Serie läuft bis Ende des Tages weiter, danach von vorn', () {
      final yesterdayOnly = CoachingProgress.compute(
        courses: courses,
        doneAt: {1: DateTime(2026, 11, 13, 20), 2: DateTime(2026, 11, 12, 20)},
        today: today,
        phase: PhaseKey.phase1,
      );
      expect(yesterdayOnly.streak, 2);
      final gap = CoachingProgress.compute(
        courses: courses,
        doneAt: {1: DateTime(2026, 11, 11)},
        today: today,
        phase: PhaseKey.phase1,
      );
      expect(gap.streak, 0);
      expect(gap.bestStreak, 1);
    });

    test('neue Abzeichen und nächste Lektion', () {
      final before = CoachingProgress.compute(courses: courses, doneAt: const {}, today: today, phase: PhaseKey.phase2);
      final after =
          CoachingProgress.compute(courses: courses, doneAt: {2: today}, today: today, phase: PhaseKey.phase2);
      expect(after.newBadgesSince(before).map((b) => b.id), ['erste']);
      final next = CoachingProgress.nextLesson(courses, (l) => l.id <= 3, const [2]);
      expect(next?.lesson.id, 10);
    });
  });

  test('Rezepttext ohne doppelten Zutaten-Abschnitt', () {
    const html = '<h3>Zutaten (2 Portionen)</h3>\n<ul><li>200 g Quark</li></ul><h3>Zubereitung</h3><p>Rühren.</p>';
    expect(stripIngredientSection(html), '<h3>Zubereitung</h3><p>Rühren.</p>');
    expect(stripIngredientSection('<p>Nur Text</p>'), '<p>Nur Text</p>');
  });
}
