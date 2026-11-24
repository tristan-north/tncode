import 'dart:math' as math;
import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'annotations.dart';
import 'sessions.dart' show EntryName;

/// The highlighter colour of annotated text.
const highlightColor = Color(0xFFFFB02E);

/// The brighter colour of the annotation that the comment box is open on or
/// the pointer is over.
const brightHighlightColor = Color(0xFFFFD84D);

/// Operations that an [Annotatable] exposes to the [AnnotationLayer] above it.
abstract interface class AnnotatableTarget {
  EntryName get name;
  Mark? selected();
  Mark? mark(int start, int end);
  Mark? wordAt(Offset position);
  Annotation? annotationAt(Offset position);
  void clearSelection();
}

/// Provides the set of mounted [AnnotatableTarget]s to [Annotatable] widgets
/// beneath an [AnnotationLayer].
class AnnotationScope extends InheritedWidget {
  const AnnotationScope({
    super.key,
    required this.targets,
    required super.child,
  });

  final Set<AnnotatableTarget> targets;

  static Set<AnnotatableTarget>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AnnotationScope>()?.targets;

  @override
  bool updateShouldNotify(AnnotationScope old) =>
      !identical(targets, old.targets);
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

class _AnnotatableState extends State<Annotatable>
    implements AnnotatableTarget {
  final _selection = SelectionListenerNotifier();
  final _highlightsKey = GlobalKey();
  Set<AnnotatableTarget>? _targets;

  _RenderHighlights get _highlights =>
      _highlightsKey.currentContext!.findRenderObject() as _RenderHighlights;

  Iterable<Annotation> get _annotations => widget.board.inReply(widget.name);

  @override
  EntryName get name => widget.name;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = AnnotationScope.maybeOf(context);
    if (!identical(next, _targets)) {
      _targets?.remove(this);
      _targets = next;
      _targets?.add(this);
    }
  }

  @override
  void dispose() {
    _targets?.remove(this);
    _selection.dispose();
    super.dispose();
  }

  /// The selected part of this reply, if any of it is selected.
  @override
  Mark? selected() {
    if (!_selection.registered) return null;
    final range = _selection.selection.range;
    if (range == null) return null;
    return mark(
      math.min(range.startOffset, range.endOffset),
      math.max(range.startOffset, range.endOffset),
    );
  }

  /// The part of this reply between [start] and [end], if there is text in
  /// it.
  @override
  Mark? mark(int start, int end) {
    final quote = _highlights.textIn(start, end).trim();
    if (quote.isEmpty) return null;
    return Mark(widget.name, start, end, quote);
  }

  /// The word of this reply at [position] on the screen.
  @override
  Mark? wordAt(Offset position) {
    final word = _highlights.wordAt(_highlights.globalToLocal(position));
    return word == null ? null : mark(word.$1, word.$2);
  }

  /// The annotation whose highlight is at [position] on the screen.
  @override
  Annotation? annotationAt(Offset position) {
    final local = _highlights.globalToLocal(position);
    for (final annotation in _annotations) {
      final mark = annotation.mark;
      final boxes = _highlights.boxes(mark.start, mark.end);
      if (boxes.any((box) => box.contains(local))) return annotation;
    }
    return null;
  }

  @override
  void clearSelection() {
    context.findAncestorStateOfType<SelectableRegionState>()?.clearSelection();
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
              annotation == widget.board.open ||
                  annotation == widget.board.hovered,
            ),
          if (widget.board.picked case final mark?
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
              widget.board.setHovered(annotationAt(event.position)),
          onExit: (_) => widget.board.setHovered(null),
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
      final color = lit ? brightHighlightColor : highlightColor;
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
