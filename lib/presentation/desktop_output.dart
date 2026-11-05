import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../platform/display_bridge.dart';
import '../platform/local_rpc.dart';
import 'live_controller.dart';
import 'renderer_session.dart';
import 'renderer_state.dart';

enum OutputConnectionState {
  closed,
  starting,
  ready,
  disarmed,
  reconnecting,
  unavailable,
  unconfirmed,
  inUse,
  incompatible,
}

/// Controls a renderer process through a private, renderer-owned local endpoint.
/// Disposal or operator-process death only disconnects; explicit close shuts it
/// down. No automatic recovery action may replace a surviving live snapshot.
class DesktopOutput extends ChangeNotifier implements OutputTransport {
  DesktopOutput({
    String? sessionPath,
    this.healthInterval = const Duration(seconds: 1),
    Future<bool> Function(int)? processExists,
    Future<int> Function(RendererLaunch)? launchRenderer,
  }) : _sessionPath = sessionPath,
       _processExists = processExists ?? NativeDisplayBridge.isProcessRunning,
       _launchRenderer = launchRenderer ?? _launchDetached;

  String? _sessionPath;
  final Duration healthInterval;
  final Future<bool> Function(int) _processExists;
  final Future<int> Function(RendererLaunch) _launchRenderer;
  final Set<LocalRpcPeer> _connectingPeers = {};
  LocalRpcPeer? _peer;
  RendererSession? _session;
  OutputConfiguration _configuration = const OutputConfiguration();
  Map<String, Object?> _window = {};
  OutputConnectionState state = OutputConnectionState.closed;
  @override
  bool get connected => !_disposed && state == OutputConnectionState.ready;
  bool get canControl => !_disposed && _peer != null && !_peer!.isClosed;
  String? get displayId => _configuration.displayId;
  bool get fullscreen => _configuration.fullscreen;
  double get canvasScale => _configuration.canvasScale;
  int? get processId => _session?.processId;
  String? get sessionId => _session?.sessionId;
  OutputFrame? recoveredFrame;
  bool opening = false;
  String? error;
  Timer? _health;
  Timer? _reconnect;
  bool _checkingHealth = false;
  bool _closing = false;
  bool _disposed = false;
  bool _needsConfirmation = false;
  int _retry = 0;
  Completer<void>? _openFinished;

  String get statusLabel => switch (state) {
    OutputConnectionState.closed => 'Output closed',
    OutputConnectionState.starting => 'Starting presentation renderer…',
    OutputConnectionState.ready =>
      fullscreen ? 'External display ready' : 'Windowed rehearsal ready',
    OutputConnectionState.disarmed =>
      'Output hidden · select Apply/open to re-arm',
    OutputConnectionState.reconnecting =>
      'Connection lost · renderer holds the last frame',
    OutputConnectionState.unavailable =>
      'Renderer stopped · open a black replacement',
    OutputConnectionState.unconfirmed =>
      'Live state unconfirmed · reconnect to inspect output',
    OutputConnectionState.inUse =>
      'Another operator controls the active output',
    OutputConnectionState.incompatible =>
      'Output belongs to a different app version',
  };

