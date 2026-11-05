import 'package:cantivra/platform/display_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cantivra/display');
  final calls = <MethodCall>[];
  const nativeStatus = <String, Object?>{
    'role': 'output',
    'visible': false,
    'displayId': 'external-42',
    'fullscreen': true,
    'displayAvailable': false,
    'reason': 'display_disconnected',
    'x': -1920.0,
    'y': 0.0,
    'width': 1920.0,
    'height': 1080.0,
    'scale': 1.0,
  };

  Future<Object?> sendNativeEvent(String method, Object? payload) async {
    const codec = StandardMethodCodec();
    final response = await TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(MethodCall(method, payload)),
          null,
        );
    return response == null ? null : codec.decodeEnvelope(response);
  }

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getOutputStatus') return nativeStatus;
          if (call.method == 'isProcessRunning') return true;
          if (call.method == 'listDisplays') {
            return [
              {
                'id': 'external-42',
                'name': 'Congregation display',
                'isPrimary': false,
                'x': -1920,
                'y': 0.0,
                'width': 1920,
                'height': 1080.0,
                'scale': 2,
              },
            ];
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'reads native IDs, negative display positions and mixed number types',
    () async {
      final displays = await NativeDisplayBridge.listDisplays();

      expect(displays, hasLength(1));
      expect(displays.single.id, 'external-42');
      expect(displays.single.name, 'Congregation display');
      expect(displays.single.isPrimary, isFalse);
      expect(displays.single.x, -1920.0);
      expect(displays.single.y, 0.0);
      expect(displays.single.width, 1920.0);
      expect(displays.single.height, 1080.0);
      expect(displays.single.scale, 2.0);
      expect(displays.single.isOutputEligible, isTrue);
      expect(displays.single.unavailableReason, isNull);
      expect(calls.single.method, 'listDisplays');
    },
  );

  test(
    'native ambiguous display identity stays ineligible with its reason',
    () {
      final display = DisplayInfo.fromMap({
        'id': 'windows:unidentified:display2',
        'name': 'Unidentified external display',
        'isPrimary': false,
        'x': 0,
        'y': 0,
        'width': 1920,
        'height': 1080,
        'scale': 1,
        'isOutputEligible': false,
        'unavailableReason': 'Use extended displays to identify the target.',
      });
      expect(display.isOutputEligible, isFalse);
      expect(display.unavailableReason, contains('extended displays'));
    },
  );

  test(
    'passes the explicit display choice and fullscreen flag unchanged',
    () async {
      await NativeDisplayBridge.configureOutput(
        displayId: 'external-42',
        fullscreen: true,
      );

      expect(calls.single.method, 'configureOutput');
      expect(calls.single.arguments, {
        'displayId': 'external-42',
        'fullscreen': true,
      });
    },
  );

  test(
    'rehearsal is an explicit null destination with windowed defaults',
    () async {
      await NativeDisplayBridge.configureOutput();

      expect(calls.single.arguments, {'displayId': null, 'fullscreen': false});
    },
  );

  test('empty display identities cannot degrade into rehearsal', () async {
    for (final id in ['', ' ', '\t\n']) {
      await expectLater(
        NativeDisplayBridge.configureOutput(displayId: id, fullscreen: true),
        throwsArgumentError,
      );
    }
    expect(calls, isEmpty);
  });

  test(
    'does not swallow native display failures or choose a replacement',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            throw PlatformException(code: 'DISPLAY_UNAVAILABLE');
          });

      await expectLater(
        NativeDisplayBridge.configureOutput(
          displayId: 'unplugged',
          fullscreen: true,
        ),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'DISPLAY_UNAVAILABLE',
          ),
        ),
      );
      expect(calls, hasLength(1));
    },
  );

  test('operator, hide and close remain distinct native actions', () async {
    await NativeDisplayBridge.configureOperator();
    await NativeDisplayBridge.hideOutput();
    await NativeDisplayBridge.closeOutput();

    expect(calls.map((call) => call.method), [
      'configureOperator',
      'hideOutput',
      'closeOutput',
    ]);
  });

  test('operator Quit requests only its native lifecycle action', () async {
    await NativeDisplayBridge.requestOperatorClose();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'requestOperatorClose');
    expect(calls.single.arguments, isNull);
  });

  for (final code in ['WRONG_WINDOW', 'CLOSE_REQUEST_FAILED']) {
    test(
      'native Quit rejection $code never falls back to output close',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              throw PlatformException(code: code);
            });

        await expectLater(
          NativeDisplayBridge.requestOperatorClose(),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              code,
            ),
          ),
        );
        expect(calls.map((call) => call.method), ['requestOperatorClose']);
      },
    );
  }

  test('reads native window status without altering output', () async {
    final status = await NativeDisplayBridge.outputStatus();

    expect(status, nativeStatus);
    expect(calls.single.method, 'getOutputStatus');
    expect(() => status['visible'] = true, throwsUnsupportedError);
  });

  test(
    'broadcasts native topology changes to independent subscribers',
    () async {
      final first = NativeDisplayBridge.changes.first;
      final second = NativeDisplayBridge.changes.first;
      final payload = <String, Object?>{
        ...nativeStatus,
        'displays': <Object?>[],
      };

      await sendNativeEvent('displayChanged', payload);

      expect(await first, payload);
      expect(await second, payload);
      expect(
        calls,
        isEmpty,
        reason: 'Subscription makes no platform control calls.',
      );
    },
  );

  test('native events resume after the last subscriber cancels', () async {
    final prior = NativeDisplayBridge.changes.listen((_) {});
    await prior.cancel();
    final next = NativeDisplayBridge.changes.first;

    await sendNativeEvent('displayChanged', nativeStatus);

    expect(await next, nativeStatus);
  });

  test('primary screen rejection does not retry a different screen', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          throw PlatformException(code: 'PRIMARY_DISPLAY_RESERVED');
        });

    await expectLater(
      NativeDisplayBridge.configureOutput(
        displayId: 'primary',
        fullscreen: true,
      ),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'PRIMARY_DISPLAY_RESERVED',
        ),
      ),
    );
    expect(calls, hasLength(1));
  });

  test('process liveness sends only an exact positive PID', () async {
    expect(await NativeDisplayBridge.isProcessRunning(0), isFalse);
    expect(await NativeDisplayBridge.isProcessRunning(-1), isFalse);
    expect(calls, isEmpty);

    expect(await NativeDisplayBridge.isProcessRunning(4123), isTrue);
    expect(calls.single.method, 'isProcessRunning');
    expect(calls.single.arguments, {'pid': 4123});
  });

  test(
    'unavailable process status is not interpreted as a dead renderer',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);

      await expectLater(
        NativeDisplayBridge.isProcessRunning(4123),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'PROCESS_STATUS_UNAVAILABLE',
          ),
        ),
      );
      await expectLater(
        NativeDisplayBridge.outputStatus(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'STATUS_UNAVAILABLE',
          ),
        ),
      );
    },
  );
}
