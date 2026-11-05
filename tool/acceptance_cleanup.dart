import 'dart:async';
import 'dart:io';

import 'package:cantivra/platform/local_rpc.dart';
import 'package:cantivra/presentation/renderer_session.dart';

/// Read-only process checks for test cleanup, never authority to kill a PID.
/// Unknown/access-denied results throw and leave the private test files intact.
Future<bool> acceptanceProcessRunning(int processId) async {
  if (processId <= 0) throw ArgumentError.value(processId, 'processId');
  if (Platform.isMacOS) {
    final result = await Process.run('/bin/ps', [
      '-p',
      '$processId',
      '-o',
      'stat=',
    ]);
    final status = result.stdout.toString().trim();
    if (result.exitCode == 1 &&
        status.isEmpty &&
        result.stderr.toString().trim().isEmpty) {
      return false;
    }
    if (result.exitCode != 0 || status.isEmpty) {
      throw StateError('The test process status could not be verified.');
    }
    return !status.startsWith('Z');
  }
  if (Platform.isWindows) {
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'''
$ErrorActionPreference = 'Stop'
try {
  $CantivraProcess = Get-Process -Id ([int]$env:CANTIVRA_CLEANUP_PID) -ErrorAction Stop
  if ($CantivraProcess.HasExited) { exit 0 }
  exit 10
} catch {
  if ($_.FullyQualifiedErrorId -like 'NoProcessFoundForGivenId*') { exit 0 }
  exit 2
}
''',
      ],
      environment: {'CANTIVRA_CLEANUP_PID': '$processId'},
    );
    if (result.exitCode == 0) return false;
    if (result.exitCode == 10) return true;
    throw StateError('The Windows test process status could not be verified.');
  }
  throw UnsupportedError('Native acceptance requires macOS or Windows.');
}

/// Only call with a capability from this test's private workspace. Recently
/// terminated peers may own the renderer until TCP EOF arrives. Shutdown ACKs
/// may also be lost as native windows exit. Actual process exit is authoritative.
Future<void> shutdownAcceptanceRenderer(
  RendererSession session, {
  Future<bool> Function(int)? isProcessRunning,
}) async {
  final running = isProcessRunning ?? acceptanceProcessRunning;
  for (var attempt = 0; attempt < 20; attempt++) {
    if (!await running(session.processId)) return;
    LocalRpcPeer? peer;
    var retry = false;
    var shutdownSent = false;
    try {
      peer = LocalRpcPeer(
        await Socket.connect(
          InternetAddress.loopbackIPv4,
          session.port,
          timeout: const Duration(seconds: 2),
        ),
      );
      final info = await peer.call('hello', {
        'protocol': 2,
        'renderSchema': renderSchemaVersion,
        'session': session.sessionId,
        'token': session.token,
      });
      if (info is! Map ||
          info['session'] != session.sessionId ||
          info['pid'] != session.processId) {
        throw StateError('The cleanup renderer identity did not match.');
      }
      shutdownSent = true;
      await peer.call('shutdown', {'session': session.sessionId});
    } on LocalRpcException catch (error) {
      if (!shutdownSent) {
        if (error.code != 'operator_connected' || attempt == 19) rethrow;
        retry = true;
      }
      // When shutdown was sent, verify real exit even if its ACK was lost.
    } on SocketException {
      if (!await running(session.processId)) return;
      rethrow;
    } finally {
      await peer?.close();
    }
    if (shutdownSent) {
      for (var check = 0; check < 30; check++) {
        if (!await running(session.processId)) return;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw StateError('The authenticated test renderer has not exited.');
    }
    if (retry) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