  static Future<int> _launchDetached(RendererLaunch launch) async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        rendererRoleArgument,
        '--cantivra-session-file=${launch.sessionPath}',
        '--cantivra-session=${launch.sessionId}',
      ],
      mode: ProcessStartMode.detached,
      environment: {rendererTokenEnvironment: launch.token},
    );
    return process.pid;
  }

  Future<String> _path() async {
    _ensureActive();
    if (_sessionPath != null) return _sessionPath!;
    final directory = await getApplicationSupportDirectory();
    _ensureActive();
    return _sessionPath =
        '${directory.path}${Platform.pathSeparator}workspace${Platform.pathSeparator}renderer-session.json';
  }

  /// Startup recovery only inspects an existing renderer. It does not create a
  /// process, configure a screen, show a hidden window or publish anything.
  Future<bool> recoverExisting() async {
    if (_disposed || _sessionPath == null || opening || canControl) {
      return false;
    }
    final existing = await RendererSession.read(_sessionPath!);
    if (_disposed || existing == null) return false;
    try {
      await _connect(existing);
      if (_disposed) return false;
      _health ??= Timer.periodic(
        healthInterval,
        (_) => unawaited(_checkHealth()),
      );
      return true;
    } catch (failure) {
      if (_disposed) return false;
      if (_isIncompatible(failure)) {
        state = OutputConnectionState.incompatible;
        error = _incompatibleMessage;
      } else if (failure is LocalRpcException &&
          failure.code == 'operator_connected') {
        state = OutputConnectionState.inUse;
        error = 'Another Cantivra operator is using the existing presentation.';
      } else {
        final running = await _processExists(existing.processId);
        if (_disposed) return false;
        if (!running) {
          state = OutputConnectionState.unavailable;
        } else {
          state = OutputConnectionState.reconnecting;
          error =
              'An existing presentation is holding its last frame. Select Open output to reconnect.';
        }
      }
      _notify();
      return false;
    }
  }

  Future<void> open({
    String? targetDisplayId,
    bool fullscreen = false,
    double scale = 1,
    double safeInset = 0,
  }) async {
    _ensureActive();
    if (opening) throw StateError('Presentation output is already opening.');
    final configuration = OutputConfiguration.fromMap({
      'displayId': targetDisplayId,
      'fullscreen': fullscreen,
      'scale': scale,
      'safeInset': safeInset,
    });
    opening = true;
    _closing = false;
    error = null;
    _reconnect?.cancel();
    _openFinished = Completer<void>();
    if (!canControl) state = OutputConnectionState.starting;
    _notify();
    RandomAccessFile? lock;
    var locked = false;
    try {
      _ensureActive();
      final path = await _path();
      _ensureActive();
      await File(path).parent.create(recursive: true);
      _ensureActive();
      lock = await File('$path.lock').open(mode: FileMode.append);
      _ensureActive();
      await lock.lock(FileLock.exclusive).timeout(const Duration(seconds: 12));
      locked = true;
      _ensureActive();
      if (canControl && _session != null) {
        final running = await _processExists(_session!.processId);
        _ensureActive();
        if (!running) {
          final deadPeer = _peer;
          _peer = null;
          await deadPeer?.close();
          _ensureActive();
        }
      }
      if (!canControl) {
        final previous = await RendererSession.read(path);
        _ensureActive();
        if (previous != null) {
          try {
            await _connect(previous);
          } catch (failure) {
            _ensureActive();
            final running = await _processExists(previous.processId);
            _ensureActive();
            if (running) {
              if (_isIncompatible(failure)) rethrow;
              throw StateError(
                'A presentation process is still running but cannot be controlled. Retry reconnecting; it will not be replaced automatically. $failure',
              );
            }
            await previous.removeIfCurrent(path);
            _ensureActive();
          }
        }
        if (!canControl) {
          _ensureActive();
          final launch = RendererLaunch(
            sessionPath: path,
            sessionId: sessionSecret(16),
            token: sessionSecret(),
          );
          final childPid = await _launchRenderer(launch);
          _ensureActive();
          var started = false;
          for (var attempt = 0; attempt < 100; attempt++) {
            final session = await RendererSession.read(path);
            _ensureActive();
            if (session != null &&
                session.sessionId == launch.sessionId &&
                session.processId == childPid) {
              await _connect(session);
              _ensureActive();
              started = true;
              break;
            }
            if (attempt > 2) {
              final running = await _processExists(childPid);
              _ensureActive();
              if (!running) {
                throw StateError(
                  'The presentation process exited during startup.',
                );
              }
            }
            await Future<void>.delayed(const Duration(milliseconds: 80));
            _ensureActive();
          }
          if (!started) {
            throw StateError('The presentation renderer did not become ready.');
          }
        }
      }
      _ensureActive();
      final info = _map(
        await _peer!.call('configure', {
          ...configuration.toMap(),
          'session': _session!.sessionId,
        }),
      );
      _ensureActive();
      _needsConfirmation = false;
      _acceptInfo(info);
      _ensureActive();
      error = null;
      _retry = 0;
      _health ??= Timer.periodic(
        healthInterval,
        (_) => unawaited(_checkHealth()),
      );
    } catch (failure) {
      if (!_disposed) {
        error = _isIncompatible(failure)
            ? _incompatibleMessage
            : 'Could not apply output configuration: $failure';
        if (!canControl) {
          state = _isIncompatible(failure)
              ? OutputConnectionState.incompatible
              : OutputConnectionState.unavailable;
        }
        _notify();
      }
      rethrow;
    } finally {
      if (lock != null) {
        try {
          if (locked) await lock.unlock();
        } finally {
          await lock.close();
        }
      }
      opening = false;
      _openFinished?.complete();
      _notify();
    }
  }

  Future<void> _connect(RendererSession session) async {
    _ensureActive();
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      session.port,
      timeout: const Duration(milliseconds: 700),
    );
    if (_disposed) {
      socket.destroy();
      _ensureActive();
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    final peer = LocalRpcPeer(socket);
    _connectingPeers.add(peer);
    try {
      final info = _map(
        await peer.call('hello', {
          'protocol': 2,
          'renderSchema': renderSchemaVersion,
          'session': session.sessionId,
          'token': session.token,
        }),
      );
      _ensureActive();
      if (info['session'] != session.sessionId ||
          info['pid'] != session.processId) {
        throw const LocalRpcException(
          'wrong_session',
          'Renderer identity did not match the private session.',
        );
      }
      _requireRenderSchema(info);
      final previous = _peer;
      _peer = peer;
      _session = session;
      peer.onEvent = (name, payload) {
        if (_disposed ||
            !identical(_peer, peer) ||
            payload['session'] != _session?.sessionId) {
          return;
        }
        if (name == 'outputStatus') {
          _window = _map(payload['window']);
          _updateStatus();
          _notify();
        }
      };
      _acceptInfo(info);
      _ensureActive();
      if (previous != null && !identical(previous, peer)) {
        await previous.close();
        _ensureActive();
      }
      unawaited(
        peer.done.then((_) {
          if (identical(_peer, peer) && !_closing && !_disposed) {
            _peer = null;
            state = OutputConnectionState.reconnecting;
            error =
                'Renderer control connection was lost. The last output is held until you reconnect.';
            _scheduleReconnect();
            _notify();
          }
        }),
      );
    } catch (_) {
      await peer.close();
      rethrow;
    } finally {
      _connectingPeers.remove(peer);
    }
  }

  void _acceptInfo(Map<String, Object?> info) {
    _ensureActive();
    _requireRenderSchema(info);
    if (info['protocol'] != 2 || info['session'] != _session?.sessionId) {
      throw const LocalRpcException(
        'wrong_session',
        'Invalid renderer status session.',
      );
    }
    recoveredFrame = OutputFrame.fromMap(_map(info['frame']));
    _configuration = OutputConfiguration.fromMap(_map(info['configuration']));
    _window = _map(info['window']);
    _updateStatus();
    _notify();
  }

  void _updateStatus() {
    if (_needsConfirmation) {
      state = OutputConnectionState.unconfirmed;
      return;
    }
    state = _window['visible'] == true && _window['displayAvailable'] == true
        ? OutputConnectionState.ready
        : OutputConnectionState.disarmed;
  }

  Future<Map<String, Object?>> inspect() async {
    _ensureActive();
    final peer = _peer;
    final session = _session;
    if (peer == null || session == null) {
      throw StateError('Renderer is not connected.');
    }
    final info = _map(
      await peer.call('inspect', {'session': session.sessionId}),
    );
    _ensureActive();
    _requireRenderSchema(info);
    return info;
  }

  static const _incompatibleMessage =
      'This renderer belongs to a different app version. Close its output from that version, then reopen output here. Its current frame is preserved.';

  static bool _isIncompatible(Object failure) =>
      failure is LocalRpcException &&
      failure.code == 'unsupported_renderer_schema';

  static void _requireRenderSchema(Map<String, Object?> info) {
    if (info['renderSchema'] != renderSchemaVersion) {
      throw const LocalRpcException(
        'unsupported_renderer_schema',
        _incompatibleMessage,
      );
    }
  }

  Future<void> _checkHealth() async {
    if (_disposed || _checkingHealth || opening || _closing || !canControl) {
      return;
    }
    _checkingHealth = true;
    final peer = _peer;
    try {
      final info = await inspect();
      if (_disposed || !identical(peer, _peer)) return;
      _window = _map(info['window']);
      _updateStatus();
      _notify();
    } catch (_) {
      if (_disposed || !identical(peer, _peer) || _closing) return;
      await peer?.close();
    } finally {
      _checkingHealth = false;
    }
  }

  void _scheduleReconnect() {
    if (_closing ||
        _disposed ||
        _session == null ||
        _reconnect?.isActive == true) {
      return;
    }
    const delays = [250, 500, 1000, 2000, 5000];
    final delay = delays[_retry.clamp(0, delays.length - 1)];
    _retry++;
    _reconnect = Timer(Duration(milliseconds: delay), () async {
      if (_closing || _disposed || canControl) return;
      final session = _session!;
      try {
        final running = await _processExists(session.processId);
        if (_disposed || _closing) return;
        if (!running) {
          state = OutputConnectionState.unavailable;
          error =
              'The renderer exited. Select Apply/open to start a new black output.';
          _notify();
          return;
        }
        await _connect(session);
        if (_disposed || _closing) return;
        _retry = 0;
        if (!_needsConfirmation) error = null;
      } catch (failure) {
        if (_disposed || _closing) return;
        if (_isIncompatible(failure)) {
          state = OutputConnectionState.incompatible;
          error = _incompatibleMessage;
          _notify();
        } else {
          _scheduleReconnect();
        }
      }
    });
  }

  @override
  Future<int> publish(OutputFrame frame) async {
    _ensureActive();
    final peer = _peer;
    final session = _session;
    if (peer == null || session == null || (!connected && !frame.emergency)) {
      throw StateError('Open and confirm the presentation output first.');
    }
    try {
      Object? reply;
      if (frame.emergency) {
        reply = await peer.call('emergency', {
          'session': session.sessionId,
          'frame': frame.toMap(),
        });
      } else {
        await peer.call('prepare', {
          'session': session.sessionId,
          'frame': frame.toMap(),
        });
        _ensureActive();
        reply = await peer.call('commit', {
          'session': session.sessionId,
          'revision': frame.revision,
        });
      }
      _ensureActive();
      final acknowledgement = _map(reply);
      if (acknowledgement['revision'] != frame.revision ||
          acknowledgement['renderedRevision'] != frame.revision) {
        throw const LocalRpcException(
          'unconfirmed',
          'Renderer did not confirm this displayed revision.',
        );
      }
      recoveredFrame = frame;
      _needsConfirmation = false;
      error = null;
      _updateStatus();
      _notify();
      return frame.revision;
    } catch (failure) {
      if (_disposed ||
          !identical(peer, _peer) ||
          _session?.sessionId != session.sessionId ||
          (recoveredFrame?.revision ?? -1) > frame.revision) {
        // A delayed failure from an older command/session cannot make a newer
        // confirmed emergency frame uncertain or disable its controls.
        rethrow;
      }
      if (failure is LocalRpcException &&
          {
            'stale_revision',
            'superseded',
            'frozen',
            'invalid_frame',
            'not_prepared',
            'busy',
          }.contains(failure.code)) {
        rethrow;
      }
      // A commit ACK can be lost after the frame is visible. Inspect the actual
      // renderer rather than assuming the old frame is still on screen.
      try {
        final actual = await inspect();
        if (actual['renderedRevision'] == frame.revision &&
            jsonEncode(actual['frame']) == jsonEncode(frame.toMap())) {
          _needsConfirmation = false;
          _acceptInfo(actual);
          error = null;
          return frame.revision;
        }
      } catch (_) {
        /* Cannot confirm the actual frame. Keep explicit uncertainty. */
      }
      _needsConfirmation = true;
      state = OutputConnectionState.unconfirmed;
      error =
          'Live output was not confirmed. Reconnect to inspect it; no replacement is automatic.';
      _notify();
      rethrow;
    }
  }

  Future<void> close() async {
    _ensureActive();
    if (opening) await _openFinished?.future;
    _ensureActive();
    _closing = true;
    _reconnect?.cancel();
    _health?.cancel();
    _health = null;
    try {
      if (!canControl && _session != null) {
        final running = await _processExists(_session!.processId);
        _ensureActive();
        if (running) await _connect(_session!);
      }
      _ensureActive();
      if (canControl) {
        // An exiting native process can close its socket before the shutdown
        // response reaches us. Its actual process exit is the final authority.
        try {
          await _peer!.call('shutdown', {'session': _session!.sessionId});
        } on LocalRpcException {
          /* Verify exit below; never assume it succeeded. */
        }
        for (var attempt = 0; attempt < 40; attempt++) {
          _ensureActive();
          final running = await _processExists(_session!.processId);
          _ensureActive();
          if (!running) break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        _ensureActive();
        final running = await _processExists(_session!.processId);
        _ensureActive();
        if (running) {
          throw StateError(
            'Presentation did not close. Keep the operator open and retry.',
          );
        }
      }
      final peer = _peer;
      _peer = null;
      await peer?.close();
      _ensureActive();
      _session = null;
      _needsConfirmation = false;
      state = OutputConnectionState.closed;
      error = null;
    } catch (failure) {
      if (!_disposed) {
        error = 'Output could not be closed: $failure';
        _notify();
      }
      rethrow;
    } finally {
      _closing = false;
      _notify();
    }
  }

  static Map<String, Object?> _map(Object? value) =>
      Map<String, Object?>.from(value! as Map);
  void _ensureActive() {
    if (_disposed) throw StateError('Presentation output has been disposed.');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _health?.cancel();
    _reconnect?.cancel();
    final peer = _peer;
    _peer = null;
    unawaited(peer?.close() ?? Future<void>.value());
    for (final connecting in _connectingPeers) {
      unawaited(connecting.close());
    }
    _connectingPeers.clear();
    super.dispose();
  }
}
