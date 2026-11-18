import '../data/models/energy.dart';

/// Kleine eingebaute Lebensmittelliste (Richtwerte kcal/100 g), damit der
/// Rechner auch offline funktioniert. Die vollständige Vibono-Datenbank
/// kommt über `GET /foods`.
abstract final class FoodDatabase {
  static const _raw = <String, double>{
    'Gurke': 12,
    'Kopfsalat': 14,
    'Tomate': 18,
    'Sellerie': 18,
    'Zucchini': 19,
    'Champignons': 22,
    'Tomaten aus der Dose': 22,
    'Spinat': 23,
    'Aubergine': 24,
    'Blumenkohl': 25,
    'Weißkohl': 25,
    'Lauch': 29,
    'Passierte Tomaten': 30,
    'Paprika': 31,
    'Erdbeeren': 32,
    'Brokkoli': 34,
    'Karotte': 36,
    'Zwiebel': 40,
    'Heidelbeeren': 42,
    'Kürbis (Butternut)': 45,
    'Orange': 47,
    'Joghurt 1,5 %': 47,
    'Milch 1,5 %': 47,
    'Apfel': 54,
    'Aprikosen': 43,
    'Hirse, gekocht': 120,
    'Magerquark': 67,
    'Kartoffeln, gekocht': 72,
    'Kokosmilch light': 75,
    'Kabeljau': 80,
    'Erbsen': 81,
    'Süßkartoffel': 86,
    'Kidneybohnen (Dose)': 90,
    'Banane': 93,
    'Hüttenkäse': 98,
    'Hähnchenbrust': 110,
    'Linsen, gekocht': 110,
    'Thunfisch im eigenen Saft': 110,
    'Saure Sahne': 115,
    'Rindfleisch, mager': 120,
    'Tofu': 120,
    'Reis, gekocht': 130,
    'Kichererbsen, gekocht': 140,
    'Vollkornnudeln, gekocht': 140,
    'Nudeln, gekocht': 150,
    'Ei': 155,
    'Kokosmilch': 180,
    'Lachs': 200,
    'Rinderhackfleisch': 210,
    'Vollkornbrot': 220,
    'Schmand': 240,
    'Pizza Margherita': 240,
    'Mozzarella': 255,
    'Feta': 270,
    'Sahne 30 %': 290,
    'Pommes frites': 290,
    'Honig': 304,
    'Rote Linsen, trocken': 340,
    'Gouda': 360,
    'Haferflocken': 370,
    'Zucker': 400,
    'Schokolade': 540,
    'Mandeln': 600,
    'Walnüsse': 690,
    'Butter': 741,
    'Olivenöl': 884,
    'Rapsöl': 884,
    'Gemüsebrühe': 5,
    'Fleischbrühe': 10,
  };

  static final all = [
    for (final e in _raw.entries) Food(id: 'local:${e.key}', name: e.key, kcalPer100g: e.value),
  ];

  static List<Food> search(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return const [];
    final starts = all.where((f) => f.name.toLowerCase().startsWith(s));
    final contains = all.where((f) => !f.name.toLowerCase().startsWith(s) && f.name.toLowerCase().contains(s));
    return [...starts, ...contains].take(12).toList();
  }
}
