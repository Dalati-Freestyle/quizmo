/// Settings screen for the latency thresholds of the technical check.
library;

import 'package:flutter/material.dart';

import '../../core/engine/tech_check.dart';
import '../l10n/app_localizations.dart';
import 'tech_check_settings.dart';

/// Edits when a round trip counts as good and when it fails the check.
class TechCheckSettingsPage extends StatefulWidget {
  /// Creates the page.
  const TechCheckSettingsPage({super.key});

  @override
  State<TechCheckSettingsPage> createState() => _TechCheckSettingsPageState();
}

class _TechCheckSettingsPageState extends State<TechCheckSettingsPage> {
  final _form = GlobalKey<FormState>();
  final _good = TextEditingController();
  final _max = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    TechCheckSettingsStore.instance.load().then((thresholds) {
      if (!mounted) return;
      setState(() {
        _fill(thresholds);
        _loaded = true;
      });
    });
  }

  void _fill(TechCheckThresholds thresholds) {
    _good.text = '${thresholds.goodRoundTrip.inMilliseconds}';
    _max.text = '${thresholds.maxRoundTrip.inMilliseconds}';
  }

  @override
  void dispose() {
    _good.dispose();
    _max.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final saved = context.tr('Grenzwerte gespeichert.');
    final failed = context.tr(
      'Die Grenzwerte konnten nicht gespeichert werden.',
    );
    try {
      await TechCheckSettingsStore.instance.save(
        TechCheckThresholds(
          goodRoundTrip: Duration(milliseconds: int.parse(_good.text.trim())),
          maxRoundTrip: Duration(milliseconds: int.parse(_max.text.trim())),
        ),
      );
      messenger.showSnackBar(SnackBar(content: Text(saved)));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  String? _positive(String? text) {
    final value = int.tryParse(text?.trim() ?? '');
    return value == null || value <= 0
        ? context.tr('Eine positive Zahl in Millisekunden eingeben.')
        : null;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('Technikcheck-Grenzwerte'))),
    body: !_loaded
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  context.tr(
                    'Laufzeit (Hin und zurück) zwischen Spielergerät und Host. Über das Internet sind einige hundert Millisekunden normal; Buzzer bleiben dank Uhrensynchronisation fair.',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('tech-check-good-ms'),
                  controller: _good,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.tr('Gut bis (ms)'),
                  ),
                  validator: _positive,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('tech-check-max-ms'),
                  controller: _max,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.tr('Fehler ab (ms)'),
                  ),
                  validator: (text) {
                    final error = _positive(text);
                    if (error != null) return error;
                    final good = int.tryParse(_good.text.trim());
                    return good != null && int.parse(text!.trim()) < good
                        ? context.tr(
                            'Die Fehlergrenze darf nicht unter „Gut bis“ liegen.',
                          )
                        : null;
                  },
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      key: const ValueKey('tech-check-save'),
                      onPressed: _save,
                      child: Text(context.tr('Speichern')),
                    ),
                    OutlinedButton(
                      onPressed: () =>
                          setState(() => _fill(const TechCheckThresholds())),
                      child: Text(
                        context.tr('Standard ({0} / {1} ms)', [
                          TechCheckThresholds.defaultGoodMs,
                          TechCheckThresholds.defaultMaxMs,
                        ]),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
  );
}
