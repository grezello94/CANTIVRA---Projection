import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cantivra/platform/local_rpc.dart';
import 'package:flutter_test/flutter_test.dart';

Future<({Socket left, Socket right})> socketPair() async {
  final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final accepted = listener.first;
  final left = await Socket.connect(
    InternetAddress.loopbackIPv4,
    listener.port,
  );
  final right = await accepted;
  await listener.close();
  addTearDown(() {
    left.destroy();
    right.destroy();
  });
  return (left: left, right: right);
}

LocalRpcPeer peer(
  Socket socket, {
  Duration timeout = const Duration(seconds: 3),
  int maxMessageBytes = 1048576,
  int maxPendingRequests = 32,
  int maxIncomingRequests = 32,
  LocalRpcRequestHandler? onRequest,
  LocalRpcEventHandler? onEvent,
}) {
  final connection = LocalRpcPeer(
    socket,
    timeout: timeout,
    maxMessageBytes: maxMessageBytes,
    maxPendingRequests: maxPendingRequests,
    maxIncomingRequests: maxIncomingRequests,
    onRequest: onRequest,
    onEvent: onEvent,
  );
  addTearDown(connection.close);
  return connection;
}

TypeMatcher<LocalRpcException> rpcError(String code) =>
    isA<LocalRpcException>().having((error) => error.code, 'code', code);

Future<void> send(Socket socket, Map<String, Object?> envelope) async {
  socket.write('${jsonEncode(envelope)}\n');
  await socket.flush();
}

Map<String, Object?> event(
  String name, [
  Map<String, Object?> payload = const {},
]) => {'protocol': 2, 'type': 'event', 'name': name, 'payload': payload};

Map<String, Object?> request(int id, String method) => {
  'protocol': 2,
  'type': 'request',
  'id': id,
  'method': method,
  'args': <String, Object?>{},
};

