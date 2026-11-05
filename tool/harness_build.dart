import 'dart:convert';
import 'dart:io';

import 'development_signing.dart';
import 'package_desktop.dart' show sha256;

/// Keep a long-running test independent of subsequent normal-app builds.
/// The native renderer launches this copied executable, not the build output.
Future<String> stageNativeHarness(
  String platform,
  Directory destination, {
  String? sourcePath,
}) async {
  if (platform != Platform.operatingSystem) {
    throw StateError('Stage $platform acceptance on a $platform host.');
  }
  if (await destination.exists()) {
    throw StateError('Refusing to replace an existing harness directory.');
  }
  final source = Directory(
    sourcePath ??
        (platform == 'macos'
            ? 'build/macos/Build/Products/Release/cantivra.app'
            : 'build/windows/x64/runner/Release'),
  ).absolute;
  if (!await source.exists()) throw StateError('The native bundle is missing.');
  await destination.parent.create(recursive: true);
  if (platform == 'macos') {
    // Preserve framework symlinks, executable modes and the signed bundle seal.
    final copy = await Process.run('/usr/bin/ditto', [
      source.path,
      destination.absolute.path,
    ]);
    if (copy.exitCode != 0) {
      throw StateError('Staging the native bundle failed: ${copy.stderr}');
    }
    final signature = await Process.run('/usr/bin/codesign', [
      '--verify',
      '--deep',
      '--strict',
      destination.absolute.path,
    ]);
    // Small test fixtures can exercise copying without pretending to be apps.
    if (sourcePath == null && signature.exitCode != 0) {
      throw StateError('The staged native signature is invalid.');
    }
  } else {
    Future<void> copyDirectory(Directory from, Directory to) async {
      await to.create();
      await for (final entity in from.list(followLinks: false)) {
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        final target = '${to.path}/$name';
        if (entity is Directory) {
          await copyDirectory(entity, Directory(target));
        } else if (entity is File) {
          await entity.copy(target);
        } else {
          throw StateError('Unexpected link in the Windows release directory.');
        }
      }
    }

    await copyDirectory(source, destination);
  }
  return File(
    platform == 'macos'
        ? '${destination.path}/Contents/MacOS/cantivra'
        : '${destination.path}/cantivra.exe',
  ).absolute.path;
}

Future<void> recordHarnessBuild(
  String marker,
  String aotPath,
  String entrypoint,
) async {
  await File(marker).parent.create(recursive: true);
  await File(marker).writeAsString(
    jsonEncode({'entrypoint': entrypoint, 'aotSha256': await sha256(aotPath)}),
    flush: true,
  );
}

Future<void> requireHarnessBuild(
  String marker,
  String aotPath,
  String entrypoint,
) async {
  if (!await File(marker).exists() || !await File(aotPath).exists()) {
    throw StateError(
      'Build this test harness first. --no-build cannot launch an unverified app.',
    );
  }
  final record = jsonDecode(await File(marker).readAsString()) as Map;
  if (record['entrypoint'] != entrypoint ||
      record['aotSha256'] != await sha256(aotPath)) {
    throw StateError(
      'The built app is different from this test harness. Rebuild without --no-build.',
    );
  }
}

Future<void> prepareNativeHarness(
  String platform,
  String entrypoint, {
  required bool skipBuild,
  void Function(Process)? onBuildStarted,
}) async {
  if (platform != Platform.operatingSystem) {
    throw StateError('Build and run $platform acceptance on a $platform host.');
  }
  final marker = 'build/qa/${entrypoint.split('/').last}.build.json';
  final aotPath = platform == 'macos'
      ? 'build/macos/Build/Products/Release/cantivra.app/Contents/Frameworks/App.framework/Versions/A/App'
      : 'build/windows/x64/runner/Release/data/app.so';
  if (skipBuild) {
    await requireHarnessBuild(marker, aotPath, entrypoint);
  } else {
    final build = await Process.start(
      'flutter',
      ['build', platform, '--release', '--no-pub', '-t', entrypoint],
      runInShell: Platform.isWindows,
      mode: ProcessStartMode.inheritStdio,
    );
    onBuildStarted?.call(build);
    if (await build.exitCode != 0) {
      throw StateError('Native test harness build failed.');
    }
  }
  if (Platform.isMacOS) {
    await sealMacosDevelopmentBundle(
      'build/macos/Build/Products/Release/cantivra.app',
    );
  }
  if (!skipBuild) {
    await recordHarnessBuild(marker, aotPath, entrypoint);
  }
}
