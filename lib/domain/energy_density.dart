import '../data/models/energy.dart';

/// Vibono-Ampel für die Energiedichte (kcal/g):
/// grün bis 1,5 · gelb bis 2,5 · rot darüber.
enum Ampel { gruen, gelb, rot }

abstract final class EnergyDensity {
  static const greenMax = 1.5;
  static const yellowMax = 2.5;

  static Ampel ampel(double kcalPerG) => kcalPerG <= greenMax
      ? Ampel.gruen
      : kcalPerG <= yellowMax
          ? Ampel.gelb
          : Ampel.rot;

  static String label(Ampel a) => switch (a) {
        Ampel.gruen => 'grün',
        Ampel.gelb => 'gelb',
        Ampel.rot => 'rot',
      };

  /// Konkreter Rat zum Ergebnis, im Vibono-Ton (Genuss statt Verzicht).
  static String advice(Ampel a) => switch (a) {
        Ampel.gruen => 'Abnehmtauglich. Davon darfst du dich richtig satt essen.',
        Ampel.gelb =>
          'Okay in normalen Mengen. Mit mehr Gemüse oder etwas weniger Fett rutscht es in den grünen Bereich.',
        Ampel.rot =>
          'Lieber als kleine Beilage genießen. Kombiniere es mit viel Gemüse, Salat oder Suppe, dann wirst du satt.',
      };

  static ({double grams, double kcal, double? density}) compute(Iterable<Ingredient> items) {
    var g = 0.0;
    var k = 0.0;
    for (final i in items) {
      if (!i.isComplete) continue;
      g += i.grams!;
      k += i.kcal;
    }
    return (grams: g, kcal: k, density: g > 0 ? k / g : null);
  }

  /// Deutsche Zahl mit Komma: 0,79
  static String format(double v, {int digits = 2}) {
    var s = v.toStringAsFixed(digits);
    if (digits > 1 && s.endsWith('0')) s = s.substring(0, s.length - 1);
    return s.replaceAll('.', ',');
  }
}
