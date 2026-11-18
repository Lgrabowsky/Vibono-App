import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/api/api_exception.dart';
import '../../data/models/coaching_day.dart';
import '../../data/models/content.dart';
import '../../data/models/sync_item.dart';
import '../../data/sync/sync_repository.dart';
import '../../domain/coaching_plan.dart';
import '../../domain/energy_density.dart';
import '../../domain/recipe_picker.dart';
import '../../state/day_checks.dart';
import '../../state/meal_plan.dart';
import '../../state/providers.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import '../navigation.dart';
import '../widgets/ampel.dart';
import '../widgets/common.dart';
import '../widgets/day_sheets.dart';
import '../widgets/onboarding_prompt.dart';
import '../widgets/streak.dart';
import 'coaching_screen.dart' show lessonKindLabel;
import 'points_screen.dart';
import 'tips_screen.dart';
import 'weekplan_screen.dart';

/// Startbildschirm „Heute“ (Variante B, „Mein Tag als Pfad“): der Tag als
/// Abfolge von Schritten ohne Uhrzeiten, der nächste offene Schritt ist
/// hervorgehoben. Darunter Tipp des Tages und Vibono-Tipp.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDateProvider);
    final day = ref.watch(coachingDayProvider(date));
    return SafeArea(
      bottom: false,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 16, 0),
          child: Row(children: [
            const VibonoLogo(height: 22),
            const Spacer(),
            PointsChip(
              points: ref.watch(pointsBalanceProvider) ?? day.value?.pointsBalance ?? 0,
              onTap: () => push(context, const PointsScreen()),
            ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            color: VibonoColors.green,
            onRefresh: () async {
              await ref.read(syncProvider).sync();
              ref.invalidate(coachingDayProvider(date));
              await ref.read(coachingDayProvider(date).future);
            },
            child: switch (day) {
              AsyncData(:final value) => _DayView(day: value, date: date),
              AsyncError(:final error) => ListView(children: [
                  const SizedBox(height: 80),
                  ErrorRetry(
                    message: error is ApiException ? error.userMessage : 'Der Tag konnte nicht geladen werden.',
                    onRetry: () => ref.invalidate(coachingDayProvider(date)),
                  ),
                ]),
              _ => const LoadingView(),
            },
          ),
        ),
      ]),
    );
  }
}

class _DateNav extends ConsumerWidget {
  const _DateNav({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(selectedDateProvider.notifier);
    Widget arrow(IconData icon, String label, VoidCallback onTap) => IconButton(
          tooltip: label,
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 22, color: VibonoColors.grey),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      arrow(Icons.chevron_left_rounded, 'Vorheriger Tag', n.previous),
      GestureDetector(
        onTap: n.today,
        child: Text(
          DateFormat('EE, d. MMMM', 'de_DE').format(date).replaceAll('.,', ',').toUpperCase(),
          style: const TextStyle(
            fontFamily: VibonoFonts.display,
            fontSize: 14,
            letterSpacing: 1.1,
            color: VibonoColors.grey,
          ),
        ),
      ),
      arrow(Icons.chevron_right_rounded, 'Nächster Tag', n.next),
    ]);
  }
}

/// Ein Schritt im Tagespfad.
class _Step {
  const _Step({
    required this.title,
    required this.subtitle,
    required this.done,
    required this.onOpen,
    this.doneTitle,
    this.focusTitle,
    this.focusMeta,
    this.action,
    this.onAction,
    this.onToggle,
    this.thumb,
    this.icon,
    this.density,
  });

  final String title;
  final String subtitle;
  final bool done;
  final VoidCallback onOpen;
  final String? doneTitle;

  /// Text und Knopf, wenn der Schritt „Jetzt dran“ ist.
  final String? focusTitle;
  final String? focusMeta;
  final String? action;
  final VoidCallback? onAction;

  /// Abhaken direkt am Kreis (Mahlzeiten).
  final VoidCallback? onToggle;
  final String? thumb;
  final IconData? icon;
  final double? density;
}

class _DayView extends ConsumerWidget {
  const _DayView({required this.day, required this.date});
  final CoachingDay day;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final sync = ref.watch(syncProvider);
    final checks = ref.watch(dayChecksProvider(dayKey(date)));
    final plan = ref.watch(planResolverProvider);
    final today = CoachingPlan.dateOnly(DateTime.now());
    final rel = CoachingPlan.daysBetween(today, date);
    final dk = dayKey(date);
    final canCheck = rel <= 0;

