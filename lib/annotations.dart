import 'dart:math' as math;
import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// The highlighter colour of annotated text.
const _marker = Color(0xFFFFB02E);

/// The brighter colour of the annotation that the comment box is open on or
/// the pointer is over.
const _brightMarker = Color(0xFFFFD84D);

/// A reply, named by its session's path and its position in the session.
typedef EntryName = (String, int);

/// A stretch of one reply that an annotation is about. [start] and [end]
/// count characters of the reply's text as it is displayed, which is not its
/// markdown source.
class Mark {
  const Mark(this.entry, this.start, this.end, this.quote);

  final EntryName entry;
  final int start;
  final int end;
  final String quote;
}

class Annotation {
  Annotation(this.mark);

  /// What it is about.
  final Mark mark;

  /// Empty only while the annotation is first being typed.
  String comment = '';
}

/// The annotations made since the app started. They are not written to disk.
class Annotations extends ChangeNotifier {
  final _all = <Annotation>[];

  /// The replies that are built now, which is those on or near the screen.
  final _replies = <_AnnotatableState>{};

  /// The annotation the comment box is open on, and the one under the
  /// pointer.
  Annotation? _open, _hovered;

  void _hover(Annotation? annotation) {
    if (annotation == _hovered) return;
    _hovered = annotation;
    notifyListeners();
  }

  int get count => _all.where((a) => a.comment.isNotEmpty).length;

  void clear() {
    _all.clear();
    _hovered = null;
    notifyListeners();
  }

  void _changed() => notifyListeners();

  /// The words being picked with Shift held, which are drawn as an
  /// annotation in the making.
  Mark? _picked;

  void _pick(Mark? mark) {
    final picked = _picked;
    if (mark?.entry == picked?.entry &&
        mark?.start == picked?.start &&
        mark?.end == picked?.end) {
      return;
    }
    _picked = mark;
    notifyListeners();
  }

  Iterable<Annotation> _in(EntryName reply) =>
      _all.where((annotation) => annotation.mark.entry == reply);

  /// The saved annotations that are about [reply], in the order of what
  /// they are about.
  List<Annotation> _savedIn(EntryName reply) =>
      _in(reply).where((annotation) => annotation.comment.isNotEmpty).toList()
        ..sort((a, b) => a.mark.start.compareTo(b.mark.start));

  int countIn(EntryName reply) => _savedIn(reply).length;

  /// The annotations about [reply] as text to paste into a chat: each quotes
  /// what it is about and gives its comment underneath.
  String export(EntryName reply) {
    return [
      for (final annotation in _savedIn(reply))
        [
          annotation.mark.quote
              .split('\n')
              .map((line) => line.isEmpty ? '>' : '> $line')
              .join('\n'),
          annotation.comment,
        ].join('\n'),
    ].join('\n\n');
  }
}

/// A reply whose text can be annotated: it reports what is selected in it to
/// the [AnnotationLayer] above and highlights its annotated text.
class Annotatable extends StatefulWidget {
  const Annotatable({
    super.key,
    required this.name,
    required this.board,
    required this.child,
  });

  final EntryName name;
  final Annotations board;
  final Widget child;

  @override
  State<Annotatable> createState() => _AnnotatableState();
}

class _AnnotatableState extends State<Annotatable> {
  final _selection = SelectionListenerNotifier();
  final _highlightsKey = GlobalKey();

  _RenderHighlights get _highlights =>
      _highlightsKey.currentContext!.findRenderObject() as _RenderHighlights;

  Iterable<Annotation> get _annotations => widget.board._in(widget.name);

  @override
  void initState() {
    super.initState();
    widget.board._replies.add(this);
  }

  @override
  void dispose() {
    widget.board._replies.remove(this);
    _selection.dispose();
    super.dispose();
  }

  /// The selected part of this reply, if any of it is selected.
  Mark? _selected() {
    if (!_selection.registered) return null;
    final range = _selection.selection.range;
    if (range == null) return null;
    return _mark(
      math.min(range.startOffset, range.endOffset),
      math.max(range.startOffset, range.endOffset),
    );
  }

  /// The part of this reply between [start] and [end], if there is text in
  /// it.
  Mark? _mark(int start, int end) {
    final quote = _highlights.textIn(start, end).trim();
    if (quote.isEmpty) return null;
    return Mark(widget.name, start, end, quote);
  }

