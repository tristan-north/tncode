import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Reads Claude Code session transcripts from `~/.claude/projects`.
///
/// Each subdirectory there is one project (named after its working directory
/// with slashes replaced by dashes) and holds one `<session-id>.jsonl` file per
/// session.

class SessionInfo {
  SessionInfo({
    required this.id,
    required this.path,
    required this.title,
    required this.cwd,
    required this.modified,
  });

  final String id;
  final String path;
  final String title;
  final String? cwd;
  final DateTime modified;
}

class ProjectGroup {
  ProjectGroup({required this.dir, required this.sessions});

  /// The project's working directory, or the encoded folder name when no
  /// session recorded one.
  final String dir;
  final List<SessionInfo> sessions;

  DateTime get modified => sessions.first.modified;
}

enum EntryKind { user, assistant, thinking, tool, output, note }

class Entry {
  Entry(
    this.kind,
    this.text, {
    this.time,
    this.images = const [],
    this.toolName,
    this.toolInput,
  });

  final EntryKind kind;

  /// The message text. For tools this is the one-line summary of the call.
  final String text;
  final DateTime? time;
  final List<Uint8List> images;
  final String? toolName;
  final String? toolInput;
  String? toolResult;
  bool toolError = false;
}

String? _env(String name) {
  final value = Platform.environment[name];
  return value == null || value.isEmpty ? null : value;
}

/// The user's home directory, without a trailing slash, or null when HOME is
/// not set.
String? homeDir() {
  final home = _env('HOME');
  if (home == null || home == '/') return home;
  return home.endsWith('/') ? home.substring(0, home.length - 1) : home;
}

/// Where Claude Code keeps its session transcripts, or null when neither
/// CLAUDE_CONFIG_DIR nor HOME says where to look.
String? claudeProjectsDir() {
  final home = homeDir();
  final config =
      _env('CLAUDE_CONFIG_DIR') ?? (home == null ? null : '$home/.claude');
  return config == null ? null : '$config/projects';
}

/// Replaces a leading home directory in [path] with `~`.
String shortenHome(String path) {
  final home = homeDir();
  if (home == null || home == '/') return path;
  if (path == home) return '~';
  return path.startsWith('$home/') ? '~${path.substring(home.length)}' : path;
}

Future<List<ProjectGroup>> loadProjects() {
  final root = claudeProjectsDir();
  if (root == null) return Future.value([]);
  return Isolate.run(() => _scanProjects(root));
}

Future<List<Entry>> loadConversation(String path) {
  return Isolate.run(() => _parseConversation(path));
}

Iterable<String> _lines(String path) {
  final bytes = File(path).readAsBytesSync();
  return const LineSplitter().convert(utf8.decode(bytes, allowMalformed: true));
}

Map<String, dynamic>? _decode(String line) {
  try {
    final value = jsonDecode(line);
    return value is Map<String, dynamic> ? value : null;
  } on FormatException {
    return null; // A partially written last line, for example.
  }
}

// ---------------------------------------------------------------------------
// Session list

List<ProjectGroup> _scanProjects(String root) {
  final rootDir = Directory(root);
  if (!rootDir.existsSync()) return [];

  // Keyed by working directory: Claude Code can file sessions from the same
  // directory under more than one folder, and they belong in one group.
  final byDir = <String, List<SessionInfo>>{};
  for (final dir in rootDir.listSync().whereType<Directory>()) {
    final sessions = <SessionInfo>[];
    for (final file in dir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.jsonl')) continue;
      try {
        final info = _scanSession(file);
        if (info != null) sessions.add(info);
      } on FileSystemException {
        // Unreadable file: leave it out.
      }
    }
    if (sessions.isEmpty) continue;
    final cwd = sessions.map((s) => s.cwd).nonNulls.firstOrNull;
    final key = cwd ?? dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    byDir.putIfAbsent(key, () => []).addAll(sessions);
  }

  final groups = <ProjectGroup>[];
  byDir.forEach((dir, sessions) {
    sessions.sort((a, b) => b.modified.compareTo(a.modified));
    groups.add(ProjectGroup(dir: dir, sessions: sessions));
  });
  groups.sort((a, b) => b.modified.compareTo(a.modified));
  return groups;
}

