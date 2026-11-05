import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'harness_build.dart';

import 'package:cantivra/platform/local_rpc.dart';
import 'package:cantivra/presentation/renderer_session.dart';

Future<void> main(List<String> arguments) async {
  final device =
      arguments.firstOrNull ?? (Platform.isMacOS ? 'macos' : 'windows');
  if (device != 'macos' && device != 'windows') {
    stderr.writeln('Choose macos or windows.');
    exitCode = 2;
    return;
  }
  try {
    await prepareNativeHarness(
      device,
      'tool/native_smoke.dart',
      skipBuild: arguments.contains('--no-build'),
    );
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
    return;
  }
  final executable = File(
    device == 'macos'
        ? 'build/macos/Build/Products/Release/cantivra.app/Contents/MacOS/cantivra'
        : 'build/windows/x64/runner/Release/cantivra.exe',
  ).absolute.path;
  final log = StringBuffer();
  Process? active;
  Directory? crashDirectory;
  Future<void> runStage(
    String marker,
    List<String> args, {
    void Function(Process)? onStarted,
  }) async {
    final process = await Process.start(executable, args);
    active = process;
    onStarted?.call(process);
    var passed = false;
    var failed = false;
    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stdout.writeln(line);
          log.writeln(line);
          if (line.contains(marker)) passed = true;
          if (line.contains('NATIVE_SMOKE_FAILED')) failed = true;
        })
        .asFuture<void>();
    final stderrDone = process.stderr.transform(utf8.decoder).listen((text) {
      stderr.write(text);
      log.write(text);
    }).asFuture<void>();
    final status = await process.exitCode.timeout(const Duration(seconds: 50));
    await stdoutDone;
    await stderrDone;
    active = null;
    if (status != 0 || !passed || failed) {
      throw StateError('Native stage failed: exit=$status marker=$passed.');
    }
  }

  try {
    await runStage('NATIVE_SMOKE_OK', const []);
    await runStage('STORAGE_RECOVERY_SMOKE_OK', const [
      '--smoke-role=storage-startup',
    ]);
    final operator = await Process.start(executable, ['--smoke-role=hold']);
    active = operator;
    final ready = Completer<void>();
    final stdoutDone = operator.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stdout.writeln(line);
          log.writeln(line);
          if (line.startsWith('OPERATOR_HOLD_READY:') && !ready.isCompleted) {
            final path = utf8.decode(
              base64Url.decode(line.substring('OPERATOR_HOLD_READY:'.length)),
            );
            crashDirectory = Directory(path);
            ready.complete();
          }
          if (line.contains('NATIVE_SMOKE_FAILED') && !ready.isCompleted) {
            ready.completeError(StateError(line));
          }
        })
        .asFuture<void>();
    final stderrDone = operator.stderr.transform(utf8.decoder).listen((text) {
      stderr.write(text);
      log.write(text);
    }).asFuture<void>();
    await ready.future.timeout(const Duration(seconds: 25));
    final path = crashDirectory!.path;
    final expected = jsonDecode(
      await File('$path/expected-frame.json').readAsString(),
    );
    final session = (await RendererSession.read(
      '$path/renderer-session.json',
    ))!;
    operator.kill(ProcessSignal.sigkill);
    await operator.exitCode;
    await stdoutDone;
    await stderrDone;
    active = null;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      session.port,
      timeout: const Duration(seconds: 3),
    );
    final peer = LocalRpcPeer(socket);
    final info = Map<String, Object?>.from(
      (await peer.call('hello', {
            'protocol': 2,
            'renderSchema': renderSchemaVersion,
            'session': session.sessionId,
            'token': session.token,
          }))!
          as Map,
    );
    if (jsonEncode(info['frame']) != jsonEncode(expected) ||
        (info['window'] as Map)['visible'] != true) {
      throw StateError('Operator crash changed or hid the surviving renderer.');
    }
    stdout.writeln(
      'PASS: SIGKILL operator leaves separate renderer visible with identical captured frame',
    );
    log.writeln(
      'PASS: SIGKILL operator leaves separate renderer visible with identical captured frame',
    );
    await peer.call('hide', {'session': session.sessionId});
    // AppKit may defer its last-window check until after the hide completes.
    await Future<void>.delayed(const Duration(seconds: 1));
    final hidden = Map<String, Object?>.from(
      (await peer.call('inspect', {'session': session.sessionId}))! as Map,
    );
    if (hidden['pid'] != session.processId ||
        hidden['session'] != session.sessionId ||
        jsonEncode(hidden['frame']) != jsonEncode(expected) ||
        (hidden['window'] as Map)['visible'] != false) {
      throw StateError('Hiding changed or stopped the surviving renderer.');
    }
    stdout.writeln(
      'PASS: hidden renderer survives with identical process, session and captured frame',
    );
    log.writeln(
      'PASS: hidden renderer survives with identical process, session and captured frame',
    );
    await peer.close();
    await runStage('RECOVERY_SMOKE_OK', [
      '--smoke-role=recover',
      '--smoke-workspace=$path',
    ]);
    await crashDirectory!.delete(recursive: true);
    crashDirectory = null;
    stdout.writeln('PHASE2_NATIVE_SMOKE_OK');
    log.writeln('PHASE2_NATIVE_SMOKE_OK');
  } catch (error, stack) {
    stderr.writeln('Native verification failed: $error\n$stack');
    log.writeln('FAILED: $error\n$stack');
    active?.kill(ProcessSignal.sigkill);
    // Explicit cleanup of this isolated test renderer only, never a real library.
    if (crashDirectory != null) {
      try {
        final session = await RendererSession.read(
          '${crashDirectory!.path}/renderer-session.json',
        );
        if (session != null) {
          final peer = LocalRpcPeer(
            await Socket.connect(
              InternetAddress.loopbackIPv4,
              session.port,
              timeout: const Duration(seconds: 1),
            ),
          );
          await peer.call('hello', {
            'protocol': 2,
            'renderSchema': renderSchemaVersion,
            'session': session.sessionId,
            'token': session.token,
          });
          await peer.call('shutdown', {'session': session.sessionId});
          await peer.close();
        }
      } catch (_) {}
    }
    exitCode = 1;
  } finally {
    await Directory('build/qa').create(recursive: true);
    await File(
      'build/qa/native-smoke-phase2.log',
    ).writeAsString(log.toString());
  }
}
