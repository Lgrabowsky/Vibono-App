import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/sync_item.dart';
import '../../state/providers.dart';
import '../navigation.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';

class TipsScreen extends ConsumerWidget {
  const TipsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tips = ref.watch(tipsProvider);
    final sync = ref.watch(syncProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('VIBONO-TIPPS')),
      body: switch (tips) {
        AsyncData(:final value) => ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: value.length,
            separatorBuilder: (_, _) => const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
            itemBuilder: (_, i) => TipCard(
              tip: value[i],
              label: sync.has(SyncCollection.favorites, 'tip:${value[i].id}') ? 'Gemerkt' : 'Vibono-Tipp',
              onTap: () => openContent(context, value[i]),
            ),
          ),
        AsyncError() => ErrorRetry(message: 'Tipps konnten nicht geladen werden.', onRetry: () => ref.invalidate(tipsProvider)),
        _ => const LoadingView(),
      },
    );
  }
}
