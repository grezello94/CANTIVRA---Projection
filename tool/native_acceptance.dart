// Isolated native acceptance harness. Never use this entrypoint for packaging.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cantivra/application/workspace_controller.dart';
import 'package:cantivra/data/app_repository.dart';
import 'package:cantivra/domain/models.dart';
import 'package:cantivra/platform/display_bridge.dart';
import 'package:cantivra/platform/local_rpc.dart';
import 'package:cantivra/presentation/desktop_output.dart';
import 'package:cantivra/presentation/live_controller.dart';
import 'package:cantivra/presentation/renderer_runtime.dart';
import 'package:cantivra/presentation/renderer_session.dart';
import 'package:cantivra/presentation/slide_surface.dart';
import 'package:cantivra/presentation/slides.dart';
import 'package:cantivra/ui/operator_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'native_acceptance_support.dart';

void event(String type, Map<String, Object?> data) =>
    stdout.writeln('QA_EVENT ${jsonEncode({'type': type, ...data})}');

void verify(bool condition, String description) {
  if (!condition) throw StateError(description);
}

String normalize(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

const passages = {
  'english':
      'We gather in peace and give thanks for this day. May kindness guide our words and actions.',
  'tamil': 'அமைதி உங்களோடு இருப்பதாக. நாம் நன்றியுடன் ஒன்றுகூடுகிறோம்.',
  'malayalam': 'എല്ലാവർക്കും സമാധാനം. നന്ദിയോടെ നാം ഒന്നിച്ചുകൂടുന്നു.',
  'hindi': 'आप सबको शांति मिले। हम कृतज्ञता के साथ एकत्र होते हैं।',
  'arabic': 'السلام معكم. نجتمع معًا بقلوب شاكرة.',
  'hebrew': 'שלום לכולכם. אנו מתכנסים בלב מלא תודה.',
  'chinese': '願平安與你們同在。我們懷著感恩的心聚集。',
  'thai': 'ขอให้สันติสุขจงอยู่กับท่านทั้งหลายเราร่วมกันด้วยใจขอบคุณ',
  'combining':
      'Café, naïve, Å, 👨‍👩‍👧‍👦, 👩🏽‍💻. Peace and gratitude unite us.',
};

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final renderer = RendererLaunch.parse(args);
  if (renderer != null) {
    final builds = AcceptanceTimings(budgetMicroseconds: 16700);
    final rasters = AcceptanceTimings(budgetMicroseconds: 16700);
    final totals = AcceptanceTimings(budgetMicroseconds: 16700);
    final profilingClock = Stopwatch()..start();
    var writing = false;
    Future<void> saveFrameTimings() async {
      if (writing || builds.count == 0) return;
      writing = true;
      try {
        final view = ui.PlatformDispatcher.instance.views.firstOrNull;
        final file = File(
          '${File(renderer.sessionPath).parent.path}/renderer-timings.json',
        );
        await File('${file.path}.pending')
            .writeAsString(
              jsonEncode({
                'scope':
                    'Native Flutter renderer timing callbacks in windowed '
                    'rehearsal only; not a physical 1080p/60Hz acceptance run.',
                'windowedOnly': true,
                'elapsedSeconds': profilingClock.elapsedMilliseconds / 1000,
                'physicalWidth': view?.physicalSize.width,
                'physicalHeight': view?.physicalSize.height,
                'devicePixelRatio': view?.devicePixelRatio,
                'build': builds.toMap(),
                'raster': rasters.toMap(),
                'totalSpan': totals.toMap(),
              }),
              flush: true,
            )
            .then((pending) => pending.rename(file.path));
      } finally {
        writing = false;
      }
    }

    WidgetsBinding.instance.addTimingsCallback((frames) {
      for (final frame in frames) {
        builds.add(frame.buildDuration.inMicroseconds);
        rasters.add(frame.rasterDuration.inMicroseconds);
        totals.add(frame.totalSpan.inMicroseconds);
      }
      if (builds.count == frames.length) {
        unawaited(saveFrameTimings().catchError((Object _) {}));
      }
    });
    Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(saveFrameTimings().catchError((Object _) {}));
    });
    await runRenderer(renderer);
    return;
  }
  final durationArgument = args
      .where((arg) => arg.startsWith('--duration-seconds='))
      .firstOrNull;
  final seconds = int.tryParse(durationArgument?.split('=').last ?? '60');
  if (seconds == null || seconds < 1 || seconds > 86400) {
    stderr.writeln('Choose --duration-seconds=1..86400.');
    exit(2);
  }
  final flutterErrors = <String>[];
  FlutterError.onError = (details) {
    if (flutterErrors.length < 8) {
      flutterErrors.add(details.exceptionAsString());
    }
    FlutterError.presentError(details);
  };
  Directory? temporary;
  AppRepository? repository;
  DesktopOutput? output;
  WorkspaceController? controller;
  AcceptanceSocketRelay? relay;
  Directory? exports;
  Stopwatch? sustainedClock;
  final report = <String, Object?>{
    'version': 2,
    'status': 'running',
    'platform': Platform.operatingSystem,
    'os': Platform.operatingSystemVersion,
    'nativeFonts': true,
    'requestedDurationSeconds': seconds,
    'requestedDurationCompleted': false,
    'eightHourSoakCompleted': false,
    'eightHourSoftwareAcceptancePassed': false,
    'physicalHdmiVerified': false,
    'linguisticReaderReview': false,
    'operatorFlutterErrors': flutterErrors,
  };
  Future<void> checkpoint() async {
    final directory = exports;
    if (directory == null) return;
    if (sustainedClock != null) {
      report['actualDurationSeconds'] =
          sustainedClock.elapsedMilliseconds / 1000;
    }
    await File('${directory.path}/report.json.pending')
        .writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
          flush: true,
        )
        .then((file) => file.rename('${directory.path}/report.json'));
  }

  try {
    await NativeDisplayBridge.configureOperator();
    temporary = await Directory.systemTemp.createTemp('cantivra-acceptance-');
    exports = await Directory('${temporary.path}/exports').create();
    event('started', {'temporaryDirectory': temporary.path});
    final repo = repository = await AppRepository.open(
      '${temporary.path}/test.sqlite',
    );
    final seedWatch = Stopwatch()..start();
    const generatedRecords = 10000;
    final createdAt = DateTime.utc(2026, 11, 5);
    // Keep the queue bounded while SQLite saves each record on its worker.
    // Seed before controller initialization so sustained RSS includes the same
    // 10,005-row operator cache that the real application would retain.
    for (var start = 0; start < generatedRecords; start += 100) {
      await Future.wait([
        for (var index = start; index < start + 100; index++)
          repo.saveContent(
            ContentItem(
              id: 'benchmark-$index',
              title: 'Benchmark hymn $index',
              kind: index.isEven ? ContentKind.hymn : ContentKind.prayer,
              sourceText:
                  'Verse 1\nWe gather in hope and walk together in peace.\n'
                  'We share the gifts of this day with our community.\n\n'
                  'Refrain\nMay love guide every step we take.\n'
                  'May grace surround us as we serve.\n\n'
                  'Verse 2\nWe bring our joys and sorrows into this place.\n'
                  'In gratitude we lift our voices and sing.\n\n'
                  'Collection reference: Hymnal $index.\n'
                  'Search identifier: token${index}end',
              tags: ['benchmark', 'community'],
              modifiedAt: createdAt,
            ),
          ),
      ]);
    }
    seedWatch.stop();
    final libraryCount = (await repo.searchContent('')).length;
    verify(libraryCount == 10005, 'The representative library is incomplete.');
    final socketRelay = relay = await AcceptanceSocketRelay.start();
    final sessionPath = '${temporary.path}/renderer-session.json';
    final transport = output = DesktopOutput(
      sessionPath: sessionPath,
      launchRenderer: (launch) async {
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
        // Rewrite only this isolated harness's capability descriptor. The real
        // renderer retains the same session, process and authentication token.
        for (var attempt = 0; attempt < 120; attempt++) {
          final session = await RendererSession.read(launch.sessionPath);
          if (session?.sessionId == launch.sessionId &&
              session?.processId == process.pid) {
            socketRelay.destinationPort = session!.port;
            // The runner can still shut down only this authenticated test
            // renderer if the operator (and its relay) is interrupted.
            await session.write(
              '${temporary!.path}/renderer-cleanup-session.json',
            );
            await RendererSession(
              sessionId: session.sessionId,
              token: session.token,
              port: socketRelay.port,
              processId: session.processId,
              createdAt: session.createdAt,
            ).write(launch.sessionPath);
            return process.pid;
          }
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
        throw StateError('The test renderer did not publish its endpoint.');
      },
    );
    final c = controller = WorkspaceController(
      repository: repo,
      output: transport,
      dataDirectory: temporary.path,
    );
    await c.initialize();
    verify(
      c.results.length == libraryCount,
      'The operator did not load the complete representative library.',
    );
    runApp(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Cantivra acceptance test'))),
      ),
    );
    await rendererFrameReady();
    await c.openOutput();
    c.edit(
      sourceText:
          '[Verse 1]\nA captured first slide.\n\n[Verse 2]\nA captured second slide.',
    );
    await c.flushSave();
    verify(await c.publishSelected(), 'Baseline publication failed.');
    final baseline = jsonEncode(c.live.frame.toMap());
    final cases = <Map<String, Object?>>[];
    report['corpus'] = cases;
    for (final entry in passages.entries) {
      final source = List.filled(18, entry.value).join(' ');
      final item = ContentItem(
        id: 'qa-${entry.key}',
        title: entry.key,
        kind: ContentKind.reading,
        sourceText: source,
        modifiedAt: DateTime.utc(2026, 11, 5),
      );
      for (final large in [false, true]) {
        final theme = PresentationTheme(
          fontSize: large ? 96 : 68,
          safeMargin: large ? .12 : .08,
          lineHeight: large ? 1.6 : 1.35,
          verticalAlignment: large ? 'bottom' : 'center',
        );
        final watch = Stopwatch()..start();
        final slides = await SlideLayout.compileAsync(item, theme);
        verify(
          slides.isNotEmpty &&
              slides.every((slide) => SlideLayout.fits(slide.text, theme)),
          '${entry.key}: measured overflow',
        );
        verify(
          normalize(slides.map((slide) => slide.text).join(' ')) ==
              normalize(source),
          '${entry.key}: text lost or reordered',
        );
        var measuredPages = 0;
        for (var index = 0; index < slides.length; index++) {
          final key = GlobalKey();
          runApp(
            MaterialApp(
              home: Scaffold(
                backgroundColor: Colors.black,
                body: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: SlideSurface(
                        slide: slides[index],
                        safeGuides: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await rendererFrameReady();
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final safe = Rect.fromLTWH(
            boundary.size.width * theme.safeMargin,
            boundary.size.height * theme.safeMargin,
            boundary.size.width * (1 - 2 * theme.safeMargin),
            boundary.size.height * (1 - 2 * theme.safeMargin),
          );
          void inspect(RenderObject object) {
            if (object is RenderParagraph) {
              final rect = MatrixUtils.transformRect(
                object.getTransformTo(boundary),
                Offset.zero & object.size,
              );
              verify(
                rect.left >= safe.left - 1 &&
                    rect.top >= safe.top - 1 &&
                    rect.right <= safe.right + 1 &&
                    rect.bottom <= safe.bottom + 1,
                '${entry.key}: painted text box exceeds safe area',
              );
              measuredPages++;
            }
            object.visitChildren(inspect);
          }

          boundary.visitChildren(inspect);
          if (index == 0 || index == slides.length - 1) {
            final image = await boundary.toImage(
              pixelRatio: 1920 / boundary.size.width,
            );
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '${exports.path}/${entry.key}_${large ? 'large' : 'normal'}_$index.png',
              ).writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
            } finally {
              image.dispose();
            }
          }
        }
        verify(
          measuredPages >= slides.length,
          'No native text boxes were inspected.',
        );
        verify(
          jsonEncode((await transport.inspect())['frame']) == baseline,
          'Corpus preparation mutated live output.',
        );
        cases.add({
          'language': entry.key,
          'source': source,
          'fontFamily': theme.fontFamily,
          'fontSize': theme.fontSize,
          'slides': slides.length,
          'measuredTextBoxes': measuredPages,
          'elapsedMs': watch.elapsedMilliseconds,
          'safeBounds': true,
          'sourceConserved': true,
        });
        event('corpus', cases.last);
      }
    }
    final operatorBoundary = GlobalKey();
    runApp(
      RepaintBoundary(
        key: operatorBoundary,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Banner(
            message: 'ISOLATED ACCEPTANCE',
            location: BannerLocation.topEnd,
            color: Colors.red.shade800,
            child: CantivraApp(controller: c),
          ),
        ),
      ),
    );
    await rendererFrameReady();
    report['operatorWorkload'] =
        'Actual CantivraApp widgets with the complete 10,005-row content cache; '
        'isolated test workspace and visible acceptance banner.';
    final originalDraftSource = c.selected!.sourceText;
    final draftTimings = AcceptanceTimings();
    final draftSamples = <Map<String, Object?>>[];
    report['draftPaint'] = {
      'scope':
          'Synthetic controller edit to completed Flutter build/layout/paint '
          'in actual operator widgets; excludes OS keyboard and input delivery '
          'latency and physical scanout. No font-size reduction.',
      'samples': draftSamples,
    };
    for (var index = 0; index < 100; index++) {
      final text = 'Prepared correction $index stays in preview.';
      final watch = Stopwatch()..start();
      c.edit(sourceText: text);
      await rendererFrameReady();
      watch.stop();
      verify(
        c.preview?.text == text && !c.layoutPending && c.layoutError == null,
        'An ordinary draft did not update the preview.',
      );
      final boundary =
          operatorBoundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      var matchingPaintedParagraphs = 0;
      void inspectPreview(RenderObject object) {
        if (object is RenderParagraph &&
            object.attached &&
            object.hasSize &&
            object.size.width > 0 &&
            object.size.height > 0 &&
            object.text.toPlainText() == text) {
          matchingPaintedParagraphs++;
        }
        object.visitChildren(inspectPreview);
      }

      boundary.visitChildren(inspectPreview);
      verify(
        matchingPaintedParagraphs > 0,
        'The actual operator did not paint the corrected preview text.',
      );
      verify(
        jsonEncode((await transport.inspect())['frame']) == baseline,
        'An ordinary operator edit changed the published live frame.',
      );
      draftTimings.add(watch.elapsedMicroseconds);
      draftSamples.add({
        'index': index,
        'elapsedMicroseconds': watch.elapsedMicroseconds,
        'matchingLaidOutParagraphs': matchingPaintedParagraphs,
        'liveFrameUnchanged': true,
      });
    }
    c.edit(sourceText: originalDraftSource);
    await c.flushSave();
    await rendererFrameReady();
    (report['draftPaint']! as Map<String, Object?>)['timings'] = draftTimings
        .toMap();
    event('draft_paint', {
      'samples': draftSamples.length,
      'timings': draftTimings.toMap(),
      'actualOperatorWidgets': true,
      'osInputLatencyIncluded': false,
    });
    verify(
      jsonEncode((await transport.inspect())['frame']) == baseline,
      'Large-library preparation changed live output.',
    );
    final queryEvidence = <Map<String, Object?>>[];
    final searchTimings = AcceptanceTimings(budgetMicroseconds: 100000);
    final searchReport = <String, Object?>{
      'generatedRecords': generatedRecords,
      'libraryRecords': libraryCount,
      'seedElapsedMs': seedWatch.elapsedMilliseconds,
      'warmupQueries': 20,
      'measuredQueries': queryEvidence,
      'querySemantics':
          'FTS token AND/prefix; quoted strings do not promise adjacent phrases',
    };
    report['search'] = searchReport;
    Future<Map<String, Object?>> query(int run) async {
      final index = 1000 + (run * 73) % 9000;
      final prefix = (index ~/ 100).toString();
      final type = switch (run % 4) {
        0 => 'exact_identifier',
        1 => 'identifier_prefix',
        2 => 'title',
        _ => 'quoted_multiword_and_prefix',
      };
      final text = switch (run % 4) {
        0 => 'token${index}end',
        1 => 'token$prefix',
        2 => 'Benchmark hymn $index',
        _ => '"Hymnal $index"',
      };
      final expected = run % 4 == 1
          ? {
              for (var candidate = 0; candidate < generatedRecords; candidate++)
                if (candidate.toString().startsWith(prefix))
                  'benchmark-$candidate',
            }
          : {'benchmark-$index'};
      final watch = Stopwatch()..start();
      final matches = await repo.searchContent(text);
      watch.stop();
      final actual = matches.map((item) => item.id).toSet();
      verify(
        matches.length == expected.length &&
            actual.length == expected.length &&
            actual.containsAll(expected),
        'Search result mismatch for $type query $text.',
      );
      return {
        'query': text,
        'type': type,
        'elapsedMicroseconds': watch.elapsedMicroseconds,
        'resultCount': matches.length,
        'expectedCount': expected.length,
        'matchedIds': actual.toList()..sort(),
        'verified': true,
      };
    }

    for (var run = 0; run < 120; run++) {
      final measured = await query(run);
      if (run >= 20) {
        queryEvidence.add(measured);
        searchTimings.add(measured['elapsedMicroseconds']! as int);
      }
    }
    searchReport['timings'] = searchTimings.toMap();
    final broadWatch = Stopwatch()..start();
    final broadResults = await repo.searchContent('"we gather in hope"');
    broadWatch.stop();
    final broadIds = broadResults.map((item) => item.id).toSet();
    verify(
      broadResults.length == 10001 &&
          broadIds.length == 10001 &&
          broadIds.contains('sample-gathering') &&
          List.generate(
            generatedRecords,
            (index) => broadIds.contains('benchmark-$index'),
          ).every((found) => found),
      'The broad lyric query lost or duplicated results.',
    );
    searchReport['broadQuery'] = {
      'query': '"we gather in hope"',
      'resultCount': broadResults.length,
      'expectedCount': 10001,
      'expectedIds': 'benchmark-0..benchmark-9999 and sample-gathering',
      'elapsedMs': broadWatch.elapsedMicroseconds / 1000,
      'unboundedResultTransfer': true,
      'verified': true,
    };
    event('search', {
      'libraryRecords': libraryCount,
      'warmupQueries': 20,
      'measuredQueries': queryEvidence.length,
      'timings': searchTimings.toMap(),
      'broadQuery': searchReport['broadQuery'],
    });

    final injectedFailures = <Map<String, Object?>>[];
    report['failureInjections'] = injectedFailures;
    Future<void> verifyHeld(String captured, String action) async {
      final actual = await transport.inspect();
      verify(
        jsonEncode(actual['frame']) == captured &&
            jsonEncode(c.live.frame.toMap()) == captured,
        '$action changed the last-good live frame.',
      );
    }

    Future<void> rejectNoncriticalFailures() async {
      await c.flushSave();
      final captured = jsonEncode(c.live.frame.toMap());
      final original = (await repo.getContent(c.selected!.id))!;
      var saveRejected = false;
      try {
        await repo.saveContent(original.copyWith(title: '  '));
      } on RepositoryException {
        saveRejected = true;
      }
      verify(saveRejected, 'Invalid repository operation was not rejected.');
      verify(
        jsonEncode((await repo.getContent(original.id))!.toMap()) ==
            jsonEncode(original.toMap()),
        'The failed repository transaction changed stable content.',
      );
      await verifyHeld(captured, 'Failed repository transaction');
      injectedFailures.add({
        'type': 'invalid_repository_save',
        'transactionRolledBack': true,
        'liveFrameUnchanged': true,
      });

      c.edit(sourceText: List.filled(50001, 'x').join());
      verify(
        c.layoutError != null &&
            c.previewSlides.isEmpty &&
            !await c.publishSelected(),
        'An invalid draft was allowed to publish.',
      );
      await verifyHeld(captured, 'Rejected invalid draft');
      c.edit(sourceText: original.sourceText);
      await c.flushSave();
      injectedFailures.add({
        'type': 'invalid_oversize_draft',
        'publicationRefused': true,
        'liveFrameUnchanged': true,
      });

      var prepareRejected = false;
      try {
        await transport.publish(
          OutputFrame(
            revision: c.live.frame.revision + 1,
            mode: OutputMode.normal,
            slide: PresentationSlide(
              id: 'qa-invalid-frame',
              sourceId: original.id,
              title: 'Rejected layout',
              label: 'Overflow',
              text: List.filled(1000, 'UnbreakableOverflow').join(' '),
              theme: c.theme,
            ),
          ),
        );
      } on LocalRpcException catch (error) {
        verify(
          error.code == 'invalid_frame',
          'Prepare failed with an unexpected error: ${error.code}.',
        );
        prepareRejected = true;
      }
      verify(
        prepareRejected,
        'Renderer accepted an overflowing prepared frame.',
      );
      await verifyHeld(captured, 'Rejected renderer prepare');
      injectedFailures.add({
        'type': 'invalid_renderer_prepare',
        'typedRejection': 'invalid_frame',
        'liveFrameUnchanged': true,
      });
      event('noncritical_failures', {'verifiedCases': 3});
    }

    Future<void> disconnectAndRecover() async {
      final captured = jsonEncode(c.live.frame.toMap());
      final processId = transport.processId;
      final sessionId = transport.sessionId;
      final connectionsBefore = socketRelay.acceptedConnections;
      final watch = Stopwatch()..start();
      socketRelay.dropConnections();
      var restored = false;
      while (watch.elapsed < const Duration(seconds: 12)) {
        if (socketRelay.acceptedConnections > connectionsBefore &&
            transport.connected) {
          await verifyHeld(captured, 'Transport disconnect/reconnect');
          verify(
            transport.processId == processId &&
                transport.sessionId == sessionId,
            'Reconnect replaced the original renderer.',
          );
          restored = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      verify(
        restored,
        'Transport did not reconnect to the surviving renderer.',
      );
      injectedFailures.add({
        'type': 'control_socket_disconnect_reconnect',
        'elapsedMs': watch.elapsedMicroseconds / 1000,
        'sameRendererProcess': true,
        'sameRendererSession': true,
        'liveFrameUnchanged': true,
      });
      event('transport_reconnected', injectedFailures.last);
    }

    await rejectNoncriticalFailures();
    // Short diagnostic runs also prove repeated connection recovery.
    await disconnectAndRecover();
    await disconnectAndRecover();
    final samples = <Map<String, Object?>>[];
    report['memorySamples'] = samples;
    final timings = AcceptanceTimings();
    final sustainedSearchTimings = AcceptanceTimings(
      budgetMicroseconds: 100000,
    );
    final clock = sustainedClock = Stopwatch()..start();
    var transitions = 0;
    var nextSample = Duration.zero;
    var nextDisconnect = const Duration(seconds: 30);
    var nextNoncriticalFailure = const Duration(seconds: 60);
    while (clock.elapsed < Duration(seconds: seconds)) {
      verify(flutterErrors.isEmpty, 'Operator UI error: $flutterErrors');
      final watch = Stopwatch()..start();
      verify(
        await (transitions.isEven ? c.live.next() : c.live.previous()),
        'Navigation failed during sustained operation.',
      );
      timings.add(watch.elapsedMicroseconds);
      transitions++;
      if (transitions % 10 == 0) {
        final result = await query(transitions ~/ 10);
        sustainedSearchTimings.add(result['elapsedMicroseconds']! as int);
        c.edit(
          sourceText: 'Unpublished sustained-test correction $transitions.',
        );
      }
      if (clock.elapsed >= nextDisconnect) {
        await disconnectAndRecover();
        nextDisconnect += const Duration(seconds: 30);
      }
      if (clock.elapsed >= nextNoncriticalFailure) {
        await rejectNoncriticalFailures();
        nextNoncriticalFailure += const Duration(seconds: 60);
      }
      if (clock.elapsed >= nextSample) {
        final info = await transport.inspect();
        verify(
          jsonEncode(info['frame']) == jsonEncode(c.live.frame.toMap()),
          'Live acknowledgement diverged.',
        );
        final resources = Map<String, Object?>.from(info['resources']! as Map);
        final rendererRss = resources['rssBytes']! as int;
        final operatorRss = ProcessInfo.currentRss;
        verify(
          rendererRss > 0 && operatorRss > 0,
          'RSS telemetry is unavailable.',
        );
        samples.add({
          'elapsedSeconds': clock.elapsedMilliseconds / 1000,
          'transitions': transitions,
          'operatorRssBytes': operatorRss,
          'rendererRssBytes': rendererRss,
          'combinedRssBytes': operatorRss + rendererRss,
        });
        event('memory', samples.last);
        report['transitions'] = transitions;
        report['navigationTimings'] = timings.toMap();
        report['sustainedSearchTimings'] = sustainedSearchTimings.toMap();
        await checkpoint();
        nextSample += const Duration(seconds: 10);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    clock.stop();
    verify(flutterErrors.isEmpty, 'Operator UI error: $flutterErrors');
    await c.flushSave();
    verify(
      await repo.integrityCheck() == 'ok',
      'Post-run database integrity failed.',
    );
    final navigation = timings.toMap();
    final memoryTotals = samples
        .map((sample) => sample['combinedRssBytes']! as int)
        .toList();
    final maximumRss = memoryTotals.reduce((a, b) => a > b ? a : b);
    final eightHours = seconds >= 28800 && clock.elapsed.inSeconds >= 28800;
    final frameTimingFile = File('${temporary.path}/renderer-timings.json');
    if (await frameTimingFile.exists()) {
      try {
        verify(
          await frameTimingFile.length() <= 100000,
          'The private renderer timing snapshot exceeded its bound.',
        );
        report['rendererFrameTimings'] = jsonDecode(
          await frameTimingFile.readAsString(),
        );
      } catch (error) {
        report['rendererFrameTimingReadError'] = '$error';
      }
    } else {
      report['rendererFrameTimings'] = {
        'status': 'unavailable',
        'scope': 'No native Flutter frame timing snapshot was received.',
      };
    }
    report.addAll({
      'status': 'functional_checks_passed',
      'acceptanceStatus': 'partial_software_evidence',
      'requestedDurationCompleted': clock.elapsed.inSeconds >= seconds,
      'actualDurationSeconds': clock.elapsedMilliseconds / 1000,
      'eightHourSoakCompleted': eightHours,
      'eightHourScenarioPassed':
          eightHours &&
          transitions >= 1000 &&
          injectedFailures
                  .where(
                    (item) =>
                        item['type'] == 'control_socket_disconnect_reconnect',
                  )
                  .length >=
              2,
      'transitions': transitions,
      'navigationTimings': navigation,
      // Compatibility fields explicitly describe the bounded recent window.
      'timingSampleCount': navigation['sampleCount'],
      'p50Ms': navigation['p50Ms'],
      'p95Ms': navigation['p95Ms'],
      'maxSampleMs': navigation['maxSampleMs'],
      'maxAllRunMs': navigation['maxAllRunMs'],
      'sustainedSearchTimings': sustainedSearchTimings.toMap(),
      'databaseIntegrity': 'ok',
      'memorySummary': {
        'firstCombinedRssBytes': memoryTotals.first,
        'lastCombinedRssBytes': memoryTotals.last,
        'maxCombinedRssBytes': maximumRss,
        'firstToLastChangeBytes': memoryTotals.last - memoryTotals.first,
        'idleTextTargetBytes': 350000000,
        'allObservedSamplesBelowIdleTarget': maximumRss <= 350000000,
        'scope':
            'Sustained 10,005-row text workload after native-font PNG capture; '
            'RSS includes caches. These are sampled values, not a peak-allocation '
            'or isolated idle benchmark. Bounded growth requires review over '
            'the actual duration.',
      },
      'performanceBudgetObservations': {
        'warmSearchP95AtMost100Ms': searchTimings
            .toMap()['allRunP95WithinThreshold'],
        'navigationAllRunP95AtMost50Ms': navigation['allRunP95WithinThreshold'],
        'syntheticDraftEditToPaintP95AtMost50Ms': draftTimings
            .toMap()['allRunP95WithinThreshold'],
        'fullPerformanceBudgetPassed': false,
        'unmeasuredRequirements': [
          'OS keyboard delivery to preview latency (synthetic edit only measured)',
          'Renderer frame timing p95 at 1080p/60 Hz',
          'Physical display scanout latency and flicker',
          'Representative-hardware idle memory and long-term growth review',
        ],
      },
      'workerFailureScope':
          'Rejected repository save with transaction rollback; '
          'does not simulate killing or restarting the SQLite worker.',
    });
    await transport.close();
    await repo.getSetting('__acceptance_barrier__');
    c.dispose();
    controller = null;
    transport.dispose();
    output = null;
    await repo.close();
    repository = null;
    await socketRelay.close();
    relay = null;
    report['normalShutdownVerified'] = true;
    await checkpoint();
    event('complete', {
      'exportDirectory': exports.path,
      'temporaryDirectory': temporary.path,
      'transitions': transitions,
      'durationSeconds': report['actualDurationSeconds'],
    });
    await stdout.flush();
    exit(0);
  } catch (error, stack) {
    sustainedClock?.stop();
    report.addAll({'status': 'failed', 'error': '$error', 'stack': '$stack'});
    try {
      await output?.close();
    } catch (cleanupError) {
      report['rendererCleanupError'] = '$cleanupError';
    }
    controller?.dispose();
    output?.dispose();
    await repository?.close();
    await relay?.close();
    try {
      await checkpoint();
    } catch (reportError) {
      report['reportWriteError'] = '$reportError';
    }
    event('failed', {
      'error': '$error',
      'stack': '$stack',
      'exportDirectory': exports?.path,
      'temporaryDirectory': temporary?.path,
    });
    await stdout.flush();
    exit(1);
  }
}
