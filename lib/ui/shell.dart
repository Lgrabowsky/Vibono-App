import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/day_checks.dart';
import '../state/providers.dart';
import '../theme/vibono_colors.dart';
import '../theme/vibono_theme.dart';
import 'screens/coaching_screen.dart';
import 'screens/more_screen.dart';
import 'screens/recipes_screen.dart';
import 'screens/today_screen.dart';
import 'screens/weekplan_screen.dart';
import 'widgets/common.dart';
import 'widgets/streak.dart';

/// Hauptgerüst mit den Tabs Heute · Rezepte · Coaching · Wochenplan · Mehr.
/// Nicht ausgewählt = Vibono-Grau, ausgewählt = Vibono-Grün.
class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onResume: _onOpen);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onOpen());
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  /// Punkte fürs tägliche Öffnen (Server vergibt sie einmal pro Tag) und
  /// Abgleich mit MyVibono.
  Future<void> _onOpen() async {
    unawaited(ref.read(syncProvider).sync());
    // Nach Mitternacht wieder auf „heute“ springen.
    ref.read(selectedDateProvider.notifier).today();
    try {
      final r = await ref.read(apiProvider).reportAppOpen();
      ref.read(pointsBalanceProvider.notifier).set(r.balance);
      if (r.streak != null) ref.read(appStreakProvider.notifier).set(r.streak);
      if (mounted && r.awardedPoints > 0) showPointsToast(context, r.awardedPoints, streakToastText(r.streak));
    } catch (_) {/* offline: der Server holt das nicht nach */}
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(tabIndexProvider);
    return Scaffold(
      body: IndexedStack(index: index, children: const [
        TodayScreen(),
        RecipesScreen(),
        CoachingScreen(),
        WeekplanScreen(),
        MoreScreen(),
      ]),
      bottomNavigationBar: _TabBar(index: index, onTap: ref.read(tabIndexProvider.notifier).go),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  static const _labels = ['Heute', 'Rezepte', 'Coaching', 'Wochenplan', 'Mehr'];

  Widget _icon(int i, Color c) => switch (i) {
        0 => Icon(index == 0 ? Icons.home_rounded : Icons.home_outlined, color: c, size: 26),
        1 => Icon(Icons.restaurant_rounded, color: c, size: 24),
        2 => VibonoV(size: 24, color: c),
        3 => Icon(index == 3 ? Icons.calendar_month_rounded : Icons.calendar_month_outlined, color: c, size: 24),
        _ => Icon(Icons.more_horiz_rounded, color: c, size: 26),
      };

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: VibonoColors.grey200)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(children: [
              for (var i = 0; i < 5; i++)
                Expanded(
                  child: Semantics(
                    selected: i == index,
                    button: true,
                    label: _labels[i],
                    excludeSemantics: true,
                    child: InkResponse(
                      onTap: () => onTap(i),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        SizedBox(height: 26, child: Center(child: _icon(i, i == index ? VibonoColors.green : VibonoColors.grey))),
                        const SizedBox(height: 2),
                        Text(
                          _labels[i],
                          style: TextStyle(
                            fontFamily: VibonoFonts.display,
                            fontSize: 12,
                            fontWeight: i == index ? FontWeight.w700 : FontWeight.w400,
                            color: i == index ? VibonoColors.green : VibonoColors.grey,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
}

/// Hilfsfunktion für Bildschirme, die zu einem Tab springen.
void goTab(WidgetRef ref, int tab) => ref.read(tabIndexProvider.notifier).go(tab);
