import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

const _usage = '''
Usage: tncode [options]

  --session=<id>|latest   Show only this session (an id or the start of one).
  --tools                 Start with tool calls shown.
  --top                   Open at the oldest prompt shown, not the latest.
  --screenshot=<file.png> Write a picture of the app to the file, then exit.
  --size=<W>x<H>          The size of that picture (default 1540x880).
''';

/// What the command line asks the app to open, and whether to write a
/// screenshot of it and exit.
class LaunchOptions {
  LaunchOptions({
    this.session,
    this.showTools = false,
    this.openAtTop = false,
    this.screenshot,
    this.size = const Size(1540, 880),
  });

  /// Exits with the usage text if an argument is not understood.
  factory LaunchOptions.parse(List<String> args) {
    String? session, screenshot;
    var showTools = false, openAtTop = false;
    var size = const Size(1540, 880);
    for (final arg in args) {
      final eq = arg.indexOf('=');
      final name = eq < 0 ? arg : arg.substring(0, eq);
      final value = eq < 0 ? null : arg.substring(eq + 1);
      final dimensions = value == null
          ? null
          : RegExp(r'^(\d+)x(\d+)$').firstMatch(value);
      if (name == '--session' && value != null && value.isNotEmpty) {
        session = value;
      } else if (name == '--screenshot' && value != null && value.isNotEmpty) {
        screenshot = value;
      } else if (name == '--size' && dimensions != null) {
        size = Size(
          double.parse(dimensions.group(1)!),
          double.parse(dimensions.group(2)!),
        );
      } else if (arg == '--tools') {
        showTools = true;
      } else if (arg == '--top') {
        openAtTop = true;
      } else {
        stderr.write('tncode: cannot use argument "$arg"\n\n$_usage');
        exit(64);
      }
    }
    return LaunchOptions(
      session: session,
      showTools: showTools,
      openAtTop: openAtTop,
      screenshot: screenshot,
      size: size,
    );
  }

  /// `latest`, or the start of a session id.
  final String? session;
  final bool showTools;
  final bool openAtTop;

  /// Where to write the screenshot. Null for a normal launch.
  final String? screenshot;
  final Size size;

  final _boundary = GlobalKey();
  bool _settled = false;

  /// For a screenshot, lays [app] out at [size] whatever size the window
  /// is, so that the picture does not depend on the window manager.
  Widget wrap(BuildContext context, Widget app) {
    if (screenshot == null) return app;
    return OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: size.width,
      maxWidth: size.width,
      minHeight: size.height,
      maxHeight: size.height,
      child: RepaintBoundary(
        key: _boundary,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(size: size),
          // So that nothing is drawn hovered, wherever the pointer lies.
          child: IgnorePointer(child: app),
        ),
      ),
    );
  }

  /// Gives up on a screenshot that [settled] never arrives for.
  void startTimeout() {
    if (screenshot == null) return;
    Future.delayed(const Duration(seconds: 5), () {
      fail('the app did not finish loading in 5 seconds');
    });
  }

  /// Ends a screenshot run that cannot show what was asked for.
  void fail(String message) {
    if (screenshot == null) return;
    stderr.writeln('tncode: $message');
    exit(1);
  }

  /// Called by the app when what was asked for is on screen. Takes the
  /// screenshot, if one was asked for, and exits.
  Future<void> settled() async {
    final path = screenshot;
    if (path == null || _settled) return;
    _settled = true;
    // Attached images are decoded a few frames after they are first shown,
    // and are drawn in the frame after that.
    do {
      await WidgetsBinding.instance.endOfFrame;
    } while (PaintingBinding.instance.imageCache.pendingImageCount > 0);
    await WidgetsBinding.instance.endOfFrame;
    try {
      final boundary =
          _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File(path).writeAsBytesSync(data!.buffer.asUint8List());
    } catch (error) {
      fail('could not write $path: $error');
    }
    exit(0);
  }
}
