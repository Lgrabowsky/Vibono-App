import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/content.dart';
import '../../data/models/json.dart';
import '../../data/models/sync_item.dart';
import '../../domain/coaching_plan.dart';
import '../../domain/recipe_picker.dart';
import '../../state/day_checks.dart';
import '../../state/providers.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import '../navigation.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';

/// Wochenplan (synchron mit „Mein Wochenplan“ auf MyVibono). Die App füllt
/// leere Plätze automatisch mit passenden Rezepten.
class WeekplanScreen extends ConsumerStatefulWidget {
  const WeekplanScreen({super.key});

  @override
  ConsumerState<WeekplanScreen> createState() => _WeekplanScreenState();
}

class _WeekplanScreenState extends ConsumerState<WeekplanScreen> {
  late DateTime _monday;


  @override
  void initState() {
    super.initState();
    final t = CoachingPlan.dateOnly(DateTime.now());
    _monday = t.subtract(Duration(days: t.weekday - 1));
  }

  @override
  Widget build(BuildContext context) {
    final recipes = ref.watch(recipesProvider);
    final sync = ref.watch(syncProvider);
    final profile = ref.watch(sessionProvider).profile;
    final start = profile.coachingStartDate ?? CoachingPlan.dateOnly(DateTime.now());
    final week = isoWeek(_monday);
    final today = CoachingPlan.dateOnly(DateTime.now());

    return SafeArea(
      bottom: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(children: [
            const Expanded(child: Text('WOCHENPLAN', style: VibonoText.screenTitle)),
            IconButton(
              tooltip: 'Einkaufsliste',
              icon: const Icon(Icons.shopping_basket_outlined),
              onPressed: () => push(context, const ShoppingListScreen()),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            IconButton(
              tooltip: 'Vorherige Woche',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => setState(() => _monday = _monday.subtract(const Duration(days: 7))),
            ),
            Expanded(
              child: Text(
                'KW $week · ${DateFormat('d. MMM', 'de_DE').format(_monday)} – ${DateFormat('d. MMM', 'de_DE').format(_monday.add(const Duration(days: 6)))}',
                textAlign: TextAlign.center,
                style: VibonoText.cardTitle,
              ),
            ),
            IconButton(
              tooltip: 'Nächste Woche',
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: () => setState(() => _monday = _monday.add(const Duration(days: 7))),
            ),
          ]),
        ),
        Expanded(
          child: switch (recipes) {
            AsyncData(:final value) => ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: 7,
                itemBuilder: (_, i) {
                  final d = _monday.add(Duration(days: i));
                  final phase = CoachingPlan.phaseFor(start, d);
                  final auto = RecipePicker.forDate(d, value, profile, phase.key);
                  return _DayPlan(
                    date: d,
                    isToday: d == today,
                    phaseLabel: CoachingPlan.shortLabel(phase),
                    slots: {
                      for (final s in MealSlot.values)
                        s: _planned(sync.get(SyncCollection.weekplan, '${dayKey(d)}:${s.wire}'), value) ?? auto[s],
                    },
                    onSwap: (slot, current) async {
                      final alt = RecipePicker.alternative(current, slot, value, profile, phase.key);
                      if (alt == null) {
                        showMessage(context, 'Kein anderes passendes Rezept gefunden.');
                        return;
                      }
                      final k = dayKey(d);
                      await sync.upsert(
                          SyncCollection.weekplan, '$k:${slot.wire}', {'date': k, 'slot': slot.wire, 'recipe_id': alt.id});
                      ref.invalidate(coachingDayProvider(d));
                    },
                  );
                },
              ),
            AsyncError() =>
              ErrorRetry(message: 'Der Wochenplan konnte nicht geladen werden.', onRetry: () => ref.invalidate(recipesProvider)),
            _ => const LoadingView(),
          },
        ),
      ]),
    );
  }

  /// ISO-Kalenderwoche (Woche mit dem Donnerstag zählt).
  static int isoWeek(DateTime d) {
    final thursday = d.add(Duration(days: 4 - d.weekday));
    final firstJan = DateTime(thursday.year);
    return CoachingPlan.daysBetween(firstJan, thursday) ~/ 7 + 1;
  }

  ContentItem? _planned(Json? data, List<ContentItem> recipes) {
    final id = asInt(data?['recipe_id']);
    return id == null ? null : recipes.where((r) => r.id == id).firstOrNull;
  }
}

