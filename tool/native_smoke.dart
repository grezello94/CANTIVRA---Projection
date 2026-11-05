// Real native process tests. Use dart run tool/run_native_smoke.dart macos.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cantivra/application/operator_bootstrap.dart';
import 'package:cantivra/application/workspace_controller.dart';
import 'package:cantivra/data/app_repository.dart';
import 'package:cantivra/domain/models.dart';
import 'package:cantivra/platform/app_lifecycle.dart';
import 'package:cantivra/platform/display_bridge.dart';
import 'package:cantivra/platform/local_rpc.dart';
import 'package:cantivra/presentation/desktop_output.dart';
import 'package:cantivra/presentation/live_controller.dart';
import 'package:cantivra/presentation/renderer_runtime.dart';
import 'package:cantivra/presentation/renderer_session.dart';
import 'package:cantivra/presentation/slides.dart';
import 'package:cantivra/ui/operator_app.dart';
import 'package:cantivra/ui/operator_startup_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void check(bool value, String label) {
  if (!value) throw StateError(label);
  stdout.writeln('PASS: $label');
}

String? option(List<String> args, String name) => args
    .where((arg) => arg.startsWith('$name='))
    .firstOrNull
    ?.substring(name.length + 1);

Future<void> storageRecoverySmoke() async {
  final directory = await Directory.systemTemp.createTemp(
    'cantivra-storage-smoke-',
  );
  final database = File('${directory.path}/cantivra.sqlite');
  const invalidDatabase = 'A deliberately invalid isolated SQLite fixture.';
  await database.writeAsString(invalidDatabase, flush: true);
  final sessionPath = '${directory.path}/renderer-session.json';
  final initialOutput = DesktopOutput(sessionPath: sessionPath);
  OperatorBootstrap? bootstrap;
  try {
    runApp(const MaterialApp(home: Scaffold(body: Text('Recovery test'))));
    await rendererFrameReady();
    // Explicit fixture setup. Production startup only inspects this process.
    await initialOutput.open();
    await initialOutput.publish(
      const OutputFrame(
        revision: 71,
        mode: OutputMode.normal,
        frozen: true,
        slide: PresentationSlide(
          id: 'storage-live',
          sourceId: 'captured-source',
          title: 'Captured before storage failure',
          label: 'Live',
          text: 'The congregation keeps this captured slide.',
          theme: PresentationTheme(),
        ),
      ),
    );
    final before = await initialOutput.inspect();
    final rendererPid = initialOutput.processId;
    initialOutput.dispose(); // Release control without stopping the renderer.
    final b = bootstrap = OperatorBootstrap(
      directoryProvider: () async => directory,
    );
    DesktopLifecycle.install(b.prepareClose);
    runApp(OperatorStartupApp(bootstrap: b));
    await b.start();
    final reconnectDeadline = Stopwatch()..start();
    while (!(b.output?.canControl ?? false) &&
        reconnectDeadline.elapsed < const Duration(seconds: 3)) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await b.reconnectExisting();
    }
    check(
      b.workspace == null && b.startupError != null,
      'Corrupt storage opens the real recovery interface',
    );
    check(
      b.output!.processId == rendererPid &&
          jsonEncode((await b.output!.inspect())['frame']) ==
              jsonEncode(before['frame']),
      'Library startup failure preserves the same renderer and exact frame',
    );
    check(
      await database.readAsString() == invalidDatabase,
      'Failed startup does not replace the corrupt test database',
    );
    check(
      await b.performOutputAction(
        b.recoveryLive!.emergencyStop,
        emergency: true,
      ),
      'Emergency black works through recovery without opening the library',
    );
    final black = (await b.output!.inspect())['frame'];
    check(
      (black as Map)['mode'] == 'black' && black['emergency'] == true,
      'Independent renderer acknowledges the recovery emergency',
    );
    await b.retry();
    check(
      b.workspace == null &&
          jsonEncode((await b.output!.inspect())['frame']) ==
              jsonEncode(black) &&
          b.output!.processId == rendererPid,
      'Failed library retry cannot reveal or replace the captured output',
    );
    // Preserve the bad fixture, then simulate repaired storage only here.
    await database.rename('${directory.path}/preserved-corrupt-fixture');
    await b.retry();
    check(
      b.workspace != null && b.startupError == null,
      'Explicit retry opens healthy storage without restarting the operator',
    );
    check(
      jsonEncode(b.workspace!.live.frame.toMap()) == jsonEncode(black) &&
          jsonEncode((await b.output!.inspect())['frame']) == jsonEncode(black),
      'Healthy workspace adopts the emergency frame without publishing',
    );
    b.workspace!.edit(sourceText: 'A recovery correction saved before Quit.');
    DesktopLifecycle.install(() async {
      try {
        check(await b.prepareClose(), 'Recovery bootstrap accepts a safe Quit');
        final repository = b.workspace!.repository;
        final selectedId = b.workspace!.selected!.id;
        await repository.close();
        final reopened = await AppRepository.open(database.path);
        check(
          (await reopened.getContent(selectedId))!.sourceText ==
              'A recovery correction saved before Quit.',
          'Recovered workspace correction survives native Quit and reopen',
        );
        await reopened.close();
        check(
          !await NativeDisplayBridge.isProcessRunning(rendererPid!),
          'Recovered workspace Quit closes its renderer process',
        );
        runApp(const SizedBox.shrink());
        await rendererFrameReady();
        b.dispose();
        bootstrap = null;
        await directory.delete(recursive: true);
        stdout.writeln('STORAGE_RECOVERY_SMOKE_OK');
        await stdout.flush();
        return true;
      } catch (error, stack) {
        stdout.writeln('NATIVE_CLOSE_FAILED: $error\n$stack');
        return false;
      }
    });
    await NativeDisplayBridge.requestOperatorClose();
    await Future<void>.delayed(const Duration(seconds: 10));
    throw StateError('Storage recovery native Quit did not terminate.');
  } catch (_) {
    try {
      await bootstrap?.output?.close();
      await bootstrap?.workspace?.repository.close();
    } catch (_) {}
    bootstrap?.dispose();
    rethrow;
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final renderer = RendererLaunch.parse(args);
  if (renderer != null) {
    try {
      await NativeDisplayBridge.requestOperatorClose();
      throw StateError('Presentation process accepted operator Quit');
    } on PlatformException catch (error) {
      check(
        error.code == 'WRONG_WINDOW',
        'Presentation process cannot invoke operator Quit',
      );
    }
    await runRenderer(renderer);
    return;
  }
  DesktopOutput? output;
  try {
    await NativeDisplayBridge.configureOperator();
    if (option(args, '--smoke-role') == 'storage-startup') {
      await storageRecoverySmoke();
      return;
    }
    final provided = option(args, '--smoke-workspace');
    final directory = provided == null
        ? await Directory.systemTemp.createTemp('cantivra-phase2-')
        : Directory(provided);
    await directory.create(recursive: true);
    final repo = await AppRepository.open('${directory.path}/library.sqlite');
    output = DesktopOutput(
      sessionPath: '${directory.path}/renderer-session.json',
    );
    final c = WorkspaceController(
      repository: repo,
      output: output,
      dataDirectory: directory.path,
    );
    await c.initialize();
    runApp(CantivraApp(controller: c));
    await WidgetsBinding.instance.endOfFrame;
    await c.openOutput();
    check(
      output.processId != pid,
      'Congregation renderer is a separate OS process',
    );
    check(
      (await output.inspect())['window'] is Map,
      'Renderer reports native window status',
    );
    final role = option(args, '--smoke-role');
    if (role == 'recover') {
      final expected = jsonDecode(
        await File('${directory.path}/expected-frame.json').readAsString(),
      );
      check(
        jsonEncode(c.live.frame.toMap()) == jsonEncode(expected),
        'New operator adopts the surviving live frame without republishing',
      );
      check(
        c.live.frame.frozen,
        'Renderer retains freeze state across operator crash',
      );
      check(
        c.selected!.sourceText ==
            'An unpublished correction saved before operator failure.',
        'Saved draft is recovered independently of live text',
      );
      check(
        c.recoveredDraftCount == 1 && !c.saved,
        'Uncommitted recovery journal restores into an editable draft',
      );
      check(
        (await repo.getContent(c.selected!.id))!.sourceText !=
            c.selected!.sourceText,
        'Journal recovery preserves the previously committed library version',
      );
      check(
        await c.live.emergencyStop(),
        'Recovered operator can immediately black the frozen renderer',
      );
      check(
        await c.live.restore(),
        'Recovered operator can restore the captured slide',
      );
      await output.close();
      await repo.close();
      stdout.writeln('RECOVERY_SMOKE_OK');
      await stdout.flush();
      exit(0);
    }
    check(
      await c.publishSelected(),
      'Prepared frame is committed and acknowledged',
    );
    final first = await output.inspect();
    check(
      first['renderedRevision'] == c.live.frame.revision,
      'ACK follows renderer frame readiness',
    );
    if (role == 'hold') {
      await c.live.freeze();
      await File(
        '${directory.path}/expected-frame.json',
      ).writeAsString(jsonEncode(c.live.frame.toMap()), flush: true);
      c.edit(
        sourceText: 'An unpublished correction saved before operator failure.',
      );
      await c.flushJournal();
      // Cancel the stable autosave after verifying journal-only durability.
      // The runner kills this test operator once the readiness marker arrives.
      runApp(
        const MaterialApp(home: Scaffold(body: Text('Draft recovery test'))),
      );
      await WidgetsBinding.instance.endOfFrame;
      c.dispose();
      check(
        (await repo.getContent(c.selected!.id))!.sourceText !=
            c.selected!.sourceText,
        'Crash fixture has a journaled correction that is not committed',
      );
      await repo.getSetting('__barrier__');
      stdout.writeln(
        'OPERATOR_HOLD_READY:${base64Url.encode(utf8.encode(directory.path))}',
      );
      await stdout.flush();
      await Completer<void>().future;
      return;
    }
    final times = <int>[];
    const navigationCount = 1000;
    for (var i = 0; i < navigationCount; i++) {
      final watch = Stopwatch()..start();
      if (!await (i.isEven ? c.live.next() : c.live.previous())) {
        throw StateError('Native navigation ${i + 1} failed');
      }
      times.add(watch.elapsedMicroseconds);
      if (i % 25 == 0) {
        check(
          (await repo.searchContent('grace')).isNotEmpty,
          'Search during navigation ${i + 1}',
        );
      }
      if (i % 100 == 99) {
        c.edit(sourceText: 'Background draft correction ${i + 1}.');
      }
    }
    check(
      times.length == navigationCount,
      '1,000 transitions with search and draft autosave workload',
    );
    times.sort();
    stdout.writeln(
      'NATIVE_NAVIGATION: samples=$navigationCount; '
      'p50=${times[times.length ~/ 2] / 1000}ms; '
      'p95=${times[(times.length * .95).ceil() - 1] / 1000}ms; '
      'max=${times.last / 1000}ms; ${Platform.operatingSystemVersion}',
    );
    final beforeEdit = await output.inspect();
    c.edit(sourceText: 'A correction prepared independently.');
    await c.flushSave();
    await c.applyTheme(c.theme.copyWith(fontSize: 88));
    check(
      jsonEncode((await output.inspect())['frame']) ==
          jsonEncode(beforeEdit['frame']),
      'Edits and themes never mutate the actual live frame',
    );
    await c.live.freeze();
    check(
      !await c.publishSelected(),
      'Frozen output refuses a new publication',
    );
    check(await c.live.emergencyStop(), 'Emergency black overrides freeze');
    check(
      ((await output.inspect())['frame'] as Map)['mode'] == 'black',
      'Independent renderer is black',
    );
    check(await c.live.restore(), 'Restore recovers prior output');
    final retained = (await output.inspect())['frame'];
    try {
      await const MethodChannel('cantivra/display').invokeMethod<void>(
        'configureOutput',
        {'displayId': 42, 'fullscreen': true},
      );
      throw StateError('Malformed output destination accepted');
    } on PlatformException catch (error) {
      check(
        error.code == 'INVALID_OUTPUT_ARGUMENTS',
        'Malformed display destination rejected without rehearsal fallback',
      );
    }
    check(
      jsonEncode((await output.inspect())['frame']) == jsonEncode(retained),
      'Malformed native display command preserves renderer frame',
    );
    try {
      await output.open(targetDisplayId: 'missing-display', fullscreen: true);
      throw StateError('Missing display accepted');
    } on LocalRpcException catch (error) {
      check(
        error.code == 'DISPLAY_UNAVAILABLE',
        'Missing display rejected with no fallback',
      );
    }
    check(
      jsonEncode((await output.inspect())['frame']) == jsonEncode(retained),
      'Failed display change retains last-known-good frame',
    );
    final displays = await NativeDisplayBridge.listDisplays();
    final primary = displays.where((display) => display.isPrimary).first;
    try {
      await output.open(targetDisplayId: primary.id, fullscreen: true);
      throw StateError('Primary display accepted');
    } on LocalRpcException catch (error) {
      check(
        error.code == 'PRIMARY_DISPLAY_RESERVED',
        'Operator primary display is reserved',
      );
    }
    await output.open(scale: .9, safeInset: .02);
    check(
      (output.canvasScale - .864).abs() < .000001,
      'Explicit calibration applies scale and safe inset',
    );
    check(
      jsonEncode((await output.inspect())['frame']) == jsonEncode(retained),
      'Calibration preserves captured text and theme',
    );
    check(
      await c.publishSelected(),
      'Corrected draft publishes only on request',
    );
    check(
      (((await output.inspect())['frame'] as Map)['slide'] as Map)['text'] ==
          'A correction prepared independently.',
      'Renderer contains the corrected text',
    );
    final beforeStructure = (await output.inspect())['frame'];
    const structuredSource =
        'Verse 1\nWe gather in peace.\nWe lift our voices.\n\nChorus\nTogether we sing.';
    c.edit(sourceText: structuredSource);
    c.applyStructure(c.recognitionSuggestion!.structure);
    c.splitAtSourceOffset(structuredSource.indexOf('We lift'));
    await c.applyTheme(
      c.theme.copyWith(
        lineHeight: 1.6,
        paragraphSpacing: 30,
        verticalAlignment: 'bottom',
        textDirection: 'auto',
      ),
    );
    await c.flushSave();
    check(
      c.selected!.sourceText == structuredSource && c.previewSlides.length == 3,
      'Reviewed hymn structure and manual split preserve original source',
    );
    check(
      jsonEncode((await output.inspect())['frame']) ==
          jsonEncode(beforeStructure),
      'Structure, spacing and alignment edits leave actual output unchanged',
    );
    check(await c.publishSelected(), 'Structured layout publishes explicitly');
    final structuredFrame = (await output.inspect())['frame'];
    final actualTheme =
        ((structuredFrame as Map)['slide'] as Map)['theme'] as Map;
    check(
      actualTheme['lineHeight'] == 1.6 &&
          actualTheme['paragraphSpacing'] == 30 &&
          actualTheme['verticalAlignment'] == 'bottom',
      'Separate renderer receives the complete Phase 3 typography snapshot',
    );
    final version = (await c.versions()).firstWhere(
      (version) => version.sourceText == 'A correction prepared independently.',
    );
    await c.restoreVersion(version);
    check(
      jsonEncode((await output.inspect())['frame']) ==
          jsonEncode(structuredFrame),
      'Restoring a revision changes only the draft',
    );
    c.edit(sourceText: 'https://${List.filled(3000, 'unbroken').join()}');
    while (c.layoutPending) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    check(
      c.layoutError != null && !await c.publishSelected(),
      'Unreadable unbroken content reports overflow and refuses publication',
    );
    check(
      jsonEncode((await output.inspect())['frame']) ==
          jsonEncode(structuredFrame),
      'Overflow retains the renderer last-known-good slide',
    );
    c.undo();
    await c.flushSave();
    await c.live.clear();
    check(
      ((await output.inspect())['frame'] as Map)['mode'] ==
          OutputMode.clear.name,
      'Clear text',
    );
    await c.live.restore();
    await c.live.toggleBackground();
    check(
      ((await output.inspect())['frame'] as Map)['backgroundVisible'] == false,
      'Hide background',
    );
    final crashedPid = output.processId!;
    check(
      Process.killPid(crashedPid, ProcessSignal.sigkill),
      'Fault injection terminates only the renderer test process',
    );
    for (
      var i = 0;
      i < 40 && await NativeDisplayBridge.isProcessRunning(crashedPid);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await c.openOutput();
    check(
      output.processId != crashedPid,
      'Operator starts a replacement renderer explicitly',
    );
    check(
      ((await output.inspect())['frame'] as Map)['mode'] == 'black',
      'Replacement renderer starts black without replaying a draft',
    );
    check(
      await c.live.restore(),
      'Operator explicitly restores the captured slide after renderer replacement',
    );
    final beforeRefusedQuit = await output.inspect();
    final beforeRefusedQuitPid = output.processId;
    final refused = Completer<void>();
    DesktopLifecycle.install(() async {
      // Signal on the next event turn so the false method-channel reply can
      // leave Dart before the harness proceeds with another native request.
      Timer.run(() {
        if (!refused.isCompleted) refused.complete();
      });
      return false;
    });
    await NativeDisplayBridge.requestOperatorClose();
    await refused.future.timeout(const Duration(seconds: 3));
    // A native round trip also verifies that the operator engine stayed alive.
    await NativeDisplayBridge.outputStatus();
    check(
      output.connected &&
          output.processId == beforeRefusedQuitPid &&
          jsonEncode((await output.inspect())['frame']) ==
              jsonEncode(beforeRefusedQuit['frame']),
      'Refused native quit leaves both processes and the live frame unchanged',
    );
    c.edit(sourceText: 'A final draft safely saved on close.');
    Future<void> finish() async {
      do {
        await c.flushSave();
      } while (!c.saved);
      final child = output!.processId!;
      await output.close();
      check(
        !await NativeDisplayBridge.isProcessRunning(child),
        'Normal close shuts down renderer process',
      );
      final id = c.selected!.id;
      runApp(const SizedBox.shrink());
      await WidgetsBinding.instance.endOfFrame;
      c.dispose();
      output.dispose();
      await repo.close();
      final reopened = await AppRepository.open(
        '${directory.path}/library.sqlite',
      );
      check(
        (await reopened.getContent(id))!.sourceText ==
            'A final draft safely saved on close.',
        'Close flush survives SQLite reopen',
      );
      await reopened.close();
      if (provided == null) await directory.delete(recursive: true);
      stdout.writeln('NATIVE_SMOKE_OK');
      await stdout.flush();
    }

    DesktopLifecycle.install(() async {
      try {
        await finish();
        return true;
      } catch (error, stack) {
        stdout.writeln('NATIVE_CLOSE_FAILED: $error\n$stack');
        return false;
      }
    });
    await NativeDisplayBridge.requestOperatorClose();
    // The native app must exit after the accepted quit.
    await Future<void>.delayed(const Duration(seconds: 10));
    throw StateError('Native quit did not terminate the operator.');
  } catch (error, stack) {
    stdout.writeln('NATIVE_SMOKE_FAILED: $error\n$stack');
    try {
      await output?.close();
    } catch (_) {}
    await stdout.flush();
    exit(1);
  }
}
