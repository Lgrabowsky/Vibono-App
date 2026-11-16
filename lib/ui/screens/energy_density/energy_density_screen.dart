import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/api/api_exception.dart';
import '../../../data/models/energy.dart';
import '../../../domain/energy_density.dart';
import '../../../domain/food_database.dart';
import '../../../state/providers.dart';
import '../../../theme/vibono_colors.dart';
import '../../../theme/vibono_theme.dart';
import '../../widgets/ampel.dart';
import '../../widgets/common.dart';

enum EdMode { manuell, scan, foto }

/// Energiedichte-Rechner: Zutaten eingeben, Rezept scannen oder Foto vom
/// fertigen Gericht schätzen lassen. Ergebnis immer in kcal/g mit Ampel.
class EnergyDensityScreen extends ConsumerStatefulWidget {
  const EnergyDensityScreen({super.key, this.initialMode = EdMode.manuell});
  final EdMode initialMode;

  @override
  ConsumerState<EnergyDensityScreen> createState() => _EnergyDensityScreenState();
}

class _EnergyDensityScreenState extends ConsumerState<EnergyDensityScreen> {
  late EdMode _mode = widget.initialMode;
  List<Ingredient> _items = const [];
  String? _scanTitle;

  void _setItems(List<Ingredient> items, {String? title, EdMode? mode}) => setState(() {
        _items = items;
        _scanTitle = title;
        if (mode != null) _mode = mode;
      });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ENERGIEDICHTE')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _Segmented(
              value: _mode,
              onChanged: (m) => setState(() => _mode = m),
            ),
          ),
          Expanded(
            child: switch (_mode) {
              EdMode.manuell => _IngredientEditor(
                  items: _items,
                  title: _scanTitle,
                  onChanged: (l) => setState(() => _items = l),
                ),
              EdMode.scan => _ScanView(onResult: (r) => _setItems(r.ingredients, title: r.title, mode: EdMode.manuell)),
              EdMode.foto => _PhotoView(
                  onCorrect: (r) => _setItems(
                    [
                      for (final c in r.components)
                        Ingredient(name: c.name, grams: (r.portionG * c.sharePct / 100).roundToDouble(), confidence: 0.4),
                    ],
                    title: r.dish,
                    mode: EdMode.manuell,
                  ),
                ),
            },
          ),
        ]),
      );
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.value, required this.onChanged});
  final EdMode value;
  final ValueChanged<EdMode> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: VibonoColors.grey100, borderRadius: BorderRadius.circular(999)),
        child: Row(children: [
          for (final (m, label) in [(EdMode.manuell, 'Eingeben'), (EdMode.scan, 'Rezept scannen'), (EdMode.foto, 'Foto')])
            Expanded(
              flex: m == EdMode.scan ? 13 : (m == EdMode.foto ? 8 : 10),
              child: Semantics(
                selected: value == m,
                button: true,
                child: GestureDetector(
                  onTap: () => onChanged(m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: value == m ? VibonoColors.green : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: VibonoFonts.display,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: value == m ? Colors.white : VibonoColors.grey,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
}

// ---------------------------------------------------------------------------
// 1 · Manuell eingeben (auch Ziel von Scan und Foto-Korrektur)
// ---------------------------------------------------------------------------

class _IngredientEditor extends ConsumerWidget {
  const _IngredientEditor({required this.items, required this.onChanged, this.title});
  final List<Ingredient> items;
  final ValueChanged<List<Ingredient>> onChanged;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = EnergyDensity.compute(items);
    final open = items.where((i) => i.needsReview).length;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
      if (title != null) ...[
        Text(title!, style: VibonoText.cardTitle.copyWith(fontSize: 18)),
        const SizedBox(height: 6),
      ],
      const _Row(name: 'ZUTAT', amount: 'MENGE', kcal: 'KCAL/100 G', head: true),
      for (var i = 0; i < items.length; i++)
        Dismissible(
          key: ValueKey('${items[i].name}-$i-${items.length}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 12),
            color: VibonoColors.warnBg,
            child: const Icon(Icons.delete_outline),
          ),
          onDismissed: (_) => onChanged([...items]..removeAt(i)),
          child: InkWell(
            onTap: () => _edit(context, ref, i),
            child: _Row(
              name: items[i].rawText != null && items[i].needsReview ? '„${items[i].rawText}“' : items[i].name,
              amount: items[i].grams == null ? '?' : '${items[i].grams!.round()} g',
              kcal: items[i].kcalPer100g == null ? '?' : '${items[i].kcalPer100g!.round()}',
              warn: items[i].needsReview,
            ),
          ),
        ),
      TextButton.icon(
        style: TextButton.styleFrom(alignment: Alignment.centerLeft),
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('ZUTAT HINZUFÜGEN'),
      ),
      if (open > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            open == 1 ? '1 Angabe bitte prüfen (gelb markiert, antippen).' : '$open Angaben bitte prüfen (gelb markiert, antippen).',
            style: VibonoText.small,
          ),
        ),
      if (r.density != null)
        EdResult(
          density: r.density!,
          detail: '${r.kcal.round()} kcal auf ${r.grams.round()} g.',
        )
      else
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: VibonoColors.grey050, borderRadius: BorderRadius.circular(14)),
          child: const Text(
            'Füge die Zutaten deines Gerichts hinzu. Die Energiedichte rechnet live mit.',
            style: VibonoText.body,
          ),
        ),
      if (items.isNotEmpty) ...[
        const SizedBox(height: 12),
        OutlinedButton(onPressed: () => onChanged(const []), child: const Text('NEU BEGINNEN')),
      ],
      const SizedBox(height: 12),
      const Text(
        'Energiedichte = Kalorien geteilt durch Gewicht. Grün (bis 1,5 kcal/g) macht satt mit wenig Kalorien. '
        'Wasser und kalorienfreie Getränke zählen nicht mit.',
        style: VibonoText.small,
      ),
    ]);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, int? index) async {
    final result = await showModalBottomSheet<Ingredient>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _IngredientSheet(initial: index == null ? null : items[index]),
    );
    if (result == null) return;
    final next = [...items];
    if (index == null) {
      next.add(result);
    } else {
      next[index] = result;
    }
    onChanged(next);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.name, required this.amount, required this.kcal, this.head = false, this.warn = false});
  final String name;
  final String amount;
  final String kcal;
  final bool head;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final style = head
        ? VibonoText.label.copyWith(color: VibonoColors.grey500, fontSize: 11)
        : VibonoText.body.copyWith(color: VibonoColors.grey800);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
      decoration: BoxDecoration(
        color: warn ? VibonoColors.warnBg : null,
        borderRadius: warn ? BorderRadius.circular(6) : null,
        border: Border(bottom: BorderSide(color: head ? VibonoColors.grey200 : VibonoColors.grey100)),
      ),
      child: Row(children: [
        Expanded(child: Text(name, style: style, maxLines: 2, overflow: TextOverflow.ellipsis)),
        SizedBox(width: 64, child: Text(amount, textAlign: TextAlign.right, style: style)),
        SizedBox(width: 82, child: Text(kcal, textAlign: TextAlign.right, style: style)),
      ]),
    );
  }
}

