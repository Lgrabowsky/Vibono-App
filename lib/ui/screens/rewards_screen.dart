import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api/api_exception.dart';
import '../../data/models/content.dart';
import '../../data/models/rewards.dart';
import '../../state/providers.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import '../navigation.dart';
import '../widgets/common.dart';
import '../widgets/day_sheets.dart';
import 'article_screen.dart';
import 'recipe_detail_screen.dart';

/// Prämien: Punkte gegen exklusive Inhalte, eBooks/PDFs und (wo erlaubt)
/// Rabatt auf die Verlängerung einlösen.
///
/// Es gibt keine Käufe: Punkte lassen sich nicht mit Geld kaufen, nur durch
/// Coaching, Lesen, die Serie beim Öffnen und Werben sammeln. Welche
/// Prämienarten die App einlösen darf, steuert `GET /config`
/// (`features.reward_kinds`); den Rest gibt es auf vibono.de unter Mein Konto.
class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key});

  static const kindTitles = {
    RewardKind.content: 'Exklusive Rezepte und Tipps',
    RewardKind.download: 'eBooks und PDFs',
    RewardKind.renewalDiscount: 'Rabatt auf deine Verlängerung',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(rewardsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('PRÄMIEN')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(rewardsProvider.future),
        child: switch (catalog) {
          AsyncData(:final value) when value == null => ListView(padding: const EdgeInsets.all(24), children: const [
              Text('Prämien gibt es hier bald. Sammle schon fleißig Punkte!', style: VibonoText.body),
            ]),
          AsyncData(:final value) => _Catalog(catalog: value!),
          AsyncError(:final error) => ErrorRetry(
              message: error is ApiException ? error.userMessage : 'Prämien konnten nicht geladen werden.',
              onRetry: () => ref.invalidate(rewardsProvider),
            ),
          _ => const LoadingView(),
        },
      ),
    );
  }
}

class _Catalog extends ConsumerWidget {
  const _Catalog({required this.catalog});
  final RewardCatalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(pointsBalanceProvider) ?? catalog.balance;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: VibonoColors.green050, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          const Icon(Icons.redeem_rounded, color: VibonoColors.green, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Du hast ${formatPoints(balance)} Punkte', style: VibonoText.cardTitle),
              const Text('Tausche sie gegen exklusive Inhalte. Einmal freigeschaltet, gehören sie dir.',
                  style: VibonoText.small),
            ]),
          ),
        ]),
      ),
      for (final kind in RewardKind.values)
        if (catalog.items.any((r) => r.kind == kind)) ...[
          const SizedBox(height: 20),
          SectionLabel(RewardsScreen.kindTitles[kind]!),
          const SizedBox(height: 6),
          for (final r in catalog.items.where((r) => r.kind == kind)) RewardTile(reward: r, balance: balance),
        ],
      if (catalog.items.isEmpty) ...[
        const SizedBox(height: 24),
        const Text('Gerade gibt es keine Prämien. Schau bald wieder vorbei!', style: VibonoText.body),
      ],
      if (catalog.unlocked.isNotEmpty) ...[
        const SizedBox(height: 24),
        const SectionLabel('Meine Prämien'),
        const SizedBox(height: 6),
        for (final u in catalog.unlocked) _UnlockTile(unlock: u),
      ],
      const SizedBox(height: 16),
      const Text(
        'Punkte sammelst du mit deinem Coaching, beim Lesen, mit deiner Serie und wenn du Freundinnen und Freunde wirbst. '
        'Punkte lassen sich nicht kaufen und nicht auszahlen.',
        style: VibonoText.small,
      ),
    ]);
  }
}

/// Eine Prämie mit Preis und passender Aktion.
class RewardTile extends ConsumerWidget {
  const RewardTile({super.key, required this.reward, required this.balance});
  final Reward reward;
  final int balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = reward;
    final missing = r.costPoints - balance;
    final subtitle = [
      if (r.description.isNotEmpty) r.description,
      if (r.discountLabel != null) '${r.discountLabel}${r.validDays != null ? ', ${r.validDays} Tage gültig' : ''}',
      if (r.fileSizeBytes != null) 'PDF, ${(r.fileSizeBytes! / 1000000).toStringAsFixed(1).replaceAll('.', ',')} MB',
    ].join(' · ');
    final Widget action;
    if (r.unlocked) {
      action = TextButton(
        onPressed: () => openRewardTarget(context, ref, r.kind, rewardId: r.id, postId: r.postId, contentType: r.contentType),
        child: Text(r.kind == RewardKind.download ? 'LADEN' : 'ÖFFNEN'),
      );
    } else if (r.canRedeem) {
      action = FilledButton(onPressed: () => confirmRedeem(context, ref, r, balance), child: const Text('EINLÖSEN'));
    } else if (r.unavailableReason == 'limit_reached') {
      action = const Text('eingelöst', style: VibonoText.small);
    } else {
      action = Text('noch ${formatPoints(missing > 0 ? missing : r.costPoints)}\nPunkte',
          style: VibonoText.small, textAlign: TextAlign.center);
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: VibonoColors.grey100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 56,
              height: 56,
              child: r.imageUrl != null
                  ? ContentImage(r.imageUrl)
                  : Container(
                      color: VibonoColors.green050,
                      child: Icon(_icon(r.kind), color: VibonoColors.green700),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.title, style: VibonoText.cardTitle),
              if (subtitle.isNotEmpty) Text(subtitle, style: VibonoText.small, maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.star_rounded, size: 16, color: VibonoColors.green),
                const SizedBox(width: 3),
                Text('${formatPoints(r.costPoints)} Punkte',
                    style: VibonoText.small.copyWith(color: VibonoColors.green900, fontWeight: FontWeight.w600)),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          action,
        ]),
      ),
    );
  }

  static IconData _icon(RewardKind k) => switch (k) {
        RewardKind.content => Icons.lock_open_rounded,
        RewardKind.download => Icons.menu_book_rounded,
        RewardKind.renewalDiscount => Icons.local_offer_outlined,
      };
}