void main() {
  test(
    'calls round-trip nested data, null and Unicode over real sockets',
    () async {
      final sockets = await socketPair();
      final client = peer(sockets.left);
      peer(
        sockets.right,
        onRequest: (method, args) =>
            method == 'empty' ? null : {'method': method, 'args': args},
      );
      expect(
        await client.call('echo', {
          'text': 'அமைதி 🕊️ शांति',
          'nested': {
            'list': [1, true, null],
          },
        }),
        {
          'method': 'echo',
          'args': {
            'text': 'அமைதி 🕊️ शांति',
            'nested': {
              'list': [1, true, null],
            },
          },
        },
      );
      expect(await client.call('empty'), isNull);
    },
  );

  test('both peers can initiate requests on the same connection', () async {
    final sockets = await socketPair();
    final left = peer(sockets.left, onRequest: (_, args) => args['left']);
    final right = peer(sockets.right, onRequest: (_, args) => args['right']);
    expect(
      await Future.wait([
        left.call('right', {'right': 10}),
        right.call('left', {'left': 20}),
      ]),
      [10, 20],
    );
  });

  test(
    'partial multibyte input is decoded only after its line is complete',
    () async {
      final sockets = await socketPair();
      final received = Completer<Map<String, Object?>>();
      final client = peer(
        sockets.left,
        onEvent: (_, payload) => received.complete(payload),
      );
      final bytes = utf8.encode(
        '${jsonEncode(event('text', {'value': '🕊️'}))}\n',
      );
      final split = bytes.indexOf(0xf0) + 2;
      sockets.right.add(bytes.sublist(0, split));
      await sockets.right.flush();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(received.isCompleted, isFalse);
      expect(client.isClosed, isFalse);
      sockets.right.add(bytes.sublist(split));
      await sockets.right.flush();
      expect(await received.future.timeout(const Duration(seconds: 2)), {
        'value': '🕊️',
      });
    },
  );

  test(
    'multiple complete lines and a partial trailing line are independent',
    () async {
      final sockets = await socketPair();
      final names = <String>[];
      final received = Completer<void>();
      peer(
        sockets.left,
        onEvent: (name, _) {
          names.add(name);
          if (names.length == 3) received.complete();
        },
      );
      final last = jsonEncode(event('three'));
      sockets.right.write(
        '${jsonEncode(event('one'))}\n'
        '${jsonEncode(event('two'))}\n${last.substring(0, 12)}',
      );
      await sockets.right.flush();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(names, ['one', 'two']);
      sockets.right.write('${last.substring(12)}\n');
      await sockets.right.flush();
      await received.future.timeout(const Duration(seconds: 2));
      expect(names, ['one', 'two', 'three']);
    },
  );

  test('outgoing byte limit counts UTF-8, not Dart character length', () async {
    final sockets = await socketPair();
    final client = peer(sockets.left, maxMessageBytes: 160);
    final received = Completer<void>();
    peer(sockets.right, onEvent: (_, _) => received.complete());
    expect(
      () => client.emit('too-large', {'text': '🕊' * 60}),
      throwsA(rpcError('message_too_large')),
    );
    expect(client.isClosed, isFalse);
    client.emit('small', {});
    await received.future.timeout(const Duration(seconds: 2));
  });

  test(
    'oversized unterminated input closes before JSON decoding and fails calls',
    () async {
      final sockets = await socketPair();
      final client = peer(sockets.left, maxMessageBytes: 160);
      final pending = expectLater(
        client.call('waiting'),
        throwsA(rpcError('message_too_large')),
      );
      sockets.right.add(List.filled(161, 0x78));
      await sockets.right.flush();
      await pending;
      await client.done;
      expect(client.isClosed, isTrue);
    },
  );

  test('byte limit also applies to a complete oversized line', () async {
    final sockets = await socketPair();
    final client = peer(sockets.left, maxMessageBytes: 160);
    sockets.right.write('${jsonEncode(event('large', {'text': 'é' * 100}))}\n');
    await sockets.right.flush();
    await client.done.timeout(const Duration(seconds: 2));
    expect(client.isClosed, isTrue);
  });

  test(
    'remote disconnect fails every pending request and close is idempotent',
    () async {
      final sockets = await socketPair();
      final client = peer(sockets.left);
      final first = expectLater(
        client.call('one'),
        throwsA(rpcError('disconnected')),
      );
      final second = expectLater(
        client.call('two'),
        throwsA(rpcError('disconnected')),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      sockets.right.destroy();
      await Future.wait([first, second]);
      await client.done;
      await client.close();
      await client.close();
      expect(client.isClosed, isTrue);
      await expectLater(
        client.call('after-close'),
        throwsA(rpcError('closed')),
      );
      expect(() => client.emit('after-close', {}), throwsA(rpcError('closed')));
    },
  );

  test(
    'a timed-out call is removed and a late valid response is ignored',
    () async {
      final sockets = await socketPair();
      final observed = Completer<void>();
      final client = peer(
        sockets.left,
        timeout: const Duration(milliseconds: 30),
        onEvent: (_, _) => observed.complete(),
      );
      await expectLater(client.call('slow'), throwsA(rpcError('timeout')));
      await send(sockets.right, {
        'protocol': 2,
        'type': 'response',
        'id': 1,
        'result': 'late',
      });
      await send(sockets.right, event('still-open'));
      await observed.future.timeout(const Duration(seconds: 2));
      expect(client.isClosed, isFalse);
    },
  );

  test('pending request cap recovers after completion', () async {
    final sockets = await socketPair();
    final client = peer(sockets.left, maxPendingRequests: 1);
    final first = client.call('one');
    await expectLater(client.call('too-many'), throwsA(rpcError('busy')));
    await send(sockets.right, {
      'protocol': 2,
      'type': 'response',
      'id': 1,
      'result': 'done',
    });
    expect(await first, 'done');
    final next = client.call('next');
    await send(sockets.right, {
      'protocol': 2,
      'type': 'response',
      'id': 2,
      'result': true,
    });
    expect(await next, isTrue);
  });

  test(
    'remote typed errors propagate and ordinary errors are sanitized',
    () async {
      final sockets = await socketPair();
      final client = peer(sockets.left);
      peer(
        sockets.right,
        onRequest: (method, _) {
          if (method == 'typed') {
            throw const LocalRpcException(
              'not_authenticated',
              'Authenticate first.',
            );
          }
          if (method == 'generic') throw StateError('secret detail');
          return 'healthy';
        },
      );
      await expectLater(
        client.call('typed'),
        throwsA(
          rpcError(
            'not_authenticated',
          ).having((error) => error.message, 'message', 'Authenticate first.'),
        ),
      );
      await expectLater(
        client.call('generic'),
        throwsA(
          rpcError('handler_error').having(
            (error) => error.message,
            'message',
            isNot(contains('secret')),
          ),
        ),
      );
      expect(await client.call('normal'), 'healthy');
    },
  );

  test(
    'an emergency request is handled while an ordinary request awaits preparation',
    () async {
      final sockets = await socketPair();
      final preparation = Completer<Object?>();
      final started = Completer<void>();
      final client = peer(sockets.left);
      peer(
        sockets.right,
        onRequest: (method, _) {
          if (method == 'prepare') {
            started.complete();
            return preparation.future;
          }
          return 'black';
        },
      );
      final ordinary = client.call('prepare');
      await started.future;
      expect(await client.call('emergency'), 'black');
      expect(preparation.isCompleted, isFalse);
      preparation.complete('prepared');
      expect(await ordinary, 'prepared');
    },
  );

  test(
    'incoming request cap returns busy without breaking accepted work',
    () async {
      final sockets = await socketPair();
      final waiting = Completer<Object?>();
      final started = Completer<void>();
      final client = peer(sockets.left);
      peer(
        sockets.right,
        maxIncomingRequests: 1,
        onRequest: (_, _) {
          started.complete();
          return waiting.future;
        },
      );
      final accepted = client.call('accepted');
      await started.future;
      await expectLater(client.call('overflow'), throwsA(rpcError('busy')));
      waiting.complete('complete');
      expect(await accepted, 'complete');
      expect(client.isClosed, isFalse);
    },
  );

  test(
    'handlers may be attached later and missing methods return typed errors',
    () async {
      final sockets = await socketPair();
      final client = peer(sockets.left);
      final server = peer(sockets.right);
      await expectLater(
        client.call('missing'),
        throwsA(rpcError('method_not_found')),
      );
      server.onRequest = (method, args) => '${method}_${args['value']}';
      expect(await client.call('attached', {'value': 7}), 'attached_7');
    },
  );

  test(
    'notification observer errors do not become uncaught async failures',
    () async {
      final sockets = await socketPair();
      final done = Completer<void>();
      var received = 0;
      final client = peer(
        sockets.left,
        onEvent: (_, _) async {
          received++;
          if (received == 1) throw StateError('optional observer failed');
          done.complete();
        },
      );
      await send(sockets.right, event('first'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await send(sockets.right, event('second'));
      await done.future.timeout(const Duration(seconds: 2));
      expect(client.isClosed, isFalse);
    },
  );

  test(
    'invalid outgoing JSON is rejected locally without closing the connection',
    () async {
      final sockets = await socketPair();
      final client = peer(sockets.left);
      peer(sockets.right, onRequest: (_, _) => true);
      await expectLater(
        client.call('bad', {'date': DateTime.utc(2026)}),
        throwsA(rpcError('invalid_message')),
      );
      expect(await client.call('healthy'), isTrue);
    },
  );

  test(
    'notification bursts cannot allocate an unbounded outgoing queue',
    () async {
      final sockets = await socketPair();
      final received = Completer<void>();
      var count = 0;
      final client = peer(
        sockets.left,
        maxPendingRequests: 1,
        maxIncomingRequests: 1,
      );
      peer(
        sockets.right,
        onEvent: (_, _) {
          count++;
          if (count == 2) received.complete();
        },
      );
      client.emit('first', {});
      client.emit('second', {});
      expect(() => client.emit('overflow', {}), throwsA(rpcError('busy')));
      await received.future.timeout(const Duration(seconds: 2));
      expect(client.isClosed, isFalse);
    },
  );

  test(
    'unknown valid response IDs are harmless and do not create state',
    () async {
      final sockets = await socketPair();
      final received = Completer<void>();
      final client = peer(sockets.left, onEvent: (_, _) => received.complete());
      await send(sockets.right, {
        'protocol': 2,
        'type': 'response',
        'id': 999,
        'result': 'unsolicited',
      });
      await send(sockets.right, event('healthy'));
      await received.future.timeout(const Duration(seconds: 2));
      expect(client.isClosed, isFalse);
    },
  );

  final malformed = <String, List<int>>{
    'bad UTF-8': [0xc3, 0x28, 10],
    'empty line': [10],
    'invalid JSON': utf8.encode('{broken}\n'),
    'nonobject envelope': utf8.encode('[]\n'),
    'wrong protocol': utf8.encode(
      '${jsonEncode({...event('bad'), 'protocol': 1})}\n',
    ),
    'noninteger protocol': utf8.encode(
      '${jsonEncode({...event('bad'), 'protocol': 2.0})}\n',
    ),
    'unknown type': utf8.encode(
      '${jsonEncode({'protocol': 2, 'type': 'unknown'})}\n',
    ),
    'zero ID': utf8.encode('${jsonEncode(request(0, 'bad'))}\n'),
    'negative ID': utf8.encode('${jsonEncode(request(-1, 'bad'))}\n'),
    'noninteger ID': utf8.encode(
      '${jsonEncode({...request(1, 'bad'), 'id': 1.5})}\n',
    ),
    'nonobject args': utf8.encode(
      '${jsonEncode({...request(1, 'bad'), 'args': []})}\n',
    ),
    'empty method': utf8.encode('${jsonEncode(request(1, ''))}\n'),
    'nonobject event payload': utf8.encode(
      '${jsonEncode({...event('bad'), 'payload': []})}\n',
    ),
    'response with no result': utf8.encode(
      '${jsonEncode({'protocol': 2, 'type': 'response', 'id': 1})}\n',
    ),
    'response with both result and error': utf8.encode(
      '${jsonEncode({
        'protocol': 2,
        'type': 'response',
        'id': 1,
        'result': 5,
        'error': {'code': 'bad', 'message': 'bad'},
      })}\n',
    ),
    'malformed error': utf8.encode(
      '${jsonEncode({
        'protocol': 2,
        'type': 'response',
        'id': 1,
        'error': {'code': 7, 'message': 'bad'},
      })}\n',
    ),
  };
  for (final entry in malformed.entries) {
    test('closes malformed connection: ${entry.key}', () async {
      final sockets = await socketPair();
      final client = peer(sockets.left);
      final pending = expectLater(
        client.call('waiting'),
        throwsA(rpcError('protocol_error')),
      );
      sockets.right.add(entry.value);
      await sockets.right.flush();
      await pending;
      await client.done;
      expect(client.isClosed, isTrue);
    });
  }

  test(
    'duplicate in-flight request ID closes rather than running side effect twice',
    () async {
      final sockets = await socketPair();
      final waiting = Completer<Object?>();
      var calls = 0;
      final server = peer(
        sockets.left,
        onRequest: (_, _) {
          calls++;
          return waiting.future;
        },
      );
      final bytes = '${jsonEncode(request(1, 'once'))}\n';
      sockets.right.write('$bytes$bytes');
      await sockets.right.flush();
      await server.done.timeout(const Duration(seconds: 2));
      expect(calls, 1);
      waiting.complete(null);
    },
  );

  test('truncated EOF closes and pending requests cannot hang', () async {
    final sockets = await socketPair();
    final client = peer(sockets.left);
    final pending = expectLater(
      client.call('waiting'),
      throwsA(rpcError('protocol_error')),
    );
    sockets.right.write('{"protocol":');
    await sockets.right.flush();
    await sockets.right.close();
    await pending;
    expect(client.isClosed, isTrue);
  });
}
