import '../data/models/coaching_day.dart';
import '../data/models/profile.dart';

class PlannedNotification {
  const PlannedNotification({
    required this.at,
    required this.topic,
    required this.title,
    required this.body,
    this.payload,
  });

  final DateTime at;
  final String topic;
  final String title;
  final String body;

  /// z. B. `content:123` oder `screen:today`, öffnet beim Antippen.
  final String? payload;
}

/// Wählt aus den Inhalten eines Coaching-Tages bis zu 10 Nachrichten aus
/// und verteilt sie gleichmäßig auf die wache Zeit (außerhalb der Ruhezeit).
/// Die Uhrzeiten sind nur intern für die Zustellung, in der App erscheinen
/// Tage ohne Uhrzeiten.
abstract final class NotificationPlanner {
  static List<PlannedNotification> plan(CoachingDay day, Profile profile, {DateTime? now}) {
    final count = profile.notificationsPerDay.clamp(0, 10);
    if (count == 0) return const [];
    final topics = profile.notificationTopics.toSet();

    final pool = <({String topic, String title, String body, String? payload})>[];
    void add(String topic, String title, String body, [String? payload]) {
      if (topics.isEmpty || topics.contains(topic)) pool.add((topic: topic, title: title, body: body, payload: payload));
    }

    // Reihenfolge = Priorität: erst der nächste Schritt, dann die Aufgaben.
    final next = day.nextStep;
    if (next != null) add('aufgaben', 'Als Nächstes', next.title, 'content:${next.id}');
    for (final i in day.sonstiges) {
      add('aufgaben', 'Heute wichtig', i.title, 'content:${i.id}');
    }
    final slots = ['Frühstück', 'Mittagessen', 'Abendessen'];
    for (var i = 0; i < day.recipes.length && i < 3; i++) {
      add('rezepte', 'Rezept fürs ${slots[i]}', day.recipes[i].title, 'recipe:${day.recipes[i].id}');
    }
    if (day.tipOfTheDay.isNotEmpty) add('motivation', 'Tipp des Tages', day.tipOfTheDay, 'screen:today');
    for (final i in day.bewegung) {
      add('bewegung', 'Zeit für Bewegung', i.title, 'screen:today');
    }
    for (final i in day.wissen) {
      add('wissen', 'Wissen für heute', '${i.title} · ${i.readingMinutes ?? 3} Min. Lesezeit', 'content:${i.id}');
    }
    final tip = day.vibonoTip;
    if (tip != null) add('motivation', 'Vibono-Tipp', tip.title, 'content:${tip.id}');
    add('motivation', 'Du schaffst das!', 'Jeder Tag zählt. Schau kurz in deinen Plan für heute.', 'screen:today');
    add('aufgaben', 'Kurzer Check', 'Hast du heute schon 3× satt gegessen? Hak es in der App ab.', 'screen:today');

    final chosen = pool.take(count).toList();
    if (chosen.isEmpty) return const [];

    // Wache Zeit des Tages bestimmen.
    final date = DateTime(day.date.year, day.date.month, day.date.day);
    final wake = _at(date, profile.quietEnd);
    var sleep = _at(date, profile.quietStart);
    if (!sleep.isAfter(wake)) sleep = sleep.add(const Duration(days: 1));
    // Etwas Abstand zu den Rändern der Ruhezeit.
    final from = wake.add(const Duration(minutes: 30));
    final to = sleep.subtract(const Duration(minutes: 30));
    final span = to.difference(from);
    final step = chosen.length == 1 ? Duration.zero : span ~/ (chosen.length - 1);

    final result = <PlannedNotification>[];
    final current = now ?? DateTime.now();
    for (var i = 0; i < chosen.length; i++) {
      final at = chosen.length == 1 ? from.add(span ~/ 3) : from.add(step * i);
      if (at.isBefore(current)) continue;
      final c = chosen[i];
      result.add(PlannedNotification(at: at, topic: c.topic, title: c.title, body: c.body, payload: c.payload));
    }
    return result;
  }

  static DateTime _at(DateTime date, String hhmm) {
    final p = hhmm.split(':');
    final h = int.tryParse(p.first) ?? 0;
    final m = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
    return DateTime(date.year, date.month, date.day, h, m);
  }
}
