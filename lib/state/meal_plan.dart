import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/content.dart';
import '../data/models/json.dart';
import '../data/models/profile.dart';
import '../data/models/sync_item.dart';
import '../data/sync/sync_repository.dart';
import '../domain/coaching_plan.dart';
import '../domain/recipe_picker.dart';
import '../domain/shopping.dart';
import '../domain/week_plan.dart';
import 'providers.dart';

/// Löst Tage des Wochenplans auf (gespeicherte Planung vor App-Auswahl).
class PlanResolver {
  PlanResolver(this.recipes, this.profile, this._sync);

  final List<ContentItem> recipes;
  final Profile profile;
  final SyncRepository _sync;
  final Map<DateTime, List<PlannedMeal>> _cache = {};

  DateTime get _start => profile.coachingStartDate ?? CoachingPlan.dateOnly(DateTime.now());

  List<PlannedMeal> day(DateTime date) {
    final d = CoachingPlan.dateOnly(date);
    return _cache.putIfAbsent(
      d,
      () => WeekPlan.day(
        date: d,
        recipes: recipes,
        profile: profile,
        phase: CoachingPlan.phaseFor(_start, d).key,
        stored: (k) => _sync.get(SyncCollection.weekplan, k),
      ),
    );
  }

  PlannedMeal meal(DateTime date, MealSlot slot) => day(date)[slot.index];

  /// Ein anderes passendes Rezept für denselben Platz.
  ContentItem? alternative(PlannedMeal m) {
    final current = m.recipe ?? m.suggestion;
    final phase = CoachingPlan.phaseFor(_start, m.date).key;
    if (current == null) return null;
    return RecipePicker.alternative(current, m.slot, recipes.where((r) => !r.locked).toList(), profile, phase);
  }

  /// Passende Rezepte für einen Platz, zum Selbst-Aussuchen.
  List<ContentItem> candidates(DateTime date, MealSlot slot) {
    final phase = CoachingPlan.phaseFor(_start, date).key;
    // Gesperrte Rezepte (Mitgliedschaft, exklusiv gegen Punkte) nie automatisch vorschlagen.
    final open = recipes.where((r) => !r.locked).toList();
    final fitting = open.where((r) => RecipePicker.fits(r, profile, phase)).toList();
    return fitting.isEmpty ? open : fitting;
  }
}

final planResolverProvider = Provider<PlanResolver?>((ref) {
  final recipes = ref.watch(recipesProvider).value;
  if (recipes == null) return null;
  final profile = ref.watch(sessionProvider.select((s) => s.profile));
  final sync = ref.watch(syncProvider);
  return PlanResolver(recipes, profile, sync);
});

/// Schreibt einen Platz des Wochenplans (wird mit MyVibono abgeglichen).
/// Ohne [recipeId] bleibt der Platz frei.
Future<void> savePlannedMeal(
  WidgetRef ref,
  DateTime date,
  MealSlot slot, {
  int? recipeId,
  required int portions,
}) async {
  final k = WeekPlan.dateKey(date);
  await ref.read(syncProvider).upsert(SyncCollection.weekplan, '$k:${slot.wire}', {
    'date': k,
    'slot': slot.wire,
    'recipe_id': ?recipeId,
    'portions': portions,
  });
  ref.invalidate(coachingDayProvider(CoachingPlan.dateOnly(date)));
}

// ---------------------------------------------------------------------------
// Einkaufsliste
// ---------------------------------------------------------------------------

class ShoppingListState {
  const ShoppingListState({
    this.meals = const {},
    this.extras = const [],
    this.checked = const {},
    this.basics = false,
  });

  /// Mahlzeiten (`YYYY-MM-DD:<slot>`), deren Zutaten auf der Liste stehen.
  /// Die Mengen werden immer aus dem aktuellen Plan berechnet, ein Tausch
  /// im Wochenplan ändert also auch die Liste.
  final Set<String> meals;
  final List<String> extras;
  final Set<String> checked;

  /// Grundausstattung für die Umstellungstage.
  final bool basics;

