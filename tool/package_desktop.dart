import 'dart:convert';
import 'dart:io';

import 'development_signing.dart';

Future<ProcessResult> checked(String executable, List<String> arguments) async {
  final result = await Process.run(
    executable,
    arguments,
    runInShell: Platform.isWindows && executable == 'flutter',
  );
  if (result.exitCode != 0) {
    throw StateError(
      '$executable failed (${result.exitCode}): ${result.stderr}',
    );
  }
  return result;
}

Future<String> sha256(String path) async {
  final result = Platform.isWindows
      ? await checked('certutil', ['-hashfile', path, 'SHA256'])
      : await checked('/usr/bin/shasum', ['-a', '256', path]);
  final match = RegExp(
    r'\b[a-fA-F0-9]{64}\b',
  ).firstMatch(result.stdout.toString());
  if (match == null) throw StateError('SHA-256 tool returned no digest.');
  return match.group(0)!.toLowerCase();
}

Future<void> main(List<String> args) async {
  final platform = args.firstOrNull ?? (Platform.isMacOS ? 'macos' : 'windows');
  if ((platform != 'macos' || !Platform.isMacOS) &&
      (platform != 'windows' || !Platform.isWindows)) {
    stderr.writeln('Package macos or windows on its native host.');
    exitCode = 2;
    return;
  }
  try {
    final build = await Process.start(
      'flutter',
      ['build', platform, '--release', '--no-pub', '-t', 'lib/main.dart'],
      runInShell: Platform.isWindows,
      mode: ProcessStartMode.inheritStdio,
    );
    if (await build.exitCode != 0) {
      throw StateError('Native release build failed.');
    }
    final pubspec = await File('pubspec.yaml').readAsString();
    final version = RegExp(
      r'^version:\s*([^\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;
    final release = version.split('+').first;
    final directory = Directory('dist');
    await directory.create(recursive: true);
    final label = platform == 'macos' ? 'macOS' : 'Windows';
    final archive = File('dist/Cantivra-$label-$release.zip').absolute.path;
    String signing;
    if (Platform.isMacOS) {
      const application = 'build/macos/Build/Products/Release/cantivra.app';
      signing = await sealMacosDevelopmentBundle(application);
      await checked('/usr/bin/ditto', [
        '-c',
        '-k',
        '--sequesterRsrc',
        '--keepParent',
        application,
        archive,
      ]);
      await checked('/usr/bin/unzip', ['-t', archive]);
    } else {
      final source = Directory(
        'build/windows/x64/runner/Release',
      ).absolute.path;
      final certificate = Platform.environment['CANTIVRA_SIGN_CERT_SHA1'];
      signing = 'unsigned development build';
      if (certificate != null && certificate.isNotEmpty) {
        await checked('signtool', [
          'sign',
          '/sha1',
          certificate,
          '/fd',
          'SHA256',
          '$source/cantivra.exe',
        ]);
        await checked('signtool', ['verify', '/pa', '$source/cantivra.exe']);
        signing =
            'Authenticode verified against the configured local certificate';
      }
      // Environment values are data, not interpolated PowerShell source.
      final powershell = await Process.start(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', '-'],
        environment: {
          'CANTIVRA_PACKAGE_SOURCE': source,
          'CANTIVRA_PACKAGE_DESTINATION': archive,
        },
      );
      final output = powershell.stdout.transform(utf8.decoder).join();
      final errors = powershell.stderr.transform(utf8.decoder).join();
      powershell.stdin.writeln(r'$ErrorActionPreference = "Stop"');
      powershell.stdin.writeln(
        r'Compress-Archive -LiteralPath $env:CANTIVRA_PACKAGE_SOURCE -DestinationPath $env:CANTIVRA_PACKAGE_DESTINATION -Force',
      );
      await powershell.stdin.close();
      final status = await powershell.exitCode;
      await output;
      if (status != 0) throw StateError(await errors);
      await errors;
    }
    final sdk = await checked('flutter', ['--version', '--machine']);
    final git = await Process.run('git', ['rev-parse', 'HEAD']);
    final digest = await sha256(archive);
    final metadata = {
      'application': 'Cantivra',
      'version': version,
      'platform': platform,
      'os': Platform.operatingSystemVersion,
      'builtAtUtc': DateTime.now().toUtc().toIso8601String(),
      'gitRevision': git.exitCode == 0 ? git.stdout.toString().trim() : null,
      'flutter': jsonDecode(sdk.stdout.toString()),
      'lockfileSha256': await sha256('pubspec.lock'),
      'archive': File(archive).uri.pathSegments.last,
      'archiveBytes': await File(archive).length(),
      'sha256': digest,
      'signing': signing,
      'entrypoint': 'lib/main.dart',
    };
    await File('$archive.manifest.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(metadata)}\n',
    );
    await File(
      '$archive.sha256',
    ).writeAsString('$digest  ${File(archive).uri.pathSegments.last}\n');
    stdout.writeln('Packaged $archive\nSigning: $signing\nSHA-256: $digest');
  } catch (error) {
    stderr.writeln('Packaging failed: $error');
    exitCode = 1;
  }
}
