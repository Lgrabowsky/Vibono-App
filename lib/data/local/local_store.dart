import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Einfacher Offline-Speicher für JSON (Cache, Sync-Daten, Ausgang).
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<LocalStore> open() async => LocalStore(await SharedPreferences.getInstance());

  dynamic readJson(String key) {
    final s = _prefs.getString(key);
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJson(String key, Object? value) =>
      value == null ? _prefs.remove(key) : _prefs.setString(key, jsonEncode(value));

  String? readString(String key) => _prefs.getString(key);
  Future<void> writeString(String key, String value) => _prefs.setString(key, value);
  bool? readBool(String key) => _prefs.getBool(key);
  Future<void> writeBool(String key, bool value) => _prefs.setBool(key, value);

  Future<void> clearUserData() async {
    for (final k in _prefs.getKeys().where((k) => k.startsWith('u.')).toList()) {
      await _prefs.remove(k);
    }
  }
}
