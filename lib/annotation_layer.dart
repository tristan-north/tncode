import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'annotation_highlights.dart';
import 'annotations.dart';

/// Wraps the page so that selecting text in a reply opens a box to comment
/// on it, and clicking a highlight opens the box on its annotation. With
/// Shift held, the word under the pointer lights up, and clicking one word
/// and then another of the same reply opens the box on those two and all
/// that is between them.
class AnnotationLayer extends StatefulWidget {
  const AnnotationLayer({
    super.key,
    required this.board,
    required this.scroll,
    required this.child,
  });

  final Annotations board;

  /// Scrolls the page. The box moves with the text it is about.
  final ScrollController scroll;
  final Widget child;

  @override
  State<AnnotationLayer> createState() => _AnnotationLayerState();
}

class _AnnotationLayerState extends State<AnnotationLayer> {
  /// The mounted replies beneath this layer.
  final _targets = <AnnotatableTarget>{};

  /// The annotation the box is open on.
  Annotation? _open;
  Offset _anchor = Offset.zero;
  double _scrollAtOpen = 0;
  final _field = TextEditingController();
  final _fieldFocus = FocusNode();

  /// Where the primary button went down, if it is what is down.
  Offset? _down;

  /// Whether words are being picked, which is while Shift is held, and
  /// whether they were when the button went down.
  bool _picking = false, _downPicking = false;

  /// The first word picked, until the second is, and the word that the
  /// pointer was last on since. The words are lit up to that one while the
  /// pointer is between words, so that the light does not flicker as it
  /// moves along a line.
  Mark? _first, _reached;

  /// Where the pointer is, if it is over the page, and whether there is a
  /// word to pick there.
  Offset? _pointer;
  bool _onWord = false;

