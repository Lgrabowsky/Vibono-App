import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/coaching_day.dart';
import '../../data/models/json.dart';
import '../../data/models/sync_item.dart';
import '../../state/day_checks.dart';
import '../../state/providers.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';

Future<void> showVibonoSheet(BuildContext context, Widget child) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: child,
      ),
    );

/// „3× satt essen“ abhaken.
class MealsSheet extends ConsumerWidget {
  const MealsSheet({super.key, required this.date, required this.rule});
  final DateTime date;
  final String rule;

  static const meals = {'fruehstueck': 'Frühstück', 'mittag': 'Mittagessen', 'abend': 'Abendessen'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checks = ref.watch(dayChecksProvider(dayKey(date)));
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Satt gegessen?', style: VibonoText.hello),
      const SizedBox(height: 4),
      Text(rule, style: VibonoText.body),
      const SizedBox(height: 12),
      for (final m in meals.entries)
        CheckboxListTile(
          value: checks.contains('meal:${m.key}'),
          onChanged: (_) => ref.read(dayChecksProvider(dayKey(date)).notifier).toggle('meal:${m.key}'),
          title: Text(m.value, style: VibonoText.cardTitle),
          activeColor: VibonoColors.green,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
        ),
    ]);
  }
}

int sportMinutes(Iterable<SyncItem> sport, String day) => sport
    .where((i) => i.data['date'] == day)
    .fold(0, (sum, i) => sum + (asInt(i.data['minutes']) ?? 0));

/// Bewegung eintragen (landet in „Mein Sport“ auf MyVibono).
class SportSheet extends ConsumerWidget {
  const SportSheet({super.key, required this.date, required this.target});
  final DateTime date;
  final int target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);
    final day = dayKey(date);
    final done = sportMinutes(sync.items(SyncCollection.sport), day);
    Future<void> add(int minutes) => sync.upsert(SyncCollection.sport, 'app-${DateTime.now().microsecondsSinceEpoch}', {
          'date': day,
          'activity': 'gehen',
          'minutes': minutes,
        });
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Bewegung', style: VibonoText.hello),
      const SizedBox(height: 4),
      Text('Heute: $done von $target Minuten. Jede Minute zählt, auch der Weg zum Bäcker.', style: VibonoText.body),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in [5, 10, 20, 30])
          ActionChip(label: Text('+ $m Min.'), onPressed: () => add(m)),
      ]),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: done >= target
              ? () => Navigator.pop(context)
              : () async {
                  await add(target - done);
                  if (context.mounted) Navigator.pop(context);
                },
          child: Text(done >= target ? 'FERTIG' : 'ALLES GESCHAFFT'),
        ),
      ),
    ]);
  }
}

/// Gewicht eintragen (landet in „Mein Gewicht“ auf MyVibono).
class WeightSheet extends ConsumerStatefulWidget {
  const WeightSheet({super.key, required this.date});
  final DateTime date;

  @override
  ConsumerState<WeightSheet> createState() => _WeightSheetState();
}

class _WeightSheetState extends ConsumerState<WeightSheet> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    final sync = ref.read(syncProvider);
    final existing = asDouble(sync.get(SyncCollection.weight, dayKey(widget.date))?['kg']);
    final last = sync.items(SyncCollection.weight).toList()
      ..sort((a, b) => '${b.data['date']}'.compareTo('${a.data['date']}'));
    final fallback = last.isEmpty ? ref.read(sessionProvider).profile.startWeightKg : asDouble(last.first.data['kg']);
    final v = existing ?? fallback;
    _c = TextEditingController(text: v == null ? '' : v.toStringAsFixed(1).replaceAll('.', ','));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final kg = asDouble(_c.text);
    if (kg == null || kg < 30 || kg > 400) return;
    final day = dayKey(widget.date);
    await ref.read(syncProvider).upsert(SyncCollection.weight, day, {'date': day, 'kg': kg});
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Gewicht eintragen', style: VibonoText.hello),
          const SizedBox(height: 4),
          const Text('Am besten morgens vor dem Frühstück, immer unter gleichen Bedingungen.', style: VibonoText.body),
          const SizedBox(height: 14),
          TextField(
            controller: _c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontFamily: VibonoFonts.display, fontSize: 28),
            decoration: const InputDecoration(suffixText: 'kg'),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: _save, child: const Text('SPEICHERN'))),
        ],
      );
}

String essenRule(PhaseKey phase) => switch (phase) {
      PhaseKey.vorbereitung => 'Noch iss wie gewohnt. Nutze die Zeit, um dich vorzubereiten.',
      PhaseKey.phase1 => 'Umstellungstag: Eiweiß und Gemüse, keine Kohlenhydrate. Iss dich 3× richtig satt.',
      PhaseKey.phase2 => 'Iss dich 3× am Tag satt, am besten mit Lebensmitteln mit grüner Energiedichte. Keine Snacks.',
      PhaseKey.phase3 => 'Satt essen und genießen. Grüne Lebensmittel als Basis, Gelbes und Rotes bewusst.',
    };
