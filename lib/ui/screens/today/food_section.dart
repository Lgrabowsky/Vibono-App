import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/coaching_day.dart';
import '../../../data/models/content.dart';
import '../../../data/models/home_feed.dart';
import '../../../data/models/profile.dart';
import '../../../domain/energy_density.dart';
import '../../../domain/food_suggestions.dart';
import '../../../domain/season.dart';
import '../../../state/home.dart';
import '../../../state/providers.dart';
import '../../../theme/vibono_colors.dart';
import '../../../theme/vibono_theme.dart';
import '../../navigation.dart';
import '../../widgets/ampel.dart';
import '../../widgets/common.dart';
import '../../widgets/day_sheets.dart';
import '../energy_density/energy_density_screen.dart';
import '../onboarding/onboarding_screen.dart';
import 'home_widgets.dart';

/// „Was heute essen?“: Rezeptvorschläge nach Vorlieben, Coaching-Phase,
/// Challenges, Saison, Wetter und Stichwörtern; dazu „Probier mal was aus
/// mit …“ und der Weg zum Energiedichte-Rechner.
class FoodSection extends ConsumerWidget {
  const FoodSection({super.key, required this.date, required this.phase, required this.isToday});
  final DateTime date;
  final PhaseKey phase;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(recipesProvider).value ?? const <ContentItem>[];
    final feed = ref.watch(homeFeedProvider(date)).value ?? HomeFeed.empty;
    final settings = ref.watch(homeSettingsProvider);
    final profile = ref.watch(sessionProvider.select((s) => s.profile));
    final weather = isToday ? ref.watch(weatherProvider).value : null;
    final entries = ref.watch(challengeEntriesProvider);
    final joined = [for (final c in feed.challenges) if (entries.containsKey(c.id)) c];

    final ctx = FoodContext(
      date: date,
      profile: profile,
      phase: phase,
      challenges: joined,
      weather: weather,
      keywords: [...settings.keywords, ...feed.keywords],
    );
    final suggestions = FoodSuggester.suggest(recipes, ctx);
    final spotlight = feed.spotlight ?? SeasonCalendar.spotlightOf(date);
    final spotRecipes = FoodSuggester.withIngredient(recipes, spotlight, ctx);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HomeSectionTitle(
        'Was heute essen?',
        actionIcon: Icons.tune_rounded,
        action: 'Vorlieben',
        onAction: () => showVibonoSheet(context, const FoodSettingsSheet()),
      ),
      const SizedBox(height: 4),
      Wrap(spacing: 12, runSpacing: 4, children: [
        HomeInfoBit(Icons.eco_outlined, SeasonCalendar.seasonOf(date).label),
        if (weather != null)
          HomeInfoBit(
            weather.cold || weather.wet ? Icons.umbrella_outlined : Icons.wb_sunny_outlined,
            '${weather.label}${weather.place == null ? '' : ' · ${weather.place}'}',
          )
        else if (isToday && settings.weatherOn && (settings.weatherPlace ?? '').isEmpty)
          InkWell(
            onTap: () => showVibonoSheet(context, const FoodSettingsSheet()),
            child: const HomeInfoBit(Icons.add_location_alt_outlined, 'Ort fürs Wetter eintragen'),
          ),
        HomeInfoBit(Icons.flag_outlined, _phaseShort(phase)),
      ]),
      if (isToday && profile.completed && settings.preferencesCheckDue) ...[
        const SizedBox(height: 12),
        _PreferenceCheck(profile: profile),
      ],
      const SizedBox(height: 10),
      _KeywordChips(editorial: feed.keywords, own: settings.keywords),
      const SizedBox(height: 10),
      if (suggestions.isEmpty)
        Text(
          recipes.isEmpty ? 'Rezepte werden geladen …' : 'Gerade passt kein Rezept zu deinen Angaben.',
          style: VibonoText.small,
        )
      else
        SizedBox(
          height: 236,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: suggestions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _SuggestionCard(
              suggestion: suggestions[i],
              onTap: () => openContent(context, suggestions[i].recipe),
            ),
          ),
        ),
      const SizedBox(height: 14),
      _SpotlightCard(name: spotlight, recipe: spotRecipes.firstOrNull, fromTeam: feed.spotlight != null),
    ]);
  }

  static String _phaseShort(PhaseKey p) => switch (p) {
        PhaseKey.vorbereitung => 'Vorbereitung',
        PhaseKey.phase1 => 'Umstellungstage',
        PhaseKey.phase2 => 'Phase 2',
        PhaseKey.phase3 => 'Phase 3',
      };
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.suggestion, required this.onTap});
  final FoodSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = suggestion.recipe;
    final reasons = suggestion.reasons.take(2).toList();
    return SizedBox(
      width: 196,
      child: HomeCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: 104, child: ContentImage(r.thumbnailUrl)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  r.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: VibonoText.body.copyWith(color: VibonoColors.grey900, fontWeight: FontWeight.w700, height: 1.3),
                ),
                const SizedBox(height: 4),
                if (r.energyDensity != null)
                  Row(children: [
                    AmpelDot(r.energyDensity!),
                    const SizedBox(width: 5),
                    Text('ED ${EnergyDensity.format(r.energyDensity!, digits: 1)}', style: VibonoText.small),
                  ]),
                const Spacer(),
                for (final reason in reasons)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(children: [
                      Icon(_reasonIcon(reason.kind), size: 13, color: VibonoColors.green700),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          reason.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VibonoText.small.copyWith(fontSize: 11, color: VibonoColors.green900),
                        ),
                      ),
                    ]),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  static IconData _reasonIcon(ReasonKind k) => switch (k) {
        ReasonKind.stichwort => Icons.sell_outlined,
        ReasonKind.challenge => Icons.emoji_events_outlined,
        ReasonKind.wetter => Icons.thermostat_outlined,
        ReasonKind.saison => Icons.eco_outlined,
        ReasonKind.phase => Icons.flag_outlined,
        ReasonKind.vorlieben => Icons.favorite_border_rounded,
      };
}

