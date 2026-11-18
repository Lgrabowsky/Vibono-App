import 'package:material_ui/material_ui.dart';

import '../../data/models/points.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';

/// Text für die Punkte-Meldung beim Öffnen der App.
String streakToastText(AppStreak? s) {
  if (s == null || !s.enabled || s.todayDay <= 1) return 'Schön, dass du heute da bist!';
  if (s.event == 'bridged') return 'Tag ${s.todayDay} in Folge. Ein Schutztag hat deine Serie gehalten.';
  if (s.stage != null && s.stage!.fromDay == s.todayDay && s.stageIndex > 0) {
    return 'Tag ${s.todayDay} in Folge. Ab heute ${s.todayPoints} Punkte pro Tag!';
  }
  return 'Tag ${s.todayDay} in Folge. Schön, dass du da bist!';
}

String _tage(int n) => n == 1 ? '1 Tag' : '$n Tage';

/// Hinweis unter der Serie: nächste Stufe, Schutztag oder Neustart.
String streakHint(AppStreak s) {
  if (s.event == 'bridged') {
    return s.bridgedDays == 1
        ? 'Gestern war Pause, ein Schutztag hat deine Serie gehalten.'
        : '${s.bridgedDays} Schutztage haben deine Serie gehalten.';
  }
  if (s.event == 'broken' && s.onBreak == 'drop_level' && s.todayDay > 1) {
    return 'Nach der Pause geht es auf der Stufe ab Tag ${s.stage?.fromDay ?? s.todayDay} weiter.';
  }
  final next = s.nextStage;
  if (next == null) return 'Höchste Stufe erreicht: ${s.todayPoints} Punkte an jedem Tag.';
  return 'Noch ${_tage(s.daysToNextStage)} bis ${next.points} Punkte pro Tag.';
}

/// Karte „Deine Serie“ auf der Startseite „Heute“: Tage in Folge, Punkte
/// heute und Weg bis zur nächsten Stufe. Ruhig, ohne Countdown.
class StreakCard extends StatelessWidget {
  const StreakCard({super.key, required this.streak, this.onTap, this.title = 'DEINE SERIE'});
  final AppStreak streak;
  final VoidCallback? onTap;
  final String title;

  @override
  Widget build(BuildContext context) {
    final s = streak;
    final days = s.openedToday ? s.days : s.todayDay;
    final from = s.stage?.fromDay ?? 1;
    final to = s.nextStage?.fromDay;
    final progress = to == null ? 1.0 : ((days - from + 1) / (to - from + 1)).clamp(0.0, 1.0);
    return Semantics(
      button: onTap != null,
      label: 'Serie: ${_tage(days)} in Folge, heute ${s.todayPoints} Punkte. ${streakHint(s)}',
      excludeSemantics: true,
      child: Material(
        color: VibonoColors.green050,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(children: [
              SizedBox(
                width: 58,
                child: Column(children: [
                  Text(
                    '$days',
                    style: const TextStyle(
                      fontFamily: VibonoFonts.display,
                      fontSize: 30,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      color: VibonoColors.green700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(days == 1 ? 'TAG' : 'TAGE', style: VibonoText.label.copyWith(fontSize: 11)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(title, style: VibonoText.label)),
                    Text('+${s.todayPoints} Punkte heute',
                        style: VibonoText.small.copyWith(fontWeight: FontWeight.w700, color: VibonoColors.grey900)),
                  ]),
                  const SizedBox(height: 7),
                  _StageBar(levels: s.levels, current: s.stageIndex, progress: progress),
                  const SizedBox(height: 7),
                  Text(streakHint(s), style: VibonoText.small.copyWith(color: VibonoColors.grey700)),
                ]),
              ),
              if (onTap != null) const Icon(Icons.chevron_right_rounded, color: VibonoColors.grey400),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Stufen als Segmente: erreichte grün, aktuelle anteilig gefüllt.
class _StageBar extends StatelessWidget {
  const _StageBar({required this.levels, required this.current, required this.progress});
  final List<StreakLevel> levels;
  final int current;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final n = levels.isEmpty ? 1 : levels.length;
    return Row(children: [
      for (var i = 0; i < n; i++) ...[
        if (i > 0) const SizedBox(width: 3),
        Expanded(
          child: ClipRect(
            child: SizedBox(
              height: 6,
              child: Stack(fit: StackFit.expand, children: [
                const ColoredBox(color: VibonoColors.green200),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: i < current ? 1 : (i == current ? progress : 0),
                  child: const ColoredBox(color: VibonoColors.green),
                ),
              ]),
            ),
          ),
        ),
      ],
    ]);
  }
}

/// Stufen der Serie für den Punkte-Bildschirm.
class StreakLadder extends StatelessWidget {
  const StreakLadder({super.key, required this.streak});
  final AppStreak streak;

  @override
  Widget build(BuildContext context) {
    final s = streak;
    final current = s.stageIndex;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StreakCard(streak: s, title: 'IN FOLGE'),
      const SizedBox(height: 10),
      for (var i = 0; i < s.levels.length; i++)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: VibonoColors.grey200))),
          child: Row(children: [
            Icon(
              i < current
                  ? Icons.check_circle_rounded
                  : (i == current ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
              size: 18,
              color: i <= current ? VibonoColors.green : VibonoColors.grey300,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                i + 1 < s.levels.length
                    ? (i == 0 ? 'Tag 1 bis ${s.levels[1].fromDay - 1}' : 'Ab Tag ${s.levels[i].fromDay}')
                    : (i == 0 ? 'Jeden Tag' : 'Ab Tag ${s.levels[i].fromDay}'),
                style: VibonoText.body.copyWith(
                  fontWeight: i == current ? FontWeight.w700 : FontWeight.w400,
                  color: i == current ? VibonoColors.grey900 : VibonoColors.grey700,
                ),
              ),
            ),
            Text('${s.levels[i].points} Punkte pro Tag',
                style: VibonoText.body.copyWith(fontWeight: i == current ? FontWeight.w700 : FontWeight.w400)),
          ]),
        ),
      const SizedBox(height: 10),
      Text(
        [
          if (s.gracePerMonth > 0)
            'Mal einen Tag verpasst? ${s.gracePerMonth == 1 ? 'Ein Schutztag' : '${s.gracePerMonth} Schutztage'} pro Monat halten deine Serie '
                '(diesen Monat noch ${s.graceLeft}).',
          s.onBreak == 'drop_level'
              ? 'Reißt die Serie trotzdem, geht es eine Stufe tiefer weiter, nicht ganz von vorn.'
              : 'Reißt die Serie, beginnt sie wieder bei Tag 1.',
          if (s.best > 0) 'Deine längste Serie: ${_tage(s.best)}.',
        ].join(' '),
        style: VibonoText.small,
      ),
    ]);
  }
}
