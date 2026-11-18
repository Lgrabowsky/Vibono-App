import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_config.dart';
import '../models/coaching_day.dart';
import '../models/content.dart';
import '../models/energy.dart';
import '../models/json.dart';
import '../models/points.dart';
import '../models/profile.dart';
import '../models/sync_item.dart';
import 'api_exception.dart';
import 'token_store.dart';
import 'vibono_api.dart';

/// Echte Anbindung an das WordPress-Plugin.
class HttpVibonoApi implements VibonoApi {
  HttpVibonoApi({required this.baseUrl, required this.tokens, http.Client? client})
      : _http = client ?? http.Client();

  final String baseUrl;
  final TokenStore tokens;
  final http.Client _http;
  Future<bool>? _refreshing;

  @override
  bool get hasSession => tokens.hasSession;

  Uri _uri(String path, [Map<String, String?>? query]) {
    final q = <String, String>{
      for (final e in (query ?? const <String, String?>{}).entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
    };
    return Uri.parse('$baseUrl$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String?>? query,
    Object? body,
    bool auth = true,
    bool retried = false,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      if (auth && tokens.accessToken != null) 'Authorization': 'Bearer ${tokens.accessToken}',
    };
    final req = http.Request(method, _uri(path, query))..headers.addAll(headers);
    if (body != null) req.body = jsonEncode(body);

    http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 30)));
    } on TimeoutException {
      throw ApiException.offline;
    } catch (_) {
      throw ApiException.offline;
    }

    if (res.statusCode == 401 && auth && !retried && tokens.refreshToken != null) {
      if (await _refresh()) {
        return _send(method, path, query: query, body: body, auth: auth, retried: true);
      }
    }

    final text = utf8.decode(res.bodyBytes);
    final decoded = text.isEmpty ? null : jsonDecode(text);
    if (res.statusCode >= 400) {
      final m = decoded is Map ? Json.from(decoded) : <String, dynamic>{};
      throw ApiException(
        res.statusCode,
        asString(m['code']) ?? 'http_${res.statusCode}',
        asString(m['message']) ?? '',
        asMap(m['data']) ?? const {},
      );
    }
    return decoded;
  }

  /// Nur ein Refresh gleichzeitig, der Refresh-Token rotiert.
  Future<bool> _refresh() => _refreshing ??= () async {
        try {
          final r = await _send('POST', '/auth/refresh',
              body: {'refresh_token': tokens.refreshToken}, auth: false, retried: true);
          await _saveTokens(Json.from(r as Map));
          return true;
        } on ApiException catch (e) {
          if (e.isUnauthorized) await tokens.clear();
          return false;
        } finally {
          _refreshing = null;
        }
      }();

  Future<Me> _saveTokens(Json r) async {
    await tokens.save(asString(r['access_token'])!, asString(r['refresh_token'])!);
    return Me.fromJson(asMap(r['user']) ?? const {});
  }

  Json _map(dynamic v) => v is Map ? Json.from(v) : <String, dynamic>{};

  @override
  Future<RemoteConfig> config(String platform) async =>
      RemoteConfig.fromJson(_map(await _send('GET', '/config', query: {'platform': platform}, auth: false)));

  @override
  Future<Me> login(String username, String password, {String? deviceName}) async => _saveTokens(_map(await _send(
        'POST',
        '/auth/login',
        body: {'username': username, 'password': password, 'device_name': ?deviceName},
        auth: false,
      )));

  @override
  Future<Me> register({required String email, required String password, String? firstName, String? referralCode}) async =>
      _saveTokens(_map(await _send('POST', '/auth/register',
          body: {
            'email': email,
            'password': password,
            'first_name': ?firstName,
            'referral_code': ?referralCode,
            'accept_privacy': true,
          },
          auth: false)));

  @override
  Future<void> logout() async {
    try {
      await _send('POST', '/auth/logout', body: {'refresh_token': tokens.refreshToken});
    } on ApiException {
      // Lokal trotzdem abmelden.
    }
    await tokens.clear();
  }

  @override
  Future<void> requestPasswordReset(String email) async =>
      _send('POST', '/auth/password-reset', body: {'email': email}, auth: false);

  @override
  Future<Me> me() async => Me.fromJson(_map(await _send('GET', '/me')));

  @override
  Future<Me> updateProfile(Profile profile) async =>
      Me.fromJson(_map(await _send('PUT', '/me/profile', body: profile.toApiJson())));

  @override
  Future<void> deleteAccount() async => _send('DELETE', '/me');

  @override
  Future<void> registerDevice(String token, String platform) async =>
      _send('POST', '/me/devices', body: {'token': token, 'platform': platform, 'locale': 'de-DE'});

  @override
  Future<SyncPull> syncPull({String? cursor}) async {
    final r = _map(await _send('GET', '/sync', query: {'cursor': cursor}));
    return SyncPull(
      cursor: asString(r['cursor']) ?? '',
      hasMore: asBool(r['has_more']),
      full: asBool(r['full']),
      changes: (r['changes'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => SyncItem.fromJson(Json.from(e)))
          .whereType<SyncItem>()
          .toList(),
    );
  }

  @override
  Future<SyncPushResult> syncPush(List<Json> changes) async {
    final r = _map(await _send('POST', '/sync', body: {'changes': changes}));
    final stale = <SyncItem>[];
    for (final res in (r['results'] as List? ?? const []).whereType<Map>()) {
      if (res['status'] == 'stale' && res['server_item'] is Map) {
        final item = SyncItem.fromJson(Json.from(res['server_item'] as Map));
        if (item != null) stale.add(item);
      }
    }
    return SyncPushResult(cursor: asString(r['cursor']), serverItems: stale);
  }

  @override
  Future<CoachingDay> coachingDay(DateTime date) async => CoachingDay.fromJson(
      _map(await _send('GET', '/coaching/today', query: {'date': date.toIso8601String().substring(0, 10)})));

  @override
  Future<List<ContentItem>> content(String type, {String? search, List<String>? tags, int? course, int page = 1}) async {
    final r = _map(await _send('GET', '/content/$type', query: {
      'search': search,
      'tags': tags?.join(','),
      'course': course?.toString(),
      'page': '$page',
      'per_page': '50',
    }));
    return asList(r['items'], ContentItem.fromJson);
  }

  @override
  Future<List<Course>> courses() async {
    // Lektionen kommen gruppiert über course_id; Kursnamen liefert der
    // Vertrag (noch) nicht separat, daher aus den Lektionen ableiten.
    final lessons = await content('lessons');
    final byCourse = <int, List<ContentItem>>{};
    for (final l in lessons) {
      byCourse.putIfAbsent(l.courseId ?? 0, () => []).add(l);
    }
    return [
      for (final e in byCourse.entries)
        Course(id: e.key, title: e.value.first.tags.isNotEmpty ? e.value.first.tags.first : 'Kurs ${e.key}', lessons: e.value),
    ];
  }

  @override
  Future<ContentItem> contentItem(int id) async => ContentItem.fromJson(_map(await _send('GET', '/content/item/$id')));

  @override
  Future<PointsSummary> points() async => PointsSummary.fromJson(_map(await _send('GET', '/points')));

  @override
  Future<List<LedgerEntry>> ledger({int page = 1}) async =>
      asList(_map(await _send('GET', '/points/ledger', query: {'page': '$page'}))['items'], LedgerEntry.fromJson);

  @override
  Future<AwardResult> reportAppOpen() async => AwardResult.fromJson(_map(await _send('POST', '/points/app-open')));

  @override
  Future<ReadingSession> startReading(int postId) async =>
      ReadingSession.fromJson(_map(await _send('POST', '/reading/start', body: {'post_id': postId})));

  @override
  Future<ReadingProgress> readingHeartbeat(String sessionId, int activeSeconds, double scrollDepth) async =>
      ReadingProgress.fromJson(_map(await _send('POST', '/reading/heartbeat', body: {
        'session_id': sessionId,
        'active_seconds': activeSeconds,
        'scroll_depth': scrollDepth,
      })));

  @override
  Future<AwardResult> completeReading(String sessionId, {int? quizAnswer}) async => AwardResult.fromJson(
      _map(await _send('POST', '/reading/complete', body: {'session_id': sessionId, 'quiz_answer': ?quizAnswer})));

  @override
  Future<ReferralInfo> referral() async => ReferralInfo.fromJson(_map(await _send('GET', '/referral')));

  @override
  Future<Uri> webSession(String redirectPath) async =>
      Uri.parse(asString(_map(await _send('POST', '/auth/web-session', body: {'redirect': redirectPath}))['url'])!);

  @override
  Future<List<Food>> foods(String query) async =>
      asList(_map(await _send('GET', '/foods', query: {'q': query}))['items'], Food.fromJson);

  @override
  Future<RecipeScanResult> scanRecipe(String imageBase64, String mime) async => RecipeScanResult.fromJson(
      _map(await _send('POST', '/energy-density/scan-recipe', body: {'image_base64': imageBase64, 'mime': mime})));

  @override
  Future<PhotoAnalysisResult> analyzePhoto(String imageBase64, String mime, {String? description}) async =>
      PhotoAnalysisResult.fromJson(_map(await _send('POST', '/energy-density/analyze-photo', body: {
        'image_base64': imageBase64,
        'mime': mime,
        if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
      })));
}
