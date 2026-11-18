import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/points.dart';
import '../../state/providers.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import '../widgets/common.dart';

/// Freunde werben: eigener Code und Link, Zähler, laufende Aktion.
class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(referralProvider);
    final campaign = ref
        .watch(pointsProvider)
        .value
        ?.campaigns
        .where((c) => c.active && c.kind == 'earn' && (c.reasons.isEmpty || c.reasons.contains('referral')))
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('FREUNDE EINLADEN')),
      body: switch (info) {
        AsyncData(value: null) => const _NotYetAvailable(),
        AsyncData(:final value?) => ListView(padding: const EdgeInsets.all(20), children: [
            const Text('Gemeinsam abnehmen macht mehr Spaß.', style: VibonoText.hello),
            const SizedBox(height: 6),
            Text(
              'Teile deinen Link. Für jede Person, die über deinen Link Vibono-Kundin oder -Kunde wird, bekommst du '
              '${formatPoints(value.pointsPerReferral)} Punkte. Deine Freunde erhalten ${formatPoints(value.friendBonusPoints)} Punkte Willkommensbonus.',
              style: VibonoText.body,
            ),
            if (campaign != null) ...[
              const SizedBox(height: 12),
              _Campaign(campaign: campaign),
            ],
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: VibonoColors.green050, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                const SectionLabel('Dein Code'),
                const SizedBox(height: 4),
                SelectableText(
                  value.code,
                  style: const TextStyle(
                    fontFamily: VibonoFonts.display,
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                    color: VibonoColors.grey900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(value.link, style: VibonoText.small),
              ]),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => SharePlus.instance.share(ShareParams(text: '${value.shareText} ${value.link}')),
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: const Text('LINK TEILEN'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value.link));
                if (context.mounted) showMessage(context, 'Link kopiert');
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('LINK KOPIEREN'),
            ),
            const SizedBox(height: 22),
            Row(children: [
              _Stat(value: '${value.invited}', label: 'eingeladen'),
              _Stat(value: '${value.converted}', label: 'Kunden geworden'),
              _Stat(value: formatPoints(value.pointsEarned), label: 'Punkte erhalten'),
            ]),
            const SizedBox(height: 18),
            const Text(
              'Die Punkte werden gutgeschrieben, sobald die erste Bestellung deiner Freunde abgeschlossen und die '
              'Widerrufsfrist abgelaufen ist.',
              style: VibonoText.small,
            ),
          ]),
        AsyncError() =>
          ErrorRetry(message: 'Dein Einladungslink konnte nicht geladen werden.', onRetry: () => ref.invalidate(referralProvider)),
        _ => const LoadingView(),
      },
    );
  }
}

/// „Freunde werben“ ist auf vibono.de noch ausgeschaltet. Kein Fehler.
class _NotYetAvailable extends StatelessWidget {
  const _NotYetAvailable();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.group_add_outlined, size: 48, color: VibonoColors.green),
            SizedBox(height: 12),
            Text('Freunde einladen kommt bald.', textAlign: TextAlign.center, style: VibonoText.cardTitle),
            SizedBox(height: 6),
            Text(
              'Sobald es losgeht, findest du hier deinen persönlichen Einladungslink.',
              textAlign: TextAlign.center,
              style: VibonoText.body,
            ),
          ]),
        ),
      );
}

class _Campaign extends StatelessWidget {
  const _Campaign({required this.campaign});
  final Campaign campaign;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: VibonoColors.gelb.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(12)),
        child: Text(
          '${campaign.name}: ${campaign.description}'
          '${campaign.endsAt == null ? '' : ' Nur bis ${DateFormat('d. MMMM', 'de_DE').format(campaign.endsAt!.toLocal())}.'}',
          style: VibonoText.body.copyWith(color: VibonoColors.grey900),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value,
              style: const TextStyle(
                  fontFamily: VibonoFonts.display, fontSize: 24, fontWeight: FontWeight.w600, color: VibonoColors.green700)),
          Text(label, textAlign: TextAlign.center, style: VibonoText.small),
        ]),
      );
}
