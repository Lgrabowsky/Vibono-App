import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Speichert Access- und Refresh-Token im Schlüsselbund (iOS) bzw.
/// verschlüsselt (Android). Keine Passwörter auf dem Gerät.
class TokenStore {
  TokenStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;
  String? _access;
  String? _refresh;

  static const _kAccess = 'vibono_access_token';
  static const _kRefresh = 'vibono_refresh_token';

  Future<void> load() async {
    try {
      _access = await _s.read(key: _kAccess);
      _refresh = await _s.read(key: _kRefresh);
    } catch (_) {
      _access = null;
      _refresh = null;
    }
  }

  String? get accessToken => _access;
  String? get refreshToken => _refresh;
  bool get hasSession => _refresh != null;

  Future<void> save(String access, String refresh) async {
    _access = access;
    _refresh = refresh;
    try {
      await _s.write(key: _kAccess, value: access);
      await _s.write(key: _kRefresh, value: refresh);
    } catch (_) {/* Web-Vorschau ohne sicheren Speicher */}
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    try {
      await _s.delete(key: _kAccess);
      await _s.delete(key: _kRefresh);
    } catch (_) {}
  }
}
