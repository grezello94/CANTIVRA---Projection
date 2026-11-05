import 'dart:convert';
import 'dart:io';

import 'harness_build.dart';

Future<void> main(List<String> args) async {
  final platform = args.firstOrNull ?? Platform.operatingSystem;
  final target = args
      .where((value) => value.startsWith('--hdmi-display='))
      .firstOrNull;
  if (!{'macos', 'windows'}.contains(platform) || target == null) {
    stderr.writeln(
      'Usage: dart run tool/run_manual_hdmi.dart macos|windows --hdmi-display=<secondary-id>',
    );
    exitCode = 2;
    return;
  }
  final directory = Directory(
    'build/qa/manual-hdmi/${DateTime.now().toUtc().microsecondsSinceEpoch}',
  );
  await directory.create(recursive: true);
  final status = File('${directory.path}/status.json');
  Future<void> record(Map<String, Object?> data) => status.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(data)}\n',
    flush: true,
  );
  Process? process;
  try {
    await record({'status': 'building', 'targetArgument': target});
    await prepareNativeHarness(
      platform,
      'tool/manual_hdmi.dart',
      skipBuild: args.contains('--no-build'),
    );
    final executable = await stageNativeHarness(
      platform,
      Directory(
        '${directory.path}/runtime/${platform == 'macos' ? 'cantivra.app' : 'Release'}',
      ),
    );
    process = await Process.start(
      executable,
      [target],
      environment: {'CANTIVRA_HDMI_DIAGNOSTICS': '1'},
    );
    await record({
      'status': 'manual_session_running',
      'operatorPid': process.pid,
      'targetArgument': target,
      'physicalAcceptancePassed': false,
    });
    final log = File('${directory.path}/session.log').openWrite();
    final output = process.stdout.transform(utf8.decoder).listen((value) {
      stdout.write(value);
      log.write(value);
    }).asFuture<void>();
    final errors = process.stderr.transform(utf8.decoder).listen((value) {
      stderr.write(value);
      log.write(value);
    }).asFuture<void>();
    final result = await process.exitCode;
    await output;
    await errors;
    await log.close();
    await record({
      'status': result == 0 ? 'manual_session_closed' : 'manual_session_failed',
      'exitCode': result,
      'physicalAcceptancePassed': false,
      'note':
          'Native state and successful exit do not certify what appeared on the TV. Record the user-observed steps separately.',
    });
    exitCode = result;
  } catch (error) {
    await record({'status': 'failed', 'error': '$error'});
    stderr.writeln(error);
    exitCode = 1;
  }
  stdout.writeln('Manual HDMI evidence: ${directory.path}');
}
