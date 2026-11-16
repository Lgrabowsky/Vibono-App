import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';
import 'core/config.dart';
import 'data/api/http_vibono_api.dart';
import 'data/api/mock_vibono_api.dart';
import 'data/api/token_store.dart';
import 'data/api/vibono_api.dart';
import 'data/local/local_store.dart';
import 'data/sync/sync_repository.dart';
import 'services/notification_service.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'de_DE';
  await initializeDateFormatting('de_DE');

  final store = await LocalStore.open();
  final VibonoApi api;
  if (AppConfig.useMocks) {
    api = MockVibonoApi(store);
  } else {
    final tokens = TokenStore();
    await tokens.load();
    api = HttpVibonoApi(baseUrl: AppConfig.apiBaseUrl, tokens: tokens);
  }
  final sync = SyncRepository(api, store)..load();

  final container = ProviderContainer(overrides: [
    storeProvider.overrideWithValue(store),
    apiProvider.overrideWithValue(api),
    syncProvider.overrideWith((ref) => sync),
  ]);
  await container.read(notificationServiceProvider).init();

  runApp(UncontrolledProviderScope(container: container, child: const VibonoApp()));
}