    bool isDone(ContentItem i) {
      if (i.id > 0) return sync.has(SyncCollection.lessonsDone, '${i.id}');
      if (i.tags.contains('task:gewicht')) return sync.has(SyncCollection.weight, dk);
      if (i.tags.contains('task:einkaufen')) return checks.contains('einkaufen');
      return false;
    }

    final greeting = switch (rel) {
      0 => '${_hello()}, ${session.me?.firstName ?? ''}!'.replaceAll(', !', '!'),
      1 => 'Vorschau auf morgen',
      -1 => 'Rückblick auf gestern',
      > 1 => 'Vorschau',
      _ => 'Rückblick',
    };

    final essen = day.essen.firstOrNull;
    final bewegung = day.bewegung.firstOrNull;
    final targetMin = int.tryParse(
            bewegung?.tags.firstWhere((t) => t.startsWith('task:bewegung:'), orElse: () => '').split(':').last ?? '') ??
        20;
    final doneMin = sportMinutes(sync.items(SyncCollection.sport), dk);

    // Mahlzeiten wie im Wochenplan, damit beide Ansichten übereinstimmen.
    final household = session.profile.householdSize;
    final meals = <(MealSlot, ContentItem, int)>[
      if (plan != null)
        for (final m in plan.day(date))
          if (m.recipe != null) (m.slot, m.recipe!, m.portions)
      else
        for (var i = 0; i < day.recipes.length && i < 3; i++) (MealSlot.values[i], day.recipes[i], household),
    ];

    _Step meal(MealSlot slot, ContentItem r, int portions) {
      final id = 'meal:${slot.wire}';
      void toggle() => ref.read(dayChecksProvider(dk).notifier).toggle(id);
      return _Step(
        title: slot.mealLabel,
        subtitle: r.title,
        done: checks.contains(id),
        thumb: r.thumbnailUrl,
        density: r.energyDensity,
        onOpen: () => openRecipe(context, r, portions: portions, date: date, slot: slot),
        onToggle: canCheck ? toggle : null,
        focusTitle: '${slot.mealLabel}: ${r.title}',
        focusMeta: r.energyDensity == null ? null : 'Energiedichte ${EnergyDensity.format(r.energyDensity!, digits: 1)}',
        action: 'Gegessen',
        onAction: toggle,
      );
    }

    _Step task(ContentItem t) {
      final isLesson = t.id > 0;
      final weight = t.tags.contains('task:gewicht');
      final shop = t.tags.contains('task:einkaufen');
      return _Step(
        title: isLesson ? t.title : t.title,
        subtitle: isLesson
            ? '${lessonKindLabel(t.lessonKind)} · ${t.readingMinutes ?? 3} Min.'
            : t.excerpt,
        done: isDone(t),
        doneTitle: weight ? 'Gewicht eingetragen' : null,
        icon: isLesson ? Icons.menu_book_outlined : (weight ? Icons.monitor_weight_outlined : Icons.shopping_basket_outlined),
        onOpen: () => _openTask(context, ref, t),
        focusTitle: isLesson ? 'Lies „${t.title}“' : t.title,
        focusMeta: isLesson
            ? [
                '${t.readingMinutes ?? 3} Min.',
                if (t.pointsForReading > 0) '+${t.pointsForReading} Punkte',
              ].join(' · ')
            : t.excerpt,
        action: isLesson ? 'Lesen' : (shop ? 'Liste' : 'Eintragen'),
        onAction: () => _openTask(context, ref, t),
        // Abhaken in beliebiger Reihenfolge. Das Gewicht braucht einen Wert,
        // dafür öffnet sich das Eingabeblatt.
        onToggle: !canCheck
            ? null
            : isLesson
                ? () => sync.toggle(SyncCollection.lessonsDone, '${t.id}', {'post_id': t.id})
                : shop
                    ? () => ref.read(dayChecksProvider(dk).notifier).toggle('einkaufen')
                    : () => _openTask(context, ref, t),
      );
    }

    final weightTask = day.sonstiges.where((s) => s.tags.contains('task:gewicht')).firstOrNull;
    final otherTasks = day.sonstiges.where((s) => !s.tags.contains('task:gewicht'));
    _Step? mealFor(MealSlot s) => meals.where((m) => m.$1 == s).map((m) => meal(m.$1, m.$2, m.$3)).firstOrNull;

