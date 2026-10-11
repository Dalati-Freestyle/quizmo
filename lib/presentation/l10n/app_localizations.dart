import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'translations.g.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);
  final Locale locale;

  static const supportedLocales = [Locale('en'), Locale('de')];
  static const delegate = _AppLocalizationsDelegate();

  static final _templates = {
    'de': _messageTemplates(germanMessages),
    'en': _messageTemplates(englishMessages),
  };

  static List<({RegExp pattern, List<int> captures, String translation})>
  _messageTemplates(Map<String, String> catalog) {
    final result =
        <({RegExp pattern, List<int> captures, String translation})>[];
    for (final entry in catalog.entries) {
      if (!entry.key.contains(RegExp(r'\{\d+\}'))) continue;
      final captures = <int>[];
      final pattern = StringBuffer('^');
      var start = 0;
      for (final placeholder in RegExp(r'\{(\d+)\}').allMatches(entry.key)) {
        pattern.write(
          RegExp.escape(entry.key.substring(start, placeholder.start)),
        );
        pattern.write('([\\s\\S]*?)');
        captures.add(int.parse(placeholder.group(1)!));
        start = placeholder.end;
      }
      pattern.write(RegExp.escape(entry.key.substring(start)));
      pattern.write(r'$');
      result.add((
        pattern: RegExp(pattern.toString()),
        captures: captures,
        translation: entry.value,
      ));
    }
    return result;
  }

  static Locale resolveLocale(
    List<Locale>? preferred,
    Iterable<Locale> supported,
  ) {
    for (final locale in preferred ?? const <Locale>[]) {
      for (final candidate in supported) {
        if (candidate.languageCode == locale.languageCode) return candidate;
      }
    }
    return const Locale('en');
  }

  String text(String message, [List<Object?> arguments = const []]) {
    final catalog = locale.languageCode == 'de'
        ? germanMessages
        : englishMessages;
    final translated = catalog[message];
    if (translated != null || arguments.isNotEmpty) {
      return formatMessage(translated ?? message, arguments);
    }
    for (final prefix in const [
      'JsonContractException: ',
      'QuizImportException: ',
      'QuizRepositoryException: ',
      'QuizValidationException: ',
      'FormatException: ',
    ]) {
      if (message.startsWith(prefix)) {
        return text(message.substring(prefix.length));
      }
    }
    if (message.contains('\n')) {
      return message.split('\n').map((line) => text(line)).join('\n');
    }
    // Host notices and validation errors originate in the pure Dart layers.
    // Translate their known templates at the presentation boundary.
    for (final template
        in _templates[locale.languageCode == 'de' ? 'de' : 'en']!) {
      final captures = template.captures;
      final match = template.pattern.firstMatch(message);
      if (match == null) continue;
      final values = List<Object?>.filled(
        captures.fold(0, (a, b) => a > b ? a : b) + 1,
        null,
      );
      for (var i = 0; i < captures.length; i++) {
        values[captures[i]] = match.group(i + 1);
      }
      return formatMessage(template.translation, values);
    }
    return message;
  }

  static String formatMessage(String message, List<Object?> arguments) =>
      message.replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
        final index = int.parse(match.group(1)!);
        return index < arguments.length
            ? '${arguments[index] ?? ""}'
            : match.group(0)!;
      });
}

extension LocalizedContext on BuildContext {
  String tr(String message, [List<Object?> arguments = const []]) {
    final translations = Localizations.of<AppLocalizations>(
      this,
      AppLocalizations,
    );
    return translations?.text(message, arguments) ??
        AppLocalizations.formatMessage(message, arguments);
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();
  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );
  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale));
  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
