/// Laufzeit-Konfiguration, per `--dart-define` setzbar.
///
///   flutter run --dart-define=VIBONO_API=https://www.vibono.de/wp-json/vibono/v1
///   flutter run --dart-define=VIBONO_MOCK=false
abstract final class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'VIBONO_API',
    defaultValue: 'https://www.vibono.de/wp-json/vibono/v1',
  );

  /// Solange das WordPress-Plugin nicht live ist, arbeitet die App mit Mocks.
  static const useMocks = bool.fromEnvironment('VIBONO_MOCK', defaultValue: true);

  static const websiteUrl = 'https://www.vibono.de';
  static const privacyUrl = 'https://www.vibono.de/datenschutz/';
  static const imprintUrl = 'https://www.vibono.de/impressum/';
  static const conceptUrl = 'https://www.vibono.de/tipps/abnehmen-in-3-phasen/';
  static const forgotPasswordUrl = 'https://www.vibono.de/mein-konto/lost-password/';
}
