/// Hilfen für Wunschgewicht und Etappenziele.
abstract final class Goals {
  /// Gesundes Tempo: etwa 0,5 kg pro Woche, ab 12 Monaten etwas weniger.
  static ({double m3, double m6, double m12}) suggest(double currentKg) {
    double r(double v) => (v * 2).roundToDouble() / 2;
    final m3 = r(currentKg - 0.5 * 13);
    final m6 = r(currentKg - 0.5 * 26 * 0.9);
    final m12 = r(currentKg - 0.5 * 52 * 0.7);
    return (m3: m3, m6: m6, m12: m12);
  }

  /// Bewertung des gewählten Tempos (kg pro Woche bis zum 12-Monats-Ziel).
  static String feedback(double currentKg, double target3m, double target12m) {
    final perWeek3 = (currentKg - target3m) / 13;
    if (target3m >= currentKg || target12m >= currentKg) {
      return 'Deine Ziele liegen nicht unter deinem aktuellen Gewicht. Passe sie gern noch an.';
    }
    if (perWeek3 > 1.0) {
      return 'Ganz schön sportlich! Das sind über 1 kg pro Woche. Langsamer hält besser.';
    }
    return 'Realistisch! Das sind etwa ${perWeek3.toStringAsFixed(1).replaceAll('.', ',')} kg pro Woche.';
  }
}
