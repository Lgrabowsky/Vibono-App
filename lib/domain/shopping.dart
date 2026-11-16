import 'week_plan.dart';

/// Ein Eintrag der Einkaufsliste, zusammengefasst über alle Mahlzeiten.
class ShoppingEntry {
  const ShoppingEntry({
    required this.id,
    required this.name,
    required this.group,
    this.amount,
    this.unit = '',
    this.recipes = const [],
    this.recipeId,
  });

  /// Stabil über Neuberechnungen hinweg (für die Häkchen).
  final String id;
  final String name;
  final String group;
  final double? amount;
  final String unit;

  /// Für welche Rezepte die Zutat gebraucht wird.
  final List<String> recipes;

  /// Gesetzt, wenn das Rezept keine Zutatenliste hat (Eintrag öffnet es).
  final int? recipeId;

  String get amountLabel => amount == null ? '' : Shopping.formatAmount(amount!, unit);
}

abstract final class Shopping {
  static const obstGemuese = 'Obst und Gemüse';
  static const kuehlregal = 'Kühlregal';
  static const fleischFisch = 'Fleisch und Fisch';
  static const vorrat = 'Vorrat und Konserven';
  static const gewuerze = 'Gewürze und Kräuter';
  static const sonstiges = 'Sonstiges';
  static const ohneListe = 'Rezepte ohne Zutatenliste';
  static const eigene = 'Eigene Einträge';
  static const basics = 'Grundausstattung';

  /// Grundausstattung für die Umstellungstage (Eiweiß und Gemüse).
  static const utBasics = [
    'Eier',
    'Magerquark und körniger Frischkäse',
    'Hähnchenbrust oder Pute',
    'Fisch (z. B. Kabeljau, Lachs)',
    'Gemüse für Suppen (Zucchini, Brokkoli, Paprika)',
    'Salat und Gurke',
    'Gemüse- oder Fleischbrühe',
    'Kräuter und Gewürze',
  ];

  /// Reihenfolge wie beim Gang durch den Supermarkt.
  static const groupOrder = [
    obstGemuese,
    kuehlregal,
    fleischFisch,
    vorrat,
    gewuerze,
    sonstiges,
    basics,
    ohneListe,
    eigene,
  ];

  static const _keywords = <String, List<String>>{
    vorrat: [
      'dose', 'glas', 'brühe', 'bruehe', 'fond', 'reis', 'nudel', 'spaghetti', 'hirse', 'quinoa', 'couscous',
      'bulgur', 'haferflocken', 'linsen', 'kichererbsen', 'kidneybohnen', 'mehl', 'öl', 'olivenöl', 'rapsöl', 'essig',
      'senf', 'tomatenmark', 'passierte', 'honig', 'zucker', 'süßstoff', 'brot', 'knäcke', 'nüsse', 'mandeln',
      'samen', 'kerne',
    ],
    kuehlregal: [
      'quark', 'joghurt', 'skyr', 'käse', 'kaese', 'gouda', 'feta', 'mozzarella', 'parmesan', 'frischkäse', 'milch',
      'sahne', 'butter', 'ei', 'eier', 'tofu', 'kefir', 'buttermilch', 'schmand', 'crème',
    ],
    fleischFisch: [
      'fleisch', 'hähnchen', 'haehnchen', 'huhn', 'pute', 'rind', 'schwein', 'hack', 'schinken', 'lachs', 'fisch',
      'kabeljau', 'seelachs', 'thunfisch', 'garnele', 'shrimps', 'forelle', 'filet',
    ],
    gewuerze: [
      'salz', 'pfeffer', 'paprikapulver', 'curry', 'kreuzkümmel', 'zimt', 'muskat', 'oregano', 'basilikum',
      'petersilie', 'schnittlauch', 'dill', 'koriander', 'thymian', 'rosmarin', 'kräuter', 'gewürz', 'chili',
    ],
    obstGemuese: [
      'paprika', 'kartoffel', 'zwiebel', 'knoblauch', 'tomate', 'karotte', 'möhre', 'zucchini', 'lauch', 'porree',
      'aubergine', 'brokkoli', 'blumenkohl', 'kohl', 'spinat', 'salat', 'gurke', 'sellerie', 'kürbis', 'pilz',
      'champignon', 'erbsen', 'bohnen', 'mais', 'ingwer', 'zitrone', 'limette', 'apfel', 'birne', 'banane',
      'beere', 'erdbeer', 'heidelbeer', 'himbeer', 'aprikose', 'pfirsich', 'orange', 'mango', 'kiwi', 'trauben',
      'rhabarber', 'radieschen', 'rucola', 'fenchel', 'spargel', 'avocado',
    ],
  };

