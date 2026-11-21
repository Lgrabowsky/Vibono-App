/// Jahreszeit und Saisonkalender für Obst und Gemüse aus Deutschland
/// (Freiland und Lager, vereinfacht). Grundlage für Rezeptvorschläge und
/// „Probier mal was aus mit …“.
enum Season { fruehling, sommer, herbst, winter }

extension SeasonX on Season {
  String get label => switch (this) {
        Season.fruehling => 'Frühling',
        Season.sommer => 'Sommer',
        Season.herbst => 'Herbst',
        Season.winter => 'Winter',
      };
}

abstract final class SeasonCalendar {
  static Season seasonOf(DateTime d) => switch (d.month) {
        3 || 4 || 5 => Season.fruehling,
        6 || 7 || 8 => Season.sommer,
        9 || 10 || 11 => Season.herbst,
        _ => Season.winter,
      };

  /// Saisonware je Monat (1 = Januar). Namen so, wie sie in Zutatenlisten stehen.
  static const _byMonth = <int, List<String>>{
    1: ['Grünkohl', 'Rosenkohl', 'Lauch', 'Rotkohl', 'Weißkohl', 'Wirsing', 'Pastinake', 'Rote Bete', 'Feldsalat', 'Chicorée', 'Schwarzwurzel', 'Karotte', 'Sellerie', 'Apfel', 'Birne'],
    2: ['Grünkohl', 'Rosenkohl', 'Lauch', 'Rotkohl', 'Weißkohl', 'Wirsing', 'Pastinake', 'Rote Bete', 'Feldsalat', 'Chicorée', 'Schwarzwurzel', 'Karotte', 'Sellerie', 'Apfel'],
    3: ['Lauch', 'Spinat', 'Feldsalat', 'Bärlauch', 'Chicorée', 'Rote Bete', 'Karotte', 'Pastinake', 'Weißkohl', 'Apfel'],
    4: ['Spargel', 'Bärlauch', 'Spinat', 'Rhabarber', 'Radieschen', 'Frühlingszwiebel', 'Kopfsalat', 'Lauch', 'Apfel'],
    5: ['Spargel', 'Rhabarber', 'Radieschen', 'Kohlrabi', 'Spinat', 'Mangold', 'Kopfsalat', 'Frühlingszwiebel', 'Erdbeeren'],
    6: ['Spargel', 'Erdbeeren', 'Kohlrabi', 'Zucchini', 'Erbsen', 'Blumenkohl', 'Brokkoli', 'Gurke', 'Kirschen', 'Johannisbeeren', 'Mangold'],
    7: ['Zucchini', 'Tomate', 'Gurke', 'Paprika', 'Bohnen', 'Blumenkohl', 'Brokkoli', 'Heidelbeeren', 'Himbeeren', 'Kirschen', 'Aprikosen', 'Mangold'],
    8: ['Tomate', 'Zucchini', 'Aubergine', 'Paprika', 'Bohnen', 'Mais', 'Gurke', 'Heidelbeeren', 'Brombeeren', 'Pflaumen', 'Aprikosen', 'Mirabellen'],
    9: ['Kürbis', 'Tomate', 'Paprika', 'Aubergine', 'Zucchini', 'Brokkoli', 'Blumenkohl', 'Pflaumen', 'Zwetschgen', 'Birne', 'Apfel', 'Weintrauben'],
    10: ['Kürbis', 'Rote Bete', 'Pastinake', 'Mangold', 'Fenchel', 'Lauch', 'Rotkohl', 'Weißkohl', 'Wirsing', 'Pilze', 'Apfel', 'Birne', 'Quitte'],
    11: ['Kürbis', 'Grünkohl', 'Rosenkohl', 'Rote Bete', 'Pastinake', 'Lauch', 'Rotkohl', 'Wirsing', 'Feldsalat', 'Topinambur', 'Steckrübe', 'Apfel', 'Birne'],
    12: ['Grünkohl', 'Rosenkohl', 'Rotkohl', 'Wirsing', 'Lauch', 'Pastinake', 'Rote Bete', 'Feldsalat', 'Steckrübe', 'Topinambur', 'Chicorée', 'Apfel'],
  };

  /// Gemüse und Obst, das gerade Saison hat.
  static List<String> produce(DateTime d) => _byMonth[d.month] ?? const [];

  /// Kalenderwoche (ISO), für Wechsel im Wochentakt.
  static int isoWeek(DateTime d) {
    final date = DateTime.utc(d.year, d.month, d.day);
    final thursday = date.add(Duration(days: DateTime.thursday - date.weekday));
    return 1 + thursday.difference(DateTime.utc(thursday.year)).inDays ~/ 7;
  }

  /// „Probier mal was aus mit …“: wechselt wöchentlich durch die Saisonware.
  static String spotlightOf(DateTime d) {
    final p = produce(d);
    if (p.isEmpty) return 'Gemüse';
    return p[(isoWeek(d) * 5 + d.year) % p.length];
  }

  /// Zutat passt zu einem Saison-Lebensmittel („Rote Bete, gekocht“ → Rote Bete).
  static bool matches(String ingredient, String produce) {
    final a = _norm(ingredient);
    final b = _norm(produce);
    if (b.isEmpty) return false;
    if (a.contains(b)) return true;
    // Einfache Pluralformen: Karotten, Tomaten, Erdbeere.
    final stem = b.endsWith('e') || b.endsWith('n') ? b.substring(0, b.length - 1) : b;
    return stem.length >= 4 && a.contains(stem);
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss')
      .replaceAll('-', ' ')
      .trim();
}
