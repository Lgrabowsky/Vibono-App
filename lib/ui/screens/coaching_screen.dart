import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/coaching_day.dart';
import '../../data/models/content.dart';
import '../../data/models/sync_item.dart';
import '../../domain/coaching_plan.dart';
import '../../domain/coaching_progress.dart';
import '../../state/gamification.dart';
import '../../state/providers.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import '../navigation.dart';
import '../widgets/common.dart';
import '../widgets/day_sheets.dart';
import '../widgets/gamification.dart';
import 'points_screen.dart';
import 'weight_screen.dart';

/// „Mein Coaching“: Lernpfad mit der nächsten Lektion, Level, Leseserie
/// und Abzeichen, dazu alle Kurse (synchron mit vibono.de).
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

  @override
  Widget build(BuildContext context) {
    final courses = ref.watch(coursesProvider);
    final sync = ref.watch(syncProvider);
    final progress = ref.watch(coachingProgressProvider);
    final phaseKey = ref.watch(currentPhaseProvider);
    final profile = ref.watch(sessionProvider).profile;
    final today = CoachingPlan.dateOnly(DateTime.now());
    final phase = CoachingPlan.phaseFor(profile.coachingStartDate ?? today.add(const Duration(days: 1)), today);
    final current = phaseCourseIds[phaseKey] ?? const <int>[];
    bool isDone(ContentItem l) => sync.has(SyncCollection.lessonsDone, '${l.id}');

    return SafeArea(
      bottom: false,
      child: switch (courses) {
        AsyncData(:final value) when progress != null => ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            children: [
              const _Title(),
              const SizedBox(height: 12),
              _Hero(progress: progress, points: ref.watch(pointsBalanceProvider)),
              const SizedBox(height: 24),
              _LearningPath(
                next: CoachingProgress.nextLesson(value, isDone, current),
                isDone: isDone,
              ),
              const SizedBox(height: 24),
              _Badges(progress: progress),
              const SizedBox(height: 24),
              _PhaseSteps(phase: phase),
              const SizedBox(height: 12),
              const _Milestones(),
              const SizedBox(height: 28),
              const SectionLabel('Alle Kurse'),
              const SizedBox(height: 8),
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
                title: const Text('Gelesene Lektionen ausblenden', style: VibonoText.body),
                activeThumbColor: VibonoColors.green,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              // Kurse der aktuellen Phase zuerst, in ihrer Reihenfolge.
              for (final c in [
                for (final id in current) ...value.where((c) => c.id == id),
                ...value.where((c) => !current.contains(c.id)),
              ])
                _course(context, c, isDone, current.contains(c.id)),
            ],
          ),
        AsyncError() => ErrorRetry(
            message: 'Coaching-Inhalte konnten nicht geladen werden.', onRetry: () => ref.invalidate(coursesProvider)),
        _ => const LoadingView(),
      },
    );
  }

  Widget _course(BuildContext context, Course c, bool Function(ContentItem) done, bool isCurrent) {
    final sync = ref.read(syncProvider);
    final lessons = c.lessons
        .where((l) => _kind == 'alle' || l.lessonKind == _kind)
        .where((l) => !_hideDone || !done(l))
        .toList();
    if (lessons.isEmpty) return const SizedBox.shrink();
    final total = c.lessons.length;
    final finished = c.lessons.where(done).length;
    final complete = total > 0 && finished == total;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: isCurrent ? VibonoColors.green : VibonoColors.grey200, width: isCurrent ? 1.5 : 1),
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: VibonoColors.green,
        title: Text(courseTitle(c.title), style: VibonoText.cardTitle),
        subtitle: Text(
          complete
              ? 'Abgeschlossen'
              : isCurrent
                  ? 'Aktuelle Phase · $finished von $total gelesen'
                  : '$finished von $total gelesen',
          style: VibonoText.small.copyWith(color: isCurrent || complete ? VibonoColors.green700 : null),
        ),
        leading: complete
            ? const CheckCircle(checked: true, size: 34)
            : SizedBox(
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
            InkWell(
              onTap: () => openContent(context, l),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 16, 0),
                child: Row(children: [
                  CheckCircle(
                    checked: done(l),
                    size: 22,
                    label: 'Als gelesen markieren',
                    onTap: () => sync.toggle(SyncCollection.lessonsDone, '${l.id}', {'post_id': l.id}),
                  ),
                  Expanded(
                    child: Text(
                      l.title,
                      style: VibonoText.body.copyWith(color: done(l) ? VibonoColors.grey400 : VibonoColors.grey800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(lessonIcon(l.lessonKind), size: 18, color: VibonoColors.green),
                ]),
              ),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

/// Kursnamen stehen auf der Website teils in Großbuchstaben.
String courseTitle(String t) {
  if (t != t.toUpperCase()) return t;
  String cap(String w) {
    final i = w.indexOf(RegExp('[A-ZÄÖÜ]'));
    if (i < 0 || w == 'UT') return w;
    return w.substring(0, i + 1) + w.substring(i + 1).toLowerCase();
  }

  return t.split(' ').map(cap).join(' ');
}

IconData lessonIcon(String? kind) => switch (kind) {
      'wichtig' => Icons.star_rounded,
      'lesen' => Icons.menu_book_rounded,
      'motivation' => Icons.favorite_rounded,
      'aufgaben' => Icons.task_alt_rounded,
      'rezepte' => Icons.restaurant_rounded,
      'probleme' => Icons.help_outline_rounded,
      'hinweise' => Icons.info_outline_rounded,
      _ => Icons.circle_outlined,
    };

String lessonKindLabel(String? kind) => switch (kind) {
      'wichtig' => 'Wichtig',
      'lesen' => 'Wissen',
      'motivation' => 'Motivation',
      'aufgaben' => 'Aufgabe',
      'rezepte' => 'Rezepte',
      'probleme' => 'Hilfe',
      'hinweise' => 'Hinweis',
      'freiwillig' => 'Extra',
      _ => 'Lektion',
    };

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) => const Text(
        'MEIN COACHING',
        style: TextStyle(
          fontFamily: VibonoFonts.display,
          fontWeight: FontWeight.w300,
          fontSize: 22,
          letterSpacing: 0.9,
          color: VibonoColors.green,
        ),
      );
}

// ---------------------------------------------------------------------------
// Level, Serie, Punkte
// ---------------------------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero({required this.progress, required this.points});
  final CoachingProgress progress;
  final int? points;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    const white = Colors.white;
    final soft = Colors.white.withValues(alpha: 0.82);
    return Container(
      color: VibonoColors.green,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          LevelSeal(level: p.level, size: 58, onGreen: true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.level.name,
                  style: const TextStyle(
                    fontFamily: VibonoFonts.display,
                    fontWeight: FontWeight.w600,
                    fontSize: 22,
                    color: white,
                    height: 1.1,
                  )),
              const SizedBox(height: 2),
              Text('${p.lessonsDone} von ${p.lessonsTotal} Lektionen gelesen',
                  style: VibonoText.small.copyWith(color: soft)),
              const SizedBox(height: 8),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: p.levelProgress),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    color: white,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                p.next == null
                    ? 'Höchstes Level erreicht.'
                    : 'Noch ${p.toNext} ${p.toNext == 1 ? 'Lektion' : 'Lektionen'} bis Level ${p.next!.number} „${p.next!.name}“',
                style: VibonoText.small.copyWith(color: soft, fontSize: 11),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        _ReadingWeek(readDays: p.readDays),
        const SizedBox(height: 12),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.25)),
        const SizedBox(height: 10),
        Row(children: [
          _Stat(value: '${p.streak}', label: p.streak == 1 ? 'Tag in Folge' : 'Tage in Folge'),
          _Stat(
            value: points == null ? '–' : formatPoints(points!),
            label: 'Punkte',
            onTap: () => push(context, const PointsScreen()),
          ),
          _Stat(value: '${p.badgesEarned}/${p.badges.length}', label: 'Abzeichen'),
        ]),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.onTap});
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Column(children: [
            Text(value,
                style: const TextStyle(
                  fontFamily: VibonoFonts.display,
                  fontWeight: FontWeight.w600,
                  fontSize: 22,
                  color: Colors.white,
                  height: 1.1,
                )),
            Text(label.toUpperCase(),
                style: TextStyle(
                  fontFamily: VibonoFonts.display,
                  fontSize: 11,
                  letterSpacing: 0.8,
                  color: Colors.white.withValues(alpha: 0.85),
                )),
          ]),
        ),
      );
}

