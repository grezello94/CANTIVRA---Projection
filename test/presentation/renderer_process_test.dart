import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cantivra/domain/models.dart';
import 'package:cantivra/platform/local_rpc.dart';
import 'package:cantivra/presentation/live_controller.dart';
import 'package:cantivra/presentation/renderer_runtime.dart';
import 'package:cantivra/presentation/renderer_session.dart';
import 'package:cantivra/presentation/renderer_state.dart';
import 'package:cantivra/presentation/slides.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class Backend implements RendererBackend {
  bool alive = true;
  bool visible = false;
  bool available = true;
  String? target;
  bool fullscreen = false;
  int configurations = 0;
  final events = StreamController<Map<String, Object?>>.broadcast();
  @override
  Stream<Map<String, Object?>> get changes => events.stream;
  @override
  Future<Map<String, Object?>> status() async => {
    'role': 'output',
    'visible': visible,
    'displayId': target,
    'fullscreen': fullscreen,
    'displayAvailable': available,
  };
  @override
  Future<void> configure(OutputConfiguration configuration) async {
    if (configuration.displayId == 'missing') {
      throw PlatformException(code: 'DISPLAY_UNAVAILABLE');
    }
    if (configuration.displayId == 'primary') {
      throw PlatformException(code: 'PRIMARY_DISPLAY_RESERVED');
    }
    target = configuration.displayId;
    fullscreen = configuration.fullscreen;
    configurations++;
    visible = true;
    available = true;
  }

  @override
  Future<void> hide() async {
    visible = false;
    events.add(await status());
  }

  @override
  Future<void> close() async {
    alive = false;
  }
}

