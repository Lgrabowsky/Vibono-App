import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/coaching_plan.dart';
import '../../domain/recipe_picker.dart';
import '../../domain/shopping.dart';
import '../../domain/week_plan.dart';
import '../../state/day_checks.dart';
import '../../state/meal_plan.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import '../navigation.dart';
import '../widgets/common.dart';

/// Einkaufsliste aus dem Wochenplan: Zutaten aller aufgenommenen
/// Mahlzeiten, nach Regalen sortiert und auf die Portionen umgerechnet.
class ShoppingListScreen extends ConsumerStatefulWidget {
  const ShoppingListScreen({super.key, this.onDone, this.notice, this.fillDays = 0, this.basics = false});

  /// Für die Tagesaufgabe „Einkaufen“: Knopf „Einkauf erledigt“.
  final VoidCallback? onDone;

  /// Hinweis nach dem Erstellen, z. B. wie viele Mahlzeiten dazukamen.
  final String? notice;

  /// Beim Öffnen die Mahlzeiten der nächsten Tage aufnehmen.
  final int fillDays;

  /// Grundausstattung für die Umstellungstage mit aufnehmen.
  final bool basics;

  @override
  ConsumerState<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends ConsumerState<ShoppingListScreen> {
  final _add = TextEditingController();
  bool _filled = false;
  bool _showMeals = false;

  @override
  void initState() {
    super.initState();
    if (widget.notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showMessage(context, widget.notice!);
      });
    }
  }

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  /// Einmalig beim Öffnen über die Tagesaufgabe.
  void _fillOnce(PlanResolver plan) {
    if (_filled || (widget.fillDays == 0 && !widget.basics)) return;
    _filled = true;
    final today = CoachingPlan.dateOnly(DateTime.now());
    final keys = [
      for (var i = 0; i < widget.fillDays; i++)
        ...plan.day(today.add(Duration(days: i))).where((m) => !m.isEmpty).map((m) => m.key),
    ];
    Future.microtask(() async {
      final list = ref.read(shoppingListProvider.notifier);
      await list.addMeals(keys);
      if (widget.basics) await list.setBasics(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(planResolverProvider);
    final entries = ref.watch(shoppingEntriesProvider);
    final list = ref.watch(shoppingListProvider);
    if (plan != null) _fillOnce(plan);

    return Scaffold(
      appBar: AppBar(
        title: const Text('EINKAUFSLISTE'),
        actions: [
          if (entries != null && entries.isNotEmpty)
            IconButton(
              tooltip: 'Liste teilen',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () => SharePlus.instance.share(ShareParams(text: _shareText(entries, list.checked))),
            ),
          if (!list.isEmpty)
            PopupMenuButton<String>(
              tooltip: 'Mehr',
              onSelected: (v) async {
                if (v == 'clear') {
                  await ref.read(shoppingListProvider.notifier).clear();
                  if (context.mounted) showMessage(context, 'Die Einkaufsliste ist leer.');
                }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'clear', child: Text('Liste leeren'))],
            ),
        ],
      ),
      body: entries == null
          ? const LoadingView()
          : list.isEmpty
              ? _Empty(onPlan: _toWeekplan)
              : _body(context, plan!, entries, list),
    );
  }

  Widget _body(BuildContext context, PlanResolver plan, List<ShoppingEntry> entries, ShoppingListState list) {
    final open = entries.where((e) => !list.checked.contains(e.id)).toList();
    final done = entries.where((e) => list.checked.contains(e.id)).toList();
    final meals = [
      for (final k in list.meals)
        if (WeekPlan.parseKey(k) case (final d, final s)) plan.meal(d, s),
    ]..sort((a, b) => a.key.compareTo(b.key));
    final groups = <String, List<ShoppingEntry>>{};
    for (final e in open) {
      groups.putIfAbsent(e.group, () => []).add(e);
    }

    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      _Summary(total: entries.length, done: done.length, meals: meals),
      const SizedBox(height: 14),
      TextField(
        controller: _add,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: 'Eigenen Eintrag hinzufügen',
          isDense: true,
          suffixIcon: IconButton(
            tooltip: 'Hinzufügen',
            icon: const Icon(Icons.add_rounded, color: VibonoColors.green700),
            onPressed: _addExtra,
          ),
        ),
        onSubmitted: (_) => _addExtra(),
      ),
      if (open.isEmpty && done.isNotEmpty) ...[
        const SizedBox(height: 20),
        Row(children: [
          const VibonoV(size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('Alles im Korb. Gut gemacht!', style: VibonoText.cardTitle.copyWith(color: VibonoColors.green700))),
        ]),
      ],
      for (final g in groups.entries) ...[
        const SizedBox(height: 20),
        SectionLabel(g.key),
        const SizedBox(height: 4),
        for (final e in g.value) _item(context, e, false),
      ],
      if (done.isNotEmpty) ...[
        const SizedBox(height: 20),
        SectionLabel('Im Korb (${done.length})', color: VibonoColors.grey400),
        const SizedBox(height: 4),
        for (final e in done) _item(context, e, true),
      ],
      if (meals.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Divider(height: 1),
        InkWell(
          onTap: () => setState(() => _showMeals = !_showMeals),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              Expanded(
                child: Text(
                  'Für ${meals.length} ${meals.length == 1 ? 'Mahlzeit' : 'Mahlzeiten'} aus dem Wochenplan',
                  style: VibonoText.body,
                ),
              ),
              Icon(_showMeals ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: VibonoColors.grey400),
            ]),
          ),
        ),
        if (_showMeals)
          for (final m in meals)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Expanded(
                  child: Text(
                    '${DateFormat('EE d.', 'de_DE').format(m.date)} · ${m.slot.mealLabel}: '
                    '${m.recipe?.title ?? 'frei'}${m.recipe == null ? '' : ' (${m.portions} P.)'}',
                    style: VibonoText.small,
                  ),
                ),
                IconButton(
                  tooltip: 'Von der Liste nehmen',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18, color: VibonoColors.grey400),
                  onPressed: () => ref.read(shoppingListProvider.notifier).removeMeal(m.key),
                ),
              ]),
            ),
      ],
      if (widget.onDone != null) ...[
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: () {
            widget.onDone!();
            Navigator.pop(context);
          },
          child: const Text('EINKAUF ERLEDIGT'),
        ),
      ],
    ]);
  }

  Widget _item(BuildContext context, ShoppingEntry e, bool checked) {
    final notifier = ref.read(shoppingListProvider.notifier);
    final row = InkWell(
      onTap: () => notifier.toggle(e.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          CheckCircle(checked: checked, size: 22, onTap: () => notifier.toggle(e.id), label: e.name),
          const SizedBox(width: 2),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                e.name,
                style: VibonoText.body.copyWith(
                  color: checked ? VibonoColors.grey400 : VibonoColors.grey900,
                  decoration: checked ? TextDecoration.lineThrough : null,
                  height: 1.3,
                ),
              ),
              if (e.recipes.isNotEmpty && !checked && e.recipeId == null)
                Text(
                  'für ${e.recipes.join(', ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VibonoText.small.copyWith(color: VibonoColors.grey400, fontSize: 11),
                ),
            ]),
          ),
          if (e.amountLabel.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(
              e.amountLabel,
              style: TextStyle(
                fontFamily: VibonoFonts.display,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: checked ? VibonoColors.grey400 : VibonoColors.grey700,
              ),
            ),
          ],
          if (e.recipeId != null)
            IconButton(
              tooltip: 'Rezept öffnen',
              icon: const Icon(Icons.chevron_right_rounded, color: VibonoColors.grey400),
              onPressed: () => _openRecipe(context, e.recipeId!),
            ),
        ]),
      ),
    );
    if (!e.id.startsWith('extra:')) return row;
    final text = e.id.substring(6);
    return Dismissible(
      key: ValueKey(e.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: VibonoColors.grey100,
        child: const Icon(Icons.delete_outline_rounded, color: VibonoColors.grey),
      ),
      onDismissed: (_) => notifier.removeExtra(text),
      child: row,
    );
  }

  void _openRecipe(BuildContext context, int id) {
    final r = ref.read(planResolverProvider)?.recipes.where((r) => r.id == id).firstOrNull;
    if (r != null) openContent(context, r);
  }

  void _addExtra() {
    ref.read(shoppingListProvider.notifier).addExtra(_add.text);
    _add.clear();
  }

  void _toWeekplan() {
    ref.read(tabIndexProvider.notifier).go(Tabs.wochenplan);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  String _shareText(List<ShoppingEntry> entries, Set<String> checked) {
    final b = StringBuffer('Einkaufsliste\n');
    String? group;
    for (final e in entries.where((e) => !checked.contains(e.id))) {
      if (e.group != group) {
        group = e.group;
        b.write('\n$group\n');
      }
      b.write('- ${e.amountLabel.isEmpty ? '' : '${e.amountLabel} '}${e.name}\n');
    }
    return b.toString();
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.total, required this.done, required this.meals});
  final int total;
  final int done;
  final List<PlannedMeal> meals;

  @override
  Widget build(BuildContext context) {
    final first = meals.isEmpty ? null : meals.first.date;
    final last = meals.isEmpty ? null : meals.last.date;
    final range = first == null
        ? null
        : first == last
            ? DateFormat('EEEE, d. MMMM', 'de_DE').format(first)
            : '${DateFormat('EE d.', 'de_DE').format(first)} bis ${DateFormat('EE d. MMMM', 'de_DE').format(last!)}';
    return Container(
      color: VibonoColors.green050,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (range != null)
          Text(range.toUpperCase(),
              style: const TextStyle(
                fontFamily: VibonoFonts.display,
                fontSize: 12,
                letterSpacing: 1,
                color: Color(0xFF6A871F),
              )),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text('$done',
              style: const TextStyle(
                fontFamily: VibonoFonts.display,
                fontWeight: FontWeight.w300,
                fontSize: 30,
                height: 1,
                color: VibonoColors.grey900,
              )),
          const SizedBox(width: 6),
          Text('von $total im Korb', style: VibonoText.small.copyWith(color: VibonoColors.grey)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : done / total,
            minHeight: 6,
            color: VibonoColors.green,
            backgroundColor: Colors.white,
          ),
        ),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onPlan});
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: VibonoColors.green050, shape: BoxShape.circle),
              child: const Icon(Icons.shopping_basket_outlined, size: 34, color: VibonoColors.green),
            ),
            const SizedBox(height: 16),
            Text('Deine Einkaufsliste ist leer', style: VibonoText.cardTitle.copyWith(fontSize: 18)),
            const SizedBox(height: 6),
            const Text(
              'Tippe im Wochenplan auf „Einkaufsliste erstellen“. Dann stehen hier alle Zutaten, '
              'passend zu deinen Portionen und nach Regalen sortiert.',
              textAlign: TextAlign.center,
              style: VibonoText.body,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onPlan, child: const Text('ZUM WOCHENPLAN')),
          ]),
        ),
      );
}
