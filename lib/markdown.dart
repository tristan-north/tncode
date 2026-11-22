// flutter_markdown_plus is still built on the Material library bundled with
// the Flutter SDK, which is deprecated in favour of package:material_ui. The
// two have separate Theme types, so this file is the one place that uses the
// bundled library: it gives the markdown widget a theme it can find.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

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

final _theme = ThemeData(
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
      ),
);

MarkdownStyleSheet? _styleSheet;

class MarkdownText extends StatelessWidget {
  const MarkdownText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _theme,
      child: Builder(
        builder: (context) {
          // Built from Theme.of rather than from _theme directly: only the
          // inherited theme has font sizes filled in, which fromTheme needs.
          final theme = Theme.of(context);
          final sheet = _styleSheet ??= MarkdownStyleSheet.fromTheme(theme)
              .copyWith(
                code: monoStyle.copyWith(
                  color: theme.colorScheme.primary,
                  backgroundColor: theme.colorScheme.surfaceContainerHigh,
                ),
                codeblockDecoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(6),
                ),
              );
          return MarkdownBody(data: text, styleSheet: sheet);
        },
      ),
    );
  }
}
