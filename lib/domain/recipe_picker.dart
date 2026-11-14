import '../data/models/coaching_day.dart';
import '../data/models/content.dart';
import '../data/models/profile.dart';

enum MealSlot { fruehstueck, mittag, abend }

extension MealSlotX on MealSlot {
  String get label => switch (this) {
        MealSlot.fruehstueck => 'Frühstück',
        MealSlot.mittag => 'Mittag',
        MealSlot.abend => 'Abend',
      };

  /// Schlüsselteil im Wochenplan (`YYYY-MM-DD:<slot>`).
  String get wire => name;
}

/// Die App nimmt Entscheidungen ab: Für jeden Tag wählt sie drei Rezepte
/// passend zu Phase, Ernährungsform und Unverträglichkeiten.
abstract final class RecipePicker {
  static bool fits(ContentItem r, Profile p, PhaseKey phase) {
    final t = r.tags.toSet();
    if (p.diet == Diet.vegan && !t.contains('vegan')) return false;
    if (p.diet == Diet.vegetarisch && !(t.contains('vegetarisch') || t.contains('vegan'))) return false;
    if (p.meatAmount == 'keins' && t.contains('fleisch')) return false;
    for (final i in p.intolerances) {
      if (t.contains('enthaelt-$i')) return false;
    }
    for (final d in p.dislikes) {
      if (r.title.toLowerCase().contains(d.toLowerCase())) return false;
    }
    if (phase == PhaseKey.phase1 && !t.contains('ut-geeignet')) return false;
    return true;
  }

  static bool _slotOk(ContentItem r, MealSlot s) {
    final t = r.tags;
    return switch (s) {
      MealSlot.fruehstueck => t.contains('fruehstueck'),
      MealSlot.mittag => t.contains('mittag') || !t.contains('fruehstueck'),
      MealSlot.abend => t.contains('abend') || !t.contains('fruehstueck'),
    };
  }

  static Map<MealSlot, ContentItem> forDate(
    DateTime date,
    List<ContentItem> recipes,
    Profile profile,
    PhaseKey phase,
  ) {
    var pool = recipes.where((r) => fits(r, profile, phase)).toList();
    // In den Umstellungstagen gibt es nur wenige passende Rezepte: dann
    // dürfen sich Rezepte wiederholen, aber nie unpassende auftauchen.
    if (pool.isEmpty) pool = recipes.where((r) => fits(r, profile, PhaseKey.phase3)).toList();
    if (pool.isEmpty) pool = recipes;
    if (pool.isEmpty) return const {};
    final seed = date.year * 400 + date.month * 31 + date.day;
    final result = <MealSlot, ContentItem>{};
    final used = <int>{};
    for (final s in MealSlot.values) {
      var candidates = pool.where((r) => _slotOk(r, s) && !used.contains(r.id)).toList();
      if (candidates.isEmpty) candidates = pool.where((r) => _slotOk(r, s)).toList();
      if (candidates.isEmpty) candidates = pool;
      final pick = candidates[(seed + s.index * 7) % candidates.length];
      used.add(pick.id);
      result[s] = pick;
    }
    return result;
  }

  /// Ein anderes passendes Rezept für denselben Platz („Tauschen“).
  static ContentItem? alternative(
    ContentItem current,
    MealSlot slot,
    List<ContentItem> recipes,
    Profile profile,
    PhaseKey phase,
  ) {
    final c = recipes.where((r) => r.id != current.id && fits(r, profile, phase) && _slotOk(r, slot)).toList();
    if (c.isEmpty) return null;
    return c[DateTime.now().millisecond % c.length];
  }
}
