/// Fehler im WordPress-Format `{code, message, data:{status}}`.
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message, [this.data = const {}]);

  final int status;
  final String code;
  final String message;
  final Map<String, dynamic> data;

  bool get isUnauthorized => status == 401;
  bool get isOffline => status == 0;

  static const offline = ApiException(0, 'offline', 'Keine Internetverbindung. Wir versuchen es gleich noch einmal.');

  /// Das Modul ist auf vibono.de noch ausgeschaltet. Kein Fehler, die
  /// Oberfläche blendet die Funktion einfach aus.
  bool get isFeatureDisabled => code == 'vibono_feature_disabled';

  /// Exklusiver Beitrag, der erst mit Punkten freigeschaltet wird
  /// (`data.reward_id`, `data.cost_points`).
  bool get isRewardRequired => code == 'vibono_reward_required';

  /// Freundliche deutsche Meldung für die Oberfläche.
  String get userMessage => switch (code) {
        'vibono_invalid_credentials' => 'E-Mail oder Passwort stimmt nicht.',
        'vibono_too_many_attempts' => 'Zu viele Versuche. Bitte warte ein paar Minuten.',
        'vibono_membership_required' => 'Dieser Inhalt ist Teil des Vibono-Coachings.',
        'vibono_rate_limited' => 'Für heute sind genug Analysen gemacht. Morgen geht es weiter.',
        'vibono_image_too_large' => 'Das Foto ist zu groß. Bitte versuche es mit einem kleineren Bild.',
        'vibono_vision_unavailable' => 'Die Bilderkennung ist gerade nicht erreichbar. Du kannst die Zutaten auch selbst eingeben.',
        'vibono_vision_declined' => 'Auf dem Foto konnte ich kein Gericht oder Rezept erkennen. Versuch es mit einem anderen Bild.',
        'vibono_reading_incomplete' => 'Lies den Beitrag bitte noch zu Ende, dann gibt es die Punkte.',
        'vibono_quiz_wrong' => 'Nicht ganz. In 30 Sekunden kannst du es noch einmal versuchen.',
        'vibono_daily_cap_reached' => 'Für heute hast du alle Lesepunkte gesammelt. Morgen gibt es neue!',
        'vibono_already_rewarded' => 'Für diesen Beitrag hast du schon Punkte bekommen.',
        'vibono_feature_disabled' => 'Diese Funktion ist noch nicht freigeschaltet.',
        'vibono_insufficient_points' => 'Dafür reichen deine Punkte noch nicht.',
        'vibono_already_unlocked' => 'Das hast du schon freigeschaltet.',
        'vibono_limit_reached' => 'Diese Prämie hast du schon eingelöst.',
        'vibono_not_available_here' => 'Diese Prämie ist in der App nicht verfügbar.',
        'vibono_link_expired' => 'Der Link ist abgelaufen. Bitte öffne die Datei noch einmal.',
        _ => message.isNotEmpty ? message : 'Da ist etwas schiefgelaufen.',
      };

  @override
  String toString() => 'ApiException($status, $code, $message)';
}
