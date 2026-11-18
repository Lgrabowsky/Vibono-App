import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/points.dart';
import '../../services/external_links.dart';
import '../../state/providers.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import '../navigation.dart';
import '../widgets/common.dart';
import '../widgets/streak.dart';
import 'referral_screen.dart';

/// Punkte: Stand, Aktionen, wie man sammelt, Verlauf.
///
/// Keine Preise und keine Kauf-Buttons. Der Gegenwert und die Einlösung im
/// Vibono-Shop erscheinen nur, wenn `GET /config` das für die Plattform
/// freigibt (`shop_links.points_redemption`). Freunde werben und Shop-Punkte
/// erscheinen erst, wenn das Modul auf vibono.de eingeschaltet ist
/// (`features.referral`, `features.shop_points`).
class PointsScreen extends ConsumerWidget {
  const PointsScreen({super.key});

  static const reasonLabels = {
    'app_open': 'Täglich die App öffnen',
    'article_read': 'Einen Beitrag lesen',
    'referral': 'Freundin oder Freund werben',
    'referral_friend': 'Willkommensbonus',
    'purchase': 'Einkauf im Vibono-Shop',
    'purchase_per_euro': 'Je Euro Einkauf im Vibono-Shop',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(pointsProvider);
    final ledger = ref.watch(ledgerProvider);
    final config = ref.watch(remoteConfigProvider).value;
    final showValue = config?.linkPointsRedemption ?? false;
    final showPurchase = (config?.featureShopPoints ?? false) && (config?.linkPhysicalProducts ?? false);
    final showReferral = config?.featureReferral ?? false;
    bool visibleReason(String r) => r.startsWith('purchase')
        ? showPurchase
        : r.startsWith('referral')
            ? showReferral
            : true;
    final campaigns = summary.value?.campaigns.where((c) =>
            c.active && (c.reasons.isEmpty || c.reasons.any(visibleReason)) && (c.kind != 'redeem' || showValue)) ??
        const <Campaign>[];

    return Scaffold(
      appBar: AppBar(title: const Text('MEINE PUNKTE')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(pointsProvider);
          ref.invalidate(ledgerProvider);
          await ref.read(pointsProvider.future);
        },
        child: ListView(padding: const EdgeInsets.all(16), children: [
          switch (summary) {
            AsyncData(:final value) => _Balance(summary: value, showValue: showValue),
            AsyncError() => ErrorRetry(message: 'Punkte konnten nicht geladen werden.', onRetry: () => ref.invalidate(pointsProvider)),
            _ => const SizedBox(height: 140, child: LoadingView()),
          },
          if (showValue) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => openVibonoAccountPage(ref, '/shop/'),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('IM VIBONO-SHOP EINLÖSEN'),
            ),
          ],
          for (final c in campaigns) ...[
            const SizedBox(height: 12),
            _CampaignBanner(campaign: c, showRedeem: showValue),
          ],
          if (summary.value?.streak.enabled ?? false) ...[
            const SizedBox(height: 20),
            const SectionLabel('Deine Serie'),
            const SizedBox(height: 6),
            StreakLadder(streak: ref.watch(appStreakProvider) ?? summary.value!.streak),
          ],
          const SizedBox(height: 20),
          const SectionLabel('So sammelst du Punkte'),
          const SizedBox(height: 4),
          if (summary.value != null)
            for (final e in summary.value!.earnRules.entries)
              if (reasonLabels.containsKey(e.key) && visibleReason(e.key))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(_icon(e.key), color: VibonoColors.green),
                  title: Text(reasonLabels[e.key]!, style: VibonoText.body),
                  subtitle: e.key == 'app_open' && summary.value!.streak.enabled
                      ? const Text('Mehr Punkte, je mehr Tage in Folge', style: VibonoText.small)
                      : null,
                  trailing: Text('+${formatPoints(e.value)}', style: VibonoText.cardTitle),
                  onTap: e.key == 'referral' && showReferral ? () => push(context, const ReferralScreen()) : null,
                ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(Icons.verified_outlined, color: VibonoColors.green),
            title: Text(
              'Lesepunkte gibt es, wenn du einen Beitrag wirklich bis zum Ende gelesen hast, einmal pro Beitrag.',
              style: VibonoText.small,
            ),
          ),
          const SizedBox(height: 16),
          const SectionLabel('Verlauf'),
          switch (ledger) {
            AsyncData(:final value) => Column(children: [
                for (final e in value)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(e.label, style: VibonoText.body),
                    subtitle: Text(
                      '${DateFormat('d. MMMM yyyy', 'de_DE').format(e.createdAt.toLocal())}${e.status == 'pending' ? ' · vorgemerkt' : ''}',
                      style: VibonoText.small,
                    ),
                    trailing: Text(
                      '${e.points > 0 ? '+' : ''}${formatPoints(e.points)}',
                      style: VibonoText.cardTitle.copyWith(
                        color: e.points >= 0 ? VibonoColors.green700 : VibonoColors.grey500,
                      ),
                    ),
                  ),
              ]),
            _ => const SizedBox.shrink(),
          },
        ]),
      ),
    );
  }

  static IconData _icon(String k) => switch (k) {
        'app_open' => Icons.wb_sunny_outlined,
        'article_read' => Icons.menu_book_rounded,
        'referral' => Icons.group_add_outlined,
        'purchase' || 'purchase_per_euro' => Icons.shopping_bag_outlined,
        _ => Icons.star_outline_rounded,
      };
}

class _Balance extends StatelessWidget {
  const _Balance({required this.summary, required this.showValue});
  final PointsSummary summary;
  final bool showValue;

  @override
  Widget build(BuildContext context) {
    final euro = NumberFormat.currency(locale: 'de_DE', symbol: '€').format(summary.valueCents / 100);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: VibonoColors.green, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        const Icon(Icons.star_rounded, size: 46, color: Colors.white),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              formatPoints(summary.balance),
              style: const TextStyle(
                fontFamily: VibonoFonts.display,
                fontSize: 40,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                height: 1,
              ),
            ),
            const Text('Punkte', style: TextStyle(fontFamily: VibonoFonts.display, fontSize: 16, color: Colors.white)),
            if (showValue)
              Text('entspricht $euro Guthaben im Vibono-Shop',
                  style: VibonoText.small.copyWith(color: Colors.white)),
            if (summary.pending > 0)
              Text('+${formatPoints(summary.pending)} vorgemerkt', style: VibonoText.small.copyWith(color: Colors.white)),
          ]),
        ),
      ]),
    );
  }
}

class _CampaignBanner extends StatelessWidget {
  const _CampaignBanner({required this.campaign, required this.showRedeem});
  final Campaign campaign;
  final bool showRedeem;

  @override
  Widget build(BuildContext context) {
    // Einlöse-Aktionen nur zeigen, wenn Einlösen verlinkt werden darf.
    if (campaign.kind == 'redeem' && !showRedeem) return const SizedBox.shrink();
    final until = campaign.endsAt == null ? '' : ' · bis ${DateFormat('d. MMMM', 'de_DE').format(campaign.endsAt!.toLocal())}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: VibonoColors.gelb.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
          child: Text('×${campaign.multiplier.toStringAsFixed(campaign.multiplier % 1 == 0 ? 0 : 1)}',
              style: VibonoText.cardTitle.copyWith(color: VibonoColors.grey900)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${campaign.name}$until', style: VibonoText.cardTitle),
            Text(campaign.description, style: VibonoText.small.copyWith(color: VibonoColors.grey700)),
          ]),
        ),
      ]),
    );
  }
}
