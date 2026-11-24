import 'dart:io';

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

/// The name of a project's directory, without the directories it is in.
String projectName(String projectDir) => projectDir
    .split('/')
    .lastWhere((part) => part.isNotEmpty, orElse: () => projectDir);

/// Where the notes are kept unless the command line names another file:
/// `tncode/notes.json` in the user's data directory, which is
/// `$XDG_DATA_HOME` or `~/.local/share`. Null when neither is known.
String? defaultNotesPath() {
  final home = homeDir();
  final data =
      _env('XDG_DATA_HOME') ?? (home == null ? null : '$home/.local/share');
  return data == null ? null : '$data/tncode/notes.json';
}
