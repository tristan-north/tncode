import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'launch.dart';
import 'markdown.dart';
import 'sessions.dart';

void main(List<String> args) {
  final options = LaunchOptions.parse(args);
  options.startTimeout();
  runApp(TncodeApp(options: options));
}

const _mono = monoStyle;

class TncodeApp extends StatelessWidget {
  const TncodeApp({super.key, required this.options});

  final LaunchOptions options;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Claude Sessions',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
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
              // Claude's colour. The one made from a blue seed is pink.
              tertiary: const Color(0xFFD8C58D),
            ),
      ),
      builder: (context, child) => options.wrap(context, child!),
      home: HomePage(options: options),
    );
  }
}

/// How many prompts, with their replies, the page shows.
const _exchangeCount = 10;

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.options});

  final LaunchOptions options;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Exchange>? _exchanges;
  Object? _error;

  late bool _showTools = widget.options.showTools;

  /// False from when the exchanges load until the view has scrolled to its
  /// end.
  bool _atLatest = false;
  bool _searching = false;
  String _query = '';

  /// What the list shows, recomputed only when the Tools toggle or the search
  /// changes: each [Exchange] that has entries passing those, as its heading,
  /// followed by those entries.
  List<Object> _rows = const [];
  int _entryCount = 0;

  /// Which collapsible entries are open, each named by its session's path and
  /// its position in the session: a reload makes new entries for a session
  /// that has changed, and those names carry over to them.
  final _expanded = <(String, int)>{};
  var _names = Map<Entry, (String, int)>.identity();

  final _store = SessionStore();
  late final _watcher = SessionWatcher(_scheduleLoad);
  Timer? _loadTimer;
  bool _loading = false;

  /// Whether a transcript changed while a load was under way.
  bool _stale = false;

  final _scroll = ScrollController();
  final _searchField = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _load();
    _watcher; // Starts watching.
  }

  @override
  void dispose() {
    _watcher.dispose();
    _loadTimer?.cancel();
    _scroll.dispose();
    _searchField.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// A transcript is written to many times a second while Claude is at
  /// work, so a change is acted on half a second later, together with all
  /// that follow it in that time.
  void _scheduleLoad() {
    _loadTimer ??= Timer(const Duration(milliseconds: 500), () {
      _loadTimer = null;
      _load();
    });
  }

  Future<void> _load() async {
    if (_loading) {
      _stale = true;
      return;
    }
    _loading = true;
    final options = widget.options;
    try {
      final changed = await _store.refresh();
      final first = _exchanges == null;
      if (!mounted || (!changed && !first)) return;
      var sessions = _store.sessions;
      // A session named on the command line is shown alone.
      final wanted = options.session;
      if (wanted != null) {
        sessions = wanted == 'latest'
            ? sessions.take(1).toList()
            : sessions.where((s) => s.id.startsWith(wanted)).toList();
        if (sessions.isEmpty) options.fail('no session matches "$wanted"');
      }
      final exchanges = await _store.recentExchanges(sessions, _exchangeCount);
      if (!mounted) return;

      // Most changes are to sessions that are not on the page.
      final before = _exchanges;
      var same = before != null && before.length == exchanges.length;
      for (var i = 0; same && i < exchanges.length; i++) {
        same = identical(before![i], exchanges[i]);
      }
      // A view that is at its end stays there as messages arrive; one that
      // has been scrolled back is left where it is.
      final follow = first
          ? !options.openAtTop
          : _scroll.hasClients &&
                _scroll.position.pixels >= _scroll.position.maxScrollExtent;
      setState(() {
        _exchanges = exchanges;
        _error = null;
        if (!same) _updateRows();
      });
      if (same) return;
      // On the first load the list stays hidden until it has settled at its
      // end, so it does not flash its first messages.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (follow) await _scrollToBottom();
        if (!first) return;
        if (mounted) setState(() => _atLatest = true);
        options.settled();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
      options.fail('could not read sessions: $error');
    } finally {
      _loading = false;
      if (_stale) {
        _stale = false;
        _scheduleLoad();
      }
    }
  }

  void _updateRows() {
    bool matches(Entry e) =>
        e.text.toLowerCase().contains(_query) ||
        (e.toolName?.toLowerCase().contains(_query) ?? false) ||
        (e.toolInput?.toLowerCase().contains(_query) ?? false) ||
        (e.toolResult?.toLowerCase().contains(_query) ?? false);
    final rows = <Object>[];
    final names = Map<Entry, (String, int)>.identity();
    var entryCount = 0;
    for (final exchange in _exchanges ?? const <Exchange>[]) {
      final path = exchange.session.path;
      names[exchange.prompt] = (path, exchange.index);
      for (final (i, reply) in exchange.replies.indexed) {
        names[reply] = (path, exchange.index + 1 + i);
      }
      final entries = [
        for (final e in [exchange.prompt, ...exchange.replies])
          if ((_showTools || e.kind != EntryKind.tool) &&
              (_query.isEmpty || matches(e)))
            e,
      ];
      if (entries.isEmpty) continue;
      rows
        ..add(exchange)
        ..addAll(entries);
      entryCount += entries.length;
    }
    _rows = rows;
    _names = names;
    _entryCount = entryCount;
  }

  void _openSearch() {
    setState(() => _searching = true);
    _searchFocus.requestFocus();
  }

  void _closeSearch() {
    _searchField.clear();
    setState(() {
      _searching = false;
      _query = '';
      _updateRows();
    });
  }

  void _scrollToTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// The list only knows the height of rows it has built, so the far end is
  /// an estimate, which can fall short of or overshoot the real end and is
  /// corrected once the rows there are built: jump until it settles.
  Future<void> _scrollToBottom() async {
    for (var i = 0; i < 20; i++) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      if (i > 0 && position.pixels == position.maxScrollExtent) return;
      _scroll.jumpTo(position.maxScrollExtent);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _openSearch,
          if (_searching)
            const SingleActivator(LogicalKeyboardKey.escape): _closeSearch,
        },
        child: Focus(
          autofocus: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: colors.surfaceContainerLow,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [_buildHeader(), if (_searching) _buildSearchBar()],
                ),
              ),
              Divider(height: 1, color: colors.outlineVariant),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final colors = Theme.of(context).colorScheme;
    final exchanges = _exchanges;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              Icons.forum_outlined,
              size: 16,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Claude Sessions',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              Text(
                exchanges == null
                    ? 'Loading…'
                    : 'Latest ${exchanges.length} prompts',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(width: 18),
          _ToggleButton(
            label: 'Show tool calls',
            icon: Icons.build_outlined,
            tooltip: _showTools
                ? 'Tool calls are shown. Click to hide them.'
                : 'Tool calls are hidden. Click to show them.',
            active: _showTools,
            onPressed: () => setState(() {
              _showTools = !_showTools;
              _updateRows();
            }),
          ),
          const Spacer(),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Search these messages (Ctrl+F)',
            icon: const Icon(Icons.search, size: 20),
            isSelected: _searching,
            onPressed: _searching ? _closeSearch : _openSearch,
          ),
          IconButton(
            tooltip: 'Scroll to top',
            icon: const Icon(Icons.vertical_align_top, size: 20),
            onPressed: _scrollToTop,
          ),
          IconButton(
            tooltip: 'Scroll to bottom',
            icon: const Icon(Icons.vertical_align_bottom, size: 20),
            onPressed: _scrollToBottom,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchField,
              focusNode: _searchFocus,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Show only messages containing…',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() {
                _query = value.trim().toLowerCase();
                _updateRows();
              }),
            ),
          ),
          const SizedBox(width: 12),
          if (_query.isNotEmpty)
            Text(
              '$_entryCount matching',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          IconButton(
            tooltip: 'Close search (Esc)',
            icon: const Icon(Icons.close, size: 18),
            onPressed: _closeSearch,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) return _Message('Could not read sessions:\n$_error');
    final exchanges = _exchanges;
    if (exchanges == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (exchanges.isEmpty) {
      final root = claudeProjectsDir();
      return _Message(
        root == null
            ? 'Cannot find Claude Code sessions: HOME is not set'
            : 'No prompts found in\n$root',
      );
    }
    if (_rows.isEmpty) return _Message('No messages contain “$_query”');
    return Opacity(
      opacity: _atLatest ? 1 : 0,
      child: SelectionArea(
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          itemCount: _rows.length,
          itemBuilder: (context, i) {
            final row = _rows[i];
            final heading = row is Exchange;
            final last = i + 1 == _rows.length || _rows[i + 1] is Exchange;
            // An exchange is drawn as one panel, which is made of its rows:
            // the heading rounds the top corners and the last entry the
            // bottom ones.
            const radius = Radius.circular(10);
            final panel = Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                14,
                heading ? 12 : 0,
                14,
                last ? 10 : 0,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.vertical(
                  top: heading ? radius : Radius.zero,
                  bottom: last ? radius : Radius.zero,
                ),
              ),
              child: heading
                  ? _ExchangeHeading(row)
                  : _buildEntry(row as Entry),
            );
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Padding(
                  padding: EdgeInsets.only(top: heading && i > 0 ? 22 : 0),
                  child: panel,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _toggle(Entry entry) => setState(() {
    final name = _names[entry]!;
    if (!_expanded.remove(name)) _expanded.add(name);
  });

  Widget _buildEntry(Entry entry) {
    final colors = Theme.of(context).colorScheme;
    final open = _expanded.contains(_names[entry]);
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
          child: MarkdownText(entry.text),
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
          onTap: () => _toggle(entry),
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
          onTap: multiline ? () => _toggle(entry) : null,
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
          onTap: () => _toggle(entry),
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

/// The line above a prompt and its reply: the project they belong to, the
/// title of their session and when the prompt was sent.
class _ExchangeHeading extends StatelessWidget {
  const _ExchangeHeading(this.exchange);

  final Exchange exchange;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final session = exchange.session;
    final project = session.projectDir
        .split('/')
        .lastWhere((part) => part.isNotEmpty, orElse: () => session.projectDir);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Tooltip(
                message: shortenHome(session.projectDir),
                child: _Chip(
                  project,
                  icon: Icons.folder_outlined,
                  color: _projectColor(session.projectDir),
                ),
              ),
              const SizedBox(width: 10),
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

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// A small bordered label, optionally led by an icon, for a piece of metadata.
class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.icon, this.color});

  final String text;
  final IconData? icon;

  /// Tints the chip. Without it the chip is neutral.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = this.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color == null
            ? colors.surfaceContainer
            : color.withValues(alpha: 0.13),
        border: Border.all(
          color: color == null
              ? colors.outlineVariant
              : color.withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color ?? colors.onSurfaceVariant),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _mono.copyWith(
                fontSize: 11,
                color: color ?? colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: active
              ? colors.onSecondaryContainer
              : colors.onSurface,
          iconColor: colors.primary,
          backgroundColor: active ? colors.secondaryContainer : null,
          side: BorderSide(
            color: active ? colors.primary : colors.outlineVariant,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          visualDensity: VisualDensity.compact,
        ),
      ),
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
  });

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
                      style: _mono.copyWith(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
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
    final codeStyle = _mono.copyWith(
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
                      style: _mono.copyWith(
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
        style: _mono.copyWith(color: error ? colors.error : colors.onSurface),
      ),
    );
  }
}

/// A colour for a project that is the same on every launch: its hue comes
/// from a hash of the directory path. The hash is written out here because
/// [String.hashCode] is not guaranteed to be stable between runs.
Color _projectColor(String projectDir) {
  var hash = 0x811c9dc5; // FNV-1a, 32 bit
  for (final unit in projectDir.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return HSLColor.fromAHSL(1, hash % 360, 0.65, 0.72).toColor();
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
