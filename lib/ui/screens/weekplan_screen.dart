import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/content.dart';
import '../../domain/coaching_plan.dart';
import '../../domain/energy_density.dart';
import '../../domain/recipe_picker.dart';
import '../../domain/week_plan.dart';
import '../../state/day_checks.dart';
import '../../state/meal_plan.dart';
import '../../state/providers.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import '../navigation.dart';
import '../widgets/ampel.dart';
import '../widgets/common.dart';
import '../widgets/day_sheets.dart';
import 'shopping_list_screen.dart';

export 'shopping_list_screen.dart' show ShoppingListScreen;

/// Wochenplan als Tagesansicht mit Wochenleiste (synchron mit „Mein
/// Wochenplan“ auf MyVibono). Die App füllt alle Plätze selbst, der Nutzer
/// kann tauschen, Portionen ändern, verschieben oder einen Platz freigeben.
class WeekplanScreen extends ConsumerStatefulWidget {
  const WeekplanScreen({super.key});

  @override
  ConsumerState<WeekplanScreen> createState() => _WeekplanScreenState();
}

class _WeekplanScreenState extends ConsumerState<WeekplanScreen> {
  late DateTime _selected;

  DateTime get _today => CoachingPlan.dateOnly(DateTime.now());
  DateTime get _monday => WeekPlan.mondayOf(_selected);

  @override
  void initState() {
    super.initState();
    _selected = _today;
  }

  void _shiftWeek(int weeks) => setState(() => _selected = _selected.add(Duration(days: 7 * weeks)));

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(planResolverProvider);
    final recipes = ref.watch(recipesProvider);
    final openCount = ref.watch(shoppingOpenCountProvider);

    return SafeArea(
      bottom: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Header(
          week: isoWeek(_monday),
          openCount: openCount,
          onPrev: () => _shiftWeek(-1),
          onNext: () => _shiftWeek(1),
          onToday: () => setState(() => _selected = _today),
          onBasket: () => push(context, const ShoppingListScreen()),
        ),
        if (plan != null)
          _DateStrip(
            selected: _selected,
            today: _today,
            densityOf: (d) => WeekPlan.dayDensity(plan.day(d)),
            onSelect: (d) => setState(() => _selected = d),
          ),
        Expanded(
          child: plan != null
              ? _DayView(
                  key: ValueKey(_selected),
                  date: _selected,
                  today: _today,
                  meals: plan.day(_selected),
                  onCreateList: _monday.add(const Duration(days: 6)).isBefore(_today) ? null : _createList,
                )
              : recipes.hasError
                  ? ErrorRetry(
                      message: 'Der Wochenplan konnte nicht geladen werden.',
                      onRetry: () => ref.invalidate(recipesProvider),
                    )
                  : const LoadingView(),
        ),
      ]),
    );
  }

  /// Die App entscheidet: alle geplanten Mahlzeiten ab heute (bzw. ab
  /// Wochenbeginn) bis Sonntag der angezeigten Woche.
  Future<void> _createList() async {
    final plan = ref.read(planResolverProvider);
    if (plan == null) return;
    final from = _monday.isBefore(_today) ? _today : _monday;
    final sunday = _monday.add(const Duration(days: 6));
    final keys = <String>[];
    for (var d = from; !d.isAfter(sunday); d = d.add(const Duration(days: 1))) {
      keys.addAll(plan.day(d).where((m) => !m.isEmpty).map((m) => m.key));
    }
    final added = await ref.read(shoppingListProvider.notifier).addMeals(keys);
    if (!mounted) return;
    final range = from == sunday
        ? DateFormat('EEEE', 'de_DE').format(from)
        : '${DateFormat('EE', 'de_DE').format(from)} bis ${DateFormat('EE', 'de_DE').format(sunday)}';
    push(
      context,
      ShoppingListScreen(
        notice: added == 0
            ? 'Die Mahlzeiten von $range stehen schon auf der Liste.'
            : 'Zutaten für $added ${added == 1 ? 'Mahlzeit' : 'Mahlzeiten'} ($range) hinzugefügt.',
      ),
    );
  }

  /// ISO-Kalenderwoche (Woche mit dem Donnerstag zählt).
  static int isoWeek(DateTime d) {
    final thursday = d.add(Duration(days: 4 - d.weekday));
    final firstJan = DateTime(thursday.year);
    return CoachingPlan.daysBetween(firstJan, thursday) ~/ 7 + 1;
  }
}