    // Reihenfolge eines Tages, ohne Uhrzeiten.
    final steps = <_Step>[
      if (weightTask != null) task(weightTask),
      ?mealFor(MealSlot.fruehstueck),
      for (final w in day.wissen) task(w),
      for (final t in otherTasks) task(t),
      ?mealFor(MealSlot.mittag),
      if (bewegung != null)
        _Step(
          title: bewegung.title,
          subtitle: doneMin > 0 ? '$doneMin von $targetMin Min.' : bewegung.excerpt,
          done: doneMin >= targetMin,
          icon: Icons.directions_walk_rounded,
          onOpen: () => showVibonoSheet(context, SportSheet(date: date, target: targetMin)),
          focusTitle: bewegung.title,
          focusMeta: doneMin > 0 ? 'Schon $doneMin von $targetMin Min.' : bewegung.excerpt,
          action: 'Eintragen',
          onAction: () => showVibonoSheet(context, SportSheet(date: date, target: targetMin)),
          onToggle: canCheck ? () => _toggleSport(context, sync, dk, doneMin, targetMin) : null,
        ),
      ?mealFor(MealSlot.abend),
    ];
    final streak = ref.watch(appStreakProvider) ?? day.streak;
    final doneCount = steps.where((s) => s.done).length;
    final focus = rel == 0 ? steps.indexWhere((s) => !s.done) : -1;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Transform.translate(offset: const Offset(-12, 0), child: _DateNav(date: date)),
              Text(
                greeting.toUpperCase(),
                maxLines: 2,
                style: const TextStyle(
                  fontFamily: VibonoFonts.display,
                  fontWeight: FontWeight.w300,
                  fontSize: 28,
                  height: 1.15,
                  letterSpacing: 1,
                  color: VibonoColors.green,
                ),
              ),
              const SizedBox(height: 4),
              Text(_phaseLine(day.phase), style: VibonoText.small),
            ]),
          ),
          const SizedBox(width: 12),
          _DayRing(done: doneCount, total: steps.length),
        ]),
        if (rel == 0) ...[const SizedBox(height: 16), const OnboardingPrompt()],
        if (rel == 0 && streak.enabled) ...[
          const SizedBox(height: 14),
          StreakCard(streak: streak, onTap: () => push(context, const PointsScreen())),
        ],
        const SizedBox(height: 22),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          const Expanded(
            child: Text(
              'DEIN TAG',
              style: TextStyle(
                fontFamily: VibonoFonts.display,
                fontWeight: FontWeight.w300,
                fontSize: 20,
                letterSpacing: 0.8,
                color: VibonoColors.grey,
              ),
            ),
          ),
          InkWell(
            onTap: () => ref.read(tabIndexProvider.notifier).go(Tabs.wochenplan),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('WOCHENPLAN ›', style: _linkStyle),
            ),
          ),
        ]),
        if (essen != null) ...[
          const SizedBox(height: 2),
          Text('Essen heute: ${essen.title} · ${essen.excerpt}', style: VibonoText.small),
        ],
        const SizedBox(height: 8),
        for (var i = 0; i < steps.length; i++)
          _StepRow(
            step: steps[i],
            focus: i == focus,
            first: i == 0,
            last: false,
          ),
        _StepRow.finish(
          done: steps.isNotEmpty && doneCount == steps.length,
          label: rel > 0 ? 'Vorschau: so sieht dein Tag aus' : null,
        ),
        const SizedBox(height: 22),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (day.tipOfTheDay.isNotEmpty) Expanded(child: _TipOfDayTile(text: day.tipOfTheDay)),
            if (day.tipOfTheDay.isNotEmpty && day.vibonoTip != null) const SizedBox(width: 12),
            if (day.vibonoTip != null)
              Expanded(child: _VibonoTipTile(tip: day.vibonoTip!, onTap: () => openContent(context, day.vibonoTip!))),
          ]),
        ),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton(
            onPressed: () => ref.read(tabIndexProvider.notifier).go(Tabs.rezepte),
            child: const Text('MEHR REZEPTE ›', style: _linkStyle),
          ),
          const SizedBox(width: 16),
          TextButton(
            onPressed: () => push(context, const TipsScreen()),
            child: const Text('MEHR TIPPS ›', style: _linkStyle),
          ),
        ]),
      ],
    );
  }

  static const _linkStyle = TextStyle(
    fontFamily: VibonoFonts.display,
    fontWeight: FontWeight.w600,
    fontSize: 14,
    letterSpacing: 1,
    color: VibonoColors.green600,
  );

  static String _phaseLine(Phase p) => switch (p.key) {
        PhaseKey.vorbereitung => 'Vorbereitung · ${p.dayLabel}',
        PhaseKey.phase1 => 'Phase 1 · ${p.dayLabel} von ${CoachingPlan.utDays}',
        PhaseKey.phase2 => 'Phase 2 · Tag ${p.dayInPhase} von ${CoachingPlan.phase2Days} · Gewohnheiten ändern',
        PhaseKey.phase3 => 'Phase 3 · ${p.dayLabel} · Satt essen & genießen',
      };

  /// Bewegung per Kreis abhaken: trägt die fehlenden Minuten ein, ein
  /// zweiter Tipp nimmt genau diesen Eintrag wieder heraus.
  void _toggleSport(BuildContext context, SyncRepository sync, String dk, int done, int target) {
    final key = 'app-quick-$dk';
    if (sync.has(SyncCollection.sport, key)) {
      sync.remove(SyncCollection.sport, key);
    } else if (done < target) {
      sync.upsert(SyncCollection.sport, key, {'date': dk, 'activity': 'gehen', 'minutes': target - done});
    } else {
      showVibonoSheet(context, SportSheet(date: date, target: target));
    }
  }

  static String _hello() {
    final h = DateTime.now().hour;
    if (h < 11) return 'Guten Morgen';
    if (h < 18) return 'Hallo';
    return 'Guten Abend';
  }

  void _openTask(BuildContext context, WidgetRef ref, ContentItem item) {
    if (item.id > 0) {
      openContent(context, item);
    } else if (item.tags.contains('task:gewicht')) {
      showVibonoSheet(context, WeightSheet(date: date));
    } else if (item.tags.contains('task:einkaufen')) {
      push(
        context,
        ShoppingListScreen(
          fillDays: 4,
          basics: true,
          onDone: () => ref.read(dayChecksProvider(dayKey(date)).notifier).toggle('einkaufen'),
        ),
      );
    }
  }
}

