import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/profile.dart';
import '../../services/notification_service.dart';
import '../../state/providers.dart';
import '../../theme/vibono_theme.dart';
import '../widgets/common.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  late Profile _p = ref.read(sessionProvider).profile;
  bool _saving = false;

  Future<void> _pickTime(bool start) async {
    final cur = (start ? _p.quietStart : _p.quietEnd).split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(cur[0]), minute: int.parse(cur[1])),
    );
    if (t == null) return;
    final v = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() => _p = start ? _p.copyWith(quietStart: v) : _p.copyWith(quietEnd: v));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(sessionProvider.notifier).saveProfile(_p);
      await ref.read(notificationServiceProvider).reschedule();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) showMessage(context, 'Speichern hat nicht geklappt. Bitte versuche es noch einmal.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('BENACHRICHTIGUNGEN')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Center(
            child: Text('${_p.notificationsPerDay}',
                style: const TextStyle(fontFamily: VibonoFonts.display, fontSize: 48, fontWeight: FontWeight.w300)),
          ),
          Center(
            child: Text(_p.notificationsPerDay == 0 ? 'keine Nachrichten' : 'Nachrichten pro Tag', style: VibonoText.small),
          ),
          Slider(
            value: _p.notificationsPerDay.toDouble(),
            min: 0,
            max: 10,
            divisions: 10,
            label: '${_p.notificationsPerDay}',
            onChanged: (v) => setState(() => _p = _p.copyWith(notificationsPerDay: v.round())),
          ),
          const SizedBox(height: 12),
          const SectionLabel('Worüber?'),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in notificationTopics.entries)
              FilterChip(
                label: Text(t.value),
                selected: _p.notificationTopics.contains(t.key),
                onSelected: (sel) => setState(() => _p = _p.copyWith(
                      notificationTopics: sel
                          ? [..._p.notificationTopics, t.key]
                          : _p.notificationTopics.where((x) => x != t.key).toList(),
                    )),
              ),
          ]),
          const SizedBox(height: 16),
          const SectionLabel('Ruhezeit'),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => _pickTime(true), child: Text('AB ${_p.quietStart}'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(onPressed: () => _pickTime(false), child: Text('BIS ${_p.quietEnd}'))),
          ]),
          const SizedBox(height: 8),
          const Text('In der Ruhezeit meldet sich Vibono nie.', style: VibonoText.small),
          const SizedBox(height: 24),
          FilledButton(onPressed: _saving ? null : _save, child: const Text('SPEICHERN')),
        ]),
      );
}
