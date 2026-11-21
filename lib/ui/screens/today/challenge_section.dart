import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/home_feed.dart';
import '../../../domain/coaching_plan.dart';
import '../../../domain/home_progress.dart';
import '../../../state/home.dart';
import '../../../theme/vibono_colors.dart';
import '../../../theme/vibono_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/day_sheets.dart';
import 'home_widgets.dart';

/// „Aktuelle Challenge“: eigene Challenges mit Fortschritt, darunter die,
/// bei denen man noch mitmachen kann.
class ChallengeSection extends ConsumerWidget {
  const ChallengeSection({super.key, required this.challenges});
  final List<Challenge> challenges;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(challengeEntriesProvider);
    final mine = [for (final c in challenges) if (entries.containsKey(c.id)) c];
    final open = [
      for (final c in challenges)
        if (!entries.containsKey(c.id) && (c.endsOn == null || !CoachingPlan.dateOnly(DateTime.now()).isAfter(c.endsOn!))) c,
    ];
    if (mine.isEmpty && open.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HomeSectionTitle(mine.length > 1 ? 'Deine Challenges' : 'Aktuelle Challenge'),
      const SizedBox(height: 8),
      for (final c in mine) ...[
        _ChallengeCard(challenge: c, entry: entries[c.id]!),
        const SizedBox(height: 12),
      ],
      if (open.isNotEmpty) ...[
        if (mine.isNotEmpty) ...[
          const SectionLabel('Mach auch mit'),
          const SizedBox(height: 8),
        ],
        for (final c in open) ...[
          _JoinCard(challenge: c, highlight: mine.isEmpty && c == open.first),
          const SizedBox(height: 10),
        ],
      ],
    ]);
  }
}

String _until(Challenge c) =>
    c.endsOn == null ? 'ohne Enddatum' : 'bis ${DateFormat('d. MMMM', 'de_DE').format(c.endsOn!)}';

String _kindLine(Challenge c) => switch (c.kind) {
      ChallengeKind.weightLoss => '${formatNumber(c.target)} ${c.unit} · ${_until(c)}',
      ChallengeKind.dailyGoal => '${c.dailyTarget ?? 1} ${c.unit} am Tag, an ${c.target.round()} Tagen · ${_until(c)}',
      ChallengeKind.collect => '${c.target.round()} ${c.unit} · ${_until(c)}',
    };

class _JoinCard extends ConsumerWidget {
  const _JoinCard({required this.challenge, required this.highlight});
  final Challenge challenge;
  final bool highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = challenge;
    return HomeCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          color: VibonoColors.green050,
          child: c.thumbnailUrl != null
              ? ContentImage(c.thumbnailUrl)
              : Icon(_icon(c.kind), color: VibonoColors.green700, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.title, style: VibonoText.body.copyWith(fontWeight: FontWeight.w700, color: VibonoColors.grey900)),
            Text(_kindLine(c), style: VibonoText.small),
            if (highlight && c.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(c.description, style: VibonoText.small.copyWith(color: VibonoColors.grey700, fontSize: 13)),
            ],
            const SizedBox(height: 10),
            HomePillButton('Mitmachen', filled: highlight, onPressed: () async {
              await joinChallenge(ref, c);
              if (context.mounted) showMessage(context, 'Du bist bei „${c.title}“ dabei. Viel Erfolg!');
            }),
          ]),
        ),
      ]),
    );
  }
}

IconData _icon(ChallengeKind k) => switch (k) {
      ChallengeKind.weightLoss => Icons.monitor_weight_outlined,
      ChallengeKind.dailyGoal => Icons.eco_outlined,
      ChallengeKind.collect => Icons.add_task_rounded,
    };

class _ChallengeCard extends ConsumerWidget {
  const _ChallengeCard({required this.challenge, required this.entry});
  final Challenge challenge;
  final ChallengeEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = challenge;
    final today = CoachingPlan.dateOnly(DateTime.now());
    final st = ChallengeProgress.status(c, entry, today, weights: ref.watch(weightEntriesProvider));
    return HomeCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(_icon(c.kind), color: VibonoColors.green700, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.title, style: VibonoText.cardTitle),
              Text(_until(c), style: VibonoText.small),
            ]),
          ),
          PopupMenuButton<String>(
            tooltip: 'Mehr',
            icon: const Icon(Icons.more_horiz_rounded, color: VibonoColors.grey400),
            onSelected: (_) => leaveChallenge(ref, c),
            itemBuilder: (_) => const [PopupMenuItem(value: 'leave', child: Text('Nicht mehr mitmachen'))],
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text(st.label,
                style: VibonoText.body.copyWith(color: VibonoColors.grey900, fontWeight: FontWeight.w700)),
          ),
          if (st.done) const Text('GESCHAFFT', style: homeTileLabel),
        ]),
        const SizedBox(height: 6),
        HomeProgressBar(st.progress),
        if (st.ended && !st.done) ...[
          const SizedBox(height: 8),
          Text('Die Challenge ist vorbei. Jeder Schritt zählt, schau, wie weit du gekommen bist.',
              style: VibonoText.small.copyWith(fontSize: 13)),
        ],
        if (!st.ended) ...[
          const SizedBox(height: 12),
          switch (c.kind) {
            ChallengeKind.weightLoss => _WeightAction(hint: st.hint),
            ChallengeKind.dailyGoal => _DailyCounter(challenge: c, entry: entry, today: today),
            ChallengeKind.collect => _CollectItems(challenge: c, entry: entry),
          },
        ],
      ]),
    );
  }
}

