import 'package:material_ui/material_ui.dart';

const seedColor = Color(0xFF4A8FE0);
const monoStyle = TextStyle(
  fontFamily: 'monospace',
  fontSize: 13,
  height: 1.35,
);

/// Neutral greys for the backgrounds and text, and the accent colour. The
/// scheme made from [seedColor] tints its greys and sets near-white text on
/// near-black; these are untinted and closer together.
const surfaceColors = (
  page: Color(0xFF212121),
  bar: Color(0xFF272727),
  panel: Color(0xFF2B2B2B),
  raised: Color(0xFF323232),
  code: Color(0xFF3A3A3A),
  line: Color(0xFF444444),
  text: Color(0xFFC8C8C8),
  dimText: Color(0xFF989898),
  accent: Color(0xFFB1B9F9),
);

/// Claude's colour. The one made from a blue seed is pink.
const claudeColor = Color(0xFFD8C58D);

/// The theme of the app. The markdown of a reply is drawn by a package that
/// needs a theme of its own, which `markdown.dart` makes from the same
/// colours.
final appTheme = ThemeData(
  colorScheme:
      ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.dark,
      ).copyWith(
        surface: surfaceColors.page,
        surfaceContainerLow: surfaceColors.bar,
        surfaceContainer: surfaceColors.panel,
        surfaceBright: surfaceColors.raised,
        surfaceContainerHigh: surfaceColors.code,
        onSurface: surfaceColors.text,
        primary: surfaceColors.accent,
        onSurfaceVariant: surfaceColors.dimText,
        outlineVariant: surfaceColors.line,
        tertiary: claudeColor,
      ),
);

/// A colour for a project that is the same on every launch: its hue comes
/// from a hash of the directory path. The hash is written out here because
/// [String.hashCode] is not guaranteed to be stable between runs.
Color projectColor(String projectDir) {
  var hash = 0x811c9dc5; // FNV-1a, 32 bit
  for (final unit in projectDir.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return HSLColor.fromAHSL(1, hash % 360, 0.65, 0.72).toColor();
}
