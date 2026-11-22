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
    required this.projectDir,
    required this.lastActivity,
  });

  final String id;
  final String path;
  final String title;

  /// The directory the session was started in, or the name of its folder
  /// under the projects directory when the transcript does not record one.
  final String projectDir;

  /// When the last message of the conversation was written.
  final DateTime lastActivity;
}

/// An image attached to a message, with its pixel size when the file format
/// is one we can read it from, so the view can reserve its space before the
/// image has been decoded.
class EntryImage {
  EntryImage(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int? width;
  final int? height;
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
  final List<EntryImage> images;
  final String? toolName;
  final String? toolInput;
  String? toolResult;
  bool toolError = false;
}

class Conversation {
  Conversation({
    required this.entries,
    this.gitBranch,
    this.model,
    this.lastActivity,
    this.totalTokens = 0,
  });

  final List<Entry> entries;
  final String? gitBranch;
  final String? model;
  final DateTime? lastActivity;

  /// Input plus output tokens, summed over every API response.
  final int totalTokens;
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

/// Every session of every project, most recently active first.
///
/// Every transcript is read in full, a few hundred megabytes of them, so
/// the files are shared out between several isolates.
Future<List<SessionInfo>> loadSessions() async {
  final root = claudeProjectsDir();
  if (root == null) return [];
  final batches = await Isolate.run(
    () => _sessionFileBatches(root, Platform.numberOfProcessors.clamp(1, 8)),
  );
  final scanned = await Future.wait([
    for (final batch in batches) Isolate.run(() => _scanSessions(batch)),
  ]);
  return scanned.expand((sessions) => sessions).toList()
    ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
}

/// A prompt and everything that followed it, up to the next prompt of its
/// session.
class Exchange {
  Exchange(this.session, this.index, this.prompt);

  final SessionInfo session;

  /// The position of the prompt among the entries of its session.
  final int index;
  final Entry prompt;
  final List<Entry> replies = [];

  DateTime get time => prompt.time ?? session.lastActivity;

