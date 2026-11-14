import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'services/notification_service.dart';
import 'state/providers.dart';
import 'theme/vibono_theme.dart';
import 'ui/screens/article_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/onboarding/onboarding_screen.dart';
import 'ui/screens/recipe_detail_screen.dart';
import 'ui/shell.dart';
import 'ui/widgets/common.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class VibonoApp extends ConsumerStatefulWidget {
  const VibonoApp({super.key});

  @override
  ConsumerState<VibonoApp> createState() => _VibonoAppState();
}

class _VibonoAppState extends ConsumerState<VibonoApp> {
  @override
  void initState() {
    super.initState();
    ref.read(notificationServiceProvider).onOpen = _openPayload;
  }

  void _openPayload(String payload) {
    final nav = navigatorKey.currentState;
    final parts = payload.split(':');
    final id = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (nav == null || id == null) return;
    nav.push(MaterialPageRoute<void>(
      builder: (_) => parts[0] == 'recipe' ? RecipeDetailScreen(recipeId: id) : ArticleScreen(contentId: id),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    ref.listen(sessionProvider.select((s) => s.status), (prev, next) {
      if (next == SessionStatus.ready) ref.read(notificationServiceProvider).reschedule();
    });
    return MaterialApp(
      title: 'Vibono',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: buildVibonoTheme(),
      locale: const Locale('de', 'DE'),
      supportedLocales: const [Locale('de', 'DE')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: switch (session.status) {
        SessionStatus.loading => const Scaffold(body: Center(child: VibonoLogo(height: 34))),
        SessionStatus.loggedOut => const LoginScreen(),
        SessionStatus.onboarding => const OnboardingScreen(),
        SessionStatus.ready => const Shell(),
      },
    );
  }
}