/// Diese Woche: an welchen Tagen gelesen wurde.
class _ReadingWeek extends StatelessWidget {
  const _ReadingWeek({required this.readDays});
  final Set<DateTime> readDays;

  @override
  Widget build(BuildContext context) {
    final today = CoachingPlan.dateOnly(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return Semantics(
      label: 'Diese Woche an ${[for (var i = 0; i < 7; i++) monday.add(Duration(days: i))].where(readDays.contains).length} Tagen gelesen',
      child: Row(children: [
        for (var i = 0; i < 7; i++)
          Expanded(child: _dot(monday.add(Duration(days: i)), today)),
      ]),
    );
  }

  Widget _dot(DateTime d, DateTime today) {
    final read = readDays.contains(d);
    final isToday = d == today;
    final future = d.isAfter(today);
    return Column(children: [
      Text(
        DateFormat('EE', 'de_DE').format(d).replaceAll('.', '').toUpperCase(),
        style: TextStyle(
          fontFamily: VibonoFonts.display,
          fontSize: 10,
          letterSpacing: 0.6,
          color: Colors.white.withValues(alpha: isToday ? 1 : 0.75),
          fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      const SizedBox(height: 4),
      Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: read ? Colors.white : Colors.white.withValues(alpha: future ? 0.12 : 0.22),
          border: isToday && !read ? Border.all(color: Colors.white, width: 1.5) : null,
        ),
        alignment: Alignment.center,
        child: read ? const VibonoV(size: 11, color: VibonoColors.green) : null,
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Lernpfad
// ---------------------------------------------------------------------------

class _LearningPath extends StatefulWidget {
  const _LearningPath({required this.next, required this.isDone});
  final ({Course course, ContentItem lesson})? next;
  final bool Function(ContentItem) isDone;

  @override
  State<_LearningPath> createState() => _LearningPathState();
}

class _LearningPathState extends State<_LearningPath> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.next;
    if (n == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: VibonoColors.green050,
          border: Border(top: BorderSide(color: VibonoColors.green, width: 3)),
        ),
        child: Row(children: [
          const CheckCircle(checked: true, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Alle Lektionen gelesen. Stark! Neue Inhalte erscheinen hier automatisch.',
                style: VibonoText.body.copyWith(color: VibonoColors.grey800)),
          ),
        ]),
      );
    }
    final lessons = n.course.lessons;
    final ci = lessons.indexOf(n.lesson);
    final done = lessons.where(widget.isDone).length;
    final start = _all ? 0 : (ci - 2).clamp(0, lessons.length);
    final end = _all ? lessons.length : (ci + 4).clamp(0, lessons.length);
    final hiddenBefore = start;
    final hiddenAfter = lessons.length - end;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(child: SectionLabel('Dein Lernpfad')),
        Text('$done von ${lessons.length}', style: VibonoText.small),
      ]),
      const SizedBox(height: 2),
      Text(courseTitle(n.course.title), style: VibonoText.cardTitle.copyWith(fontSize: 18)),
      const SizedBox(height: 12),
      if (hiddenBefore > 0)
        _PathRow(
          node: const _Node.dots(),
          lineAbove: false,
          lineBelowDone: true,
          child: _PathText(
            title: '$hiddenBefore ${hiddenBefore == 1 ? 'Lektion' : 'Lektionen'} davor',
            meta: 'Alle anzeigen',
            onTap: () => setState(() => _all = true),
            muted: true,
          ),
        ),
      for (var i = start; i < end; i++)
        _PathRow(
          node: widget.isDone(lessons[i])
              ? const _Node.done()
              : i == ci
                  ? const _Node.current()
                  : _Node.open(i + 1),
          lineAbove: i > start || hiddenBefore > 0,
          lineAboveDone: i == 0 || widget.isDone(lessons[i - 1]),
          lineBelowDone: widget.isDone(lessons[i]),
          child: i == ci
              ? _CurrentLesson(lesson: lessons[i])
              : _PathText(
                  title: lessons[i].title,
                  meta: widget.isDone(lessons[i])
                      ? 'Gelesen'
                      : '${lessonKindLabel(lessons[i].lessonKind)} · ${lessons[i].readingMinutes ?? 3} Min.',
                  muted: widget.isDone(lessons[i]),
                  onTap: () => openContent(context, lessons[i]),
                ),
        ),
      if (hiddenAfter > 0)
        _PathRow(
          node: const _Node.dots(),
          lineAbove: true,
          lineBelowDone: false,
          child: _PathText(
            title: 'Noch $hiddenAfter ${hiddenAfter == 1 ? 'Lektion' : 'Lektionen'}',
            meta: 'Alle anzeigen',
            onTap: () => setState(() => _all = true),
            muted: true,
          ),
        ),
      _PathRow(
        node: const _Node.goal(),
        lineAbove: true,
        lineBelow: false,
        child: _PathText(
          title: 'Kurs abschließen',
          meta: 'Dafür gibt es das Abzeichen „Kurs geschafft“.',
          muted: true,
        ),
      ),
    ]);
  }
}

