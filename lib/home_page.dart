import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'annotation_layer.dart';
import 'annotations.dart';
import 'entry_widgets.dart';
import 'launch.dart';
import 'notes.dart';
import 'notes_sidebar.dart';
import 'paths.dart';
import 'project_picker.dart';
import 'session_bar.dart';
import 'session_controller.dart';
import 'sessions.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.options});

  final LaunchOptions options;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final SessionController _controller;

  /// False from when the exchanges load until the view has scrolled to its
  /// end.
  bool _atLatest = false;
  bool _searching = false;

  final _annotations = Annotations();

  late final _notes = Notes(widget.options.notes ?? defaultNotesPath());
  bool _showNotes = true;
  final _noteFocus = FocusNode();

  final _scroll = ScrollController();
  final _searchField = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final options = widget.options;
    _controller = SessionController(
      onlySession: options.session,
      startProject: options.project,
      showTools: options.showTools,
      onLoaded: _loaded,
      onProblem: options.fail,
    )..addListener(_changed);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _searchField.dispose();
    _searchFocus.dispose();
    _annotations.dispose();
    _notes.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  /// Called before the page is built with what was loaded, so the view is
  /// still where it was.
  void _loaded(Loaded kind) {
    final options = widget.options;
    final first = kind == Loaded.first;
    // A view that is at its end stays there as messages arrive; one that
    // has been scrolled back is left where it is. A session opens at its
    // end.
    final follow = switch (kind) {
      Loaded.first => !options.openAtTop,
      Loaded.switched => true,
      Loaded.updated =>
        _scroll.hasClients &&
            _scroll.position.pixels >= _scroll.position.maxScrollExtent,
    };
    if (kind == Loaded.switched) setState(() => _atLatest = false);
    // On the first load, and when another session is opened, the list
    // stays hidden until it has settled at its end, so it does not flash
    // its first messages.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (follow) await _scrollToBottom();
      if (kind == Loaded.updated) return;
      if (mounted) setState(() => _atLatest = true);
      if (first) options.settled();
    });
  }

  void _openSearch() {
    setState(() => _searching = true);
    _searchFocus.requestFocus();
  }

  void _closeSearch() {
    _searchField.clear();
    _controller.query = '';
    setState(() => _searching = false);
  }

  /// Opens the notes sidebar, if it is closed, and puts the keyboard in the
  /// box that a note is added in.
  void _addNote() {
    setState(() => _showNotes = true);
    _noteFocus.requestFocus();
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
    final project = _controller.project;
    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _openSearch,
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _addNote,
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
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildBody()),
                    if (_showNotes)
                      NotesSidebar(
                        notes: _notes,
                        // Notes made when there are no sessions belong to no
                        // project.
                        project: project ?? '',
                        addFocus: _noteFocus,
                        projectLabel: _controller.projects.isEmpty
                            ? null
                            : ProjectPicker(
                                projects: _controller.projects,
                                current: project ?? '',
                                notes: _notes,
                                onSelected: _controller.selectProject,
                              ),
                      ),
                  ],
                ),
              ),
              if (_controller.sessions.isNotEmpty) ...[
                Divider(height: 1, color: colors.outlineVariant),
                Material(
                  color: colors.surfaceContainerLow,
                  child: SessionBar(
                    sessions: _controller.sessions,
                    current: _controller.session,
                    onSelected: _controller.selectSession,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final colors = Theme.of(context).colorScheme;
    final exchanges = _controller.exchanges;
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
            tooltip: _controller.showTools
                ? 'Tool calls are shown. Click to hide them.'
                : 'Tool calls are hidden. Click to show them.',
            active: _controller.showTools,
            onPressed: () => _controller.showTools = !_controller.showTools,
          ),
          const Spacer(),
          ListenableBuilder(
            listenable: _annotations,
            builder: (context, _) {
              final count = _annotations.count;
              if (count == 0) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Discard all annotations',
                icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                onPressed: _annotations.clear,
              );
            },
          ),
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
          ListenableBuilder(
            listenable: _notes,
            builder: (context, _) {
              final count = _notes.openCount(_controller.project ?? '');
              return IconButton(
                tooltip: _showNotes
                    ? 'Hide the notes'
                    : 'Show the notes (Ctrl+N adds one)',
                // The number of notes to do, while they are out of sight.
                icon: Badge(
                  isLabelVisible: !_showNotes && count > 0,
                  label: Text('$count'),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  textColor: Theme.of(context).colorScheme.onPrimary,
                  child: const Icon(Icons.checklist, size: 20),
                ),
                isSelected: _showNotes,
                onPressed: () => setState(() => _showNotes = !_showNotes),
              );
            },
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
              onChanged: (value) => _controller.query = value,
            ),
          ),
          const SizedBox(width: 12),
          if (_controller.query.isNotEmpty)
            Text(
              '${_controller.entryCount} matching',
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
    final error = _controller.error;
    if (error != null) return _Message('Could not read sessions:\n$error');
    final exchanges = _controller.exchanges;
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
    final rows = _controller.rows;
    if (rows.isEmpty) {
      return _Message('No messages contain “${_controller.query}”');
    }
    return Opacity(
      opacity: _atLatest ? 1 : 0,
      child: AnnotationLayer(
        board: _annotations,
        scroll: _scroll,
        child: SelectionArea(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              final heading = row is Exchange;
              final last = i + 1 == rows.length || rows[i + 1] is Exchange;
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
                    ? ExchangeHeading(row)
                    : _buildEntry(row as Entry),
              );
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    children: [
                      if (heading && i > 0) const SizedBox(height: 22),
                      panel,
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEntry(Entry entry) {
    return EntryView(
      entry: entry,
      name: _controller.nameOf(entry),
      open: _controller.isOpen(entry),
      onToggle: () => _controller.toggle(entry),
      annotations: _annotations,
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
