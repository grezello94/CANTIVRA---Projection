import 'dart:async';

import 'package:flutter/services.dart';

/// A native display. Coordinates use Cocoa points on macOS and physical pixels
/// on Windows; [scale] maps logical pixels to the display's backing pixels.
/// Pass [id] back to the native bridge rather than calculating window positions.
class DisplayInfo {
  const DisplayInfo({
    required this.id,
    required this.name,
    required this.isPrimary,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.scale,
    this.isOutputEligible = true,
    this.unavailableReason,
  });

  factory DisplayInfo.fromMap(Map<Object?, Object?> map) => DisplayInfo(
    id: map['id']! as String,
    name: map['name']! as String,
    isPrimary: map['isPrimary']! as bool,
    x: (map['x']! as num).toDouble(),
    y: (map['y']! as num).toDouble(),
    width: (map['width']! as num).toDouble(),
    height: (map['height']! as num).toDouble(),
    scale: (map['scale']! as num).toDouble(),
    isOutputEligible: map['isOutputEligible'] as bool? ?? true,
    unavailableReason: map['unavailableReason'] as String?,
  );

  final String id;
  final String name;
  final bool isPrimary;
  final double x;
  final double y;
  final double width;
  final double height;
  final double scale;

  /// False when native discovery cannot distinguish a safe output target.
  final bool isOutputEligible;
  final String? unavailableReason;
}

/// Each Flutter engine owns its channel and controls only its own native window.
/// Missing displays are errors: the bridge never guesses a replacement screen.
abstract final class NativeDisplayBridge {
  static const _channel = MethodChannel('cantivra/display');
  static final _changes = StreamController<Map<String, Object?>>.broadcast(
    onListen: () => _channel.setMethodCallHandler(_handleNativeEvent),
    onCancel: () => _channel.setMethodCallHandler(null),
  );

  /// Native status and topology notifications. A fresh [outputStatus] query
  /// supplies initial state; this broadcast stream does not replay old events.
  static Stream<Map<String, Object?>> get changes => _changes.stream;

  static Future<void> _handleNativeEvent(MethodCall call) async {
    if (call.method != 'displayChanged') return;
    final payload = call.arguments;
    if (payload is! Map) {
      throw PlatformException(
        code: 'INVALID_DISPLAY_EVENT',
        message: 'The native display event did not contain a status map.',
      );
    }
    _changes.add(
      Map<String, Object?>.unmodifiable(Map<String, Object?>.from(payload)),
    );
  }

  static Future<Map<String, Object?>> outputStatus() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'getOutputStatus',
    );
    if (result == null) {
      throw PlatformException(code: 'STATUS_UNAVAILABLE');
    }
    return Map<String, Object?>.unmodifiable(result);
  }

  /// A read-only liveness check. Native access-denied results are conservatively
  /// treated as alive, so an unreachable session cannot spawn a duplicate.
  static Future<bool> isProcessRunning(int pid) async {
    if (pid <= 0) return false;
    final result = await _channel.invokeMethod<bool>('isProcessRunning', {
      'pid': pid,
    });
    if (result == null) {
      throw PlatformException(code: 'PROCESS_STATUS_UNAVAILABLE');
    }
    return result;
  }

  static Future<List<DisplayInfo>> listDisplays() async {
    final result = await _channel.invokeListMethod<Object?>('listDisplays');
    return (result ?? const <Object?>[])
        .map((value) => DisplayInfo.fromMap(value! as Map<Object?, Object?>))
        .toList(growable: false);
  }

  /// Call from the presentation engine only, after its initial black frame.
  /// A null [displayId] always opens a windowed rehearsal on the primary screen.
  static Future<void> configureOutput({
    String? displayId,
    bool fullscreen = false,
  }) {
    if (displayId != null && displayId.trim().isEmpty) {
      return Future<void>.error(
        ArgumentError.value(
          displayId,
          'displayId',
          'Choose a nonempty display ID',
        ),
      );
    }
    return _channel.invokeMethod<void>('configureOutput', {
      'displayId': displayId,
      'fullscreen': fullscreen,
    });
  }

  static Future<void> configureOperator() =>
      _channel.invokeMethod<void>('configureOperator');

  /// Requests the operator's normal native Quit action. This only queues the
  /// request: the OS still waits for DesktopLifecycle's save acknowledgement,
  /// and a refused save leaves both the operator and live output running.
  /// Presentation processes are never allowed to invoke this action.
  static Future<void> requestOperatorClose() =>
      _channel.invokeMethod<void>('requestOperatorClose');

  static Future<void> hideOutput() => _channel.invokeMethod<void>('hideOutput');

  static Future<void> closeOutput() =>
      _channel.invokeMethod<void>('closeOutput');
}
