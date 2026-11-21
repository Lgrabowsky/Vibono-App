import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/content.dart';
import '../../../data/models/home_feed.dart';
import '../../../domain/coaching_progress.dart';
import '../../../domain/home_progress.dart';
import '../../../state/home.dart';
import '../../../theme/vibono_colors.dart';
import '../../../theme/vibono_theme.dart';
import '../../navigation.dart';
import '../../widgets/common.dart';
import '../coaching_screen.dart' show lessonKindLabel;
import 'home_widgets.dart';

/// Coaching-Fortschritt und nächste Lektion.
class NextLessonCard extends StatelessWidget {
  const NextLessonCard({super.key, required this.lesson, this.progress, this.compact = false});
  final ContentItem? lesson;
  final CoachingProgress? progress;

  /// Nur Fortschritt, wenn die Lektion schon als „Jetzt dran“ im Tagespfad steht.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final l = lesson;
    return HomeCard(
      onTap: l == null || compact ? null : () => openContent(context, l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (p != null) ...[
          Row(children: [
            Expanded(
              child: Text(
                'Level ${p.level.number} · ${p.level.name}',
                style: VibonoText.small.copyWith(color: VibonoColors.grey700, fontWeight: FontWeight.w700),
              ),
            ),
            Text('${p.lessonsDone} von ${p.lessonsTotal} Lektionen', style: VibonoText.small),
          ]),
          const SizedBox(height: 6),
          HomeProgressBar(p.lessonsTotal == 0 ? 0 : p.lessonsDone / p.lessonsTotal, height: 6),
          if (p.next != null) ...[
            const SizedBox(height: 4),
            Text(
              'Noch ${p.toNext} ${p.toNext == 1 ? 'Lektion' : 'Lektionen'} bis „${p.next!.name}“',
              style: VibonoText.small.copyWith(fontSize: 11),
            ),
          ],
        ],
        if (l != null && !compact) ...[
          if (p != null) const SizedBox(height: 12),
          const Text('NÄCHSTE LEKTION', style: homeTileLabel),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: VibonoText.body.copyWith(color: VibonoColors.grey900, fontWeight: FontWeight.w700)),
                Text(
                  [
                    lessonKindLabel(l.lessonKind),
                    '${l.readingMinutes ?? 3} Min.',
                    if (l.pointsForReading > 0) '+${l.pointsForReading} Punkte',
                  ].join(' · '),
                  style: VibonoText.small,
                ),
              ]),
            ),
            const SizedBox(width: 10),
            HomePillButton('Lesen', onPressed: () => openContent(context, l)),
          ]),
        ],
        if (l == null && p != null && !compact) ...[
          const SizedBox(height: 10),
          Text('Alle Lektionen für heute gelesen. Stark!',
              style: VibonoText.small.copyWith(color: VibonoColors.green900, fontWeight: FontWeight.w700)),
        ],
      ]),
    );
  }
}

/// Freundlicher Schubs, wenn eine Weile keine Lektion gelesen wurde.
class NudgeCard extends StatelessWidget {
  const NudgeCard({super.key, required this.nudge, this.lesson});
  final Nudge nudge;
  final ContentItem? lesson;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: VibonoColors.warnBg,
          border: Border(left: BorderSide(color: VibonoColors.orange, width: 4)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const ClipOval(child: CoachAvatar(size: 36)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nudge.title, style: VibonoText.body.copyWith(fontWeight: FontWeight.w700, color: VibonoColors.grey900)),
              const SizedBox(height: 2),
              Text(nudge.text, style: VibonoText.small.copyWith(color: VibonoColors.grey700, fontSize: 13)),
              if (lesson != null) ...[
                const SizedBox(height: 10),
                HomePillButton('Jetzt 3 Minuten lesen', onPressed: () => openContent(context, lesson!)),
              ],
            ]),
          ),
        ]),
      );
}

/// Quiz des Tages: eine Frage, Antwort antippen, Erklärung lesen.
class QuizCard extends ConsumerWidget {
  const QuizCard({super.key, required this.quiz, required this.date});
  final QuizQuestion quiz;
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answered = ref.watch(quizAnswersProvider)[QuizAnswers.key(date, quiz)];
    final right = answered == quiz.correct;
    return HomeCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.quiz_outlined, size: 18, color: VibonoColors.green700),
          const SizedBox(width: 6),
          const Expanded(child: Text('QUIZ DES TAGES', style: homeTileLabel)),
          if (answered != null)
            Text(right ? 'Richtig' : 'Knapp daneben', style: VibonoText.small.copyWith(color: VibonoColors.green900, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        Text(quiz.question, style: VibonoText.body.copyWith(color: VibonoColors.grey900, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        for (var i = 0; i < quiz.answers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AnswerButton(
              text: quiz.answers[i],
              state: answered == null
                  ? _AnswerState.open
                  : i == quiz.correct
                      ? _AnswerState.correct
                      : i == answered
                          ? _AnswerState.wrong
                          : _AnswerState.idle,
              onTap: answered == null ? () => ref.read(quizAnswersProvider.notifier).answer(date, quiz, i) : null,
            ),
          ),
        if (answered != null && quiz.explanation.isNotEmpty)
          Text(
            right ? quiz.explanation : 'Richtig ist „${quiz.answers[quiz.correct]}“. ${quiz.explanation}',
            style: VibonoText.small.copyWith(color: VibonoColors.grey700, fontSize: 13),
          ),
      ]),
    );
  }
}

enum _AnswerState { open, idle, correct, wrong }

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({required this.text, required this.state, this.onTap});
  final String text;
  final _AnswerState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg, icon) = switch (state) {
      _AnswerState.open => (Colors.white, VibonoColors.grey300, VibonoColors.grey900, null),
      _AnswerState.idle => (Colors.white, VibonoColors.grey200, VibonoColors.grey400, null),
      _AnswerState.correct => (VibonoColors.green050, VibonoColors.green, VibonoColors.green900, Icons.check_rounded),
      _AnswerState.wrong => (VibonoColors.grey050, VibonoColors.grey400, VibonoColors.grey700, Icons.close_rounded),
    };
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(side: BorderSide(color: border, width: 1.5)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Expanded(child: Text(text, style: VibonoText.body.copyWith(color: fg))),
            if (icon != null) Icon(icon, size: 18, color: fg),
          ]),
        ),
      ),
    );
  }
}
