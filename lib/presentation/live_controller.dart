import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'slides.dart';

enum OutputMode { normal, black, clear }

class OutputFrame {
  const OutputFrame({
    required this.revision,
    this.slide,
    this.mode = OutputMode.black,
    this.frozen = false,
    this.backgroundVisible = true,
    this.emergency = false,
  });

  final int revision;
  final PresentationSlide? slide;
  final OutputMode mode;
  final bool frozen;
  final bool backgroundVisible;
  final bool emergency;

  OutputFrame copyWith({
    int? revision,
    OutputMode? mode,
    bool? frozen,
    bool? backgroundVisible,
    bool? emergency,
  }) => OutputFrame(
    revision: revision ?? this.revision,
    slide: slide,
    mode: mode ?? this.mode,
    frozen: frozen ?? this.frozen,
    backgroundVisible: backgroundVisible ?? this.backgroundVisible,
    emergency: emergency ?? this.emergency,
  );

  Map<String, Object?> toMap() => {
    'protocol': 1,
    'revision': revision,
    'slide': slide?.toMap(),
    'mode': mode.name,
    'frozen': frozen,
    'backgroundVisible': backgroundVisible,
    'emergency': emergency,
  };

  factory OutputFrame.fromMap(
    Map<String, Object?> map, {
    bool validateLayout = true,
  }) {
    if (map['protocol'] != 1) {
      throw const FormatException('Unsupported output protocol');
    }
    final frame = OutputFrame(
      revision: map['revision']! as int,
      slide: map['slide'] == null
          ? null
          : PresentationSlide.fromMap(
              Map<String, Object?>.from(map['slide']! as Map),
            ),
      mode: OutputMode.values.byName(map['mode']! as String),
      frozen: map['frozen']! as bool,
      backgroundVisible: map['backgroundVisible']! as bool,
      emergency: map['emergency'] as bool? ?? false,
    );
    if (frame.revision < 0 || (frame.slide?.text.length ?? 0) > 50000) {
      throw const FormatException('Invalid output frame');
    }
    if (frame.slide case final slide?) {
      if (validateLayout && !SlideLayout.fits(slide.text, slide.theme)) {
        throw const FormatException('Slide overflows the output safe area');
      }
    }
    return frame;
  }
}

abstract interface class OutputTransport {
  bool get connected;
  Future<int> publish(OutputFrame frame);
}

/// The only route to changing output. Preview/editor state is never referenced
/// after publication. Local LIVE state changes only after the renderer ACKs.
class LiveController extends ChangeNotifier {
  LiveController(this.transport);
  final OutputTransport transport;
  OutputFrame _frame = const OutputFrame(revision: 0);
  OutputFrame get frame => _frame;
  List<PresentationSlide> _deck = const [];
  List<PresentationSlide> get deck => _deck;
  int _index = 0;
  int get index => _index;
  final Set<int> _pending = {};
  bool get busy => _pending.isNotEmpty;
  String? error;
  int _sequence = 0;

  Future<bool> goLive(List<PresentationSlide> slides, int index) async {
    if (_frame.frozen ||
        slides.isEmpty ||
        index < 0 ||
        index >= slides.length) {
      return false;
    }
    final snapshot = List<PresentationSlide>.unmodifiable(slides);
    return _commit(
      OutputFrame(
        revision: ++_sequence,
        slide: snapshot[index],
        mode: OutputMode.normal,
        backgroundVisible: _frame.backgroundVisible,
      ),
      onCommit: () {
        _deck = snapshot;
        _index = index;
      },
    );
  }

  Future<bool> next() => _navigate(1);
  Future<bool> previous() => _navigate(-1);
  Future<bool> _navigate(int delta) async {
    final target = _index + delta;
    if (_frame.frozen || target < 0 || target >= _deck.length) return false;
    return goLive(_deck, target);
  }

  Future<bool> black() => _commit(
    _frame.copyWith(
      revision: ++_sequence,
      mode: OutputMode.black,
      emergency: false,
    ),
  );
  Future<bool> clear() => _mode(OutputMode.clear);
  Future<bool> _mode(OutputMode mode) async {
    if (_frame.frozen) return false;
    return _commit(
      _frame.copyWith(revision: ++_sequence, mode: mode, emergency: false),
    );
  }

  Future<bool> freeze() => _commit(
    _frame.copyWith(revision: ++_sequence, frozen: true, emergency: false),
  );
  Future<bool> restore() => _commit(
    _frame.copyWith(
      revision: ++_sequence,
      frozen: false,
      mode: _frame.slide == null ? OutputMode.black : OutputMode.normal,
      emergency: false,
    ),
  );
  Future<bool> toggleBackground() async {
    if (_frame.frozen) return false;
    return _commit(
      _frame.copyWith(
        revision: ++_sequence,
        backgroundVisible: !_frame.backgroundVisible,
        emergency: false,
      ),
    );
  }

  Future<bool> emergencyStop() => _commit(
    _frame.copyWith(
      revision: ++_sequence,
      mode: OutputMode.black,
      frozen: false,
      emergency: true,
    ),
  );

  Future<bool> synchronize() => _commit(_frame.copyWith(revision: ++_sequence));

  /// Reattachment reads the renderer's actual snapshot; it never publishes a
  /// draft or replaces a surviving live frame with startup black.
  void reconcileOutput(OutputFrame remote) {
    if (busy) {
      throw StateError(
        'Wait for the pending output command before reconnecting.',
      );
    }
    _sequence = math.max(_sequence, remote.revision);
    if (remote.slide != null) {
      final index = _deck.indexWhere(
        (slide) =>
            jsonEncode(slide.toMap()) == jsonEncode(remote.slide!.toMap()),
      );
      if (index >= 0) {
        _index = index;
      } else {
        _deck = List.unmodifiable([remote.slide!]);
        _index = 0;
      }
      _frame = remote;
    } else {
      // A replacement renderer starts black. Retain the prior safe slide in
      // memory so Restore remains an explicit operator choice.
      _frame = OutputFrame(
        revision: remote.revision,
        slide: _frame.slide,
        mode: OutputMode.black,
        backgroundVisible: remote.backgroundVisible,
      );
    }
    error = null;
    notifyListeners();
  }

  Future<bool> _commit(OutputFrame candidate, {VoidCallback? onCommit}) async {
    if (busy && !candidate.emergency) return false;
    _pending.add(candidate.revision);
    error = null;
    notifyListeners();
    try {
      final ack = await transport.publish(candidate);
      if (ack != candidate.revision) {
        throw StateError(
          'Output did not acknowledge revision ${candidate.revision}.',
        );
      }
      // A newer emergency revision must never be overwritten by a late ACK.
      if (candidate.revision > _frame.revision) {
        _frame = candidate;
        onCommit?.call();
      }
      return true;
    } catch (e) {
      if (candidate.revision >= _frame.revision) {
        error = 'Output was not confirmed: $e';
      }
      return false;
    } finally {
      _pending.remove(candidate.revision);
      notifyListeners();
    }
  }
}
