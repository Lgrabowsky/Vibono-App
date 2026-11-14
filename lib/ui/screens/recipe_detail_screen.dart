import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/api/api_exception.dart';
import '../../data/models/content.dart';
import '../../data/models/sync_item.dart';
import '../../domain/coaching_plan.dart';
import '../../domain/energy_density.dart';
import '../../domain/recipe_picker.dart';
import '../../state/day_checks.dart';
import '../../state/providers.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import '../navigation.dart';
import '../widgets/ampel.dart';
import '../widgets/common.dart';
import '../widgets/day_sheets.dart';
import 'energy_density/energy_density_screen.dart';

class RecipeDetailScreen extends ConsumerWidget {
  const RecipeDetailScreen({super.key, required this.recipeId, this.preview});
  final int recipeId;
  final ContentItem? preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(contentItemProvider(recipeId));
    final sync = ref.watch(syncProvider);
    final r = item.value ?? preview;
    final favKey = 'recipe:$recipeId';
    final fav = sync.has(SyncCollection.favorites, favKey);

    return Scaffold(
      body: r == null
          ? (item.hasError
              ? ErrorRetry(
                  message: item.error is ApiException ? (item.error! as ApiException).userMessage : 'Fehler beim Laden.',
                  onRetry: () => ref.invalidate(contentItemProvider(recipeId)))
              : const LoadingView())
          : CustomScrollView(slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 260,
                backgroundColor: Colors.white,
                flexibleSpace: FlexibleSpaceBar(background: ContentImage(r.thumbnailUrl)),
                actions: [
                  IconButton.filledTonal(
                    tooltip: fav ? 'Aus Lieblingsrezepten entfernen' : 'Als Lieblingsrezept merken',
                    style: IconButton.styleFrom(backgroundColor: Colors.white),
                    icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: VibonoColors.green),
                    onPressed: () => sync.toggle(SyncCollection.favorites, favKey, {'post_id': recipeId, 'kind': 'recipe'}),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                sliver: SliverList.list(children: [
                  Text(r.title, style: VibonoText.hello),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final t in r.tags.where(_tagLabels.containsKey))
                      Chip(label: Text(_tagLabels[t]!), visualDensity: VisualDensity.compact),
                  ]),
                  if (r.energyDensity != null) ...[
                    const SizedBox(height: 12),
                    EdResult(density: r.energyDensity!, detail: 'Energiedichte dieses Rezepts.'),
                  ],
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _addToPlan(context, ref, r),
                        icon: const Icon(Icons.event_available_rounded, size: 18),
                        label: const Text('IN DEN PLAN'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => push(context, const EnergyDensityScreen()),
                        icon: const Icon(Icons.calculate_outlined, size: 18),
                        label: const Text('RECHNER'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  if (r.contentHtml != null)
                    HtmlWidget(r.contentHtml!, textStyle: VibonoText.body.copyWith(fontSize: 15))
                  else if (item.isLoading)
                    const LoadingView(),
                ]),
              ),
            ]),
    );
  }

  static const _tagLabels = {
    'vegetarisch': 'Vegetarisch',
    'vegan': 'Vegan',
    'ut-geeignet': 'UT-geeignet',
    'schnell': 'Schnell',
    'suppe': 'Suppe',
    'fruehstueck': 'Frühstück',
  };

  Future<void> _addToPlan(BuildContext context, WidgetRef ref, ContentItem r) async {
    final today = CoachingPlan.dateOnly(DateTime.now());
    DateTime day = today;
    MealSlot slot = r.tags.contains('fruehstueck') ? MealSlot.fruehstueck : MealSlot.abend;
    await showVibonoSheet(
      context,
      StatefulBuilder(builder: (context, setState) {
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('In den Wochenplan', style: VibonoText.hello),
          const SizedBox(height: 12),
          const SectionLabel('Tag'),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < 7; i++)
              ChoiceChip(
                label: Text(i == 0 ? 'Heute' : (i == 1 ? 'Morgen' : DateFormat('EE d.', 'de_DE').format(today.add(Duration(days: i))))),
                selected: day == today.add(Duration(days: i)),
                onSelected: (_) => setState(() => day = today.add(Duration(days: i))),
              ),
          ]),
          const SizedBox(height: 12),
          const SectionLabel('Mahlzeit'),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            for (final s in MealSlot.values)
              ChoiceChip(label: Text(s.label), selected: slot == s, onSelected: (_) => setState(() => slot = s)),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                final d = dayKey(day);
                await ref.read(syncProvider).upsert(SyncCollection.weekplan, '$d:${slot.wire}', {
                  'date': d,
                  'slot': slot.wire,
                  'recipe_id': r.id,
                });
                ref.invalidate(coachingDayProvider(day));
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('EINPLANEN'),
            ),
          ),
        ]);
      }),
    );
  }
}

/// Kleines Rezept-Kärtchen für Listen und Raster.
class RecipeCard extends ConsumerWidget {
  const RecipeCard({super.key, required this.recipe});
  final ContentItem recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fav = ref.watch(syncProvider).has(SyncCollection.favorites, 'recipe:${recipe.id}');
    return InkWell(
      onTap: () => openContent(context, recipe),
      borderRadius: BorderRadius.circular(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(fit: StackFit.expand, children: [
              ContentImage(recipe.thumbnailUrl),
              if (recipe.energyDensity != null)
                Positioned(
                  left: 6,
                  top: 6,
                  child: _Ed(value: recipe.energyDensity!),
                ),
              if (fav) const Positioned(right: 6, top: 6, child: Icon(Icons.favorite, color: Colors.white, size: 20)),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Text(recipe.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: VibonoText.cardTitle.copyWith(fontSize: 15)),
      ]),
    );
  }
}

class _Ed extends StatelessWidget {
  const _Ed({required this.value});
  final double value;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(5, 2, 7, 2),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: ampelColor(EnergyDensity.ampel(value)), shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text('${EnergyDensity.format(value, digits: 1)} kcal/g',
              style: const TextStyle(
                  fontFamily: VibonoFonts.display, fontWeight: FontWeight.w700, fontSize: 12, color: VibonoColors.grey800)),
        ]),
      );
}
