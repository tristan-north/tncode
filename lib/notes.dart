import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/scheduler.dart' show timeDilation;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'markdown.dart';
import 'sessions.dart';

/// One thing to do.
class Note {
  Note({required this.text, required this.created, this.done});

  String text;
  final DateTime created;

  /// When it was marked as done. Null while it is still to do.
  DateTime? done;
}

/// Where the notes are kept unless the command line names another file:
/// `tncode/notes.json` in the user's data directory, which is
/// `$XDG_DATA_HOME` or `~/.local/share`. Null when neither is known.
String? defaultNotesPath() {
  final home = homeDir();
  var data = Platform.environment['XDG_DATA_HOME'];
  if (data == null || data.isEmpty) {
    data = home == null ? null : '$home/.local/share';
  }
  return data == null ? null : '$data/tncode/notes.json';
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

/// What Shift+Enter does in a box where Enter alone ends the typing: breaks
/// the line where the cursor is, in place of any text that is selected.
Map<ShortcutActivator, VoidCallback> _lineBreakBinding(
  TextEditingController field,
) => {
  const SingleActivator(LogicalKeyboardKey.enter, shift: true): () {
    final value = field.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    field.value = TextEditingValue(
      text: value.text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
    );
  },
};

/// The sidebar that lists the notes of [project]: a box to add one, those
/// still to do, and at the bottom those that are done, folded away until
/// asked for.
class NotesSidebar extends StatefulWidget {
  const NotesSidebar({
    super.key,
    required this.notes,
    required this.project,
    required this.projectName,
    required this.projectColor,
    required this.addFocus,
  });

  static const width = 320.0;

  final Notes notes;

  /// The project's directory.
  final String project;
  final String projectName;
  final Color projectColor;

  /// The focus of the box that a note is added in.
  final FocusNode addFocus;

  @override
  State<NotesSidebar> createState() => _NotesSidebarState();
}

class _NotesSidebarState extends State<NotesSidebar> {
  final _addField = TextEditingController();
  bool _doneOpen = false;

  /// The note whose text is being changed.
  Note? _editing;

  @override
  void didUpdateWidget(NotesSidebar old) {
    super.didUpdateWidget(old);
    if (old.project != widget.project) _editing = null;
  }

  @override
  void dispose() {
    _addField.dispose();
    _hideGrabCursor();
    if (_dropTimer != null) {
      _dropTimer!.cancel();
      timeDilation = 1;
    }
    super.dispose();
  }

  /// While a note is dragged, a layer over the whole window that makes the
  /// pointer a closed hand, wherever it is taken. It lets everything else
  /// through.
  OverlayEntry? _grabCursor;

  void _showGrabCursor() {
    _hideGrabCursor();
    final entry = _grabCursor = OverlayEntry(
      builder: (context) => const MouseRegion(
        cursor: SystemMouseCursors.grabbing,
        opaque: false,
        hitTestBehavior: HitTestBehavior.translucent,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  void _hideGrabCursor() {
    _grabCursor?.remove();
    _grabCursor?.dispose();
    _grabCursor = null;
  }

  /// How many times quicker than Flutter's quarter of a second a note that
  /// is let go of moves to its place.
  static const _dropSpeed = 5;
  Timer? _dropTimer;

  /// Flutter's list gives no way to set how long that move takes, so for as
  /// long as it lasts every animation in the app is run faster.
  void _hurryDrop() {
    timeDilation = 1 / _dropSpeed;
    _dropTimer?.cancel();
    _dropTimer = Timer(
      const Duration(milliseconds: 250 ~/ _dropSpeed + 30),
      () {
        _dropTimer = null;
        timeDilation = 1;
      },
    );
  }

  void _add(String text) {
    widget.notes.add(widget.project, text);
    _addField.clear();
    widget.addFocus.requestFocus();
  }

  /// Deletes [notes], and offers for a few seconds to put them back.
  void _delete(Iterable<Note> notes) {
    final project = widget.project;
    final removed = widget.notes.remove(project, notes);
    if (removed.isEmpty) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            removed.length == 1
                ? 'Deleted 1 note'
                : 'Deleted ${removed.length} notes',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => widget.notes.putBack(project, removed),
          ),
          behavior: SnackBarBehavior.floating,
          width: 300,
          duration: const Duration(seconds: 5),
          // One with a button otherwise stays until it is dismissed.
          persist: false,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: NotesSidebar.width,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(left: BorderSide(color: colors.outlineVariant)),
      ),
      child: ListenableBuilder(
        listenable: widget.notes,
        builder: (context, _) {
          final notes = widget.notes;
          final todo = notes.open(widget.project);
          final done = notes.done(widget.project);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(todo.length),
              _buildAddField(),
              if (notes.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Text(
                    notes.error!,
                    style: TextStyle(fontSize: 12, color: colors.error),
                  ),
                ),
              Expanded(child: _buildTodo(todo, done.isNotEmpty)),
              if (done.isNotEmpty) ...[
                Divider(height: 1, color: colors.outlineVariant),
                _buildDoneHeader(done),
                if (_doneOpen)
                  // At most the lower part of the sidebar, so that the notes
                  // to do keep some room.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.35,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 8),
                      children: [for (final note in done) _buildRow(note)],
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(int count) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          Icon(Icons.checklist, size: 17, color: colors.primary),
          const SizedBox(width: 8),
          const Text(
            'Notes',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.projectName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoStyle.copyWith(
                fontSize: 12,
                color: widget.projectColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count to do',
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildAddField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: CallbackShortcuts(
        bindings: _lineBreakBinding(_addField),
        child: TextField(
          controller: _addField,
          focusNode: widget.addFocus,
          style: const TextStyle(fontSize: 13),
          // A long note wraps. Enter adds it, and Shift+Enter breaks the
          // line.
          minLines: 1,
          maxLines: 6,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'Add a note…',
            prefixIcon: Icon(Icons.add, size: 18),
            isDense: true,
            border: OutlineInputBorder(),
          ),
          // Given so that the box keeps the keyboard for the next note.
          onEditingComplete: () {},
          onSubmitted: _add,
        ),
      ),
    );
  }

  Widget _buildTodo(List<Note> todo, bool anyDone) {
    if (todo.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
        child: Text(
          anyDone ? 'Everything is done.' : 'Nothing to do yet.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      buildDefaultDragHandles: false,
      itemCount: todo.length,
      onReorderStart: (_) => _showGrabCursor(),
      onReorderEnd: (_) {
        _hideGrabCursor();
        _hurryDrop();
      },
      onReorderItem: (from, to) => widget.notes.move(widget.project, from, to),
      // The dragged note takes no part in what the pointer is over, so that
      // the pointer is the closed hand there too.
      proxyDecorator: (child, _, _) => IgnorePointer(
        child: Material(
          color: Theme.of(context).colorScheme.surfaceBright,
          elevation: 4,
          child: child,
        ),
      ),
      itemBuilder: (context, i) => _buildRow(todo[i], index: i),
    );
  }

  Widget _buildDoneHeader(List<Note> done) {
    final colors = Theme.of(context).colorScheme;
    final dim = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);
    return InkWell(
      onTap: () => setState(() => _doneOpen = !_doneOpen),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
        child: SizedBox(
          height: 36,
          child: Row(
            children: [
              Icon(
                _doneOpen ? Icons.expand_more : Icons.chevron_right,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'Done',
                style: dim.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(width: 8),
              Text('${done.length}', style: dim),
              const Spacer(),
              if (_doneOpen)
                TextButton(
                  onPressed: () => _delete(done),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.onSurfaceVariant,
                    textStyle: const TextStyle(fontSize: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Delete all'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The row of [note], which is at [index] among the notes to do, or is
  /// done when that is null.
  Widget _buildRow(Note note, {int? index}) {
    final notes = widget.notes;
    return _NoteRow(
      key: ObjectKey(note),
      note: note,
      index: index,
      editing: identical(note, _editing),
      saved: notes.saved.contains(note) ? notes.savedAt : null,
      onToggle: () => notes.setDone(widget.project, note, note.done == null),
      onEdit: () => setState(() => _editing = note),
      onEdited: (text) {
        if (text != null) notes.edit(note, text);
        if (identical(note, _editing)) setState(() => _editing = null);
      },
      onDelete: () => _delete([note]),
    );
  }
}

class _NoteRow extends StatefulWidget {
  const _NoteRow({
    super.key,
    required this.note,
    required this.index,
    required this.editing,
    required this.saved,
    required this.onToggle,
    required this.onEdit,
    required this.onEdited,
    required this.onDelete,
  });

  final Note note;

  /// Where the note is among those to do. Null for one that is done, which
  /// cannot be dragged to another place.
  final int? index;
  final bool editing;

  /// When the note was saved to the file, if the last change was to it.
  final DateTime? saved;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  /// Called with the new text when the editing ends, or with null when it
  /// was given up.
  final ValueChanged<String?> onEdited;
  final VoidCallback onDelete;

  @override
  State<_NoteRow> createState() => _NoteRowState();
}

/// The colour of the outline that a note has for a moment when it has been
/// saved.
const _savedColor = Color(0xFF6FCF8E);

class _NoteRowState extends State<_NoteRow>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;

  /// Runs from 0 to 1 as the outline of a note that has been saved fades.
  late final _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    // A row is also made when the done notes are unfolded, which may be long
    // after its note was saved.
    final saved = widget.saved;
    if (saved != null &&
        DateTime.now().difference(saved) < const Duration(milliseconds: 300)) {
      _flash.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(_NoteRow old) {
    super.didUpdateWidget(old);
    if (widget.saved != null && widget.saved != old.saved) {
      _flash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final note = widget.note;
    final done = note.done != null;
    final index = widget.index;
    // The whole style, with what the text around it gives, since the box
    // that the text is changed in would fill in the rest of a partial style
    // from another one, with other letter spacing.
    final textStyle = DefaultTextStyle.of(context).style
        .merge(const TextStyle(fontSize: 13, height: 1.4));

    final row = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ColoredBox(
        color: _hovered && !widget.editing
            ? colors.surfaceBright
            : const Color(0x00000000),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: done ? 'Not done after all' : 'Mark as done',
                child: InkResponse(
                  onTap: widget.onToggle,
                  radius: 14,
                  child: Icon(
                    done ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 18,
                    color: done ? colors.onSurfaceVariant : colors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: widget.editing
                    ? _NoteEditor(
                        text: note.text,
                        style: textStyle,
                        onDone: widget.onEdited,
                      )
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: done ? null : widget.onEdit,
                        child: MouseRegion(
                          cursor: done
                              ? MouseCursor.defer
                              : SystemMouseCursors.text,
                          // The box that the text is changed in keeps
                          // this much room for its cursor, so the text
                          // leaves it too and wraps at the same places.
                          child: Padding(
                            padding: const EdgeInsets.only(
                              right: _NoteEditor.cursorRoom,
                            ),
                            child: Text(
                              note.text,
                              style: done
                                  ? textStyle.copyWith(
                                      color: colors.onSurfaceVariant,
                                      decoration: TextDecoration.lineThrough,
                                      decorationColor: colors.onSurfaceVariant,
                                    )
                                  : textStyle,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 4),
              // The button keeps its room when it is not shown, so that the
              // text is not laid out again as the pointer passes.
              Visibility.maintain(
                visible: _hovered && !widget.editing,
                child: Tooltip(
                  message: 'Delete',
                  child: InkResponse(
                    onTap: widget.onDelete,
                    radius: 14,
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final outlined = AnimatedBuilder(
      animation: _flash,
      child: row,
      builder: (context, child) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(
            color: _savedColor.withValues(
              alpha: 0.7 * (1 - Curves.easeIn.transform(_flash.value)),
            ),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: child,
      ),
    );
    if (index == null) return outlined;
    // A note to do is dragged to another place by any part of it. While its
    // text is being changed, a drag selects text instead.
    return ReorderableDragStartListener(
      index: index,
      enabled: !widget.editing,
      child: outlined,
    );
  }
}

/// The box a note's text is changed in. Enter, or a click elsewhere, keeps
/// the change, Escape gives it up and Shift+Enter breaks the line.
class _NoteEditor extends StatefulWidget {
  const _NoteEditor({
    required this.text,
    required this.style,
    required this.onDone,
  });

  static const _cursorWidth = 2.0;

  /// The width at the end of each line that the box keeps free for its
  /// cursor: Flutter adds a gap of 1 to the cursor's width.
  static const cursorRoom = _cursorWidth + 1;

  final String text;
  final TextStyle style;
  final ValueChanged<String?> onDone;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final _field = TextEditingController(text: widget.text);
  final _focus = FocusNode();
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _end(_field.text);
    });
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _end(String? text) {
    if (_ended) return;
    _ended = true;
    widget.onDone(text);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _end(null),
        ..._lineBreakBinding(_field),
      },
      child: TextField(
        controller: _field,
        focusNode: _focus,
        style: widget.style,
        cursorWidth: _NoteEditor._cursorWidth,
        minLines: 1,
        maxLines: 12,
        textInputAction: TextInputAction.done,
        // No border and no padding, so that the text stays where it was.
        decoration: const InputDecoration.collapsed(hintText: null),
        onEditingComplete: () {},
        onSubmitted: _end,
        onTapOutside: (_) => _end(_field.text),
      ),
    );
  }
}
