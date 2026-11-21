import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/api/api_exception.dart';
import '../../data/models/content.dart';
import '../../data/models/points.dart';
import '../../data/models/sync_item.dart';
import '../../domain/coaching_progress.dart';
import '../../state/gamification.dart';
import '../../state/providers.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import '../widgets/common.dart';
import '../widgets/day_sheets.dart';
import '../widgets/gamification.dart';
import 'rewards_screen.dart';

/// Beitrag lesen (Lektion oder Vibono-Tipp) mit Lese-Nachweis für Punkte.
///
/// Punkte gibt es nur, wenn der Beitrag nachweislich gelesen wurde:
/// 1. Aktive Lesezeit: zählt nur, solange die App im Vordergrund ist, der
///    Beitrag sichtbar ist und in den letzten 45 Sekunden gescrollt oder
///    getippt wurde.
/// 2. Scrolltiefe: das Ende des Beitrags muss erreicht sein.
/// 3. Der Server prüft per Heartbeat die Wanduhrzeit, die Aktivzeit kann
///    also nicht vorgetäuscht werden. Pro Beitrag gibt es Punkte nur einmal.
/// 4. Bei längeren Beiträgen optional eine kurze Quizfrage.
class ArticleScreen extends ConsumerStatefulWidget {
  const ArticleScreen({super.key, required this.contentId, this.preview});
  final int contentId;
  final ContentItem? preview;

  @override
  ConsumerState<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends ConsumerState<ArticleScreen> {
  static const idleLimit = Duration(seconds: 45);

  final _scroll = ScrollController();
  late final AppLifecycleListener _life;
  Timer? _ticker;
  ReadingSession? _session;
  bool _alreadyRewarded = false;
  bool _rewarded = false;
  bool _completing = false;
  bool _foreground = true;
  int _active = 0;
  int _sinceBeat = 0;
  double _depth = 0;
  DateTime _lastInteraction = DateTime.now();
  int? _quizChoice;
  String? _quizError;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _life = AppLifecycleListener(onStateChange: (s) => _foreground = s == AppLifecycleState.resumed);
    _startSession();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _life.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _startSession() async {
    final p = widget.preview;
    if (p != null && p.type == ContentType.recipe) return;
    try {
      final s = await ref.read(apiProvider).startReading(widget.contentId);
      if (!mounted) return;
      setState(() => _session = s);
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } on ApiException catch (e) {
      if (mounted && e.code == 'vibono_already_rewarded') setState(() => _alreadyRewarded = true);
    }
  }

  void _interact() => _lastInteraction = DateTime.now();

  void _onScroll() {
    _interact();
    _updateDepth();
  }

  void _updateDepth() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final d = pos.maxScrollExtent <= 0 ? 1.0 : ((pos.pixels + pos.viewportDimension) / (pos.maxScrollExtent + pos.viewportDimension));
    if (d > _depth) setState(() => _depth = d.clamp(0.0, 1.0));
  }

  bool get _visible => ModalRoute.of(context)?.isCurrent ?? false;

  void _tick() {
    final s = _session;
    if (s == null || _rewarded || !mounted) return;
    final idle = DateTime.now().difference(_lastInteraction) > idleLimit;
    if (_foreground && _visible && !idle) {
      setState(() => _active++);
      _sinceBeat++;
      if (_sinceBeat >= s.heartbeatIntervalSeconds) {
        _sinceBeat = 0;
        unawaited(ref.read(apiProvider).readingHeartbeat(s.sessionId, _active, _depth).catchError((_) => const ReadingProgress(acceptedActiveSeconds: 0, scrollDepth: 0, readyToComplete: false)));
      }
    }
    if (_ready && s.quizQuestion == null && !_completing) _complete();
  }

  bool get _ready {
    final s = _session;
    return s != null && _active >= s.minActiveSeconds && _depth >= s.minScrollDepth;
  }

