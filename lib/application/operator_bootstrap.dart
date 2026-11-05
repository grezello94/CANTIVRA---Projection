import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/app_repository.dart';
import '../platform/display_bridge.dart';
import '../presentation/desktop_output.dart';
import '../presentation/live_controller.dart';
import 'workspace_controller.dart';

/// Opens operator storage independently from the surviving presentation process.
/// Startup and retry only inspect an existing renderer; they never open a new
/// output, move a window, change display settings or publish a frame.
class OperatorBootstrap extends ChangeNotifier {
  OperatorBootstrap({
    Future<Directory> Function()? directoryProvider,
    DesktopOutput Function(String sessionPath)? outputFactory,
  }) : _directoryProvider = directoryProvider ?? _workspaceDirectory,
       _outputFactory = outputFactory ?? _createOutput;

  final Future<Directory> Function() _directoryProvider;
  final DesktopOutput Function(String sessionPath) _outputFactory;
  Directory? _directory;
  WorkspaceController? _workspace;
  DesktopOutput? _output;
  LiveController? _recoveryLive;
  Future<void>? _startup;
  Future<void>? _reconnection;
  final Set<Future<bool>> _outputActions = {};
  Future<bool>? _close;
  bool _disposed = false;
  bool _loading = true;
  String? _startupError;
  String? _actionError;
  int _actionGeneration = 0;

  bool get loading => _loading;
  WorkspaceController? get workspace => _workspace;
  DesktopOutput? get output => _output;
  LiveController? get recoveryLive => _recoveryLive;
  String? get startupError => _startupError;
  String? get actionError => _actionError;
  bool get reconnecting => _reconnection != null;
  bool get closing => _close != null;