class _UnlockTile extends ConsumerWidget {
  const _UnlockTile({required this.unlock});
  final RewardUnlock unlock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = unlock;
    final date = DateFormat('d. MMMM yyyy', 'de_DE').format(u.createdAt.toLocal());
    if (u.coupon != null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.local_offer_outlined, color: VibonoColors.green),
        title: Text(u.title, style: VibonoText.body),
        subtitle: Text(
          u.coupon!.used
              ? 'Gutschein ${u.coupon!.code} · eingelöst'
              : 'Gutschein ${u.coupon!.code}${u.coupon!.expiresAt != null ? ' · gültig bis ${DateFormat('d.M.yyyy').format(u.coupon!.expiresAt!.toLocal())}' : ''}',
          style: VibonoText.small,
        ),
        trailing: IconButton(
          tooltip: 'Code kopieren',
          icon: const Icon(Icons.copy_rounded),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: u.coupon!.code));
            showMessage(context, 'Gutscheincode kopiert');
          },
        ),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(u.kind == RewardKind.download ? Icons.menu_book_rounded : Icons.lock_open_rounded, color: VibonoColors.green),
      title: Text(u.title, style: VibonoText.body),
      subtitle: Text('Freigeschaltet am $date', style: VibonoText.small),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => openRewardTarget(context, ref, u.kind, rewardId: u.rewardId, postId: u.postId),
    );
  }
}

/// Freigeschaltete Prämie öffnen: Beitrag lesen oder Datei herunterladen.
Future<void> openRewardTarget(BuildContext context, WidgetRef ref, RewardKind kind,
    {required int rewardId, int? postId, String? contentType}) async {
  if (kind == RewardKind.download) {
    try {
      final uri = await ref.read(apiProvider).rewardDownload(rewardId);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.userMessage);
    }
    return;
  }
  if (postId == null) return;
  ref.invalidate(contentItemProvider(postId));
  final page = contentType == 'recipe'
      ? RecipeDetailScreen(recipeId: postId)
      : contentType == null
          ? _ContentById(postId: postId)
          : ArticleScreen(contentId: postId);
  await push<void>(context, page);
}

/// Öffnet einen Beitrag, dessen Art (Rezept oder Artikel) erst beim Laden feststeht.
class _ContentById extends ConsumerWidget {
  const _ContentById({required this.postId});
  final int postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(contentItemProvider(postId));
    return switch (item) {
      AsyncData(:final value) => value.type == ContentType.recipe
          ? RecipeDetailScreen(recipeId: postId, preview: value)
          : ArticleScreen(contentId: postId, preview: value),
      AsyncError() => Scaffold(
          appBar: AppBar(),
          body: ErrorRetry(message: 'Der Beitrag konnte nicht geladen werden.', onRetry: () => ref.invalidate(contentItemProvider(postId))),
        ),
      _ => const Scaffold(body: LoadingView()),
    };
  }
}

