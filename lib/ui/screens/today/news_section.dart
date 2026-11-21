import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/app_config.dart';
import '../../../data/models/content.dart';
import '../../../data/models/home_feed.dart';
import '../../../services/external_links.dart';
import '../../../state/providers.dart';
import '../../../theme/vibono_colors.dart';
import '../../../theme/vibono_theme.dart';
import '../../navigation.dart';
import '../../widgets/common.dart';
import 'home_widgets.dart';

/// Meldungen, die in dieser App-Version auf der Plattform erlaubt sind.
/// Shop-Links (Angebote, eBooks) nur, wenn `/config` sie freigibt.
List<NewsItem> visibleNews(List<NewsItem> news, RemoteConfig config) => [
      for (final n in news)
        if (switch (n.kind) {
          NewsKind.offer => config.linkPhysicalProducts,
          NewsKind.ebook => config.linkDigitalProducts,
          _ => true,
        })
          n,
    ];

/// „News & Tipp des Tages“: Tipp des Tages, Vibono-Tipp und Neuigkeiten
/// (Blog, Coaching-Brief, eBook, Angebote, Club).
class NewsSection extends ConsumerWidget {
  const NewsSection({super.key, required this.news, required this.tipOfTheDay, this.vibonoTip});
  final List<NewsItem> news;
  final String tipOfTheDay;
  final ContentItem? vibonoTip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(remoteConfigProvider).value ?? RemoteConfig.safeDefault;
    final items = visibleNews(news, config);
    // Der Vibono-Tipp nur, wenn er nicht ohnehin als neuer Blogartikel erscheint.
    final tip = vibonoTip != null && items.any((n) => n.contentId == vibonoTip!.id) ? null : vibonoTip;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const HomeSectionTitle('News & Tipp des Tages'),
      const SizedBox(height: 8),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (tipOfTheDay.isNotEmpty) Expanded(child: _TipOfDayTile(text: tipOfTheDay)),
          if (tipOfTheDay.isNotEmpty && tip != null) const SizedBox(width: 12),
          if (tip != null) Expanded(child: _VibonoTipTile(tip: tip, onTap: () => openContent(context, tip))),
        ]),
      ),
      for (final n in items) ...[
        const SizedBox(height: 12),
        _NewsTile(item: n),
      ],
    ]);
  }
}

class _NewsTile extends StatelessWidget {
  const _NewsTile({required this.item});
  final NewsItem item;

  IconData get _icon => switch (item.kind) {
        NewsKind.blog => Icons.article_outlined,
        NewsKind.offer => Icons.local_offer_outlined,
        NewsKind.club => Icons.groups_outlined,
        NewsKind.coachingLetter => Icons.mail_outline_rounded,
        NewsKind.ebook => Icons.menu_book_outlined,
        NewsKind.info => Icons.info_outline_rounded,
      };

  void _open(BuildContext context) {
    final id = item.contentId;
    if (id != null) {
      openContent(
        context,
        ContentItem(id: id, type: ContentType.tip, title: item.title, excerpt: item.excerpt, thumbnailUrl: item.thumbnailUrl, url: item.url),
      );
    } else if (item.url != null) {
      openWebsite(item.url!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canOpen = item.contentId != null || item.url != null;
    return HomeCard(
      onTap: canOpen ? () => _open(context) : null,
      padding: EdgeInsets.zero,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 84,
          height: 84,
          child: item.thumbnailUrl != null
              ? ContentImage(item.thumbnailUrl)
              : ColoredBox(color: VibonoColors.green050, child: Icon(_icon, color: VibonoColors.green700, size: 26)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.kind.label.toUpperCase(), style: homeTileLabel),
              const SizedBox(height: 3),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: VibonoText.body.copyWith(color: VibonoColors.grey900, fontWeight: FontWeight.w700, height: 1.3),
              ),
              if (item.excerpt.isNotEmpty)
                Text(item.excerpt, maxLines: 2, overflow: TextOverflow.ellipsis, style: VibonoText.small),
              if (canOpen && item.cta != null) ...[
                const SizedBox(height: 4),
                Text('${item.cta!.toUpperCase()} ›', style: homeLinkStyle.copyWith(fontSize: 12)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

class _TipOfDayTile extends StatelessWidget {
  const _TipOfDayTile({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        color: VibonoColors.green050,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lightbulb_outline_rounded, size: 20, color: VibonoColors.green700),
          const SizedBox(height: 8),
          const Text('TIPP DES TAGES', style: homeTileLabel),
          const SizedBox(height: 6),
          Text(text, style: VibonoText.small.copyWith(fontSize: 13, height: 1.5, color: VibonoColors.grey900)),
        ]),
      );
}

class _VibonoTipTile extends StatelessWidget {
  const _VibonoTipTile({required this.tip, required this.onTap});
  final ContentItem tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HomeCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: 64, child: ContentImage(tip.thumbnailUrl)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('VIBONO-TIPP', style: homeTileLabel),
              const SizedBox(height: 4),
              Text(tip.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: VibonoText.small.copyWith(fontSize: 13, height: 1.4, color: VibonoColors.grey900)),
            ]),
          ),
        ]),
      );
}
