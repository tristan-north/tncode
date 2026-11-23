import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// How much larger than Flutter draws it the app has to be drawn to come out
/// at the size the desktop asks for.
///
/// It is 1 except on X11, which the app runs on to avoid a deadlock in
/// Flutter 3.50 on Wayland (see `linux/runner/main.cc`). There a desktop
/// with a scale that is not a whole number, such as 1.75, gives the window
/// the pixels of the screen and says how large to draw in the font
/// resolution (Xft/DPI). GTK follows that, but Flutter only follows whole
/// scales, so everything comes out tiny. Remove this together with the
/// preference for X11.
final uiScale = ValueNotifier<double>(1);

const _channel = MethodChannel('tncode/scale');

/// Sets [uiScale] from what the runner reports, and keeps it up to date as
/// the desktop's scale changes, such as when a screen is unplugged.
Future<void> followDesktopScale() async {
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'changed') uiScale.value = _scale(call.arguments);
  });
  try {
    uiScale.value = _scale(await _channel.invokeMethod<Object?>('get'));
  } on MissingPluginException {
    // Not the Linux runner, as in a widget test.
  }
}

double _scale(Object? value) =>
    value is num && value.isFinite ? value.toDouble().clamp(1, 4) : 1;

/// Draws [child] [uiScale] times as large, in the same space: the child is
/// laid out in a space that much smaller, then scaled up to fill it.
class UiScale extends StatelessWidget {
  const UiScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: uiScale,
      child: child,
      builder: (context, scale, child) {
        if (scale == 1) return child!;
        final media = MediaQuery.of(context);
        return FractionallySizedBox(
          alignment: Alignment.topLeft,
          widthFactor: 1 / scale,
          heightFactor: 1 / scale,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: MediaQuery(
              data: media.copyWith(
                size: media.size / scale,
                devicePixelRatio: media.devicePixelRatio * scale,
              ),
              child: child!,
            ),
          ),
        );
      },
    );
  }
}
