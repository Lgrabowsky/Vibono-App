import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/coaching_day.dart';
import '../../data/models/content.dart';
import '../../data/models/sync_item.dart';
import '../../domain/coaching_plan.dart';
import '../../state/providers.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import '../navigation.dart';
import '../widgets/common.dart';
import '../widgets/phase_bar.dart';
import 'weight_screen.dart';

/// „Mein Coaching“: alle Kurse und Lektionen, synchron mit vibono.de.
class CoachingScreen extends ConsumerStatefulWidget {
  const CoachingScreen({super.key});

  @override
  ConsumerState<CoachingScreen> createState() => _CoachingScreenState();
}

class _CoachingScreenState extends ConsumerState<CoachingScreen> {
  String _kind = 'alle';
  bool _hideDone = false;

  static const _kinds = {
    'alle': 'Alle',
    'wichtig': 'Wichtig',
    'lesen': 'Wissen',
    'motivation': 'Motivation',
    'aufgaben': 'Aufgaben',
    'rezepte': 'Rezepte',
    'probleme': 'Probleme',
  };

  static const _phaseCourses = {
    PhaseKey.vorbereitung: [247, 248, 249, 219],
    PhaseKey.phase1: [220, 251, 250, 252],
    PhaseKey.phase2: [253, 221, 254, 256, 255],
    PhaseKey.phase3: [222, 257, 258, 260, 261],
  };

  @override
  Widget build(BuildContext context) {
    final today = CoachingPlan.dateOnly(DateTime.now());
    final day = ref.watch(coachingDayProvider(today)).value;
    final courses = ref.watch(coursesProvider);
    final sync = ref.watch(syncProvider);
    final current = day == null ? const <int>[] : _phaseCourses[day.phase.key] ?? const <int>[];

    return SafeArea(
      bottom: false,
      child: switch (courses) {
        AsyncData(:final value) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              const Text('MEIN COACHING', style: VibonoText.screenTitle),
              const SizedBox(height: 10),
              if (day != null) ...[
                Text(day.phase.label, style: VibonoText.cardTitle.copyWith(fontSize: 18)),
                Text(day.phase.dayLabel, style: VibonoText.small),
                const SizedBox(height: 10),
                PhaseBar(phase: day.phase, progress: day.phaseProgress),
                const SizedBox(height: 14),
                _Milestones(day: day),
                const SizedBox(height: 16),
              ],
              SizedBox(
                height: 40,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final k in _kinds.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(k.value),
                        selected: _kind == k.key,
                        onSelected: (_) => setState(() => _kind = k.key),
                      ),
                    ),
                ]),
              ),
              SwitchListTile(
                value: _hideDone,
                onChanged: (v) => setState(() => _hideDone = v),
                title: const Text('Erledigte Lektionen ausblenden', style: VibonoText.body),
                activeThumbColor: VibonoColors.green,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              // Kurse der aktuellen Phase zuerst, in ihrer Reihenfolge.
              for (final c in [
                for (final id in current) ...value.where((c) => c.id == id),
                ...value.where((c) => !current.contains(c.id)),
              ])
                _course(context, c, sync.has, current.contains(c.id)),
            ],
          ),
        AsyncError() => ErrorRetry(
            message: 'Coaching-Inhalte konnten nicht geladen werden.', onRetry: () => ref.invalidate(coursesProvider)),
        _ => const LoadingView(),
      },
    );
  }

  Widget _course(BuildContext context, Course c, bool Function(SyncCollection, String) has, bool isCurrent) {
    final sync = ref.read(syncProvider);
    bool done(ContentItem l) => has(SyncCollection.lessonsDone, '${l.id}');
    final lessons = c.lessons
        .where((l) => _kind == 'alle' || l.lessonKind == _kind)
        .where((l) => !_hideDone || !done(l))
        .toList();
    if (lessons.isEmpty) return const SizedBox.shrink();
    final total = c.lessons.length;
    final finished = c.lessons.where(done).length;
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: isCurrent ? VibonoColors.green : VibonoColors.grey200, width: isCurrent ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: isCurrent,
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: VibonoColors.green,
        title: Text(_title(c.title), style: VibonoText.cardTitle),
        subtitle: Text(
          isCurrent ? 'Dein aktueller Kurs · $finished von $total erledigt' : '$finished von $total erledigt',
          style: VibonoText.small.copyWith(color: isCurrent ? VibonoColors.green700 : null),
        ),
        leading: SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(
            value: total == 0 ? 0 : finished / total,
            backgroundColor: VibonoColors.grey100,
            strokeWidth: 4,
          ),
        ),
        children: [
          for (final l in lessons)
            ListTile(
              dense: true,
              leading: Checkbox(
                value: done(l),
                activeColor: VibonoColors.green,
                onChanged: (_) => sync.toggle(SyncCollection.lessonsDone, '${l.id}', {'post_id': l.id}),
              ),
              title: Text(
                l.title,
                style: VibonoText.body.copyWith(
                  color: done(l) ? VibonoColors.grey400 : VibonoColors.grey800,
                  decoration: done(l) ? TextDecoration.lineThrough : null,
                ),
              ),
              trailing: Icon(_icon(l.lessonKind), size: 18, color: VibonoColors.green),
              onTap: () => openContent(context, l),
            ),
        ],
      ),
    );
  }

  static String _title(String t) {
    // Kursnamen stehen auf der Website teils in Großbuchstaben.
    if (t != t.toUpperCase()) return t;
    String cap(String w) {
      final i = w.indexOf(RegExp('[A-ZÄÖÜ]'));
      if (i < 0 || w == 'UT') return w;
      return w.substring(0, i + 1) + w.substring(i + 1).toLowerCase();
    }
    return t.split(' ').map(cap).join(' ');
  }

  static IconData _icon(String? kind) => switch (kind) {
        'wichtig' => Icons.star_rounded,
        'lesen' => Icons.menu_book_rounded,
        'motivation' => Icons.favorite_rounded,
        'aufgaben' => Icons.priority_high_rounded,
        'rezepte' => Icons.restaurant_rounded,
        'probleme' => Icons.help_outline_rounded,
        'hinweise' => Icons.info_outline_rounded,
        _ => Icons.circle_outlined,
      };
}

class _Milestones extends ConsumerWidget {
  const _Milestones({required this.day});
  final CoachingDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(sessionProvider).profile;
    final targets = [p.target3m, p.target6m, p.target12m];
    if (targets.every((t) => t == null)) return const SizedBox.shrink();
    return InkWell(
      onTap: () => push(context, const WeightScreen()),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: VibonoColors.grey200), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Column(children: [
                Text(const ['3 Monate', '6 Monate', '12 Monate'][i], style: VibonoText.small),
                Text(
                  targets[i] == null ? '–' : '${targets[i]!.toStringAsFixed(1).replaceAll('.', ',').replaceAll(',0', '')} kg',
                  style: const TextStyle(
                    fontFamily: VibonoFonts.display,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: VibonoColors.green700,
                  ),
                ),
                if (i < day.milestones.length)
                  Text(DateFormat('MMM yyyy', 'de_DE').format(day.milestones[i].date), style: VibonoText.small),
              ]),
            ),
        ]),
      ),
    );
  }
}