PresentationSlide slide(String text) => PresentationSlide(
  id: text,
  sourceId: 'source',
  title: 'Title',
  label: 'Verse',
  text: text,
  theme: const PresentationTheme(),
);
OutputFrame frame(int revision, String text) => OutputFrame(
  revision: revision,
  slide: slide(text),
  mode: OutputMode.normal,
);
Matcher rpcError(String code) =>
    isA<LocalRpcException>().having((e) => e.code, 'code', code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sessionId = '0123456789abcdef0123456789abcdef';
  const token =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
  group('Renderer staging and ordering', () {
    late RendererState state;
    setUp(
      () =>
          state = RendererState(sessionId: sessionId, frameReady: () async {}),
    );
    tearDown(() => state.dispose());
    Map<String, Object?> args(OutputFrame candidate) => {
      'session': sessionId,
      'frame': candidate.toMap(),
    };
    test(
      'prepare does not mutate output; commit acknowledges readiness',
      () async {
        final wait = Completer<void>();
        final delayed = RendererState(
          sessionId: sessionId,
          frameReady: () => wait.future,
        );
        delayed.prepare(args(frame(1, 'First')));
        expect(delayed.frame.mode, OutputMode.black);
        var acknowledged = false;
        final commit = delayed
            .commit({'session': sessionId, 'revision': 1})
            .then((result) {
              acknowledged = true;
              return result;
            });
        expect(delayed.frame.slide!.text, 'First');
        expect(delayed.renderedRevision, 0);
        expect(acknowledged, isFalse);
        wait.complete();
        expect((await commit)['renderedRevision'], 1);
        delayed.dispose();
      },
    );
    test(
      'wrong session, cancelled and stale revisions cannot alter live content',
      () async {
        expect(
          () => state.prepare({...args(frame(1, 'Wrong')), 'session': 'old'}),
          throwsA(rpcError('wrong_session')),
        );
        state.prepare(args(frame(1, 'First')));
        await state.commit({'session': sessionId, 'revision': 1});
        expect(
          () => state.prepare(args(frame(1, 'Stale'))),
          throwsA(rpcError('stale_revision')),
        );
        state.prepare(args(frame(2, 'Cancelled')));
        state.cancel({'session': sessionId, 'revision': 2});
        await expectLater(
          state.commit({'session': sessionId, 'revision': 2}),
          throwsA(rpcError('not_prepared')),
        );
        expect(state.frame.slide!.text, 'First');
      },
    );
    test(
      'invalid measured frame leaves last accepted frame unchanged',
      () async {
        state.prepare(args(frame(1, 'First')));
        await state.commit({'session': sessionId, 'revision': 1});
        expect(
          () => state.prepare(
            args(frame(2, List.filled(100, 'Too many lines').join('\n'))),
          ),
          throwsFormatException,
        );
        expect(state.frame.slide!.text, 'First');
      },
    );
    test(
      'emergency supersedes an awaiting commit and discards prepared frames',
      () async {
        final ready = Completer<void>();
        final delayed = RendererState(
          sessionId: sessionId,
          frameReady: () => ready.future,
        );
        delayed.prepare(args(frame(1, 'Ordinary')));
        final ordinary = delayed.commit({'session': sessionId, 'revision': 1});
        final ordinaryResult = expectLater(
          ordinary,
          throwsA(rpcError('superseded')),
        );
        delayed.prepare(args(frame(2, 'Prepared draft')));
        final emergency = delayed.emergency(
          args(const OutputFrame(revision: 3, emergency: true)),
        );
        expect(delayed.frame.mode, OutputMode.black);
        ready.complete();
        await ordinaryResult;
        expect((await emergency)['renderedRevision'], 3);
        await expectLater(
          delayed.commit({'session': sessionId, 'revision': 2}),
          throwsA(rpcError('not_prepared')),
        );
        delayed.dispose();
      },
    );
    test(
      'freeze is enforced in renderer independently of operator UI',
      () async {
        final frozen = frame(1, 'Captured').copyWith(frozen: true);
        state.prepare(args(frozen));
        await state.commit({'session': sessionId, 'revision': 1});
        expect(
          () => state.prepare(args(frame(2, 'Changed'))),
          throwsA(rpcError('frozen')),
        );
        state.prepare(
          args(frozen.copyWith(revision: 2, mode: OutputMode.black)),
        );
        await state.commit({'session': sessionId, 'revision': 2});
        expect(state.frame.frozen, isTrue);
        state.prepare(args(frozen.copyWith(revision: 3, frozen: false)));
        await state.commit({'session': sessionId, 'revision': 3});
        expect(state.frame.frozen, isFalse);
      },
    );
    test(
      'configuration rejects nonfinite scaling, excessive insets and implicit fullscreen',
      () {
        for (final map in [
          {'scale': .5},
          {'scale': double.nan},
          {'safeInset': .2},
          {'fullscreen': true},
        ]) {
          expect(
            () => OutputConfiguration.fromMap(map),
            throwsA(rpcError('invalid_configuration')),
          );
        }
        expect(
          OutputConfiguration.fromMap({
            'scale': .9,
            'safeInset': .02,
          }).canvasScale,
          closeTo(.864, .000001),
        );
      },
    );
  });

  group('Authenticated process control over real sockets', () {
    late Directory directory;
    late RendererRuntime runtime;
    late RendererState state;
    late Backend backend;
    var frameWaits = 0;
    final peers = <LocalRpcPeer>[];
    Future<LocalRpcPeer> connect({
      String key = token,
      int? renderSchema = renderSchemaVersion,
    }) async {
      final peer = LocalRpcPeer(
        await Socket.connect(
          InternetAddress.loopbackIPv4,
          runtime.session.port,
        ),
      );
      peers.add(peer);
      await peer.call('hello', {
        'protocol': 2,
        'renderSchema': ?renderSchema,
        'session': sessionId,
        'token': key,
      });
      return peer;
    }

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('renderer-runtime-');
      backend = Backend();
      frameWaits = 0;
      state = RendererState(
        sessionId: sessionId,
        frameReady: () async {
          frameWaits++;
        },
      );
      runtime = RendererRuntime(
        launch: RendererLaunch(
          sessionPath: '${directory.path}/session.json',
          sessionId: sessionId,
          token: token,
        ),
        state: state,
        backend: backend,
      );
      await runtime.start();
    });
    tearDown(() async {
      for (final peer in peers) {
        await peer.close();
      }
      peers.clear();
      await runtime.dispose();
      state.dispose();
      await backend.events.close();
      await directory.delete(recursive: true);
    });
    test(
      'authentication rejects wrong secrets and unauthenticated commands',
      () async {
        await expectLater(
          connect(key: 'wrong'),
          throwsA(rpcError('unauthorized')),
        );
        final peer = LocalRpcPeer(
          await Socket.connect(
            InternetAddress.loopbackIPv4,
            runtime.session.port,
          ),
        );
        peers.add(peer);
        await expectLater(
          peer.call('prepare', {
            'session': sessionId,
            'frame': frame(1, 'Attack').toMap(),
          }),
          throwsA(rpcError('unauthorized')),
        );
        expect(state.frame.revision, 0);
      },
    );
    test('only one authenticated operator can control a session', () async {
      final owner = await connect();
      await expectLater(connect(), throwsA(rpcError('operator_connected')));
      expect(
        (await owner.call('inspect', {'session': sessionId}) as Map)['pid'],
        pid,
      );
    });
    test(
      'authenticated diagnostics report real positive process memory',
      () async {
        final owner = await connect();
        final info = await owner.call('inspect', {'session': sessionId}) as Map;
        final resources = info['resources'] as Map;
        expect(resources['rssBytes'], greaterThan(0));
        expect(
          resources['maxRssBytes'],
          greaterThanOrEqualTo(resources['rssBytes']),
        );
        expect(state.frame.revision, 0);
      },
    );
    test(
      'incompatible operators gain no authority and preserve the last frame',
      () async {
        final original = await connect();
        await original.call('prepare', {
          'session': sessionId,
          'frame': frame(6, 'Last known good frame').toMap(),
        });
        await original.call('commit', {'session': sessionId, 'revision': 6});
        await original.close();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        for (final schema in <int?>[null, 1, renderSchemaVersion + 1]) {
          await expectLater(
            connect(renderSchema: schema),
            throwsA(rpcError('unsupported_renderer_schema')),
          );
          final rejected = peers.last;
          await expectLater(
            rejected.call('emergency', {
              'session': sessionId,
              'frame': const OutputFrame(revision: 7, emergency: true).toMap(),
            }),
            throwsA(rpcError('unauthorized')),
          );
          expect(
            state.frame.toMap(),
            frame(6, 'Last known good frame').toMap(),
          );
          expect(backend.configurations, 0);
          expect(backend.alive, isTrue);
          await rejected.close();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final replacement = await connect();
        final info =
            await replacement.call('inspect', {'session': sessionId}) as Map;
        expect(info['renderSchema'], renderSchemaVersion);
        expect(info['frame'], frame(6, 'Last known good frame').toMap());
      },
    );
    test(
      'disconnect retains exact frame and permits a new authenticated operator',
      () async {
        final owner = await connect();
        await owner.call('prepare', {
          'session': sessionId,
          'frame': frame(1, 'Keep').toMap(),
        });
        await owner.call('commit', {'session': sessionId, 'revision': 1});
        await owner.close();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final replacement = await connect();
        expect(
          (await replacement.call('inspect', {'session': sessionId})
              as Map)['frame'],
          frame(1, 'Keep').toMap(),
        );
        expect(backend.alive, isTrue);
      },
    );
    test(
      'native missing/primary errors retain configuration and frame',
      () async {
        final owner = await connect();
        await owner.call('configure', {'session': sessionId, 'scale': .9});
        await owner.call('prepare', {
          'session': sessionId,
          'frame': frame(1, 'Keep').toMap(),
        });
        await owner.call('commit', {'session': sessionId, 'revision': 1});
        await expectLater(
          owner.call('configure', {
            'session': sessionId,
            'displayId': 'missing',
            'fullscreen': true,
          }),
          throwsA(rpcError('DISPLAY_UNAVAILABLE')),
        );
        await expectLater(
          owner.call('configure', {
            'session': sessionId,
            'displayId': 'primary',
            'fullscreen': true,
          }),
          throwsA(rpcError('PRIMARY_DISPLAY_RESERVED')),
        );
        expect(state.configuration.scale, .9);
        expect(state.frame.slide!.text, 'Keep');
      },
    );
    test(
      'same healthy placement does not hide or relocate when applying calibration',
      () async {
        final owner = await connect();
        await owner.call('configure', {'session': sessionId});
        expect(backend.configurations, 1);
        await owner.call('configure', {'session': sessionId, 'scale': .85});
        expect(backend.configurations, 1);
        expect(backend.visible, isTrue);
        expect(state.configuration.scale, .85);
      },
    );
    test(
      'identical healthy configuration needs no new frame acknowledgement',
      () async {
        final owner = await connect();
        await owner.call('configure', {
          'session': sessionId,
          'scale': .9,
          'safeInset': .02,
        });
        expect(frameWaits, 1);
        final info =
            await owner.call('configure', {
                  'session': sessionId,
                  'scale': .9,
                  'safeInset': .02,
                })
                as Map;
        expect(backend.configurations, 1);
        expect(frameWaits, 1);
        expect((info['configuration'] as Map)['scale'], .9);
        await owner.call('configure', {
          'session': sessionId,
          'scale': .9,
          'safeInset': .03,
        });
        expect(backend.configurations, 1);
        expect(
          frameWaits,
          2,
          reason:
              'A changed calibration still needs its paint acknowledgement.',
        );
      },
    );
    test(
      'native status is forwarded without automatically rearming a display',
      () async {
        final owner = await connect();
        final statusEvent = Completer<Map<String, Object?>>();
        owner.onEvent = (name, args) {
          if (name == 'outputStatus' && !statusEvent.isCompleted) {
            statusEvent.complete(args);
          }
        };
        await owner.call('configure', {'session': sessionId});
        await backend.hide();
        final notification = await statusEvent.future;
        expect((notification['window'] as Map)['visible'], isFalse);
        expect(backend.configurations, 1);
      },
    );
    test(
      'malformed prepared frame is a typed error, not a renderer failure',
      () async {
        final owner = await connect();
        await expectLater(
          owner.call('prepare', {
            'session': sessionId,
            'frame': {'protocol': 99},
          }),
          throwsA(rpcError('invalid_frame')),
        );
        expect(
          (await owner.call('inspect', {'session': sessionId})
              as Map)['renderedRevision'],
          0,
        );
      },
    );
  });

  group('Session descriptors', () {
    test('launch arguments reject missing tokens and relative files', () {
      expect(RendererLaunch.parse(const []), isNull);
      expect(
        () => RendererLaunch.parse(
          [
            rendererRoleArgument,
            '--cantivra-session-file=relative.json',
            '--cantivra-session=$sessionId',
          ],
          environment: {rendererTokenEnvironment: token},
        ),
        throwsFormatException,
      );
      expect(
        () => RendererLaunch.parse([
          rendererRoleArgument,
          '--cantivra-session-file=/tmp/session.json',
          '--cantivra-session=$sessionId',
        ], environment: const {}),
        throwsFormatException,
      );
      expect(secretsMatch(token, token), isTrue);
      expect(secretsMatch(token, 'x'), isFalse);
    });
    test(
      'private atomic descriptor preserves newer sessions during old cleanup',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'session-file-',
        );
        final path = '${directory.path}/session.json';
        final first = RendererSession(
          sessionId: sessionId,
          token: token,
          port: 12345,
          processId: pid,
          createdAt: DateTime.now(),
        );
        await first.write(path);
        expect((await RendererSession.read(path))!.toMap(), first.toMap());
        if (Platform.isMacOS) {
          final permissions = await Process.run('/usr/bin/stat', [
            '-f',
            '%Lp',
            path,
          ]);
          expect(permissions.stdout.toString().trim(), '600');
        }
        final second = RendererSession(
          sessionId: '1123456789abcdef0123456789abcdef',
          token: token,
          port: 12346,
          processId: pid,
          createdAt: DateTime.now(),
        );
        await second.write(path);
        await first.removeIfCurrent(path);
        expect((await RendererSession.read(path))!.sessionId, second.sessionId);
        expect(
          directory.listSync().where((file) => file.path.endsWith('.tmp')),
          isEmpty,
        );
        await second.removeIfCurrent(path);
        expect(await RendererSession.read(path), isNull);
        await directory.delete(recursive: true);
      },
    );
    test(
      'oversized or unsupported descriptors fail without modifying data',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'session-invalid-',
        );
        final file = File('${directory.path}/session.json');
        await file.writeAsString('x' * 16385);
        await expectLater(
          RendererSession.read(file.path),
          throwsFormatException,
        );
        await file.writeAsString(jsonEncode({'protocol': 1}));
        await expectLater(
          RendererSession.read(file.path),
          throwsFormatException,
        );
        expect(await file.readAsString(), jsonEncode({'protocol': 1}));
        await directory.delete(recursive: true);
      },
    );
  });
}
