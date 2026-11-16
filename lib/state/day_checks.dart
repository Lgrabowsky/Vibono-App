import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Lokale Häkchen eines Tages, für die es (noch) keine MyVibono-Sammlung
/// gibt: Mahlzeiten („3× satt“) und z. B. „Einkaufen erledigt“.
class DayChecks extends Notifier<Set<String>> {
  DayChecks(this.day);
  final String day;

  String get _key => 'u.checks.$day';

  @override
  Set<String> build() {
    final raw = ref.watch(storeProvider).readJson(_key);
    return raw is List ? raw.map((e) => '$e').toSet() : <String>{};
  }

  Future<void> toggle(String id) async {
    final next = {...state};
    if (!next.remove(id)) next.add(id);
    state = next;
    await ref.read(storeProvider).writeJson(_key, next.toList());
  }
}

final dayChecksProvider = NotifierProvider.family<DayChecks, Set<String>, String>(DayChecks.new);

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Ausgewählter Tab in der unteren Leiste.
class TabIndex extends Notifier<int> {
  @override
  int build() => 0;
  void go(int i) => state = i;
}

final tabIndexProvider = NotifierProvider<TabIndex, int>(TabIndex.new);

abstract final class Tabs {
  static const heute = 0;
  static const rezepte = 1;
  static const coaching = 2;
  static const wochenplan = 3;
  static const mehr = 4;
}
