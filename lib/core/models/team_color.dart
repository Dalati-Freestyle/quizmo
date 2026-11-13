/// The named colours offered for teams and admin view sections.
library;

/// One colour of the shared Quizmo palette.
///
/// Quiz files (schema 9 and newer) store a team colour by [name], so nobody
/// has to pick colours with cryptic hexadecimal codes. The same colours are
/// offered for the sections of the admin view.
enum TeamColor {
  blue(0xFF3F6FD8, 'Blau'),
  teal(0xFF1E9E8F, 'Türkis'),
  orange(0xFFD9822B, 'Orange'),
  purple(0xFF8E5BD6, 'Lila'),
  green(0xFF2E9E4F, 'Grün'),
  pink(0xFFD64F7A, 'Pink'),
  ochre(0xFFB59A12, 'Ocker'),
  cyan(0xFF0B8FC4, 'Cyan'),
  red(0xFFC0392B, 'Rot'),
  olive(0xFF6D7F1A, 'Oliv'),
  indigo(0xFF5C6BC0, 'Indigo'),
  brown(0xFF8D6E63, 'Braun'),
  darkTeal(0xFF00897B, 'Petrol'),
  orchid(0xFFAD5FB0, 'Orchidee'),
  slate(0xFF607D8B, 'Schiefergrau'),
  vermilion(0xFFE0682B, 'Zinnober');

  const TeamColor(this.argb, this.labelKey);

  /// 32 bit ARGB value.
  final int argb;

  /// Message key of the display name.
  final String labelKey;

  /// The palette colour named [name], or `null`.
  static TeamColor? byName(String name) =>
      values.where((color) => color.name == name).firstOrNull;

  /// The palette colour closest to [argb] (exact matches win).
  ///
  /// Used to migrate team colours of quiz files before schema 9, which stored
  /// any ARGB value.
  static TeamColor nearest(int argb) {
    int channel(int value, int shift) => (value >> shift) & 0xFF;
    var best = values.first;
    var bestDistance = 1 << 30;
    for (final color in values) {
      var distance = 0;
      for (final shift in const [16, 8, 0]) {
        final delta = channel(color.argb, shift) - channel(argb, shift);
        distance += delta * delta;
      }
      if (distance < bestDistance) {
        best = color;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// A colour for the [index]th team, cycling through the palette.
  static TeamColor forIndex(int index) => values[index % values.length];
}
