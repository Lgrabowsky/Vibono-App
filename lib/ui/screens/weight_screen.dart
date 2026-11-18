import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/json.dart';
import '../../data/models/sync_item.dart';
import '../../domain/coaching_plan.dart';
import '../../state/providers.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import '../navigation.dart';
import '../widgets/common.dart';
import '../widgets/day_sheets.dart';
import 'onboarding/onboarding_screen.dart';

String kg(double v) => '${v.toStringAsFixed(1).replaceAll('.', ',')} kg';

/// Mein Gewicht & Etappenziele (3, 6, 12 Monate).
class WeightScreen extends ConsumerWidget {
  const WeightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(sessionProvider).profile;
    final entries = ref.watch(syncProvider).items(SyncCollection.weight).toList()
      ..sort((a, b) => '${b.data['date']}'.compareTo('${a.data['date']}'));
    final current = entries.isEmpty ? p.startWeightKg : asDouble(entries.first.data['kg']);
    final start = p.startWeightKg ?? current;

    return Scaffold(
      appBar: AppBar(title: const Text('MEIN GEWICHT')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: VibonoColors.green,
        foregroundColor: Colors.white,
        onPressed: () => showVibonoSheet(context, WeightSheet(date: CoachingPlan.dateOnly(DateTime.now()))),
        icon: const Icon(Icons.add),
        label: const Text('EINTRAGEN'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        if (current != null)
          Center(
            child: Column(children: [
              Text(kg(current),
                  style: const TextStyle(fontFamily: VibonoFonts.display, fontSize: 44, fontWeight: FontWeight.w300)),
              if (start != null && start > current)
                Text('${kg(start - current)} weniger als zum Start', style: VibonoText.body.copyWith(color: VibonoColors.green700)),
            ]),
          ),
        const SizedBox(height: 16),
        const SectionLabel('Deine Etappenziele'),
        const SizedBox(height: 6),
        for (final (label, target) in [('3 Monate', p.target3m), ('6 Monate', p.target6m), ('12 Monate', p.target12m)])
          if (target != null)
            _GoalRow(label: label, target: target, start: start, current: current),
        TextButton(
          onPressed: () => push(context, const OnboardingScreen(editMode: true, startAt: OnboardingStep.ziele)),
          child: const Text('ZIELE ANPASSEN'),
        ),
        const SizedBox(height: 10),
        const SectionLabel('Verlauf'),
        if (entries.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Noch keine Einträge.', style: VibonoText.body)),
        for (final e in entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(kg(asDouble(e.data['kg']) ?? 0), style: VibonoText.cardTitle),
            subtitle: Text(DateFormat('EEEE, d. MMMM yyyy', 'de_DE').format(DateTime.parse('${e.data['date']}')),
                style: VibonoText.small),
            trailing: IconButton(
              tooltip: 'Löschen',
              icon: const Icon(Icons.delete_outline, color: VibonoColors.grey400),
              onPressed: () => ref.read(syncProvider).remove(SyncCollection.weight, e.key),
            ),
          ),
        const SizedBox(height: 6),
        const Text('Wird mit „Mein Gewicht“ auf vibono.de abgeglichen.', style: VibonoText.small),
      ]),
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.label, required this.target, required this.start, required this.current});
  final String label;
  final double target;
  final double? start;
  final double? current;

  @override
  Widget build(BuildContext context) {
    final s = start, c = current;
    final progress = s == null || c == null || s <= target ? 0.0 : ((s - c) / (s - target)).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(width: 82, child: Text(label, style: VibonoText.cardTitle.copyWith(fontSize: 15))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: VibonoColors.grey100),
          ),
        ),
        SizedBox(
          width: 76,
          child: Text(kg(target),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontFamily: VibonoFonts.display, fontWeight: FontWeight.w700, fontSize: 16, color: VibonoColors.green700)),
        ),
      ]),
    );
  }
}
