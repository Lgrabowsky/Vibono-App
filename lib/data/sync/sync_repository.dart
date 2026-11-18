import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_exception.dart';
import '../api/vibono_api.dart';
import '../local/local_store.dart';
import '../models/json.dart';
import '../models/sync_item.dart';

/// Offline-first-Synchronisation der Nutzerdaten mit MyVibono.
///
/// * Lokale Änderungen landen sofort im lokalen Stand und im Ausgang.
/// * `sync()` schickt den Ausgang (`POST /sync`) und holt danach alle
///   Änderungen seit dem letzten Cursor (`GET /sync`), auch die, die auf
///   der Website gemacht wurden.
/// * Konflikte: je Eintrag gewinnt die jüngste Änderung (`updated_at`),
///   so wie es der Server auch macht.
class SyncRepository extends ChangeNotifier {
  SyncRepository(this._api, this._store);

  final VibonoApi _api;
  final LocalStore _store;

  final Map<SyncCollection, Map<String, SyncItem>> _items = {
    for (final c in SyncCollection.values) c: <String, SyncItem>{},
  };
  final Map<String, SyncItem> _outbox = {}; // "collection|key" → Änderung
  String? _cursor;
  bool _syncing = false;
  DateTime? lastSyncedAt;
  String? lastError;

  static const _kItems = 'u.sync.items';
  static const _kOutbox = 'u.sync.outbox';
  static const _kCursor = 'u.sync.cursor';

  bool get isSyncing => _syncing;
  int get pendingChanges => _outbox.length;

  void load() {
    final raw = _store.readJson(_kItems);
    if (raw is List) {
      for (final e in raw.whereType<Map>()) {
        final i = SyncItem.fromJson(Json.from(e));
        if (i != null) _items[i.collection]![i.key] = i;
      }
    }
    final out = _store.readJson(_kOutbox);
    if (out is List) {
      for (final e in out.whereType<Map>()) {
        final i = SyncItem.fromJson(Json.from(e));
        if (i != null) _outbox[_id(i)] = i;
      }
    }
    _cursor = _store.readString(_kCursor);
  }

  Future<void> _persist() async {
    await _store.writeJson(_kItems, [for (final m in _items.values) ...m.values.map((i) => i.toJson())]);
    await _store.writeJson(_kOutbox, _outbox.values.map((i) => i.toJson()).toList());
    if (_cursor != null) await _store.writeString(_kCursor, _cursor!);
  }

  static String _id(SyncItem i) => '${i.collection.wire}|${i.key}';

  // ---------- Lesen ----------

  Iterable<SyncItem> items(SyncCollection c) => _items[c]!.values.where((i) => !i.deleted);

  bool has(SyncCollection c, String key) {
    final i = _items[c]![key];
    return i != null && !i.deleted;
  }

  Json? get(SyncCollection c, String key) {
    final i = _items[c]![key];
    return i == null || i.deleted ? null : i.data;
  }

  // ---------- Schreiben ----------

  Future<void> upsert(SyncCollection c, String key, Json data) => _change(
      SyncItem(collection: c, key: key, data: data, updatedAt: DateTime.now().toUtc()));

  Future<void> remove(SyncCollection c, String key) => _change(SyncItem(
      collection: c, key: key, data: const {}, updatedAt: DateTime.now().toUtc(), deleted: true));

  Future<void> toggle(SyncCollection c, String key, Json data) =>
      has(c, key) ? remove(c, key) : upsert(c, key, data);

  Future<void> _change(SyncItem item) async {
    _items[item.collection]![item.key] = item;
    _outbox[_id(item)] = item;
    notifyListeners();
    await _persist();
    unawaited(sync());
  }

  // ---------- Abgleich ----------

  Future<void>? _running;
  bool _again = false;

  /// Abgleich starten. Läuft schon einer, wird danach noch einmal
  /// abgeglichen, damit keine Änderung liegen bleibt.
  Future<void> sync() {
    if (!_api.hasSession) return Future.value();
    if (_running != null) {
      _again = true;
      return _running!;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _runOnce();
    } while (_again && lastError == null);
  }

  Future<void> _runOnce() async {
    _syncing = true;
    notifyListeners();
    try {
      await _push();
      await _pull();
      lastSyncedAt = DateTime.now();
      lastError = null;
    } on ApiException catch (e) {
      lastError = e.isOffline ? null : e.userMessage; // offline: später erneut
      if (e.isOffline) _again = false;
    } finally {
      _syncing = false;
      await _persist();
      notifyListeners();
    }
  }

  Future<void> _push() async {
    while (_outbox.isNotEmpty) {
      final batch = _outbox.values.take(500).toList();
      final res = await _api.syncPush([for (final i in batch) i.toChange(_id(i))]);
      for (final i in batch) {
        // Nur entfernen, wenn seitdem keine neuere lokale Änderung kam.
        if (identical(_outbox[_id(i)], i)) _outbox.remove(_id(i));
      }
      for (final s in res.serverItems) {
        _applyRemote(s);
      }
    }
  }

  Future<void> _pull() async {
    var hasMore = true;
    while (hasMore) {
      SyncPull r;
      try {
        r = await _api.syncPull(cursor: _cursor);
      } on ApiException catch (e) {
        if (e.status == 410) {
          _cursor = null; // Cursor abgelaufen → vollständig neu laden
          r = await _api.syncPull();
        } else {
          rethrow;
        }
      }
      if (r.full) {
        final pending = {for (final o in _outbox.values) _id(o)};
        for (final m in _items.values) {
          m.removeWhere((k, v) => !pending.contains(_id(v)));
        }
      }
      for (final i in r.changes) {
        _applyRemote(i);
      }
      _cursor = r.cursor;
      hasMore = r.hasMore;
    }
  }

  void _applyRemote(SyncItem remote) {
    final local = _items[remote.collection]![remote.key];
    final pending = _outbox[_id(remote)];
    if (pending != null && pending.updatedAt.isAfter(remote.updatedAt)) return;
    if (local == null || !local.updatedAt.isAfter(remote.updatedAt)) {
      _items[remote.collection]![remote.key] = remote;
      if (pending != null) _outbox.remove(_id(remote));
    }
  }

  Future<void> reset() async {
    for (final m in _items.values) {
      m.clear();
    }
    _outbox.clear();
    _cursor = null;
    notifyListeners();
  }
}