/// Stichwörter: vom Vibono-Team (fest) und eigene (zum Entfernen).
class _KeywordChips extends ConsumerWidget {
  const _KeywordChips({required this.editorial, required this.own});
  final List<String> editorial;
  final List<String> own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(homeSettingsProvider.notifier);
    return Wrap(spacing: 8, runSpacing: 6, children: [
      for (final k in editorial)
        Chip(
          avatar: const Icon(Icons.sell_outlined, size: 16, color: VibonoColors.green700),
          label: Text(k),
          backgroundColor: VibonoColors.green050,
          side: BorderSide.none,
          visualDensity: VisualDensity.compact,
        ),
      for (final k in own)
        InputChip(
          label: Text(k),
          visualDensity: VisualDensity.compact,
          onDeleted: () => n.setKeywords([...own]..remove(k)),
          deleteButtonTooltipMessage: '„$k“ entfernen',
        ),
      ActionChip(
        avatar: const Icon(Icons.add_rounded, size: 18, color: VibonoColors.green700),
        label: const Text('Worauf hast du Lust?'),
        visualDensity: VisualDensity.compact,
        onPressed: () async {
          final v = await _askKeyword(context);
          if (v != null && v.trim().isNotEmpty && !own.contains(v.trim())) {
            await n.setKeywords([...own, v.trim()]);
          }
        },
      ),
    ]);
  }

  static Future<String?> _askKeyword(BuildContext context) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Worauf hast du Lust?'),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'z. B. Kürbis, Suppe, scharf'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Hinzufügen')),
        ],
      ),
    );
  }
}

/// „Probier mal was aus mit …!“ und „Suche ein Rezept mit … und berechne die ED“.
class _SpotlightCard extends StatelessWidget {
  const _SpotlightCard({required this.name, required this.recipe, required this.fromTeam});
  final String name;
  final ContentItem? recipe;
  final bool fromTeam;

  @override
  Widget build(BuildContext context) {
    final r = recipe;
    return Container(
      color: VibonoColors.green050,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(fromTeam ? 'TIPP VOM VIBONO-TEAM' : 'SAISON-IDEE DER WOCHE', style: homeTileLabel),
        const SizedBox(height: 6),
        Text(
          'Probier mal was aus mit $name!',
          style: VibonoText.cardTitle.copyWith(color: VibonoColors.grey900),
        ),
        const SizedBox(height: 6),
        if (r != null) ...[
          InkWell(
            onTap: () => openContent(context, r),
            child: Row(children: [
              SizedBox(width: 52, height: 44, child: ContentImage(r.thumbnailUrl)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Unser Rezept', style: VibonoText.small.copyWith(fontSize: 11)),
                  Text(r.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: VibonoText.body.copyWith(color: VibonoColors.grey900, height: 1.3)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: VibonoColors.green700),
            ]),
          ),
          const SizedBox(height: 10),
        ],
        Text(
          r == null
              ? 'Such dir ein Rezept mit $name und berechne die Energiedichte mit der Vibono-App.'
              : 'Oder such dir ein eigenes Rezept mit $name und berechne die Energiedichte mit der Vibono-App.',
          style: VibonoText.small.copyWith(color: VibonoColors.grey700, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Row(children: [
          HomePillButton(
            'Energiedichte berechnen',
            filled: r == null,
            onPressed: () => push(context, const EnergyDensityScreen(initialMode: EdMode.scan)),
          ),
        ]),
      ]),
    );
  }
}

/// Ab und zu nachfragen, ob die Vorlieben noch stimmen.
class _PreferenceCheck extends ConsumerWidget {
  const _PreferenceCheck({required this.profile});
  final Profile profile;

