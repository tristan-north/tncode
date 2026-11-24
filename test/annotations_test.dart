import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tncode/annotation_highlights.dart';
import 'package:tncode/annotation_layer.dart';
import 'package:tncode/annotations.dart';
import 'package:tncode/markdown.dart';

const _reply = '''
First paragraph with **bold** and `code` in it.

- item one
- item two

```
some code
```

Last paragraph.
''';

void main() {
  late Annotations board;
  late ScrollController scroll;

  Future<void> pumpPage(WidgetTester tester) async {
    board = Annotations();
    scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotationLayer(
            board: board,
            scroll: scroll,
            child: SelectionArea(
              child: ListView(
                controller: scroll,
                children: [
                  const Text('A prompt, which cannot be annotated.'),
                  Annotatable(
                    name: ('session', 1),
                    board: board,
                    child: const MarkdownText(_reply),
                  ),
                  Annotatable(
                    name: ('session', 2),
                    board: board,
                    child: const MarkdownText('A second reply.'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Selects with the mouse from the start of the text [from] to the end of
  /// the text [to].
  Future<void> select(WidgetTester tester, String from, String to) async {
    final start = tester.getRect(find.textContaining(from, findRichText: true));
    final end = tester.getRect(find.textContaining(to, findRichText: true));
    final gesture = await tester.startGesture(
      start.centerLeft + const Offset(1, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(end.center);
    await tester.pump();
    await gesture.moveTo(end.centerRight - const Offset(1, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  Future<void> clickAway(WidgetTester tester) async {
    await tester.tapAt(const Offset(700, 590), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
  }

  testWidgets('a selection is annotated by typing and clicking away', (
    tester,
  ) async {
    await pumpPage(tester);
    await select(tester, 'First paragraph', 'item two');
    expect(find.byType(TextField), findsOneWidget);

    tester.testTextInput.enterText('Too long.');
    await clickAway(tester);
    expect(find.byType(TextField), findsNothing);
    expect(board.count, 1);
    expect(
      board.export(('session', 1)),
      '> First paragraph with bold and code in it.\n'
      '> • item one\n'
      '> • item two\n'
      'Too long.',
    );
  });

  testWidgets('clicking away with nothing typed drops the annotation', (
    tester,
  ) async {
    await pumpPage(tester);
    await select(tester, 'Last paragraph', 'Last paragraph');
    expect(find.byType(TextField), findsOneWidget);
    await clickAway(tester);
    expect(find.byType(TextField), findsNothing);
    expect(board.count, 0);
  });

  testWidgets('text outside a reply is not annotated', (tester) async {
    await pumpPage(tester);
    await select(tester, 'A prompt', 'A prompt');
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('annotations are copied by reply, and one can be reopened', (
    tester,
  ) async {
    await pumpPage(tester);
    await select(tester, 'A second reply', 'A second reply');
    tester.testTextInput.enterText('Second.');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await select(tester, 'some code', 'some code');
    tester.testTextInput.enterText('First.');
    await clickAway(tester);
    await select(tester, 'First paragraph', 'First paragraph');
    tester.testTextInput.enterText('Earlier.');
    await clickAway(tester);
    // Each reply's annotations are copied apart, in the order of their text.
    expect(
      board.export(('session', 1)),
      '> First paragraph with bold and code in it.\nEarlier.\n\n'
      '> some code\nFirst.',
    );
    expect(board.export(('session', 2)), '> A second reply.\nSecond.');

    // A click on a highlight opens its annotation; emptying it deletes it.
    await tester.tapAt(
      tester.getCenter(find.textContaining('some code', findRichText: true)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.text('First.'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete this annotation'));
    await tester.pumpAndSettle();
    expect(board.countIn(('session', 1)), 1);
    expect(board.count, 2);
  });

  /// The middle of the first word of the text [text].
  Offset word(WidgetTester tester, String text) =>
      tester.getRect(find.textContaining(text, findRichText: true)).centerLeft +
      const Offset(8, 0);

  testWidgets('with Shift held, two clicks annotate the words between them', (
    tester,
  ) async {
    await pumpPage(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: word(tester, 'item one'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await mouse.down(word(tester, 'item one'));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    // The second word can be the earlier one.
    await mouse.moveTo(word(tester, 'First paragraph'));
    await mouse.down(word(tester, 'First paragraph'));
    await mouse.up();
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(find.byType(TextField), findsOneWidget);
    tester.testTextInput.enterText('Picked.');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      board.export(('session', 1)),
      '> First paragraph with bold and code in it.\n> • item\nPicked.',
    );
  });

  testWidgets('letting go of Shift forgets the first word', (tester) async {
    await pumpPage(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: word(tester, 'item one'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await mouse.down(word(tester, 'item one'));
    await mouse.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await mouse.moveTo(word(tester, 'Last paragraph'));
    await mouse.down(word(tester, 'Last paragraph'));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    // The second word has to be in the reply of the first.
    await mouse.moveTo(word(tester, 'A second reply'));
    await mouse.down(word(tester, 'A second reply'));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);

    await mouse.moveTo(word(tester, 'some code'));
    await mouse.down(word(tester, 'some code'));
    await mouse.up();
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    tester.testTextInput.enterText('Both.');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(board.export(('session', 1)), '> some code\n> Last\nBoth.');
  });

  testWidgets('a selection over two replies is not annotated', (tester) async {
    await pumpPage(tester);
    await select(tester, 'Last paragraph', 'A second reply');
    expect(find.byType(TextField), findsNothing);
    expect(board.count, 0);
  });

  testWidgets('clearing annotations closes an open comment box', (
    tester,
  ) async {
    await pumpPage(tester);
    await select(tester, 'Last paragraph', 'Last paragraph');
    expect(find.byType(TextField), findsOneWidget);

    board.clear();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(board.count, 0);
    expect(board.open, isNull);
  });
}
