import 'package:material_ui/material_ui.dart';

import '../../data/models/content.dart';
import '../../domain/coaching_progress.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import 'common.dart';

IconData badgeIcon(String id) => switch (id) {
      'erste' => Icons.flag_outlined,
      'zehn' => Icons.menu_book_outlined,
      'serie3' => Icons.repeat_rounded,
      'serie7' => Icons.calendar_month_outlined,
      'kurs' => Icons.school_outlined,
      'wichtig' => Icons.star_outline_rounded,
      'ut' => Icons.eco_outlined,
      'halbzeit' => Icons.timelapse_rounded,
      _ => Icons.workspace_premium_outlined,
    };

/// Abzeichen als Siegel: verdient grün gefüllt, sonst grau mit
/// Fortschrittsring.
class BadgeSeal extends StatelessWidget {
  const BadgeSeal({super.key, required this.badge, this.size = 56});
  final CoachingBadge badge;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          if (!badge.earned)
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: badge.progress,
                strokeWidth: 3,
                color: VibonoColors.green300,
                backgroundColor: VibonoColors.grey100,
              ),
            ),
          Container(
            width: badge.earned ? size : size - 10,
            height: badge.earned ? size : size - 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: badge.earned ? VibonoColors.green : VibonoColors.grey050,
            ),
            child: Icon(
              badgeIcon(badge.id),
              size: size * 0.42,
              color: badge.earned ? Colors.white : VibonoColors.grey300,
            ),
          ),
        ]),
      );
}

/// Level als rundes Siegel mit Zahl.
class LevelSeal extends StatelessWidget {
  const LevelSeal({super.key, required this.level, this.size = 60, this.onGreen = false});
  final CoachingLevel level;
  final double size;
  final bool onGreen;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: onGreen ? VibonoColors.green200 : VibonoColors.green, width: 3),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(
            'LEVEL',
            style: TextStyle(
              fontFamily: VibonoFonts.display,
              fontWeight: FontWeight.w600,
              fontSize: size * 0.14,
              letterSpacing: 1,
              color: VibonoColors.green700,
              height: 1,
            ),
          ),
          Text(
            '${level.number}',
            style: TextStyle(
              fontFamily: VibonoFonts.display,
              fontWeight: FontWeight.w600,
              fontSize: size * 0.42,
              color: VibonoColors.green700,
              height: 1.05,
            ),
          ),
        ]),
      );
}

/// Kurz erklärt, wie man ein Abzeichen bekommt.
class BadgeSheet extends StatelessWidget {
  const BadgeSheet({super.key, required this.badge});
  final CoachingBadge badge;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        BadgeSeal(badge: badge, size: 84),
        const SizedBox(height: 12),
        Text(badge.title, style: VibonoText.cardTitle.copyWith(fontSize: 20)),
        const SizedBox(height: 4),
        Text(badge.description, textAlign: TextAlign.center, style: VibonoText.body),
        const SizedBox(height: 10),
        SectionLabel(badge.earned ? 'Verdient' : badge.progressLabel,
            color: badge.earned ? VibonoColors.green700 : VibonoColors.grey400),
        const SizedBox(height: 8),
      ]);
}

/// Nach einer gelesenen Lektion: Bestätigung mit Punkten, Level-Fortschritt
/// und neuen Abzeichen. Ruhige Bewegung, kein Feuerwerk.
class LessonDoneSheet extends StatelessWidget {
  const LessonDoneSheet({
    super.key,
    required this.before,
    required this.after,
    required this.points,
    this.next,
    this.onNext,
  });

  final CoachingProgress before;
  final CoachingProgress after;
  final int points;
  final ContentItem? next;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final levelUp = after.level.number > before.level.number;
    final fresh = after.newBadgesSince(before);
    final from = levelUp ? 0.0 : before.levelProgress;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.85, end: 1),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (_, s, child) => Transform.scale(scale: s, child: Opacity(opacity: ((s - 0.85) / 0.15).clamp(0, 1), child: child)),
          child: Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(color: VibonoColors.green, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const VibonoV(size: 32, color: Colors.white),
          ),
        ),
      ),
      const SizedBox(height: 12),
      const Center(child: SectionLabel('Lektion geschafft')),
      const SizedBox(height: 2),
      Center(
        child: Text(
          levelUp ? 'Neues Level: ${after.level.name}' : 'Gut gemacht!',
          style: VibonoText.hello.copyWith(fontSize: 24, fontWeight: FontWeight.w300),
        ),
      ),
      if (points > 0) ...[
        const SizedBox(height: 8),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: VibonoColors.green050, borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star_rounded, size: 16, color: VibonoColors.green),
              const SizedBox(width: 4),
              Text('+$points Punkte',
                  style: const TextStyle(
                    fontFamily: VibonoFonts.display,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: VibonoColors.green900,
                  )),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 18),
      Row(children: [
        LevelSeal(level: after.level, size: 46),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Level ${after.level.number} · ${after.level.name}', style: VibonoText.cardTitle),
            const SizedBox(height: 6),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: from, end: after.levelProgress),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 8,
                  color: VibonoColors.green,
                  backgroundColor: VibonoColors.green100,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              after.next == null
                  ? 'Höchstes Level erreicht.'
                  : 'Noch ${after.toNext} ${after.toNext == 1 ? 'Lektion' : 'Lektionen'} bis „${after.next!.name}“',
              style: VibonoText.small,
            ),
          ]),
        ),
      ]),
      if (after.streak > 1) ...[
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.repeat_rounded, size: 18, color: VibonoColors.green700),
          const SizedBox(width: 8),
          Text('${after.streak} Tage in Folge gelesen', style: VibonoText.body),
        ]),
      ],
      for (final b in fresh) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: VibonoColors.green050,
            border: Border(top: BorderSide(color: VibonoColors.green, width: 3)),
          ),
          child: Row(children: [
            BadgeSeal(badge: b, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SectionLabel('Neues Abzeichen'),
                Text(b.title, style: VibonoText.cardTitle),
                Text(b.description, style: VibonoText.small),
              ]),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 20),
      if (next != null && onNext != null)
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: () {
            Navigator.pop(context);
            onNext!();
          },
          child: const Text('NÄCHSTE LEKTION'),
        ),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('FERTIG')),
      if (next != null)
        Center(
          child: Text('Als Nächstes: ${next!.title}',
              textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: VibonoText.small),
        ),
    ]);
  }
}