  /// The word of this reply at [position] on the screen.
  Mark? _wordAt(Offset position) {
    final word = _highlights.wordAt(_highlights.globalToLocal(position));
    return word == null ? null : _mark(word.$1, word.$2);
  }

  /// The annotation whose highlight is at [position] on the screen.
  Annotation? _annotationAt(Offset position) {
    final local = _highlights.globalToLocal(position);
    for (final annotation in _annotations) {
      final mark = annotation.mark;
      final boxes = _highlights.boxes(mark.start, mark.end);
      if (boxes.any((box) => box.contains(local))) return annotation;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.board,
      builder: (context, child) => _Highlights(
        key: _highlightsKey,
        ranges: [
          for (final annotation in _annotations)
            (
              annotation.mark.start,
              annotation.mark.end,
              annotation == widget.board._open ||
                  annotation == widget.board._hovered,
            ),
          if (widget.board._picked case final mark?
              when mark.entry == widget.name)
            (mark.start, mark.end, true),
        ],
        child: child,
      ),
      // A wide code block scrolls sideways under its highlights.
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _highlights.markNeedsPaint();
          return false;
        },
        child: MouseRegion(
          opaque: false,
          onHover: (event) =>
              widget.board._hover(_annotationAt(event.position)),
          onExit: (_) => widget.board._hover(null),
          child: SelectionListener(
            selectionNotifier: _selection,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _Highlights extends SingleChildRenderObjectWidget {
  const _Highlights({super.key, required this.ranges, super.child});

  /// Each a start, an end and whether to draw it in the brighter colour.
  final List<(int, int, bool)> ranges;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHighlights(ranges);

  @override
  void updateRenderObject(BuildContext context, _RenderHighlights render) {
    render.ranges = ranges;
  }
}

/// A run of selectable text in a paragraph under a [_RenderHighlights].
/// [offset] is how many characters of the reply come before it, and [clip]
/// the part of the reply it can be seen in when something clips it.
typedef _Piece = ({
  RenderParagraph paragraph,
  String text,
  int from,
  int to,
  int offset,
  Rect? clip,
});

const _cornerRadius = 2.5;

final _placeholder = String.fromCharCode(PlaceholderSpan.placeholderCodeUnit);

/// Draws highlights over ranges of the text beneath it. The ranges count
/// characters the way [SelectionListener] does for the same subtree: through
/// its paragraphs in order, leaving out the widgets set within their text.
class _RenderHighlights extends RenderProxyBox {
  _RenderHighlights(this._ranges);

  List<(int, int, bool)> _ranges;
  set ranges(List<(int, int, bool)> value) {
    if (listEquals(value, _ranges)) return;
    _ranges = value;
    markNeedsPaint();
  }

  List<_Piece> _pieces() {
    final pieces = <_Piece>[];
    var offset = 0;
    void visit(RenderObject object, Rect? clip) {
      if (object is RenderParagraph) {
        final text = object.text.toPlainText(includeSemanticsLabels: false);
        var from = 0;
        while (from < text.length) {
          var to = text.indexOf(_placeholder, from);
          if (to < 0) to = text.length;
          if (to > from) {
            pieces.add((
              paragraph: object,
              text: text,
              from: from,
              to: to,
              offset: offset,
              clip: clip,
            ));
            offset += to - from;
          }
          from = to + 1;
        }
      }
      object.visitChildren((child) {
        var inner = clip;
        final own = object.describeApproximatePaintClip(child);
        if (own != null) {
          final rect = MatrixUtils.transformRect(
            object.getTransformTo(this),
            own,
          );
          inner = inner?.intersect(rect) ?? rect;
        }
        visit(child, inner);
      });
    }

    visit(this, null);
    return pieces;
  }

  /// The parts of the paragraphs that lie between [start] and [end].
  Iterable<(_Piece, TextSelection)> _within(int start, int end) sync* {
    for (final piece in _pieces()) {
      final a = math.max(start - piece.offset, 0) + piece.from;
      final b = math.min(end - piece.offset + piece.from, piece.to);
      if (a < b) yield (piece, TextSelection(baseOffset: a, extentOffset: b));
    }
  }

  /// The start and the end of the word drawn at [point]. A word is what
  /// stands between two spaces, punctuation included.
  (int, int)? wordAt(Offset point) {
    bool isSpace(String character) => character.trim().isEmpty;
    for (final piece in _pieces()) {
      if (piece.clip?.contains(point) == false) continue;
      final paragraph = piece.paragraph;
      final local = paragraph.globalToLocal(point, ancestor: this);
      if (!(Offset.zero & paragraph.size).contains(local)) continue;
      final text = piece.text;
      final at = paragraph.getPositionForOffset(local).offset;
      // The position is between two characters, and the pointer can be on
      // either.
      for (final index in [at, at - 1]) {
        if (index < piece.from || index >= piece.to) continue;
        if (isSpace(text[index])) continue;
        var start = index, end = index + 1;
        while (start > piece.from && !isSpace(text[start - 1])) {
          start--;
        }
        while (end < piece.to && !isSpace(text[end])) {
          end++;
        }
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
          boxHeightStyle: BoxHeightStyle.max,
        );
        if (!boxes.any((box) => box.toRect().contains(local))) continue;
        final shift = piece.offset - piece.from;
        return (start + shift, end + shift);
      }
    }
    return null;
  }

  /// Where the text between [start] and [end] is drawn. Each box is as tall
  /// as its line, so the boxes of a paragraph's lines meet.
  Iterable<Rect> boxes(int start, int end) sync* {
    for (final (piece, selection) in _within(start, end)) {
      final transform = piece.paragraph.getTransformTo(this);
      final boxes = piece.paragraph.getBoxesForSelection(
        selection,
        boxHeightStyle: BoxHeightStyle.max,
      );
      for (final box in boxes) {
        var rect = MatrixUtils.transformRect(transform, box.toRect());
        final clip = piece.clip;
        if (clip != null) rect = rect.intersect(clip);
        if (rect.width > 0 && rect.height > 0) yield rect;
      }
    }
  }

  /// The text between [start] and [end], with a line break between
  /// paragraphs, or a space between ones that are side by side, as a list
  /// item is with its bullet.
  String textIn(int start, int end) {
    final buffer = StringBuffer();
    RenderParagraph? previous;
    var bottom = 0.0;
    for (final (piece, selection) in _within(start, end)) {
      final paragraph = piece.paragraph;
      final rect = MatrixUtils.transformRect(
        paragraph.getTransformTo(this),
        Offset.zero & paragraph.size,
      );
      if (previous != null && previous != paragraph) {
        buffer.write(rect.top < bottom - 1 ? ' ' : '\n');
      }
      buffer.write(selection.textInside(piece.text));
      previous = paragraph;
      bottom = rect.bottom;
    }
    return buffer.toString();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    // Over the text rather than under it, because code has a background of
    // its own that would hide them.
    for (final (start, end, lit) in _ranges) {
      // One box for each line of text.
      final lines = <Rect>[];
      for (final box in boxes(start, end)) {
        final rect = box.shift(offset);
        final last = lines.lastOrNull;
        if (last != null &&
            (last.top - rect.top).abs() < 0.5 &&
            (last.bottom - rect.bottom).abs() < 0.5 &&
            rect.left <= last.right + 1 &&
            rect.right >= last.left - 1) {
          lines.last = last.expandToInclude(rect);
        } else {
          lines.add(rect);
        }
      }
      final shape = Path();
      for (final line in lines) {
        shape.addRect(line.deflate(1));
      }
      // A thick outline with round joins rounds the corners that point out
      // of the shape. The boxes and their outlines overlap, so they are
      // drawn solid on a layer and the layer is made see-through as a whole:
      // laid on one by one, the colour would be darker wherever two of them
      // overlap.
      final color = lit ? _brightMarker : _marker;
      final solid = Paint()..color = color;
      final canvas = context.canvas;
      canvas.saveLayer(
        shape.getBounds().inflate(_cornerRadius),
        Paint()..color = color.withValues(alpha: lit ? 0.45 : 0.3),
      );
      canvas.drawPath(shape, solid);
      canvas.drawPath(
        shape,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * _cornerRadius
          ..strokeJoin = StrokeJoin.round,
      );
      // The corners that point into the shape are where one line stops
      // short of the line above or below it. Each is rounded by filling it
      // in, up to a quarter circle.
      for (var i = 1; i < lines.length; i++) {
        if ((lines[i].top - lines[i - 1].bottom).abs() > 1) continue;
        // The lines as drawn, outline included.
        final above = lines[i - 1].inflate(_cornerRadius - 1);
        final below = lines[i].inflate(_cornerRadius - 1);
        if (above.left >= below.right || below.left >= above.right) continue;
        for (final side in const [-1.0, 1.0]) {
          final a = side < 0 ? above.left : above.right;
          final b = side < 0 ? below.left : below.right;
          if ((a - b).abs() < 2 * _cornerRadius) continue;
          final aboveIsShort = side < 0 ? a > b : a < b;
          final corner = aboveIsShort
              ? Offset(a, below.top)
              : Offset(b, above.bottom);
          final outward = Offset(
            side * _cornerRadius,
            aboveIsShort ? -_cornerRadius : _cornerRadius,
          );
          canvas.drawPath(
            Path.combine(
              PathOperation.difference,
              // Starts a little inside the shape, to leave no seam.
              Path()..addRect(
                Rect.fromPoints(corner - outward * 0.2, corner + outward),
              ),
              Path()..addOval(
                Rect.fromCircle(
                  center: corner + outward,
                  radius: _cornerRadius,
                ),
              ),
            ),
            solid,
          );
        }
      }
      canvas.restore();
    }
  }
}

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
    widget.board._pick(first == null ? word : _span(first, _reached));
  }

  /// The word at [position] that can be picked. Once one word is picked,
  /// that is only a word of the same reply.
  Mark? _wordAt(Offset position) {
    final first = _first;
    for (final reply in widget.board._replies) {
      if (first != null && reply.widget.name != first.entry) continue;
      final word = reply._wordAt(position);
      if (word != null) return word;
    }
    return null;
  }

  /// The words [a] and [b] of one reply and all that is between them. Null
  /// if the reply is too far off the screen to be built.
  Mark? _span(Mark a, Mark? b) {
    if (b == null) return a;
    for (final reply in widget.board._replies) {
      if (reply.widget.name == a.entry) {
        return reply._mark(math.min(a.start, b.start), math.max(a.end, b.end));
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
    final annotation = Annotation(mark);
    widget.board._all.add(annotation);
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
    widget.board._picked = null;
    final open = _open;
    if (open != null && open.comment.isEmpty) widget.board._all.remove(open);
    widget.board._open = null;
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
    final board = widget.board;
    final replies = board._replies;
    final marks = [for (final reply in replies) ?reply._selected()];
    // A selection that runs over several replies is not annotated.
    if (marks.length == 1) {
      final annotation = Annotation(marks.single);
      board._all.add(annotation);
      // The highlight takes the place of the selection.
      replies.first.context
          .findAncestorStateOfType<SelectableRegionState>()
          ?.clearSelection();
      _show(annotation, position);
    } else if (marks.isEmpty && click) {
      for (final reply in replies) {
        final annotation = reply._annotationAt(position);
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
    widget.board
      .._open = annotation
      .._changed();
  }

  /// Closes the box. An annotation left with no comment is dropped.
  void _close({required bool save}) {
    final annotation = _open;
    if (annotation == null) return;
    if (save) annotation.comment = _field.text.trim();
    if (annotation.comment.isEmpty) widget.board._all.remove(annotation);
    setState(() => _open = null);
    widget.board
      .._open = null
      .._changed();
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
    return Stack(
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
                delegate: _BoxPlacement(_anchor, _scrollAtOpen, widget.scroll),
                child: TapRegion(
                  onTapOutside: (_) => _close(save: true),
                  child: _buildBox(open),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBox(Annotation annotation) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: colors.surfaceBright,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: _marker.withValues(alpha: 0.7)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 6, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): () =>
                    _close(save: true),
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    _close(save: false),
                const SingleActivator(LogicalKeyboardKey.keyC, control: true):
                    _copy,
              },
              child: TextField(
                controller: _field,
                focusNode: _fieldFocus,
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
                if (annotation.comment.isNotEmpty)
                  IconButton(
                    tooltip: 'Delete this annotation',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _field.clear();
                      _close(save: true);
                    },
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
