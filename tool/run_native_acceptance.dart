import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cantivra/presentation/renderer_session.dart';

import 'acceptance_cleanup.dart';
import 'harness_build.dart';

Future<void> main(List<String> args) async {
  final platform = args.firstOrNull ?? (Platform.isMacOS ? 'macos' : 'windows');
  final durationArg =
      args.where((arg) => arg.startsWith('--duration-seconds=')).firstOrNull ??
      '--duration-seconds=60';
  final seconds = int.tryParse(durationArg.split('=').last);
  if (!{'macos', 'windows'}.contains(platform) ||
      seconds == null ||
      seconds < 1 ||
      seconds > 86400) {
    stderr.writeln(
      'Usage: dart run tool/run_native_acceptance.dart macos|windows --duration-seconds=60',
    );
    exitCode = 2;
    return;
  }
  final runId = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
  final artifactDirectory = Directory('build/qa/native-acceptance/$runId');
  await artifactDirectory.create(recursive: true);
  final statusFile = File('build/qa/native-acceptance/latest-run.json');
  int? nativeOperatorPid;
  Future<void> recordStatus(String value, {String? error}) async {
    final data = jsonEncode({
      'status': value,
      'runDirectory': artifactDirectory.path,
      'requestedDurationSeconds': seconds,
      'runnerPid': pid,
      'nativeOperatorPid': ?nativeOperatorPid,
      'updatedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'error': ?error,
    });
    // Each run owns a status file; latest-run.json is only a convenience pointer.
    for (final file in [
      File('${artifactDirectory.path}/status.json'),
      statusFile,
    ]) {
      final staging = File('${file.path}.$runId.tmp');
      await staging.writeAsString(data, flush: true);
      await staging.rename(file.path);
    }
  }

  await recordStatus('running');
  final log = File('${artifactDirectory.path}/events.ndjson').openWrite();
  Process? active;
  Process? sleepAssertion;
  Directory? testDirectory;
  Map<String, Object?>? exportedEvent;
  Future<void> copyArtifacts(Map<String, Object?> data) async {
    final exports = Directory(data['exportDirectory']! as String);
    final temporary = Directory(data['temporaryDirectory']! as String);
    if (temporary.path != testDirectory?.path ||
        !temporary.path.contains('cantivra-acceptance-') ||
        exports.parent.path != temporary.path) {
      throw StateError('Refusing an unexpected artifact directory.');
    }
    if (!await exports.exists()) return;
    for (final file in exports.listSync(followLinks: false).whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (RegExp(r'^[a-z0-9_-]+\.(png|json)$').hasMatch(name)) {
        await file.copy('${artifactDirectory.path}/$name');
      }
    }
  }

  var interrupted = false;
  final interruptions = <StreamSubscription<ProcessSignal>>[];
  void interrupt(ProcessSignal signal) {
    interrupted = true;
    active?.kill(ProcessSignal.sigterm);
  }

  interruptions.add(ProcessSignal.sigint.watch().listen(interrupt));
  if (!Platform.isWindows) {
    interruptions.add(ProcessSignal.sigterm.watch().listen(interrupt));
  }
  final staged = Directory(
    '${artifactDirectory.path}/runtime/${platform == 'macos' ? 'cantivra.app' : 'Release'}',
  );
  try {
    await prepareNativeHarness(
      platform,
      'tool/native_acceptance.dart',
      skipBuild: args.contains('--no-build'),
      onBuildStarted: (process) {
        active = process;
        if (interrupted) process.kill(ProcessSignal.sigterm);
      },
    );
    active = null;
    if (interrupted) throw StateError('Acceptance interrupted before launch.');
    final executable = await stageNativeHarness(platform, staged);
    if (interrupted) throw StateError('Acceptance interrupted before launch.');
    final process = active = await Process.start(executable, [durationArg]);
    nativeOperatorPid = process.pid;
    await recordStatus('running');
    if (interrupted) process.kill(ProcessSignal.sigterm);
    if (Platform.isMacOS) {
      // Keep only idle sleep away; lid closure and explicit sleep remain the
      // user's choice. The assertion ends with this isolated test process.
      sleepAssertion = await Process.start('/usr/bin/caffeinate', [
        '-i',
        '-w',
        '${process.pid}',
      ]);
    }
    Map<String, Object?>? completion;
    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (!line.startsWith('QA_EVENT ')) {
            stdout.writeln(line);
            return;
          }
          final data = Map<String, Object?>.from(
            jsonDecode(line.substring(9)) as Map,
          );
          log.writeln(jsonEncode(data));
          if (data['type'] == 'started') {
            testDirectory = Directory(data['temporaryDirectory']! as String);
          }
          if (data['type'] == 'complete') completion = data;
          if ((data['type'] == 'complete' || data['type'] == 'failed') &&
              data['exportDirectory'] is String) {
            exportedEvent = data;
          }
          // Keep long source fixtures in the JSON artifact, not the terminal log.
          stdout.writeln(jsonEncode(Map.of(data)..remove('source')));
        })
        .asFuture<void>();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .listen(stderr.write)
        .asFuture<void>();
    final status = await process.exitCode.timeout(
      Duration(seconds: seconds + 240),
    );
    await stdoutDone;
    await stderrDone;
    active = null;
    if (exportedEvent != null) await copyArtifacts(exportedEvent!);
    if (status != 0 || completion == null) {
      throw StateError('Native acceptance failed (exit $status).');
    }
    final temporary = Directory(completion!['temporaryDirectory']! as String);
    await temporary.delete(recursive: true);
    testDirectory = null;
    if (await staged.parent.exists()) {
      await staged.parent.delete(recursive: true);
    }
    await recordStatus('passed');
    stdout.writeln(
      'NATIVE_ACCEPTANCE_OK — ${artifactDirectory.path}/report.json',
    );
  } catch (error) {
    active?.kill(ProcessSignal.sigterm);
    final terminating = active;
    if (terminating != null) {
      try {
        await terminating.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {
        terminating.kill(ProcessSignal.sigkill);
        try {
          await terminating.exitCode.timeout(const Duration(seconds: 3));
        } catch (_) {}
      }
    }
    if (testDirectory != null) {
      try {
        // SIGINT/SIGTERM can end the native process before it emits a failure
        // event. Retain its last atomic checkpoint and allowlisted PNGs too.
        await copyArtifacts({
          'temporaryDirectory': testDirectory!.path,
          'exportDirectory': '${testDirectory!.path}/exports',
        });
      } catch (artifactError) {
        log.writeln(
          jsonEncode({
            'type': 'artifact_copy_failed',
            'error': '$artifactError',
          }),
        );
      }
    }
    var rendererCleanupConfirmed = testDirectory == null;
    if (testDirectory != null &&
        testDirectory!.path.contains('cantivra-acceptance-')) {
      try {
        // Only this run's private capability can authorize cleanup. Never use
        // the application's actual workspace or guess an unrelated PID.
        final session =
            await RendererSession.read(
              '${testDirectory!.path}/renderer-cleanup-session.json',
            ) ??
            await RendererSession.read(
              '${testDirectory!.path}/renderer-session.json',
            );
        if (session != null) {
          await shutdownAcceptanceRenderer(session);
          rendererCleanupConfirmed = true;
        } else {
          log.writeln(jsonEncode({'type': 'cleanup_unconfirmed'}));
        }
      } catch (cleanupError) {
        log.writeln(
          jsonEncode({'type': 'cleanup_unconfirmed', 'error': '$cleanupError'}),
        );
      }
    }
    if (rendererCleanupConfirmed && testDirectory != null) {
      try {
        await testDirectory!.delete(recursive: true);
      } catch (_) {}
    }
    if (rendererCleanupConfirmed && await staged.parent.exists()) {
      try {
        await staged.parent.delete(recursive: true);
      } catch (_) {}
    }
    log.writeln(jsonEncode({'type': 'runner_failure', 'error': '$error'}));
    await recordStatus('failed', error: '$error');
    stderr.writeln('Native acceptance failed: $error');
    exitCode = 1;
  } finally {
    sleepAssertion?.kill();
    for (final subscription in interruptions) {
      await subscription.cancel();
    }
    await log.close();
  }
}