// ---------------------------------------------------------------------------
// Kopf und Wochenleiste
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.week,
    required this.openCount,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onBasket,
  });

  final int week;
  final int openCount;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onBasket;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 10, 12),
        child: Row(children: [
          const Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'MEIN WOCHENPLAN',
                style: TextStyle(
                  fontFamily: VibonoFonts.display,
                  fontWeight: FontWeight.w300,
                  fontSize: 22,
                  letterSpacing: 0.9,
                  color: VibonoColors.green,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              border: Border.all(color: VibonoColors.grey300),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _PillArrow(icon: Icons.chevron_left_rounded, tooltip: 'Vorherige Woche', onTap: onPrev),
              Tooltip(
                message: 'Zu heute',
                child: GestureDetector(
                  onTap: onToday,
                  child: Text('KW $week',
                      style: const TextStyle(
                        fontFamily: VibonoFonts.display,
                        fontSize: 13,
                        letterSpacing: 0.5,
                        color: VibonoColors.grey,
                      )),
                ),
              ),
              _PillArrow(icon: Icons.chevron_right_rounded, tooltip: 'Nächste Woche', onTap: onNext),
            ]),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: openCount == 0 ? 'Einkaufsliste' : 'Einkaufsliste, $openCount offen',
            onPressed: onBasket,
            icon: Badge(
              isLabelVisible: openCount > 0,
              backgroundColor: VibonoColors.green,
              textColor: Colors.white,
              label: Text('$openCount', style: const TextStyle(fontFamily: VibonoFonts.display, fontSize: 11)),
              child: const Icon(Icons.shopping_basket_outlined, color: VibonoColors.grey),
            ),
          ),
        ]),
      );
}

class _PillArrow extends StatelessWidget {
  const _PillArrow({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: 18,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(icon, size: 18, color: VibonoColors.grey),
          ),
        ),
      );
}

/// Datumsleiste zum seitlichen Wischen über viele Wochen. Der gewählte
/// Tag (anfangs heute) steht in der Mitte.
class _DateStrip extends StatefulWidget {
  const _DateStrip({
    required this.selected,
    required this.today,
    required this.densityOf,
    required this.onSelect,
  });

  final DateTime selected;
  final DateTime today;
  final double? Function(DateTime) densityOf;
  final ValueChanged<DateTime> onSelect;

  @override
  State<_DateStrip> createState() => _DateStripState();
}

class _DateStripState extends State<_DateStrip> {
  /// Tage vor und nach heute, durch die gewischt werden kann.
  static const _range = 400;
  static const _visible = 7;

  ScrollController? _ctrl;
  double _itemW = 52;
  double _viewport = 7 * 52;

  DateTime get selected => widget.selected;
  DateTime get today => widget.today;

  int _indexOf(DateTime d) => CoachingPlan.daysBetween(today, d) + _range;
  DateTime _dateAt(int i) => today.add(Duration(days: i - _range));
  double _offsetFor(DateTime d) => (_indexOf(d) * _itemW - (_viewport - _itemW) / 2).clamp(0, double.infinity);

