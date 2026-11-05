import 'dart:io';

/// Seal generated local-development output explicitly. Flutter incremental
/// assembly can replace App.framework after Xcode sealed the outer bundle.
/// This is ad-hoc signing, not Developer ID distribution or notarization.
Future<String> sealMacosDevelopmentBundle(String application) async {
  Future<ProcessResult> run(List<String> arguments) async {
    final result = await Process.run('/usr/bin/codesign', arguments);
    if (result.exitCode != 0) {
      throw StateError('Development signing failed: ${result.stderr}');
    }
    return result;
  }

  await run([
    '--force',
    '--sign',
    '-',
    '--entitlements',
    'macos/Runner/Release.entitlements',
    application,
  ]);
  await run(['--verify', '--deep', '--strict', application]);
  final details = await run(['--display', '--verbose=4', application]);
  if (!details.stderr.toString().contains('Signature=adhoc')) {
    throw StateError(
      'Development package did not have the expected ad-hoc signature.',
    );
  }
  return 'ad-hoc development signature; nested code verified';
}
