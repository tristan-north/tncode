import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tncode/notes.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tncode-notes');
    path = '${dir.path}/data/notes.json';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  List<String> texts(List<Note> notes) => [for (final n in notes) n.text];

  test('notes are kept per project and read back from the file', () {
    final notes = Notes(path);
    notes.add('/a', 'first');
    notes.add('/a', '  second  ');
    notes.add('/a', '   ');
    notes.add('/b', 'other');
    notes.setDone('/a', notes.open('/a').last, true);

    final again = Notes(path);
    expect(again.error, isNull);
    expect(texts(again.open('/a')), ['second']);
    expect(texts(again.done('/a')), ['first']);
    expect(texts(again.open('/b')), ['other']);
  });

  test('moving, taking up again, deleting and putting back', () {
    final notes = Notes(path);
    for (final text in ['c', 'b', 'a']) {
      notes.add('/p', text);
    }
    expect(texts(notes.open('/p')), ['a', 'b', 'c']);
    notes.move('/p', 0, 2);
    expect(texts(notes.open('/p')), ['b', 'c', 'a']);

    final c = notes.open('/p')[1];
    notes.setDone('/p', c, true);
    expect(texts(notes.open('/p')), ['b', 'a']);
    notes.setDone('/p', c, false);
    expect(texts(notes.open('/p')), ['c', 'b', 'a']);

    final removed = notes.remove('/p', [notes.open('/p')[1]]);
    expect(texts(notes.open('/p')), ['c', 'a']);
    notes.putBack('/p', removed);
    expect(texts(notes.open('/p')), ['c', 'b', 'a']);
    expect(texts(Notes(path).open('/p')), ['c', 'b', 'a']);
  });

  test('a file that cannot be understood is not written over', () {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('not json');
    final notes = Notes(path);
    expect(notes.error, isNotNull);
    notes.add('/a', 'kept in memory only');
    expect(File(path).readAsStringSync(), 'not json');
  });

  testWidgets('the sidebar adds a note and folds done ones away', (
    tester,
  ) async {
    final notes = Notes(null);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const Spacer(),
              NotesSidebar(
                notes: notes,
                project: '/p',
                projectName: 'p',
                projectColor: const Color(0xFFFFFFFF),
                addFocus: focus,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Nothing to do yet.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Write the tests');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('Write the tests'), findsOneWidget);
    expect(find.text('1 to do'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.radio_button_unchecked));
    await tester.pump();
    expect(find.text('Write the tests'), findsNothing);
    expect(find.text('Everything is done.'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Write the tests'), findsOneWidget);
    expect(notes.done('/p'), hasLength(1));
  });

  testWidgets('a dragged note is in its place soon after it is let go', (
    tester,
  ) async {
    final notes = Notes(null);
    notes.add('/p', 'lower');
    notes.add('/p', 'upper');
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotesSidebar(
            notes: notes,
            project: '/p',
            projectName: 'p',
            projectColor: const Color(0xFFFFFFFF),
            addFocus: focus,
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('lower')),
    );
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(0, -12));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await gesture.up();
    await tester.pump();
    // Flutter's own move takes 250 milliseconds.
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect([for (final n in notes.open('/p')) n.text], ['lower', 'upper']);
    // Animations run at their usual speed again.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  });
}
