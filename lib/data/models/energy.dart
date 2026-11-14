import 'json.dart';

class Food {
  const Food({required this.id, required this.name, required this.kcalPer100g});
  final String id;
  final String name;
  final double kcalPer100g;

  factory Food.fromJson(Json j) => Food(
        id: asString(j['id']) ?? '',
        name: asString(j['name']) ?? '',
        kcalPer100g: asDouble(j['kcal_per_100g']) ?? 0,
      );
}

/// Eine Zeile im Energiedichte-Rechner.
class Ingredient {
  const Ingredient({
    required this.name,
    this.grams,
    this.kcalPer100g,
    this.confidence = 1,
    this.rawText,
  });

  final String name;
  final double? grams;
  final double? kcalPer100g;

  /// 0..1, unter 0,7 markiert die App die Zeile gelb zum Nachprüfen.
  final double confidence;
  final String? rawText;

  bool get isComplete => grams != null && grams! > 0 && kcalPer100g != null;
  bool get needsReview => !isComplete || confidence < 0.7;
  double get kcal => isComplete ? grams! * kcalPer100g! / 100 : 0;

  Ingredient copyWith({String? name, double? grams, double? kcalPer100g, double? confidence}) => Ingredient(
        name: name ?? this.name,
        grams: grams ?? this.grams,
        kcalPer100g: kcalPer100g ?? this.kcalPer100g,
        confidence: confidence ?? this.confidence,
        rawText: rawText,
      );

  factory Ingredient.fromScanJson(Json j) => Ingredient(
        name: asString(j['name']) ?? '',
        grams: asDouble(j['amount_g']),
        kcalPer100g: asDouble(j['kcal_per_100g']),
        confidence: asDouble(j['confidence']) ?? 0.5,
        rawText: asString(j['raw_text']),
      );
}

class RecipeScanResult {
  const RecipeScanResult({this.title, this.servings, required this.ingredients});
  final String? title;
  final int? servings;
  final List<Ingredient> ingredients;

  factory RecipeScanResult.fromJson(Json j) => RecipeScanResult(
        title: asString(j['title']),
        servings: asInt(j['servings']),
        ingredients: asList(j['ingredients'], Ingredient.fromScanJson),
      );
}

class PhotoComponent {
  const PhotoComponent({required this.name, required this.sharePct});
  final String name;
  final double sharePct;
}

class PhotoAnalysisResult {
  const PhotoAnalysisResult({
    required this.dish,
    required this.portionG,
    required this.kcalTotal,
    required this.kcalPerG,
    required this.components,
    required this.confidence,
    required this.notes,
  });

  final String dish;
  final double portionG;
  final double kcalTotal;
  final double kcalPerG;
  final List<PhotoComponent> components;
  final double confidence;
  final String notes;

  factory PhotoAnalysisResult.fromJson(Json j) => PhotoAnalysisResult(
        dish: asString(j['dish']) ?? '',
        portionG: asDouble(j['portion_g']) ?? 0,
        kcalTotal: asDouble(j['kcal_total']) ?? 0,
        kcalPerG: asDouble(j['kcal_per_g']) ?? 0,
        components: asList(
          j['components'],
          (c) => PhotoComponent(name: asString(c['name']) ?? '', sharePct: asDouble(c['share_pct']) ?? 0),
        ),
        confidence: asDouble(j['confidence']) ?? 0.5,
        notes: asString(j['notes']) ?? '',
      );
}