  /// A slash command or shell escape that Claude said nothing to, such as
  /// `/clear`.
  bool get isBareCommand =>
      (prompt.text.startsWith('/') || prompt.text.startsWith('! ')) &&
      !replies.any((e) => e.kind == EntryKind.assistant);
}

/// The [count] most recent exchanges of [sessions], which must be ordered
/// most recently active first. The oldest exchange comes first.
Future<List<Exchange>> loadRecentExchanges(
  List<SessionInfo> sessions,
  int count,
) {
  return Isolate.run(() => _recentExchanges(sessions, count));
}

List<Exchange> _recentExchanges(List<SessionInfo> sessions, int count) {
  final recent = <Exchange>[];
  for (final session in sessions) {
    // No prompt of a session is later than the session's last message, so
    // once this session cannot displace anything, neither can a later one.
    if (recent.length >= count &&
        !recent[count - 1].time.isBefore(session.lastActivity)) {
      break;
    }
    try {
      recent.addAll(_exchanges(session));
    } on FileSystemException {
      continue; // Unreadable file: leave it out.
    }
    recent.sort((a, b) {
      final byTime = b.time.compareTo(a.time);
      return byTime != 0 ? byTime : b.index.compareTo(a.index);
    });
    if (recent.length > count) recent.length = count;
  }
  return recent.reversed.toList();
}

List<Exchange> _exchanges(SessionInfo session) {
  final exchanges = <Exchange>[];
  final entries = _parseConversation(session.path).entries;
  for (final (index, entry) in entries.indexed) {
    if (entry.kind == EntryKind.user) {
      exchanges.add(Exchange(session, index, entry));
    } else if (exchanges.isNotEmpty) {
      exchanges.last.replies.add(entry);
    }
  }
  return exchanges..removeWhere((e) => e.isBareCommand);
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

/// The paths of all transcripts under [root], dealt into at most [count]
/// batches of about the same total size.
List<List<String>> _sessionFileBatches(String root, int count) {
  final rootDir = Directory(root);
  if (!rootDir.existsSync()) return [];

  final sizes = <String, int>{};
  for (final dir in rootDir.listSync().whereType<Directory>()) {
    try {
      for (final file in dir.listSync().whereType<File>()) {
        if (file.path.endsWith('.jsonl')) sizes[file.path] = file.lengthSync();
      }
    } on FileSystemException {
      // Unreadable directory or file: leave it out.
    }
  }
  // Largest first, each to the batch that is smallest so far.
  final paths = sizes.keys.toList()
    ..sort((a, b) => sizes[b]!.compareTo(sizes[a]!));
  final batches = [for (var i = 0; i < count; i++) <String>[]];
  final totals = List.filled(count, 0);
  for (final path in paths) {
    var smallest = 0;
    for (var i = 1; i < count; i++) {
      if (totals[i] < totals[smallest]) smallest = i;
    }
    batches[smallest].add(path);
    totals[smallest] += sizes[path]!;
  }
  return [
    for (final batch in batches)
      if (batch.isNotEmpty) batch,
  ];
}

List<SessionInfo> _scanSessions(List<String> paths) {
  final sessions = <SessionInfo>[];
  for (final path in paths) {
    try {
      final info = _scanSession(File(path));
      if (info != null) sessions.add(info);
    } on FileSystemException {
      // Unreadable file: leave it out.
    }
  }
  return sessions;
}

// The session list needs little from each transcript, which is mostly tool
// output and logged API requests, so only the lines that can matter are
// decoded. They are found by searching the raw bytes for these keys. A match
// can be a key of a nested object rather than of the line itself, which costs
// a wasted decode and nothing else; it cannot lie inside a string, where the
// quotes would be escaped. A transcript written with spaces after its colons
// would not match at all.
const _userLine = 1, _assistantLine = 2, _titleLine = 4, _cwdLine = 8;
final _markers = {
  ascii.encode('"type":"user"'): _userLine,
  ascii.encode('"type":"assistant"'): _assistantLine,
  ascii.encode('"type":"ai-title"'): _titleLine,
  ascii.encode('"type":"custom-title"'): _titleLine,
  ascii.encode('"cwd":"'): _cwdLine,
};

/// One line of a transcript that holds at least one of the [_markers].
typedef _MarkedLine = ({int start, int end, int kinds});

List<_MarkedLine> _markedLines(Uint8List bytes) {
  const newline = 0x0A, quote = 0x22;
  final lines = <_MarkedLine>[];
  var start = 0, kinds = 0;
  for (var i = 0; i < bytes.length; i++) {
    final byte = bytes[i];
    if (byte == quote) {
      kinds |= _markerAt(bytes, i);
    } else if (byte == newline) {
      if (kinds != 0) lines.add((start: start, end: i, kinds: kinds));
      start = i + 1;
      kinds = 0;
    }
  }
  if (kinds != 0) lines.add((start: start, end: bytes.length, kinds: kinds));
  return lines;
}

/// The kind of the marker that starts at [at], or 0 when none does.
int _markerAt(Uint8List bytes, int at) {
  // Nearly every quote in a transcript fails this first test.
  if (at + 1 >= bytes.length) return 0;
  final next = bytes[at + 1];
  if (next != 0x74 /* t */ && next != 0x63 /* c */ ) return 0;
  marker:
  for (final MapEntry(key: marker, value: kind) in _markers.entries) {
    if (at + marker.length > bytes.length) continue;
    for (var i = 1; i < marker.length; i++) {
      if (bytes[at + i] != marker[i]) continue marker;
    }
    return kind;
  }
  return 0;
}

final _lineDecoder = const Utf8Decoder(allowMalformed: true)
    .fuse(const JsonDecoder());

Map<String, dynamic>? _decodeLine(Uint8List bytes, _MarkedLine line) {
  try {
    final value = _lineDecoder.convert(
      Uint8List.sublistView(bytes, line.start, line.end),
    );
    return value is Map<String, dynamic> ? value : null;
  } on FormatException {
    return null; // A partially written last line, for example.
  }
}

/// Whether a line is a message of the conversation itself, and so counts
/// towards when the session was last active.
bool _isOwnMessage(Map<String, dynamic> json) => switch (json['type']) {
  'assistant' => json['isSidechain'] != true,
  'user' => json['isMeta'] != true && json['isSidechain'] != true,
  _ => false,
};

/// Pulls the title and working directory out of a session file.
SessionInfo? _scanSession(File file) {
  final bytes = file.readAsBytesSync();
  final lines = _markedLines(bytes);

  String? cwd, aiTitle, customTitle, firstPrompt, firstCommand;
  var hasConversation = false;
  for (final line in lines) {
    // The title can be set anywhere and its last setting counts. The rest is
    // settled early in the file: the directory by the first line that names
    // one, the prompt by the first one typed.
    final wanted =
        _titleLine |
        (cwd == null ? _cwdLine : 0) |
        (firstPrompt == null ? _userLine : 0);
    if (line.kinds & wanted == 0) continue;
    final json = _decodeLine(bytes, line);
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
        if (!_isOwnMessage(json)) continue;
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

  // The last message is found from the end of the file.
  DateTime? lastActivity;
  for (final line in lines.reversed) {
    if (line.kinds & (_userLine | _assistantLine) == 0) continue;
    final json = _decodeLine(bytes, line);
    if (json == null || !_isOwnMessage(json)) continue;
    lastActivity = _time(json);
    if (lastActivity != null) break;
  }

  final name = file.uri.pathSegments.last;
  var title =
      customTitle ?? aiTitle ?? firstPrompt ?? firstCommand ?? '(no prompt)';
  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (title.length > 120) title = '${title.substring(0, 120)}…';
  return SessionInfo(
    id: name.substring(0, name.length - '.jsonl'.length),
    path: file.path,
    title: title,
    projectDir:
        cwd ?? file.parent.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
    // Not the file's modification time: Claude Code rewrites old transcripts
    // (on resume or upgrade, say) without anything having been said.
    lastActivity: lastActivity ?? file.lastModifiedSync(),
  );
}

// ---------------------------------------------------------------------------
// Conversation

const _maxResultChars = 20000;

Conversation _parseConversation(String path) {
  final entries = <Entry>[];
  final tools = <String, Entry>{};
  // One API response is stored as several lines, one per content block, each
  // repeating the response's usage; keyed by response id to count it once.
  final tokensByResponse = <String, int>{};
  String? gitBranch, model;
  DateTime? lastActivity;

  for (final line in _lines(path)) {
    final json = _decode(line);
    if (json == null) continue;
    if (json['isSidechain'] == true || json['isMeta'] == true) continue;
    final type = json['type'];
    if (type != 'user' && type != 'assistant') continue;

    if (json['gitBranch'] case final String branch when branch.isNotEmpty) {
      gitBranch = branch;
    }
    lastActivity = _time(json) ?? lastActivity;

    if (type == 'user') {
      _addUserMessage(json, entries, tools);
    } else {
      final usage = _addAssistantMessage(json, entries, tools);
      if (usage == null) continue;
      model = usage.model ?? model;
      tokensByResponse[usage.responseId] = usage.input + usage.output;
    }
  }
  return Conversation(
    entries: entries,
    gitBranch: gitBranch,
    model: model,
    lastActivity: lastActivity,
    totalTokens: tokensByResponse.values.fold(0, (sum, n) => sum + n),
  );
}

DateTime? _time(Map<String, dynamic> json) {
  final value = json['timestamp'];
  return value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

typedef _Usage = ({String responseId, String? model, int input, int output});

int _int(Object? value) => value is int ? value : 0;

/// Adds the entries of one assistant line and returns the usage of the API
/// response it belongs to, or null when the line records none.
_Usage? _addAssistantMessage(
  Map<String, dynamic> json,
  List<Entry> entries,
  Map<String, Entry> tools,
) {
  final message = json['message'];
  if (message is! Map) return null;
  final content = message['content'];
  if (content is! List) return null;
  final time = _time(json);

  // Claude Code writes its own notices (an API error, say) as assistant
  // messages with the model "<synthetic>"; those have no model or usage.
  final rawModel = message['model'];
  final model = rawModel is String && !rawModel.startsWith('<')
      ? rawModel
      : null;
  final usage = message['usage'];
  var input = 0, output = 0;
  if (model != null && usage is Map) {
    input =
        _int(usage['input_tokens']) +
        _int(usage['cache_read_input_tokens']) +
        _int(usage['cache_creation_input_tokens']);
    output = _int(usage['output_tokens']);
  }

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

  final id = message['id'];
  if (id is! String || model == null) return null;
  return (responseId: id, model: model, input: input, output: output);
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
  final images = <EntryImage>[];
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
Entry? _classifyUserText(String raw, DateTime? time, List<EntryImage> images) {
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

EntryImage? _decodeImage(Map block) {
  final source = block['source'];
  if (source is! Map || source['type'] != 'base64') return null;
  final data = source['data'];
  if (data is! String) return null;
  final Uint8List bytes;
  try {
    bytes = base64Decode(data);
  } on FormatException {
    return null;
  }
  final size = _imageSize(bytes);
  return EntryImage(bytes, size?.$1, size?.$2);
}

/// Reads the pixel size from a PNG, GIF or JPEG header.
(int, int)? _imageSize(Uint8List b) {
  final data = ByteData.sublistView(b);
  // PNG: signature, then the IHDR chunk holding width and height.
  if (b.length >= 24 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E) {
    return (data.getUint32(16), data.getUint32(20));
  }
  // GIF: "GIF", version, then little-endian width and height.
  if (b.length >= 10 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
    return (data.getUint16(6, Endian.little), data.getUint16(8, Endian.little));
  }
  // JPEG: walk the segments to the start-of-frame one.
  if (b.length >= 4 && b[0] == 0xFF && b[1] == 0xD8) {
    var i = 2;
    while (i + 9 < b.length && b[i] == 0xFF) {
      final marker = b[i + 1];
      final isFrame =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isFrame) return (data.getUint16(i + 7), data.getUint16(i + 5));
      i += 2 + data.getUint16(i + 2);
    }
  }
  return null;
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
