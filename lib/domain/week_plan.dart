import '../data/models/coaching_day.dart';
import '../data/models/content.dart';
import '../data/models/json.dart';
import '../data/models/profile.dart';
import 'recipe_picker.dart';

/// Eine Mahlzeit im Wochenplan.
class PlannedMeal {
  const PlannedMeal({
    required this.date,
    required this.slot,
    required this.portions,
    this.recipe,
    this.suggestion,
    this.planned = false,
  });

  final DateTime date;
  final MealSlot slot;

  /// `null`: Platz bewusst frei, z. B. weil auswärts gegessen wird.
  final ContentItem? recipe;

  /// Vorschlag der App für einen freien Platz.
  final ContentItem? suggestion;
  final int portions;

  /// Vom Nutzer festgelegt (sonst von der App gewählt).
  final bool planned;

  bool get isEmpty => recipe == null;
  String get key => WeekPlan.key(date, slot);
}

/// Wochenplan: gespeicherte Planung (Sync mit „Mein Wochenplan“ auf
/// MyVibono) hat Vorrang, alle übrigen Plätze füllt die App selbst.
///
/// Gespeichert wird je Platz `{date, slot, recipe_id?, portions?}`. Ein
/// Eintrag ohne `recipe_id` heißt: Platz bleibt frei.
abstract final class WeekPlan {
  static const maxPortions = 12;

  /// Übliche Tellerportion, wenn ein Rezept keine Zutatenliste hat.
  static const defaultPortionGrams = 400.0;

  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String key(DateTime d, MealSlot s) => '${dateKey(d)}:${s.wire}';

  static DateTime mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  /// `YYYY-MM-DD:<slot>` → Datum und Platz.
  static (DateTime, MealSlot)? parseKey(String key) {
    final i = key.indexOf(':');
    if (i < 0) return null;
    final date = DateTime.tryParse(key.substring(0, i));
    final slot = MealSlot.values.where((s) => s.wire == key.substring(i + 1)).firstOrNull;
    if (date == null || slot == null) return null;
    return (DateTime(date.year, date.month, date.day), slot);
  }

  static List<PlannedMeal> day({
    required DateTime date,
    required List<ContentItem> recipes,
    required Profile profile,
    required PhaseKey phase,
    required Json? Function(String key) stored,
  }) {
    // Gesperrte Rezepte (Mitgliedschaft, exklusiv gegen Punkte) nicht automatisch vorschlagen.
    final auto = RecipePicker.forDate(date, recipes.where((r) => !r.locked).toList(), profile, phase);
    final fallbackPortions = profile.householdSize.clamp(1, maxPortions);
    return [
      for (final s in MealSlot.values)
        _resolve(date, s, stored(key(date, s)), auto[s], recipes, fallbackPortions),
    ];
  }

  static PlannedMeal _resolve(
    DateTime date,
    MealSlot slot,
    Json? data,
    ContentItem? auto,
    List<ContentItem> recipes,
    int fallbackPortions,
  ) {
    if (data == null) return PlannedMeal(date: date, slot: slot, recipe: auto, portions: fallbackPortions);
    final portions = (asInt(data['portions']) ?? fallbackPortions).clamp(1, maxPortions);
    final id = asInt(data['recipe_id']);
    if (id == null) {
      return PlannedMeal(date: date, slot: slot, suggestion: auto, portions: portions, planned: true);
    }
    final recipe = recipes.where((r) => r.id == id).firstOrNull ?? auto;
    return PlannedMeal(date: date, slot: slot, recipe: recipe, portions: portions, planned: true);
  }

  /// Gramm und kcal einer Portion. Ohne Zutatenliste gilt eine übliche
  /// Portion von 400 g mit der Energiedichte des Rezepts.
  static ({double grams, double kcal})? perPortion(ContentItem r) {
    final servings = (r.servings ?? 1).clamp(1, 100);
    var g = 0.0;
    var k = 0.0;
    var complete = r.ingredients.isNotEmpty;
    for (final i in r.ingredients) {
      final grams = i.grams;
      if (grams == null || i.kcalPer100g == null) {
        complete = false;
        break;
      }
      g += grams;
      k += grams * i.kcalPer100g! / 100;
    }
    if (complete && g > 0) {
      final grams = g / servings;
      // Die Energiedichte aus WordPress ist maßgeblich, falls vorhanden.
      final kcal = r.energyDensity != null ? grams * r.energyDensity! : k / servings;
      return (grams: grams, kcal: kcal);
    }
    if (r.energyDensity == null) return null;
    return (grams: defaultPortionGrams, kcal: defaultPortionGrams * r.energyDensity!);
  }

  /// Energiedichte des ganzen Tages (kcal ÷ g über alle geplanten Teller).
  static double? dayDensity(Iterable<PlannedMeal> meals) {
    var g = 0.0;
    var k = 0.0;
    for (final m in meals) {
      final p = m.recipe == null ? null : perPortion(m.recipe!);
      if (p == null) continue;
      g += p.grams;
      k += p.kcal;
    }
    return g > 0 ? k / g : null;
  }
}
