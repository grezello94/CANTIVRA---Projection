import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'application/operator_bootstrap.dart';
import 'platform/app_lifecycle.dart';
import 'presentation/renderer_runtime.dart';
import 'presentation/renderer_session.dart';
import 'ui/operator_startup_app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  RendererLaunch? renderer;
  try {
    renderer = RendererLaunch.parse(args);
  } on FormatException catch (error) {
    stderr.writeln('Invalid renderer startup configuration: $error');
    exit(2);
  }
  if (renderer != null) {
    // This process never opens the library or constructs the operator UI.
    try {
      await runRenderer(renderer);
    } catch (error) {
      stderr.writeln('Presentation renderer could not start: $error');
      exit(1);
    }
    return;
  }
  final bootstrap = OperatorBootstrap();
  DesktopLifecycle.install(bootstrap.prepareClose);
  runApp(OperatorStartupApp(bootstrap: bootstrap));
  unawaited(bootstrap.start());
}
