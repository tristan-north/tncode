import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tncode/launch.dart';

void main() {
  group('LaunchOptions.parse', () {
    test('uses sensible defaults when no arguments are passed', () {
      final options = LaunchOptions.parse(const []);
      expect(options.session, isNull);
      expect(options.project, isNull);
      expect(options.notes, isNull);
      expect(options.showTools, isFalse);
      expect(options.openAtTop, isFalse);
      expect(options.screenshot, isNull);
      expect(options.size, const Size(1540, 880));
      expect(options.wait, Duration.zero);
    });

    test('parses every supported option', () {
      final options = LaunchOptions.parse(const [
        '--session=abc',
        '--project=tncode',
        '--notes=/tmp/notes.json',
        '--tools',
        '--top',
        '--screenshot=/tmp/out.png',
        '--size=1000x2000',
        '--wait=3',
      ]);
      expect(options.session, 'abc');
      expect(options.project, 'tncode');
      expect(options.notes, '/tmp/notes.json');
      expect(options.showTools, isTrue);
      expect(options.openAtTop, isTrue);
      expect(options.screenshot, '/tmp/out.png');
      expect(options.size, const Size(1000, 2000));
      expect(options.wait, const Duration(seconds: 3));
    });

    test('throws FormatException on unknown or malformed options', () {
      expect(() => LaunchOptions.parse(['--unknown']), throwsFormatException);
      expect(() => LaunchOptions.parse(['--size=wide']), throwsFormatException);
      expect(() => LaunchOptions.parse(['--session=']), throwsFormatException);
      expect(() => LaunchOptions.parse(['--wait=abc']), throwsFormatException);
    });
  });
}
