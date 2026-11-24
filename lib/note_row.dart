import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'notes.dart';

/// What Shift+Enter does in a box where Enter alone ends the typing: breaks
/// the line where the cursor is, in place of any text that is selected.
Map<ShortcutActivator, VoidCallback> lineBreakBinding(
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

/// The colour of the outline that a note has for a moment when it has been
/// saved.
const _savedColor = Color(0xFF6FCF8E);

class NoteRow extends StatefulWidget {
  const NoteRow({
    super.key,
    required this.note,
    required this.index,
    required this.editing,
    required this.dragged,
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

  /// The note that is being dragged, if one is. While it is, it alone is
  /// drawn as the pointer's, whichever notes the pointer passes over.
  final ValueNotifier<Note?> dragged;

  /// When the note was saved to the file, if the last change was to it.
  final DateTime? saved;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  /// Called with the new text when the editing ends, or with null when it
  /// was given up.
  final ValueChanged<String?> onEdited;
  final VoidCallback onDelete;

  @override
  State<NoteRow> createState() => _NoteRowState();
}

class _NoteRowState extends State<NoteRow> with SingleTickerProviderStateMixin {
  bool _hovered = false;

  static final _radius = BorderRadius.circular(6);

  final _text = GlobalKey();

  /// Where in the text the click that began the editing was, which is where
  /// the cursor is put. The text is laid out the same in the box that it is
  /// changed in.
  int? _cursor;

  void _edit(TapUpDetails details) {
    final paragraph = _text.currentContext?.findRenderObject();
    _cursor = paragraph is RenderParagraph
        ? paragraph
              .getPositionForOffset(
                paragraph.globalToLocal(details.globalPosition),
              )
              .offset
        : null;
    widget.onEdit();
  }

  /// Runs from 0 to 1 as the outline of a note that has been saved fades.
  late final _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    widget.dragged.addListener(_dragChanged);
    // A row is also made when the done notes are unfolded, which may be long
    // after its note was saved.
    final saved = widget.saved;
    if (saved != null &&
        DateTime.now().difference(saved) < const Duration(milliseconds: 300)) {
      _flash.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(NoteRow old) {
    super.didUpdateWidget(old);
    if (!identical(old.dragged, widget.dragged)) {
      old.dragged.removeListener(_dragChanged);
      widget.dragged.addListener(_dragChanged);
    }
    if (widget.saved != null && widget.saved != old.saved) {
      _flash.forward(from: 0);
    }
  }

  void _dragChanged() => setState(() {});

  @override
  void dispose() {
    widget.dragged.removeListener(_dragChanged);
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final note = widget.note;
    final done = note.done != null;
    final index = widget.index;
    final dragged = widget.dragged.value;
    final lit =
        !widget.editing &&
        (dragged == null ? _hovered : identical(dragged, note));
    // The whole style, with what the text around it gives, since the box
    // that the text is changed in would fill in the rest of a partial style
    // from another one, with other letter spacing.
    final textStyle = DefaultTextStyle.of(context).style
        .merge(const TextStyle(fontSize: 13, height: 1.4));

    final row = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: lit ? colors.surfaceContainerHigh : colors.surfaceBright,
          borderRadius: _radius,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
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
                        cursor: _cursor,
                        style: textStyle,
                        onDone: widget.onEdited,
                      )
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: done ? null : _edit,
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
                              key: _text,
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
                visible: lit,
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
          borderRadius: _radius,
        ),
        child: child,
      ),
    );
    // Each note is a box of its own, as wide as the box that one is added
    // in, with a gap to the next.
    final box = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: outlined,
    );
    if (index == null) return box;
    // A note to do is dragged to another place by any part of it. While its
    // text is being changed, a drag selects text instead.
    return ReorderableDragStartListener(
      index: index,
      enabled: !widget.editing,
      child: box,
    );
  }
}

/// The box a note's text is changed in. Enter, or a click elsewhere, keeps
/// the change, Escape gives it up and Shift+Enter breaks the line.
class _NoteEditor extends StatefulWidget {
  const _NoteEditor({
    required this.text,
    required this.cursor,
    required this.style,
    required this.onDone,
  });

  static const _cursorWidth = 2.0;

  /// The width at the end of each line that the box keeps free for its
  /// cursor: Flutter adds a gap of 1 to the cursor's width.
  static const cursorRoom = _cursorWidth + 1;

  final String text;

  /// Where in the text the cursor starts. Null for its end.
  final int? cursor;
  final TextStyle style;
  final ValueChanged<String?> onDone;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final _field = TextEditingController.fromValue(
    TextEditingValue(
      text: widget.text,
      selection: TextSelection.collapsed(
        offset: (widget.cursor ?? widget.text.length).clamp(
          0,
          widget.text.length,
        ),
      ),
    ),
  );
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
        ...lineBreakBinding(_field),
      },
      child: TextField(
        controller: _field,
        focusNode: _focus,
        style: widget.style,
        cursorWidth: _NoteEditor._cursorWidth,
        minLines: 1,
        // As tall as its text, as the note is when it is not being changed.
        maxLines: null,
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
