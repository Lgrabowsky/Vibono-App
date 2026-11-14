import '../data/models/coaching_day.dart';
import '../data/models/content.dart';
import 'coaching_plan.dart';

/// Stufe im Coaching, steigt mit jeder gelesenen Lektion.
class CoachingLevel {
  const CoachingLevel(this.number, this.name, this.minLessons);
  final int number;
  final String name;
  final int minLessons;
}

/// Abzeichen für Etappen beim Lesen. Bewusst ruhig: keine Countdowns,
/// nichts geht verloren, ein verdientes Abzeichen bleibt.
class CoachingBadge {
  const CoachingBadge({
    required this.id,
    required this.title,
    required this.description,
    required this.earned,
    required this.progress,
    required this.progressLabel,
  });

  final String id;
  final String title;
  final String description;
  final bool earned;

  /// 0..1 bis zum Abzeichen.
  final double progress;
  final String progressLabel;
}

class CoachingProgress {
  const CoachingProgress({
    required this.lessonsDone,
    required this.lessonsTotal,
    required this.level,
    required this.next,
    required this.levelProgress,
    required this.toNext,
    required this.streak,
    required this.bestStreak,
    required this.readDays,
    required this.coursesDone,
    required this.badges,
  });

  final int lessonsDone;
  final int lessonsTotal;
  final CoachingLevel level;
  final CoachingLevel? next;

  /// 0..1 vom aktuellen zum nächsten Level.
  final double levelProgress;

  /// Lektionen bis zum nächsten Level.
  final int toNext;

  /// Tage in Folge mit mindestens einer gelesenen Lektion (heute oder bis
  /// gestern; die Serie gilt also bis zum Ende des heutigen Tages).
  final int streak;
  final int bestStreak;
  final Set<DateTime> readDays;
  final int coursesDone;
  final List<CoachingBadge> badges;

  int get badgesEarned => badges.where((b) => b.earned).length;

  static const levels = [
    CoachingLevel(1, 'Einsteiger', 0),
    CoachingLevel(2, 'Entdecker', 5),
    CoachingLevel(3, 'Kenner', 15),
    CoachingLevel(4, 'Fortgeschritten', 35),
    CoachingLevel(5, 'Profi', 70),
    CoachingLevel(6, 'Experte', 120),
    CoachingLevel(7, 'Vibono-Meister', 170),
  ];

  static CoachingLevel levelFor(int lessons) => levels.lastWhere((l) => lessons >= l.minLessons);

