import 'json.dart';

/// Sammlungen, die zwischen App und MyVibono in beide Richtungen
/// synchronisiert werden.
enum SyncCollection { favorites, lessonsDone, coursesDone, weight, sport, weekplan, challenges }

extension SyncCollectionX on SyncCollection {
  /// Name im Body von /sync (mit Unterstrich).
  String get wire => switch (this) {
        SyncCollection.favorites => 'favorites',
        SyncCollection.lessonsDone => 'lessons_done',
        SyncCollection.coursesDone => 'courses_done',
        SyncCollection.weight => 'weight',
        SyncCollection.sport => 'sport',
        SyncCollection.weekplan => 'weekplan',
        SyncCollection.challenges => 'challenges',
      };

  static SyncCollection? fromWire(String? s) =>
      SyncCollection.values.where((c) => c.wire == s).firstOrNull;
}

class SyncItem {
  const SyncItem({
    required this.collection,
    required this.key,
    required this.data,
    required this.updatedAt,
    this.deleted = false,
  });

  final SyncCollection collection;
  final String key;
  final Json data;
  final DateTime updatedAt;
  final bool deleted;

  static SyncItem? fromJson(Json j) {
    final c = SyncCollectionX.fromWire(asString(j['collection']));
    if (c == null) return null;
    return SyncItem(
      collection: c,
      key: asString(j['key']) ?? '',
      data: asMap(j['data']) ?? <String, dynamic>{},
      updatedAt: DateTime.tryParse(asString(j['updated_at']) ?? '')?.toUtc() ?? DateTime.now().toUtc(),
      deleted: asBool(j['deleted']),
    );
  }

  Json toJson() => {
        'collection': collection.wire,
        'key': key,
        'data': data,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted': deleted,
      };

  /// Als Änderung für `POST /sync`.
  Json toChange(String clientChangeId) => {
        'client_change_id': clientChangeId,
        'collection': collection.wire,
        'key': key,
        'op': deleted ? 'delete' : 'upsert',
        if (!deleted) 'data': data,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };
}
