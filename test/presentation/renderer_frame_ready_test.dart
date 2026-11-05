import 'package:cantivra/presentation/live_controller.dart';
import 'package:cantivra/presentation/renderer_runtime.dart';
import 'package:cantivra/presentation/renderer_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'renderer_process_test.dart' show frame;

class _PaintFrame extends CustomPainter {
  _PaintFrame(this.mode, this.onPaint);
  final OutputMode mode;
  final void Function(OutputMode) onPaint;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = mode == OutputMode.black ? Colors.black : Colors.white,
    );
    onPaint(mode);
  }

  @override
  bool shouldRepaint(_PaintFrame oldDelegate) => oldDelegate.mode != mode;
}

Future<void> _lifecycle(AppLifecycleState state) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'flutter/lifecycle',
          const StringCodec().encodeMessage(state.toString()),
          (_) {},
        );

void main() {
  testWidgets(
    'hidden renderer paints before acknowledging normal and emergency revisions',
    (tester) async {
      const session = 'frame-readiness';
      final state = RendererState(
        sessionId: session,
        frameReady: rendererFrameReady,
      );
      OutputMode? painted;
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: state,
          builder: (_, _) => CustomPaint(
            painter: _PaintFrame(state.frame.mode, (mode) {
              painted = mode;
            }),
          ),
        ),
      );
      expect(painted, OutputMode.black);
      try {
        await _lifecycle(AppLifecycleState.hidden);
        expect(tester.binding.framesEnabled, isFalse);
        state.prepare({
          'session': session,
          'frame': frame(1, 'A prepared scene').toMap(),
        });
        final normal = await state.commit({'session': session, 'revision': 1});
        expect(normal['renderedRevision'], 1);
        expect(
          painted,
          OutputMode.normal,
          reason: 'The acknowledgement must follow the paint phase.',
        );
        expect(
          tester.binding.framesEnabled,
          isFalse,
          reason: 'Rendering must not resume or focus a hidden window.',
        );
        final emergency = await state.emergency({
          'session': session,
          'frame': const OutputFrame(revision: 2, emergency: true).toMap(),
        });
        expect(emergency['renderedRevision'], 2);
        expect(painted, OutputMode.black);
        expect(tester.binding.lifecycleState, AppLifecycleState.hidden);
        expect(tester.takeException(), isNull);
      } finally {
        await _lifecycle(AppLifecycleState.resumed);
        await tester.pumpWidget(const SizedBox.shrink());
        state.dispose();
      }
    },
  );
}
