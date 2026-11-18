import 'package:material_ui/material_ui.dart';

import '../../data/models/coaching_day.dart';
import '../../domain/coaching_plan.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';

/// Fortschrittsbalken über die Abschnitte Start · UT · Phase 2 · Phase 3.
/// Zeigt, wo im Coaching man gerade steht.
class PhaseBar extends StatelessWidget {
  const PhaseBar({super.key, required this.phase, required this.progress});

  final Phase phase;

  /// Füllstand des aktuellen Abschnitts (0..1).
  final double progress;

  static const _flex = [1, 1, 3, 2];
  static const _labels = ['Start', 'UT', 'Phase 2', 'Phase 3'];

  @override
  Widget build(BuildContext context) {
    final current = phase.key.index;
    return Semantics(
      label: 'Fortschritt: ${phase.label}, ${phase.dayLabel}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                flex: _flex[i],
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    height: 9,
                    child: LinearProgressIndicator(
                      value: i < current ? 1 : (i == current ? progress.clamp(0.04, 1.0) : 0),
                      backgroundColor: VibonoColors.grey100,
                      color: VibonoColors.green,
                    ),
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 4),
          Row(children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                flex: _flex[i],
                child: Text(
                  i == current ? CoachingPlan.shortLabel(phase) : _labels[i],
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: TextStyle(
                    fontFamily: VibonoFonts.display,
                    fontSize: 12.5,
                    fontWeight: i == current ? FontWeight.w700 : FontWeight.w400,
                    color: i == current ? VibonoColors.green700 : VibonoColors.grey400,
                  ),
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }
}
