import 'dart:math';

import '../data/models/coaching_day.dart';
import '../data/models/content.dart';
import '../data/models/home_feed.dart';
import '../data/models/profile.dart';
import 'recipe_picker.dart';
import 'season.dart';

/// Wetter vor Ort, vereinfacht auf das, was für Rezeptvorschläge zählt.
enum WeatherKind { sonnig, bewoelkt, nebel, regen, schnee, gewitter }

class WeatherInfo {
  const WeatherInfo({required this.tempC, required this.kind, this.place});
  final double tempC;
  final WeatherKind kind;
  final String? place;

  bool get cold => tempC <= 8 || kind == WeatherKind.schnee;
  bool get wet => kind == WeatherKind.regen || kind == WeatherKind.gewitter || kind == WeatherKind.schnee;
  bool get hot => tempC >= 24;

  String get kindLabel => switch (kind) {
        WeatherKind.sonnig => 'sonnig',
        WeatherKind.bewoelkt => 'bewölkt',
        WeatherKind.nebel => 'neblig',
        WeatherKind.regen => 'Regen',
        WeatherKind.schnee => 'Schnee',
        WeatherKind.gewitter => 'Gewitter',
      };

  String get label => '${tempC.round()} °C, $kindLabel';

  /// WMO-Wettercode (Open-Meteo) zu [WeatherKind].
  static WeatherKind kindFromWmo(int code) => switch (code) {
        0 || 1 => WeatherKind.sonnig,
        2 || 3 => WeatherKind.bewoelkt,
        45 || 48 => WeatherKind.nebel,
        >= 71 && <= 77 || 85 || 86 => WeatherKind.schnee,
        >= 95 => WeatherKind.gewitter,
        >= 51 && <= 67 || >= 80 && <= 82 => WeatherKind.regen,
        _ => WeatherKind.bewoelkt,
      };
}

/// Warum ein Rezept vorgeschlagen wird. Die App zeigt höchstens zwei Gründe.
enum ReasonKind { stichwort, challenge, wetter, saison, phase, vorlieben }

class SuggestionReason {
  const SuggestionReason(this.kind, this.label);
  final ReasonKind kind;
  final String label;
}

class FoodSuggestion {
  const FoodSuggestion(this.recipe, this.reasons, this.score);
  final ContentItem recipe;
  final List<SuggestionReason> reasons;
  final double score;
}

/// Alles, wovon die Vorschläge für „Was heute essen?“ abhängen.
class FoodContext {
  const FoodContext({
    required this.date,
    required this.profile,
    required this.phase,
    this.challenges = const [],
    this.weather,
    this.keywords = const [],
  });

  final DateTime date;
  final Profile profile;
  final PhaseKey phase;

  /// Nur Challenges, bei denen die Person mitmacht.
  final List<Challenge> challenges;
  final WeatherInfo? weather;

  /// Stichwörter vom Vibono-Team und eigene („Worauf hast du Lust?“).
  final List<String> keywords;

  Season get season => SeasonCalendar.seasonOf(date);
}

abstract final class FoodSuggester {
  static const _warmWords = ['suppe', 'eintopf', 'gulasch', 'auflauf', 'ofen', 'curry', 'brühe', 'warm'];
  static const _freshWords = ['salat', 'bowl', 'kalt', 'gazpacho', 'quark', 'smoothie', 'frisch'];

  static bool _has(ContentItem r, List<String> words) {
    final hay = '${r.title} ${r.tags.join(' ')}'.toLowerCase();
    return words.any(hay.contains);
  }

  /// Trifft ein Stichwort Titel, Schlagwörter oder Zutaten?
  static bool matchesKeyword(ContentItem r, String keyword) {
    final k = keyword.trim();
    if (k.isEmpty) return false;
    if (SeasonCalendar.matches(r.title, k)) return true;
    if (r.tags.any((t) => SeasonCalendar.matches(t, k))) return true;
    return r.ingredients.any((i) => SeasonCalendar.matches(i.name, k));
  }

  /// Saisonware im Rezept (Titel oder Zutaten), z. B. „Kürbis“.
  static String? seasonalProduce(ContentItem r, DateTime date) {
    for (final p in SeasonCalendar.produce(date)) {
      if (SeasonCalendar.matches(r.title, p) || r.ingredients.any((i) => SeasonCalendar.matches(i.name, p))) return p;
    }
    return null;
  }

  static bool _fitsChallenge(ContentItem r, Challenge c) {
    final tagHit = c.recipeTags.isNotEmpty && r.tags.any(c.recipeTags.contains);
    final edOk = c.recipeMaxEd != null && r.energyDensity != null && r.energyDensity! <= c.recipeMaxEd!;
    return tagHit || edOk;
  }

