import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/api/api_exception.dart';
import '../../../data/models/json.dart';
import '../../../data/models/profile.dart';
import '../../../data/models/sync_item.dart';
import '../../../domain/coaching_plan.dart';
import '../../../domain/goals.dart';
import '../../../services/notification_service.dart';
import '../../../state/day_checks.dart';
import '../../../state/providers.dart';
import '../../../theme/vibono_colors.dart';
import '../../../theme/vibono_theme.dart';
import '../../widgets/common.dart';

enum OnboardingStep {
  willkommen,
  ernaehrung,
  unvertraeglichkeiten,
  abneigungen,
  bewegung,
  geschlecht,
  alter,
  haushalt,
  gewicht,
  ziele,
  start,
  benachrichtigungen,
}

/// Onboarding im Duolingo-Stil: eine Frage pro Bildschirm, große
/// Antwortkacheln, Fortschrittsbalken oben, das Vibono-Icon als Coach.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.editMode = false, this.startAt});

  /// Aus „Mehr → Meine Angaben“: ohne Begrüßung, mit Speichern am Ende.
  final bool editMode;
  final OnboardingStep? startAt;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late Profile _p;
  late List<OnboardingStep> _steps;
  int _i = 0;
  bool _saving = false;
  final _weight = TextEditingController();
  final _height = TextEditingController();
  final _dislike = TextEditingController();
  String _startChoice = 'morgen';

  @override
  void initState() {
    super.initState();
    _p = ref.read(sessionProvider).profile;
    _steps = [
      for (final s in OnboardingStep.values)
        if (!(widget.editMode && (s == OnboardingStep.willkommen || s == OnboardingStep.start))) s,
    ];
    if (widget.startAt != null) _i = _steps.indexOf(widget.startAt!).clamp(0, _steps.length - 1);
    if (_p.startWeightKg != null) _weight.text = _fmt(_p.startWeightKg!);
    if (_p.heightCm != null) _height.text = _p.heightCm!.round().toString();
  }

  @override
  void dispose() {
    _weight.dispose();
    _height.dispose();
    _dislike.dispose();
    super.dispose();
  }

  static String _fmt(double v) => v.toStringAsFixed(1).replaceAll('.', ',').replaceAll(',0', '');

  OnboardingStep get _step => _steps[_i];

  bool get _canContinue => switch (_step) {
        OnboardingStep.ernaehrung => _p.diet != null,
        OnboardingStep.bewegung => _p.activityLevel != null,
        OnboardingStep.geschlecht => _p.gender != null,
        OnboardingStep.alter => _p.ageGroup != null,
        OnboardingStep.gewicht => (asDouble(_weight.text) ?? 0) >= 40,
        OnboardingStep.ziele => _p.target3m != null && _p.target6m != null && _p.target12m != null,
        _ => true,
      };

  void _back() {
    if (_i == 0) {
      Navigator.maybePop(context);
    } else {
      setState(() => _i--);
    }
  }

  Future<void> _next() async {
    if (!_canContinue) return;
    if (_step == OnboardingStep.gewicht) {
      final w = asDouble(_weight.text)!;
      final changed = _p.startWeightKg != w;
      _p = _p.copyWith(startWeightKg: w, heightCm: asDouble(_height.text));
      if (changed || _p.target3m == null) {
        final g = Goals.suggest(w);
        _p = _p.copyWith(target3m: g.m3, target6m: g.m6, target12m: g.m12);
      }
    }
    if (_i < _steps.length - 1) {
      setState(() => _i++);
      return;
    }
    await _finish();
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final today = CoachingPlan.dateOnly(DateTime.now());
    var p = _p.copyWith(completed: true);
    if (!widget.editMode || p.coachingStartDate == null) {
      final start = switch (_startChoice) {
        'heute' => today,
        'montag' => today.add(Duration(days: 8 - today.weekday)),
        _ => today.add(const Duration(days: 1)),
      };
      p = p.copyWith(coachingStartDate: start);
    }
    try {
      await ref.read(sessionProvider.notifier).saveProfile(p);
      if (p.startWeightKg != null && !widget.editMode) {
        final d = dayKey(today);
        await ref.read(syncProvider).upsert(SyncCollection.weight, d, {'date': d, 'kg': p.startWeightKg});
      }
      final notifications = ref.read(notificationServiceProvider);
      if (p.notificationsPerDay > 0) await notifications.requestPermission();
      await notifications.reschedule();
      if (mounted && widget.editMode) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _i == _steps.length - 1;
    return PopScope(
      canPop: _i == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 16, 0),
              child: Row(children: [
                IconButton(
                  tooltip: _i == 0 ? 'Schließen' : 'Zurück',
                  onPressed: _i == 0 && !widget.editMode ? null : _back,
                  icon: Icon(_i == 0 ? Icons.close_rounded : Icons.arrow_back_rounded, color: VibonoColors.grey400),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: (_i + 1) / _steps.length),
                      duration: const Duration(milliseconds: 300),
                      builder: (_, v, _) =>
                          LinearProgressIndicator(value: v, minHeight: 11, backgroundColor: VibonoColors.grey100),
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: ListView(
                  key: ValueKey(_step),
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  children: _content(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: _BigButton(
                label: _saving ? 'MOMENT …' : (last ? (widget.editMode ? 'SPEICHERN' : "LOS GEHT'S!") : 'WEITER'),
                onPressed: _canContinue && !_saving ? _next : null,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _content() {
    final name = ref.read(sessionProvider).me?.firstName ?? '';
    switch (_step) {
      case OnboardingStep.willkommen:
        return [
          const SizedBox(height: 12),
          const Center(child: CoachAvatar(size: 96)),
          const SizedBox(height: 22),
          Text(name.isEmpty ? 'Schön, dass du da bist!' : 'Schön, dass du da bist, $name!',
              textAlign: TextAlign.center, style: VibonoText.hello),
          const SizedBox(height: 10),
          const Text(
            'Ich begleite dich Schritt für Schritt durch das Vibono-Konzept: erst die Vorbereitung, dann zwei '
            'Umstellungstage, danach änderst du in Phase 2 deine Gewohnheiten und in Phase 3 isst du dich satt und genießt.\n\n'
            'Damit ich dir jeden Tag die passenden Rezepte und Aufgaben geben kann, stelle ich dir ein paar kurze Fragen. '
            'Das dauert etwa 2 Minuten.',
            textAlign: TextAlign.center,
            style: VibonoText.body,
          ),
        ];
      case OnboardingStep.ernaehrung:
        return [
          const _Coach('Wie isst du am liebsten?'),
          const SizedBox(height: 16),
          for (final (diet, meat, title, sub, img) in [
            (Diet.alles, 'viel', 'Mit viel Fleisch', 'Fleisch gehört fast täglich dazu', 'recipe-5'),
            (Diet.flexitarisch, 'wenig', 'Mit wenig Fleisch', 'Ab und zu Fleisch oder Fisch', 'recipe-6'),
            (Diet.vegetarisch, 'keins', 'Vegetarisch', 'Kein Fleisch, kein Fisch', 'recipe-1'),
            (Diet.vegan, 'keins', 'Vegan', 'Rein pflanzlich', 'recipe-3'),
          ])
            _Option(
              title: title,
              subtitle: sub,
              leading: ClipOval(child: Image.asset('assets/images/$img.png', width: 40, height: 40, fit: BoxFit.cover)),
              selected: _p.diet == diet,
              onTap: () => setState(() => _p = _p.copyWith(diet: diet, meatAmount: meat)),
            ),
        ];
      case OnboardingStep.unvertraeglichkeiten:
        return [
          const _Coach('Verträgst du etwas nicht?', hint: 'Mehrfachauswahl. Solche Rezepte schlage ich dir dann nicht vor.'),
          const SizedBox(height: 16),
          _Chips(
            options: intoleranceOptions,
            selected: _p.intolerances.toSet(),
            onToggle: (k) => setState(() => _p = _p.copyWith(
                intolerances: _p.intolerances.contains(k)
                    ? _p.intolerances.where((x) => x != k).toList()
                    : [..._p.intolerances, k])),
          ),
          const SizedBox(height: 10),
          if (_p.intolerances.isEmpty) const Text('Nichts davon? Dann einfach weiter.', style: VibonoText.small),
        ];
      case OnboardingStep.abneigungen:
        const suggestions = ['Fisch', 'Pilze', 'Koriander', 'Oliven', 'Rosenkohl', 'Scharfes', 'Rote Bete', 'Innereien'];
        final all = {...suggestions, ..._p.dislikes};
        return [
          const _Coach('Was magst du gar nicht?', hint: 'Damit nichts auf deinem Teller landet, das dir nicht schmeckt.'),
          const SizedBox(height: 16),
          _Chips(
            options: {for (final s in all) s: s},
            selected: _p.dislikes.toSet(),
            onToggle: (k) => setState(() => _p = _p.copyWith(
                dislikes: _p.dislikes.contains(k) ? _p.dislikes.where((x) => x != k).toList() : [..._p.dislikes, k])),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dislike,
            decoration: InputDecoration(
              hintText: 'Eigene Zutat hinzufügen',
              suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: _addDislike),
            ),
            onSubmitted: (_) => _addDislike(),
          ),
        ];
      case OnboardingStep.bewegung:
        return [
          const _Coach('Ganz ehrlich: Wie viel bewegst du dich?'),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.25,
            children: [
              for (final (lvl, title, sub, bars) in [
                (ActivityLevel.sportmuffel, 'Sportmuffel', 'Kaum Bewegung', 1),
                (ActivityLevel.eingerostet, 'Eingerostet', 'Früher mehr', 2),
                (ActivityLevel.moderatAktiv, 'Moderat aktiv', '1–2× pro Woche', 3),
                (ActivityLevel.sehrAktiv, 'Sehr aktiv', '3× oder öfter', 4),
              ])
                _Tile(
                  selected: _p.activityLevel == lvl,
                  onTap: () => setState(() => _p = _p.copyWith(activityLevel: lvl)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _Bars(on: bars),
                    const SizedBox(height: 8),
                    Text(title, style: VibonoText.cardTitle),
                    Text(sub, style: VibonoText.small),
                  ]),
                ),
            ],
          ),
          if (_p.activityLevel == ActivityLevel.sportmuffel || _p.activityLevel == ActivityLevel.eingerostet) ...[
            const SizedBox(height: 16),
            const _Coach(
              'Kein Problem! Bei Vibono ist die richtige Ernährung wichtiger als Sport. Wir starten mit kleinen Schritten.',
              soft: true,
            ),
          ],
        ];
      case OnboardingStep.geschlecht:
        return [
          const _Coach('Damit ich dich richtig anspreche: Du bist …'),
          const SizedBox(height: 16),
          for (final g in genderOptions.entries)
            _Option(
              title: g.value,
              selected: _p.gender == g.key,
              onTap: () => setState(() => _p = _p.copyWith(gender: g.key)),
            ),
        ];
      case OnboardingStep.alter:
        return [
          const _Coach('Wie alt bist du?'),
          const SizedBox(height: 16),
          for (final a in ageGroupOptions.entries)
            _Option(
              title: a.value,
              selected: _p.ageGroup == a.key,
              onTap: () => setState(() => _p = _p.copyWith(ageGroup: a.key)),
            ),
        ];
      case OnboardingStep.haushalt:
        return [
          const _Coach('Für wie viele Personen kochst du?', hint: 'Danach richten sich Portionen und Einkaufsliste.'),
          const SizedBox(height: 20),
          _Stepper(
            label: 'Personen im Haushalt',
            sub: 'dich mitgezählt',
            value: _p.householdSize,
            min: 1,
            max: 15,
            onChanged: (v) => setState(() => _p = _p.copyWith(householdSize: v, children: _p.children.clamp(0, v - 1))),
          ),
          const SizedBox(height: 12),
          _Stepper(
            label: 'Davon Kinder',
            value: _p.children,
            min: 0,
            max: _p.householdSize - 1,
            onChanged: (v) => setState(() => _p = _p.copyWith(children: v)),
          ),
        ];
      case OnboardingStep.gewicht:
        return [
          const _Coach('Wie viel wiegst du heute?', hint: 'Bleibt unter uns. Nur du siehst deine Werte.'),
          const SizedBox(height: 22),
          TextField(
            controller: _weight,
            autofocus: true,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontFamily: VibonoFonts.display, fontSize: 44, fontWeight: FontWeight.w300),
            decoration: const InputDecoration(suffixText: 'kg', hintText: '0,0'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _height,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Größe (optional)', suffixText: 'cm'),
          ),
        ];
      case OnboardingStep.ziele:
        final w = _p.startWeightKg ?? 0;
        final start = _p.coachingStartDate ?? CoachingPlan.dateOnly(DateTime.now());
        String month(int m) => DateFormat('MMM yyyy', 'de_DE').format(DateTime(start.year, start.month + m));
        return [
          const _Coach('Wo möchtest du hin? Setze dir Etappenziele.'),
          const SizedBox(height: 14),
          Center(
            child: Text('${_fmt(w)} kg',
                style: const TextStyle(fontFamily: VibonoFonts.display, fontSize: 38, fontWeight: FontWeight.w300)),
          ),
          const Center(child: Text('dein Gewicht heute', style: VibonoText.small)),
          const SizedBox(height: 14),
          for (final (label, m, value, set) in [
            ('3 Monate', 3, _p.target3m, (double v) => _p.copyWith(target3m: v)),
            ('6 Monate', 6, _p.target6m, (double v) => _p.copyWith(target6m: v)),
            ('12 Monate', 12, _p.target12m, (double v) => _p.copyWith(target12m: v)),
          ])
            _GoalStepper(
              label: label,
              sub: month(m),
              value: value ?? w,
              onChanged: (v) => setState(() => _p = set(v)),
            ),
          const SizedBox(height: 8),
          if (_p.target3m != null && _p.target12m != null)
            _Coach(Goals.feedback(w, _p.target3m!, _p.target12m!), soft: true),
        ];
      case OnboardingStep.start:
        final today = CoachingPlan.dateOnly(DateTime.now());
        final monday = today.add(Duration(days: 8 - today.weekday));
        return [
          const _Coach('Wann starten deine Umstellungstage?',
              hint: 'Davor planst du einen Tag Vorbereitung ein: einkaufen und ein paar Beiträge lesen.'),
          const SizedBox(height: 16),
          _Option(
            title: 'Morgen',
            subtitle: 'Empfohlen: heute vorbereiten, morgen geht es los',
            selected: _startChoice == 'morgen',
            onTap: () => setState(() => _startChoice = 'morgen'),
          ),
          _Option(
            title: 'Am Montag, ${DateFormat('d. MMMM', 'de_DE').format(monday)}',
            subtitle: 'Mehr Zeit zum Vorbereiten',
            selected: _startChoice == 'montag',
            onTap: () => setState(() => _startChoice = 'montag'),
          ),
          _Option(
            title: 'Heute',
            subtitle: 'Du bist schon vorbereitet',
            selected: _startChoice == 'heute',
            onTap: () => setState(() => _startChoice = 'heute'),
          ),
        ];
      case OnboardingStep.benachrichtigungen:
        return [
          const _Coach('Wie oft darf ich mich am Tag melden?'),
          const SizedBox(height: 14),
          Center(
            child: Text('${_p.notificationsPerDay}',
                style: const TextStyle(fontFamily: VibonoFonts.display, fontSize: 52, fontWeight: FontWeight.w300)),
          ),
          Center(
            child: Text(_p.notificationsPerDay == 0 ? 'keine Nachrichten' : 'Nachrichten pro Tag', style: VibonoText.small),
          ),
          Slider(
            value: _p.notificationsPerDay.toDouble(),
            min: 0,
            max: 10,
            divisions: 10,
            onChanged: (v) => setState(() => _p = _p.copyWith(notificationsPerDay: v.round())),
          ),
          const SizedBox(height: 8),
          const SectionLabel('Worüber?'),
          const SizedBox(height: 8),
          _Chips(
            options: notificationTopics,
            selected: _p.notificationTopics.toSet(),
            onToggle: (k) => setState(() => _p = _p.copyWith(
                notificationTopics: _p.notificationTopics.contains(k)
                    ? _p.notificationTopics.where((x) => x != k).toList()
                    : [..._p.notificationTopics, k])),
          ),
          const SizedBox(height: 14),
          const SectionLabel('Ruhezeit'),
          const SizedBox(height: 4),
          Text('${_p.quietStart} – ${_p.quietEnd} Uhr. Ändern kannst du das jederzeit unter „Mehr“.', style: VibonoText.body),
        ];
    }
  }

  void _addDislike() {
    final v = _dislike.text.trim();
    if (v.isEmpty) return;
    setState(() {
      if (!_p.dislikes.contains(v)) _p = _p.copyWith(dislikes: [..._p.dislikes, v]);
      _dislike.clear();
    });
  }
}

// ---------------------------------------------------------------------------
// Bausteine
// ---------------------------------------------------------------------------

class _Coach extends StatelessWidget {
  const _Coach(this.text, {this.hint, this.soft = false});
  final String text;
  final String? hint;
  final bool soft;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        CoachAvatar(size: soft ? 36 : 48),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
            decoration: BoxDecoration(
              color: soft ? VibonoColors.green050 : Colors.white,
              border: Border.all(color: soft ? Colors.transparent : VibonoColors.grey200, width: 1.5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                text,
                style: soft
                    ? VibonoText.body.copyWith(color: VibonoColors.grey700)
                    : const TextStyle(
                        fontFamily: VibonoFonts.display,
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                        color: VibonoColors.grey900,
                        height: 1.2,
                      ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(hint!, style: VibonoText.small),
              ],
            ]),
          ),
        ),
      ]);
}

