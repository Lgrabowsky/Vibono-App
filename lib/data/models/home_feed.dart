import 'json.dart';

/// Art einer Challenge (`Challenge.kind` im Vertrag).
enum ChallengeKind { weightLoss, dailyGoal, collect }

ChallengeKind? challengeKindFrom(String? s) => switch (s) {
      'weight_loss' => ChallengeKind.weightLoss,
      'daily_goal' => ChallengeKind.dailyGoal,
      'collect' => ChallengeKind.collect,
      _ => null,
    };

/// Challenge auf der Startseite, z. B. „7 kg bis Weihnachten“. Die Teilnahme
/// liegt in der Sync-Sammlung `challenges`, den Fortschritt rechnet die App.
class Challenge {
  const Challenge({
    required this.id,
    required this.kind,
    required this.title,
    this.description = '',
    this.thumbnailUrl,
    required this.target,
    required this.unit,
    this.dailyTarget,
    this.startsOn,
    this.endsOn,
    this.recipeTags = const [],
    this.recipeMaxEd,
    this.suggestions = const [],
  });

  final int id;
  final ChallengeKind kind;
  final String title;
  final String description;
  final String? thumbnailUrl;

  /// Abnehmziel in kg, Anzahl Tage (Tagesziel) oder Anzahl (Sammeln).
  final double target;
  final String unit;

  /// Nur Tagesziel: so viel pro Tag (z. B. 5 Portionen).
  final int? dailyTarget;
  final DateTime? startsOn;
  final DateTime? endsOn;

  /// Rezepte mit diesen Schlagwörtern schlägt die App während der Challenge vor.
  final List<String> recipeTags;
  final double? recipeMaxEd;

  /// Nur Sammeln: Ideen zum Antippen.
  final List<String> suggestions;

  static Challenge? tryParse(Json j) {
    final kind = challengeKindFrom(asString(j['kind']));
    final target = asDouble(j['target']);
    if (kind == null || target == null || target <= 0) return null;
    return Challenge(
      id: asInt(j['id']) ?? 0,
      kind: kind,
      title: asString(j['title']) ?? '',
      description: asString(j['description']) ?? '',
      thumbnailUrl: asString(j['thumbnail_url']),
      target: target,
      unit: asString(j['unit']) ?? '',
      dailyTarget: asInt(j['daily_target']),
      startsOn: DateTime.tryParse(asString(j['starts_on']) ?? ''),
      endsOn: DateTime.tryParse(asString(j['ends_on']) ?? ''),
      recipeTags: asStringList(j['recipe_tags']),
      recipeMaxEd: asDouble(j['recipe_max_ed']),
      suggestions: asStringList(j['suggestions']),
    );
  }
}

/// Art einer Meldung im Bereich „News“.
enum NewsKind { blog, offer, club, coachingLetter, ebook, info }

NewsKind? newsKindFrom(String? s) => switch (s) {
      'blog' => NewsKind.blog,
      'offer' => NewsKind.offer,
      'club' => NewsKind.club,
      'coaching_letter' => NewsKind.coachingLetter,
      'ebook' => NewsKind.ebook,
      'info' => NewsKind.info,
      _ => null,
    };

extension NewsKindX on NewsKind {
  String get label => switch (this) {
        NewsKind.blog => 'Neu im Blog',
        NewsKind.offer => 'Angebot',
        NewsKind.club => 'Aus dem Club',
        NewsKind.coachingLetter => 'Coaching-Brief',
        NewsKind.ebook => 'Neues eBook',
        NewsKind.info => 'Hinweis',
      };
}

class NewsItem {
  const NewsItem({
    required this.id,
    required this.kind,
    required this.title,
    this.excerpt = '',
    this.thumbnailUrl,
    this.url,
    this.contentId,
    this.cta,
    this.publishedOn,
    this.endsOn,
  });

  final String id;
  final NewsKind kind;
  final String title;
  final String excerpt;
  final String? thumbnailUrl;
  final String? url;

  /// Gesetzt, wenn die App den Beitrag selbst anzeigen kann (Leseansicht).
  final int? contentId;
  final String? cta;
  final DateTime? publishedOn;
  final DateTime? endsOn;

  static NewsItem? tryParse(Json j) {
    final kind = newsKindFrom(asString(j['kind']));
    final title = asString(j['title']) ?? '';
    if (kind == null || title.isEmpty) return null;
    return NewsItem(
      id: asString(j['id']) ?? title,
      kind: kind,
      title: title,
      excerpt: asString(j['excerpt']) ?? '',
      thumbnailUrl: asString(j['thumbnail_url']),
      url: asString(j['url']),
      contentId: asInt(j['content_id']),
      cta: asString(j['cta']),
      publishedOn: DateTime.tryParse(asString(j['published_on']) ?? ''),
      endsOn: DateTime.tryParse(asString(j['ends_on']) ?? ''),
    );
  }
}

/// Quizfrage des Tages.
class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.question,
    required this.answers,
    required this.correct,
    this.explanation = '',
  });

  final String id;
  final String question;
  final List<String> answers;
  final int correct;
  final String explanation;

  static QuizQuestion? tryParse(Json? j) {
    if (j == null) return null;
    final answers = asStringList(j['answers']);
    final correct = asInt(j['correct']) ?? -1;
    final q = asString(j['question']) ?? '';
    if (q.isEmpty || answers.length < 2 || correct < 0 || correct >= answers.length) return null;
    return QuizQuestion(
      id: asString(j['id']) ?? q,
      question: q,
      answers: answers,
      correct: correct,
      explanation: asString(j['explanation']) ?? '',
    );
  }
}

/// `GET /home`: redaktionelle Vorgaben und Inhalte für die Startseite.
/// Rezeptvorschläge, Saison, Wetter und Fortschritt rechnet die App selbst.
class HomeFeed {
  const HomeFeed({
    this.keywords = const [],
    this.spotlight,
    this.quiz,
    this.challenges = const [],
    this.news = const [],
  });

  /// Stichwörter vom Vibono-Team, z. B. „Kürbis“ in der Kürbiswoche.
  final List<String> keywords;

  /// „Probier mal was aus mit …“, vom Team vorgegeben. `null` = Saison.
  final String? spotlight;
  final QuizQuestion? quiz;
  final List<Challenge> challenges;
  final List<NewsItem> news;

  static const empty = HomeFeed();

  factory HomeFeed.fromJson(Json j) {
    final food = asMap(j['food']) ?? const {};
    final plan = asMap(j['plan']) ?? const {};
    final spot = asString(asMap(food['spotlight'])?['name'])?.trim();
    return HomeFeed(
      keywords: asStringList(food['keywords']),
      spotlight: spot == null || spot.isEmpty ? null : spot,
      quiz: QuizQuestion.tryParse(asMap(plan['quiz'])),
      challenges: [
        for (final c in (j['challenges'] is List ? j['challenges'] as List : const []))
          if (c is Map) ?Challenge.tryParse(Json.from(c)),
      ],
      news: [
        for (final n in (j['news'] is List ? j['news'] as List : const []))
          if (n is Map) ?NewsItem.tryParse(Json.from(n)),
      ],
    );
  }
}
