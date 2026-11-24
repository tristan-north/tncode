// flutter_markdown_plus is still built on the Material library bundled with
// the Flutter SDK, which is deprecated in favour of package:material_ui. The
// two have separate Theme types, so this file is the one place that uses the
// bundled library: it gives the markdown widget a theme it can find.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'theme.dart';

// The same colours as [appTheme], which is of the other library's type and
// so cannot be used here.
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
                // Replies are set a little larger than prompts.
                textScaler: const TextScaler.linear(15 / 14),
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
