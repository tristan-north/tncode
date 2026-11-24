import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tncode/session_controller.dart';
import 'package:tncode/sessions.dart';

var _second = 0;

String _stamp() => DateTime.utc(
  2026,
  1,
  1,
).add(Duration(seconds: _second++)).toIso8601String();

String _user(String text, {String cwd = '/home/me/dev/app'}) => jsonEncode({
  'type': 'user',
  'timestamp': _stamp(),
  'cwd': cwd,
  'message': {'role': 'user', 'content': text},
});

String _assistant(List<Map<String, Object?>> content) => jsonEncode({
  'type': 'assistant',
  'timestamp': _stamp(),
  'message': {'role': 'assistant', 'content': content},
});

Map<String, Object?> _text(String text) => {'type': 'text', 'text': text};

Map<String, Object?> _tool(String command) => {
  'type': 'tool_use',
  'id': command,
  'name': 'Bash',
  'input': {'command': command},
};

/// A prompt, a tool call and a reply.
List<String> _exchange(String prompt, {String cwd = '/home/me/dev/app'}) => [
  _user(prompt, cwd: cwd),
  _assistant([_tool('ls $prompt')]),
  _assistant([_text('Reply to $prompt')]),
];

void main() {
  late Directory root;
  late SessionController controller;
  final loads = <Loaded>[];
  final problems = <String>[];
  Completer<void>? loaded;

  setUp(() {
    root = Directory.systemTemp.createTempSync('tncode_controller');
    loads.clear();
    problems.clear();
  });
  tearDown(() {
    controller.dispose();
    root.deleteSync(recursive: true);
  });

  File write(String id, List<String> lines, {bool append = false}) {
    final file = File('${root.path}/-proj/$id.jsonl');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${lines.join('\n')}\n',
      mode: append ? FileMode.append : FileMode.write,
    );
    return file;
  }

  /// Waits for the next load that changes the exchanges.
  Future<void> nextLoad() {
    final waiting = loaded = Completer<void>();
    return waiting.future.timeout(const Duration(seconds: 5));
  }

  Future<void> start({String? onlySession, String? startProject}) {
    controller = SessionController(
      root: root.path,
      onlySession: onlySession,
      startProject: startProject,
      onLoaded: (kind) {
        loads.add(kind);
        loaded?.complete();
        loaded = null;
      },
      onProblem: problems.add,
    );
    return nextLoad();
  }

  List<String> texts() => [
    for (final row in controller.rows)
      if (row is Entry) row.text,
  ];

  test('opens the session with the latest message', () async {
    write('old', _exchange('one'));
    write('new', _exchange('two', cwd: '/home/me/dev/other'));
    await start();

    expect(loads, [Loaded.first]);
    expect([for (final s in controller.sessions) s.id], ['new', 'old']);
    expect(controller.session, endsWith('new.jsonl'));
    expect(controller.project, '/home/me/dev/other');
    expect(controller.projects, ['/home/me/dev/other', '/home/me/dev/app']);
    expect(controller.rows.first, isA<Exchange>());
    expect(texts(), ['two', 'Reply to two']);
    expect(problems, isEmpty);
  });

  test('offers only the session that is named', () async {
    write('abc', _exchange('one'));
    write('xyz', _exchange('two'));
    await start(onlySession: 'ab');
    expect([for (final s in controller.sessions) s.id], ['abc']);
    expect(texts(), ['one', 'Reply to one']);
  });

  test('says so when no session or project is the one named', () async {
    write('abc', _exchange('one'));
    await start(onlySession: 'nothing');
    expect(problems, ['no session matches "nothing"']);
    expect(controller.exchanges, isEmpty);

    controller.dispose();
    problems.clear();
    await start(startProject: 'nothing');
    expect(problems, ['no project matches "nothing"']);
    expect(texts(), ['one', 'Reply to one']);
  });

  test('opens at the latest session of the project that is named', () async {
    write('a', _exchange('one'));
    write('b', _exchange('two'));
    write('c', _exchange('three', cwd: '/home/me/dev/other'));
    await start(startProject: 'app');
    expect(controller.session, endsWith('b.jsonl'));
    expect(texts(), ['two', 'Reply to two']);
  });

  test('shows another session or project when it is picked', () async {
    write('a', _exchange('one'));
    write('b', _exchange('two'));
    write('c', _exchange('three', cwd: '/home/me/dev/other'));
    await start();
    expect(texts().first, 'three');

    controller.selectSession(controller.sessions[2]);
    expect(controller.session, endsWith('a.jsonl'));
    await nextLoad();
    expect(texts().first, 'one');

    controller.selectProject('/home/me/dev/other');
    await nextLoad();
    expect(texts().first, 'three');
    expect(loads, [Loaded.first, Loaded.switched, Loaded.switched]);
  });

  test('shows tool calls when asked, and only what is searched for', () async {
    write('a', [..._exchange('one'), ..._exchange('two')]);
    await start();
    var notified = 0;
    controller.addListener(() => notified++);

    controller.showTools = true;
    expect(texts(), [
      'one',
      'ls one',
      'Reply to one',
      'two',
      'ls two',
      'Reply to two',
    ]);
    expect(controller.entryCount, 6);

    controller.query = '  LS ';
    expect(controller.query, 'ls');
    expect(texts(), ['ls one', 'ls two']);
    expect(controller.rows.whereType<Exchange>(), hasLength(2));

    controller.query = 'reply to two';
    expect(texts(), ['Reply to two']);
    expect(controller.rows.whereType<Exchange>(), hasLength(1));

    controller.query = 'nowhere';
    expect(controller.rows, isEmpty);
    expect(notified, 4);
  });

  test('follows the session, and keeps what was opened open', () async {
    final file = write('a', _exchange('one'));
    write('b', _exchange('other'));
    // The session on the page is the one written to last.
    file.writeAsStringSync('${_user('two')}\n', mode: FileMode.append);
    await start();
    controller.showTools = true;
    expect(texts(), ['one', 'ls one', 'Reply to one', 'two']);

    final tool = controller.rows.whereType<Entry>().elementAt(1);
    expect(controller.isOpen(tool), isFalse);
    controller.toggle(tool);
    expect(controller.isOpen(tool), isTrue);

    write('a', [
      _assistant([_text('Reply to two')]),
    ], append: true);
    await nextLoad();
    expect(loads, [Loaded.first, Loaded.updated]);
    expect(texts(), ['one', 'ls one', 'Reply to one', 'two', 'Reply to two']);
    // The entries are new ones, and the tool call is still open.
    final again = controller.rows.whereType<Entry>().elementAt(1);
    expect(again, isNot(same(tool)));
    expect(controller.nameOf(again), (file.path, 1));
    expect(controller.isOpen(again), isTrue);
  });

  test('a change to another session leaves the page as it is', () async {
    write('b', _exchange('other'));
    write('a', _exchange('one'));
    await start();
    final rows = controller.rows;
    final titles = Completer<void>();
    controller.addListener(() {
      if (!titles.isCompleted) titles.complete();
    });

    write('b', [
      jsonEncode({'type': 'ai-title', 'aiTitle': 'B'}),
    ], append: true);
    await titles.future.timeout(const Duration(seconds: 5));
    expect(controller.sessions.last.title, 'B');
    expect(controller.rows, same(rows));
    expect(loads, [Loaded.first]);
  });
}