  /// Whether the pointer has moved since Shift went down, and whether an
  /// annotation has been made since then.
  bool _movedInShift = false, _madeInShift = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_key);
    widget.board.addListener(_onBoardChanged);
  }

  @override
  void didUpdateWidget(AnnotationLayer old) {
    super.didUpdateWidget(old);
    if (!identical(old.board, widget.board)) {
      old.board.removeListener(_onBoardChanged);
      widget.board.addListener(_onBoardChanged);
    }
  }

  void _onBoardChanged() {
    if (_open != null && !identical(widget.board.open, _open)) {
      setState(() => _open = null);
    }
  }

  bool _key(KeyEvent event) {
    _sync();
    return false;
  }

  /// Starts or stops picking words, and shows the ones picked so far.
  void _sync({bool moved = false}) {
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (!shift) {
      _movedInShift = _madeInShift = false;
    } else if (moved) {
      _movedInShift = true;
    }
    // Shift is also held to type a capital letter, which should not light
    // up the word that the pointer was left on. Nor should the words by a
    // new annotation light up before Shift is let go.
    final typing =
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>() !=
        null;
    final picking = shift && !_madeInShift && (_movedInShift || !typing);
    if (!picking) _first = null;
    final first = _first;
    if (first == null) _reached = null;
    final position = _pointer;
    final word = picking && position != null ? _wordAt(position) : null;
    if (picking != _picking || (word != null) != _onWord) {
      setState(() {
        _picking = picking;
        _onWord = word != null;
      });
    }
    if (first != null && word != null) _reached = word;
    widget.board.setPicked(first == null ? word : _span(first, _reached));
  }

  /// The word at [position] that can be picked. Once one word is picked,
  /// that is only a word of the same reply.
  Mark? _wordAt(Offset position) {
    final first = _first;
    for (final reply in _targets) {
      if (first != null && reply.name != first.entry) continue;
      final word = reply.wordAt(position);
      if (word != null) return word;
    }
    return null;
  }

  /// The words [a] and [b] of one reply and all that is between them. Null
  /// if the reply is too far off the screen to be built.
  Mark? _span(Mark a, Mark? b) {
    if (b == null) return a;
    for (final reply in _targets) {
      if (reply.name == a.entry) {
        return reply.mark(math.min(a.start, b.start), math.max(a.end, b.end));
      }
    }
    return null;
  }

  /// Picks the word at [position]: the first of an annotation, or the
  /// second, which opens the box.
  void _pickAt(Offset position) {
    final word = _wordAt(position);
    if (word == null) return;
    final first = _first;
    if (first == null) {
      _first = word;
      return _sync();
    }
    final mark = _span(first, word);
    if (mark == null) return;
    final annotation = widget.board.add(mark);
    _madeInShift = true;
    _sync();
    _show(annotation, position);
  }

  void _moved(PointerEvent event) {
    _pointer = event.position;
    _sync(moved: event is PointerHoverEvent);
  }

  /// Turns the wheel for the page, which does not get it while words are
  /// picked.
  void _wheel(PointerSignalEvent event) {
    final scroll = widget.scroll;
    if (!_picking || event is! PointerScrollEvent || !scroll.hasClients) {
      return;
    }
    final position = scroll.position;
    final delta = event.scrollDelta;
    position.jumpTo(
      (position.pixels + (delta.dy != 0 ? delta.dy : delta.dx)).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    // Another word is under the pointer once the page has moved.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    widget.board.removeListener(_onBoardChanged);
    widget.board.detach();
    _field.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  void _pointerUp(PointerUpEvent event) {
    final down = _down;
    if (down == null) return;
    final click = (event.position - down).distance < kTouchSlop;
    if (_downPicking) {
      if (click && _picking) _pickAt(event.position);
      return;
    }
    // The selection takes in the pointer's last movement at the end of the
    // frame.
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted) _released(event.position, click: click);
      })
      ..ensureVisualUpdate();
  }

  void _released(Offset position, {required bool click}) {
    final marks = [for (final reply in _targets) ?reply.selected()];
    // A selection that runs over several replies is not annotated.
    if (marks.length == 1) {
      final annotation = widget.board.add(marks.single);
      // The highlight takes the place of the selection.
      _targets.first.clearSelection();
      _show(annotation, position);
    } else if (marks.isEmpty && click) {
      for (final reply in _targets) {
        final annotation = reply.annotationAt(position);
        if (annotation != null) return _show(annotation, position);
      }
    }
  }

  void _show(Annotation annotation, Offset position) {
    final box = context.findRenderObject() as RenderBox;
    final scroll = widget.scroll;
    setState(() {
      _open = annotation;
      _anchor = box.globalToLocal(position);
      _scrollAtOpen = scroll.hasClients ? scroll.offset : 0;
      _field.text = annotation.comment;
    });
    _fieldFocus.requestFocus();
    widget.board.setOpen(annotation);
  }

  /// Closes the box. An annotation left with no comment is dropped.
  void _close({required bool save}) {
    if (_open == null) return;
    setState(() => _open = null);
    widget.board.closeOpen(save: save, comment: _field.text);
  }

  /// Focus moving to the box clears the selection, so Ctrl+C there copies
  /// the text that was selected, unless some of the comment is.
  void _copy() {
    final selection = _field.selection;
    final text = selection.isValid && !selection.isCollapsed
        ? selection.textInside(_field.text)
        : _open!.mark.quote;
    Clipboard.setData(ClipboardData(text: text));
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    return AnnotationScope(
      targets: _targets,
      child: Stack(
        children: [
          MouseRegion(
            cursor: _onWord ? SystemMouseCursors.click : MouseCursor.defer,
            onEnter: _moved,
            onHover: _moved,
            onExit: (_) {
              _pointer = null;
              if (mounted) _sync();
            },
            child: Listener(
              onPointerDown: (event) {
                _down = event.buttons == kPrimaryButton ? event.position : null;
                _downPicking = _picking;
              },
              onPointerUp: _pointerUp,
              onPointerSignal: _wheel,
              // While words are picked, the page gets no clicks, which would
              // select text.
              child: AbsorbPointer(absorbing: _picking, child: widget.child),
            ),
          ),
          if (open != null)
            Positioned.fill(
              child: ClipRect(
                child: CustomSingleChildLayout(
                  delegate: _BoxPlacement(
                    _anchor,
                    _scrollAtOpen,
                    widget.scroll,
                  ),
                  child: TapRegion(
                    onTapOutside: (_) => _close(save: true),
                    child: _CommentBox(
                      controller: _field,
                      focusNode: _fieldFocus,
                      canDelete: open.comment.isNotEmpty,
                      onSave: () => _close(save: true),
                      onCancel: () => _close(save: false),
                      onCopy: _copy,
                      onDelete: () {
                        _field.clear();
                        _close(save: true);
                      },
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CommentBox extends StatelessWidget {
  const _CommentBox({
    required this.controller,
    required this.focusNode,
    required this.canDelete,
    required this.onSave,
    required this.onCancel,
    required this.onCopy,
    required this.onDelete,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canDelete;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: colors.surfaceBright,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: highlightColor.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 6, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): onSave,
                const SingleActivator(LogicalKeyboardKey.escape): onCancel,
                const SingleActivator(LogicalKeyboardKey.keyC, control: true):
                    onCopy,
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 2,
                maxLines: 8,
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Comment on the selected text…',
                  isDense: true,
                  border: InputBorder.none,
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Enter saves · Shift+Enter new line · Esc cancels',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                // Only for an annotation that was saved before.
                if (canDelete)
                  IconButton(
                    tooltip: 'Delete this annotation',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                  )
                else
                  const SizedBox(height: 28),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Puts the comment box just below where the pointer was released, or above
/// it where there is no room below, and keeps it by its text as the page
/// scrolls.
class _BoxPlacement extends SingleChildLayoutDelegate {
  _BoxPlacement(this.anchor, this.scrollAtOpen, this.scroll)
    : super(relayout: scroll);

  final Offset anchor;
  final double scrollAtOpen;
  final ScrollController scroll;

  static const _width = 360.0, _gap = 14.0, _margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(
        width: math.min(_width, constraints.maxWidth - 2 * _margin),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final scrolled = scroll.hasClients ? scroll.offset - scrollAtOpen : 0;
    final below = anchor.dy + _gap + childSize.height + _margin <= size.height;
    return Offset(
      (anchor.dx - 24).clamp(
        _margin,
        math.max(_margin, size.width - childSize.width - _margin),
      ),
      (below ? anchor.dy + _gap : anchor.dy - _gap - childSize.height) -
          scrolled,
    );
  }

  @override
  bool shouldRelayout(_BoxPlacement old) =>
      anchor != old.anchor || scrollAtOpen != old.scrollAtOpen;
}
