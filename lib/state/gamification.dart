import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/coaching_day.dart';
import '../data/models/content.dart';
import '../data/models/sync_item.dart';
import '../data/sync/sync_repository.dart';
import '../domain/coaching_plan.dart';
import '../domain/coaching_progress.dart';
import 'providers.dart';

/// Aktuelle Phase aus dem Startdatum, ohne auf den Server zu warten.
final currentPhaseProvider = Provider<PhaseKey>((ref) {
  final start = ref.watch(sessionProvider.select((s) => s.profile.coachingStartDate));
  final today = CoachingPlan.dateOnly(DateTime.now());
  return CoachingPlan.phaseFor(start ?? today.add(const Duration(days: 1)), today).key;
});

/// Gelesene Lektionen mit Zeitpunkt (aus der Sync-Sammlung lessons_done).
Map<int, DateTime> lessonsDoneAt(SyncRepository sync) => {
      for (final i in sync.items(SyncCollection.lessonsDone))
        ?int.tryParse(i.key): i.updatedAt,
    };

CoachingProgress computeCoachingProgress(List<Course> courses, SyncRepository sync, PhaseKey phase) =>
    CoachingProgress.compute(
      courses: courses,
      doneAt: lessonsDoneAt(sync),
      today: DateTime.now(),
      phase: phase,
      phaseCourseIds: phaseCourseIds[phase] ?? const [],
    );

/// Level, Serie und Abzeichen. `null`, solange die Kurse laden.
final coachingProgressProvider = Provider<CoachingProgress?>((ref) {
  final courses = ref.watch(coursesProvider).value;
  if (courses == null) return null;
  return computeCoachingProgress(courses, ref.watch(syncProvider), ref.watch(currentPhaseProvider));
});
