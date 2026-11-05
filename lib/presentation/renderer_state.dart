import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../platform/local_rpc.dart';
import 'live_controller.dart';

class OutputConfiguration {
  const OutputConfiguration({
    this.displayId,
    this.fullscreen = false,
    this.scale = 1,
    this.safeInset = 0,
  });
  final String? displayId;
  final bool fullscreen;
  final double scale;
  final double safeInset;
  double get canvasScale => scale * (1 - 2 * safeInset);
  Map<String, Object?> toMap() => {
    'displayId': displayId,
    'fullscreen': fullscreen,
    'scale': scale,
    'safeInset': safeInset,
  };

  factory OutputConfiguration.fromMap(Map<String, Object?> map) {
    final configuration = OutputConfiguration(
      displayId: map['displayId'] as String?,
      fullscreen: map['fullscreen'] as bool? ?? false,
      scale: (map['scale'] as num?)?.toDouble() ?? 1,
      safeInset: (map['safeInset'] as num?)?.toDouble() ?? 0,
    );
    if (!configuration.scale.isFinite ||
        configuration.scale < .75 ||
        configuration.scale > 1 ||
        !configuration.safeInset.isFinite ||
        configuration.safeInset < 0 ||
        configuration.safeInset > .12 ||
        (configuration.fullscreen && configuration.displayId == null)) {
      throw const LocalRpcException(
        'invalid_configuration',
        'Output scale, inset or display is invalid.',
      );
    }
    return configuration;
  }
}

/// Renderer-owned state. A failed prepare never changes the visible canvas.
/// Revisions belong to one authenticated renderer session, not a socket/client.
class RendererState extends ChangeNotifier {
  RendererState({required this.sessionId, required this.frameReady});
  final String sessionId;
  final Future<void> Function() frameReady;
  OutputFrame _frame = const OutputFrame(revision: 0);
  OutputFrame get frame => _frame;
  int renderedRevision = 0;
  OutputConfiguration configuration = const OutputConfiguration();
  final Map<int, OutputFrame> _prepared = {};

  void notifyConfiguration() => notifyListeners();
  void discardPrepared() => _prepared.clear();

  void requireSession(Map<String, Object?> args) {
    if (args['session'] != sessionId) {
      throw const LocalRpcException(
        'wrong_session',
        'This command belongs to a different renderer session.',
      );
    }
  }

  Map<String, Object?> prepare(Map<String, Object?> args) {
    requireSession(args);
    final candidate = OutputFrame.fromMap(
      Map<String, Object?>.from(args['frame']! as Map),
    );
    _validateRevision(candidate);
    _validateFreeze(candidate);
    if (_prepared.length >= 8 && !_prepared.containsKey(candidate.revision)) {
      throw const LocalRpcException('busy', 'Too many prepared frames.');
    }
    _prepared[candidate.revision] = candidate;
    return {'revision': candidate.revision, 'prepared': true};
  }

  Future<Map<String, Object?>> commit(Map<String, Object?> args) async {
    requireSession(args);
    final revision = args['revision'];
    if (revision == _frame.revision && renderedRevision == revision) {
      return acknowledgement();
    }
    final candidate = _prepared.remove(revision);
    if (candidate == null) {
      throw const LocalRpcException(
        'not_prepared',
        'Prepare a valid frame before committing it.',
      );
    }
    _validateRevision(candidate);
    _validateFreeze(candidate);
    return _present(candidate);
  }

  Future<Map<String, Object?>> emergency(Map<String, Object?> args) async {
    requireSession(args);
    final candidate = OutputFrame.fromMap(
      Map<String, Object?>.from(args['frame']! as Map),
      validateLayout: false,
    );
    if (!candidate.emergency ||
        candidate.mode != OutputMode.black ||
        candidate.frozen) {
      throw const LocalRpcException(
        'invalid_emergency',
        'Emergency output must be black and unfrozen.',
      );
    }
    _validateRevision(candidate);
    _prepared.clear();
    return _present(candidate);
  }

  Future<Map<String, Object?>> _present(OutputFrame candidate) async {
    _frame = candidate;
    _prepared.removeWhere((revision, _) => revision <= candidate.revision);
    notifyListeners();
    await frameReady();
    renderedRevision = _frame.revision;
    if (_frame.revision != candidate.revision) {
      throw const LocalRpcException(
        'superseded',
        'A newer output command superseded this frame.',
      );
    }
    return acknowledgement();
  }

  Map<String, Object?> acknowledgement() => {
    'revision': _frame.revision,
    'renderedRevision': renderedRevision,
  };

  void _validateRevision(OutputFrame candidate) {
    if (candidate.revision <= _frame.revision) {
      throw const LocalRpcException(
        'stale_revision',
        'Output revision must increase within a session.',
      );
    }
  }

  void _validateFreeze(OutputFrame candidate) {
    if (!_frame.frozen || candidate.emergency) return;
    if (jsonEncode(candidate.slide?.toMap()) !=
            jsonEncode(_frame.slide?.toMap()) ||
        candidate.backgroundVisible != _frame.backgroundVisible ||
        candidate.mode == OutputMode.clear) {
      throw const LocalRpcException(
        'frozen',
        'Restore frozen output before changing its content.',
      );
    }
  }

  void cancel(Map<String, Object?> args) {
    requireSession(args);
    _prepared.remove(args['revision']);
  }
}
