import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'annotation_highlights.dart';
import 'annotations.dart';
import 'markdown.dart';
import 'sessions.dart';
import 'theme.dart';

/// The line above a prompt and its reply: the title of their session and
/// when the prompt was sent.
class ExchangeHeading extends StatelessWidget {
  const ExchangeHeading(this.exchange, {super.key});

  final Exchange exchange;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final session = exchange.session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _relativeTime(exchange.time),
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One entry of a conversation, drawn as its kind is: a message, a tool
/// call, the output of a command and so on.
class EntryView extends StatelessWidget {
  const EntryView({
    super.key,
    required this.entry,
    required this.name,
    required this.open,
    required this.onToggle,
    required this.annotations,
  });

  final Entry entry;
  final EntryName name;

  /// Whether the entry is unfolded, if it is of a kind that folds.
  final bool open;
  final VoidCallback onToggle;
  final Annotations annotations;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    switch (entry.kind) {
      case EntryKind.user:
        return _MessageCard(
          accent: colors.primary,
          background: colors.surfaceBright,
          icon: Icons.person_outline,
          author: 'You',
          time: entry.time,
          child: _UserContent(entry: entry),
        );
      case EntryKind.assistant:
        return _MessageCard(
          accent: colors.tertiary,
          background: colors.surface,
          icon: Icons.auto_awesome_outlined,
          author: 'Claude',
          time: entry.time,
          headerButton: _CopyAnnotationsButton(
            annotations: annotations,
            reply: name,
          ),
          child: Annotatable(
            name: name,
            board: annotations,
            child: MarkdownText(entry.text),
          ),
        );
      case EntryKind.output:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _CodeBox(entry.text),
        );
      case EntryKind.thinking:
        return _Collapsible(
          icon: Icons.psychology_outlined,
          label: 'Thinking',
          summary: open ? '' : entry.text.replaceAll('\n', ' '),
          open: open,
          onTap: onToggle,
          child: Text(
            entry.text,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      case EntryKind.note:
        final firstLine = entry.text.split('\n').first;
        final multiline = firstLine.length < entry.text.length;
        return _Collapsible(
          icon: Icons.info_outline,
          label: multiline ? 'Earlier conversation summarized' : firstLine,
          summary: '',
          open: open,
          onTap: multiline ? onToggle : null,
          child: Text(
            entry.text,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        );
      case EntryKind.tool:
        final result = entry.toolResult;
        return _Collapsible(
          icon: entry.toolError ? Icons.error_outline : Icons.build_outlined,
          iconColor: entry.toolError ? colors.error : null,
          label: entry.toolName ?? 'Tool',
          summary: entry.text,
          open: open,
          onTap: onToggle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CodeBox(entry.toolInput ?? ''),
              if (result != null && result.isNotEmpty) ...[
                const SizedBox(height: 6),
                _CodeBox(result, error: entry.toolError),
              ],
            ],
          ),
        );
    }
  }
}

/// The button on a reply that has annotations, which copies them.
class _CopyAnnotationsButton extends StatelessWidget {
  const _CopyAnnotationsButton({
    required this.annotations,
    required this.reply,
  });

  final Annotations annotations;
  final EntryName reply;