  /// [doneAt]: Lektion → Zeitpunkt, an dem sie als gelesen markiert wurde.
  factory CoachingProgress.compute({
    required List<Course> courses,
    required Map<int, DateTime> doneAt,
    required DateTime today,
    required PhaseKey phase,
    List<int> phaseCourseIds = const [],
  }) {
    final allIds = {for (final c in courses) for (final l in c.lessons) l.id};
    final done = doneAt.keys.where(allIds.contains).length;
    final total = allIds.length;

    final level = levelFor(done);
    final next = levels.where((l) => l.minLessons > done).firstOrNull;
    final span = next == null ? 1 : next.minLessons - level.minLessons;
    final levelProgress = next == null ? 1.0 : (done - level.minLessons) / span;

    final days = {for (final t in doneAt.values) CoachingPlan.dateOnly(t.toLocal())};
    final t = CoachingPlan.dateOnly(today);
    var cursor = days.contains(t) ? t : t.subtract(const Duration(days: 1));
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    final sorted = days.toList()..sort();
    var best = 0;
    var run = 0;
    DateTime? prev;
    for (final d in sorted) {
      run = prev != null && CoachingPlan.daysBetween(prev, d) == 1 ? run + 1 : 1;
      if (run > best) best = run;
      prev = d;
    }

    bool isDone(ContentItem l) => doneAt.containsKey(l.id);
    final coursesDone = courses.where((c) => c.lessons.isNotEmpty && c.lessons.every(isDone)).length;
    final bestCourse = courses.where((c) => c.lessons.isNotEmpty).fold<double>(
          0,
          (m, c) => (c.lessons.where(isDone).length / c.lessons.length) > m ? c.lessons.where(isDone).length / c.lessons.length : m,
        );
    final important = [
      for (final c in courses)
        if (phaseCourseIds.contains(c.id)) ...c.lessons.where((l) => l.lessonKind == 'wichtig'),
    ];
    final importantDone = important.where(isDone).length;

    CoachingBadge count(String id, String title, String description, int have, int need, String unit) =>
        CoachingBadge(
          id: id,
          title: title,
          description: description,
          earned: have >= need,
          progress: need == 0 ? 1 : (have / need).clamp(0.0, 1.0),
          progressLabel: '${have.clamp(0, need)} von $need $unit',
        );

    final halfway = (total / 2).ceil();
    final badges = [
      count('erste', 'Der Anfang', 'Deine erste Lektion gelesen.', done, 1, 'Lektionen'),
      count('zehn', 'Wissenshunger', '10 Lektionen gelesen.', done, 10, 'Lektionen'),
      count('serie3', 'Dranbleiber', 'An 3 Tagen in Folge gelesen.', best, 3, 'Tagen'),
      count('serie7', 'Eine ganze Woche', 'An 7 Tagen in Folge gelesen.', best, 7, 'Tagen'),
      CoachingBadge(
        id: 'kurs',
        title: 'Kurs geschafft',
        description: 'Einen Kurs komplett gelesen.',
        earned: coursesDone > 0,
        progress: coursesDone > 0 ? 1 : bestCourse,
        progressLabel: coursesDone > 0 ? '$coursesDone Kurse fertig' : '${(bestCourse * 100).round()} % im besten Kurs',
      ),
      if (important.isNotEmpty)
        count('wichtig', 'Das Wichtigste zuerst', 'Alle „Wichtig“-Lektionen deiner aktuellen Phase gelesen.',
            importantDone, important.length, 'Lektionen'),
      CoachingBadge(
        id: 'ut',
        title: 'Umstellungstage',
        description: 'Die Umstellungstage geschafft und in Phase 2 angekommen.',
        earned: phase.index >= PhaseKey.phase2.index,
        progress: switch (phase) {
          PhaseKey.vorbereitung => 0,
          PhaseKey.phase1 => 0.5,
          _ => 1,
        },
        progressLabel: phase.index >= PhaseKey.phase2.index ? 'geschafft' : 'ab Phase 2',
      ),
      if (total > 0) count('halbzeit', 'Halbzeit', 'Die Hälfte aller Lektionen gelesen.', done, halfway, 'Lektionen'),
    ];

    return CoachingProgress(
      lessonsDone: done,
      lessonsTotal: total,
      level: level,
      next: next,
      levelProgress: levelProgress.clamp(0.0, 1.0),
      toNext: next == null ? 0 : next.minLessons - done,
      streak: streak,
      bestStreak: best,
      readDays: days,
      coursesDone: coursesDone,
      badges: badges,
    );
  }

  /// Abzeichen, die zwischen [before] und diesem Stand neu dazukamen.
  List<CoachingBadge> newBadgesSince(CoachingProgress before) {
    final had = {for (final b in before.badges) if (b.earned) b.id};
    return badges.where((b) => b.earned && !had.contains(b.id)).toList();
  }

  /// Nächste ungelesene Lektion: zuerst in den Kursen der aktuellen Phase.
  static ({Course course, ContentItem lesson})? nextLesson(
    List<Course> courses,
    bool Function(ContentItem) isDone,
    List<int> phaseCourseIds,
  ) {
    final ordered = [
      for (final id in phaseCourseIds) ...courses.where((c) => c.id == id),
      ...courses.where((c) => !phaseCourseIds.contains(c.id)),
    ];
    for (final c in ordered) {
      final l = c.lessons.where((l) => !isDone(l)).firstOrNull;
      if (l != null) return (course: c, lesson: l);
    }
    return null;
  }
}

/// Kurse je Phase (Kurs-IDs aus „Mein Coaching“), in Lesereihenfolge.
const phaseCourseIds = {
  PhaseKey.vorbereitung: [247, 248, 249, 219],
  PhaseKey.phase1: [220, 251, 250, 252],
  PhaseKey.phase2: [253, 221, 254, 256, 255],
  PhaseKey.phase3: [222, 257, 258, 260, 261],
};
