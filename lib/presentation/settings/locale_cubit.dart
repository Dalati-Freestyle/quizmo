import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LanguagePreference {
  system,
  de,
  en;

  Locale? get locale => this == system ? null : Locale(name);
}

abstract interface class LanguagePreferenceStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPreferencesLanguageStore implements LanguagePreferenceStore {
  static const key = 'quizmo.language.v1';
  late final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  @override
  Future<String?> read() => _preferences.getString(key);
  @override
  Future<void> write(String value) => _preferences.setString(key, value);
}

class LocaleSettingsState {
  const LocaleSettingsState({
    this.preference = LanguagePreference.system,
    this.error,
  });
  final LanguagePreference preference;
  final String? error;
}

class LocaleCubit extends Cubit<LocaleSettingsState> {
  LocaleCubit({LanguagePreferenceStore? store})
    : _store = store ?? SharedPreferencesLanguageStore(),
      super(const LocaleSettingsState());
  final LanguagePreferenceStore _store;
  int _revision = 0;
  Future<void> _writes = Future.value();

  Future<void> load() async {
    final revision = _revision;
    try {
      final saved = await _store.read();
      if (isClosed || revision != _revision) return;
      final preference = LanguagePreference.values.firstWhere(
        (value) => value.name == saved,
        orElse: () => LanguagePreference.system,
      );
      emit(LocaleSettingsState(preference: preference));
    } on Object {
      if (!isClosed && revision == _revision) {
        emit(
          LocaleSettingsState(
            preference: state.preference,
            error: 'Language settings could not be loaded. Select your language again.',
          ),
        );
      }
    }
  }

  Future<void> select(LanguagePreference preference) async {
    if (isClosed) return;
    final revision = ++_revision;
    emit(LocaleSettingsState(preference: preference));
    _writes = _writes.then((_) => _store.write(preference.name));
    final currentWrite = _writes;
    // A failed write must not prevent a later choice from being saved.
    _writes = currentWrite.catchError((Object _) {});
    try {
      await currentWrite;
    } on Object {
      if (!isClosed && revision == _revision) {
        emit(
          LocaleSettingsState(
            preference: preference,
            error: 'Language settings could not be saved. Check browser storage or device permissions and try again.',
          ),
        );
      }
    }
  }
}