enum _NodeKind { done, current, open, dots, goal }

class _Node {
  const _Node.done()
      : kind = _NodeKind.done,
        number = 0;
  const _Node.current()
      : kind = _NodeKind.current,
        number = 0;
  const _Node.open(this.number) : kind = _NodeKind.open;
  const _Node.dots()
      : kind = _NodeKind.dots,
        number = 0;
  const _Node.goal()
      : kind = _NodeKind.goal,
        number = 0;

  final _NodeKind kind;
  final int number;

  Widget build() => switch (kind) {
        _NodeKind.done => const CheckCircle(checked: true, size: 26),
        _NodeKind.current => Container(
            width: 30,
            height: 30,
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
          ),
        _NodeKind.open => Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: VibonoColors.grey300, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text('$number',
                style: const TextStyle(fontFamily: VibonoFonts.display, fontSize: 12, color: VibonoColors.grey500)),
          ),
        _NodeKind.dots => const SizedBox(
            width: 26,
            height: 26,
            child: Icon(Icons.more_vert_rounded, size: 18, color: VibonoColors.grey300),
          ),
        _NodeKind.goal => Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: VibonoColors.green050),
            child: const Icon(Icons.workspace_premium_outlined, size: 18, color: VibonoColors.green700),
          ),
      };
}

