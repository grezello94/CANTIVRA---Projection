import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cantivra/platform/local_rpc.dart';
import 'package:cantivra/presentation/desktop_output.dart';
import 'package:cantivra/presentation/live_controller.dart';
import 'package:cantivra/presentation/renderer_runtime.dart';
import 'package:cantivra/presentation/renderer_session.dart';
import 'package:cantivra/presentation/renderer_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'renderer_process_test.dart' show Backend, frame;

Future<void> waitFor(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue);
}

class AckRenderer {
  AckRenderer({
    this.delayAck = false,
    this.uncertainCommit = false,
    this.renderSchema = renderSchemaVersion,
  });
  final bool delayAck;
  final bool uncertainCommit;
  final int? renderSchema;
  Completer<void>? helloGate;
  Completer<void>? configureGate;
  late ServerSocket server;
  late RendererSession session;
  final peers = <LocalRpcPeer>[];
  OutputFrame current = const OutputFrame(revision: 0);
  OutputFrame? prepared;
  int rendered = 0;
  bool alive = true;
  final methods = <String>[];
  Map<String, Object?> get info => {
    'protocol': 2,
    if (renderSchema != null) 'renderSchema': renderSchema,
    'session': session.sessionId,
    'pid': pid,
    'frame': current.toMap(),
    'renderedRevision': rendered,
    'configuration': const OutputConfiguration().toMap(),
    'window': {'visible': true, 'displayAvailable': true},
  };
  Future<void> start(String path) async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    session = RendererSession(
      sessionId: sessionSecret(16),
      token: sessionSecret(),
      port: server.port,
      processId: pid,
      createdAt: DateTime.now(),
    );
    await session.write(path);
    server.listen((socket) {
      final peer = LocalRpcPeer(
        socket,
        onRequest: (method, args) async {
          methods.add(method);
          switch (method) {
            case 'hello':
              await helloGate?.future;
              return info;
            case 'configure':
              await configureGate?.future;
              return info;
            case 'prepare':
              prepared = OutputFrame.fromMap(
                Map<String, Object?>.from(args['frame']! as Map),
              );
              return {'prepared': true};
            case 'commit':
              if (!uncertainCommit) {
                current = prepared!;
                rendered = current.revision;
              }
              if (delayAck || uncertainCommit) {
                await Future<void>.delayed(const Duration(milliseconds: 3300));
              }
              return {
                'revision': current.revision,
                'renderedRevision': rendered,
              };
            case 'emergency':
              current = OutputFrame.fromMap(
                Map<String, Object?>.from(args['frame']! as Map),
              );
              rendered = current.revision;
              return {
                'revision': current.revision,
                'renderedRevision': rendered,
              };
            default:
              return info;
          }
        },
      );
      peers.add(peer);
    });
  }

  Future<void> close() async {
    for (final peer in peers) {
      await peer.close();
    }
    await server.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DesktopOutput output;
  late Backend backend;
  RendererRuntime? runtime;
  RendererState? state;
  var starts = 0;
  late String path;
  Future<int> launch(RendererLaunch launch) async {
    starts++;
    backend = Backend();
    state = RendererState(sessionId: launch.sessionId, frameReady: () async {});
    runtime = RendererRuntime(launch: launch, state: state!, backend: backend);
    await runtime!.start();
    return pid;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('output-supervision-');
    path = '${directory.path}/session.json';
    starts = 0;
    backend = Backend();
    runtime = null;
    state = null;
    output = DesktopOutput(
      sessionPath: path,
      launchRenderer: launch,
      processExists: (_) async => backend.alive,
      healthInterval: const Duration(milliseconds: 40),
    );
  });
  tearDown(() async {
    output.dispose();
    await runtime?.dispose();
    state?.dispose();
    await backend.events.close();
    await directory.delete(recursive: true);
  });

  test(
    'disposed output never reconnects, launches or sends commands',
    () async {
      output.dispose();
      expect(await output.recoverExisting(), isFalse);
      await expectLater(output.open(), throwsStateError);
      await expectLater(output.inspect(), throwsStateError);
      await expectLater(output.publish(frame(1, 'Unused')), throwsStateError);
      await expectLater(output.close(), throwsStateError);
      expect(output.canControl, isFalse);
      expect(output.connected, isFalse);
      expect(starts, 0);
      expect(await File(path).exists(), isFalse);
    },
  );

  test(
    'disposal during recovery hello closes its pending authenticated peer',
    () async {
      final remote = AckRenderer()..helloGate = Completer<void>();
      remote.current = frame(17, 'The renderer keeps the accepted frame.');
      remote.rendered = 17;
      await remote.start(path);
      final descriptor = await File(path).readAsBytes();
      try {
        final recovery = output.recoverExisting();
        await waitFor(() => remote.methods.contains('hello'));
        output.dispose();
        remote.helloGate!.complete();
        expect(await recovery, isFalse);
        await waitFor(() => remote.peers.every((peer) => peer.isClosed));
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(output.canControl, isFalse);
        expect(output.connected, isFalse);
        expect(output.recoveredFrame, isNull);
        expect(remote.methods, ['hello']);
        expect(remote.current.revision, 17);
        expect(await File(path).readAsBytes(), descriptor);
        expect(starts, 0);
      } finally {
        if (!remote.helloGate!.isCompleted) remote.helloGate!.complete();
        await remote.close();
      }
    },
  );

  test(
    'disposal during open hello never configures the surviving output',
    () async {
      final remote = AckRenderer()..helloGate = Completer<void>();
      remote.current = frame(19, 'Keep this output on its original display.');
      remote.rendered = 19;
      await remote.start(path);
      try {
        final opening = expectLater(output.open(), throwsA(anything));
        await waitFor(() => remote.methods.contains('hello'));
        output.dispose();
        remote.helloGate!.complete();
        await opening;
        await waitFor(() => remote.peers.every((peer) => peer.isClosed));
        expect(output.canControl, isFalse);
        expect(remote.methods, ['hello']);
        expect(remote.current.revision, 19);
        expect(starts, 0);
      } finally {
        if (!remote.helloGate!.isCompleted) remote.helloGate!.complete();
        await remote.close();
      }
    },
  );

  test(
    'disposal during configure cannot resurrect control or health polling',
    () async {
      final remote = AckRenderer()..configureGate = Completer<void>();
      remote.current = frame(21, 'A configured renderer remains independent.');
      remote.rendered = 21;
      await remote.start(path);
      try {
        final opening = expectLater(output.open(), throwsA(anything));
        await waitFor(() => remote.methods.contains('configure'));
        output.dispose();
        remote.configureGate!.complete();
        await opening;
        await waitFor(() => remote.peers.every((peer) => peer.isClosed));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(output.canControl, isFalse);
        expect(output.connected, isFalse);
        expect(remote.methods, ['hello', 'configure']);
        expect(remote.current.revision, 21);
        expect(starts, 0);
      } finally {
        if (!remote.configureGate!.isCompleted) {
          remote.configureGate!.complete();
        }
        await remote.close();
      }
    },
  );

  test(
    'disposed stale-session inspection cannot remove it or launch a replacement',
    () async {
      final oldSession = RendererSession(
        sessionId: sessionSecret(16),
        token: sessionSecret(),
        port: 1,
        processId: 123,
        createdAt: DateTime.now(),
      );
      await oldSession.write(path);
      final descriptor = await File(path).readAsBytes();
      final checked = Completer<void>();
      final running = Completer<bool>();
      output.dispose();
      output = DesktopOutput(
        sessionPath: path,
        launchRenderer: launch,
        processExists: (_) {
          if (!checked.isCompleted) checked.complete();
          return running.future;
        },
      );
      final opening = expectLater(output.open(), throwsA(anything));
      await checked.future.timeout(const Duration(seconds: 2));
      output.dispose();
      running.complete(false);
      await opening;
      expect(starts, 0);
      expect(await File(path).readAsBytes(), descriptor);
      expect(output.canControl, isFalse);
    },
  );
  for (final schema in <int?>[null, renderSchemaVersion + 1]) {
    test(
      'incompatible renderer schema $schema is never adopted or replaced',
      () async {
        final remote = AckRenderer(renderSchema: schema);
        remote.current = frame(7, 'Keep the older app output');
        remote.rendered = 7;
        await remote.start(path);
        final descriptor = await File(path).readAsBytes();
        try {
          expect(await output.recoverExisting(), isFalse);
          expect(output.state, OutputConnectionState.incompatible);
          expect(output.canControl, isFalse);
          expect(output.recoveredFrame, isNull);
          expect(output.processId, isNull);
          expect(output.error, contains('Close its output from that version'));
          await expectLater(
            output.open(),
            throwsA(
              isA<LocalRpcException>().having(
                (error) => error.code,
                'code',
                'unsupported_renderer_schema',
              ),
            ),
          );
          expect(output.state, OutputConnectionState.incompatible);
          expect(output.canControl, isFalse);
          expect(starts, 0);
          expect(remote.methods, ['hello', 'hello']);
          expect(
            remote.current.toMap(),
            frame(7, 'Keep the older app output').toMap(),
          );
          expect(await File(path).readAsBytes(), descriptor);
        } finally {
          await remote.close();
        }
      },
    );
  }
  test(
    'a lost commit ACK is reconciled by inspecting the actual rendered revision',
    () async {
      final remote = AckRenderer(delayAck: true);
      await remote.start(path);
      output.dispose();
      output = DesktopOutput(
        sessionPath: path,
        processExists: (_) async => true,
        healthInterval: const Duration(hours: 1),
      );
      try {
        await output.open();
        expect(await output.publish(frame(5, 'Confirmed by inspection')), 5);
        expect(output.connected, isTrue);
        expect(output.error, isNull);
        expect(output.recoveredFrame!.slide!.text, 'Confirmed by inspection');
      } finally {
        await remote.close();
      }
    },
  );
  test(
    'late ordinary timeout cannot make a newer emergency confirmation uncertain',
    () async {
      final remote = AckRenderer(uncertainCommit: true);
      await remote.start(path);
      output.dispose();
      output = DesktopOutput(
        sessionPath: path,
        processExists: (_) async => true,
        healthInterval: const Duration(hours: 1),
      );
      try {
        await output.open();
        final old = expectLater(
          output.publish(frame(1, 'Slow ordinary command')),
          throwsA(anything),
        );
        expect(
          await output.publish(const OutputFrame(revision: 2, emergency: true)),
          2,
        );
        await old;
        expect(output.connected, isTrue);
        expect(output.error, isNull);
        expect(output.recoveredFrame!.revision, 2);
      } finally {
        await remote.close();
      }
    },
  );
  test(
    'uncertain publication requires inspection but confirmed emergency remains available',
    () async {
      final remote = AckRenderer(uncertainCommit: true);
      await remote.start(path);
      output.dispose();
      output = DesktopOutput(
        sessionPath: path,
        processExists: (_) async => true,
        healthInterval: const Duration(hours: 1),
      );
      try {
        await output.open();
        await expectLater(
          output.publish(frame(1, 'Unknown outcome')),
          throwsA(anything),
        );
        expect(output.state, OutputConnectionState.unconfirmed);
        expect(output.canControl, isTrue);
        expect(
          await output.publish(const OutputFrame(revision: 2, emergency: true)),
          2,
        );
        expect(output.connected, isTrue);
        expect(output.error, isNull);
        expect(remote.current.mode, OutputMode.black);
      } finally {
        await remote.close();
      }
    },
  );
  test(
    'new renderer starts black, staged publication ACKs, and explicit close stops it',
    () async {
      await output.open();
      expect(starts, 1);
      expect(output.connected, isTrue);
      expect(output.recoveredFrame!.mode, OutputMode.black);
      expect(await output.publish(frame(1, 'Accepted')), 1);
      expect((await output.inspect())['frame'], frame(1, 'Accepted').toMap());
      await output.close();
      expect(backend.alive, isFalse);
      expect(output.state, OutputConnectionState.closed);
      expect(await RendererSession.read(path), isNull);
    },
  );
  test(
    'operator disconnect reattaches to surviving frame without publication',
    () async {
      await output.open();
      await output.publish(frame(9, 'Captured'));
      final session = output.sessionId;
      output.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      output = DesktopOutput(
        sessionPath: path,
        launchRenderer: launch,
        processExists: (_) async => backend.alive,
      );
      await output.open();
      expect(starts, 1);
      expect(output.sessionId, session);
      expect(output.recoveredFrame!.slide!.text, 'Captured');
      final live = LiveController(output);
      live.reconcileOutput(output.recoveredFrame!);
      expect(live.frame.revision, 9);
      expect(
        await live.goLive([frame(1, 'A new explicit draft').slide!], 0),
        isTrue,
      );
      expect(live.frame.revision, greaterThan(9));
      live.dispose();
    },
  );
  test(
    'startup recovery only inspects and never configures or republishes',
    () async {
      await output.open();
      await output.publish(frame(8, 'Hold on restart'));
      final count = backend.configurations;
      output.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      output = DesktopOutput(
        sessionPath: path,
        processExists: (_) async => backend.alive,
        launchRenderer: launch,
      );
      expect(await output.recoverExisting(), isTrue);
      expect(backend.configurations, count);
      expect(starts, 1);
      expect(output.recoveredFrame!.slide!.text, 'Hold on restart');
      expect(output.connected, isTrue);
    },
  );
  test('shutdown EOF succeeds only after the actual process is gone', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final session = RendererSession(
      sessionId: sessionSecret(16),
      token: sessionSecret(),
      port: server.port,
      processId: pid,
      createdAt: DateTime.now(),
    );
    await session.write(path);
    var alive = true;
    final peers = <LocalRpcPeer>[];
    server.listen((socket) {
      late LocalRpcPeer peer;
      peer = LocalRpcPeer(
        socket,
        onRequest: (method, args) async {
          if (method == 'shutdown') {
            alive = false;
            await peer.close();
            return null;
          }
          return {
            'protocol': 2,
            'renderSchema': renderSchemaVersion,
            'session': session.sessionId,
            'pid': pid,
            'frame': const OutputFrame(revision: 0).toMap(),
            'renderedRevision': 0,
            'configuration': const OutputConfiguration().toMap(),
            'window': {'visible': true, 'displayAvailable': true},
          };
        },
      );
      peers.add(peer);
    });
    output.dispose();
    output = DesktopOutput(
      sessionPath: path,
      processExists: (_) async => alive,
      launchRenderer: launch,
    );
    try {
      await output.open();
      await output.close();
      expect(alive, isFalse);
      expect(output.state, OutputConnectionState.closed);
    } finally {
      for (final peer in peers) {
        await peer.close();
      }
      await server.close();
    }
  });
  test(
    'native disconnect and reconnect never automatically rearm output',
    () async {
      await output.open(targetDisplayId: 'hdmi', fullscreen: true);
      await output.publish(frame(1, 'Hold'));
      backend.available = false;
      await backend.hide();
      await waitFor(() => output.state == OutputConnectionState.disarmed);
      backend.available = true;
      backend.events.add(await backend.status());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(output.connected, isFalse);
      expect(backend.visible, isFalse);
      expect(backend.configurations, 1);
      expect(state!.frame.slide!.text, 'Hold');
      await output.open(targetDisplayId: 'hdmi', fullscreen: true);
      expect(output.connected, isTrue);
      expect(backend.configurations, 2);
      expect(output.recoveredFrame!.slide!.text, 'Hold');
    },
  );
  test(
    'failed placement keeps healthy previous output and calibration',
    () async {
      await output.open(scale: .9);
      await output.publish(frame(1, 'Keep'));
      await expectLater(
        output.open(targetDisplayId: 'missing', fullscreen: true),
        throwsA(anything),
      );
      expect(output.connected, isTrue);
      expect(output.canvasScale, .9);
      expect(backend.visible, isTrue);
      expect(state!.frame.slide!.text, 'Keep');
      expect(output.opening, isFalse);
    },
  );
  test('unreachable live process is never replaced automatically', () async {
    final session = RendererSession(
      sessionId: sessionSecret(16),
      token: sessionSecret(),
      port: 1,
      processId: pid,
      createdAt: DateTime.now(),
    );
    await session.write(path);
    await expectLater(
      output.open(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('still running'),
        ),
      ),
    );
    expect(starts, 0);
    expect(output.opening, isFalse);
    expect((await RendererSession.read(path))!.sessionId, session.sessionId);
  });
  test(
    'corrupt discovery data refuses duplicate launch without deleting it',
    () async {
      await File(path).writeAsString('{corrupt');
      await expectLater(output.open(), throwsFormatException);
      expect(starts, 0);
      expect(await File(path).readAsString(), '{corrupt');
      expect(output.opening, isFalse);
    },
  );
  test(
    'stale dead session is replaced black and retains no old draft',
    () async {
      final session = RendererSession(
        sessionId: sessionSecret(16),
        token: sessionSecret(),
        port: 1,
        processId: 123,
        createdAt: DateTime.now(),
      );
      await session.write(path);
      output.dispose();
      output = DesktopOutput(
        sessionPath: path,
        launchRenderer: launch,
        processExists: (processId) async => processId == pid && backend.alive,
      );
      await output.open();
      expect(starts, 1);
      expect(output.sessionId, isNot(session.sessionId));
      expect(output.recoveredFrame!.slide, isNull);
      expect(output.recoveredFrame!.mode, OutputMode.black);
    },
  );
  test(
    'invalid configuration fails before spawning or touching session file',
    () async {
      await expectLater(output.open(scale: double.infinity), throwsA(anything));
      expect(starts, 0);
      expect(await File(path).exists(), isFalse);
    },
  );
  test(
    'new black renderer keeps previous safe slide available for explicit Restore',
    () async {
      await output.open();
      final live = LiveController(output);
      await live.goLive([frame(1, 'Prior live').slide!], 0);
      live.reconcileOutput(const OutputFrame(revision: 0));
      expect(live.frame.mode, OutputMode.black);
      expect(live.frame.slide!.text, 'Prior live');
      expect(
        state!.frame.mode,
        OutputMode.normal,
      ); // Reconciliation never writes.
      live.dispose();
    },
  );
  test(
    'normal output error does not clear a newer emergency confirmation',
    () async {
      await output.open();
      await output.publish(frame(1, 'First'));
      final before = jsonEncode(state!.frame.toMap());
      await expectLater(output.publish(frame(1, 'Stale')), throwsA(anything));
      expect(output.connected, isTrue);
      expect(jsonEncode(state!.frame.toMap()), before);
    },
  );
}
