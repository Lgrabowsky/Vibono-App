import 'package:material_ui/material_ui.dart';

import '../data/models/content.dart';
import '../domain/recipe_picker.dart';
import 'screens/article_screen.dart';
import 'screens/recipe_detail_screen.dart';

/// Öffnet einen Inhalt passend zu seinem Typ.
Future<void> openContent(BuildContext context, ContentItem item) {
  final page = item.type == ContentType.recipe
      ? RecipeDetailScreen(recipeId: item.id, preview: item)
      : ArticleScreen(contentId: item.id, preview: item);
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

/// Rezept mit Portionen öffnen; mit [date] und [slot] aus dem Wochenplan,
/// dann werden geänderte Portionen dort gespeichert.
Future<void> openRecipe(BuildContext context, ContentItem recipe, {int? portions, DateTime? date, MealSlot? slot}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          RecipeDetailScreen(recipeId: recipe.id, preview: recipe, portions: portions, date: date, slot: slot),
    ));

Future<T?> push<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => page));
