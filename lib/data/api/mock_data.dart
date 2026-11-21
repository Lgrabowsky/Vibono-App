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
  // Saisonrezepte für Herbst und Winter (ohne Foto, bis echte Rezepte kommen).
  {
    'id': 9007,
    'title': 'Kürbissuppe mit Ingwer',
    'tags': ['mittag', 'abend', 'vegan', 'suppe', 'warm'],
    'energy_density': 0.4,
    'servings': 2,
    'ingredients': [
      ['Hokkaido-Kürbis', 500, 63],
      ['Karotte', 150, 36],
      ['Zwiebel', 80, 40],
      ['Ingwer', 10, 80],
      ['Gemüsebrühe', 600, 5],
    ],
  },
  {
    'id': 9008,
    'title': 'Grünkohl-Kartoffel-Eintopf',
    'tags': ['mittag', 'abend', 'vegetarisch', 'eintopf', 'warm', 'gemuese'],
    'energy_density': 0.6,
    'servings': 2,
    'ingredients': [
      ['Grünkohl', 400, 49],
      ['Kartoffeln, gekocht', 300, 72],
      ['Zwiebel', 80, 40],
      ['Gemüsebrühe', 400, 5],
      ['Senf', 10, 90],
    ],
  },
  {
    'id': 9009,
    'title': 'Ofengemüse mit Roter Bete und Kräuterquark',
    'tags': ['mittag', 'abend', 'vegetarisch', 'ofen', 'gemuese'],
    'energy_density': 0.7,
    'servings': 2,
    'ingredients': [
      ['Rote Bete', 300, 43],
      ['Pastinake', 200, 75],
      ['Karotte', 200, 36],
      ['Magerquark', 150, 67],
      ['Rapsöl', 10, 884],
    ],
  },
  {
    'id': 9010,
    'title': 'Feldsalat mit Apfel und Birne',
    'tags': ['mittag', 'abend', 'vegan', 'salat', 'schnell', 'gemuese', 'obst'],
    'energy_density': 0.5,
    'servings': 2,
    'ingredients': [
      ['Feldsalat', 150, 14],
      ['Apfel', 150, 52],
      ['Birne', 150, 57],
      ['Gurke', 150, 12],
      ['Walnüsse', 15, 654],
    ],
  },
  {
    'id': 9011,
    'title': 'Warmer Apfel-Zimt-Porridge',
    'tags': ['fruehstueck', 'vegetarisch', 'warm', 'obst'],
    'energy_density': 0.9,
    'servings': 2,
    'ingredients': [
      ['Haferflocken', 60, 370],
      ['Milch 1,5 %', 400, 47],
      ['Apfel', 200, 52],
      ['Zimt', 2, 250],
    ],
  },
  {
    'id': 9012,
    'title': 'Rosenkohl-Pfanne mit Hähnchen',
    'tags': ['mittag', 'abend', 'fleisch', 'ut-geeignet', 'gemuese'],
    'energy_density': 0.7,
    'servings': 2,
    'ingredients': [
      ['Rosenkohl', 400, 43],
      ['Hähnchenbrust', 250, 110],
      ['Zwiebel', 80, 40],
      ['Gemüsebrühe', 100, 5],
    ],
  },
];

/// Beispiel-Challenges für „Aktuelle Challenge“. Daten relativ zu heute,
/// damit die Demo immer eine laufende Challenge zeigt.
List<Map<String, dynamic>> mockChallenges(DateTime today) {
  String d(DateTime x) => x.toIso8601String().substring(0, 10);
  final christmas = DateTime(today.month == 12 && today.day > 24 ? today.year + 1 : today.year, 12, 24);
  return [
    {
      'id': 9301,
      'kind': 'weight_loss',
      'title': '7 kg bis Weihnachten',
      'description': 'Bis Heiligabend 7 Kilo leichter, mit Genuss statt Verzicht. Die App schlägt dir dafür besonders grüne Rezepte vor.',
      'target': 7,
      'unit': 'kg',
      'starts_on': d(today.subtract(const Duration(days: 20))),
      'ends_on': d(christmas),
      'recipe_tags': <String>[],
      'recipe_max_ed': 0.7,
    },
    {
      'id': 9302,
      'kind': 'daily_goal',
      'title': 'Obst-/Gemüse-Challenge',
      'description': '5 Portionen Obst und Gemüse am Tag, an 14 Tagen. Eine Portion ist eine Handvoll.',
      'target': 14,
      'daily_target': 5,
      'unit': 'Portionen',
      'starts_on': d(today.subtract(const Duration(days: 5))),
      'ends_on': d(today.add(const Duration(days: 30))),
      'recipe_tags': ['gemuese', 'obst', 'salat'],
    },
    {
      'id': 9303,
      'kind': 'collect',
      'title': '5 Lebensmittel',
      'description': 'Probier 5 Lebensmittel, die du noch nie oder lange nicht gegessen hast. Grüne Energiedichte zählt doppelt gut.',
      'target': 5,
      'unit': 'Lebensmittel',
      'starts_on': d(today.subtract(const Duration(days: 2))),
      'ends_on': d(today.add(const Duration(days: 12))),
      'suggestions': ['Pastinake', 'Topinambur', 'Steckrübe', 'Schwarzwurzel', 'Rote Bete', 'Grünkohl', 'Quitte'],
    },
  ];
}

