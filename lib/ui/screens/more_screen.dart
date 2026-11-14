import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config.dart';
import '../../services/external_links.dart';
import '../../state/providers.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import '../navigation.dart';
import '../widgets/common.dart';
import 'energy_density/energy_density_screen.dart';
import 'notification_settings_screen.dart';
import 'onboarding/onboarding_screen.dart';
import 'points_screen.dart';
import 'referral_screen.dart';
import 'tips_screen.dart';
import 'weight_screen.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(sessionProvider).me;
    final balance = ref.watch(pointsBalanceProvider) ?? me?.pointsBalance ?? 0;
    final sync = ref.watch(syncProvider);

    Widget tile(IconData icon, String title, VoidCallback onTap, {String? subtitle, Widget? trailing}) => ListTile(
          leading: Icon(icon, color: VibonoColors.green),
          title: Text(title, style: VibonoText.cardTitle.copyWith(fontWeight: FontWeight.w400, fontSize: 16)),
          subtitle: subtitle == null ? null : Text(subtitle, style: VibonoText.small),
          trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: VibonoColors.grey300),
          onTap: onTap,
        );

    final syncText = sync.isSyncing
        ? 'Wird abgeglichen …'
        : sync.lastError ??
            (sync.pendingChanges > 0
                ? '${sync.pendingChanges} Änderungen warten auf Verbindung'
                : sync.lastSyncedAt == null
                    ? 'Noch nicht abgeglichen'
                    : 'Zuletzt abgeglichen ${DateFormat('HH:mm', 'de_DE').format(sync.lastSyncedAt!)} Uhr');

    return SafeArea(
      bottom: false,
      child: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            const CoachAvatar(size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(me?.firstName.isNotEmpty == true ? me!.firstName : 'Mein Konto', style: VibonoText.hello),
                Text(me?.membershipName ?? me?.email ?? '', style: VibonoText.small),
              ]),
            ),
            PointsChip(points: balance, onTap: () => push(context, const PointsScreen())),
          ]),
        ),
        const Divider(),
        tile(Icons.star_outline_rounded, 'Meine Punkte', () => push(context, const PointsScreen())),
        tile(Icons.group_add_outlined, 'Freunde einladen', () => push(context, const ReferralScreen()),
            subtitle: 'Punkte für jede Empfehlung'),
        tile(Icons.calculate_outlined, 'Energiedichte-Rechner', () => push(context, const EnergyDensityScreen()),
            subtitle: 'Eingeben, Rezept scannen oder Foto'),
        tile(Icons.monitor_weight_outlined, 'Mein Gewicht & Ziele', () => push(context, const WeightScreen())),
        tile(Icons.lightbulb_outline_rounded, 'Vibono-Tipps', () => push(context, const TipsScreen())),
        const Divider(),
        tile(Icons.notifications_none_rounded, 'Benachrichtigungen', () => push(context, const NotificationSettingsScreen()),
            subtitle: '${ref.watch(sessionProvider).profile.notificationsPerDay} pro Tag'),
        tile(Icons.tune_rounded, 'Meine Angaben', () => push(context, const OnboardingScreen(editMode: true)),
            subtitle: 'Ernährung, Bewegung, Haushalt'),
        tile(Icons.sync_rounded, 'Mit MyVibono abgleichen', sync.sync,
            subtitle: syncText,
            trailing: sync.isSyncing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : null),
        const Divider(),
        tile(Icons.info_outline_rounded, 'Das Vibono-Konzept', () => openWebsite(AppConfig.conceptUrl)),
        tile(Icons.privacy_tip_outlined, 'Datenschutz', () => openWebsite(AppConfig.privacyUrl)),
        tile(Icons.article_outlined, 'Impressum', () => openWebsite(AppConfig.imprintUrl)),
        const Divider(),
        tile(Icons.logout_rounded, 'Abmelden', () => ref.read(sessionProvider.notifier).logout(), trailing: const SizedBox()),
        tile(Icons.delete_outline_rounded, 'Konto löschen', () => _confirmDelete(context, ref), trailing: const SizedBox()),
        if (AppConfig.useMocks)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Demo-Modus: Die App arbeitet mit Beispieldaten, bis die Vibono-Schnittstelle live ist.',
                style: VibonoText.small),
          ),
        const SizedBox(height: 24),
      ]),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konto löschen?'),
        content: const Text(
            'Wir löschen dein Vibono-Konto mit allen App-Daten. Das Vibono-Team bestätigt dir die Löschung per E-Mail.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ABBRECHEN')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('LÖSCHEN')),
        ],
      ),
    );
    if (ok == true) await ref.read(sessionProvider.notifier).deleteAccount();
  }
}
