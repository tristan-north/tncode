import 'dart:async';

import 'package:flutter/scheduler.dart' show timeDilation;
import 'package:material_ui/material_ui.dart';

import 'note_row.dart';
import 'notes.dart';
import 'paths.dart';
import 'theme.dart';

/// The sidebar that lists the notes of [project]: a box to add one, those
/// still to do, and at the bottom those that are done, folded away until
/// asked for.
class NotesSidebar extends StatefulWidget {
  const NotesSidebar({
    super.key,
    required this.notes,
    required this.project,
    required this.addFocus,
    this.projectLabel,
  });

  static const width = 320.0;

  final Notes notes;

  /// The project's directory.
  final String project;

  /// Shown at the top in place of the project's name, when given.
  final Widget? projectLabel;

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

  /// The note that is being dragged to another place.
  final _dragged = ValueNotifier<Note?>(null);

  @override
  void didUpdateWidget(NotesSidebar old) {
    super.didUpdateWidget(old);
    if (old.project != widget.project) _editing = null;
  }

  @override
  void dispose() {
    _addField.dispose();
    _dragged.dispose();
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
          // The icon and the count take the same width, so that the name
          // between them is in the middle of the sidebar.
          SizedBox(
            width: _headerSide,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Icon(Icons.checklist, size: 17, color: colors.primary),
            ),
          ),
          Expanded(
            child:
                widget.projectLabel ??
                Text(
                  projectName(widget.project),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: monoStyle.copyWith(
                    fontSize: 12,
                    color: projectColor(widget.project),
                  ),
                ),
          ),
          SizedBox(
            width: _headerSide,
            child: Text(
              '$count to do',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  static const _headerSide = 64.0;

  Widget _buildAddField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: CallbackShortcuts(
        bindings: lineBreakBinding(_addField),
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
      onReorderStart: (i) {
        _dragged.value = todo[i];
        _showGrabCursor();
      },
      onReorderEnd: (_) {
        _dragged.value = null;
        _hideGrabCursor();
        _hurryDrop();
      },
      onReorderItem: (from, to) => widget.notes.move(widget.project, from, to),
      // The dragged note takes no part in what the pointer is over, so that
      // the pointer is the closed hand there too.
      proxyDecorator: (child, _, _) => IgnorePointer(
        child: Material(type: MaterialType.transparency, child: child),
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
    return NoteRow(
      key: ObjectKey(note),
      note: note,
      index: index,
      editing: identical(note, _editing),
      dragged: _dragged,
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