  void _copy(BuildContext context) {
    final count = annotations.countIn(reply);
    Clipboard.setData(ClipboardData(text: annotations.export(reply)));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count == 1 ? 'Copied 1 annotation' : 'Copied $count annotations',
        ),
        behavior: SnackBarBehavior.floating,
        width: 280,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: annotations,
      builder: (context, _) {
        final count = annotations.countIn(reply);
        if (count == 0) return const SizedBox.shrink();
        // Its label is not part of the conversation's text.
        return SelectionContainer.disabled(
          child: OutlinedButton.icon(
            onPressed: () => _copy(context),
            icon: const Icon(Icons.copy, size: 13),
            label: Text(
              count == 1 ? 'Copy 1 annotation' : 'Copy $count annotations',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.onSurface,
              iconColor: colors.tertiary,
              backgroundColor: colors.surfaceBright,
              side: BorderSide(color: colors.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              textStyle: const TextStyle(fontSize: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, _MessageCard.headerButtonHeight),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        );
      },
    );
  }
}

/// One message: a bordered card with a coloured left edge and a header line
/// naming the author.
class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.accent,
    required this.background,
    required this.icon,
    required this.author,
    required this.time,
    required this.child,
    this.headerButton,
  });

  /// The header line is not as tall as this, and does not grow for the
  /// button: text that moved down when a reply got its first annotation
  /// would move away from the comment box.
  static const headerButtonHeight = 24.0;

  /// Shown in the middle of the header line.
  final Widget? headerButton;

  final Color accent;
  final Color background;
  final IconData icon;
  final String author;
  final DateTime? time;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          padding: const EdgeInsets.fromLTRB(15, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 15, color: accent),
                      const SizedBox(width: 6),
                      Text(
                        author,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                      const Spacer(),
                      if (time != null)
                        Text(
                          _hourMinute(time!),
                          style: monoStyle.copyWith(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  if (headerButton != null)
                    Positioned(
                      height: headerButtonHeight,
                      child: headerButton!,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

final _inlineCode = RegExp(r'`([^`\n]+)`');

class _UserContent extends StatelessWidget {
  const _UserContent({required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final codeStyle = monoStyle.copyWith(
      color: colors.primary,
      backgroundColor: colors.surfaceContainerHigh,
    );

    // Prompts are shown as typed, except that `backticked` spans are set as
    // code.
    final text = entry.text;
    final spans = <InlineSpan>[];
    var end = 0;
    for (final match in _inlineCode.allMatches(text)) {
      spans.add(TextSpan(text: text.substring(end, match.start)));
      spans.add(TextSpan(text: ' ${match.group(1)} ', style: codeStyle));
      end = match.end;
    }
    spans.add(TextSpan(text: text.substring(end)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (text.isNotEmpty)
          Text.rich(
            TextSpan(children: spans),
            style: const TextStyle(height: 1.45),
          ),
        for (final image in entry.images)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _MessageImage(image),
          ),
      ],
    );
  }
}

/// An attached image, at most [_maxHeight] tall. Its box is sized from the
/// image's known dimensions rather than from the decoded image, which arrives
/// a few frames late: a box that grew then would push the conversation down
/// after the view had scrolled to its end.
class _MessageImage extends StatelessWidget {
  const _MessageImage(this.image);

  final EntryImage image;

  static const _maxHeight = 360.0;

  @override
  Widget build(BuildContext context) {
    final width = image.width, height = image.height;
    return LayoutBuilder(
      builder: (context, constraints) {
        var size = const Size(_maxHeight, _maxHeight);
        if (width != null && height != null && width > 0 && height > 0) {
          final scale = [
            1.0,
            constraints.maxWidth / width,
            _maxHeight / height,
          ].reduce((a, b) => a < b ? a : b);
          size = Size(width * scale, height * scale);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox.fromSize(
            size: size,
            child: Image.memory(
              image.bytes,
              // Decode near display size; pasted screenshots are large.
              cacheHeight: 720,
              fit: BoxFit.contain,
              alignment: Alignment.topLeft,
              errorBuilder: (_, _, _) => const Text('[image]'),
            ),
          ),
        );
      },
    );
  }
}

/// A one-line header that opens to show [child] underneath.
class _Collapsible extends StatelessWidget {
  const _Collapsible({
    required this.icon,
    required this.label,
    required this.summary,
    required this.open,
    required this.onTap,
    required this.child,
    this.iconColor,
  });

  final IconData icon;
  final Color? iconColor;
  final String label;
  final String summary;
  final bool open;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final labelText = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: colors.onSurfaceVariant,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: iconColor ?? colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                // Tool names are short and sit beside a summary that takes
                // the remaining width; a note has only its label, which then
                // takes that width itself.
                if (summary.isEmpty)
                  Expanded(child: labelText)
                else ...[
                  labelText,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle.copyWith(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                if (onTap != null)
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 4, bottom: 8),
            child: child,
          ),
      ],
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox(this.text, {this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: monoStyle.copyWith(
          color: error ? colors.error : colors.onSurface,
        ),
      ),
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

String _date(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';

String _hourMinute(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return '${_date(t)} ${_hourMinute(t)}';
}
