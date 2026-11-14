import 'package:material_ui/material_ui.dart';

import '../data/models/content.dart';
import 'screens/article_screen.dart';
import 'screens/recipe_detail_screen.dart';

/// Öffnet einen Inhalt passend zu seinem Typ.
Future<void> openContent(BuildContext context, ContentItem item) {
  final page = item.type == ContentType.recipe
      ? RecipeDetailScreen(recipeId: item.id, preview: item)
      : ArticleScreen(contentId: item.id, preview: item);
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

Future<T?> push<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => page));
