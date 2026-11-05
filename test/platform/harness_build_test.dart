import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/harness_build.dart';

void main() {
  test(
    'no-build refuses an unknown or replaced application before launch',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cantivra-harness-proof-',
      );
      try {
        final marker = '${directory.path}/marker.json';
        final aot = '${directory.path}/app.so';
        await File(aot).writeAsString('Test harness AOT fixture');
        await expectLater(
          requireHarnessBuild(marker, aot, 'tool/native_smoke.dart'),
          throwsStateError,
        );
        await recordHarnessBuild(marker, aot, 'tool/native_smoke.dart');
        await requireHarnessBuild(marker, aot, 'tool/native_smoke.dart');
        await expectLater(
          requireHarnessBuild(marker, aot, 'tool/native_acceptance.dart'),
          throwsStateError,
        );
        await File(aot).writeAsString('Normal app AOT fixture');
        await expectLater(
          requireHarnessBuild(marker, aot, 'tool/native_smoke.dart'),
          throwsStateError,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'staged harness retains runtime assets after build output changes',
    () async {
      if (!Platform.isMacOS && !Platform.isWindows) return;
      final directory = await Directory.systemTemp.createTemp(
        'cantivra-stage-',
      );
      try {
        final source = await Directory('${directory.path}/source').create();
        final nested = await Directory('${source.path}/data').create();
        await File('${nested.path}/app.so').writeAsString('Captured AOT');
        final destination = Directory('${directory.path}/captured');
        await stageNativeHarness(
          Platform.operatingSystem,
          destination,
          sourcePath: source.path,
        );
        await File('${nested.path}/app.so').writeAsString('Normal application');
        expect(
          await File('${destination.path}/data/app.so').readAsString(),
          'Captured AOT',
        );
        await expectLater(
          stageNativeHarness(
            Platform.operatingSystem,
            destination,
            sourcePath: source.path,
          ),
          throwsStateError,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
