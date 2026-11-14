import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config.dart';
import '../../data/api/api_exception.dart';
import '../../services/external_links.dart';
import '../../state/providers.dart';
import '../../theme/vibono_colors.dart';
import '../../theme/vibono_theme.dart';
import '../widgets/common.dart';

/// Anmelden mit dem bestehenden Vibono-Konto (gleiche Zugangsdaten wie auf
/// vibono.de) oder neues Konto anlegen.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _register = false;
  bool _privacy = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Bitte E-Mail und Passwort eingeben.');
      return;
    }
    if (_register && !_privacy) {
      setState(() => _error = 'Bitte stimme der Datenschutzerklärung zu.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final s = ref.read(sessionProvider.notifier);
    try {
      if (_register) {
        await s.register(_email.text, _password.text, _name.text, _code.text);
      } else {
        await s.login(_email.text, _password.text);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                shrinkWrap: true,
                children: [
                  const Center(child: CoachAvatar(size: 84)),
                  const SizedBox(height: 18),
                  const Center(child: VibonoLogo(height: 30)),
                  const SizedBox(height: 18),
                  Text(
                    _register ? 'Konto anlegen' : 'Schritt für Schritt zu deinem Wunschgewicht.',
                    textAlign: TextAlign.center,
                    style: VibonoText.hello.copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _register
                        ? 'Mit deinem Vibono-Konto nutzt du die App und MyVibono auf vibono.de.'
                        : 'Melde dich mit deinem Vibono-Konto an, also mit denselben Daten wie auf vibono.de.',
                    textAlign: TextAlign.center,
                    style: VibonoText.body,
                  ),
                  const SizedBox(height: 22),
                  if (_register) ...[
                    TextField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Vorname'),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email, AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'E-Mail'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Passwort',
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Passwort anzeigen' : 'Passwort verbergen',
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  if (_register) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _code,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Empfehlungscode (optional)'),
                    ),
                    CheckboxListTile(
                      value: _privacy,
                      onChanged: (v) => setState(() => _privacy = v ?? false),
                      activeColor: VibonoColors.green,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'Ich stimme der Datenschutzerklärung zu, auch der Verarbeitung meiner Gesundheitsdaten '
                        '(Gewicht, Ziele) für das Coaching.',
                        style: VibonoText.small,
                      ),
                      secondary: IconButton(
                        tooltip: 'Datenschutzerklärung öffnen',
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        onPressed: () => openWebsite(AppConfig.privacyUrl),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: VibonoText.body.copyWith(color: const Color(0xFFDC3545))),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_register ? 'KONTO ANLEGEN' : 'ANMELDEN'),
                  ),
                  if (!_register)
                    TextButton(
                      onPressed: () => openWebsite(AppConfig.forgotPasswordUrl),
                      child: const Text('PASSWORT VERGESSEN?'),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() {
                      _register = !_register;
                      _error = null;
                    }),
                    child: Text(_register ? 'ICH HABE SCHON EIN KONTO' : 'NEU HIER? KONTO ANLEGEN'),
                  ),
                  if (AppConfig.useMocks)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Demo-Modus: beliebige E-Mail und ein Passwort mit mindestens 4 Zeichen.',
                        textAlign: TextAlign.center,
                        style: VibonoText.small,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}