  @override
  void didUpdateWidget(_DateStrip old) {
    super.didUpdateWidget(old);
    final c = _ctrl;
    if (old.selected != selected && c != null && c.hasClients) {
      final target = _offsetFor(selected).clamp(0.0, c.position.maxScrollExtent);
      c.animateTo(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        _viewport = c.maxWidth;
        _itemW = (c.maxWidth - 8) / _visible;
        _ctrl ??= ScrollController(initialScrollOffset: _offsetFor(selected));
        return SizedBox(
          height: 70,
          child: ListView.builder(
            controller: _ctrl,
            scrollDirection: Axis.horizontal,
            itemExtent: _itemW,
            itemCount: 2 * _range + 1,
            itemBuilder: (_, i) {
              final d = _dateAt(i);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(child: _dayTile(d)),
                  // Feine Linie vor jedem Montag trennt die Wochen.
                  if (d.weekday == DateTime.monday && d != selected)
                    const Positioned(
                      left: -2.5,
                      top: 14,
                      bottom: 14,
                      child: SizedBox(width: 1, child: ColoredBox(color: VibonoColors.grey200)),
                    ),
                ]),
              );
            },
          ),
        );
      });

  Widget _dayTile(DateTime d) {
    final isSel = d == selected;
    final isToday = d == today;
    final density = widget.densityOf(d);
    final dot = isSel
        ? Colors.white
        : density == null
            ? VibonoColors.grey300
            : ampelColor(EnergyDensity.ampel(density));
    return Semantics(
      button: true,
      selected: isSel,
      label: '${DateFormat('EEEE, d. MMMM', 'de_DE').format(d)}${isToday ? ', heute' : ''}',
      child: Material(
        color: isSel ? VibonoColors.green : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
        child: InkWell(
          onTap: () => widget.onSelect(d),
          borderRadius: BorderRadius.circular(3),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 7),
            child: Column(children: [
              Text(
                DateFormat('EE', 'de_DE').format(d).replaceAll('.', '').toUpperCase(),
                style: TextStyle(
                  fontFamily: VibonoFonts.display,
                  fontSize: 11,
                  letterSpacing: 0.7,
                  color: isSel ? Colors.white.withValues(alpha: 0.85) : VibonoColors.grey400,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${d.day}',
                style: TextStyle(
                  fontFamily: VibonoFonts.display,
                  fontSize: 20,
                  height: 1,
                  fontWeight: isSel || isToday ? FontWeight.w600 : FontWeight.w300,
                  color: isSel ? Colors.white : (isToday ? VibonoColors.green700 : VibonoColors.grey900),
                ),
              ),
              const SizedBox(height: 5),
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tagesansicht
// ---------------------------------------------------------------------------

class _DayView extends ConsumerWidget {
  const _DayView({
    super.key,
    required this.date,
    required this.today,
    required this.meals,
    required this.onCreateList,
  });

  final DateTime date;
  final DateTime today;
  final List<PlannedMeal> meals;
  final VoidCallback? onCreateList;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checks = ref.watch(dayChecksProvider(dayKey(date)));
    final canCheck = !date.isAfter(today);
    final planned = meals.where((m) => !m.isEmpty).toList();
    final eaten = planned.where((m) => checks.contains('meal:${m.slot.wire}')).length;
    final status = canCheck && eaten > 0
        ? '$eaten von ${planned.length} ${planned.length == 1 ? 'Mahlzeit' : 'Mahlzeiten'} gegessen'
        : '${planned.length} von 3 Mahlzeiten geplant';

    return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 28), children: [
      _DaySummary(date: date, density: WeekPlan.dayDensity(meals), status: status),
      const SizedBox(height: 16),
      for (final m in meals) ...[
        if (m.isEmpty)
          _EmptySlotCard(meal: m)
        else
          _MealCard(
            meal: m,
            checked: checks.contains('meal:${m.slot.wire}'),
            onCheck: canCheck ? () => ref.read(dayChecksProvider(dayKey(date)).notifier).toggle('meal:${m.slot.wire}') : null,
          ),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 4),
      const _PrincipleNote(),
      if (onCreateList != null) ...[
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: onCreateList,
          icon: const Icon(Icons.shopping_basket_outlined, size: 20),
          label: const Text('EINKAUFSLISTE ERSTELLEN'),
        ),
      ],
    ]);
  }
}

class _DaySummary extends StatelessWidget {
  const _DaySummary({required this.date, required this.density, required this.status});
  final DateTime date;
  final double? density;
  final String status;

  @override
  Widget build(BuildContext context) {
    final d = density;
    return Container(
      color: VibonoColors.green050,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              DateFormat('EEEE, d. MMMM', 'de_DE').format(date).toUpperCase(),
              style: const TextStyle(
                fontFamily: VibonoFonts.display,
                fontSize: 12,
                letterSpacing: 1,
                color: Color(0xFF6A871F),
              ),
            ),
            const SizedBox(height: 4),
            Text.rich(TextSpan(children: [
              TextSpan(
                text: d == null ? '–' : EnergyDensity.format(d, digits: 1),
                style: const TextStyle(
                  fontFamily: VibonoFonts.display,
                  fontWeight: FontWeight.w300,
                  fontSize: 30,
                  height: 1.1,
                  color: VibonoColors.grey900,
                ),
              ),
              TextSpan(text: '  kcal/g Tages-ED', style: VibonoText.small.copyWith(color: VibonoColors.grey)),
              if (d != null) ...[
                const TextSpan(text: '  '),
                WidgetSpan(alignment: PlaceholderAlignment.middle, child: AmpelDot(d, size: 12)),
              ],
            ])),
            const SizedBox(height: 4),
            Text(status, style: VibonoText.small),
          ]),
        ),
        if (d != null) ...[const SizedBox(width: 12), AmpelScale(value: d, width: 112)],
      ]),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, required this.checked, required this.onCheck});
  final PlannedMeal meal;
  final bool checked;
  final VoidCallback? onCheck;

  @override
  Widget build(BuildContext context) {
    final r = meal.recipe!;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x1F1C1C1C), blurRadius: 10, offset: Offset(0, 2))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => showVibonoSheet(context, _MealSheet(date: meal.date, slot: meal.slot)),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, onCheck == null ? 12 : 6, 12),
            child: Row(children: [
              SizedBox(width: 56, height: 56, child: ContentImage(r.thumbnailUrl)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    meal.slot.mealLabel.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: VibonoFonts.display,
                      fontSize: 12,
                      letterSpacing: 1,
                      color: VibonoColors.green600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    r.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: VibonoText.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: VibonoColors.grey900,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  _MetaLine(recipe: r, portions: meal.portions),
                ]),
              ),
              if (onCheck != null)
                CheckCircle(
                  checked: checked,
                  onTap: onCheck,
                  label: '${meal.slot.mealLabel} gegessen',
                )
              else
                const Icon(Icons.more_horiz_rounded, color: VibonoColors.grey300),
            ]),
          ),
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.recipe, required this.portions});
  final ContentItem recipe;
  final int portions;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontFamily: VibonoFonts.body, fontSize: 11, color: VibonoColors.grey);
    final ed = recipe.energyDensity;
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 2, children: [
      if (ed != null) ...[
        Text('ED: ${EnergyDensity.format(ed, digits: 1)} kcal/g', style: style),
        AmpelDot(ed),
      ],
      Text(
        '${ed != null ? '· ' : ''}$portions ${portions == 1 ? 'Portion' : 'Portionen'}',
        style: style.copyWith(color: VibonoColors.grey400),
      ),
    ]);
  }
}

