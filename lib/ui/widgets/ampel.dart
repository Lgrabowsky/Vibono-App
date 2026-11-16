import 'package:material_ui/material_ui.dart';

import '../../domain/energy_density.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';

Color ampelColor(Ampel a) => switch (a) {
      Ampel.gruen => VibonoColors.green,
      Ampel.gelb => VibonoColors.gelb,
      Ampel.rot => VibonoColors.rot,
    };

/// Ampel-Skala 0 bis 4 kcal/g mit Markierung.
class AmpelBar extends StatelessWidget {
  const AmpelBar({super.key, required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => Column(children: [
        LayoutBuilder(builder: (context, c) {
          final x = (value / 4).clamp(0.0, 1.0) * c.maxWidth;
          return SizedBox(
            height: 18,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: 0,
                right: 0,
                top: 5,
                height: 8,
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(flex: 375, child: _seg(VibonoColors.green)),
                  const SizedBox(width: 2),
                  Expanded(flex: 250, child: _seg(VibonoColors.gelb)),
                  const SizedBox(width: 2),
                  Expanded(flex: 375, child: _seg(VibonoColors.rot)),
                ]),
              ),
              Positioned(
                left: x - 2,
                top: 0,
                child: Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(color: VibonoColors.grey900, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ]),
          );
        }),
        const SizedBox(height: 2),
        const Row(children: [
          Expanded(flex: 375, child: Text('0', style: _lab)),
          Expanded(flex: 250, child: Text('1,5', style: _lab)),
          Expanded(flex: 330, child: Text('2,5', style: _lab)),
          Text('4+', style: _lab),
        ]),
      ]);

  static const _lab = TextStyle(fontFamily: VibonoFonts.display, fontSize: 11, color: VibonoColors.grey500);

  Widget _seg(Color c) => DecoratedBox(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)));
}

/// Ampel-Punkt (grün, gelb, rot) zur Energiedichte.
class AmpelDot extends StatelessWidget {
  const AmpelDot(this.density, {super.key, this.size = 9});
  final double density;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: ampelColor(EnergyDensity.ampel(density)), shape: BoxShape.circle),
      );
}

/// Schmale Ampel-Skala 0 bis 3+ mit rundem Regler, für Zusammenfassungen.
class AmpelScale extends StatelessWidget {
  const AmpelScale({super.key, required this.value, this.width = 120});
  final double value;
  final double width;

  static const _max = 3.0;

  @override
  Widget build(BuildContext context) {
    final a = EnergyDensity.ampel(value);
    final x = (value / _max).clamp(0.0, 1.0) * width;
    const lab = TextStyle(fontFamily: VibonoFonts.body, fontSize: 10, color: VibonoColors.grey400);
    return Semantics(
      label: 'Energiedichte ${EnergyDensity.format(value, digits: 1)}, ${EnergyDensity.label(a)}',
      child: SizedBox(
        width: width,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 16,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: 0,
                right: 0,
                top: 4,
                height: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: const Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(flex: 15, child: ColoredBox(color: VibonoColors.green)),
                    SizedBox(width: 2),
                    Expanded(flex: 10, child: ColoredBox(color: VibonoColors.gelb)),
                    SizedBox(width: 2),
                    Expanded(flex: 5, child: ColoredBox(color: VibonoColors.rot)),
                  ]),
                ),
              ),
              Positioned(
                left: x - 8,
                top: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: a == Ampel.gelb ? const Color(0xFFD9C24A) : ampelColor(a), width: 3),
                    boxShadow: const [BoxShadow(color: Color(0x1A1C1C1C), blurRadius: 3, offset: Offset(0, 1))],
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 12,
            child: Stack(children: [
              const Positioned(left: 0, child: Text('0', style: lab)),
              Positioned(left: width * 0.5 - 8, child: const Text('1,5', style: lab)),
              Positioned(left: width * 0.833 - 13, child: const Text('2,5', style: lab)),
              const Positioned(right: 0, child: Text('3+', style: lab)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Ergebnisbox: große Zahl kcal/g + Ampel + Rat.
class EdResult extends StatelessWidget {
  const EdResult({super.key, required this.density, required this.detail, this.approx = false});
  final double density;
  final String detail;
  final bool approx;

  @override
  Widget build(BuildContext context) {
    final a = EnergyDensity.ampel(density);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: VibonoColors.green050, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Row(children: [
          SizedBox(
            width: 92,
            child: Column(children: [
              Text(
                '${approx ? '≈ ' : ''}${EnergyDensity.format(density)}',
                style: const TextStyle(
                  fontFamily: VibonoFonts.display,
                  fontSize: 34,
                  fontWeight: FontWeight.w300,
                  color: VibonoColors.grey900,
                ),
              ),
              const Text('kcal/g', style: VibonoText.small),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: ampelColor(a), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(EnergyDensity.label(a).toUpperCase(),
                    style: const TextStyle(
                      fontFamily: VibonoFonts.display,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: VibonoColors.grey800,
                    )),
              ]),
              const SizedBox(height: 3),
              Text('$detail ${EnergyDensity.advice(a)}', style: VibonoText.small.copyWith(color: VibonoColors.grey700)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        AmpelBar(value: density),
      ]),
    );
  }
}
