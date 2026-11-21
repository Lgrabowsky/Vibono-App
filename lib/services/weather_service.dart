import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/food_suggestions.dart';
import '../domain/season.dart';

/// Wetter für Rezeptvorschläge. Die App fragt nur mit dem Ort, den die Person
/// selbst einträgt (kein Standortzugriff).
abstract interface class WeatherSource {
  Future<WeatherInfo?> current(String? place);
}

/// Open-Meteo (frei, ohne Schlüssel): erst Ort zu Koordinaten, dann aktuelles Wetter.
class OpenMeteoWeather implements WeatherSource {
  OpenMeteoWeather({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  Future<Map<String, dynamic>?> _get(Uri uri) async {
    try {
      final r = await _http.get(uri).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<WeatherInfo?> current(String? place) async {
    final p = place?.trim() ?? '';
    if (p.isEmpty) return null;
    final geo = await _get(Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': p,
      'count': '1',
      'language': 'de',
      'format': 'json',
    }));
    final results = geo?['results'];
    if (results is! List || results.isEmpty || results.first is! Map) return null;
    final first = results.first as Map;
    final lat = first['latitude'], lon = first['longitude'];
    if (lat is! num || lon is! num) return null;
    final fc = await _get(Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lat.toStringAsFixed(2),
      'longitude': lon.toStringAsFixed(2),
      'current': 'temperature_2m,weather_code',
      'timezone': 'auto',
    }));
    final cur = fc?['current'];
    if (cur is! Map) return null;
    final t = cur['temperature_2m'], code = cur['weather_code'];
    if (t is! num || code is! num) return null;
    return WeatherInfo(tempC: t.toDouble(), kind: WeatherInfo.kindFromWmo(code.toInt()), place: '${first['name'] ?? p}');
  }
}

/// Demo-Modus: typisches Wetter der Jahreszeit, ohne Netz.
class DemoWeather implements WeatherSource {
  const DemoWeather();

  @override
  Future<WeatherInfo?> current(String? place) async {
    final now = DateTime.now();
    final (t, k) = switch (SeasonCalendar.seasonOf(now)) {
      Season.winter => (2.0, WeatherKind.bewoelkt),
      Season.fruehling => (14.0, WeatherKind.sonnig),
      Season.sommer => (27.0, WeatherKind.sonnig),
      Season.herbst => (now.month == 11 ? 6.0 : 11.0, WeatherKind.regen),
    };
    return WeatherInfo(tempC: t, kind: k, place: (place == null || place.trim().isEmpty) ? 'Beispielwetter' : place.trim());
  }
}
