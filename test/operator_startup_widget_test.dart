import 'dart:io';

import 'package:cantivra/application/operator_bootstrap.dart';
import 'package:cantivra/domain/models.dart';
import 'package:cantivra/presentation/desktop_output.dart';
import 'package:cantivra/presentation/live_controller.dart';
import 'package:cantivra/presentation/slides.dart';
import 'package:cantivra/ui/operator_app.dart';
import 'package:cantivra/ui/operator_startup_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecoveryOutput extends DesktopOutput {
  bool available = true;
  bool attached = false;
  int opens = 0;
  final frames = <OutputFrame>[];

  _RecoveryOutput() {
    recoveredFrame = const OutputFrame(
      revision: 42,
      mode: OutputMode.normal,
      frozen: true,
      slide: PresentationSlide(
        id: 'captured',
        sourceId: 'source',
        title: 'Captured congregation slide',
        label: 'Verse 1',
        text: 'Peace be with you.',
        theme: PresentationTheme(),
      ),
    );
  }

  @override
  bool get canControl => attached;
  @override
  bool get connected => attached;
  @override
  Future<bool> recoverExisting() async {
    attached = available;
    state = attached
        ? OutputConnectionState.ready
        : OutputConnectionState.reconnecting;
    return attached;
  }

  @override
  Future<void> open({
    String? targetDisplayId,
    bool fullscreen = false,
    double scale = 1,
    double safeInset = 0,
  }) async {
    opens++;
  }

  @override
  Future<int> publish(OutputFrame frame) async {
    frames.add(OutputFrame.fromMap(frame.toMap()));
    recoveredFrame = frames.last;
    return frame.revision;
  }
}

void main() {
  const channel = MethodChannel('cantivra/display');
  late Directory directory;
  late _RecoveryOutput output;
  late OperatorBootstrap bootstrap;
  const corruptBytes = [1, 2, 3, 4, 5, 6, 7];

  Future<void> prepareView(
    WidgetTester tester, {
    Size size = const Size(1180, 760),
  }) async {
    await tester.runAsync(() async {
      final fonts = <ByteData>[];
      final loader = FontLoader('Roboto');
      for (final weight in ['Regular', 'Medium', 'Bold']) {
        final bytes = ByteData.sublistView(
          await File('assets/fonts/Roboto-$weight.ttf').readAsBytes(),
        );
        fonts.add(bytes);
        loader.addFont(Future.value(bytes));
      }
      await loader.load();
      // These widget tests exercise actions/layout, not native font fidelity.
      for (final family in ['Georgia', 'Ahem']) {
        await (FontLoader(family)..addFont(Future.value(fonts.first))).load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'listDisplays') return <Object?>[];
          return null;
        });
    directory = await Directory.systemTemp.createTemp('cantivra-recovery-ui-');
    await File('${directory.path}/cantivra.sqlite').writeAsBytes(corruptBytes);
    output = _RecoveryOutput();
    bootstrap = OperatorBootstrap(
      directoryProvider: () async => directory,
      outputFactory: (_) => output,
    );
  });

  tearDown(() async {
    final repository = bootstrap.workspace?.repository;
    if (repository != null) await repository.close();
    bootstrap.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('corrupt library keeps F12 and explicit captured-slide restore', (
    tester,
  ) async {
    await prepareView(tester);
    await tester.runAsync(bootstrap.start);
    await tester.pumpWidget(OperatorStartupApp(bootstrap: bootstrap));
    await tester.pump();
    expect(find.text('Your library needs attention'), findsOneWidget);
    expect(output.frames, isEmpty);
    expect(output.opens, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();
    expect(output.frames, hasLength(1));
    expect(output.frames.single.mode, OutputMode.black);
    expect(output.frames.single.emergency, isTrue);
    expect(output.frames.single.frozen, isFalse);
    expect(output.frames.single.slide!.text, 'Peace be with you.');
    await tester.tap(find.byKey(const ValueKey('recovery-restore')));
    await tester.pump();
    expect(output.frames.last.mode, OutputMode.normal);
    expect(output.frames.last.slide!.text, 'Peace be with you.');
    expect(
      await tester.runAsync(
        () => File('${directory.path}/cantivra.sqlite').readAsBytes(),
      ),
      corruptBytes,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unreachable output cannot publish; reconnect does not launch', (
    tester,
  ) async {
    await prepareView(tester, size: const Size(800, 600));
    output.available = false;
    await tester.runAsync(bootstrap.start);
    await tester.pumpWidget(OperatorStartupApp(bootstrap: bootstrap));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('recovery-emergency')),
          )
          .onPressed,
      isNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();
    expect(output.frames, isEmpty);
    output.available = true;
    await tester.ensureVisible(
      find.byKey(const ValueKey('recovery-reconnect')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('recovery-reconnect')));
    await tester.pump();
    expect(output.opens, 0);
    expect(output.frames, isEmpty);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('recovery-emergency')),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('retry returns to workspace without revealing a blacked slide', (
    tester,
  ) async {
    await prepareView(tester);
    await tester.runAsync(bootstrap.start);
    await tester.pumpWidget(OperatorStartupApp(bootstrap: bootstrap));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pump();
    final held = output.frames.single.toMap();
    await tester.runAsync(
      () => File(
        '${directory.path}/cantivra.sqlite',
      ).rename('${directory.path}/preserved-corrupt-fixture.sqlite'),
    );
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('retry-library')));
      await bootstrap.retry();
    });
    await tester.pump();
    expect(find.byType(OperatorShell), findsOneWidget);
    expect(bootstrap.workspace!.live.frame.toMap(), held);
    expect(output.frames, hasLength(1));
    expect(output.opens, 0);
    expect(
      await tester.runAsync(
        () => File(
          '${directory.path}/preserved-corrupt-fixture.sqlite',
        ).readAsBytes(),
      ),
      corruptBytes,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
