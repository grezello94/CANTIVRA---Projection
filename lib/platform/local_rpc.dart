import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

typedef LocalRpcRequestHandler =
    FutureOr<Object?> Function(String method, Map<String, Object?> args);
typedef LocalRpcEventHandler =
    FutureOr<void> Function(String event, Map<String, Object?> payload);

class LocalRpcException implements Exception {
  const LocalRpcException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'LocalRpcException($code): $message';
}

/// A protocol-v2, bounded UTF-8 NDJSON connection between local processes.
///
/// [maxMessageBytes] excludes the terminating LF. Both the incomplete byte
/// buffer and each complete outgoing message are bounded before JSON decoding.
/// Pending calls, concurrent incoming work and queued writes are also bounded.
/// Authentication and presentation-session rules belong to the application.
class LocalRpcPeer {
  LocalRpcPeer(
    this._socket, {
    this.timeout = const Duration(seconds: 3),
    this.maxMessageBytes = 1048576,
    this.maxPendingRequests = 32,
    this.maxIncomingRequests = 32,
    this.onRequest,
    this.onEvent,
  }) {
    if (timeout <= Duration.zero ||
        maxMessageBytes <= 0 ||
        maxPendingRequests <= 0 ||
        maxIncomingRequests <= 0) {
      throw ArgumentError('RPC limits and timeout must be positive.');
    }
    _subscription = _socket.listen(
      _receive,
      onError: (Object error, StackTrace stack) {
        _finish(const LocalRpcException('disconnected', 'RPC socket failed.'));
      },
      onDone: () => _finish(
        _buffer.length == 0
            ? const LocalRpcException('disconnected', 'RPC socket closed.')
            : const LocalRpcException(
                'protocol_error',
                'RPC socket closed during a message.',
              ),
      ),
      cancelOnError: true,
    );
  }

  final Socket _socket;
  final Duration timeout;
  final int maxMessageBytes;
  final int maxPendingRequests;
  final int maxIncomingRequests;
  LocalRpcRequestHandler? onRequest;
  LocalRpcEventHandler? onEvent;

  late final StreamSubscription<Uint8List> _subscription;
  final _buffer = BytesBuilder();
  final _pending = <int, _PendingRequest>{};
  final _activeRequestIds = <int>{};
  final _done = Completer<void>();
  Future<void> _writeTail = Future.value();
  int _nextId = 0;
  int _activeEvents = 0;
  int _queuedWrites = 0;
  int _queuedWriteBytes = 0;
  bool _isClosed = false;

  bool get isClosed => _isClosed;
  Future<void> get done => _done.future;

  Future<Object?> call(String method, [Map<String, Object?> args = const {}]) {
    if (_isClosed) {
      return Future.error(
        const LocalRpcException('closed', 'RPC connection is closed.'),
      );
    }
    if (method.isEmpty) {
      return Future.error(
        const LocalRpcException('invalid_message', 'RPC method is empty.'),
      );
    }
    if (_pending.length >= maxPendingRequests) {
      return Future.error(
        const LocalRpcException('busy', 'Too many pending RPC requests.'),
      );
    }
    final id = ++_nextId;
    final request = _PendingRequest();
    try {
      _enqueue({
        'protocol': 2,
        'type': 'request',
        'id': id,
        'method': method,
        'args': args,
      });
      _pending[id] = request;
      request.timer = Timer(timeout, () {
        if (_pending.remove(id) != null) {
          request.completer.completeError(
            LocalRpcException('timeout', 'RPC request "$method" timed out.'),
          );
        }
      });
    } on LocalRpcException catch (error) {
      request.completer.completeError(error);
    }
    return request.completer.future;
  }

  void emit(String event, Map<String, Object?> payload) {
    if (event.isEmpty) {
      throw const LocalRpcException('invalid_message', 'RPC event is empty.');
    }
    _enqueue({
      'protocol': 2,
      'type': 'event',
      'name': event,
      'payload': payload,
    });
  }

  /// Closes immediately and fails pending calls. [done] itself never throws.
  Future<void> close() async {
    _finish(const LocalRpcException('closed', 'RPC connection was closed.'));
    await done;
  }

  void _enqueue(Map<String, Object?> envelope) {
    if (_isClosed) {
      throw const LocalRpcException('closed', 'RPC connection is closed.');
    }
    late final List<int> bytes;
    try {
      bytes = utf8.encode(jsonEncode(envelope));
    } catch (_) {
      throw const LocalRpcException(
        'invalid_message',
        'RPC message contains a value that cannot be encoded as JSON.',
      );
    }
    if (bytes.length > maxMessageBytes) {
      throw const LocalRpcException(
        'message_too_large',
        'RPC message exceeds the configured byte limit.',
      );
    }
    final maxQueued = maxPendingRequests + maxIncomingRequests;
    final length = bytes.length + 1;
    if (_queuedWrites >= maxQueued ||
        _queuedWriteBytes + length > (maxMessageBytes + 1) * maxQueued) {
      throw const LocalRpcException('busy', 'RPC write queue is full.');
    }
    _queuedWrites++;
    _queuedWriteBytes += length;
    _writeTail = _writeTail
        .then((_) async {
          if (_isClosed) return;
          _socket.add(bytes);
          _socket.add(const [10]);
          await _socket.flush();
        })
        .catchError((Object error, StackTrace stack) {
          _finish(const LocalRpcException('disconnected', 'RPC write failed.'));
        })
        .whenComplete(() {
          _queuedWrites--;
          _queuedWriteBytes -= length;
        });
  }

