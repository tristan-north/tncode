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
      title: 'tncode',
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
  late Future<List<ProjectGroup>> _projects = loadProjects();
  SessionInfo? _selected;
  String _filter = '';

  void _refresh() => setState(() => _projects = loadProjects());

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 360,
            child: ColoredBox(
              color: colors.surfaceContainerLow,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              hintText: 'Filter sessions',
                              prefixIcon: Icon(Icons.search, size: 20),
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) =>
                                setState(() => _filter = v.toLowerCase()),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Reload sessions',
                          icon: const Icon(Icons.refresh),
                          onPressed: _refresh,
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _buildSessionList()),
                ],
              ),
            ),
          ),
          VerticalDivider(width: 1, color: colors.outlineVariant),
          Expanded(
            child: _selected == null
                ? Center(
                    child: Text(
                      'Select a session',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  )
                : ConversationView(
                    key: ValueKey(_selected!.path),
                    session: _selected!,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionList() {
    return FutureBuilder(
      future: _projects,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _Message('Could not read sessions:\n${snapshot.error}');
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final projects = snapshot.data!;
        if (projects.isEmpty) {
          return _Message('No sessions found in\n${claudeProjectsDir()}');
        }
        final tiles = <Widget>[];
        for (final project in projects) {
          final projectMatches = project.dir.toLowerCase().contains(_filter);
          final sessions = projectMatches
              ? project.sessions
              : project.sessions
                    .where((s) => s.title.toLowerCase().contains(_filter))
                    .toList();
          if (sessions.isNotEmpty) tiles.add(_buildProject(project, sessions));
        }
        if (tiles.isEmpty) return const _Message('No matching sessions');
        return ListView(children: tiles);
      },
    );
  }

  Widget _buildProject(ProjectGroup project, List<SessionInfo> sessions) {
    final colors = Theme.of(context).colorScheme;
    final dir = _shortenHome(project.dir);
    final slash = dir.lastIndexOf('/');
    final name = slash >= 0 && slash < dir.length - 1
        ? dir.substring(slash + 1)
        : dir;
    return ExpansionTile(
      // Rebuilding with a filter-specific key opens every group that has a
      // match while a filter is typed.
      key: PageStorageKey('${project.dir}|${_filter.isEmpty}'),
      initiallyExpanded:
          _filter.isNotEmpty || project.sessions.contains(_selected),
      shape: const Border(),
      dense: true,
      leading: const Icon(Icons.folder_outlined, size: 20),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '$dir  ·  ${sessions.length}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
      ),
      children: [
        for (final session in sessions)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 32, right: 12),
            selected: session.path == _selected?.path,
            selectedTileColor: colors.secondaryContainer,
            selectedColor: colors.onSecondaryContainer,
            title: Text(
              session.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _relativeTime(session.modified),
              style: const TextStyle(fontSize: 11),
            ),
            onTap: () => setState(() => _selected = session),
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

class ConversationView extends StatefulWidget {
  const ConversationView({super.key, required this.session});

  final SessionInfo session;

  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  late final Future<List<Entry>> _entries = loadConversation(
    widget.session.path,
  );

  /// Which collapsible entries are open, by index, so that the state survives
  /// the list recycling rows as they scroll out of view.
  final _expanded = <int>{};

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final session = widget.session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              SelectableText(
                '${_shortenHome(session.cwd ?? '')}  ·  '
                '${_fullTime(session.modified)}  ·  ${session.id}',
                maxLines: 1,
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: colors.outlineVariant),
        Expanded(
          child: FutureBuilder(
            future: _entries,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _Message('Could not read session:\n${snapshot.error}');
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final entries = snapshot.data!;
              if (entries.isEmpty) {
                return const _Message('This session has no messages');
              }
              return SelectionArea(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, i) => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _buildEntry(entries[i], i),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _toggle(int index) => setState(() {
    if (!_expanded.remove(index)) _expanded.add(index);
  });

  Widget _buildEntry(Entry entry, int index) {
    final colors = Theme.of(context).colorScheme;
    final open = _expanded.contains(index);
    switch (entry.kind) {
      case EntryKind.user:
        return _UserBubble(entry: entry);
      case EntryKind.assistant:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
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
          onTap: () => _toggle(index),
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
          onTap: multiline ? () => _toggle(index) : null,
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
          onTap: () => _toggle(index),
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

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.time != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'You  ·  ${_fullTime(entry.time!)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSecondaryContainer.withValues(alpha: 0.7),
                  ),
                ),
              ),
            if (entry.text.isNotEmpty)
              Text(
                entry.text,
                style: TextStyle(color: colors.onSecondaryContainer),
              ),
            for (final image in entry.images)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: Image.memory(
                      image,
                      // Decode near display size; pasted screenshots are large.
                      cacheHeight: 720,
                      errorBuilder: (_, _, _) => const Text('[image]'),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
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

String _shortenHome(String path) {
  final home = claudeProjectsDir().split('/.claude').first;
  return path.startsWith(home) ? '~${path.substring(home.length)}' : path;
}

String _two(int n) => n.toString().padLeft(2, '0');

String _fullTime(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';

String _relativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return _fullTime(t);
}
