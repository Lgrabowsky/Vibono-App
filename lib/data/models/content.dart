import 'json.dart';

enum ContentType { lesson, recipe, tip, tipOfTheDay }

ContentType contentTypeFrom(String? s) => switch (s) {
      'recipe' => ContentType.recipe,
      'tip' => ContentType.tip,
      'tip_of_the_day' => ContentType.tipOfTheDay,
      _ => ContentType.lesson,
    };

/// Entspricht `ContentSummary` / `ContentDetail` im API-Vertrag.
class ContentItem {
  const ContentItem({
    required this.id,
    required this.type,
    required this.title,
    this.excerpt = '',
    this.thumbnailUrl,
    this.url,
    this.tags = const [],
    this.lessonKind,
    this.courseId,
    this.energyDensity,
    this.readingMinutes,
    this.pointsForReading = 0,
    this.requiresMembership = false,
    this.locked = false,
    this.done,
    this.contentHtml,
    this.wordCount,
  });

  final int id;
  final ContentType type;
  final String title;
  final String excerpt;

  /// `asset:` = Bild aus dem App-Bundle (nur Mocks), sonst https-URL.
  final String? thumbnailUrl;
  final String? url;
  final List<String> tags;
  final String? lessonKind;
  final int? courseId;
  final double? energyDensity;
  final int? readingMinutes;
  final int pointsForReading;
  final bool requiresMembership;
  final bool locked;
  final bool? done;
  final String? contentHtml;
  final int? wordCount;

  factory ContentItem.fromJson(Json j) => ContentItem(
        id: asInt(j['id']) ?? 0,
        type: contentTypeFrom(asString(j['type'])),
        title: asString(j['title']) ?? '',
        excerpt: asString(j['excerpt']) ?? '',
        thumbnailUrl: asString(j['thumbnail_url']),
        url: asString(j['url']),
        tags: asStringList(j['tags']),
        lessonKind: asString(j['lesson_kind']),
        courseId: asInt(j['course_id']),
        energyDensity: asDouble(j['energy_density']),
        readingMinutes: asInt(j['reading_minutes']),
        pointsForReading: asInt(j['points_for_reading']) ?? 0,
        requiresMembership: asBool(j['requires_membership']),
        locked: asBool(j['locked']),
        done: j['done'] == null ? null : asBool(j['done']),
        contentHtml: asString(j['content_html']),
        wordCount: asInt(j['word_count']),
      );

  Json toJson() => {
        'id': id,
        'type': switch (type) {
          ContentType.recipe => 'recipe',
          ContentType.tip => 'tip',
          ContentType.tipOfTheDay => 'tip_of_the_day',
          ContentType.lesson => 'lesson',
        },
        'title': title,
        'excerpt': excerpt,
        'thumbnail_url': thumbnailUrl,
        'url': url,
        'tags': tags,
        'lesson_kind': lessonKind,
        'course_id': courseId,
        'energy_density': energyDensity,
        'reading_minutes': readingMinutes,
        'points_for_reading': pointsForReading,
        'requires_membership': requiresMembership,
        'locked': locked,
        'done': done,
        if (contentHtml != null) 'content_html': contentHtml,
        if (wordCount != null) 'word_count': wordCount,
      };
}

class Course {
  const Course({required this.id, required this.title, required this.lessons});
  final int id;
  final String title;
  final List<ContentItem> lessons;
}
