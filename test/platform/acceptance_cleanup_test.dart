import 'dart:io';

import 'package:cantivra/platform/local_rpc.dart';
import 'package:cantivra/presentation/renderer_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/acceptance_cleanup.dart';

RendererSession fixture(int port) => RendererSession(
  sessionId: 'a' * 32,
  token: 'b' * 64,
  port: port,
  processId: 123,
  createdAt: DateTime.utc(2026),
);

void main() {
  test(
    'read-only host check distinguishes current and absent process',
    () async {
      if (!Platform.isMacOS && !Platform.isWindows) return;
      expect(await acceptanceProcessRunning(pid), isTrue);
      final child = await Process.start(
        Platform.isMacOS ? '/usr/bin/true' : 'cmd.exe',
        Platform.isMacOS ? const [] : const ['/c', 'exit', '0'],
      );
      await child.exitCode;
      expect(await acceptanceProcessRunning(child.pid), isFalse);
      await expectLater(acceptanceProcessRunning(0), throwsArgumentError);
    },
  );

  test('already exited renderer needs no socket connection', () async {
    var checks = 0;
    await shutdownAcceptanceRenderer(
      fixture(1),
      isProcessRunning: (_) async {
        checks++;
        return false;
      },
    );
    expect(checks, 1);
  });

  test(
    'cleanup retries prior operator race and verifies exit after lost ACK',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final session = fixture(server.port);
      final peers = <LocalRpcPeer>[];
      var connections = 0;
      var alive = true;
      var shutdowns = 0;
      final subscription = server.listen((socket) {
        connections++;
        final connection = connections;
        late LocalRpcPeer peer;
        peer = LocalRpcPeer(
          socket,
          onRequest: (method, args) async {
            if (method == 'hello') {
              expect(args['token'], session.token);
              expect(args['renderSchema'], renderSchemaVersion);
              if (connection <= 2) {
                throw const LocalRpcException(
                  'operator_connected',
                  'Closing peer',
                );
              }
              return {'session': session.sessionId, 'pid': session.processId};
            }
            expect(method, 'shutdown');
            expect(args['session'], session.sessionId);
            shutdowns++;
            alive = false;
            await peer.close(); // Native exit can beat the shutdown response.
            return null;
          },
        );
        peers.add(peer);
      });
      try {
        await shutdownAcceptanceRenderer(
          session,
          isProcessRunning: (_) async => alive,
        );
        expect(connections, 3);
        expect(shutdowns, 1);
        expect(alive, isFalse);
      } finally {
        for (final peer in peers) {
          await peer.close();
        }
        await subscription.cancel();
        await server.close();
      }
    },
  );

  test(
    'failed authentication is not retried and cannot authorize shutdown',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <LocalRpcPeer>[];
      var requests = 0;
      final subscription = server.listen((socket) {
        final peer = LocalRpcPeer(
          socket,
          onRequest: (method, args) {
            requests++;
            expect(method, 'hello');
            throw const LocalRpcException('unauthorized', 'Rejected');
          },
        );
        peers.add(peer);
      });
      try {
        await expectLater(
          shutdownAcceptanceRenderer(
            fixture(server.port),
            isProcessRunning: (_) async => true,
          ),
          throwsA(
            isA<LocalRpcException>().having(
              (e) => e.code,
              'code',
              'unauthorized',
            ),
          ),
        );
        expect(requests, 1);
      } finally {
        for (final peer in peers) {
          await peer.close();
        }
        await subscription.cancel();
        await server.close();
      }
    },
  );
}