class _EmptySlotCard extends ConsumerWidget {
  const _EmptySlotCard({required this.meal});
  final PlannedMeal meal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = meal.suggestion;
    return CustomPaint(
      painter: _DashedRectPainter(color: VibonoColors.grey300),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        child: Row(children: [
          Semantics(
            button: true,
            label: '${meal.slot.mealLabel} selbst aussuchen',
            child: Material(
              color: VibonoColors.green050,
              child: InkWell(
                onTap: () => _pick(context, ref),
                child: const SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(Icons.add_rounded, color: VibonoColors.green, size: 28),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                meal.slot.mealLabel.toUpperCase(),
                style: const TextStyle(
                  fontFamily: VibonoFonts.display,
                  fontSize: 12,
                  letterSpacing: 1,
                  color: VibonoColors.green600,
                ),
              ),
              const SizedBox(height: 2),
              Text('${meal.slot.mealLabel} planen',
                  style: VibonoText.body.copyWith(fontWeight: FontWeight.w700, color: VibonoColors.grey700, height: 1.3)),
              if (s != null) ...[
                const SizedBox(height: 3),
                Row(children: [
                  Flexible(
                    child: Text(
                      'Vorschlag: ${s.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: VibonoFonts.body, fontSize: 11, color: VibonoColors.grey400),
                    ),
                  ),
                  if (s.energyDensity != null) ...[const SizedBox(width: 6), AmpelDot(s.energyDensity!)],
                ]),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          if (s != null)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                side: const BorderSide(color: VibonoColors.green, width: 1.5),
                foregroundColor: VibonoColors.green700,
                textStyle: const TextStyle(fontFamily: VibonoFonts.display, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              onPressed: () => savePlannedMeal(ref, meal.date, meal.slot, recipeId: s.id, portions: meal.portions),
              child: const Text('ÜBERNEHMEN'),
            ),
        ]),
      ),
    );
  }

  void _pick(BuildContext context, WidgetRef ref) =>
      showVibonoSheet(context, _RecipeChooser(date: meal.date, slot: meal.slot, portions: meal.portions));
}

class _PrincipleNote extends StatelessWidget {
  const _PrincipleNote();

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: VibonoColors.green050,
          border: Border(top: BorderSide(color: VibonoColors.green, width: 3)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.lightbulb_outline_rounded, size: 18, color: VibonoColors.green700),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Drei Mahlzeiten pro Tag, keine Zwischenmahlzeiten: Das ist das Vibono-Prinzip. '
              'Der Plan hat deshalb genau drei Plätze.',
              style: VibonoText.small.copyWith(color: VibonoColors.grey700, fontSize: 12.5),
            ),
          ),
        ]),
      );
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const dash = 4.0;
    const gap = 3.0;
    void line(Offset a, Offset b) {
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var t = 0.0; t < len; t += dash + gap) {
        canvas.drawLine(a + dir * t, a + dir * (t + dash).clamp(0, len), paint);
      }
    }

    final r = Offset.zero & size;
    final rr = r.deflate(0.5);
    line(rr.topLeft, rr.topRight);
    line(rr.topRight, rr.bottomRight);
    line(rr.bottomRight, rr.bottomLeft);
    line(rr.bottomLeft, rr.topLeft);
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Blätter: Mahlzeit bearbeiten, Rezept aussuchen
// ---------------------------------------------------------------------------

