import 'package:material_ui/material_ui.dart';

import '../../data/models/content.dart';
import '../../domain/energy_density.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import 'common.dart';

/// „Als Nächstes“: genau ein nächster Schritt mit einem Knopf.
class NextStepCard extends StatelessWidget {
  const NextStepCard({
    super.key,
    required this.label,
    required this.title,
    this.subtitle,
    required this.action,
    required this.onTap,
    this.soft = false,
  });

  final String label;
  final String title;
  final String? subtitle;
  final String action;
  final VoidCallback onTap;
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final fg = soft ? VibonoColors.grey800 : Colors.white;
    return Material(
      color: soft ? VibonoColors.green050 : VibonoColors.green,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SectionLabel(label, color: soft ? VibonoColors.green700 : Colors.white),
                const SizedBox(height: 2),
                Text(title,
                    style: TextStyle(
                      fontFamily: VibonoFonts.display,
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                      color: fg,
                    )),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: VibonoText.small.copyWith(color: soft ? VibonoColors.grey500 : Colors.white)),
                ],
              ]),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: soft ? VibonoColors.green : Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                action.toUpperCase(),
                style: TextStyle(
                  fontFamily: VibonoFonts.display,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  letterSpacing: 0.6,
                  color: soft ? Colors.white : VibonoColors.green700,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Kachel im Tagesraster (Essen, Bewegung, Wissen, Wichtig).
class DayTile extends StatelessWidget {
  const DayTile({
    super.key,
    required this.kind,
    required this.title,
    required this.status,
    this.done = false,
    this.onTap,
  });

  final String kind;
  final String title;
  final String status;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: done ? VibonoColors.green050 : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: done ? Colors.transparent : VibonoColors.grey200),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: SectionLabel(kind)),
                if (done) const Icon(Icons.check_circle_rounded, size: 16, color: VibonoColors.green),
              ]),
              const SizedBox(height: 1),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VibonoText.cardTitle.copyWith(fontSize: 15.5)),
              Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: VibonoText.small),
            ]),
          ),
        ),
      );
}

/// Energiedichte-Plakette auf Rezeptbildern.
class EdBadge extends StatelessWidget {
  const EdBadge(this.value, {super.key});
  final double value;

  @override
  Widget build(BuildContext context) {
    final color = switch (EnergyDensity.ampel(value)) {
      Ampel.gruen => VibonoColors.green,
      Ampel.gelb => VibonoColors.gelb,
      Ampel.rot => VibonoColors.rot,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 2, 7, 2),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(
          EnergyDensity.format(value, digits: 1),
          semanticsLabel: 'Energiedichte ${EnergyDensity.format(value, digits: 1)}',
          style: const TextStyle(
            fontFamily: VibonoFonts.display,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: VibonoColors.grey800,
          ),
        ),
      ]),
    );
  }
}

/// Rezept als quadratisches Vorschaubild mit Bezeichnung.
class RecipeThumb extends StatelessWidget {
  const RecipeThumb({super.key, required this.recipe, required this.caption, this.onTap, this.favorite = false});
  final ContentItem recipe;
  final String caption;
  final VoidCallback? onTap;
  final bool favorite;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$caption: ${recipe.title}',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(fit: StackFit.expand, children: [
                  ContentImage(recipe.thumbnailUrl),
                  if (recipe.energyDensity != null) Positioned(left: 6, top: 6, child: EdBadge(recipe.energyDensity!)),
                  if (favorite)
                    const Positioned(right: 6, top: 6, child: Icon(Icons.favorite, size: 18, color: Colors.white)),
                ]),
              ),
            ),
            const SizedBox(height: 4),
            Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: VibonoText.cardTitle.copyWith(fontSize: 14)),
          ]),
        ),
      );
}

/// Vibono-Tipp (Blogbeitrag) mit Vorschaubild.
class TipCard extends StatelessWidget {
  const TipCard({super.key, required this.tip, this.onTap, this.label = 'Vibono-Tipp'});
  final ContentItem tip;
  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Row(children: [
          SizedBox(
            width: 112,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(borderRadius: BorderRadius.circular(10), child: ContentImage(tip.thumbnailUrl)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SectionLabel(label),
              Text(tip.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: VibonoText.cardTitle),
            ]),
          ),
        ]),
      );
}

class TipOfTheDay extends StatelessWidget {
  const TipOfTheDay({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: BoxDecoration(color: VibonoColors.green050, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const CoachAvatar(size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionLabel('Tipp des Tages'),
              Text(text, style: VibonoText.body.copyWith(fontSize: 13.5, color: VibonoColors.grey700)),
            ]),
          ),
        ]),
      );
}
