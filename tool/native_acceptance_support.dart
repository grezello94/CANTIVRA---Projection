import 'dart:async';
import 'dart:collection';
import 'dart:io';

/// Keeps percentile storage bounded while retaining the maximum of every call.
class AcceptanceTimings {
  AcceptanceTimings({this.capacity = 4096, this.budgetMicroseconds = 50000}) {
    if (capacity < 1) throw ArgumentError.value(capacity, 'capacity');
    if (budgetMicroseconds < 0) {
      throw ArgumentError.value(budgetMicroseconds, 'budgetMicroseconds');
    }
  }

  final int capacity;
  final int budgetMicroseconds;
  final Queue<int> _samples = Queue<int>();
  int count = 0;
  int _maximum = 0;
  int _overBudget = 0;

  void add(int microseconds) {
    if (microseconds < 0) {
      throw ArgumentError.value(microseconds, 'microseconds');
    }
    count++;
    if (microseconds > budgetMicroseconds) _overBudget++;
    if (microseconds > _maximum) _maximum = microseconds;
    _samples.addLast(microseconds);
    if (_samples.length > capacity) _samples.removeFirst();
  }

  Map<String, Object?> toMap() {
    final sorted = _samples.toList()..sort();
    return {
      'count': count,
      'sampleCount': sorted.length,
      'samplePolicy': 'most recent $capacity observations',
      'p50Ms': sorted.isEmpty ? null : sorted[sorted.length ~/ 2] / 1000,
      'p95Ms': sorted.isEmpty
          ? null
          : sorted[(sorted.length * .95).ceil() - 1] / 1000,
      'maxSampleMs': sorted.isEmpty ? null : sorted.last / 1000,
      'maxAllRunMs': count == 0 ? null : _maximum / 1000,
      'budgetThresholdMs': budgetMicroseconds / 1000,
      'allRunSamplesOverThreshold': _overBudget,
      'allRunP95WithinThreshold': count == 0
          ? null
          : _overBudget <= count ~/ 20,
    };
  }
}

/// Harness-only TCP relay. Dropping both socket ends exercises the production
/// transport's reconnect path without adding fault hooks to production code.
/// Payloads and the private renderer capability are never inspected or logged.
class AcceptanceSocketRelay {
  AcceptanceSocketRelay._(this._server) {
    _subscription = _server.listen(_accept);
  }

  static Future<AcceptanceSocketRelay> start() async => AcceptanceSocketRelay._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
  );

  final ServerSocket _server;
  late final StreamSubscription<Socket> _subscription;
  final Set<_RelayConnection> _connections = {};
  int? destinationPort;
  int acceptedConnections = 0;
  int _generation = 0;
  bool _closed = false;
  int get port => _server.port;

  Future<void> _accept(Socket incoming) async {
    final destination = destinationPort;
    if (_closed || destination == null) {
      incoming.destroy();
      return;
    }
    final generation = _generation;
    final connection = _RelayConnection(incoming);
    _connections.add(connection);
    acceptedConnections++;
    try {
      final outgoing = await Socket.connect(
        InternetAddress.loopbackIPv4,
        destination,
        timeout: const Duration(seconds: 2),
      );
      if (_closed || generation != _generation || connection.closed) {
        outgoing.destroy();
        return;
      }
      connection.outgoing = outgoing;
      incoming.setOption(SocketOption.tcpNoDelay, true);
      outgoing.setOption(SocketOption.tcpNoDelay, true);
      void finish() {
        connection.close();
        _connections.remove(connection);
      }

      void forward(Socket target, List<int> bytes) {
        try {
          target.add(bytes);
        } catch (_) {
          finish();
        }
      }

      connection.incomingSubscription = incoming.listen(
        (bytes) => forward(outgoing, bytes),
        onError: (Object _) => finish(),
        onDone: finish,
      );
      connection.outgoingSubscription = outgoing.listen(
        (bytes) => forward(incoming, bytes),
        onError: (Object _) => finish(),
        onDone: finish,
      );
    } catch (_) {
      connection.close();
      _connections.remove(connection);
    }
  }

  void dropConnections() {
    _generation++;
    for (final connection in _connections.toList()) {
      connection.close();
    }
    _connections.clear();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    dropConnections();
    await _subscription.cancel();
    await _server.close();
  }
}

class _RelayConnection {
  _RelayConnection(this.incoming);
  final Socket incoming;
  Socket? outgoing;
  StreamSubscription<List<int>>? incomingSubscription;
  StreamSubscription<List<int>>? outgoingSubscription;
  bool closed = false;

  void close() {
    if (closed) return;
    closed = true;
    incoming.destroy();
    outgoing?.destroy();
    unawaited(incomingSubscription?.cancel());
    unawaited(outgoingSubscription?.cancel());
  }
}