/// Antwortkachel mit dickerem Rand unten (Duolingo-Optik).
class _Tile extends StatelessWidget {
  const _Tile({required this.selected, required this.onTap, required this.child});
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? VibonoColors.green050 : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border(
                top: BorderSide(color: selected ? VibonoColors.green : VibonoColors.grey200, width: 2),
                left: BorderSide(color: selected ? VibonoColors.green : VibonoColors.grey200, width: 2),
                right: BorderSide(color: selected ? VibonoColors.green : VibonoColors.grey200, width: 2),
                bottom: BorderSide(color: selected ? VibonoColors.green : VibonoColors.grey200, width: 4),
              ),
            ),
            child: child,
          ),
        ),
      );
}

class _Option extends StatelessWidget {
  const _Option({required this.title, this.subtitle, this.leading, required this.selected, required this.onTap});
  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _Tile(
          selected: selected,
          onTap: onTap,
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: VibonoText.cardTitle.copyWith(fontSize: 17)),
                if (subtitle != null) Text(subtitle!, style: VibonoText.small),
              ]),
            ),
            if (selected) const Icon(Icons.check_circle_rounded, color: VibonoColors.green),
          ]),
        ),
      );
}

class _Chips extends StatelessWidget {
  const _Chips({required this.options, required this.selected, required this.onToggle});
  final Map<String, String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final o in options.entries)
          FilterChip(
            label: Text(o.value),
            selected: selected.contains(o.key),
            showCheckmark: false,
            labelStyle: TextStyle(
              fontFamily: VibonoFonts.display,
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: selected.contains(o.key) ? Colors.white : VibonoColors.grey800,
            ),
            onSelected: (_) => onToggle(o.key),
          ),
      ]);
}