  static Future<Directory> _workspaceDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}workspace');
  }

  static DesktopOutput _createOutput(String sessionPath) =>
      DesktopOutput(sessionPath: sessionPath);

  Future<void> start() {
    if (_disposed || _workspace != null) return Future<void>.value();
    if (_startup case final pending?) return pending;
    if (_reconnection != null || _close != null || _controlBusy) {
      _actionError = 'Wait for the current output command before retrying.';
      _notify();
      return Future<void>.value();
    }
    final complete = Completer<void>();
    _startup = complete.future;
    _loading = true;
    _startupError = null;
    _actionError = null;
    _notify();
    unawaited(
      _openWorkspace().whenComplete(() {
        _startup = null;
        _loading = false;
        complete.complete();
        _notify();
      }),
    );
    return complete.future;
  }

  Future<void> retry() => start();

  Future<void> _openWorkspace() async {
    AppRepository? repository;
    WorkspaceController? candidate;
    try {
      // Even a native operator-window error must not skip the known renderer's
      // independent control endpoint. It still prevents normal workspace use.
      Object? operatorFailure;
      try {
        await NativeDisplayBridge.configureOperator();
      } catch (error) {
        operatorFailure = error;
      }
      _directory ??= await _directoryProvider();
      if (_disposed) return;
      final directory = _directory!;
      if (_output == null) {
        _output = _outputFactory(
          '${directory.path}${Platform.pathSeparator}renderer-session.json',
        )..addListener(_forward);
        _recoveryLive = LiveController(_output!)..addListener(_forward);
        _notify();
      }
      await _inspectExisting();
      if (_disposed) return;
      if (operatorFailure != null) {
        throw StateError(
          'The operator window could not be prepared: $operatorFailure',
        );
      }
      // Creating this exact directory never replaces, repairs or deletes an
      // existing database. SQLite itself rejects corrupt or newer schemas.
      await directory.create(recursive: true);
      repository = await AppRepository.open(
        '${directory.path}${Platform.pathSeparator}cantivra.sqlite',
      );
      if (_disposed) return;
      candidate = WorkspaceController(
        repository: repository,
        output: _output!,
        dataDirectory: directory.path,
      );
      await candidate.initialize();
      // An emergency may be requested while storage is opening. Transfer only
      // after its ACK, so the replacement controls adopt the newest frame.
      while (_outputActions.isNotEmpty) {
        await Future.wait(_outputActions.toList());
      }
      if (_disposed) return;
      final recovered = _output!.recoveredFrame;
      if (_output!.canControl && recovered != null) {
        candidate.live.reconcileOutput(recovered);
      }
      final previousRecovery = _recoveryLive;
      _workspace = candidate;
      candidate = null;
      repository = null;
      _recoveryLive = null;
      _startupError = null;
      _notify();
      previousRecovery?.removeListener(_forward);
      previousRecovery?.dispose();
    } catch (error) {
      if (!_disposed) {
        _startupError = 'The local workspace could not be opened: $error';
        // The first inspection may have preceded a transient reconnect. This
        // second read is also safe: it never creates or configures an output.
        await _inspectExisting();
      }
    } finally {
      candidate?.dispose();
      if (repository != null) {
        try {
          await repository.close();
        } catch (error) {
          if (!_disposed) {
            _actionError =
                'The failed storage connection could not be closed: $error';
          }
        }
      }
    }
  }

  bool get _controlBusy =>
      _outputActions.isNotEmpty ||
      (_recoveryLive?.busy ?? false) ||
      (_workspace?.live.busy ?? false) ||
      (_output?.opening ?? false);

  Future<void> _inspectExisting() async {
    final transport = _output;
    if (transport == null || _disposed) return;
    try {
      await transport.recoverExisting();
      if (_disposed) return;
      // recoverExisting is deliberately a no-op for an already attached peer.
      // Retry must still transfer its actual snapshot into the new controller.
      final frame = transport.recoveredFrame;
      if (transport.canControl && frame != null) {
        if (_recoveryLive?.busy == false) {
          _recoveryLive!.reconcileOutput(frame);
        }
        _actionError = null;
      } else {
        _actionError = transport.error;
      }
    } catch (error) {
      if (!_disposed) {
        _actionError = 'Existing output could not be inspected: $error';
      }
    }
    _notify();
  }

  Future<void> reconnectExisting() {
    if (_disposed || _workspace != null) return Future<void>.value();
    if (_reconnection case final pending?) return pending;
    if (_loading || _startup != null || _close != null || _controlBusy) {
      _actionError = 'Wait for the current operation before reconnecting.';
      _notify();
      return Future<void>.value();
    }
    final complete = Completer<void>();
    _reconnection = complete.future;
    _actionError = null;
    _notify();
    unawaited(
      _inspectExisting().whenComplete(() {
        _reconnection = null;
        complete.complete();
        _notify();
      }),
    );
    return complete.future;
  }

  /// The recovery screen has live controls but no library or draft publisher.
  /// It may request an emergency during startup; normal busy/ACK rules remain
  /// owned by LiveController and DesktopOutput.
  Future<bool> performOutputAction(
    Future<bool> Function() action, {
    bool emergency = false,
  }) {
    if (_disposed ||
        (_workspace != null && !emergency) ||
        (_reconnection != null && !emergency) ||
        _close != null ||
        (_outputActions.isNotEmpty && !emergency)) {
      return Future<bool>.value(false);
    }
    final complete = Completer<bool>();
    final generation = ++_actionGeneration;
    _outputActions.add(complete.future);
    _actionError = null;
    _notify();
    unawaited(() async {
      var success = false;
      try {
        success = await action();
        if (!success && generation == _actionGeneration) {
          _actionError =
              _workspace?.live.error ??
              _recoveryLive?.error ??
              _output?.error ??
              'The output command was not applied.';
        }
      } catch (error) {
        if (generation == _actionGeneration) {
          _actionError = 'The output command was not confirmed: $error';
        }
      } finally {
        _outputActions.remove(complete.future);
        complete.complete(success);
        _notify();
      }
    }());
    return complete.future;
  }

  Future<bool> prepareClose() {
    if (_disposed) return Future<bool>.value(false);
    if (_close case final pending?) return pending;
    if (_loading || _startup != null || _reconnection != null || _controlBusy) {
      _actionError =
          'Wait for the current operation before closing the operator.';
      _notify();
      return Future<bool>.value(false);
    }
    final complete = Completer<bool>();
    _close = complete.future;
    _actionError = null;
    _notify();
    unawaited(() async {
      var success = false;
      try {
        final controller = _workspace;
        if (controller != null) {
          do {
            await controller.flushSave();
          } while (!controller.saved);
        }
        // This is reached only through an explicit native Quit. Disposing the
        // bootstrap or retrying storage never shuts down a surviving renderer.
        await _output?.close();
        // The editor remains usable while the renderer acknowledges shutdown.
        // Drain corrections made during that wait before allowing the OS to
        // terminate the operator. A failed save keeps its current source open;
        // the explicitly closed renderer is never restarted automatically.
        if (controller != null) {
          do {
            await controller.flushSave();
          } while (!controller.saved);
        }
        success = true;
      } catch (error) {
        _actionError = 'The operator could not close safely: $error';
        _workspace?.reportError(_actionError!);
      } finally {
        _close = null;
        complete.complete(success);
        _notify();
      }
    }());
    return complete.future;
  }

  void _forward() => _notify();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final controller = _workspace;
    final recovery = _recoveryLive;
    recovery?.removeListener(_forward);
    if (_outputActions.isEmpty) {
      controller?.dispose();
      if (controller != null) {
        unawaited(controller.repository.close().catchError((Object _) {}));
      }
      recovery?.dispose();
    } else {
      // Disconnect first, then allow in-flight ACK/failure callbacks to drain
      // before disposing their LiveController notifier.
      unawaited(
        Future.wait(_outputActions.toList()).then((_) {
          controller?.dispose();
          if (controller != null) {
            unawaited(controller.repository.close().catchError((Object _) {}));
          }
          recovery?.dispose();
        }),
      );
    }
    _output?.removeListener(_forward);
    _output?.dispose();
    super.dispose();
  }
}