class _MealSheet extends ConsumerStatefulWidget {
  const _MealSheet({required this.date, required this.slot});
  final DateTime date;
  final MealSlot slot;

  @override
  ConsumerState<_MealSheet> createState() => _MealSheetState();
}

class _MealSheetState extends ConsumerState<_MealSheet> {
  bool _moving = false;
  late DateTime _moveDay = widget.date;
  late MealSlot _moveSlot = widget.slot;

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(planResolverProvider);
    final meal = plan?.meal(widget.date, widget.slot);
    final r = meal?.recipe;
    if (plan == null || meal == null || r == null) return const SizedBox(height: 120, child: LoadingView());
    final onList = ref.watch(shoppingListProvider.select((s) => s.meals.contains(meal.key)));
    final heading = '${DateFormat('EE d. MMM', 'de_DE').format(meal.date)} · ${meal.slot.mealLabel}';

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionLabel(heading),
      const SizedBox(height: 10),
      InkWell(
        onTap: () => openRecipe(context, r, portions: meal.portions, date: meal.date, slot: meal.slot),
        child: Row(children: [
          SizedBox(width: 84, height: 84, child: ContentImage(r.thumbnailUrl)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.title, style: VibonoText.cardTitle.copyWith(fontSize: 18)),
              const SizedBox(height: 4),
              _MetaLine(recipe: r, portions: meal.portions),
              const SizedBox(height: 6),
              const Text('REZEPT ANSEHEN ›',
                  style: TextStyle(
                    fontFamily: VibonoFonts.display,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    letterSpacing: 0.5,
                    color: VibonoColors.green700,
                  )),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        const Expanded(child: Text('Portionen', style: VibonoText.body)),
        _StepButton(
          icon: Icons.remove_rounded,
          tooltip: 'Eine Portion weniger',
          onTap: meal.portions <= 1 ? null : () => _save(meal, r.id, meal.portions - 1),
        ),
        SizedBox(
          width: 36,
          child: Text('${meal.portions}', textAlign: TextAlign.center, style: VibonoText.cardTitle.copyWith(fontSize: 18)),
        ),
        _StepButton(
          icon: Icons.add_rounded,
          tooltip: 'Eine Portion mehr',
          onTap: meal.portions >= WeekPlan.maxPortions ? null : () => _save(meal, r.id, meal.portions + 1),
        ),
      ]),
      const SizedBox(height: 14),
      if (!_moving) ...[
        Row(children: [
          Expanded(child: _SheetButton(label: 'Tauschen', icon: Icons.autorenew_rounded, onTap: () => _swap(plan, meal))),
          const SizedBox(width: 8),
          Expanded(
            child: _SheetButton(
              label: 'Verschieben',
              icon: Icons.open_with_rounded,
              onTap: () => setState(() => _moving = true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SheetButton(
              label: 'Entfernen',
              icon: Icons.remove_circle_outline_rounded,
              onTap: () async {
                await savePlannedMeal(ref, meal.date, meal.slot, portions: meal.portions);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ),
        ]),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () async {
            final list = ref.read(shoppingListProvider.notifier);
            if (onList) {
              await list.removeMeal(meal.key);
            } else {
              await list.addMeals([meal.key]);
            }
            if (context.mounted) {
              showMessage(context, onList ? 'Von der Einkaufsliste genommen.' : 'Zutaten stehen auf der Einkaufsliste.');
            }
          },
          icon: Icon(onList ? Icons.remove_shopping_cart_outlined : Icons.add_shopping_cart_rounded, size: 20),
          label: Text(onList ? 'VON DER EINKAUFSLISTE NEHMEN' : 'ZUTATEN AUF DIE EINKAUFSLISTE'),
        ),
      ] else
        ..._moveControls(plan, meal),
    ]);
  }

  List<Widget> _moveControls(PlanResolver plan, PlannedMeal meal) {
    final monday = WeekPlan.mondayOf(meal.date);
    final today = CoachingPlan.dateOnly(DateTime.now());
    final target = plan.meal(_moveDay, _moveSlot);
    final same = _moveDay == meal.date && _moveSlot == meal.slot;
    return [
      const SectionLabel('Verschieben auf'),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var i = 0; i < 7; i++)
          if (!monday.add(Duration(days: i)).isBefore(today))
            ChoiceChip(
              label: Text(DateFormat('EE d.', 'de_DE').format(monday.add(Duration(days: i)))),
              selected: _moveDay == monday.add(Duration(days: i)),
              onSelected: (_) => setState(() => _moveDay = monday.add(Duration(days: i))),
            ),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 6, children: [
        for (final s in MealSlot.values)
          ChoiceChip(label: Text(s.mealLabel), selected: _moveSlot == s, onSelected: (_) => setState(() => _moveSlot = s)),
      ]),
      const SizedBox(height: 8),
      Text(
        same
            ? 'Wähle einen anderen Tag oder eine andere Mahlzeit.'
            : target.isEmpty
                ? 'Der Platz ist frei.'
                : 'Dort steht „${target.recipe!.title}“. Die beiden Gerichte tauschen den Platz.',
        style: VibonoText.small,
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => setState(() => _moving = false), child: const Text('ZURÜCK'))),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: same
                ? null
                : () async {
                    await savePlannedMeal(ref, target.date, target.slot,
                        recipeId: meal.recipe!.id, portions: meal.portions);
                    await savePlannedMeal(ref, meal.date, meal.slot,
                        recipeId: target.recipe?.id, portions: target.portions);
                    if (mounted) Navigator.pop(context);
                  },
            child: const Text('VERSCHIEBEN'),
          ),
        ),
      ]),
    ];
  }

  Future<void> _save(PlannedMeal meal, int recipeId, int portions) =>
      savePlannedMeal(ref, meal.date, meal.slot, recipeId: recipeId, portions: portions);

  Future<void> _swap(PlanResolver plan, PlannedMeal meal) async {
    final alt = plan.alternative(meal);
    if (alt == null) {
      showMessage(context, 'Kein anderes passendes Rezept gefunden.');
      return;
    }
    await _save(meal, alt.id, meal.portions);
  }
}

