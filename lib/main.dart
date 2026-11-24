import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'home_page.dart';
import 'launch.dart';
import 'theme.dart';

void main(List<String> args) {
  final LaunchOptions options;
  try {
    options = LaunchOptions.parse(args);
  } on FormatException catch (error) {
    stderr.write('tncode: ${error.message}\n\n${LaunchOptions.usage}');
    exit(64);
  }
  options.startTimeout();
  runApp(TncodeApp(options: options));
}

class TncodeApp extends StatelessWidget {
  const TncodeApp({super.key, required this.options});

  final LaunchOptions options;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Claude Sessions',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      builder: (context, child) => options.wrap(context, child!),
      home: HomePage(options: options),
    );
  }
}
