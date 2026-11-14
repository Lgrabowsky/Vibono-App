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
    return Material(
      color: VibonoColors.green050,
      child: InkWell(
        onTap: () => push(context, const OnboardingScreen()),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(children: [
            const ClipOval(child: CoachAvatar(size: 32)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Erzähl mir kurz von dir',
                    style: VibonoText.body.copyWith(fontWeight: FontWeight.w700, color: VibonoColors.grey900)),
                const Text('2 Minuten, dann passen Rezepte und Ziele zu dir', style: VibonoText.small),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: VibonoColors.green700),
            IconButton(
              tooltip: 'Später',
              visualDensity: VisualDensity.compact,
              onPressed: _later,
              icon: const Icon(Icons.close_rounded, size: 18, color: VibonoColors.grey400),
            ),
          ]),
        ),
      ),
    );
  }
}
