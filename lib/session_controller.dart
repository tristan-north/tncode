import 'dart:async';

import 'package:flutter/foundation.dart';

import 'paths.dart';
import 'sessions.dart';

/// How many prompts, with their replies, the page shows.
const _exchangeCount = 10;

/// How many sessions the session bar offers.
const _sessionCount = 8;

/// What a load put on the page.
enum Loaded {
  /// The first exchanges since the app started.
  first,

  /// The exchanges of another session than the one that was shown.
  switched,

  /// Changed exchanges of the session that was shown.
  updated,
}

/// Which session is open and what of it the page shows. It reads the
/// sessions when it is made and again whenever a transcript changes.
class SessionController extends ChangeNotifier {
  /// Reads the transcripts under [root], which is [claudeProjectsDir] unless
  /// another directory is given.
  SessionController({
    String? root,
    this.onlySession,
    this.startProject,
    this._showTools = false,
    this.onLoaded,
    this.onProblem,
  }) : _store = SessionStore(root: root) {
    _watcher = SessionWatcher(_scheduleLoad, root: root);
    _load();
  }

  /// The one session to offer: `latest`, or the start of its id. Null to
  /// offer them all.
  final String? onlySession;

  /// The name of the project whose latest session to open at. Null for the
  /// session with the latest message.
  final String? startProject;

  /// Called when a load has changed [exchanges], after the listeners and
  /// before the page is built again.
  final void Function(Loaded)? onLoaded;

  /// Called with the reason when what was asked for cannot be shown.
  final void Function(String)? onProblem;

  final SessionStore _store;
  late final SessionWatcher _watcher;
  Timer? _loadTimer;
  bool _loading = false;
  bool _disposed = false;

  /// Whether a transcript changed while a load was under way.
  bool _stale = false;

  /// The latest exchanges of the session that is shown. Null until the first
  /// load is done.
  List<Exchange>? get exchanges => _exchanges;
  List<Exchange>? _exchanges;

  /// Why the sessions could not be read, if they could not.
  Object? get error => _error;
  Object? _error;

  /// The sessions on the session bar: those with the latest messages, the
  /// latest first.
  List<SessionInfo> get sessions => _sessions;
  List<SessionInfo> _sessions = const [];

  /// The path of the session that was asked for. The one whose prompts are
  /// shown is another until the load that follows [selectSession] is done.
  String? get session => _session;
  String? _session;
  String? _shownSession;

  /// Every project, by directory, the one with the latest message first.
  List<String> get projects => _projects;
  List<String> _projects = const [];

  /// The directory of the project that the session asked for belongs to.
  /// That session is not on the bar yet when it has just been picked by its
  /// project.
  String? get project =>
      _store.sessions.where((s) => s.path == _session).firstOrNull?.projectDir;

  /// Whether tool calls are among the [rows].
  bool get showTools => _showTools;
  bool _showTools;
  set showTools(bool value) {
    if (value == _showTools) return;
    _showTools = value;
    _updateRows();
    notifyListeners();
  }

  /// What the entries shown must contain, in lower case. Empty to show them
  /// all.
  String get query => _query;
  String _query = '';
  set query(String value) {
    value = value.trim().toLowerCase();
    if (value == _query) return;
    _query = value;
    _updateRows();
    notifyListeners();
  }

  /// What the list shows: each [Exchange] that has entries passing
  /// [showTools] and [query], as its heading, followed by those entries.
  List<Object> get rows => _rows;
  List<Object> _rows = const [];

  /// How many of the [rows] are entries.
  int get entryCount => _entryCount;
  int _entryCount = 0;

  /// Which collapsible entries are open, each named by its session's path and
  /// its position in the session: a reload makes new entries for a session
  /// that has changed, and those names carry over to them.
  final _expanded = <EntryName>{};
  var _names = Map<Entry, EntryName>.identity();

  /// The name of [entry], which must be one of the [exchanges].
  EntryName nameOf(Entry entry) => _names[entry]!;

  bool isOpen(Entry entry) => _expanded.contains(_names[entry]);

  /// Opens a collapsible entry, or closes it if it is open.
  void toggle(Entry entry) {
    final name = nameOf(entry);
    if (!_expanded.remove(name)) _expanded.add(name);
    notifyListeners();
  }

  void selectSession(SessionInfo session) {
    if (session.path == _session) return;
    _session = session.path;
    notifyListeners();
    _load();
  }

  /// Opens the latest session of [project].
  void selectProject(String project) {
    if (project == this.project) return;
    final latest = _store.sessions
        .where((s) => s.projectDir == project)
        .firstOrNull;
    if (latest != null) selectSession(latest);
  }

  @override
  void dispose() {
    _disposed = true;
    _watcher.dispose();
    _loadTimer?.cancel();
    super.dispose();
  }

  /// A transcript is written to many times a second while Claude is at
  /// work, so a change is acted on half a second later, together with all
  /// that follow it in that time.
  void _scheduleLoad() {
    if (_disposed) return;
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
    try {
      final changed = await _store.refresh();
      if (_disposed) return;
      final first = _exchanges == null;
      if (!changed && !first && _session == _shownSession) return;
      var sessions = _store.sessions;
      // A session named on the command line is shown alone.
      final wanted = onlySession;
      if (wanted != null) {
        sessions = wanted == 'latest'
            ? sessions.take(1).toList()
            : sessions.where((s) => s.id.startsWith(wanted)).toList();
        if (sessions.isEmpty) onProblem?.call('no session matches "$wanted"');
      }

      // A project named on the command line opens at its latest session.
      var path = _session;
      final named = startProject;
      if (first && named != null) {
        path = sessions
            .where((s) => projectName(s.projectDir) == named)
            .firstOrNull
            ?.path;
        if (path == null) onProblem?.call('no project matches "$named"');
      }
      // The session stays the one that was picked, whichever has the latest
      // message, and stays on the bar when eight others have later ones.
      final session =
          sessions.where((s) => s.path == path).firstOrNull ??
          sessions.firstOrNull;
      final shown = sessions.take(_sessionCount).toList();
      if (session != null && !shown.contains(session)) shown.last = session;
      final switched = !first && session?.path != _shownSession;

      final exchanges = session == null
          ? const <Exchange>[]
          : await _store.recentExchanges(session, _exchangeCount);
      if (_disposed) return;
      // Another session was picked meanwhile: the load that follows this
      // one shows it.
      if (!first && _session != _shownSession && _session != session?.path) {
        _stale = true;
        return;
      }

      // Most changes are to sessions that are not the one on the page.
      final before = _exchanges;
      var same =
          !switched && before != null && before.length == exchanges.length;
      for (var i = 0; same && i < exchanges.length; i++) {
        same = identical(before![i], exchanges[i]);
      }
      _exchanges = exchanges;
      _sessions = shown;
      // Sessions come latest first, and so do the projects made from them.
      _projects = {for (final s in sessions) s.projectDir}.toList();
      _session = _shownSession = session?.path;
      _error = null;
      if (!same) _updateRows();
      notifyListeners();
      if (same) return;
      onLoaded?.call(
        first
            ? Loaded.first
            : switched
            ? Loaded.switched
            : Loaded.updated,
      );
    } catch (error) {
      if (!_disposed) {
        _error = error;
        notifyListeners();
      }
      onProblem?.call('could not read sessions: $error');
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
    final names = Map<Entry, EntryName>.identity();
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
}
