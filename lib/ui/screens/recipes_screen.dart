import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/content.dart';
import '../../data/models/sync_item.dart';
import '../../domain/energy_density.dart';
import '../../state/providers.dart';
import '../../theme/vibono_theme.dart';
import '../navigation.dart';
import '../widgets/common.dart';
import 'energy_density/energy_density_screen.dart';
import 'recipe_detail_screen.dart';

class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});

  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  String _query = '';
  String _filter = 'alle';

  static const _filters = {
    'alle': 'Alle',
    'favoriten': 'Lieblingsrezepte',
    'gruen': 'Grün',
    'fruehstueck': 'Frühstück',
    'vegetarisch': 'Vegetarisch',
    'vegan': 'Vegan',
    'ut-geeignet': 'UT-geeignet',
  };

  bool _match(ContentItem r, Set<String> favs) {
    if (_query.isNotEmpty && !r.title.toLowerCase().contains(_query.toLowerCase())) return false;
    return switch (_filter) {
      'alle' => true,
      'favoriten' => favs.contains('recipe:${r.id}'),
      'gruen' => r.energyDensity != null && EnergyDensity.ampel(r.energyDensity!) == Ampel.gruen,
      _ => r.tags.contains(_filter) || (_filter == 'vegetarisch' && r.tags.contains('vegan')),
    };
  }

  @override
  Widget build(BuildContext context) {
    final recipes = ref.watch(recipesProvider);
    final favs = {for (final f in ref.watch(syncProvider).items(SyncCollection.favorites)) f.key};
    return SafeArea(
      bottom: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(children: [
            const Expanded(child: Text('REZEPTE', style: VibonoText.screenTitle)),
            IconButton(
              tooltip: 'Energiedichte-Rechner',
              icon: const Icon(Icons.calculate_outlined),
              onPressed: () => push(context, const EnergyDensityScreen()),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Rezept suchen',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              for (final f in _filters.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(f.value),
                    selected: _filter == f.key,
                    onSelected: (_) => setState(() => _filter = f.key),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: switch (recipes) {
            AsyncData(:final value) => () {
                final list = value.where((r) => _match(r, favs)).toList();
                if (list.isEmpty) {
                  return const Center(child: Text('Keine passenden Rezepte gefunden.', style: VibonoText.body));
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(recipesProvider.future),
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.98,
                    ),
                    itemCount: list.length,
                    itemBuilder: (_, i) => RecipeCard(recipe: list[i]),
                  ),
                );
              }(),
            AsyncError() => ErrorRetry(
                message: 'Rezepte konnten nicht geladen werden.', onRetry: () => ref.invalidate(recipesProvider)),
            _ => const LoadingView(),
          },
        ),
      ]),
    );
  }
}