class _Bars extends StatelessWidget {
  const _Bars({required this.on});
  final int on;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Container(
              width: 8,
              height: 8.0 + i * 6,
              decoration: BoxDecoration(
                color: i < on ? VibonoColors.green : VibonoColors.grey200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ],
      );
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, this.sub, required this.value, required this.min, required this.max, required this.onChanged});
  final String label;
  final String? sub;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(border: Border.all(color: VibonoColors.grey200, width: 2), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: VibonoText.cardTitle),
              if (sub != null) Text(sub!, style: VibonoText.small),
            ]),
          ),
          IconButton.outlined(
            tooltip: 'Weniger',
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 44,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: VibonoFonts.display, fontSize: 24, fontWeight: FontWeight.w600)),
          ),
          IconButton.outlined(
            tooltip: 'Mehr',
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add),
          ),
        ]),
      );
}

class _GoalStepper extends StatelessWidget {
  const _GoalStepper({required this.label, required this.sub, required this.value, required this.onChanged});
  final String label;
  final String sub;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration:
              BoxDecoration(border: Border.all(color: VibonoColors.grey200, width: 2), borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            SizedBox(
              width: 84,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: VibonoText.cardTitle),
                Text(sub, style: VibonoText.small),
              ]),
            ),
            const Spacer(),
            IconButton(tooltip: '0,5 kg weniger', onPressed: () => onChanged(value - 0.5), icon: const Icon(Icons.remove_circle_outline)),
            SizedBox(
              width: 80,
              child: Text(
                '${value.toStringAsFixed(1).replaceAll('.', ',')} kg',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: VibonoFonts.display, fontSize: 19, fontWeight: FontWeight.w700, color: VibonoColors.green700),
              ),
            ),
            IconButton(tooltip: '0,5 kg mehr', onPressed: () => onChanged(value + 0.5), icon: const Icon(Icons.add_circle_outline)),
          ]),
        ),
      );
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? VibonoColors.green : VibonoColors.grey200,
            borderRadius: BorderRadius.circular(999),
            border: Border(bottom: BorderSide(color: enabled ? VibonoColors.green700 : VibonoColors.grey300, width: 4)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: VibonoFonts.display,
              fontWeight: FontWeight.w700,
              fontSize: 17,
              letterSpacing: 1,
              color: enabled ? Colors.white : VibonoColors.grey500,
            ),
          ),
        ),
      ),
    );
  }
}