  Future<void> _complete() async {
    final s = _session;
    if (s == null || _completing || _rewarded) return;
    setState(() {
      _completing = true;
      _quizError = null;
    });
    final api = ref.read(apiProvider);
    try {
      // Letzter Stand an den Server, damit er die Prüfung abschließen kann.
      await api.readingHeartbeat(s.sessionId, _active, _depth);
      final r = await api.completeReading(s.sessionId, quizAnswer: _quizChoice);
      if (!mounted) return;
      _ticker?.cancel();
      setState(() => _rewarded = true);
      ref.read(pointsBalanceProvider.notifier).set(r.balance);
      ref.invalidate(pointsProvider);
      ref.invalidate(ledgerProvider);
      final item = widget.preview;
      final sync = ref.read(syncProvider);
      final key = '${widget.contentId}';
      if (item != null && item.type == ContentType.lesson && !sync.has(SyncCollection.lessonsDone, key)) {
        // Lesepunkte plus Punkte für die erledigte Lektion (vergibt der Server beim Abgleich).
        final lessonPoints = ref.read(pointsProvider).value?.earnRules['lesson_done'] ?? 0;
        await _celebrate(r.awardedPoints + lessonPoints,
            () => sync.upsert(SyncCollection.lessonsDone, key, {'post_id': widget.contentId}));
      } else {
        showPointsToast(context, r.awardedPoints, 'Beitrag gelesen');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'vibono_quiz_wrong') {
        setState(() => _quizError = e.userMessage);
      } else if (e.code == 'vibono_daily_cap_reached' || e.code == 'vibono_already_rewarded') {
        _ticker?.cancel();
        setState(() => _alreadyRewarded = true);
        showMessage(context, e.userMessage);
      }
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  /// Lektion als gelesen speichern und zeigen, was sie gebracht hat:
  /// Punkte, Level-Fortschritt, Serie und neue Abzeichen.
  Future<void> _celebrate(int points, Future<void> Function() markDone) async {
    final sync = ref.read(syncProvider);
    final phase = ref.read(currentPhaseProvider);
    List<Course> courses;
    try {
      courses = await ref.read(coursesProvider.future);
    } catch (_) {
      courses = const [];
    }
    final before = computeCoachingProgress(courses, sync, phase);
    await markDone();
    final after = computeCoachingProgress(courses, sync, phase);
    if (!mounted) return;
    if (courses.isEmpty) {
      showPointsToast(context, points, 'Lektion gelesen');
      return;
    }
    final next = CoachingProgress.nextLesson(
      courses,
      (l) => sync.has(SyncCollection.lessonsDone, '${l.id}'),
      phaseCourseIds[phase] ?? const [],
    )?.lesson;
    await showVibonoSheet(
      context,
      LessonDoneSheet(
        before: before,
        after: after,
        points: points,
        next: next,
        onNext: next == null
            ? null
            : () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(builder: (_) => ArticleScreen(contentId: next.id, preview: next)),
                ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(contentItemProvider(widget.contentId));
    // Exklusiven Beitrag gerade freigeschaltet: jetzt gibt es auch Lesepunkte.
    ref.listen(contentItemProvider(widget.contentId), (prev, next) {
      if ((prev?.hasError ?? false) && next.hasValue && _session == null && !_alreadyRewarded) _startSession();
    });
    final sync = ref.watch(syncProvider);
    final isLesson = (item.value ?? widget.preview)?.type == ContentType.lesson;
    final done = sync.has(SyncCollection.lessonsDone, '${widget.contentId}');
    final favKey = 'tip:${widget.contentId}';
    final isTip = (item.value ?? widget.preview)?.type == ContentType.tip;

    return Scaffold(
      appBar: AppBar(
        title: Text(isLesson ? 'Mein Coaching' : 'Vibono-Tipp'),
        actions: [
          if (isTip)
            IconButton(
              tooltip: 'Merken',
              icon: Icon(sync.has(SyncCollection.favorites, favKey) ? Icons.favorite : Icons.favorite_border,
                  color: VibonoColors.green),
              onPressed: () => sync.toggle(SyncCollection.favorites, favKey, {'post_id': widget.contentId, 'kind': 'tip'}),
            ),
        ],
      ),
      body: switch (item) {
        AsyncData(:final value) => Listener(
            onPointerDown: (_) => _interact(),
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _updateDepth());
                return false;
              },
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  if (value.thumbnailUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AspectRatio(aspectRatio: 16 / 7, child: ContentImage(value.thumbnailUrl)),
                      ),
                    ),
                  Text(value.title, style: VibonoText.hello),
                  const SizedBox(height: 4),
                  Text('${value.readingMinutes ?? 3} Minuten Lesezeit', style: VibonoText.small),
                  const SizedBox(height: 12),
                  HtmlWidget(
                    value.contentHtml ?? '<p>${value.excerpt}</p>',
                    textStyle: VibonoText.body.copyWith(fontSize: 15.5, height: 1.6),
                  ),
                  const SizedBox(height: 16),
                  if (_session?.quizQuestion != null && _ready && !_rewarded) _quiz(_session!),
                  if (isLesson)
                    CheckboxListTile(
                      value: done,
                      onChanged: (_) => sync.toggle(
                          SyncCollection.lessonsDone, '${widget.contentId}', {'post_id': widget.contentId}),
                      title: const Text('Lektion erledigt', style: VibonoText.cardTitle),
                      subtitle: const Text('Wird mit „Mein Coaching“ auf vibono.de abgeglichen', style: VibonoText.small),
                      activeColor: VibonoColors.green,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                ],
              ),
            ),
          ),
        AsyncError(:final error) when error is ApiException && error.isRewardRequired => ExclusiveUnlockPanel(
            postId: widget.contentId,
            error: error,
            title: widget.preview?.title,
          ),
        AsyncError(:final error) => ErrorRetry(
            message: error is ApiException ? error.userMessage : 'Der Beitrag konnte nicht geladen werden.',
            onRetry: () => ref.invalidate(contentItemProvider(widget.contentId)),
          ),
        _ => const LoadingView(),
      },
      bottomNavigationBar: _readingBar(),
    );
  }

  Widget _quiz(ReadingSession s) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: VibonoColors.green050, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionLabel('Kurze Frage für deine Punkte'),
          const SizedBox(height: 4),
          Text(s.quizQuestion!, style: VibonoText.cardTitle),
          const SizedBox(height: 6),
          RadioGroup<int>(
            groupValue: _quizChoice,
            onChanged: (v) => setState(() => _quizChoice = v),
            child: Column(children: [
              for (var i = 0; i < s.quizAnswers.length; i++)
                RadioListTile<int>(
                  value: i,
                  title: Text(s.quizAnswers[i], style: VibonoText.body),
                  activeColor: VibonoColors.green,
                  contentPadding: EdgeInsets.zero,
                ),
            ]),
          ),
          if (_quizError != null) Text(_quizError!, style: VibonoText.small.copyWith(color: VibonoColors.rot)),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: _quizChoice == null || _completing ? null : _complete,
            child: const Text('ANTWORTEN'),
          ),
        ]),
      );

  Widget? _readingBar() {
    final s = _session;
    String text;
    double value;
    if (_rewarded) {
      text = 'Punkte gutgeschrieben. Danke fürs Lesen!';
      value = 1;
    } else if (_alreadyRewarded) {
      return null;
    } else if (s == null) {
      return null;
    } else {
      final left = (s.minActiveSeconds - _active).clamp(0, 9999);
      value = ((_active / s.minActiveSeconds).clamp(0.0, 1.0) * 0.5 + (_depth / s.minScrollDepth).clamp(0.0, 1.0) * 0.5);
      text = _ready
          ? (s.quizQuestion != null ? 'Fast geschafft: beantworte die Frage unten.' : 'Gleich geschafft …')
          : left > 0
              ? '+${s.points} Punkte fürs Lesen · noch etwa $left s'
              : '+${s.points} Punkte fürs Lesen · lies bis zum Ende';
    }
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: VibonoColors.grey100))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(Icons.star_rounded, size: 18, color: VibonoColors.green),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: VibonoText.small.copyWith(color: VibonoColors.grey700))),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: value, minHeight: 5, backgroundColor: VibonoColors.grey100),
          ),
        ]),
      ),
    );
  }
}
