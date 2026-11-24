import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tncode/paths.dart';
import 'package:tncode/sessions.dart';

var _second = 0;

/// A timestamp a second later than the one before, so that the lines of a
/// transcript are in order.
String _stamp() => DateTime.utc(
  2026,
  1,
  1,
).add(Duration(seconds: _second++)).toIso8601String();

String _user(Object content, [Map<String, Object?> more = const {}]) =>
    jsonEncode({
      'type': 'user',
      'timestamp': _stamp(),
      'cwd': '/home/me/dev/app',
      'message': {'role': 'user', 'content': content},
      ...more,
    });

String _assistant(
  List<Map<String, Object?>> content, [
  Map<String, Object?> more = const {},
]) => jsonEncode({
  'type': 'assistant',
  'timestamp': _stamp(),
  'message': {
    'id': 'msg_$_second',
    'model': 'claude',
    'role': 'assistant',
    'content': content,
    'usage': {'input_tokens': 3, 'output_tokens': 4},
  },
  ...more,
});

Map<String, Object?> _text(String text) => {'type': 'text', 'text': text};

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('tncode_sessions'));
  tearDown(() => root.deleteSync(recursive: true));

  /// Writes a transcript and returns its file.
  File write(String id, List<String> lines, {String project = '-proj'}) {
    final file = File('${root.path}/$project/$id.jsonl');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${lines.join('\n')}\n');
    return file;
  }

  Future<SessionStore> load() async {
    final store = SessionStore(root: root.path);
    await store.refresh();
    return store;
  }

  Future<List<Exchange>> exchangesOf(List<String> lines) async {
    write('s', lines);
    final store = await load();
    return store.recentExchanges(store.sessions.single, 100);
  }

  group('the session list', () {
    test('names a session by its title, or else its first prompt', () async {
      write('prompted', [
        _user('<command-name>/clear</command-name>'),
        _user('Fix the\n  login   page'),
        _assistant([_text('Done.')]),
      ]);
      write('titled', [
        _user('Fix the login page'),
        jsonEncode({'type': 'ai-title', 'aiTitle': 'Login fix'}),
        jsonEncode({'type': 'ai-title', 'aiTitle': 'Login page fix'}),
      ]);
      write('renamed', [
        _user('Fix the login page'),
        jsonEncode({'type': 'custom-title', 'customTitle': 'Mine'}),
        jsonEncode({'type': 'ai-title', 'aiTitle': 'Login page fix'}),
      ]);
      write('command', [_user('<command-name>/clear</command-name>')]);

      final store = await load();
      final titles = {for (final s in store.sessions) s.id: s.title};
      expect(titles, {
        'prompted': 'Fix the login page',
        'titled': 'Login page fix',
        'renamed': 'Mine',
        'command': '/clear',
      });
    });

    test('takes the project from the transcript, or else its folder', () async {
      write('a', [_user('Hello')]);
      write('b', [
        jsonEncode({
          'type': 'user',
          'timestamp': _stamp(),
          'message': {'content': 'Hello'},
        }),
      ], project: '-home-me-other');

      final store = await load();
      final projects = {for (final s in store.sessions) s.id: s.projectDir};
      expect(projects, {'a': '/home/me/dev/app', 'b': '-home-me-other'});
    });

    test('is ordered by the last message of the conversation', () async {
      write('old', [_user('First')]);
      write('new', [_user('Second')]);
      // Neither of these is something that was said in the old session.
      write('old', [
        _user('First'),
        _user('A note to Claude', {'isMeta': true}),
        _assistant([_text('From a subagent')], {'isSidechain': true}),
      ]);
      // Written after the lines above, but dated before them.
      final last = DateTime.utc(2026, 1, 1).add(Duration(seconds: _second));
      write('new', [
        _user('Second'),
        jsonEncode({
          'type': 'assistant',
          'timestamp': last.toIso8601String(),
          'message': {
            'content': [_text('Reply')],
          },
        }),
      ]);

      final store = await load();
      expect([for (final s in store.sessions) s.id], ['new', 'old']);
      expect(store.sessions.first.lastActivity.toUtc(), last);
    });

    test('leaves out a transcript in which nothing was said', () async {
      write('empty', [
        _user('A note to Claude', {'isMeta': true}),
        jsonEncode({'type': 'summary', 'summary': 'Nothing'}),
      ]);
      write('real', [_user('Hello')]);

      final store = await load();
      expect([for (final s in store.sessions) s.id], ['real']);
    });

    test('reads again only when a transcript has changed', () async {
      final file = write('s', [_user('One')]);
      final store = await load();
      final before = store.sessions.single;
      expect(await store.refresh(), isFalse);
      expect(store.sessions.single, same(before));

      file.writeAsStringSync('${_user('Two')}\n', mode: FileMode.append);
      expect(await store.refresh(), isTrue);
      expect(store.sessions.single, isNot(same(before)));

      file.deleteSync();
      expect(await store.refresh(), isTrue);
      expect(store.sessions, isEmpty);
    });
  });

  group('the exchanges of a session', () {
    test('are each a prompt and what followed it', () async {
      final exchanges = await exchangesOf([
        _user('One'),
        _assistant([
          {'type': 'thinking', 'thinking': ' Hmm. '},
          _text('First reply'),
        ]),
        _user([_text('Two')]),
        _assistant([_text('Second reply')]),
        _assistant([_text('From a subagent')], {'isSidechain': true}),
      ]);

      expect(exchanges, hasLength(2));
      expect(exchanges[0].prompt.text, 'One');
      expect(exchanges[0].index, 0);
      expect(
        [for (final e in exchanges[0].replies) (e.kind, e.text)],
        [(EntryKind.thinking, 'Hmm.'), (EntryKind.assistant, 'First reply')],
      );
      expect(exchanges[1].prompt.text, 'Two');
      expect(exchanges[1].index, 3);
      expect(exchanges[1].replies.single.text, 'Second reply');
    });

    test('give a tool call its result', () async {
      final long = 'x' * 20005;
      final exchanges = await exchangesOf([
        _user('Run them'),
        _assistant([
          {
            'type': 'tool_use',
            'id': 'a',
            'name': 'Bash',
            'input': {'command': 'ls\n  -l', 'description': 'List'},
          },
          {
            'type': 'tool_use',
            'id': 'b',
            'name': 'Read',
            'input': {'file_path': '/tmp/f'},
          },
          {
            'type': 'tool_use',
            'id': 'c',
            'name': 'Bash',
            'input': {'command': 'yes'},
          },
        ]),
        _user([
          {
            'type': 'tool_result',
            'tool_use_id': 'a',
            'content': '\x1B[1mfile\x1B[0m\n',
          },
          {
            'type': 'tool_result',
            'tool_use_id': 'b',
            'is_error': true,
            'content': [
              _text('No such file'),
              {'type': 'image'},
            ],
          },
          {'type': 'tool_result', 'tool_use_id': 'c', 'content': long},
        ]),
      ]);

      final [bash, read, yes] = exchanges.single.replies;
      expect(bash.kind, EntryKind.tool);
      expect(bash.toolName, 'Bash');
      expect(bash.text, 'ls -l');
      expect(bash.toolInput, contains('"description": "List"'));
      expect(bash.toolResult, 'file');
      expect(bash.toolError, isFalse);

      expect(read.text, '/tmp/f');
      expect(read.toolInput, '/tmp/f');
      expect(read.toolResult, 'No such file\n[image]');
      expect(read.toolError, isTrue);

      expect(yes.toolResult, '${'x' * 20000}\n… (5 more characters)');
    });

    test('show what was typed or seen, not how it is stored', () async {
      final exchanges = await exchangesOf([
        _user(
          'Hello <system-reminder>Be good.</system-reminder>\n'
          '<system-reminder>Really.</system-reminder>',
        ),
        _assistant([_text('Hi')]),
        _user('<local-command-caveat>Not a request.</local-command-caveat>'),
        _user(
          '<command-name>/model</command-name>'
          '<command-args>opus</command-args>',
        ),
        _user('<local-command-stdout>\x1B[2mSet\x1B[0m</local-command-stdout>'),
        _user('<local-command-stdout></local-command-stdout>'),
        _assistant([_text('Noted')]),
        _user('<bash-input>ls</bash-input>'),
        _user('<bash-stdout>a.txt</bash-stdout>'),
        _user(
          '<task-notification><summary>Build done</summary>'
          '</task-notification>',
        ),
        _assistant([_text('Good')]),
        _user('Long ago\n\nwe spoke.', {'isCompactSummary': true}),
      ]);

      expect(
        [
          for (final exchange in exchanges)
            [
              exchange.prompt.text,
              for (final e in exchange.replies) (e.kind, e.text),
            ],
        ],
        [
          ['Hello', (EntryKind.assistant, 'Hi')],
          [
            '/model opus',
            (EntryKind.output, 'Set'),
            (EntryKind.assistant, 'Noted'),
          ],
          [
            '! ls',
            (EntryKind.output, 'a.txt'),
            (EntryKind.note, 'Build done'),
            (EntryKind.assistant, 'Good'),
            (EntryKind.note, 'Long ago\n\nwe spoke.'),
          ],
        ],
      );
    });

    test('leave out a command that Claude said nothing to', () async {
      final exchanges = await exchangesOf([
        _user('<command-name>/clear</command-name>'),
        _user('<local-command-stdout>Cleared</local-command-stdout>'),
        _user('Hello'),
        _user('<bash-input>ls</bash-input>'),
      ]);
      expect([for (final e in exchanges) e.prompt.text], ['Hello']);
    });

    test('read the size of an attached image from its header', () async {
      // The signature of a PNG and the start of its first chunk.
      final png = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
        0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
        0, 0, 0x02, 0x80, 0, 0, 0x01, 0xE0,
      ];
      Map<String, Object?> image(List<int> bytes) => {
        'type': 'image',
        'source': {'type': 'base64', 'data': base64Encode(bytes)},
      };
      final exchanges = await exchangesOf([
        _user([_text('Look'), image(png)]),
        _user([
          image([1, 2, 3]),
        ]),
      ]);

      final shown = exchanges[0].prompt.images.single;
      expect((shown.width, shown.height), (640, 480));
      expect(shown.bytes, png);

      expect(exchanges[1].prompt.text, '');
      final unknown = exchanges[1].prompt.images.single;
      expect((unknown.width, unknown.height), (null, null));
    });

    test('skip a line that is not whole', () async {
      final exchanges = await exchangesOf([
        _user('Hello'),
        _assistant([_text('Hi')]),
        '{"type":"assistant","message":{"content":[{"type":"text","te',
      ]);
      expect(exchanges.single.replies.single.text, 'Hi');
    });

    test('are the latest ones, and the same until they change', () async {
      final file = write('s', [
        for (var i = 1; i <= 5; i++) ...[
          _user('Prompt $i'),
          _assistant([_text('Reply $i')]),
        ],
      ]);
      final store = await load();
      final session = store.sessions.single;
      final recent = await store.recentExchanges(session, 2);
      expect([for (final e in recent) e.prompt.text], ['Prompt 4', 'Prompt 5']);
      expect(recent.first.session.path, session.path);

      final again = await store.recentExchanges(session, 2);
      expect(again.first, same(recent.first));

      file.writeAsStringSync('${_user('Prompt 6')}\n', mode: FileMode.append);
      await store.refresh();
      final changed = await store.recentExchanges(store.sessions.single, 2);
      expect(
        [for (final e in changed) e.prompt.text],
        ['Prompt 5', 'Prompt 6'],
      );
    });
  });

  test('a home directory at the start of a path is shortened', () {
    final home = homeDir();
    if (home == null || home == '/') return;
    expect(shortenHome(home), '~');
    expect(shortenHome('$home/dev/app'), '~/dev/app');
    expect(shortenHome('${home}er/dev'), '${home}er/dev');
    expect(shortenHome('/elsewhere'), '/elsewhere');
  });
}
