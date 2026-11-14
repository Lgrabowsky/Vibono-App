import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';

/// Vibono-Logo, unverändert aus dem Design-System übernommen.
class VibonoLogo extends StatelessWidget {
  const VibonoLogo({super.key, this.height = 22});
  final double height;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/images/vibono-logo.jpg',
        height: height,
        fit: BoxFit.contain,
        semanticLabel: 'Vibono',
      );
}

/// Das Vibono-V (für den Coaching-Tab).
class VibonoV extends StatelessWidget {
  const VibonoV({super.key, this.size = 24, this.color = VibonoColors.green});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/icons/vibono-v.svg',
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
}

/// App-Icon als „Coach“-Avatar.
class CoachAvatar extends StatelessWidget {
  const CoachAvatar({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.27),
        child: Image.asset('assets/images/vibono-app-icon.jpg', width: size, height: size),
      );
}

/// Bild aus dem App-Bundle (`asset:`) oder aus dem Netz.
class ContentImage extends StatelessWidget {
  const ContentImage(this.url, {super.key, this.fit = BoxFit.cover});
  final String? url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final u = url;
    const placeholder = ColoredBox(
      color: VibonoColors.green050,
      child: Center(child: VibonoV(size: 22, color: VibonoColors.green300)),
    );
    if (u == null || u.isEmpty) return placeholder;
    if (u.startsWith('asset:')) return Image.asset(u.substring(6), fit: fit);
    return Image.network(u, fit: fit, errorBuilder: (_, _, _) => placeholder);
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: VibonoText.label.copyWith(color: color));
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key, this.action, this.onAction});
  final String label;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: SectionLabel(label)),
          if (action != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  action!,
                  style: const TextStyle(
                    fontFamily: VibonoFonts.display,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: VibonoColors.green700,
                  ),
                ),
              ),
            ),
        ],
      );
}

/// Fehleranzeige mit „Nochmal versuchen“.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center, style: VibonoText.body),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('NOCHMAL VERSUCHEN')),
            ],
          ),
        ),
      );
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

/// Punktestand als kleine Pille.
class PointsChip extends StatelessWidget {
  const PointsChip({super.key, required this.points, this.onTap});
  final int points;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        label: '$points Punkte',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: VibonoColors.green050, borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star_rounded, size: 16, color: VibonoColors.green),
              const SizedBox(width: 4),
              Text(
                formatPoints(points),
                style: const TextStyle(
                  fontFamily: VibonoFonts.display,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: VibonoColors.green900,
                ),
              ),
            ]),
          ),
        ),
      );
}

String formatPoints(int p) {
  final s = p.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '${p < 0 ? '−' : ''}$b';
}

void showPointsToast(BuildContext context, int points, String reason) {
  if (points <= 0) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      const Icon(Icons.star_rounded, color: VibonoColors.green),
      const SizedBox(width: 8),
      Expanded(child: Text('+$points Punkte · $reason')),
    ]),
    duration: const Duration(seconds: 3),
  ));
}

void showMessage(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