/// Fortschrittsring „2/6 erledigt“.
class _DayRing extends StatelessWidget {
  const _DayRing({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$done von $total erledigt',
        child: SizedBox(
          width: 72,
          height: 72,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: total == 0 ? 0 : done / total),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => CircularProgressIndicator(
                  value: v,
                  strokeWidth: 6,
                  color: VibonoColors.green,
                  backgroundColor: VibonoColors.green100,
                ),
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$done/$total',
                  style: const TextStyle(
                    fontFamily: VibonoFonts.display,
                    fontSize: 20,
                    height: 1,
                    color: VibonoColors.grey900,
                  )),
              const Text('erledigt', style: TextStyle(fontFamily: VibonoFonts.body, fontSize: 10, color: VibonoColors.grey500)),
            ]),
          ]),
        ),
      );
}

/// Zeile im Tagespfad: Knoten links auf einer durchgehenden Linie.
class _StepRow extends StatelessWidget {
  const _StepRow({required _Step this.step, required this.focus, required this.first, required this.last})
      : finishDone = false,
        finishLabel = null;

  const _StepRow.finish({required bool done, String? label})
      : step = null,
        focus = false,
        first = false,
        last = true,
        finishDone = done,
        finishLabel = label;

  final _Step? step;
  final bool focus;
  final bool first;
  final bool last;
  final bool finishDone;
  final String? finishLabel;