  static bool _hasPreferences(Profile p) =>
      p.diet != null || p.intolerances.isNotEmpty || p.dislikes.isNotEmpty || p.meatAmount == 'keins';

  static String _preferenceLabel(Profile p) {
    if (p.diet == Diet.vegan) return 'Vegan, wie du magst';
    if (p.diet == Diet.vegetarisch) return 'Vegetarisch, wie du magst';
    if (p.intolerances.isNotEmpty) return 'Ohne ${intoleranceOptions[p.intolerances.first] ?? p.intolerances.first}';
    return 'Passt zu deinen Vorlieben';
  }

  /// Bewertet ein Rezept. `null` = passt nicht zu Vorlieben oder Phase.
  static FoodSuggestion? rate(ContentItem r, FoodContext c, {bool strict = true}) {
    if (strict && !RecipePicker.fits(r, c.profile, c.phase)) return null;
    final reasons = <SuggestionReason>[];
    var score = 0.0;

    for (final k in c.keywords) {
      if (matchesKeyword(r, k)) {
        score += 3;
        reasons.add(SuggestionReason(ReasonKind.stichwort, 'Mit ${k.trim()}'));
        break;
      }
    }
    for (final ch in c.challenges) {
      if (_fitsChallenge(r, ch)) {
        score += 2;
        reasons.add(SuggestionReason(ReasonKind.challenge, 'Passt zu „${ch.title}“'));
        break;
      }
    }
    final w = c.weather;
    if (w != null) {
      if ((w.cold || w.wet) && _has(r, _warmWords)) {
        score += 1.2;
        reasons.add(SuggestionReason(ReasonKind.wetter, w.cold ? 'Wärmt bei ${w.tempC.round()} °C' : 'Warm bei Regenwetter'));
      } else if (w.hot && _has(r, _freshWords)) {
        score += 1.2;
        reasons.add(SuggestionReason(ReasonKind.wetter, 'Leicht bei ${w.tempC.round()} °C'));
      }
    }
    final produce = seasonalProduce(r, c.date);
    if (produce != null) {
      score += 1.5;
      reasons.add(SuggestionReason(ReasonKind.saison, '$produce hat Saison'));
    }
    final ed = r.energyDensity;
    switch (c.phase) {
      case PhaseKey.phase1:
        score += 1;
        reasons.add(const SuggestionReason(ReasonKind.phase, 'Für die Umstellungstage'));
      case PhaseKey.phase2 when ed != null && ed <= 1.0:
        score += 1;
        reasons.add(const SuggestionReason(ReasonKind.phase, 'Grün für Phase 2'));
      case PhaseKey.phase3 when ed != null && ed <= 1.5:
        score += 0.5;
        reasons.add(const SuggestionReason(ReasonKind.phase, 'Grüne Energiedichte'));
      default:
        break;
    }
    if (_hasPreferences(c.profile)) {
      reasons.add(SuggestionReason(ReasonKind.vorlieben, _preferenceLabel(c.profile)));
    }
    return FoodSuggestion(r, reasons, score);
  }

  /// Die besten Vorschläge für den Tag, jeden Tag etwas anders gemischt.
  static List<FoodSuggestion> suggest(List<ContentItem> recipes, FoodContext c, {int count = 4}) {
    // Nur Passendes: in den Umstellungstagen also nur UT-geeignete Rezepte,
    // lieber wenige Vorschläge als unpassende.
    final rated = [for (final r in recipes) ?rate(r, c)];
    final seed = c.date.year * 400 + c.date.month * 31 + c.date.day;
    final rnd = Random(seed);
    final jitter = {for (final s in rated) s.recipe.id: rnd.nextDouble() * 0.9};
    rated.sort((a, b) => (b.score + jitter[b.recipe.id]!).compareTo(a.score + jitter[a.recipe.id]!));
    return rated.take(count).toList();
  }

  /// Rezepte mit einem bestimmten Lebensmittel („Probier mal was aus mit …“).
  static List<ContentItem> withIngredient(List<ContentItem> recipes, String name, FoodContext c) => [
        for (final r in recipes)
          if (matchesKeyword(r, name) && RecipePicker.fits(r, c.profile, PhaseKey.phase3)) r,
      ];
}

/// Mahlzeit, für die ein Vorschlag gerade am meisten nützt.
MealSlot nextMealSlot(DateTime now) => now.hour < 10
    ? MealSlot.fruehstueck
    : now.hour < 14
        ? MealSlot.mittag
        : MealSlot.abend;
