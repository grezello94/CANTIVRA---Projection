import 'dart:io';
import 'dart:ui' as ui;

import 'package:cantivra/application/workspace_controller.dart';
import 'package:cantivra/data/app_repository.dart';
import 'package:cantivra/presentation/desktop_output.dart';
import 'package:cantivra/presentation/live_controller.dart';
import 'package:cantivra/ui/operator_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises real SQLite and shell actions while substituting only the native
/// output window. Physical HDMI and native engine tests have a separate suite.
class _WidgetOutput extends DesktopOutput {
  @override
  String? displayId;
  @override
  bool fullscreen = false;
  final frames = <OutputFrame>[];
  final opens = <Map<String, Object?>>[];

  @override
  bool get connected => true;

  @override
  OutputFrame? get recoveredFrame => frames.lastOrNull;

  @override
  Future<void> open({
    String? targetDisplayId,
    bool fullscreen = false,
    double scale = 1,
    double safeInset = 0,
  }) async {
    opens.add({
      'displayId': targetDisplayId,
      'fullscreen': fullscreen,
      'scale': scale,
      'safeInset': safeInset,
    });
    displayId = targetDisplayId;
    this.fullscreen = fullscreen;
  }

  @override
  Future<int> publish(OutputFrame frame) async {
    frames.add(OutputFrame.fromMap(frame.toMap()));
    return frame.revision;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const displayChannel = MethodChannel('cantivra/display');
  late Directory temporary;
  late AppRepository repository;
  late _WidgetOutput output;
  late WorkspaceController controller;
  WidgetTester? activeTester;
  final uiFonts = <ByteData>[];

  setUpAll(() async {
    // Use the exact bundled UI fonts instead of the test engine's Ahem glyphs.
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      uiFonts.add(
        ByteData.sublistView(
          await File('assets/fonts/Roboto-$weight.ttf').readAsBytes(),
        ),
      );
    }
  });

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(displayChannel, (call) async {
          if (call.method != 'listDisplays') return null;
          return [
            {
              'id': 'operator',
              'name': 'Laptop',
              'isPrimary': true,
              'x': 0,
              'y': 0,
              'width': 1440,
              'height': 900,
              'scale': 1,
            },
            {
              'id': 'hdmi',
              'name': 'Congregation',
              'isPrimary': false,
              'x': 1440,
              'y': 0,
              'width': 1920,
              'height': 1080,
              'scale': 1,
            },
          ];
        });
    temporary = await Directory.systemTemp.createTemp('cantivra-ui-test-');
    repository = await AppRepository.open('${temporary.path}/library.sqlite');
    output = _WidgetOutput();
    controller = WorkspaceController(
      repository: repository,
      output: output,
      dataDirectory: temporary.path,
    );
    await controller.initialize();
  });

  tearDown(() async {
    Future<void> close() async {
      await repository.getSetting('__test_barrier__');
      controller.dispose();
      output.dispose();
      await repository.close();
      await temporary.delete(recursive: true);
    }

    if (activeTester != null) {
      await activeTester!.runAsync(close);
    } else {
      await close();
    }
    activeTester = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(displayChannel, null);
  });

  Future<void> showApp(
    WidgetTester tester,
    Size size, {
    GlobalKey? screenshotKey,
  }) async {
    activeTester = tester;
    await tester.runAsync(() async {
      final loader = FontLoader('Roboto');
      for (final font in uiFonts) {
        loader.addFont(Future.value(font));
      }
      await loader.load();
      // Output font fidelity is verified in native tests, not the widget engine.
      for (final family in ['Georgia', 'Menlo', 'Ahem']) {
        await (FontLoader(family)..addFont(Future.value(uiFonts.first))).load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: screenshotKey,
        child: CantivraApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.runAsync(() async {
      await repository.getSetting('__test_barrier__');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pumpAndSettle();
  }

  Future<void> waitFor(WidgetTester tester, bool Function() condition) async {
    for (var attempt = 0; attempt < 50 && !condition(); attempt++) {
      await drain(tester);
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(condition(), isTrue, reason: 'The UI action did not finish.');
  }

  Future<void> flushDraft(WidgetTester tester) async {
    var done = false;
    Object? failure;
    // The save may already be queued by a FakeAsync timer. Keep pumping that
    // zone while the real SQLite worker completes rather than awaiting a fake
    // zone future from tester.runAsync, which would pause its completion.
    controller.flushSave().then<void>(
      (_) => done = true,
      onError: (Object error) {
        failure = error;
        done = true;
      },
    );
    await waitFor(tester, () => done);
    expect(failure, isNull);
  }

  Future<void> navigate(WidgetTester tester, WorkspacePage page) async {
    final label = '${page.name[0].toUpperCase()}${page.name.substring(1)}';
    await tester.tap(find.text(label).first);
    await drain(tester);
    expect(controller.page, page);
    expect(
      tester.takeException(),
      isNull,
      reason: '$label must render without layout overflow.',
    );
  }

  for (final size in [const Size(1440, 900), const Size(1180, 760)]) {
    testWidgets('all sidebar pages work at ${size.width} × ${size.height}', (
      tester,
    ) async {
      await showApp(tester, size);
      expect(find.text('Service workspace'), findsOneWidget);
      expect(find.text('LIVE OUTPUT'), findsOneWidget);
      expect(find.text('PREVIEW'), findsOneWidget);
      expect(controller.live.frame.mode, OutputMode.black);
      expect(output.frames, isEmpty);
      expect(tester.takeException(), isNull);

      for (final page in WorkspacePage.values) {
        await navigate(tester, page);
      }
      expect(
        output.frames,
        isEmpty,
        reason: 'Navigation and filtering cannot publish.',
      );
    });
  }

  testWidgets('editing and theme selection remain in preview until Go live', (
    tester,
  ) async {
    await showApp(tester, const Size(1440, 900));
    await tester.tap(find.text('Go live · selected slide'));
    await waitFor(tester, () => output.frames.isNotEmpty);
    final published = controller.live.frame.toMap();
    final sent = output.frames.length;
    const correction = 'A volunteer correction ready for review.';

    await tester.enterText(
      find.byKey(const ValueKey('source-text')),
      correction,
    );
    await tester.pump();
    expect(controller.preview!.text, correction);
    expect(controller.live.frame.toMap(), published);
    expect(output.frames, hasLength(sent));
    expect(find.text(correction), findsWidgets);

    await navigate(tester, WorkspacePage.themes);
    await tester.tap(find.text('Sanctuary'));
    await drain(tester);
    expect(controller.preview!.theme.id, 'sanctuary');
    expect(controller.live.frame.toMap(), published);
    expect(output.frames, hasLength(sent));
    await navigate(tester, WorkspacePage.hymns);
    await waitFor(
      tester,
      () => controller.results.every((item) => item.kind.name == 'hymn'),
    );
    expect(controller.live.frame.toMap(), published);

    await tester.tap(find.text('Go live · selected slide'));
    await waitFor(tester, () => output.frames.length > sent);
    expect(controller.live.frame.slide!.text, correction);
    expect(controller.live.frame.slide!.theme.id, 'sanctuary');
    await flushDraft(tester);
    final stored = await tester.runAsync(
      () => repository.getContent(controller.selected!.id),
    );
    expect(stored!.sourceText, correction);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'new content dialog, search and Add to service persist real data',
    (tester) async {
      await showApp(tester, const Size(1440, 900));
      await navigate(tester, WorkspacePage.library);
      await tester.tap(find.text('New content'));
      await tester.pumpAndSettle();
      const title = 'A volunteer-created hymn';
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        title,
      );
      await tester.tap(find.text('Create'));
      await waitFor(tester, () => controller.selected?.title == title);
      expect(controller.previewSlides, isNotEmpty);
      expect(output.frames, isEmpty);

      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Search titles, words, or a phrase…',
      );
      await tester.enterText(search, 'volunteer-created');
      await tester.pump(const Duration(milliseconds: 150));
      await waitFor(
        tester,
        () =>
            controller.results.length == 1 &&
            controller.results.single.title == title,
      );
      final before = controller.service!.items.length;
      await tester.tap(find.byTooltip('Add to current service'));
      await waitFor(
        tester,
        () => controller.service!.items.length == before + 1,
      );
      expect(controller.service!.items.last.contentId, controller.selected!.id);
      final saved = await tester.runAsync(() => repository.listServices());
      expect(saved!.single.items.length, before + 1);
      expect(output.frames, isEmpty);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'transport controls operate without publishing a draft implicitly',
    (tester) async {
      await showApp(tester, const Size(1440, 900));
      await tester.tap(find.text('Go live · selected slide'));
      await waitFor(tester, () => output.frames.isNotEmpty);
      final text = controller.live.frame.slide!.text;
      for (final control in [
        'Clear text',
        'Black',
        'Restore',
        'Freeze',
        'Emergency',
      ]) {
        await tester.tap(find.text(control));
        await tester.pumpAndSettle();
        expect(controller.live.frame.slide!.text, text);
        expect(tester.takeException(), isNull);
      }
      expect(controller.live.frame.mode, OutputMode.black);
      expect(controller.live.frame.emergency, isTrue);
    },
  );

  testWidgets(
    'output profile controls prepare, save and explicitly apply a display setup',
    (tester) async {
      await showApp(tester, const Size(1440, 900));
      await tester.tap(find.text('Go live · selected slide'));
      await waitFor(tester, () => output.frames.isNotEmpty);
      final published = controller.live.frame.toMap();
      final publishedCount = output.frames.length;
      await navigate(tester, WorkspacePage.settings);
      expect(find.text('CONNECTED DISPLAYS'), findsOneWidget);
      expect(find.text('Primary · operator display'), findsOneWidget);
      expect(find.text('Secondary · presentation available'), findsOneWidget);

      final name = find.widgetWithText(TextFormField, 'Windowed rehearsal');
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Main church profile');
      await tester.pump();
      final scale = find.byKey(const ValueKey('output-scale'));
      await tester.ensureVisible(scale);
      final slider = tester.widget<Slider>(scale);
      slider.onChanged!(.9);
      await tester.pump();
      expect(controller.outputProfileDraft.scale, .9);
      expect(controller.live.frame.toMap(), published);
      expect(output.opens, isEmpty);
      expect(output.frames, hasLength(publishedCount));

      final save = find.text('Save profile');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await waitFor(tester, () => !controller.hasPreparedOutputChanges);
      expect(controller.selectedOutputProfile!.name, 'Main church profile');
      expect(output.opens, isEmpty);
      expect(controller.live.frame.toMap(), published);

      final apply = find.text('Apply / open output');
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await waitFor(tester, () => output.opens.isNotEmpty);
      await drain(tester);
      expect(output.opens.single, {
        'displayId': null,
        'fullscreen': false,
        'scale': .9,
        'safeInset': 0.0,
      });
      expect(controller.live.frame.toMap(), published);
      expect(output.frames, hasLength(publishedCount));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reviewed structure, split and merge prepare only the draft', (
    tester,
  ) async {
    final screenshotKey = GlobalKey();
    await showApp(tester, const Size(1180, 760), screenshotKey: screenshotKey);
    await tester.ensureVisible(find.text('Go live · selected slide'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go live · selected slide'));
    await waitFor(tester, () => output.frames.isNotEmpty);
    final live = controller.live.frame.toMap();
    final publishedCount = output.frames.length;
    const source =
        'Verse 1\nWe gather in peace.\nWe lift our voices.\n\nChorus\nTogether we sing.';
    await tester.enterText(find.byKey(const ValueKey('source-text')), source);
    await tester.pump();
    expect(controller.selected!.structure, isNull);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('source-text')),
    );
    final offset = source.indexOf('We lift');
    field.controller!.selection = TextSelection.collapsed(offset: offset);
    await tester.tap(find.byKey(const ValueKey('content-tools')));
    await drain(tester);
    expect(find.textContaining('Suggested hymn'), findsOneWidget);
    final label = find
        .byWidgetPredicate(
          (widget) =>
              widget is TextFormField &&
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'review-label-',
              ),
        )
        .first;
    final structureScroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('structure-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    structureScroll.position.jumpTo(structureScroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.enterText(label, 'Opening verse');
    final apply = find.byKey(const ValueKey('apply-reviewed-structure'));
    await tester.tap(apply);
    await tester.pump();
    expect(
      controller.selected!.structure!.sections.first.label,
      'Opening verse',
    );
    expect(controller.previewSlides.first.label, contains('Opening verse'));
    expect(controller.selected!.sourceText, source);
    final split = find.byKey(const ValueKey('split-at-source-cursor'));
    structureScroll.position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(split);
    await tester.pump();
    expect(controller.selected!.structure!.splitOffsets, contains(offset));
    final count = controller.previewSlides.length;
    await tester.tap(find.byKey(const ValueKey('merge-next-slide')));
    await tester.pump();
    expect(controller.previewSlides.length, lessThan(count));
    expect(controller.selected!.sourceText, source);
    expect(controller.live.frame.toMap(), live);
    expect(output.frames, hasLength(publishedCount));
    await tester.pumpAndSettle();
    final boundary =
        screenshotKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'build/qa/content-tools-1180x760.png',
        ).writeAsBytes(png!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
    await tester.tap(find.byTooltip('Close content tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Undo source edit'));
    await tester.pump();
    expect(controller.selected!.structure!.splitOffsets, contains(offset));
    expect(controller.live.frame.toMap(), live);
    expect(tester.takeException(), isNull);
    await flushDraft(tester);
    await tester.tap(find.byKey(const ValueKey('content-tools')));
    await drain(tester);
    expect(find.widgetWithText(TextFormField, 'Opening verse'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('apply-reviewed-structure')));
    await tester.pump();
    expect(controller.selected!.structure!.splitOffsets, contains(offset));
    expect(controller.live.frame.toMap(), live);
    await tester.tap(find.byTooltip('Close content tools'));
    await tester.pumpAndSettle();
    await flushDraft(tester);
  });

  testWidgets(
    'layout controls recalculate preview without changing live output',
    (tester) async {
      await showApp(tester, const Size(1180, 760));
      await tester.ensureVisible(find.text('Go live · selected slide'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go live · selected slide'));
      await waitFor(tester, () => output.frames.isNotEmpty);
      final live = controller.live.frame.toMap();
      final sent = output.frames.length;
      await tester.tap(find.byKey(const ValueKey('content-tools')));
      await drain(tester);
      await tester.tap(find.text('Layout').last);
      await tester.pumpAndSettle();
      final lineHeight = find.byKey(const ValueKey('line-height'));
      await tester.ensureVisible(lineHeight);
      tester.widget<Slider>(lineHeight).onChanged!(1.7);
      await drain(tester);
      expect(controller.theme.lineHeight, 1.7);
      final spacing = find.byKey(const ValueKey('paragraph-spacing'));
      await tester.ensureVisible(spacing);
      tester.widget<Slider>(spacing).onChanged!(35);
      await drain(tester);
      expect(controller.theme.paragraphSpacing, 35);
      expect(controller.preview!.theme.lineHeight, 1.7);
      expect(controller.live.frame.toMap(), live);
      expect(output.frames, hasLength(sent));
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.f12);
      await waitFor(tester, () => controller.live.frame.emergency);
      expect(controller.live.frame.mode, OutputMode.black);
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.byTooltip('Close content tools'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'history restores a saved revision and editor follows undo shortcuts',
    (tester) async {
      await showApp(tester, const Size(1440, 900));
      await tester.tap(find.text('Go live · selected slide'));
      await waitFor(tester, () => output.frames.isNotEmpty);
      final live = controller.live.frame.toMap();
      const first = 'A saved first revision.';
      const second = 'A saved second revision.';
      await tester.enterText(find.byKey(const ValueKey('source-text')), first);
      await flushDraft(tester);
      await tester.enterText(find.byKey(const ValueKey('source-text')), second);
      await flushDraft(tester);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('content-tools')));
      await drain(tester);
      await tester.tap(find.text('History').last);
      await drain(tester);
      final tiles = find.byType(ExpansionTile);
      expect(tiles, findsAtLeastNWidgets(2));
      await tester.tap(tiles.at(1));
      await tester.pumpAndSettle();
      final restore = find.text('Restore to draft');
      await tester.ensureVisible(restore);
      await tester.tap(restore);
      await waitFor(tester, () => find.byType(Dialog).evaluate().isEmpty);
      expect(controller.selected!.sourceText, first);
      var field = tester.widget<TextField>(
        find.byKey(const ValueKey('source-text')),
      );
      expect(field.controller!.text, first);
      await tester.tap(find.byKey(const ValueKey('source-text')));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(controller.selected!.sourceText, second);
      field = tester.widget<TextField>(
        find.byKey(const ValueKey('source-text')),
      );
      expect(field.controller!.text, second);
      expect(controller.live.frame.toMap(), live);
      expect(tester.takeException(), isNull);
      await flushDraft(tester);
    },
  );

  testWidgets('operator screenshot artifact at normal desktop size', (
    tester,
  ) async {
    final key = GlobalKey();
    await showApp(tester, const Size(1440, 900), screenshotKey: key);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('build/qa');
        await directory.create(recursive: true);
        await File(
          '${directory.path}/operator-1440x900.png',
        ).writeAsBytes(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  });
}
