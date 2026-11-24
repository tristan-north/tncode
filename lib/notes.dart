import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'paths.dart';

/// One thing to do.
class Note {
  Note({required this.text, required this.created, this.done});

  String text;
  final DateTime created;

  /// When it was marked as done. Null while it is still to do.
  DateTime? done;
}

/// The to-do notes of every project, which are read from the file at [path]
/// and written back to it on every change.
class Notes extends ChangeNotifier {
  Notes(this.path) {
    _read();
  }

  /// Null when there is nowhere to keep the notes, which then last only as
  /// long as the app runs.
  final String? path;

  /// Why the notes could not be read or written, to show to the user.
  String? error;

  /// The notes that the last change was to, if it was saved to the file, and
  /// when that was. The sidebar shows them as saved.
  Set<Note> saved = const {};
  DateTime? savedAt;

  /// A file that could not be understood is left as it is rather than
  /// written over.
  bool _unreadable = false;

  /// The notes of each project, by its directory: those to do, in the order
  /// they are shown in, followed by those that are done.
  final _projects = <String, List<Note>>{};

  /// The notes of [project] that are still to do, in the order the user has
  /// put them in.
  List<Note> open(String project) => [
    for (final note in _projects[project] ?? const <Note>[])
      if (note.done == null) note,
  ];

  /// The notes of [project] that are done, the latest done first.
  List<Note> done(String project) => [
    for (final note in _projects[project] ?? const <Note>[])
      if (note.done != null) note,
  ]..sort((a, b) => b.done!.compareTo(a.done!));

  int openCount(String project) => open(project).length;

  /// Puts a new note at the top of those to do.
  void add(String project, String text) {
    text = text.trim();
    if (text.isEmpty) return;
    _projects
        .putIfAbsent(project, () => [])
        .insert(0, Note(text: text, created: DateTime.now()));
    _changed([_projects[project]!.first]);
  }

  /// A note that is taken up again goes to the top of those to do.
  void setDone(String project, Note note, bool done) {
    final notes = _projects[project];
    if (notes == null || !notes.remove(note)) return;
    note.done = done ? DateTime.now() : null;
    if (done) {
      notes.add(note);
    } else {
      notes.insert(0, note);
    }
    _changed([note]);
  }

  void edit(Note note, String text) {
    text = text.trim();
    if (text.isEmpty || text == note.text) return;
    note.text = text;
    _changed([note]);
  }

  /// Moves the note at [from] among those to do so that it is at [to] among
  /// them.
  void move(String project, int from, int to) {
    final todo = open(project);
    if (from < 0 || from >= todo.length) return;
    final note = todo.removeAt(from);
    todo.insert(to.clamp(0, todo.length), note);
    _projects[project] = [...todo, ...done(project)];
    _changed([note]);
  }

  /// Deletes [notes] and returns what [putBack] needs to undo that.
  List<(int, Note)> remove(String project, Iterable<Note> notes) {
    final all = _projects[project];
    if (all == null) return const [];
    final gone = Set<Note>.identity()..addAll(notes);
    final removed = [
      for (final (i, note) in all.indexed)
        if (gone.contains(note)) (i, note),
    ];
    if (removed.isEmpty) return removed;
    all.removeWhere(gone.contains);
    _changed();
    return removed;
  }

  /// Puts notes that [remove] deleted back where they were.
  void putBack(String project, List<(int, Note)> removed) {
    if (removed.isEmpty) return;
    final all = _projects.putIfAbsent(project, () => []);
    for (final (i, note) in removed) {
      all.insert(i.clamp(0, all.length), note);
    }
    _changed([for (final (_, note) in removed) note]);
  }

  /// Saves a change, which was to [notes] unless it was their deletion.
  void _changed([List<Note> notes = const []]) {
    saved = const {};
    if (_write()) {
      saved = Set.identity()..addAll(notes);
      savedAt = DateTime.now();
    }
    notifyListeners();
  }

  void _read() {
    final path = this.path;
    if (path == null) return;
    final file = File(path);
    try {
      if (!file.existsSync()) return;
      final json = jsonDecode(file.readAsStringSync());
      final projects = (json as Map)['projects'] as Map;
      for (final MapEntry(:key, :value) in projects.entries) {
        _projects[key as String] = [
          for (final note in value as List)
            Note(
              text: note['text'] as String,
              created: DateTime.parse(note['created'] as String).toLocal(),
              done: note['done'] == null
                  ? null
                  : DateTime.parse(note['done'] as String).toLocal(),
            ),
        ];
      }
    } catch (e) {
      _projects.clear();
      _unreadable = true;
      error = 'Could not read ${shortenHome(path)}, so notes are not saved: $e';
    }
  }

  /// Whether the notes are now in the file.
  bool _write() {
    final path = this.path;
    if (path == null || _unreadable) return false;
    String stamp(DateTime time) => time.toUtc().toIso8601String();
    final json = {
      'version': 1,
      'projects': {
        for (final MapEntry(:key, :value) in _projects.entries)
          if (value.isNotEmpty)
            key: [
              for (final note in value)
                {
                  'text': note.text,
                  'created': stamp(note.created),
                  if (note.done != null) 'done': stamp(note.done!),
                },
            ],
      },
    };
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      // Written beside the file and moved over it, so that the file is
      // never left half written.
      final temporary = File('$path.tmp');
      temporary.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(json)}\n',
        flush: true,
      );
      temporary.renameSync(path);
      error = null;
      return true;
    } catch (e) {
      error = 'Could not save notes to ${shortenHome(path)}: $e';
      return false;
    }
  }
}
