import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class QuizmoLogo extends StatelessWidget {
  const QuizmoLogo({this.size = 40, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.18),
    child: Image.asset(
      'assets/branding/logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: context.tr("Quizmo logo"),
    ),
  );
}