class _WeightAction extends StatelessWidget {
  const _WeightAction({this.hint});
  final String? hint;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Text(hint ?? 'Grüne Rezepte helfen dir dabei. Wieg dich am besten morgens.',
              style: VibonoText.small.copyWith(fontSize: 13)),
        ),
        const SizedBox(width: 10),
        HomePillButton(
          'Gewicht',
          filled: hint != null,
          onPressed: () => showVibonoSheet(context, WeightSheet(date: CoachingPlan.dateOnly(DateTime.now()))),
        ),
      ]);
}

/// Tagesziel: heute zählen, z. B. Portionen Obst und Gemüse.
class _DailyCounter extends ConsumerWidget {
  const _DailyCounter({required this.challenge, required this.entry, required this.today});
  final Challenge challenge;
  final ChallengeEntry entry;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goal = challenge.dailyTarget ?? 1;
    final n = entry.countOn(today);
    void set(int v) => saveChallengeEntry(ref, challenge, entry.withCount(today, v.clamp(0, 50)));
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Heute: $n von $goal ${challenge.unit}', style: VibonoText.body.copyWith(color: VibonoColors.grey900)),
          const SizedBox(height: 4),
          Row(children: [
            for (var i = 0; i < goal; i++)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < n ? VibonoColors.green : Colors.white,
                    border: Border.all(color: i < n ? VibonoColors.green : VibonoColors.grey300, width: 1.5),
                  ),
                ),
              ),
          ]),
        ]),
      ),
      IconButton.outlined(
        tooltip: 'Eine weniger',
        onPressed: n > 0 ? () => set(n - 1) : null,
        icon: const Icon(Icons.remove_rounded),
      ),
      const SizedBox(width: 6),
      IconButton.filled(
        tooltip: 'Eine mehr',
        onPressed: () => set(n + 1),
        icon: const Icon(Icons.add_rounded),
      ),
    ]);
  }
}

/// Sammeln: z. B. neue Lebensmittel eintragen.
class _CollectItems extends ConsumerWidget {
  const _CollectItems({required this.challenge, required this.entry});
  final Challenge challenge;
  final ChallengeEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> add(String v) async {
      final t = v.trim();
      if (t.isEmpty || entry.items.contains(t)) return;
      await saveChallengeEntry(ref, challenge, entry.withItems([...entry.items, t]));
    }

    final ideas = challenge.suggestions.where((s) => !entry.items.contains(s)).take(4).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (entry.items.isNotEmpty)
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final i in entry.items)
            InputChip(
              label: Text(i),
              avatar: const Icon(Icons.check_rounded, size: 16, color: VibonoColors.green700),
              visualDensity: VisualDensity.compact,
              onDeleted: () => saveChallengeEntry(ref, challenge, entry.withItems([...entry.items]..remove(i))),
              deleteButtonTooltipMessage: '„$i“ entfernen',
            ),
        ]),
      if (entry.items.length < challenge.target) ...[
        if (entry.items.isNotEmpty) const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in ideas)
            ActionChip(
              label: Text(s),
              avatar: const Icon(Icons.add_rounded, size: 16, color: VibonoColors.green700),
              visualDensity: VisualDensity.compact,
              onPressed: () => add(s),
            ),
          ActionChip(
            label: const Text('Eigenes eintragen'),
            avatar: const Icon(Icons.edit_outlined, size: 16, color: VibonoColors.green700),
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              final c = TextEditingController();
              final v = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Was hast du probiert?'),
                  content: TextField(
                    controller: c,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'z. B. Pastinake'),
                    onSubmitted: (v) => Navigator.pop(ctx, v),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                    TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Eintragen')),
                  ],
                ),
              );
              if (v != null) await add(v);
            },
          ),
        ]),
      ],
    ]);
  }
}
