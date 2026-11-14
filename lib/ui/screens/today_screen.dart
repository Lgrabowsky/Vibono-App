import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/api/api_exception.dart';
import '../../data/models/coaching_day.dart';
import '../../data/models/content.dart';
import '../../data/models/json.dart';
import '../../data/models/sync_item.dart';
import '../../data/sync/sync_repository.dart';
import '../../domain/coaching_plan.dart';
import '../../state/day_checks.dart';
import '../../state/providers.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import '../navigation.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/day_sheets.dart';
import '../widgets/phase_bar.dart';
import 'points_screen.dart';
import 'tips_screen.dart';
import 'weekplan_screen.dart';

/// Startbildschirm „Heute“ (Entwurf Variante A): alles Wichtige des
/// Coaching-Tages auf einen Blick, ohne Uhrzeiten.
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
          padding: const EdgeInsets.fromLTRB(16, 8, 10, 0),
          child: Row(children: [
            const VibonoLogo(height: 20),
            const Spacer(),
            _DateNav(date: date),
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
    final text = DateFormat('EE, d. MMM', 'de_DE').format(date);
    Widget arrow(IconData icon, String label, VoidCallback onTap) => Semantics(
          button: true,
          label: label,
          child: InkResponse(
            onTap: onTap,
            radius: 22,
            child: Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(color: VibonoColors.grey100, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: VibonoColors.grey),
            ),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      arrow(Icons.chevron_left_rounded, 'Vorheriger Tag', n.previous),
      GestureDetector(
        onTap: n.today,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(text,
              style: const TextStyle(
                fontFamily: VibonoFonts.display,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: VibonoColors.grey,
              )),
        ),
      ),
      arrow(Icons.chevron_right_rounded, 'Nächster Tag', n.next),
    ]);
  }
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
    final balance = ref.watch(pointsBalanceProvider) ?? day.pointsBalance;
    final today = CoachingPlan.dateOnly(DateTime.now());
    final rel = CoachingPlan.daysBetween(today, date);
    final dk = dayKey(date);

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

    // „Als Nächstes“: der erste offene Schritt des Tages.
    final candidates = <ContentItem>[
      ?day.nextStep,
      ...day.wissen,
      ...day.sonstiges,
    ];
    final next = candidates.where((c) => !isDone(c)).firstOrNull;

    final essen = day.essen.firstOrNull;
    final bewegung = day.bewegung.firstOrNull;
    final wissen = day.wissen.firstOrNull;
    final wichtig = day.sonstiges.where((s) => !isDone(s)).firstOrNull ?? day.sonstiges.firstOrNull;
    final meals = checks.where((c) => c.startsWith('meal:')).length;
    final targetMin = int.tryParse(
            bewegung?.tags.firstWhere((t) => t.startsWith('task:bewegung:'), orElse: () => '').split(':').last ?? '') ??
        20;
    final doneMin = sportMinutes(sync.items(SyncCollection.sport), dk);

    final favs = {for (final f in sync.items(SyncCollection.favorites)) f.key};

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: Text(greeting, style: VibonoText.hello, maxLines: 2)),
          PointsChip(points: balance, onTap: () => push(context, const PointsScreen())),
        ]),
        const SizedBox(height: 10),
        PhaseBar(phase: day.phase, progress: day.phaseProgress),
        const SizedBox(height: 12),
        _nextCard(context, ref, next, rel),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.55,
          children: [
            if (essen != null)
              DayTile(
                kind: 'Essen',
                title: essen.title,
                status: meals == 0 ? essen.excerpt : '$meals von 3 Mahlzeiten satt',
                done: meals >= 3,
                onTap: () => showVibonoSheet(context, MealsSheet(date: date, rule: essenRule(day.phase.key))),
              ),
            if (bewegung != null)
              DayTile(
                kind: 'Bewegung',
                title: bewegung.title,
                status: '$doneMin von $targetMin Min.',
                done: doneMin >= targetMin,
                onTap: () => showVibonoSheet(context, SportSheet(date: date, target: targetMin)),
              ),
            if (wissen != null)
              DayTile(
                kind: 'Wissen',
                title: wissen.title,
                status: isDone(wissen) ? 'Gelesen' : '${wissen.readingMinutes ?? 3} Min. Lesezeit',
                done: isDone(wissen),
                onTap: () => openContent(context, wissen),
              ),
            if (wichtig != null)
              DayTile(
                kind: 'Wichtig',
                title: wichtig.title,
                status: isDone(wichtig) ? _doneText(wichtig, sync, dk) : wichtig.excerpt,
                done: isDone(wichtig),
                onTap: () => _openTask(context, ref, wichtig),
              ),
          ],
        ),
        const SizedBox(height: 14),
        SectionHeader(
          rel == 0 ? 'Deine Rezepte für heute' : 'Rezepte für ${DateFormat('EEEE', 'de_DE').format(date)}',
          action: 'Wochenplan',
          onAction: () => ref.read(tabIndexProvider.notifier).go(Tabs.wochenplan),
        ),
        const SizedBox(height: 6),
        Row(children: [
          for (var i = 0; i < day.recipes.length && i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: RecipeThumb(
                recipe: day.recipes[i],
                caption: const ['Frühstück', 'Mittag', 'Abend'][i],
                favorite: favs.contains('recipe:${day.recipes[i].id}'),
                onTap: () => openContent(context, day.recipes[i]),
              ),
            ),
          ],
        ]),
        if (day.vibonoTip != null) ...[
          const SizedBox(height: 14),
          TipCard(tip: day.vibonoTip!, onTap: () => openContent(context, day.vibonoTip!)),
        ],
        if (day.tipOfTheDay.isNotEmpty) ...[
          const SizedBox(height: 12),
          TipOfTheDay(text: day.tipOfTheDay),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: () => ref.read(tabIndexProvider.notifier).go(Tabs.rezepte),
              child: const Text('MEHR REZEPTE'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: () => push(context, const TipsScreen()),
              child: const Text('MEHR TIPPS'),
            ),
          ),
        ]),
      ],
    );
  }

  static String _hello() {
    final h = DateTime.now().hour;
    if (h < 11) return 'Guten Morgen';
    if (h < 18) return 'Hallo';
    return 'Guten Abend';
  }

  String _doneText(ContentItem i, SyncRepository sync, String dk) {
    if (i.tags.contains('task:gewicht')) {
      final kg = asDouble(sync.get(SyncCollection.weight, dk)?['kg']);
      return kg == null ? 'Erledigt' : '${kg.toStringAsFixed(1).replaceAll('.', ',')} kg eingetragen';
    }
    return 'Erledigt';
  }

  Widget _nextCard(BuildContext context, WidgetRef ref, ContentItem? next, int rel) {
    if (rel < 0) {
      return NextStepCard(
        soft: true,
        label: 'Rückblick',
        title: next == null ? 'Alles erledigt an diesem Tag' : 'Noch offen: ${next.title}',
        subtitle: 'Mit dem Pfeil rechts geht es zurück zu heute.',
        action: 'Heute',
        onTap: ref.read(selectedDateProvider.notifier).today,
      );
    }
    if (next == null) {
      return NextStepCard(
        label: rel == 0 ? 'Geschafft' : 'Vorschau',
        title: rel == 0 ? 'Alles erledigt für heute!' : 'Alles vorbereitet',
        subtitle: 'Gönn dir ein grünes Rezept oder einen Vibono-Tipp.',
        action: 'Rezepte',
        onTap: () => ref.read(tabIndexProvider.notifier).go(Tabs.rezepte),
      );
    }
    final isLesson = next.id > 0;
    final subtitle = isLesson
        ? [
            '${next.readingMinutes ?? 3} Minuten Lesezeit',
            if (next.pointsForReading > 0) '+${next.pointsForReading} Punkte',
          ].join(' · ')
        : next.excerpt;
    return NextStepCard(
      soft: rel > 0,
      label: rel > 0 ? 'Für morgen vorbereiten' : 'Als Nächstes',
      title: isLesson ? 'Lies „${next.title}“' : next.title,
      subtitle: subtitle,
      action: isLesson ? 'Los' : (next.tags.contains('task:einkaufen') ? 'Liste' : 'Eintragen'),
      onTap: () => _openTask(context, ref, next),
    );
  }

  void _openTask(BuildContext context, WidgetRef ref, ContentItem item) {
    if (item.id > 0) {
      openContent(context, item);
    } else if (item.tags.contains('task:gewicht')) {
      showVibonoSheet(context, WeightSheet(date: date));
    } else if (item.tags.contains('task:einkaufen')) {
      push(context, ShoppingListScreen(onDone: () => ref.read(dayChecksProvider(dayKey(date)).notifier).toggle('einkaufen')));
    }
  }
}