/// Beispiel-Meldungen für „News“. Titel sind Platzhalter.
List<Map<String, dynamic>> mockNews(DateTime today) {
  String d(int daysAgo) => today.subtract(Duration(days: daysAgo)).toIso8601String().substring(0, 10);
  return [
    {
      'id': 'blog:9102',
      'kind': 'blog',
      'title': 'Verschiedene Körperfettarten',
      'excerpt': 'Warum nicht jedes Fett gleich ist und was das fürs Abnehmen bedeutet.',
      'thumbnail_url': 'asset:assets/images/tip-2.png',
      'url': 'https://www.vibono.de/tipps/',
      'content_id': 9102,
      'published_on': d(1),
    },
    {
      'id': 'coaching_letter:1',
      'kind': 'coaching_letter',
      'title': 'Coaching-Brief: Gut durch die Adventszeit',
      'excerpt': 'Plätzchen, Glühwein, Weihnachtsfeier: So bleibst du entspannt auf Kurs.',
      'url': 'https://www.vibono.de/coaching-briefe/',
      'cta': 'Brief lesen',
      'published_on': d(3),
    },
    {
      'id': 'club:1',
      'kind': 'club',
      'title': 'Im Club: Live-Fragestunde am Donnerstag',
      'excerpt': 'Stell deine Fragen rund ums Satt-Essen. Die Aufzeichnung gibt es danach im Club.',
      'url': 'https://www.vibono.de/',
      'cta': 'Zum Club',
      'published_on': d(2),
    },
    {
      'id': 'ebook:1',
      'kind': 'ebook',
      'title': 'Neues eBook: Satt durch den Winter',
      'excerpt': '30 wärmende Rezepte mit grüner Energiedichte.',
      'url': 'https://www.vibono.de/shop/',
      'cta': 'Ansehen',
      'published_on': d(5),
    },
    {
      'id': 'offer:1',
      'kind': 'offer',
      'title': 'Aktion: Gewürz-Set zum Adventspreis',
      'excerpt': 'Nur für kurze Zeit im Vibono-Shop.',
      'url': 'https://www.vibono.de/shop/',
      'cta': 'Zum Angebot',
      'published_on': d(0),
      'ends_on': today.add(const Duration(days: 7)).toIso8601String().substring(0, 10),
    },
  ];
}

/// Fragen fürs Quiz des Tages (wie der Standard-Pool im Plugin).
const mockQuiz = <Map<String, dynamic>>[
  {
    'id': 'ed-gurke',
    'question': 'Welches Lebensmittel hat die niedrigste Energiedichte?',
    'answers': ['Gurke', 'Banane', 'Vollkornbrot'],
    'correct': 0,
    'explanation': 'Gurke hat nur rund 0,1 kcal pro Gramm. Davon kannst du dich richtig satt essen.',
  },
  {
    'id': 'ed-ampel',
    'question': 'Ab welcher Energiedichte ist ein Lebensmittel bei Vibono „grün“?',
    'answers': ['bis 1,5 kcal/g', 'bis 2,5 kcal/g', 'bis 4 kcal/g'],
    'correct': 0,
    'explanation': 'Grün heißt: bis 1,5 kcal pro Gramm. Davon darfst du essen, bis du satt bist.',
  },
  {
    'id': 'satt-zeit',
    'question': 'Wie lange braucht das Sattgefühl ungefähr, bis es ankommt?',
    'answers': ['5 Minuten', '20 Minuten', '1 Stunde'],
    'correct': 1,
    'explanation': 'Rund 20 Minuten. Wer langsam isst, merkt rechtzeitig, dass er satt ist.',
  },
  {
    'id': 'suppe',
    'question': 'Warum ist eine Suppe als Vorspeise eine gute Idee?',
    'answers': ['Sie füllt den Magen mit wenig Kalorien', 'Sie beschleunigt den Stoffwechsel', 'Sie ersetzt das Trinken'],
    'correct': 0,
    'explanation': 'Viel Volumen, wenig Kalorien: Eine klare Gemüsesuppe vorweg macht schon halb satt.',
  },
  {
    'id': 'mahlzeiten',
    'question': 'Wie oft am Tag solltest du dich bei Vibono richtig satt essen?',
    'answers': ['Einmal', 'Dreimal', 'So selten wie möglich'],
    'correct': 1,
    'explanation': 'Dreimal satt essen. Wer zwischendurch hungrig ist, greift schneller zu Snacks.',
  },
  {
    'id': 'kaese',
    'question': 'Welche Energiedichte-Farbe hat Gouda?',
    'answers': ['Grün', 'Gelb', 'Rot'],
    'correct': 2,
    'explanation': 'Mit rund 3,6 kcal/g ist Gouda rot. Genießen ist erlaubt, nur eben in kleinen Mengen.',
  },
  {
    'id': 'wasser',
    'question': 'Was hilft vor dem Essen gegen zu großen Hunger?',
    'answers': ['Ein großes Glas Wasser', 'Ein Schokoriegel', 'Nichts trinken'],
    'correct': 0,
    'explanation': 'Ein großes Glas Wasser vor dem Essen füllt den Magen ganz ohne Kalorien.',
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
