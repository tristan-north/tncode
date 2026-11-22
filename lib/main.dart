import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'markdown.dart';
import 'sessions.dart';

void main() {
  runApp(const TncodeApp());
}

const _mono = monoStyle;

class TncodeApp extends StatelessWidget {
  const TncodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Claude Sessions',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<SessionInfo>? _sessions;
  Object? _error;
  SessionInfo? _selected;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _sessions = null;
      _error = null;
    });
    try {
      final sessions = await loadSessions();
      if (mounted) setState(() => _sessions = sessions);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 380,
            child: Material(
              color: colors.surfaceContainerLow,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSidebarHeader(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 14, 10),
                    child: TextField(
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Filter projects or sessions...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        filled: true,
                        fillColor: colors.surface,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: colors.outlineVariant),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) =>
                          setState(() => _filter = v.toLowerCase()),
                    ),
                  ),
                  Divider(height: 1, color: colors.outlineVariant),
                  Expanded(child: _buildSessionList()),
                ],
              ),
            ),
          ),
          VerticalDivider(width: 1, color: colors.outlineVariant),
          Expanded(
            child: _selected == null
                ? const _Message('Select a session')
                : ConversationView(
                    key: ValueKey(_selected!.path),
                    session: _selected!,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader() {
    final colors = Theme.of(context).colorScheme;
    final sessions = _sessions;
    final projectCount = sessions?.map((s) => s.projectDir).toSet().length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Claude Sessions',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Text(
                  sessions == null
                      ? 'Loading…'
                      : '$projectCount projects · ${sessions.length} sessions',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Reload sessions',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: _load,
          ),
        ],
      ),
    );
  }

  Widget _buildSessionList() {
    if (_error != null) return _Message('Could not read sessions:\n$_error');
    final sessions = _sessions;
    if (sessions == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (sessions.isEmpty) {
      final root = claudeProjectsDir();
      return _Message(
        root == null
            ? 'Cannot find Claude Code sessions: HOME is not set'
            : 'No sessions found in\n$root',
      );
    }
    final matching = _filter.isEmpty
        ? sessions
        : [
            for (final s in sessions)
              if (s.title.toLowerCase().contains(_filter) ||
                  s.projectDir.toLowerCase().contains(_filter))
                s,
          ];
    if (matching.isEmpty) return const _Message('No matching sessions');
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: matching.length,
      itemBuilder: (context, i) => _buildSession(matching[i]),
    );
  }

  Widget _buildSession(SessionInfo session) {
    final colors = Theme.of(context).colorScheme;
    final selected = session.path == _selected?.path;
    final project = session.projectDir
        .split('/')
        .lastWhere((part) => part.isNotEmpty, orElse: () => session.projectDir);
    return Ink(
      color: selected ? colors.secondaryContainer : null,
      child: InkWell(
        onTap: () => setState(() => _selected = session),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? colors.onSecondaryContainer : null,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Flexible(
                    child: Tooltip(
                      message: shortenHome(session.projectDir),
                      child: _Chip(
                        project,
                        icon: Icons.folder_outlined,
                        color: _projectColor(session.projectDir),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _relativeTime(session.lastActivity),
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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

class ConversationView extends StatefulWidget {
  const ConversationView({super.key, required this.session});

  final SessionInfo session;

  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  Conversation? _conversation;
  Object? _error;

  bool _showTools = false;

  /// False from when a conversation loads until the view has scrolled to
  /// its end.
  bool _atLatest = false;
  bool _searching = false;
  String _query = '';

  /// The entries that pass the Tools toggle and the search, recomputed only
  /// when one of those changes.
  List<Entry> _visible = const [];

  /// Which collapsible entries are open. Kept here so that it survives the
  /// list recycling rows as they scroll out of view.
  final _expanded = <Entry>{};

  final _scroll = ScrollController();
  final _searchField = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchField.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _conversation = null;
      _error = null;
      _expanded.clear();
    });
    try {
      final conversation = await loadConversation(widget.session.path);
      if (!mounted) return;
      setState(() {
        _conversation = conversation;
        _updateVisible();
        _atLatest = false;
      });
      // Open on the latest messages. The list stays hidden until it has
      // settled there, so it does not flash its first messages.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _scrollToBottom();
        if (mounted) setState(() => _atLatest = true);
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _updateVisible() {
    final entries = _conversation?.entries ?? const <Entry>[];
    bool matches(Entry e) =>
        e.text.toLowerCase().contains(_query) ||
        (e.toolName?.toLowerCase().contains(_query) ?? false) ||
        (e.toolInput?.toLowerCase().contains(_query) ?? false) ||
        (e.toolResult?.toLowerCase().contains(_query) ?? false);
    _visible = [
      for (final e in entries)
        if ((_showTools || e.kind != EntryKind.tool) &&
            (_query.isEmpty || matches(e)))
          e,
    ];
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
      _updateVisible();
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
    return CallbackShortcuts(
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
            _buildHeader(),
            if (_searching) _buildSearchBar(),
            Divider(height: 1, color: colors.outlineVariant),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final session = widget.session;
    final conversation = _conversation;
    final id = session.id.length > 8
        ? '${session.id.substring(0, 8)}…'
        : session.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Chip(
                      shortenHome(session.projectDir),
                      icon: Icons.folder_outlined,
                      color: _projectColor(session.projectDir),
                    ),
                    if (conversation?.gitBranch != null)
                      _Chip(conversation!.gitBranch!, icon: Icons.fork_right),
                    if (conversation?.model != null)
                      _Chip(conversation!.model!, icon: Icons.memory),
                    Tooltip(
                      message: session.id,
                      child: _Chip(id, icon: Icons.tag),
                    ),
                    _Chip(
                      _dateTime(
                        conversation?.lastActivity ?? session.lastActivity,
                      ),
                      icon: Icons.schedule,
                    ),
                    if (conversation != null && conversation.totalTokens > 0)
                      _Chip(
                        '${_tokens(conversation.totalTokens)} tokens',
                        icon: Icons.data_usage,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _ToggleButton(
            label: 'Tools',
            icon: Icons.build_outlined,
            tooltip: _showTools ? 'Hide tool calls' : 'Show tool calls',
            active: _showTools,
            onPressed: () => setState(() {
              _showTools = !_showTools;
              _updateVisible();
            }),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Search this conversation (Ctrl+F)',
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
          IconButton(
            tooltip: 'Reload conversation',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _load,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 10, 10),
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
                _updateVisible();
              }),
            ),
          ),
          const SizedBox(width: 12),
          if (_query.isNotEmpty)
            Text(
              '${_visible.length} matching',
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
    if (_error != null) return _Message('Could not read session:\n$_error');
    final conversation = _conversation;
    if (conversation == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (conversation.entries.isEmpty) {
      return const _Message('This session has no messages');
    }
    if (_visible.isEmpty) {
      return _Message(
        _query.isEmpty
            ? 'Only tool calls here. Turn on Tools to see them.'
            : 'No messages contain “$_query”',
      );
    }
    return Opacity(
      opacity: _atLatest ? 1 : 0,
      child: SelectionArea(
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          itemCount: _visible.length,
          itemBuilder: (context, i) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildEntry(_visible[i]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggle(Entry entry) => setState(() {
    if (!_expanded.remove(entry)) _expanded.add(entry);
  });

  Widget _buildEntry(Entry entry) {
    final colors = Theme.of(context).colorScheme;
    final open = _expanded.contains(entry);
    switch (entry.kind) {
      case EntryKind.user:
        return _MessageCard(
          accent: colors.primary,
          background: Color.alphaBlend(
            colors.primary.withValues(alpha: 0.07),
            colors.surface,
          ),
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
          chips: [
            if (entry.model != null) _Chip(entry.model!),
            if (entry.inputTokens + entry.outputTokens > 0)
              _Chip(
                '${_tokens(entry.inputTokens)} in · '
                '${_tokens(entry.outputTokens)} out',
              ),
          ],
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
    this.chips = const [],
  });

  final Color accent;
  final Color background;
  final IconData icon;
  final String author;
  final DateTime? time;
  final List<Widget> chips;
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
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
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
                    ],
                  ),
                  ...chips,
                  if (time != null)
                    Text(
                      _clock(time!),
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

String _clock(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

String _dateTime(DateTime t) => '${_date(t)} ${_clock(t)}';

/// A token count the way the header and message chips show it: 140, 58.7k,
/// 1.2M.
String _tokens(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '${(n / 1000000).toStringAsFixed(1)}M';
}

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return '${_date(t)} ${_two(t.hour)}:${_two(t.minute)}';
}