/// Pulls the title and working directory out of a session file.
SessionInfo? _scanSession(File file) {
  String? cwd, aiTitle, customTitle, firstPrompt, firstCommand;
  var hasConversation = false;

  for (final line in _lines(file.path)) {
    final json = _decode(line);
    if (json == null) continue;
    if (cwd == null && json['cwd'] is String) cwd = json['cwd'] as String;

    switch (json['type']) {
      case 'ai-title':
        if (json['aiTitle'] is String) aiTitle = json['aiTitle'] as String;
      case 'custom-title':
        if (json['customTitle'] is String) {
          customTitle = json['customTitle'] as String;
        }
      case 'user':
        if (json['isMeta'] == true || json['isSidechain'] == true) continue;
        hasConversation = true;
        if (firstPrompt != null) continue;
        final entries = <Entry>[];
        _addUserMessage(json, entries, {});
        final text = entries
            .where((e) => e.kind == EntryKind.user && e.text.isNotEmpty)
            .map((e) => e.text)
            .firstOrNull;
        // A typed prompt names the session better than a slash command such
        // as /clear, so keep looking past commands.
        if (text != null && text.startsWith('/')) {
          firstCommand ??= text;
        } else {
          firstPrompt = text;
        }
    }
  }
  if (!hasConversation) return null;

  final name = file.uri.pathSegments.last;
  var title =
      customTitle ?? aiTitle ?? firstPrompt ?? firstCommand ?? '(no prompt)';
  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (title.length > 120) title = '${title.substring(0, 120)}…';
  return SessionInfo(
    id: name.substring(0, name.length - '.jsonl'.length),
    path: file.path,
    title: title,
    cwd: cwd,
    modified: file.lastModifiedSync(),
  );
}

// ---------------------------------------------------------------------------
// Conversation

const _maxResultChars = 20000;

List<Entry> _parseConversation(String path) {
  final entries = <Entry>[];
  final tools = <String, Entry>{};

  for (final line in _lines(path)) {
    final json = _decode(line);
    if (json == null) continue;
    if (json['isSidechain'] == true || json['isMeta'] == true) continue;
    switch (json['type']) {
      case 'user':
        _addUserMessage(json, entries, tools);
      case 'assistant':
        _addAssistantMessage(json, entries, tools);
    }
  }
  return entries;
}

