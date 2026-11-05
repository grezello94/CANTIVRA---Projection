import 'package:flutter/services.dart';

/// Native close requests wait for the current draft transaction before allowing
/// either operating system to tear down the operator and presentation engines.
abstract final class DesktopLifecycle {
  static const channel = MethodChannel('cantivra/lifecycle');

  static void install(Future<bool> Function() prepareClose) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'prepareClose') return prepareClose();
      throw MissingPluginException(call.method);
    });
  }
}