class _IngredientSheet extends ConsumerStatefulWidget {
  const _IngredientSheet({this.initial});
  final Ingredient? initial;

  @override
  ConsumerState<_IngredientSheet> createState() => _IngredientSheetState();
}

class _IngredientSheetState extends ConsumerState<_IngredientSheet> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _grams = TextEditingController(text: widget.initial?.grams?.round().toString() ?? '');
  late final _kcal = TextEditingController(text: widget.initial?.kcalPer100g?.round().toString() ?? '');
  List<Food> _suggestions = const [];
  int _query = 0;

  @override
  void dispose() {
    _name.dispose();
    _grams.dispose();
    _kcal.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final mine = ++_query;
    if (q.trim().length < 2) {
      setState(() => _suggestions = const []);
      return;
    }
    setState(() => _suggestions = FoodDatabase.search(q));
    try {
      final remote = await ref.read(apiProvider).foods(q);
      if (mounted && mine == _query && remote.isNotEmpty) setState(() => _suggestions = remote);
    } catch (_) {/* offline: lokale Liste reicht */}
  }

  void _save() {
    final g = double.tryParse(_grams.text.replaceAll(',', '.'));
    final k = double.tryParse(_kcal.text.replaceAll(',', '.'));
    if (_name.text.trim().isEmpty || g == null || k == null) return;
    Navigator.pop(context, Ingredient(name: _name.text.trim(), grams: g, kcalPer100g: k));
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.initial == null ? 'Zutat hinzufügen' : 'Zutat prüfen', style: VibonoText.hello),
          if (widget.initial?.rawText != null) ...[
            const SizedBox(height: 4),
            Text('Im Rezept steht: „${widget.initial!.rawText}“', style: VibonoText.small),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: widget.initial == null,
            decoration: const InputDecoration(labelText: 'Lebensmittel', prefixIcon: Icon(Icons.search)),
            onChanged: _search,
          ),
          if (_suggestions.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView(shrinkWrap: true, children: [
                for (final f in _suggestions)
                  ListTile(
                    dense: true,
                    title: Text(f.name, style: VibonoText.body),
                    trailing: Text('${f.kcalPer100g.round()} kcal/100 g', style: VibonoText.small),
                    onTap: () => setState(() {
                      _name.text = f.name;
                      _kcal.text = f.kcalPer100g.round().toString();
                      _suggestions = const [];
                    }),
                  ),
              ]),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _grams,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Menge', suffixText: 'g'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _kcal,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'kcal pro 100 g'),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          const Text('Flüssigkeiten: 100 ml ≈ 100 g.', style: VibonoText.small),
          const SizedBox(height: 14),
          FilledButton(onPressed: _save, child: const Text('ÜBERNEHMEN')),
        ]),
      );
}