DateTime? _time(Map<String, dynamic> json) {
  final value = json['timestamp'];
  return value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

void _addAssistantMessage(
  Map<String, dynamic> json,
  List<Entry> entries,
  Map<String, Entry> tools,
) {
  final content = (json['message'] as Map?)?['content'];
  if (content is! List) return;
  final time = _time(json);

  for (final block in content.whereType<Map>()) {
    switch (block['type']) {
      case 'text':
        final text = (block['text'] as String? ?? '').trim();
        if (text.isNotEmpty) {
          entries.add(Entry(EntryKind.assistant, text, time: time));
        }
      case 'thinking':
        final text = (block['thinking'] as String? ?? '').trim();
        if (text.isNotEmpty) {
          entries.add(Entry(EntryKind.thinking, text, time: time));
        }
      case 'tool_use':
        final name = block['name'] as String? ?? 'tool';
        final input = block['input'];
        final entry = Entry(
          EntryKind.tool,
          _toolSummary(input),
          time: time,
          toolName: name,
          toolInput: _toolInputText(input),
        );
        entries.add(entry);
        final id = block['id'];
        if (id is String) tools[id] = entry;
    }
  }
}

void _addUserMessage(
  Map<String, dynamic> json,
  List<Entry> entries,
  Map<String, Entry> tools,
) {
  final content = (json['message'] as Map?)?['content'];
  final time = _time(json);
  final compacted = json['isCompactSummary'] == true;

  final texts = <String>[];
  final images = <Uint8List>[];
  if (content is String) {
    texts.add(content);
  } else if (content is List) {
    for (final block in content.whereType<Map>()) {
      switch (block['type']) {
        case 'text':
          texts.add(block['text'] as String? ?? '');
        case 'image':
          final image = _decodeImage(block);
          if (image != null) images.add(image);
        case 'tool_result':
          final tool = tools[block['tool_use_id']];
          if (tool != null) {
            tool.toolResult = _toolResultText(block['content']);
            tool.toolError = block['is_error'] == true;
          }
      }
    }
  }

  if (compacted) {
    entries.add(Entry(EntryKind.note, texts.join('\n\n').trim(), time: time));
    return;
  }

  var addedImages = false;
  for (final raw in texts) {
    final entry = _classifyUserText(raw, time, addedImages ? const [] : images);
    if (entry == null) continue;
    entries.add(entry);
    addedImages = true;
  }
  if (!addedImages && images.isNotEmpty) {
    entries.add(Entry(EntryKind.user, '', time: time, images: images));
  }
}

String? _tag(String text, String tag) {
  final match = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(text);
  return match?.group(1)?.trim();
}

final _ansi = RegExp(r'\x1B\[[0-9;?]*[A-Za-z]');
final _reminder = RegExp(
  r'<system-reminder>.*?</system-reminder>',
  dotAll: true,
);

/// Turns the raw text of a user turn into what the person actually saw or
/// typed: slash commands, shell escapes and their output are stored wrapped in
/// tags, and some turns are bookkeeping that never appeared on screen.
Entry? _classifyUserText(String raw, DateTime? time, List<Uint8List> images) {
  final text = raw.replaceAll(_reminder, '').trim();
  if (text.isEmpty || text.startsWith('<local-command-caveat>')) return null;

  final command = _tag(text, 'command-name');
  if (command != null) {
    final args = _tag(text, 'command-args') ?? '';
    return Entry(EntryKind.user, '$command $args'.trim(), time: time);
  }

  final bashInput = _tag(text, 'bash-input');
  if (bashInput != null) {
    return Entry(EntryKind.user, '! $bashInput', time: time);
  }

  if (text.startsWith('<local-command-stdout>') ||
      text.startsWith('<local-command-stderr>') ||
      text.startsWith('<bash-stdout>') ||
      text.startsWith('<bash-stderr>')) {
    final output = text
        .replaceAll(RegExp(r'</?(local-command|bash)-std(out|err)>'), '')
        .replaceAll(_ansi, '')
        .trim();
    return output.isEmpty ? null : Entry(EntryKind.output, output, time: time);
  }

  if (text.startsWith('<task-notification>')) {
    final summary = _tag(text, 'summary') ?? 'Background task finished';
    return Entry(EntryKind.note, summary, time: time);
  }

  return Entry(EntryKind.user, text, time: time, images: images);
}

Uint8List? _decodeImage(Map block) {
  final source = block['source'];
  if (source is! Map || source['type'] != 'base64') return null;
  final data = source['data'];
  if (data is! String) return null;
  try {
    return base64Decode(data);
  } on FormatException {
    return null;
  }
}

String _toolSummary(Object? input) {
  if (input is! Map) return '';
  for (final key in const [
    'command',
    'file_path',
    'pattern',
    'description',
    'query',
    'url',
    'skill',
    'prompt',
  ]) {
    final value = input[key];
    if (value is String && value.isNotEmpty) {
      return value.replaceAll(RegExp(r'\s+'), ' ');
    }
  }
  return input.values.whereType<String>().firstOrNull ?? '';
}

String _toolInputText(Object? input) {
  if (input is Map && input.length == 1 && input.values.first is String) {
    return input.values.first as String;
  }
  return const JsonEncoder.withIndent('  ').convert(input);
}

String _toolResultText(Object? content) {
  String text;
  if (content is String) {
    text = content;
  } else if (content is List) {
    text = content
        .whereType<Map>()
        .map(
          (b) => switch (b['type']) {
            'text' => b['text'] as String? ?? '',
            'image' => '[image]',
            _ => '',
          },
        )
        .join('\n');
  } else {
    text = '';
  }
  text = text.replaceAll(_ansi, '').trimRight();
  if (text.length > _maxResultChars) {
    final dropped = text.length - _maxResultChars;
    text =
        '${text.substring(0, _maxResultChars)}\n… ($dropped more characters)';
  }
  return text;
}
