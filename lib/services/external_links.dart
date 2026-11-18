import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/providers.dart';

/// Öffnet Seiten auf vibono.de immer im externen Browser (nie als
/// In-App-Kauf). Shop-Links nur, wenn `GET /config` sie für die Plattform
/// erlaubt; das prüfen die Aufrufer über [RemoteConfig].
Future<void> openWebsite(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// Eingeloggt auf vibono.de landen (Einmal-Link vom Server).
Future<void> openVibonoAccountPage(WidgetRef ref, String path) async {
  final uri = await ref.read(apiProvider).webSession(path);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