// ---------------------------------------------------------------------------
// Bild aufnehmen
// ---------------------------------------------------------------------------

class _Picked {
  const _Picked(this.bytes, this.mime);
  final Uint8List bytes;
  final String mime;
}

Future<_Picked?> _pickImage(BuildContext context, ImageSource source) async {
  try {
    final x = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 75);
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    final name = x.name.toLowerCase();
    final mime = x.mimeType ??
        (name.endsWith('.png')
            ? 'image/png'
            : name.endsWith('.webp')
                ? 'image/webp'
                : 'image/jpeg');
    return _Picked(bytes, mime);
  } catch (_) {
    if (context.mounted) showMessage(context, 'Kamera oder Fotos sind nicht verfügbar. Bitte Zugriff in den Einstellungen erlauben.');
    return null;
  }
}

Widget _sourceButtons(BuildContext context, void Function(ImageSource) onPick, {required String cameraLabel}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () => onPick(ImageSource.camera),
          icon: const Icon(Icons.photo_camera_outlined, size: 20),
          label: Text(cameraLabel),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => onPick(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined, size: 20),
          label: const Text('AUS DEN FOTOS WÄHLEN'),
        ),
      ],
    );

class _Viewfinder extends StatelessWidget {
  const _Viewfinder({this.image, required this.hint});
  final Uint8List? image;
  final String hint;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 4 / 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(fit: StackFit.expand, children: [
            if (image != null)
              Image.memory(image!, fit: BoxFit.cover)
            else
              Container(
                color: VibonoColors.grey800,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(24),
                child: Text(hint, textAlign: TextAlign.center, style: VibonoText.body.copyWith(color: Colors.white)),
              ),
            for (final a in [Alignment.topLeft, Alignment.topRight, Alignment.bottomLeft, Alignment.bottomRight])
              Align(
                alignment: a,
                child: Container(
                  margin: const EdgeInsets.all(10),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    border: Border(
                      top: a.y < 0 ? const BorderSide(color: VibonoColors.green, width: 3) : BorderSide.none,
                      bottom: a.y > 0 ? const BorderSide(color: VibonoColors.green, width: 3) : BorderSide.none,
                      left: a.x < 0 ? const BorderSide(color: VibonoColors.green, width: 3) : BorderSide.none,
                      right: a.x > 0 ? const BorderSide(color: VibonoColors.green, width: 3) : BorderSide.none,
                    ),
                  ),
                ),
              ),
          ]),
        ),
      );
}

// ---------------------------------------------------------------------------
// 2 · Rezept scannen
// ---------------------------------------------------------------------------

class _ScanView extends ConsumerStatefulWidget {
  const _ScanView({required this.onResult});
  final ValueChanged<RecipeScanResult> onResult;

  @override
  ConsumerState<_ScanView> createState() => _ScanViewState();
}

class _ScanViewState extends ConsumerState<_ScanView> {
  _Picked? _img;
  bool _busy = false;

  Future<void> _pick(ImageSource s) async {
    final p = await _pickImage(context, s);
    if (p == null) return;
    setState(() {
      _img = p;
      _busy = true;
    });
    try {
      final r = await ref.read(apiProvider).scanRecipe(base64Encode(p.bytes), p.mime);
      if (!mounted) return;
      if (r.ingredients.isEmpty) {
        showMessage(context, 'Auf dem Foto habe ich keine Zutatenliste gefunden. Versuch es mit mehr Licht.');
      } else {
        widget.onResult(r);
      }
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        _Viewfinder(image: _img?.bytes, hint: 'Fotografiere die Zutatenliste eines Rezepts, aus dem Kochbuch, einer Zeitschrift oder vom Bildschirm.'),
        const SizedBox(height: 14),
        if (_busy)
          const Column(children: [
            CircularProgressIndicator(),
            SizedBox(height: 8),
            Text('Ich lese die Zutaten …', style: VibonoText.body),
          ])
        else
          _sourceButtons(context, _pick, cameraLabel: 'REZEPT FOTOGRAFIEREN'),
        const SizedBox(height: 14),
        const Text(
          'Die App liest Zutaten und Mengen und berechnet die Energiedichte. Unsichere Angaben markiert sie gelb, '
          'die prüfst du kurz nach. Das Foto wird nur zur Auswertung übertragen und nicht gespeichert.',
          style: VibonoText.small,
        ),
      ]);
}

