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
import '../../domain/week_plan.dart';
import '../../domain/shopping.dart';
import '../../state/meal_plan.dart';
import '../../state/providers.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import '../navigation.dart';
import '../widgets/ampel.dart';
import '../widgets/common.dart';
import '../widgets/day_sheets.dart';
import 'energy_density/energy_density_screen.dart';
import 'rewards_screen.dart';

/// Rezept mit einstellbaren Portionen. Kommt es aus dem Wochenplan
/// ([date] und [slot]), werden geänderte Portionen dort mitgespeichert.
class RecipeDetailScreen extends ConsumerStatefulWidget {
  const RecipeDetailScreen({super.key, required this.recipeId, this.preview, this.portions, this.date, this.slot});
  final int recipeId;
  final ContentItem? preview;
  final int? portions;
  final DateTime? date;
  final MealSlot? slot;

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen> {
  late int _portions =
      widget.portions ?? ref.read(sessionProvider).profile.householdSize.clamp(1, WeekPlan.maxPortions);

  int get recipeId => widget.recipeId;

  Future<void> _setPortions(ContentItem r, int n) async {
    setState(() => _portions = n);
    final d = widget.date;
    final s = widget.slot;
    if (d != null && s != null) await savePlannedMeal(ref, d, s, recipeId: r.id, portions: n);
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(contentItemProvider(recipeId));
    final sync = ref.watch(syncProvider);
    final r = item.value ?? widget.preview;
    final favKey = 'recipe:$recipeId';
    final fav = sync.has(SyncCollection.favorites, favKey);
    final html = r?.contentHtml;

    final err = item.error;
    if (err is ApiException && err.isRewardRequired) {
      return Scaffold(
        appBar: AppBar(title: const Text('Rezept')),
        body: ExclusiveUnlockPanel(postId: recipeId, error: err, title: widget.preview?.title),
      );
    }

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
                  if (r.ingredients.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _Ingredients(recipe: r, portions: _portions, onPortions: (n) => _setPortions(r, n)),
                  ],
                  const SizedBox(height: 16),
                  if (html != null)
                    HtmlWidget(
                      r.ingredients.isEmpty ? html : stripIngredientSection(html),
                      textStyle: VibonoText.body.copyWith(fontSize: 15),
                    )
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
          const SizedBox(height: 4),
          Text('$_portions ${_portions == 1 ? 'Portion' : 'Portionen'}', style: VibonoText.small),
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
              ChoiceChip(label: Text(s.mealLabel), selected: slot == s, onSelected: (_) => setState(() => slot = s)),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                await savePlannedMeal(ref, day, slot, recipeId: r.id, portions: _portions);
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
              if (recipe.exclusive && recipe.locked)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
                    decoration: BoxDecoration(color: VibonoColors.green900.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(999)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.lock_rounded, size: 13, color: Colors.white),
                      const SizedBox(width: 3),
                      Text('Exklusiv · ${formatPoints(recipe.rewardCost ?? 0)} P.',
                          style: VibonoText.small.copyWith(color: Colors.white, fontSize: 12)),
                    ]),
                  ),
                ),
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

/// Entfernt den Zutaten-Abschnitt („<h3>Zutaten …</h3><ul>…</ul>“) aus dem
/// Rezepttext, wenn die App die Zutaten selbst mit Portionen anzeigt.
String stripIngredientSection(String html) => html.replaceFirst(
      RegExp(r'<h[1-6][^>]*>[^<]*Zutaten[^<]*</h[1-6]>\s*(<ul[\s\S]*?</ul>|<ol[\s\S]*?</ol>)', caseSensitive: false),
      '',
    );

/// Zutatenliste mit Portionsregler, Mengen werden umgerechnet.
class _Ingredients extends StatelessWidget {
  const _Ingredients({required this.recipe, required this.portions, required this.onPortions});
  final ContentItem recipe;
  final int portions;
  final ValueChanged<int> onPortions;

  @override
  Widget build(BuildContext context) {
    final servings = recipe.servings;
    final factor = servings == null ? 1.0 : portions / servings;
    String? group;
    final rows = <Widget>[];
    for (final i in recipe.ingredients) {
      if (i.group != null && i.group!.isNotEmpty && i.group != group) {
        group = i.group;
        rows.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text(group!, style: VibonoText.cardTitle.copyWith(fontSize: 14, color: VibonoColors.grey700)),
        ));
      }
      final amount = i.amount == null ? '' : Shopping.formatAmount(i.amount! * factor, i.unit);
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 86,
            child: Text(
              amount,
              style: const TextStyle(
                fontFamily: VibonoFonts.display,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: VibonoColors.grey800,
              ),
            ),
          ),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: i.name),
              if (i.amount == null)
                const TextSpan(text: '  nach Geschmack', style: TextStyle(color: VibonoColors.grey400, fontSize: 12)),
            ]), style: VibonoText.body.copyWith(color: VibonoColors.grey900, height: 1.35)),
          ),
        ]),
      ));
      rows.add(const Divider(height: 1, color: VibonoColors.grey100));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(child: SectionLabel('Zutaten')),
        if (servings != null)
          PortionStepper(value: portions, onChanged: onPortions)
        else
          const Text('Mengen laut Rezept', style: VibonoText.small),
      ]),
      const SizedBox(height: 6),
      ...rows,
    ]);
  }
}