  void _receive(Uint8List bytes) {
    if (_isClosed) return;
    var start = 0;
    for (var index = 0; index < bytes.length; index++) {
      if (bytes[index] != 10) continue;
      if (!_append(Uint8List.sublistView(bytes, start, index))) return;
      final line = _buffer.takeBytes();
      start = index + 1;
      try {
        final decoded = jsonDecode(utf8.decode(line, allowMalformed: false));
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Envelope must be an object.');
        }
        _dispatch(Map<String, Object?>.from(decoded));
      } catch (_) {
        _finish(
          const LocalRpcException('protocol_error', 'Invalid RPC envelope.'),
        );
      }
      if (_isClosed) return;
    }
    _append(Uint8List.sublistView(bytes, start));
  }

  bool _append(Uint8List bytes) {
    if (_buffer.length + bytes.length > maxMessageBytes) {
      _finish(
        const LocalRpcException(
          'message_too_large',
          'Incoming RPC message exceeds the byte limit.',
        ),
      );
      return false;
    }
    _buffer.add(bytes);
    return true;
  }

  void _dispatch(Map<String, Object?> envelope) {
    if (envelope['protocol'] is! int || envelope['protocol'] != 2) {
      throw const FormatException('Unsupported RPC protocol.');
    }
    switch (envelope['type']) {
      case 'request':
        final id = _id(envelope['id']);
        final method = envelope['method'];
        if (method is! String || method.isEmpty) {
          throw const FormatException('Invalid RPC method.');
        }
        final args = _object(envelope['args']);
        if (_activeRequestIds.contains(id)) {
          throw const FormatException('Duplicate active RPC request ID.');
        }
        if (_activeRequestIds.length + _activeEvents >= maxIncomingRequests) {
          _sendError(
            id,
            const LocalRpcException('busy', 'RPC receiver is busy.'),
          );
          return;
        }
        _activeRequestIds.add(id);
        unawaited(_handleRequest(id, method, args));
      case 'response':
        final id = _id(envelope['id']);
        final hasResult = envelope.containsKey('result');
        final hasError = envelope.containsKey('error');
        if (hasResult == hasError) {
          throw const FormatException('RPC response needs result or error.');
        }
        LocalRpcException? error;
        if (hasError) {
          final details = _object(envelope['error']);
          final code = details['code'];
          final message = details['message'];
          if (code is! String || code.isEmpty || message is! String) {
            throw const FormatException('Invalid RPC error.');
          }
          error = LocalRpcException(code, message);
        }
        final pending = _pending.remove(id);
        if (pending == null) return; // Timeout or response to an old call.
        pending.timer?.cancel();
        if (error == null) {
          pending.completer.complete(envelope['result']);
        } else {
          pending.completer.completeError(error);
        }
      case 'event':
        final name = envelope['name'];
        if (name is! String || name.isEmpty) {
          throw const FormatException('Invalid RPC event name.');
        }
        final payload = _object(envelope['payload']);
        if (_activeRequestIds.length + _activeEvents >= maxIncomingRequests) {
          throw const FormatException('Too many concurrent RPC events.');
        }
        _activeEvents++;
        unawaited(_handleEvent(name, payload));
      default:
        throw const FormatException('Unknown RPC envelope type.');
    }
  }

  static int _id(Object? value) {
    if (value is! int || value <= 0) {
      throw const FormatException('RPC request IDs must be positive integers.');
    }
    return value;
  }

  static Map<String, Object?> _object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('RPC arguments must be JSON objects.');
    }
    return Map<String, Object?>.from(value);
  }

  Future<void> _handleRequest(
    int id,
    String method,
    Map<String, Object?> args,
  ) async {
    try {
      final handler = onRequest;
      if (handler == null) {
        throw const LocalRpcException(
          'method_not_found',
          'No RPC request handler is registered.',
        );
      }
      final result = await handler(method, args);
      if (!_isClosed) {
        _enqueue({
          'protocol': 2,
          'type': 'response',
          'id': id,
          'result': result,
        });
      }
    } catch (error) {
      if (!_isClosed) {
        _sendError(
          id,
          error is LocalRpcException
              ? error
              : const LocalRpcException(
                  'handler_error',
                  'Remote request failed.',
                ),
        );
      }
    } finally {
      _activeRequestIds.remove(id);
    }
  }

  void _sendError(int id, LocalRpcException error) {
    try {
      _enqueue({
        'protocol': 2,
        'type': 'response',
        'id': id,
        'error': {'code': error.code, 'message': error.message},
      });
    } catch (_) {
      _finish(
        const LocalRpcException(
          'disconnected',
          'RPC response could not be sent.',
        ),
      );
    }
  }

  Future<void> _handleEvent(String name, Map<String, Object?> payload) async {
    try {
      final result = onEvent?.call(name, payload);
      if (result is Future) await result;
    } catch (_) {
      // A notification has no response channel. An optional observer failing
      // must not leak an unhandled asynchronous error or break presentation RPC.
    } finally {
      _activeEvents--;
    }
  }

  void _finish(LocalRpcException error) {
    if (_isClosed) return;
    _isClosed = true;
    _buffer.clear();
    for (final request in _pending.values) {
      request.timer?.cancel();
      request.completer.completeError(error);
    }
    _pending.clear();
    unawaited(_subscription.cancel().catchError((Object _) {}));
    _socket.destroy();
    _done.complete();
  }
}

class _PendingRequest {
  final completer = Completer<Object?>();
  Timer? timer;
}