  /// Regal für eine Zutat. Die Reihenfolge der Prüfung verhindert z. B.,
  /// dass „Tomaten aus der Dose“ beim Gemüse landet.
  static String groupFor(String name) {
    final n = name.toLowerCase();
    bool hit(String w) => w.length <= 3 ? RegExp('(^|[^a-zäöüß])$w([^a-zäöüß]|\$)').hasMatch(n) : n.contains(w);
    for (final g in [vorrat, kuehlregal, fleischFisch, gewuerze, obstGemuese]) {
      if (_keywords[g]!.any(hit)) return g;
    }
    return sonstiges;
  }

  /// Fasst die Zutaten aller Mahlzeiten zusammen und rechnet sie auf die
  /// geplanten Portionen um.
  static List<ShoppingEntry> aggregate(Iterable<PlannedMeal> meals) {
    final byKey = <String, _Acc>{};
    final noList = <int, _Acc>{};
    for (final m in meals) {
      final r = m.recipe;
      if (r == null) continue;
      if (r.ingredients.isEmpty) {
        noList.putIfAbsent(r.id, () => _Acc('Zutaten für „${r.title}“', ohneListe, '')).recipes.add(r.title);
        continue;
      }
      final factor = r.servings == null ? 1.0 : m.portions / r.servings!;
      for (final i in r.ingredients) {
        final unit = _baseUnit(i.unit);
        final k = '${_norm(i.name)}|$unit';
        final acc = byKey.putIfAbsent(k, () => _Acc(i.name, groupFor(i.name), unit));
        if (i.amount != null) acc.amount = (acc.amount ?? 0) + _toBase(i.amount!, i.unit) * factor;
        if (!acc.recipes.contains(r.title)) acc.recipes.add(r.title);
      }
    }
    final result = [
      for (final e in byKey.entries)
        ShoppingEntry(
          id: 'ing:${e.key}',
          name: e.value.name,
          group: groupOrder.contains(e.value.group) ? e.value.group : sonstiges,
          amount: e.value.amount,
          unit: e.value.unit,
          recipes: e.value.recipes,
        ),
      for (final e in noList.entries)
        ShoppingEntry(
          id: 'recipe:${e.key}',
          name: e.value.name,
          group: ohneListe,
          recipes: e.value.recipes,
          recipeId: e.key,
        ),
    ];
    result.sort((a, b) {
      final g = groupOrder.indexOf(a.group).compareTo(groupOrder.indexOf(b.group));
      return g != 0 ? g : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  static String _norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String _baseUnit(String u) => switch (u) {
        'kg' => 'g',
        'l' => 'ml',
        _ => u,
      };

  static double _toBase(double amount, String unit) => switch (unit) {
        'kg' || 'l' => amount * 1000,
        _ => amount,
      };

  /// „1,2 kg“, „350 g“, „2 EL“. Gerundet, damit sich die Liste gut liest.
  static String formatAmount(double amount, String unit) {
    String num(double v) {
      final s = v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
      return s.replaceAll('.', ',');
    }

    if (unit == 'g' || unit == 'ml') {
      if (amount >= 1000) return '${num((amount / 100).round() / 10)} ${unit == 'g' ? 'kg' : 'l'}';
      final step = amount < 10 ? 1 : (amount < 100 ? 5 : 10);
      final r = ((amount / step).round() * step).clamp(step, 1000);
      return '$r $unit';
    }
    final r = (amount * 2).round() / 2;
    final label = switch (unit) {
      'el' => 'EL',
      'tl' => 'TL',
      'stück' || 'stk' || '' => '',
      'pck' => 'Pck.',
      'msp' => 'Msp.',
      'prise' || 'bund' || 'dose' || 'becher' || 'glas' || 'scheibe' || 'zehe' || 'tasse' || 'handvoll' || 'kopf' ||
      'stange' || 'zweig' =>
        unit[0].toUpperCase() + unit.substring(1),
      _ => unit,
    };
    return label.isEmpty ? num(r < 0.5 ? 0.5 : r) : '${num(r < 0.5 ? 0.5 : r)} $label';
  }
}

class _Acc {
  _Acc(this.name, this.group, this.unit);
  final String name;
  final String group;
  final String unit;
  double? amount;
  final List<String> recipes = [];
}
