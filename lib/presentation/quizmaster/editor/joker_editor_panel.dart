/// Editor panel that decides whether, and which, jokers a quiz offers.
library;

import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../common/adaptive_layout.dart';
import '../../common/joker_texts.dart';
import '../../l10n/app_localizations.dart';

/// Lists the joker kinds the quiz format supports; each can be switched on
/// and configured. A quiz has no jokers unless one is switched on here.
class JokerEditorPanel extends StatelessWidget {
  /// Creates the panel for [quiz].
  const JokerEditorPanel({
    required this.quiz,
    required this.onSet,
    required this.onRemove,
    super.key,
  });

  final Quiz quiz;

  /// Adds [Joker] or replaces the configured joker of the same kind.
  final ValueChanged<Joker> onSet;

  /// Removes the joker with this id.
  final ValueChanged<String> onRemove;

  /// Whether [format] offers any joker kind at all.
  static bool offersJokers(QuizFormat format) =>
      kJokerTemplates.any((joker) => joker.isSupportedBy(format));

  @override
  Widget build(BuildContext context) => PanelCard(
    title: context.tr("Joker (optional)"),
    icon: Icons.style_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(
            "Ohne eingeschalteten Joker spielt das Quiz ohne Joker. Jedes Team bekommt jeden eingeschalteten Joker so oft wie angegeben; ein Team kann pro Frage nur von einem Joker betroffen sein.",
          ),
        ),
        for (final template in kJokerTemplates)
          if (template.isSupportedBy(quiz.format))
            _JokerTile(
              key: ValueKey('joker-${template.id}'),
              configured: quiz.jokers
                  .where((joker) => joker.id == template.id)
                  .firstOrNull,
              template: template,
              onSet: onSet,
              onRemove: onRemove,
            ),
      ],
    ),
  );
}

class _JokerTile extends StatelessWidget {
  const _JokerTile({
    required this.configured,
    required this.template,
    required this.onSet,
    required this.onRemove,
    super.key,
  });

  final Joker? configured;
  final Joker template;
  final ValueChanged<Joker> onSet;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final joker = configured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(jokerIcon(template)),
          title: Text(jokerName(context, template)),
          subtitle: Text(jokerRule(context, joker ?? template)),
          value: joker != null,
          onChanged: (on) => on ? onSet(template) : onRemove(template.id),
        ),
        if (joker != null)
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _NumberField(
                fieldKey: '${joker.id}-uses',
                label: context.tr("Einsätze pro Team"),
                value: joker.usesPerTeam,
                onChanged: (uses) => onSet(switch (joker) {
                  CreditJoker(:final maxLoss) => CreditJoker(
                    usesPerTeam: uses,
                    maxLoss: maxLoss,
                  ),
                  ForcedStakeJoker(
                    :final stake,
                    :final cost,
                    :final lossFactor,
                  ) =>
                    ForcedStakeJoker(
                      usesPerTeam: uses,
                      stake: stake,
                      cost: cost,
                      lossFactor: lossFactor,
                    ),
                }),
              ),
              ...switch (joker) {
                CreditJoker(:final usesPerTeam) => [
                  _NumberField(
                    fieldKey: '${joker.id}-maxLoss',
                    label: context.tr("Restverlust in Chips"),
                    value: joker.maxLoss,
                    onChanged: (value) => onSet(
                      CreditJoker(usesPerTeam: usesPerTeam, maxLoss: value),
                    ),
                  ),
                ],
                ForcedStakeJoker(
                  :final usesPerTeam,
                  :final stake,
                  :final cost,
                  :final lossFactor,
                ) =>
                  [
                    _NumberField(
                      fieldKey: '${joker.id}-stake',
                      label: context.tr("Zwangseinsatz"),
                      value: stake,
                      onChanged: (value) => onSet(
                        ForcedStakeJoker(
                          usesPerTeam: usesPerTeam,
                          stake: value,
                          cost: cost,
                          lossFactor: lossFactor,
                        ),
                      ),
                    ),
                    _NumberField(
                      fieldKey: '${joker.id}-cost',
                      label: context.tr("Kosten für den Angreifer"),
                      value: cost,
                      onChanged: (value) => onSet(
                        ForcedStakeJoker(
                          usesPerTeam: usesPerTeam,
                          stake: stake,
                          cost: value,
                          lossFactor: lossFactor,
                        ),
                      ),
                    ),
                    _NumberField(
                      fieldKey: '${joker.id}-lossFactor',
                      label: context.tr("Verlustfaktor bei Falsch"),
                      value: lossFactor,
                      onChanged: (value) => onSet(
                        ForcedStakeJoker(
                          usesPerTeam: usesPerTeam,
                          stake: stake,
                          cost: cost,
                          lossFactor: value,
                        ),
                      ),
                    ),
                  ],
              },
            ],
          ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String fieldKey;
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: TextFormField(
      key: ValueKey(fieldKey),
      initialValue: '$value',
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      // Invalid input stays visible and is reported by the quiz validation.
      onChanged: (text) => onChanged(int.tryParse(text.trim()) ?? -1),
    ),
  );
}
