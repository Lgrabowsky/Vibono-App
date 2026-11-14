// Beispielinhalte für die Entwicklung ohne WordPress-Zugang.
// Fotos, Logo und Tipp-Titel stammen aus den Assets des Vibono
// Design-Systems; Rezepttexte und Mengen sind Platzhalter, bis die
// Inhalte über die Schnittstelle aus WordPress kommen.

const mockRecipes = <Map<String, dynamic>>[
  {
    'id': 9001,
    'title': 'Quark-Frühstück mit Obst und Heidelbeeren',
    'thumbnail_url': 'asset:assets/images/recipe-1.png',
    'tags': ['fruehstueck', 'vegetarisch', 'schnell'],
    'energy_density': 0.9,
    'servings': 2,
    'ingredients': [
      ['Magerquark', 200, 67],
      ['Heidelbeeren', 80, 42],
      ['Aprikosen', 80, 43],
      ['Haferflocken', 20, 370],
    ],
  },
  {
    'id': 9002,
    'title': 'Gemüsegulasch mit Reis und Kräuterquark',
    'thumbnail_url': 'asset:assets/images/recipe-2.png',
    'tags': ['mittag', 'abend', 'vegetarisch'],
    'energy_density': 0.6,
    'servings': 2,
    'ingredients': [
      ['Paprika', 300, 31],
      ['Kartoffeln, gekocht', 200, 72],
      ['Zwiebel', 100, 40],
      ['Tomaten aus der Dose', 400, 22],
      ['Reis, gekocht', 150, 130],
      ['Magerquark', 100, 67],
    ],
  },
  {
    'id': 9003,
    'title': 'Asiatische Gemüsesuppe mit Nudeln',
    'thumbnail_url': 'asset:assets/images/recipe-3.png',
    'tags': ['mittag', 'abend', 'vegan', 'suppe'],
    'energy_density': 0.8,
    'servings': 2,
    'ingredients': [
      ['Karotte', 150, 36],
      ['Zucchini', 150, 19],
      ['Lauch', 80, 29],
      ['Gemüsebrühe', 500, 5],
      ['Nudeln, gekocht', 150, 150],
    ],
  },
  {
    'id': 9004,
    'title': 'Erdbeer-Quark mit Hirse',
    'thumbnail_url': 'asset:assets/images/recipe-4.png',
    'tags': ['fruehstueck', 'vegetarisch', 'schnell'],
    'energy_density': 0.8,
    'servings': 2,
    'ingredients': [
      ['Erdbeeren', 200, 32],
      ['Magerquark', 150, 67],
      ['Hirse, gekocht', 60, 120],
    ],
  },
  {
    'id': 9005,
    'title': 'Fleischbrühe mit Kichererbsen und Erbsen',
    'thumbnail_url': 'asset:assets/images/recipe-5.png',
    'tags': ['mittag', 'abend', 'ut-geeignet', 'suppe', 'fleisch'],
    'energy_density': 0.4,
    'servings': 2,
    'ingredients': [
      ['Fleischbrühe', 600, 10],
      ['Rindfleisch, mager', 120, 120],
      ['Erbsen', 100, 81],
      ['Kichererbsen, gekocht', 80, 140],
    ],
  },
  {
    'id': 9006,
    'title': 'Gefüllte Aubergine mit Hirse und Käse',
    'thumbnail_url': 'asset:assets/images/recipe-6.png',
    'tags': ['mittag', 'abend', 'vegetarisch'],
    'energy_density': 1.0,
    'servings': 2,
    'ingredients': [
      ['Aubergine', 400, 24],
      ['Hirse, gekocht', 120, 120],
      ['Tomate', 150, 18],
      ['Gouda', 40, 360],
    ],
  },
];

const mockTips = <Map<String, dynamic>>[
  {
    'id': 9101,
    'title': 'Wie mein innerer Schweinehund zu seinem Namen kam',
    'thumbnail_url': 'asset:assets/images/tip-1.png',
    'tags': ['motivation'],
    'reading_minutes': 4,
  },
  {
    'id': 9102,
    'title': 'Verschiedene Körperfettarten',
    'thumbnail_url': 'asset:assets/images/tip-2.png',
    'tags': ['wissen'],
    'reading_minutes': 5,
  },
];

const mockTipsOfTheDay = <String>[
  'Fülle den Teller zur Hälfte mit Gemüse.',
  'Trink vor jeder Mahlzeit ein großes Glas Wasser.',
  'Iss langsam. Das Sattgefühl braucht rund 20 Minuten.',
  'Eine Suppe vorweg macht satt und hat kaum Kalorien.',
  'Plane morgen schon heute: Was gibt es zum Frühstück?',
  'Geh nach dem Essen 10 Minuten spazieren.',
  'Satt essen ist erlaubt, mit grünen Lebensmitteln sogar erwünscht.',
  'Schreib auf, wofür du abnehmen möchtest, und häng den Zettel sichtbar auf.',
];

/// Platzhalter-Text für Beiträge, bis der echte Inhalt aus WordPress kommt.
String mockArticleHtml(String title) => '''
<p>Dieser Text ist ein Platzhalter. In der fertigen App steht hier der Beitrag aus „Mein Coaching“ auf vibono.de, geladen über die Vibono-Schnittstelle.</p>
<p>Beim Vibono-Konzept geht es nicht um Verzicht, sondern darum, dich mit den richtigen Lebensmitteln satt zu essen. Lebensmittel mit niedriger Energiedichte, also wenig Kalorien pro Gramm, füllen den Magen und machen lange satt.</p>
<p>Gemüse, Salat, Obst, Suppen, magere Milchprodukte und mageres Fleisch oder Fisch sind deshalb die Basis. Fette Soßen, Süßes und Knabbereien genießt du bewusst in kleinen Mengen.</p>
<p>Wichtig ist, dass du drei Mal am Tag richtig satt wirst. Wer zwischendurch hungrig ist, greift schneller zu Snacks. Plane deine Mahlzeiten deshalb vor und koche, wenn möglich, gleich für zwei Tage.</p>
<p>Bewegung unterstützt dich dabei, ist aber nicht das Wichtigste. Fang klein an: 10 Minuten zügiges Gehen nach dem Essen sind ein guter Start.</p>
<p>Und wenn es mal nicht klappt? Kein Problem. Jeder Tag ist eine neue Chance. Wichtig ist, dass du dranbleibst.</p>
<p>Wenn du diesen Beitrag bis hierhin gelesen hast, bekommst du deine Lesepunkte gutgeschrieben.</p>
''';

String mockRecipeHtml(Map<String, dynamic> r) {
  final ing = (r['ingredients'] as List).map((i) => '<li>${i[1]} g ${i[0]}</li>').join();
  return '''
<h3>Zutaten (2 Portionen)</h3>
<ul>$ing</ul>
<h3>Zubereitung</h3>
<p>Platzhalter: Die Zubereitungsschritte kommen aus dem Rezept auf vibono.de.</p>
<ol><li>Zutaten vorbereiten und klein schneiden.</li><li>Nach Rezept garen und abschmecken.</li><li>Auf zwei Teller verteilen und satt essen.</li></ol>
''';
}
