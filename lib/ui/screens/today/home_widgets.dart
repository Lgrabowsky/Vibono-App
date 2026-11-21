import 'package:material_ui/material_ui.dart';

import '../../../theme/vibono_colors.dart';
import '../../../theme/vibono_theme.dart';

/// Überschrift eines Abschnitts auf „Heute“ („WAS HEUTE ESSEN?“).
class HomeSectionTitle extends StatelessWidget {
  const HomeSectionTitle(this.title, {super.key, this.action, this.onAction, this.actionIcon});
  final String title;
  final String? action;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontFamily: VibonoFonts.display,
              fontWeight: FontWeight.w300,
              fontSize: 20,
              letterSpacing: 0.8,
              color: VibonoColors.grey,
            ),
          ),
        ),
        if (action != null || actionIcon != null)
          InkWell(
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (actionIcon != null) Icon(actionIcon, size: 18, color: VibonoColors.green600),
                if (actionIcon != null && action != null) const SizedBox(width: 4),
                if (action != null) Text(action!.toUpperCase(), style: homeLinkStyle),
              ]),
            ),
          ),
      ]);
}

const homeLinkStyle = TextStyle(
  fontFamily: VibonoFonts.display,
  fontWeight: FontWeight.w600,
  fontSize: 14,
  letterSpacing: 1,
  color: VibonoColors.green600,
);

const homeTileLabel = TextStyle(
  fontFamily: VibonoFonts.display,
  fontWeight: FontWeight.w600,
  fontSize: 12,
  letterSpacing: 1,
  color: Color(0xFF6A871F),
);

/// Weiße Karte mit leichtem Schatten, eckig wie auf vibono.de.
class HomeCard extends StatelessWidget {
  const HomeCard({super.key, required this.child, this.onTap, this.color = Colors.white, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          boxShadow: color == Colors.white
              ? const [BoxShadow(color: Color(0x1A1C1C1C), blurRadius: 10, offset: Offset(0, 2))]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      );
}

/// Grüner Pillen-Knopf in Großbuchstaben.
class HomePillButton extends StatelessWidget {
  const HomePillButton(this.label, {super.key, required this.onPressed, this.filled = true});
  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) => Material(
        color: filled ? VibonoColors.green : Colors.white,
        shape: StadiumBorder(side: filled ? BorderSide.none : const BorderSide(color: VibonoColors.green, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: VibonoFonts.display,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 1,
                color: filled ? Colors.white : VibonoColors.green700,
              ),
            ),
          ),
        ),
      );
}

/// Kleine Info mit Symbol, z. B. „6 °C, Regen“.
class HomeInfoBit extends StatelessWidget {
  const HomeInfoBit(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: VibonoColors.green700),
        const SizedBox(width: 4),
        Text(text, style: VibonoText.small.copyWith(color: VibonoColors.grey700)),
      ]);
}

/// Fortschrittsbalken, ruhig und flach.
class HomeProgressBar extends StatelessWidget {
  const HomeProgressBar(this.value, {super.key, this.height = 8});
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0, 1)),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => LinearProgressIndicator(
            value: v,
            minHeight: height,
            color: VibonoColors.green,
            backgroundColor: VibonoColors.green100,
          ),
        ),
      );
}
