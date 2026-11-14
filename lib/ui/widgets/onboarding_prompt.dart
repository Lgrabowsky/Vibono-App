import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/day_checks.dart';
import '../../state/providers.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import '../navigation.dart';
import '../screens/onboarding/onboarding_screen.dart';
import 'common.dart';

/// Kachel auf der Startseite, solange das Onboarding nicht ausgefüllt ist.
/// „Später“ blendet sie bis morgen aus.
class OnboardingPrompt extends ConsumerStatefulWidget {
  const OnboardingPrompt({super.key});

  static const _kHiddenOn = 'u.onboardingPrompt.hiddenOn';

  @override
  ConsumerState<OnboardingPrompt> createState() => _OnboardingPromptState();
}

class _OnboardingPromptState extends ConsumerState<OnboardingPrompt> {
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _hidden = ref.read(storeProvider).readString(OnboardingPrompt._kHiddenOn) == dayKey(DateTime.now());
  }

  Future<void> _later() async {
    setState(() => _hidden = true);
    await ref.read(storeProvider).writeString(OnboardingPrompt._kHiddenOn, dayKey(DateTime.now()));
  }

  @override
  Widget build(BuildContext context) {
    final completed = ref.watch(sessionProvider.select((s) => s.profile.completed));
    if (completed || _hidden) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: const BoxDecoration(
        color: VibonoColors.green050,
        border: Border(top: BorderSide(color: VibonoColors.green, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CoachAvatar(size: 40),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Erzähl mir kurz von dir', style: VibonoText.cardTitle.copyWith(color: VibonoColors.grey900)),
            const SizedBox(height: 4),
            const Text(
              'Zwei Minuten. Danach passen Rezepte, Ziele und Erinnerungen zu dir.',
              style: VibonoText.small,
            ),
            const SizedBox(height: 8),
            Row(children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                onPressed: () => push(context, const OnboardingScreen()),
                child: const Text("LOS GEHT'S"),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: _later, child: const Text('Später')),
            ]),
          ]),
        ),
      ]),
    );
  }
}
