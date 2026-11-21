import 'package:flutter_test/flutter_test.dart';
import 'package:vibono/data/api/mock_data.dart';
import 'package:vibono/data/models/app_config.dart';
import 'package:vibono/data/models/coaching_day.dart';
import 'package:vibono/data/models/content.dart';
import 'package:vibono/data/models/home_feed.dart';
import 'package:vibono/data/models/profile.dart';
import 'package:vibono/domain/food_suggestions.dart';
import 'package:vibono/domain/home_progress.dart';
import 'package:vibono/domain/season.dart';
import 'package:vibono/ui/screens/today/news_section.dart';

List<ContentItem> get recipes => [for (final r in mockRecipes) ContentItem.fromJson({...r, 'type': 'recipe'})];

ContentItem byId(int id) => recipes.firstWhere((r) => r.id == id);

void main() {
  final nov = DateTime(2026, 11, 21);

  group('Saisonkalender', () {
    test('Jahreszeit und Saisonware', () {
      expect(SeasonCalendar.seasonOf(nov), Season.herbst);
      expect(SeasonCalendar.seasonOf(DateTime(2026, 1, 3)), Season.winter);
      expect(SeasonCalendar.produce(nov), contains('Kürbis'));
      expect(SeasonCalendar.produce(DateTime(2026, 5, 1)), contains('Spargel'));
    });

    test('Zutaten erkennen, auch mit Zusatz und Plural', () {
      expect(SeasonCalendar.matches('Hokkaido-Kürbis', 'Kürbis'), isTrue);
      expect(SeasonCalendar.matches('Rote Bete, gekocht', 'Rote Bete'), isTrue);
      expect(SeasonCalendar.matches('Karotten', 'Karotte'), isTrue);
      expect(SeasonCalendar.matches('Tomaten aus der Dose', 'Tomate'), isTrue);
      expect(SeasonCalendar.matches('Magerquark', 'Apfel'), isFalse);
    });

    test('Saison-Idee wechselt wöchentlich, nicht täglich', () {
      final mon = DateTime(2026, 11, 16), sun = DateTime(2026, 11, 22), next = DateTime(2026, 11, 23);
      expect(SeasonCalendar.isoWeek(mon), 47);
      expect(SeasonCalendar.isoWeek(DateTime(2027, 1, 1)), 53);
      expect(SeasonCalendar.spotlightOf(mon), SeasonCalendar.spotlightOf(sun));
      expect(SeasonCalendar.spotlightOf(next), isNot(SeasonCalendar.spotlightOf(sun)));
      expect(SeasonCalendar.produce(nov), contains(SeasonCalendar.spotlightOf(nov)));
    });
  });

  group('Rezeptvorschläge', () {
    FoodContext ctx({
      Profile profile = const Profile(),
      PhaseKey phase = PhaseKey.phase3,
      WeatherInfo? weather,
      List<String> keywords = const [],
      List<Challenge> challenges = const [],
    }) =>
        FoodContext(
          date: nov,
          profile: profile,
          phase: phase,
          weather: weather,
          keywords: keywords,
          challenges: challenges,
        );

    test('Vorlieben filtern hart: vegan bekommt nur Veganes', () {
      final s = FoodSuggester.suggest(recipes, ctx(profile: const Profile(diet: Diet.vegan)), count: 10);
      expect(s, isNotEmpty);
      expect(s.every((x) => x.recipe.tags.contains('vegan')), isTrue);
      expect(s.first.reasons.map((r) => r.label), contains('Vegan, wie du magst'));
    });

    test('Umstellungstage: nur geeignete Rezepte', () {
      final s = FoodSuggester.suggest(recipes, ctx(phase: PhaseKey.phase1), count: 10);
      expect(s.map((x) => x.recipe.id).toSet(), {9005, 9012});
      expect(s.first.reasons.map((r) => r.label), contains('Für die Umstellungstage'));
    });

    test('Stichwort hebt passende Rezepte nach vorn', () {
      final s = FoodSuggester.suggest(recipes, ctx(keywords: ['Kürbis']));
      expect(s.first.recipe.id, 9007);
      expect(s.first.reasons.first.label, 'Mit Kürbis');
    });

    test('Kaltes Wetter: Warmes; Hitze: Leichtes', () {
      const cold = WeatherInfo(tempC: 3, kind: WeatherKind.regen);
      final warm = FoodSuggester.rate(byId(9008), ctx(weather: cold))!;
      expect(warm.reasons.map((r) => r.kind), contains(ReasonKind.wetter));
      expect(FoodSuggester.rate(byId(9010), ctx(weather: cold))!.reasons.map((r) => r.kind), isNot(contains(ReasonKind.wetter)));

      const hot = WeatherInfo(tempC: 29, kind: WeatherKind.sonnig);
      expect(FoodSuggester.rate(byId(9010), ctx(weather: hot))!.reasons.first.label, 'Leicht bei 29 °C');
    });

    test('Saison und Challenge zählen als Grund', () {
      final r = FoodSuggester.rate(byId(9009), ctx())!;
      expect(r.reasons.map((x) => x.label), contains('Rote Bete hat Saison'));

      final veg = Challenge.tryParse(mockChallenges(nov)[1])!;
      final c = FoodSuggester.rate(byId(9010), ctx(challenges: [veg]))!;
      expect(c.reasons.first.label, 'Passt zu „Obst-/Gemüse-Challenge“');

      final weight = Challenge.tryParse(mockChallenges(nov)[0])!;
      expect(FoodSuggester.rate(byId(9007), ctx(challenges: [weight]))!.reasons.map((x) => x.kind), contains(ReasonKind.challenge));
      expect(FoodSuggester.rate(byId(9006), ctx(challenges: [weight]))!.reasons.map((x) => x.kind), isNot(contains(ReasonKind.challenge)));
    });

    test('Gleiches Datum, gleiche Vorschläge', () {
      final a = FoodSuggester.suggest(recipes, ctx()).map((s) => s.recipe.id).toList();
      final b = FoodSuggester.suggest(recipes, ctx()).map((s) => s.recipe.id).toList();
      expect(a, b);
      expect(a.length, 4);
    });

    test('Probier mal was aus mit …', () {
      expect(FoodSuggester.withIngredient(recipes, 'Pastinake', ctx()).map((r) => r.id), [9009]);
      expect(FoodSuggester.withIngredient(recipes, 'Topinambur', ctx()), isEmpty);
    });

    test('Wettercodes', () {
      expect(WeatherInfo.kindFromWmo(0), WeatherKind.sonnig);
      expect(WeatherInfo.kindFromWmo(61), WeatherKind.regen);
      expect(WeatherInfo.kindFromWmo(81), WeatherKind.regen);
      expect(WeatherInfo.kindFromWmo(73), WeatherKind.schnee);
      expect(WeatherInfo.kindFromWmo(95), WeatherKind.gewitter);
    });
  });

  group('Challenges', () {
    final cs = [for (final c in mockChallenges(nov)) Challenge.tryParse(c)!];

    test('Abnehmziel: Startgewicht beim Mitmachen, Fortschritt in kg', () {
      final e = ChallengeEntry(joinedOn: DateTime(2026, 11, 10), startKg: 84);
      final st = ChallengeProgress.status(cs[0], e, nov, weights: [(DateTime(2026, 11, 20), 81.9)]);
      expect(st.label, '2,1 von 7 kg');
      expect(st.progress, closeTo(0.3, 0.001));
      expect(st.done, isFalse);

      // Ohne gemerktes Startgewicht: letzter Wert vor dem Mitmachen.
      final e2 = ChallengeEntry(joinedOn: DateTime(2026, 11, 10));
      final st2 = ChallengeProgress.status(cs[0], e2, nov,
          weights: [(DateTime(2026, 11, 1), 85), (DateTime(2026, 11, 9), 84.5), (DateTime(2026, 11, 20), 83.5)]);
      expect(st2.label, '1 von 7 kg');
      expect(ChallengeProgress.status(cs[0], e2, nov).hint, isNotNull);
    });

    test('Tagesziel: Tage mit erreichtem Ziel zählen', () {
      var e = ChallengeEntry(joinedOn: DateTime(2026, 11, 15));
      e = e.withCount(DateTime(2026, 11, 19), 5).withCount(DateTime(2026, 11, 20), 3).withCount(nov, 6);
      final st = ChallengeProgress.status(cs[1], e, nov);
      expect(st.label, '2 von 14 Tagen');
      expect(st.todayCount, 6);
      expect(e.withCount(nov, 0).days.containsKey('2026-11-21'), isFalse);
      // Rundweg über JSON (Sync).
      expect(ChallengeEntry.fromJson(e.toJson())!.days, e.days);
    });

    test('Sammeln', () {
      final e = ChallengeEntry(joinedOn: nov, items: const ['Pastinake', 'Topinambur']);
      final st = ChallengeProgress.status(cs[2], e, nov);
      expect(st.label, '2 von 5 Lebensmittel');
      expect(ChallengeProgress.status(cs[2], e, DateTime(2027, 1, 1)).ended, isTrue);
    });

    test('Unbekannte Art wird ignoriert', () {
      expect(Challenge.tryParse({'kind': 'bingo', 'title': 'X', 'target': 3}), isNull);
      expect(HomeFeed.fromJson({
        'challenges': [
          {'kind': 'bingo', 'title': 'X', 'target': 3},
          mockChallenges(nov).first,
        ],
      }).challenges.length, 1);
    });
  });

  group('Motivationsschub', () {
    test('ab zwei Tagen ohne Lektion, Ton passt zur Pause', () {
      expect(InactivityNudge.forDays(DateTime(2026, 11, 20, 22), nov), isNull);
      expect(InactivityNudge.forDays(null, nov), isNull);
      expect(InactivityNudge.forDays(DateTime(2026, 11, 19), nov)!.title, 'Kleiner Schubs');
      expect(InactivityNudge.forDays(DateTime(2026, 11, 15), nov)!.days, 6);
      expect(InactivityNudge.forDays(DateTime(2026, 11, 1), nov)!.title, 'Zeit für einen Neustart');
    });
  });

  group('Startseite vom Server', () {
    test('Feed lesen', () {
      final f = HomeFeed.fromJson({
        'food': {
          'keywords': ['Kürbis'],
          'spotlight': {'name': ' Rote Bete '},
        },
        'plan': {'quiz': mockQuiz.first},
        'challenges': mockChallenges(nov),
        'news': [
          ...mockNews(nov),
          {'kind': 'unbekannt', 'title': 'X'},
        ],
      });
      expect(f.keywords, ['Kürbis']);
      expect(f.spotlight, 'Rote Bete');
      expect(f.quiz!.answers.length, 3);
      expect(f.challenges.length, 3);
      expect(f.news.length, 5);
      expect(f.news.first.contentId, 9102);
      expect(HomeFeed.fromJson(const {}).quiz, isNull);
    });

    test('Quizfragen aus dem Beispielpool sind gültig', () {
      for (final q in mockQuiz) {
        expect(QuizQuestion.tryParse(q), isNotNull, reason: '${q['id']}');
      }
      expect(QuizQuestion.tryParse({'question': 'X', 'answers': ['A', 'B'], 'correct': 2}), isNull);
    });

    test('Shop-Meldungen nur, wo Links erlaubt sind', () {
      final news = [for (final n in mockNews(nov)) NewsItem.tryParse(n)!];
      const ios = RemoteConfig(linkPhysicalProducts: true);
      const android = RemoteConfig(linkPhysicalProducts: true, linkDigitalProducts: true);
      expect(visibleNews(news, ios).map((n) => n.kind), isNot(contains(NewsKind.ebook)));
      expect(visibleNews(news, ios).map((n) => n.kind), contains(NewsKind.offer));
      expect(visibleNews(news, android).length, 5);
      expect(visibleNews(news, RemoteConfig.safeDefault).map((n) => n.kind), isNot(contains(NewsKind.offer)));
    });
  });

  test('Zahlen deutsch formatiert', () {
    expect(formatNumber(2.1), '2,1');
    expect(formatNumber(7), '7');
    expect(formatNumber(0.0), '0');
  });
}
