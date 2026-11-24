import 'package:flutter/foundation.dart';

import 'sessions.dart' show EntryName;

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

  /// The annotation the comment box is open on, and the one under the
  /// pointer.
  Annotation? _open, _hovered;

  /// The words being picked with Shift held, which are drawn as an
  /// annotation in the making.
  Mark? _picked;

  Annotation? get open => _open;
  Annotation? get hovered => _hovered;
  Mark? get picked => _picked;

  int get count => _all.where((a) => a.comment.isNotEmpty).length;

  /// Adds a new annotation for [mark] and opens it for commenting.
  Annotation add(Mark mark) {
    final annotation = Annotation(mark);
    _all.add(annotation);
    _open = annotation;
    notifyListeners();
    return annotation;
  }

  /// Marks an existing [annotation] as the one currently open.
  void setOpen(Annotation? annotation) {
    if (identical(annotation, _open)) return;
    _open = annotation;
    notifyListeners();
  }

  /// Closes the open annotation, optionally saving [comment]. An annotation
  /// left with no comment is dropped.
  void closeOpen({required bool save, String comment = ''}) {
    final annotation = _open;
    if (annotation == null) return;
    if (save) annotation.comment = comment.trim();
    if (annotation.comment.isEmpty) _all.remove(annotation);
    _open = null;
    notifyListeners();
  }

  void setHovered(Annotation? annotation) {
    if (annotation == _hovered) return;
    _hovered = annotation;
    notifyListeners();
  }

  void setPicked(Mark? mark) {
    final picked = _picked;
    if (mark?.entry == picked?.entry &&
        mark?.start == picked?.start &&
        mark?.end == picked?.end) {
      return;
    }
    _picked = mark;
    notifyListeners();
  }

  /// Clears transient interaction state when the layer is disposed, without
  /// notifying listeners during teardown.
  void detach() {
    _picked = null;
    final open = _open;
    if (open != null && open.comment.isEmpty) _all.remove(open);
    _open = null;
  }

  void clear() {
    _all.clear();
    _open = null;
    _hovered = null;
    _picked = null;
    notifyListeners();
  }

  Iterable<Annotation> inReply(EntryName reply) =>
      _all.where((annotation) => annotation.mark.entry == reply);

  /// The saved annotations that are about [reply], in the order of what
  /// they are about.
  List<Annotation> _savedIn(EntryName reply) =>
      inReply(reply)
          .where((annotation) => annotation.comment.isNotEmpty)
          .toList()
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