class _DayPlan extends StatelessWidget {
  const _DayPlan({
    required this.date,
    required this.isToday,
    required this.phaseLabel,
    required this.slots,
    required this.onSwap,
  });

  final DateTime date;
  final bool isToday;
  final String phaseLabel;
  final Map<MealSlot, ContentItem?> slots;
  final void Function(MealSlot, ContentItem) onSwap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                DateFormat('EEEE, d. MMMM', 'de_DE').format(date),
                style: VibonoText.cardTitle.copyWith(color: isToday ? VibonoColors.green700 : VibonoColors.grey900),
              ),
            ),
            Text(phaseLabel, style: VibonoText.small),
          ]),
          const SizedBox(height: 6),
          for (final e in slots.entries)
            if (e.value != null)
              InkWell(
                onTap: () => openContent(context, e.value!),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: ContentImage(e.value!.thumbnailUrl)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.key.label.toUpperCase(), style: VibonoText.label.copyWith(fontSize: 11)),
                        Text(e.value!.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: VibonoText.body),
                      ]),
                    ),
                    if (e.value!.energyDensity != null) EdBadge(e.value!.energyDensity!),
                    IconButton(
                      tooltip: 'Rezept tauschen',
                      icon: const Icon(Icons.swap_horiz_rounded, color: VibonoColors.grey),
                      onPressed: () => onSwap(e.key, e.value!),
                    ),
                  ]),
                ),
              ),
          const Divider(height: 16),
        ]),
      );
}

/// Einkaufsliste für die nächsten Tage. Solange die Schnittstelle keine
/// strukturierten Zutaten liefert, listet sie die geplanten Rezepte und die
/// Grundausstattung der aktuellen Phase.
class ShoppingListScreen extends ConsumerWidget {
  const ShoppingListScreen({super.key, this.onDone});
  final VoidCallback? onDone;

  static const _utBasics = [
    'Eier',
    'Magerquark und körniger Frischkäse',
    'Hähnchenbrust oder Pute',
    'Fisch (z. B. Kabeljau, Lachs)',
    'Gemüse für Suppen (Zucchini, Brokkoli, Paprika)',
    'Salat und Gurke',
    'Gemüse- oder Fleischbrühe',
    'Kräuter und Gewürze',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = CoachingPlan.dateOnly(DateTime.now());
    final checks = ref.watch(dayChecksProvider('einkauf'));
    final days = [for (var i = 0; i < 3; i++) ref.watch(coachingDayProvider(today.add(Duration(days: i)))).value];
    final recipes = {
      for (final d in days.nonNulls) for (final r in d.recipes) r.id: r,
    }.values.toList();

    Widget item(String id, String text) => CheckboxListTile(
          value: checks.contains(id),
          onChanged: (_) => ref.read(dayChecksProvider('einkauf').notifier).toggle(id),
          title: Text(text,
              style: VibonoText.body.copyWith(decoration: checks.contains(id) ? TextDecoration.lineThrough : null)),
          activeColor: VibonoColors.green,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('EINKAUFSLISTE')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const SectionLabel('Grundausstattung'),
        for (final b in _utBasics) item('basic:$b', b),
        const SizedBox(height: 12),
        const SectionLabel('Für deine Rezepte der nächsten 3 Tage'),
        if (recipes.isEmpty) const Padding(padding: EdgeInsets.all(8), child: LoadingView()),
        for (final r in recipes) item('recipe:${r.id}', r.title),
        if (onDone != null) ...[
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              onDone!();
              Navigator.pop(context);
            },
            child: const Text('EINKAUF ERLEDIGT'),
          ),
        ],
      ]),
    );
  }
}
