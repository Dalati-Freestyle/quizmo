/// Hand written JSON plumbing for the pure Dart domain layer.
///
/// `lib/core` must stay free of Flutter *and* of generated code so that it can
/// run head-less inside a Docker container, a background isolate or a plain
/// `dart test` process. Every model therefore implements serialization
/// explicitly on top of the accessors declared here.
///
/// ## Wire conventions
///
/// * Instants are transported as **microseconds since the Unix epoch** and use
///   the `...Micros` suffix.
/// * Durations are transported as **milliseconds** and use the `...Ms` suffix.
library;

/// The canonical shape of a decoded JSON object.
typedef JsonMap = Map<String, Object?>;

/// Thrown when an inbound payload violates the documented wire contract.
///
/// Network input is never trusted: handlers translate this exception into a
/// protocol level error response instead of tearing down the host process.
class JsonContractException implements Exception {
  /// Creates an exception describing a single broken field expectation.
  const JsonContractException(this.message);

  /// Human readable explanation of the violated contract.
  final String message;

  @override
  String toString() => 'JsonContractException: $message';
}

T _cast<T>(String key, Object? value) {
  if (value is T) return value;
  throw JsonContractException(
    'Field "$key" expected $T but received ${value.runtimeType}.',
  );
}

/// Self describing, null safe accessors for decoded JSON objects.
///
/// Each getter throws a [JsonContractException] that names the offending field,
/// which turns malformed payloads into actionable log lines instead of opaque
/// `type 'Null' is not a subtype of ...` crashes.
extension JsonMapReader on JsonMap {
  Object _required(String key) {
    final value = this[key];
    if (value == null) {
      throw JsonContractException('Missing required field "$key".');
    }
    return value;
  }

  /// Returns the string stored under [key].
  String readString(String key) => _cast<String>(key, _required(key));

  /// Returns the string stored under [key], or `null` when it is absent.
  String? readStringOrNull(String key) =>
      this[key] == null ? null : _cast<String>(key, this[key]);

  /// Returns the integer stored under [key].
  ///
  /// JavaScript collapses whole doubles into integers, so numeric values are
  /// read as [num] and narrowed afterwards.
  int readInt(String key) => _cast<num>(key, _required(key)).toInt();

  /// Returns the integer stored under [key], or `null` when it is absent.
  int? readIntOrNull(String key) =>
      this[key] == null ? null : _cast<num>(key, this[key]).toInt();

  /// Returns the boolean stored under [key], falling back to [orElse].
  bool readBool(String key, {bool orElse = false}) =>
      this[key] == null ? orElse : _cast<bool>(key, this[key]);

  /// Returns the [Duration] stored under [key] as milliseconds.
  Duration readDurationMs(String key) => Duration(milliseconds: readInt(key));

  /// Returns the nested object stored under [key].
  JsonMap readObject(String key) => _cast<JsonMap>(key, _required(key));

  /// Returns the nested object stored under [key], or `null` when absent.
  JsonMap? readObjectOrNull(String key) =>
      this[key] == null ? null : _cast<JsonMap>(key, this[key]);

  /// Decodes the list of objects stored under [key] with [decode].
  List<T> readList<T>(String key, T Function(JsonMap json) decode) =>
      _cast<List<Object?>>(key, _required(key))
          .map((element) => decode(_cast<JsonMap>(key, element)))
          .toList(growable: false);

  /// Returns the list of strings stored under [key].
  List<String> readStringList(String key) => _cast<List<Object?>>(
    key,
    _required(key),
  ).map((element) => _cast<String>(key, element)).toList(growable: false);

  /// Returns the list of integers stored under [key].
  List<int> readIntList(String key) => _cast<List<Object?>>(
    key,
    _required(key),
  ).map((element) => _cast<num>(key, element).toInt()).toList(growable: false);

  /// Decodes the `<id, object>` map stored under [key] with [decode].
  Map<String, T> readMap<T>(String key, T Function(JsonMap json) decode) {
    final raw = _cast<JsonMap>(key, _required(key));
    return {
      for (final entry in raw.entries)
        entry.key: decode(_cast<JsonMap>(key, entry.value)),
    };
  }

  /// Returns the `<id, int>` map stored under [key].
  Map<String, int> readIntMap(String key) {
    final raw = _cast<JsonMap>(key, _required(key));
    return {
      for (final entry in raw.entries)
        entry.key: _cast<num>(key, entry.value).toInt(),
    };
  }
}