/// Aktion im Mahlzeit-Blatt: Symbol über kurzer Beschriftung, quadratisch
/// umrandet, damit drei nebeneinander auch auf kleinen Telefonen passen.
class _SheetButton extends StatelessWidget {
  const _SheetButton({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: const RoundedRectangleBorder(side: BorderSide(color: VibonoColors.grey200)),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(children: [
              Icon(icon, size: 22, color: VibonoColors.green700),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: VibonoFonts.display,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    letterSpacing: 0.6,
                    color: VibonoColors.grey,
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        style: IconButton.styleFrom(
          side: BorderSide(color: onTap == null ? VibonoColors.grey200 : VibonoColors.green, width: 1.5),
          foregroundColor: VibonoColors.green700,
        ),
        icon: Icon(icon, size: 20),
      );
}

class _RecipeChooser extends ConsumerWidget {
  const _RecipeChooser({required this.date, required this.slot, required this.portions});
  final DateTime date;
  final MealSlot slot;
  final int portions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(planResolverProvider);
    if (plan == null) return const SizedBox(height: 120, child: LoadingView());
    final list = plan.candidates(date, slot);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionLabel('${slot.mealLabel} aussuchen'),
        const SizedBox(height: 8),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = list[i];
              return InkWell(
                onTap: () async {
                  await savePlannedMeal(ref, date, slot, recipeId: r.id, portions: portions);
                  if (context.mounted) Navigator.pop(context);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    SizedBox(width: 52, height: 52, child: ContentImage(r.thumbnailUrl)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(r.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: VibonoText.body.copyWith(color: VibonoColors.grey900)),
                    ),
                    if (r.energyDensity != null) ...[
                      const SizedBox(width: 8),
                      Text(EnergyDensity.format(r.energyDensity!, digits: 1), style: VibonoText.small),
                      const SizedBox(width: 4),
                      AmpelDot(r.energyDensity!),
                    ],
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