class _PathRow extends StatelessWidget {
  const _PathRow({
    required this.node,
    required this.child,
    this.lineAbove = true,
    this.lineAboveDone = false,
    this.lineBelow = true,
    this.lineBelowDone = false,
  });

  final _Node node;
  final Widget child;
  final bool lineAbove;
  final bool lineAboveDone;
  final bool lineBelow;
  final bool lineBelowDone;

  @override
  Widget build(BuildContext context) {
    Widget line(bool show, bool done) => Container(
          width: 2,
          color: !show ? Colors.transparent : (done ? VibonoColors.green : VibonoColors.grey200),
        );
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 34,
          child: Column(children: [
            SizedBox(height: 6, child: line(lineAbove, lineAboveDone)),
            node.build(),
            Expanded(child: line(lineBelow, lineBelowDone)),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 12), child: child)),
      ]),
    );
  }
}

class _PathText extends StatelessWidget {
  const _PathText({required this.title, required this.meta, this.onTap, this.muted = false});
  final String title;
  final String meta;
  final VoidCallback? onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: VibonoText.body.copyWith(color: muted ? VibonoColors.grey500 : VibonoColors.grey800, height: 1.3)),
            Text(meta, style: VibonoText.small.copyWith(fontSize: 11, color: VibonoColors.grey400)),
          ]),
        ),
      );
}

class _CurrentLesson extends StatelessWidget {
  const _CurrentLesson({required this.lesson});
  final ContentItem lesson;

