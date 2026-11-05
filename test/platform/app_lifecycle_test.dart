import 'dart:async';

import 'package:cantivra/platform/app_lifecycle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const codec = StandardMethodCodec();

  tearDown(() {
    DesktopLifecycle.channel.setMethodCallHandler(null);
  });

  for (final allowed in [true, false]) {
    test(
      'native close waits for the save acknowledgement and returns $allowed',
      () async {
        final saving = Completer<bool>();
        var saveRequests = 0;
        var nativeReplied = false;
        DesktopLifecycle.install(() {
          saveRequests++;
          return saving.future;
        });

        // Simulate an incoming native message rather than an outgoing plugin call.
        final response = TestDefaultBinaryMessengerBinding
            .instance
            .defaultBinaryMessenger
            .handlePlatformMessage(
              'cantivra/lifecycle',
              codec.encodeMethodCall(const MethodCall('prepareClose')),
              (_) => nativeReplied = true,
            );
        await Future<void>.delayed(Duration.zero);

        expect(saveRequests, 1);
        expect(saving.isCompleted, isFalse);
        expect(
          nativeReplied,
          isFalse,
          reason: 'The OS must not close while the draft save is pending.',
        );

        saving.complete(allowed);
        final envelope = await response;
        expect(envelope, isNotNull);
        expect(codec.decodeEnvelope(envelope!), allowed);
        expect(nativeReplied, isTrue);
        expect(saveRequests, 1);
      },
    );
  }

  test(
    'unsupported native method receives MissingPlugin without requesting a save',
    () async {
      var saveRequested = false;
      DesktopLifecycle.install(() async {
        saveRequested = true;
        return true;
      });

      final response = await TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .handlePlatformMessage(
            'cantivra/lifecycle',
            codec.encodeMethodCall(const MethodCall('unknownLifecycleAction')),
            null,
          );

      // A null method-channel envelope is the native MissingPlugin response.
      expect(response, isNull);
      expect(saveRequested, isFalse);
    },
  );
}
