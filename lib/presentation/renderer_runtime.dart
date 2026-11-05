import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/display_bridge.dart';
import '../platform/local_rpc.dart';
import 'renderer_session.dart';
import 'renderer_state.dart';
import 'slide_surface.dart';

abstract interface class RendererBackend {
  Future<void> configure(OutputConfiguration configuration);
  Future<Map<String, Object?>> status();
  Stream<Map<String, Object?>> get changes;
  Future<void> hide();
  Future<void> close();
}

class NativeRendererBackend implements RendererBackend {
  @override
  Future<void> configure(OutputConfiguration configuration) =>
      NativeDisplayBridge.configureOutput(
        displayId: configuration.displayId,
        fullscreen: configuration.fullscreen,
      );
  @override
  Future<Map<String, Object?>> status() => NativeDisplayBridge.outputStatus();
  @override
  Stream<Map<String, Object?>> get changes => NativeDisplayBridge.changes;
  @override
  Future<void> hide() => NativeDisplayBridge.hideOutput();
  @override
  Future<void> close() => NativeDisplayBridge.closeOutput();
}

/// An independently running renderer owns its endpoint and its last frame. A
/// socket disconnect is deliberately not a hide, clear, restore or quit action.
class RendererRuntime {
  RendererRuntime({
    required this.launch,
    required this.state,
    RendererBackend? backend,
  }) : backend = backend ?? NativeRendererBackend();
  final RendererLaunch launch;
  final RendererState state;
  final RendererBackend backend;
  late final ServerSocket _server;
  late final RendererSession session;
  final Set<LocalRpcPeer> _clients = {};
  LocalRpcPeer? _operator;
  StreamSubscription<Map<String, Object?>>? _displayChanges;
  Map<String, Object?> _windowStatus = {};
  bool _configuring = false;
  bool _closing = false;

  Future<void> start() async {
    _windowStatus = await backend.status();
    _server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    session = RendererSession(
      sessionId: launch.sessionId,
      token: launch.token,
      port: _server.port,
      processId: pid,
      createdAt: DateTime.now(),
    );
    _server.listen(
      _accept,
      onError: (Object error) {
        // Losing a listening endpoint cannot invalidate the visible canvas.
        debugPrint(
          'Renderer control listener stopped; holding the last frame.',
        );
      },
    );
    try {
      await session.write(launch.sessionPath);
    } catch (_) {
      await _server.close();
      rethrow;
    }
    _displayChanges = backend.changes.listen(
      (status) {
        _windowStatus = Map<String, Object?>.from(status)..remove('displays');
        _notifyStatus();
      },
      onError: (Object error) {
        debugPrint(
          'Renderer display observer failed; the last frame is retained.',
        );
      },
    );
  }