  static String summary(Profile p) {
    final parts = <String>[
      switch (p.diet) {
        Diet.vegan => 'vegan',
        Diet.vegetarisch => 'vegetarisch',
        Diet.flexitarisch => 'flexitarisch',
        Diet.alles => 'isst alles',
        null => 'keine Ernährungsform',
      },
      if (p.intolerances.isNotEmpty || p.dislikes.isNotEmpty)
        'ohne ${[...p.intolerances.map((i) => intoleranceOptions[i] ?? i), ...p.dislikes].join(', ')}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => HomeCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const ClipOval(child: CoachAvatar(size: 32)),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Passen deine Vorlieben noch?',
                  style: VibonoText.body.copyWith(fontWeight: FontWeight.w700, color: VibonoColors.grey900)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('Gerade schlage ich dir Rezepte so vor: ${summary(profile)}.', style: VibonoText.small),
          const SizedBox(height: 10),
          Row(children: [
            HomePillButton('Passt so', onPressed: () => ref.read(homeSettingsProvider.notifier).confirmPreferences()),
            const SizedBox(width: 10),
            HomePillButton('Ändern', filled: false, onPressed: () async {
              await push(context, const OnboardingScreen(editMode: true, startAt: OnboardingStep.ernaehrung));
              await ref.read(homeSettingsProvider.notifier).confirmPreferences();
            }),
          ]),
        ]),
      );
}

/// Einstellungen für die Vorschläge: Wetter, eigene Stichwörter, Vorlieben.
class FoodSettingsSheet extends ConsumerStatefulWidget {
  const FoodSettingsSheet({super.key});

  @override
  ConsumerState<FoodSettingsSheet> createState() => _FoodSettingsSheetState();
}

class _FoodSettingsSheetState extends ConsumerState<FoodSettingsSheet> {
  late final TextEditingController _place;
  late final TextEditingController _keywords;
  late bool _weather;

  @override
  void initState() {
    super.initState();
    final s = ref.read(homeSettingsProvider);
    _place = TextEditingController(text: s.weatherPlace ?? '');
    _keywords = TextEditingController(text: s.keywords.join(', '));
    _weather = s.weatherOn;
  }

  @override
  void dispose() {
    _place.dispose();
    _keywords.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = ref.read(homeSettingsProvider.notifier);
    await n.setWeather(on: _weather, place: _place.text);
    await n.setKeywords(_keywords.text.split(','));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(sessionProvider.select((s) => s.profile));
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Deine Vorschläge', style: VibonoText.hello),
      const SizedBox(height: 4),
      const Text(
        'Rezepte schlage ich passend zu deinen Vorlieben, deiner Coaching-Phase, deinen Challenges, der Saison und dem Wetter vor.',
        style: VibonoText.small,
      ),
      const SizedBox(height: 14),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.restaurant_menu_rounded, color: VibonoColors.green700),
        title: const Text('Ernährung und Unverträglichkeiten'),
        subtitle: Text(_PreferenceCheck.summary(profile)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () async {
          await push(context, const OnboardingScreen(editMode: true, startAt: OnboardingStep.ernaehrung));
          await ref.read(homeSettingsProvider.notifier).confirmPreferences();
        },
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Wetter berücksichtigen'),
        subtitle: const Text('Bei Kälte eher Warmes, bei Hitze eher Leichtes'),
        value: _weather,
        onChanged: (v) => setState(() => _weather = v),
      ),
      if (_weather)
        TextField(
          controller: _place,
          decoration: const InputDecoration(
            labelText: 'Ort oder Postleitzahl',
            helperText: 'Nur für das Wetter. Die App nutzt keinen Standort.',
          ),
        ),
      const SizedBox(height: 12),
      TextField(
        controller: _keywords,
        decoration: const InputDecoration(
          labelText: 'Worauf hast du Lust?',
          hintText: 'z. B. Kürbis, Suppe, scharf',
          helperText: 'Stichwörter, kommagetrennt',
        ),
      ),
      const SizedBox(height: 18),
      FilledButton(onPressed: _save, child: const Text('SPEICHERN')),
    ]);
  }
}