/// Nachfragen, einlösen, Ergebnis zeigen. Mit [inPlace] steht der Inhalt schon
/// auf dem Bildschirm (Freischalten direkt am Beitrag) und lädt dort neu.
Future<void> confirmRedeem(BuildContext context, WidgetRef ref, Reward r, int balance, {bool inPlace = false}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r.title, style: VibonoText.hello),
        const SizedBox(height: 8),
        Text(
          'Für ${formatPoints(r.costPoints)} Punkte einlösen? Danach hast du noch ${formatPoints(balance - r.costPoints)} Punkte.',
          style: VibonoText.body,
        ),
        if (r.kind == RewardKind.renewalDiscount) ...[
          const SizedBox(height: 6),
          Text('Du bekommst einen persönlichen Gutscheincode (${r.discountLabel ?? 'Rabatt'}).', style: VibonoText.small),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ABBRECHEN'))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('EINLÖSEN'))),
        ]),
      ]),
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    final res = await ref.read(apiProvider).redeemReward(r.id, platformName);
    refreshPointsViews(ref, balance: res.balance);
    if (r.postId != null) {
      ref.invalidate(contentItemProvider(r.postId!));
      ref.invalidate(recipesProvider);
      ref.invalidate(tipsProvider);
    }
    if (!context.mounted) return;
    await showVibonoSheet(
      context,
      _RedeemedSheet(
        reward: r,
        unlock: res.unlock,
        inPlace: inPlace,
        onOpen: () => openRewardTarget(context, ref, r.kind, rewardId: r.id, postId: r.postId, contentType: r.contentType),
      ),
    );
  } on ApiException catch (e) {
    if (context.mounted) showMessage(context, e.userMessage);
  }
}

class _RedeemedSheet extends StatelessWidget {
  const _RedeemedSheet({required this.reward, required this.unlock, required this.onOpen, this.inPlace = false});
  final Reward reward;
  final RewardUnlock unlock;
  final bool inPlace;

  /// Öffnet Beitrag oder Datei (mit dem Kontext der aufrufenden Seite).
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final coupon = unlock.coupon;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Icon(Icons.celebration_rounded, size: 44, color: VibonoColors.green),
      const SizedBox(height: 8),
      const Text('Freigeschaltet!', style: VibonoText.hello, textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text(reward.title, style: VibonoText.body, textAlign: TextAlign.center),
      const SizedBox(height: 16),
      if (coupon != null) ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: VibonoColors.green050, borderRadius: BorderRadius.circular(12)),
          child: SelectableText(coupon.code, textAlign: TextAlign.center, style: VibonoText.hello),
        ),
        const SizedBox(height: 8),
        Text(
          'Dein persönlicher Code (${coupon.label}). Gib ihn bei deiner nächsten Verlängerung ein.',
          style: VibonoText.small,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: coupon.code));
            showMessage(context, 'Gutscheincode kopiert');
          },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('CODE KOPIEREN'),
        ),
      ] else
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            if (!inPlace) onOpen();
          },
          child: Text(inPlace
              ? 'WEITER'
              : reward.kind == RewardKind.download
                  ? 'JETZT HERUNTERLADEN'
                  : 'JETZT ANSEHEN'),
        ),
    ]);
  }
}

/// Exklusiver Beitrag, der noch nicht freigeschaltet ist: Hinweis mit Preis
/// und „Freischalten“. Erscheint statt des Inhalts (Antwort 403
/// `vibono_reward_required`).
class ExclusiveUnlockPanel extends ConsumerWidget {
  const ExclusiveUnlockPanel({super.key, required this.postId, required this.error, this.title});
  final int postId;
  final ApiException error;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cost = (error.data['cost_points'] as num?)?.toInt() ?? 0;
    final rewardId = (error.data['reward_id'] as num?)?.toInt();
    final balance = ref.watch(pointsBalanceProvider) ?? 0;
    final config = ref.watch(remoteConfigProvider).value;
    final inApp = config?.rewardKinds.contains('content') ?? false;
    final enough = balance >= cost;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(color: VibonoColors.green050, shape: BoxShape.circle),
            child: const Icon(Icons.lock_rounded, size: 40, color: VibonoColors.green700),
          ),
          const SizedBox(height: 14),
          const Text('Exklusiv für Vibono-Punkte', style: VibonoText.hello, textAlign: TextAlign.center),
          if (title != null) ...[
            const SizedBox(height: 4),
            Text(title!, style: VibonoText.cardTitle, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 8),
          Text(
            'Schalte diesen Beitrag mit ${formatPoints(cost)} Punkten dauerhaft frei. Du hast ${formatPoints(balance)} Punkte.',
            style: VibonoText.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          if (rewardId != null && inApp && enough)
            FilledButton(
              onPressed: () => confirmRedeem(
                context,
                ref,
                Reward(
                  id: rewardId,
                  kind: RewardKind.content,
                  title: title ?? 'Exklusiver Beitrag',
                  costPoints: cost,
                  canRedeem: true,
                  postId: postId,
                ),
                balance,
                inPlace: true,
              ),
              child: Text('FÜR ${formatPoints(cost)} PUNKTE FREISCHALTEN'),
            )
          else if (inApp)
            Text('Dir fehlen noch ${formatPoints(cost - balance)} Punkte.', style: VibonoText.cardTitle)
          else
            const Text('Freischalten kannst du ihn auf vibono.de in deinem Konto.', style: VibonoText.small,
                textAlign: TextAlign.center),
          const SizedBox(height: 8),
          TextButton(onPressed: () => push<void>(context, const RewardsScreen()), child: const Text('ALLE PRÄMIEN')),
        ]),
      ),
    );
  }
}