  void _accept(Socket socket) {
    if (_closing || _clients.length >= 4 || !socket.remoteAddress.isLoopback) {
      socket.destroy();
      return;
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    var authenticated = false;
    late final LocalRpcPeer peer;
    late final Timer authenticationDeadline;
    peer = LocalRpcPeer(
      socket,
      onRequest: (method, args) async {
        try {
          if (!authenticated) {
            if (method != 'hello' ||
                args['protocol'] != 2 ||
                args['session'] != launch.sessionId ||
                !secretsMatch(args['token'] as String? ?? '', launch.token)) {
              Timer(const Duration(milliseconds: 100), peer.close);
              throw const LocalRpcException(
                'unauthorized',
                'Renderer control authentication failed.',
              );
            }
            if (args['renderSchema'] != renderSchemaVersion) {
              Timer(const Duration(milliseconds: 100), peer.close);
              throw const LocalRpcException(
                'unsupported_renderer_schema',
                'The operator and renderer use incompatible slide layouts. Open the operator from the same app version.',
              );
            }
            if (_operator != null &&
                !_operator!.isClosed &&
                !identical(_operator, peer)) {
              throw const LocalRpcException(
                'operator_connected',
                'Another operator is already connected to this presentation.',
              );
            }
            authenticated = true;
            authenticationDeadline.cancel();
            _operator = peer;
            return await inspect();
          }
          state.requireSession(args);
          switch (method) {
            case 'inspect':
              return await inspect();
            case 'prepare':
              return state.prepare(args);
            case 'commit':
              return await state.commit(args);
            case 'cancel':
              state.cancel(args);
              return null;
            case 'emergency':
              return await state.emergency(args);
            case 'configure':
              if (_configuring) {
                throw const LocalRpcException(
                  'busy',
                  'Output configuration is already being applied.',
                );
              }
              _configuring = true;
              try {
                final configuration = OutputConfiguration.fromMap(args);
                final status = await backend.status();
                // Reconnecting an unchanged healthy window must not hide it or
                // switch focus. A disarmed/missing display needs explicit re-arm.
                final placementHealthy =
                    status['visible'] == true &&
                    status['displayId'] == configuration.displayId &&
                    status['fullscreen'] == configuration.fullscreen &&
                    status['displayAvailable'] == true;
                final current = state.configuration;
                final unchanged =
                    current.displayId == configuration.displayId &&
                    current.fullscreen == configuration.fullscreen &&
                    current.scale == configuration.scale &&
                    current.safeInset == configuration.safeInset;
                if (placementHealthy && unchanged) return await inspect();
                if (!placementHealthy) {
                  await backend.configure(configuration);
                }
                state.configuration = configuration;
                state.notifyConfiguration();
                await state.frameReady();
                _windowStatus = await backend.status();
                return await inspect();
              } finally {
                _configuring = false;
              }
            case 'hide':
              await backend.hide();
              _windowStatus = await backend.status();
              _notifyStatus();
              return await inspect();
            case 'shutdown':
              await backend.hide();
              await session.removeIfCurrent(launch.sessionPath);
              _closing = true;
              // Flush the RPC response before closing the native application.
              Timer(
                const Duration(milliseconds: 100),
                () => unawaited(backend.close()),
              );
              return {'closing': true};
            default:
              throw const LocalRpcException(
                'method_not_found',
                'Unsupported renderer command.',
              );
          }
        } on PlatformException catch (error) {
          throw LocalRpcException(
            error.code,
            error.message ?? 'Native output operation failed.',
          );
        } on FormatException catch (error) {
          throw LocalRpcException('invalid_frame', error.message);
        }
      },
    );
    authenticationDeadline = Timer(const Duration(seconds: 3), peer.close);
    _clients.add(peer);
    unawaited(
      peer.done.then((_) {
        authenticationDeadline.cancel();
        _clients.remove(peer);
        if (identical(_operator, peer)) {
          _operator = null;
          state.discardPrepared();
        }
      }),
    );
  }

  Future<Map<String, Object?>> inspect() async {
    _windowStatus = await backend.status();
    return {
      'protocol': 2,
      'renderSchema': renderSchemaVersion,
      'session': launch.sessionId,
      'pid': pid,
      'frame': state.frame.toMap(),
      'renderedRevision': state.renderedRevision,
      'configuration': state.configuration.toMap(),
      'window': _windowStatus,
      'resources': {
        'rssBytes': ProcessInfo.currentRss,
        'maxRssBytes': ProcessInfo.maxRss,
      },
    };
  }

  void _notifyStatus() {
    try {
      _operator?.emit('outputStatus', {
        'session': launch.sessionId,
        'window': _windowStatus,
      });
    } on LocalRpcException {
      /* Operator unavailable; retain the last frame. */
    }
  }

  /// For tests/explicit server teardown only. Disconnecting a controller never
  /// calls this; the native renderer remains independent until explicit quit.
  Future<void> dispose() async {
    _closing = true;
    await _displayChanges?.cancel();
    for (final client in _clients.toList()) {
      await client.close();
    }
    await _server.close();
    await session.removeIfCurrent(launch.sessionPath);
  }
}

class CongregationApp extends StatelessWidget {
  const CongregationApp({super.key, required this.runtime});
  final RendererRuntime runtime;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Cantivra — Presentation',
    color: Colors.black,
    home: Scaffold(
      backgroundColor: Colors.black,
      body: MouseRegion(
        cursor: SystemMouseCursors.none,
        child: ListenableBuilder(
          listenable: runtime.state,
          builder: (context, _) => SlideSurface(
            slide: runtime.state.frame.slide,
            mode: runtime.state.frame.mode,
            backgroundVisible: runtime.state.frame.backgroundVisible,
            canvasScale: runtime.state.configuration.canvasScale,
          ),
        ),
      ),
    ),
  );
}

/// Wait for Flutter's build/layout/paint barrier even when the OS suppresses
/// vsync for an occluded or hidden rehearsal window. A warm-up frame never
/// changes window placement or focus. As with a normal post-frame ACK, this
/// confirms the prepared Flutter scene rather than physical display scanout.
Future<void> rendererFrameReady() {
  final binding = WidgetsBinding.instance;
  final ready = binding.endOfFrame;
  var completed = false;
  final fallback = Timer.periodic(const Duration(milliseconds: 250), (_) {
    if (!completed) binding.scheduleWarmUpFrame();
  });
  if (!binding.framesEnabled) binding.scheduleWarmUpFrame();
  return ready.whenComplete(() {
    completed = true;
    fallback.cancel();
  });
}

Future<void> runRenderer(RendererLaunch launch) async {
  final state = RendererState(
    sessionId: launch.sessionId,
    frameReady: rendererFrameReady,
  );
  final runtime = RendererRuntime(launch: launch, state: state);
  await runtime.start();
  runApp(CongregationApp(runtime: runtime));
}