  @override
  Widget build(BuildContext context) {
    final s = step;
    final Widget node;
    final Widget content;
    if (s == null) {
      node = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: finishDone ? VibonoColors.green : Colors.white,
          border: finishDone ? null : Border.all(color: VibonoColors.grey300, width: 2),
        ),
        alignment: Alignment.center,
        child: finishDone
            ? const VibonoV(size: 13, color: Colors.white)
            : const Icon(Icons.flag_outlined, size: 14, color: VibonoColors.grey400),
      );
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          finishLabel ?? (finishDone ? 'Tag geschafft. Stark!' : 'Tag geschafft, wenn alles erledigt ist'),
          style: VibonoText.small.copyWith(
            fontSize: 13,
            color: finishDone ? VibonoColors.green700 : VibonoColors.grey500,
            fontWeight: finishDone ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      );
    } else if (focus) {
      final ring = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: VibonoColors.green, width: 3),
        ),
        alignment: Alignment.center,
        child: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(color: VibonoColors.green, shape: BoxShape.circle),
        ),
      );
      node = Padding(
        padding: const EdgeInsets.only(top: 6),
        child: s.onToggle == null
            ? Padding(padding: const EdgeInsets.all(10), child: ring)
            : Semantics(
                button: true,
                label: '${s.title} abhaken',
                child: InkResponse(
                  onTap: s.onToggle,
                  radius: 24,
                  child: Padding(padding: const EdgeInsets.all(10), child: ring),
                ),
              ),
      );
      content = _FocusCard(step: s);
    } else {
      node = s.done
          ? CheckCircle(checked: true, size: 28, onTap: s.onToggle, label: '${s.title} erledigt')
          : (s.onToggle != null
              ? CheckCircle(checked: false, size: 28, onTap: s.onToggle, label: '${s.title} abhaken')
              : Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: VibonoColors.grey300, width: 2),
                  ),
                ));
      content = InkWell(
        onTap: s.onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(
              width: 48,
              height: 40,
              child: s.thumb != null
                  ? Opacity(opacity: s.done ? 0.75 : 1, child: ContentImage(s.thumb))
                  : ColoredBox(
                      color: VibonoColors.green050,
                      child: Icon(s.icon ?? Icons.check_rounded, size: 20, color: VibonoColors.green700),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  s.done ? (s.doneTitle ?? s.title) : s.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: VibonoText.body.copyWith(
                    color: s.done ? VibonoColors.grey500 : VibonoColors.grey900,
                    height: 1.3,
                  ),
                ),
                Text(
                  s.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VibonoText.small.copyWith(color: s.done ? VibonoColors.grey400 : VibonoColors.grey500),
                ),
              ]),
            ),
            if (s.density != null) ...[
              const SizedBox(width: 8),
              AmpelDot(s.density!),
              const SizedBox(width: 5),
              Text(EnergyDensity.format(s.density!, digits: 1), style: VibonoText.small.copyWith(color: VibonoColors.grey)),
            ],
          ]),
        ),
      );
    }

    // Kreis links: mit Abhak-Fläche 48 px, sonst 28 px plus Rand.
    final hasTapNode = s != null && (focus || s.onToggle != null);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 48,
          child: Stack(alignment: Alignment.topCenter, children: [
            Positioned(
              top: first ? 24 : 0,
              bottom: last ? null : 0,
              height: last ? 24 : null,
              child: Container(width: 2, color: VibonoColors.grey200),
            ),
            Padding(
              padding: EdgeInsets.only(top: hasTapNode ? 0 : 10),
              child: node,
            ),
          ]),
        ),
        const SizedBox(width: 6),
        Expanded(child: Padding(padding: EdgeInsets.only(top: focus ? 6 : 0, bottom: focus ? 6 : 0), child: content)),
      ]),
    );
  }
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.step});
  final _Step step;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          color: VibonoColors.green,
          boxShadow: [BoxShadow(color: Color(0x1F1C1C1C), blurRadius: 10, offset: Offset(0, 2))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: step.onOpen,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SectionLabel('Jetzt dran', color: Colors.white),
                const SizedBox(height: 6),
                Text(
                  step.focusTitle ?? step.title,
                  style: VibonoText.body.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: Text(step.focusMeta ?? '',
                        style: VibonoText.small.copyWith(color: Colors.white.withValues(alpha: 0.95))),
                  ),
                  if (step.action != null)
                    Material(
                      color: Colors.white,
                      shape: const StadiumBorder(),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: step.onAction ?? step.onOpen,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                          child: Text(
                            step.action!.toUpperCase(),
                            style: const TextStyle(
                              fontFamily: VibonoFonts.display,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              letterSpacing: 1,
                              color: Color(0xFF6A871F),
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
              ]),
            ),
          ),
        ),
      );
}

class _TipOfDayTile extends StatelessWidget {
  const _TipOfDayTile({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        color: VibonoColors.green050,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lightbulb_outline_rounded, size: 20, color: VibonoColors.green700),
          const SizedBox(height: 8),
          const Text('TIPP DES TAGES', style: _tileLabel),
          const SizedBox(height: 6),
          Text(text, style: VibonoText.small.copyWith(fontSize: 13, height: 1.5, color: VibonoColors.grey900)),
        ]),
      );
}

class _VibonoTipTile extends StatelessWidget {
  const _VibonoTipTile({required this.tip, required this.onTap});
  final ContentItem tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Color(0x1F1C1C1C), blurRadius: 10, offset: Offset(0, 2))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(height: 64, child: ContentImage(tip.thumbnailUrl)),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('VIBONO-TIPP', style: _tileLabel),
                  const SizedBox(height: 4),
                  Text(tip.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: VibonoText.small.copyWith(fontSize: 13, height: 1.4, color: VibonoColors.grey900)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

const _tileLabel = TextStyle(
  fontFamily: VibonoFonts.display,
  fontWeight: FontWeight.w600,
  fontSize: 12,
  letterSpacing: 1,
  color: Color(0xFF6A871F),
);
