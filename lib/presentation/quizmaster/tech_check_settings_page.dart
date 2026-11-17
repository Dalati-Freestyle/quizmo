/// Settings screen for the latency thresholds of the technical check.
library;

import 'package:flutter/material.dart';

import '../../core/engine/tech_check.dart';
import '../l10n/app_localizations.dart';
import 'tech_check_settings.dart';

/// Edits when a round trip counts as good and when it fails the check,
/// separately for LAN and internet games.
class TechCheckSettingsPage extends StatefulWidget {
  /// Creates the page.
  const TechCheckSettingsPage({super.key});

  @override
  State<TechCheckSettingsPage> createState() => _TechCheckSettingsPageState();
}

/// Text fields of one mode.
final class _ModeFields {
  _ModeFields(this.internet);

  final bool internet;
  final good = TextEditingController();
  final max = TextEditingController();

  void fill(TechCheckThresholds thresholds) {
    good.text = '${thresholds.goodRoundTrip.inMilliseconds}';
    max.text = '${thresholds.maxRoundTrip.inMilliseconds}';
  }

  TechCheckThresholds get value => TechCheckThresholds(
    goodRoundTrip: Duration(milliseconds: int.parse(good.text.trim())),
    maxRoundTrip: Duration(milliseconds: int.parse(max.text.trim())),
  );

  void dispose() {
    good.dispose();
    max.dispose();
  }
}

class _TechCheckSettingsPageState extends State<TechCheckSettingsPage> {
  final _form = GlobalKey<FormState>();
  final _lan = _ModeFields(false);
  final _internet = _ModeFields(true);
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = TechCheckSettingsStore.instance;
    final lan = await store.load(internet: false);
    final internet = await store.load(internet: true);
    if (!mounted) return;
    setState(() {
      _lan.fill(lan);
      _internet.fill(internet);
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _lan.dispose();
    _internet.dispose();
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
      final store = TechCheckSettingsStore.instance;
      await store.save(_lan.value, internet: false);
      await store.save(_internet.value, internet: true);
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

  List<Widget> _mode(String title, _ModeFields fields) {
    final defaults = TechCheckThresholds.defaultsFor(internet: fields.internet);
    final prefix = fields.internet ? 'internet' : 'lan';
    return [
      const SizedBox(height: 24),
      Text(context.tr(title), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      TextFormField(
        key: ValueKey('tech-check-$prefix-good-ms'),
        controller: fields.good,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: context.tr('Gut bis (ms)')),
        validator: _positive,
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: ValueKey('tech-check-$prefix-max-ms'),
        controller: fields.max,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: context.tr('Fehler ab (ms)')),
        validator: (text) {
          final error = _positive(text);
          if (error != null) return error;
          final good = int.tryParse(fields.good.text.trim());
          return good != null && int.parse(text!.trim()) < good
              ? context.tr(
                  'Die Fehlergrenze darf nicht unter „Gut bis“ liegen.',
                )
              : null;
        },
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(
          onPressed: () => setState(() => fields.fill(defaults)),
          child: Text(
            context.tr('Standard ({0} / {1} ms)', [
              defaults.goodRoundTrip.inMilliseconds,
              defaults.maxRoundTrip.inMilliseconds,
            ]),
          ),
        ),
      ),
    ];
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
                ..._mode('LAN-Server auf diesem Gerät', _lan),
                ..._mode('Internet-Raum über das Relay', _internet),
                const SizedBox(height: 24),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton(
                    key: const ValueKey('tech-check-save'),
                    onPressed: _save,
                    child: Text(context.tr('Speichern')),
                  ),
                ),
              ],
            ),
          ),
  );
}