  bool get isEmpty => meals.isEmpty && extras.isEmpty && !basics;

  ShoppingListState copyWith({Set<String>? meals, List<String>? extras, Set<String>? checked, bool? basics}) =>
      ShoppingListState(
        meals: meals ?? this.meals,
        extras: extras ?? this.extras,
        checked: checked ?? this.checked,
        basics: basics ?? this.basics,
      );

  factory ShoppingListState.fromJson(Object? raw) {
    final j = raw is Map ? Json.from(raw) : const <String, dynamic>{};
    return ShoppingListState(
      meals: asStringList(j['meals']).toSet(),
      extras: asStringList(j['extras']),
      checked: asStringList(j['checked']).toSet(),
      basics: asBool(j['basics']),
    );
  }

  Json toJson() => {
        'meals': meals.toList()..sort(),
        'extras': extras,
        'checked': checked.toList(),
        'basics': basics,
      };
}

class ShoppingList extends Notifier<ShoppingListState> {
  static const _k = 'u.shopping';

  @override
  ShoppingListState build() {
    final s = ShoppingListState.fromJson(ref.watch(storeProvider).readJson(_k));
    // Vergangene Mahlzeiten fallen heraus, die sind gekauft und gegessen.
    final today = CoachingPlan.dateOnly(DateTime.now());
    final meals = s.meals.where((k) {
      final p = WeekPlan.parseKey(k);
      return p != null && !p.$1.isBefore(today);
    }).toSet();
    return meals.length == s.meals.length ? s : s.copyWith(meals: meals);
  }

  Future<void> _set(ShoppingListState s) async {
    state = s;
    await ref.read(storeProvider).writeJson(_k, s.toJson());
  }

  /// Fügt Mahlzeiten hinzu und gibt zurück, wie viele neu dazukamen.
  Future<int> addMeals(Iterable<String> keys) async {
    final next = {...state.meals, ...keys};
    final added = next.length - state.meals.length;
    if (added > 0) await _set(state.copyWith(meals: next));
    return added;
  }

  Future<void> removeMeal(String key) => _set(state.copyWith(meals: {...state.meals}..remove(key)));

  Future<void> toggle(String id) {
    final next = {...state.checked};
    if (!next.remove(id)) next.add(id);
    return _set(state.copyWith(checked: next));
  }

  Future<void> addExtra(String text) {
    final t = text.trim();
    if (t.isEmpty || state.extras.contains(t)) return Future.value();
    return _set(state.copyWith(extras: [...state.extras, t]));
  }

  Future<void> removeExtra(String text) => _set(state.copyWith(
        extras: [...state.extras]..remove(text),
        checked: {...state.checked}..remove('extra:$text'),
      ));

  Future<void> setBasics(bool on) => _set(state.copyWith(basics: on));

  Future<void> clear() => _set(const ShoppingListState());
}

final shoppingListProvider = NotifierProvider<ShoppingList, ShoppingListState>(ShoppingList.new);

/// Alle Einträge der Einkaufsliste, `null` solange die Rezepte laden.
final shoppingEntriesProvider = Provider<List<ShoppingEntry>?>((ref) {
  final plan = ref.watch(planResolverProvider);
  final list = ref.watch(shoppingListProvider);
  if (plan == null) return null;
  final meals = [
    for (final k in list.meals)
      if (WeekPlan.parseKey(k) case (final date, final slot)) plan.meal(date, slot),
  ];
  return [
    ...Shopping.aggregate(meals),
    if (list.basics)
      for (final b in Shopping.utBasics) ShoppingEntry(id: 'basic:$b', name: b, group: Shopping.basics),
    for (final e in list.extras) ShoppingEntry(id: 'extra:$e', name: e, group: Shopping.eigene),
  ];
});

/// Offene Einträge, für die Zahl am Korb.
final shoppingOpenCountProvider = Provider<int>((ref) {
  final entries = ref.watch(shoppingEntriesProvider) ?? const <ShoppingEntry>[];
  final checked = ref.watch(shoppingListProvider).checked;
  return entries.where((e) => !checked.contains(e.id)).length;
});
