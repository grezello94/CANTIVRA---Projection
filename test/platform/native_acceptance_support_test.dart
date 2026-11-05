import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/native_acceptance_support.dart';

void main() {
  test('timings retain all-run maxima and exact threshold counts', () {
    final timings = AcceptanceTimings(capacity: 2);
    timings.add(1000000);
    for (var index = 0; index < 19; index++) {
      timings.add(1000);
    }
    final result = timings.toMap();
    expect(result['count'], 20);
    expect(result['sampleCount'], 2);
    expect(result['p95Ms'], 1);
    expect(result['maxSampleMs'], 1);
    expect(result['maxAllRunMs'], 1000);
    expect(result['allRunSamplesOverThreshold'], 1);
    expect(result['allRunP95WithinThreshold'], isTrue);
    timings.add(50001);
    expect(timings.toMap()['allRunP95WithinThreshold'], isFalse);
  });

  test('empty timing window does not claim a performance pass', () {
    final timings = AcceptanceTimings();
    final result = timings.toMap();
    expect(result['p95Ms'], isNull);
    expect(result['maxAllRunMs'], isNull);
    expect(result['allRunP95WithinThreshold'], isNull);
    expect(() => timings.add(-1), throwsArgumentError);
    expect(() => AcceptanceTimings(capacity: 0), throwsArgumentError);
  });

  test(
    'relay drops sockets then forwards a fresh authenticated-style session',
    () async {
      final backend = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final active = <Socket>{};
      final backendSubscription = backend.listen((socket) {
        active.add(socket);
        void finish() {
          active.remove(socket);
          socket.destroy();
        }

        socket.listen(
          socket.add,
          onError: (Object _) => finish(),
          onDone: finish,
        );
      });
      final relay = await AcceptanceSocketRelay.start();
      relay.destinationPort = backend.port;
      Socket? first;
      Socket? second;
      try {
        first = await Socket.connect(InternetAddress.loopbackIPv4, relay.port);
        final firstFrames = StreamIterator(
          first
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter()),
        );
        first.writeln('first');
        expect(await firstFrames.moveNext(), isTrue);
        expect(firstFrames.current, 'first');
        relay.dropConnections();
        expect(
          await firstFrames.moveNext().timeout(const Duration(seconds: 2)),
          isFalse,
        );
        await firstFrames.cancel();
        second = await Socket.connect(InternetAddress.loopbackIPv4, relay.port);
        final secondFrames = StreamIterator(
          second
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter()),
        );
        second.writeln('second');
        expect(await secondFrames.moveNext(), isTrue);
        expect(secondFrames.current, 'second');
        expect(relay.acceptedConnections, 2);
        await relay.close();
        expect(
          await secondFrames.moveNext().timeout(const Duration(seconds: 2)),
          isFalse,
        );
        await secondFrames.cancel();
        await relay.close();
      } finally {
        first?.destroy();
        second?.destroy();
        await relay.close();
        for (final socket in active.toList()) {
          socket.destroy();
        }
        await backendSubscription.cancel();
        await backend.close();
      }
    },
  );
}
