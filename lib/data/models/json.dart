/// Kleine Helfer für robustes JSON-Parsing (WordPress liefert Zahlen
/// manchmal als String).
typedef Json = Map<String, dynamic>;

int? asInt(Object? v) => switch (v) {
      int i => i,
      double d => d.round(),
      String s => int.tryParse(s),
      _ => null,
    };

double? asDouble(Object? v) => switch (v) {
      num n => n.toDouble(),
      String s => double.tryParse(s.replaceAll(',', '.')),
      _ => null,
    };

String? asString(Object? v) => v?.toString();

bool asBool(Object? v) => v == true || v == 1 || v == '1' || v == 'true';

List<T> asList<T>(Object? v, T Function(Json) f) =>
    v is List ? v.whereType<Map>().map((e) => f(Json.from(e))).toList() : <T>[];

List<String> asStringList(Object? v) =>
    v is List ? v.map((e) => e.toString()).toList() : const <String>[];

Json? asMap(Object? v) => v is Map ? Json.from(v) : null;