// ---------------------------------------------------------------------------
// 3 · Foto vom Gericht
// ---------------------------------------------------------------------------

class _PhotoView extends ConsumerStatefulWidget {
  const _PhotoView({required this.onCorrect});
  final ValueChanged<PhotoAnalysisResult> onCorrect;

  @override
  ConsumerState<_PhotoView> createState() => _PhotoViewState();
}

class _PhotoViewState extends ConsumerState<_PhotoView> {
  _Picked? _img;
  final _desc = TextEditingController();
  bool _busy = false;
  PhotoAnalysisResult? _result;

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource s) async {
    final p = await _pickImage(context, s);
    if (p == null) return;
    setState(() {
      _img = p;
      _result = null;
    });
  }

  Future<void> _analyze() async {
    final p = _img;
    if (p == null) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiProvider).analyzePhoto(base64Encode(p.bytes), p.mime, description: _desc.text);
      if (mounted) setState(() => _result = r);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _mixColors = [VibonoColors.green, VibonoColors.green300, VibonoColors.grey300, VibonoColors.gelb];

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return ListView(padding: const EdgeInsets.all(16), children: [
      _Viewfinder(image: _img?.bytes, hint: 'Fotografiere dein Gericht von schräg oben, gern auch im Restaurant.'),
      const SizedBox(height: 12),
      if (_img == null)
        _sourceButtons(context, _pick, cameraLabel: 'GERICHT FOTOGRAFIEREN')
      else ...[
        TextField(
          controller: _desc,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Was ist das? (optional)',
            hintText: 'z. B. Gemüsegulasch mit Kartoffeln',
          ),
        ),
        const SizedBox(height: 10),
        if (_busy)
          const Center(child: Column(children: [CircularProgressIndicator(), SizedBox(height: 8), Text('Ich schätze …')]))
        else if (r == null)
          FilledButton(onPressed: _analyze, child: const Text('ENERGIEDICHTE SCHÄTZEN'))
        else ...[
          Text(r.dish, style: VibonoText.cardTitle.copyWith(fontSize: 18)),
          const SizedBox(height: 4),
          SectionLabel('Geschätzter Teller · ca. ${r.portionG.round()} g'),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(children: [
              for (var i = 0; i < r.components.length; i++)
                Expanded(
                  flex: r.components[i].sharePct.round().clamp(1, 100),
                  child: Container(
                    height: 22,
                    color: _mixColors[i % _mixColors.length],
                    padding: const EdgeInsets.only(left: 6),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      r.components[i].sharePct >= 15 ? '${r.components[i].name} ${r.components[i].sharePct.round()} %' : '',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: const TextStyle(fontFamily: VibonoFonts.display, fontWeight: FontWeight.w700, fontSize: 12, color: VibonoColors.grey900),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          EdResult(density: r.kcalPerG, approx: true, detail: 'Ca. ${r.kcalTotal.round()} kcal. ${r.notes}'),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Genauigkeit der Schätzung', style: VibonoText.small),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: r.confidence, minHeight: 6, backgroundColor: VibonoColors.grey100),
              ),
            ),
            const SizedBox(width: 8),
            Text(r.confidence >= 0.7 ? 'hoch' : (r.confidence >= 0.45 ? 'mittel' : 'gering'), style: VibonoText.small),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton(
                onPressed: () => setState(() {
                  _img = null;
                  _result = null;
                  _desc.clear();
                }),
                child: const Text('NEUES FOTO'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(onPressed: () => widget.onCorrect(r), child: const Text('KORRIGIEREN'))),
          ]),
        ],
      ],
      const SizedBox(height: 10),
      const Text(
        'Die App erkennt Bestandteile und Portionsgröße, rechnet typische Zusätze wie Öl oder Sahne ein und zeigt, '
        'wie sicher die Schätzung ist. Mit einer kurzen Beschreibung wird sie genauer.',
        style: VibonoText.small,
      ),
    ]);
  }
}