  @override
  Widget build(BuildContext context) {
    final meta = [
      lessonKindLabel(lesson.lessonKind),
      '${lesson.readingMinutes ?? 3} Min.',
      if (lesson.pointsForReading > 0) '+${lesson.pointsForReading} Punkte',
    ].join(' · ');
    return Material(
      color: VibonoColors.green,
      child: InkWell(
        onTap: () => openContent(context, lesson),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SectionLabel('Jetzt dran', color: Colors.white),
                const SizedBox(height: 2),
                Text(lesson.title,
                    style: const TextStyle(
                      fontFamily: VibonoFonts.display,
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                      height: 1.15,
                      color: Colors.white,
                    )),
                const SizedBox(height: 3),
                Text(meta, style: VibonoText.small.copyWith(color: Colors.white.withValues(alpha: 0.9))),
              ]),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
              child: const Text('LESEN',
                  style: TextStyle(
                    fontFamily: VibonoFonts.display,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.6,
                    color: VibonoColors.green700,
                  )),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Abzeichen
// ---------------------------------------------------------------------------

class _Badges extends StatelessWidget {
  const _Badges({required this.progress});
  final CoachingProgress progress;

  @override
  Widget build(BuildContext context) {
    final badges = progress.badges;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(child: SectionLabel('Deine Abzeichen')),
        Text('${progress.badgesEarned} von ${badges.length}', style: VibonoText.small),
      ]),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, c) {
        const perRow = 4;
        final w = (c.maxWidth - 8 * (perRow - 1)) / perRow;
        return Wrap(spacing: 8, runSpacing: 14, children: [
          for (final b in badges)
            SizedBox(
              width: w,
              child: Semantics(
                button: true,
                label: '${b.title}, ${b.earned ? 'verdient' : b.progressLabel}',
                child: InkWell(
                  onTap: () => showVibonoSheet(context, BadgeSheet(badge: b)),
                  child: Column(children: [
                    BadgeSeal(badge: b, size: 52),
                    const SizedBox(height: 6),
                    Text(
                      b.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        fontFamily: VibonoFonts.display,
                        fontSize: 12,
                        height: 1.15,
                        color: b.earned ? VibonoColors.grey800 : VibonoColors.grey400,
                        fontWeight: b.earned ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
        ]);
      }),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Phasen und Wunschgewicht
// ---------------------------------------------------------------------------

class _PhaseSteps extends StatelessWidget {
  const _PhaseSteps({required this.phase});
  final Phase phase;

  static const _steps = [
    ('Vorbereitung', 'Vor dem Start'),
    ('Phase 1: Umstellungstage', '${CoachingPlan.utDays} Tage'),
    ('Phase 2: Gewohnheiten ändern', '${CoachingPlan.phase2Days} Tage'),
    ('Phase 3: Satt essen & genießen', 'Dauerhaft'),
  ];

  @override
  Widget build(BuildContext context) {
    final current = phase.key.index;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x1F1C1C1C), blurRadius: 10, offset: Offset(0, 2))],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Expanded(child: SectionLabel('Dein Weg')),
          Text('4 PHASEN', style: TextStyle(fontFamily: VibonoFonts.display, fontSize: 12, letterSpacing: 1, color: VibonoColors.grey400)),
        ]),
        const SizedBox(height: 8),
        for (var i = 0; i < _steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (i < current)
                const CheckCircle(checked: true, size: 28)
              else
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: i == current ? VibonoColors.green : VibonoColors.grey300, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text('${i == 0 ? 'S' : i}',
                      style: TextStyle(
                        fontFamily: VibonoFonts.display,
                        fontWeight: FontWeight.w600,
                        color: i == current ? VibonoColors.green700 : VibonoColors.grey400,
                      )),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_steps[i].$1,
                      style: VibonoText.body.copyWith(
                        color: i == current ? VibonoColors.grey900 : (i < current ? VibonoColors.grey700 : VibonoColors.grey400),
                        fontWeight: i == current ? FontWeight.w700 : FontWeight.w400,
                        height: 1.3,
                      )),
                  Text(
                    i < current ? '${_steps[i].$2} · geschafft' : (i == current ? phase.dayLabel : _steps[i].$2),
                    style: VibonoText.small.copyWith(fontSize: 11),
                  ),
                  if (i == current) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: CoachingPlan.phaseProgress(phase),
                        minHeight: 5,
                        color: VibonoColors.green,
                        backgroundColor: VibonoColors.green100,
                      ),
                    ),
                  ],
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _Milestones extends ConsumerWidget {
  const _Milestones();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(sessionProvider).profile;
    final targets = [p.target3m, p.target6m, p.target12m];
    if (targets.every((t) => t == null)) return const SizedBox.shrink();
    final start = p.coachingStartDate;
    return InkWell(
      onTap: () => push(context, const WeightScreen()),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(border: Border.all(color: VibonoColors.grey200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionLabel('Wunschgewicht'),
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: Column(children: [
                  Text(const ['3 Monate', '6 Monate', '12 Monate'][i], style: VibonoText.small),
                  Text(
                    targets[i] == null
                        ? '–'
                        : '${targets[i]!.toStringAsFixed(1).replaceAll('.', ',').replaceAll(',0', '')} kg',
                    style: const TextStyle(
                      fontFamily: VibonoFonts.display,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: VibonoColors.green700,
                    ),
                  ),
                  if (start != null)
                    Text(
                      DateFormat('MMM yyyy', 'de_DE')
                          .format(DateTime(start.year, start.month + const [3, 6, 12][i], start.day)),
                      style: VibonoText.small,
                    ),
                ]),
              ),
          ]),
        ]),
      ),
    );
  }
}
