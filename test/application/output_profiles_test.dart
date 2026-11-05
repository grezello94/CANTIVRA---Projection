import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cantivra/application/workspace_controller.dart';
import 'package:cantivra/data/app_repository.dart';
import 'package:cantivra/domain/output_profile.dart';
import 'package:cantivra/presentation/desktop_output.dart';
import 'package:cantivra/presentation/live_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProfileOutput extends DesktopOutput {
  @override
  String? displayId;
  @override
  bool fullscreen = false;
  final frames = <OutputFrame>[];
  final opens = <Map<String, Object?>>[];
  bool failOpen = false;
  OutputFrame? recovery;

  @override
  bool get connected => true;

  @override
  OutputFrame? get recoveredFrame => recovery;

  @override
  Future<void> open({
    String? targetDisplayId,
    bool fullscreen = false,
    double scale = 1,
    double safeInset = 0,
  }) async {
    opens.add({
      'displayId': targetDisplayId,
      'fullscreen': fullscreen,
      'scale': scale,
      'safeInset': safeInset,
    });
    if (failOpen) throw StateError('Renderer rejected display placement');
    displayId = targetDisplayId;
    this.fullscreen = fullscreen;
  }

  @override
  Future<int> publish(OutputFrame frame) async {
    frames.add(OutputFrame.fromMap(frame.toMap()));
    return frame.revision;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cantivra/display');
  const codec = StandardMethodCodec();
  late Directory temporary;
  late AppRepository repository;
  late _ProfileOutput output;
  late WorkspaceController controller;
  late List<Map<String, Object?>> connectedDisplays;

  Future<void> constructController() async {
    output = _ProfileOutput();
    controller = WorkspaceController(
      repository: repository,
      output: output,
      dataDirectory: temporary.path,
    );
    await controller.initialize();
  }

  Future<void> reopenController() async {
    await repository.getSetting('__profile_test_barrier__');
    controller.dispose();
    output.dispose();
    await constructController();
  }

  setUp(() async {
    connectedDisplays = [
      {
        'id': 'laptop',
        'name': 'Laptop',
        'isPrimary': true,
        'x': 0,
        'y': 0,
        'width': 1440,
        'height': 900,
        'scale': 2,
      },
      {
        'id': 'church-hdmi',
        'name': 'Church screens',
        'isPrimary': false,
        'x': -1920,
        'y': 0,
        'width': 1920,
        'height': 1080,
        'scale': 1,
      },
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'listDisplays') return connectedDisplays;
          return null;
        });
    temporary = await Directory.systemTemp.createTemp('cantivra-profile-test-');
    repository = await AppRepository.open('${temporary.path}/library.sqlite');
    await constructController();
  });

  tearDown(() async {
    await controller.flushSave();
    await repository.getSetting('__profile_test_barrier__');
    controller.dispose();
    output.dispose();
    await repository.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await temporary.delete(recursive: true);
  });

  test(
    'versioned profile roundtrip preserves target and whole-canvas calibration',
    () {
      const profile = OutputProfile(
        id: 'church',
        name: 'Church',
        displayId: 'hdmi',
        scale: .9,
        safeInset: .05,
      );
      expect(OutputProfile.fromMap(profile.toMap()), profile);
      expect(profile.effectiveScale, closeTo(.81, .00001));
      expect(profile.isRehearsal, isFalse);
      expect(profile.copyWith(name: 'Chapel').displayId, 'hdmi');
      expect(profile.copyWith(displayId: null).isRehearsal, isTrue);
      const rehearsal = OutputProfile(id: 'rehearsal', name: 'Rehearsal');
      expect(rehearsal.scale, 1);
      expect(rehearsal.safeInset, 0);
      expect(rehearsal.effectiveScale, 1);
      expect(
        () => OutputProfile.fromMap({...profile.toMap(), 'version': 99}),
        throwsFormatException,
      );
      expect(
        () => OutputProfile.fromMap({...profile.toMap(), 'scale': 'large'}),
        throwsFormatException,
      );
    },
  );

  test('profile validation rejects invalid geometry and identifiers', () {
    const valid = OutputProfile(id: 'valid', name: 'Valid');
    for (final profile in [
      valid.copyWith(scale: .749),
      valid.copyWith(scale: 1.001),
      valid.copyWith(scale: double.nan),
      valid.copyWith(safeInset: -.001),
      valid.copyWith(safeInset: .121),
      valid.copyWith(safeInset: double.infinity),
      valid.copyWith(id: ''),
      valid.copyWith(name: '  '),
      valid.copyWith(displayId: ''),
    ]) {
      expect(profile.validate, throwsFormatException);
    }
    valid.copyWith(scale: .75, safeInset: .12).validate();
    expect(
      valid.copyWith(scale: .75, safeInset: .12).effectiveScale,
      closeTo(.57, .00001),
    );
  });

  test(
    'legacy target migrates lazily without opening or replacing disconnected display',
    () async {
      await repository.saveSetting(
        'preferredDisplay',
        'remembered-offline-hdmi',
      );
      await reopenController();
      expect(controller.preferredDisplayId, 'remembered-offline-hdmi');
      expect(
        controller.outputProfileDraft.displayId,
        'remembered-offline-hdmi',
      );
      expect(controller.outputProfileDraft.name, 'Church screens');
      expect(await repository.getSetting('outputProfiles'), isNull);
      expect(output.opens, isEmpty);
      expect(output.frames, isEmpty);
      await controller.saveOutputProfile();
      expect(
        jsonDecode((await repository.getSetting('outputProfiles'))!)['version'],
        1,
      );
      await reopenController();
      expect(controller.preferredDisplayId, 'remembered-offline-hdmi');
      expect(output.opens, isEmpty);
    },
  );

  test(
    'creating, renaming, saving and selecting profiles persist independently of output',
    () async {
      await controller.saveOutputProfile();
      final rehearsalId = controller.selectedOutputProfileId;
      await controller.createOutputProfile('Main church');
      final churchId = controller.selectedOutputProfileId;
      controller.prepareOutputProfile(
        controller.outputProfileDraft.copyWith(
          name: 'Main church HDMI',
          displayId: 'church-hdmi',
          scale: .92,
          safeInset: .04,
        ),
      );
      expect(controller.hasPreparedOutputChanges, isTrue);
      await controller.saveOutputProfile();
      expect(controller.hasPreparedOutputChanges, isFalse);
      await controller.selectOutputProfile(rehearsalId);
      expect(controller.outputProfileDraft.isRehearsal, isTrue);
      await controller.selectOutputProfile(churchId);
      await reopenController();
      expect(controller.outputProfiles, hasLength(2));
      expect(controller.selectedOutputProfileId, churchId);
      expect(controller.outputProfileDraft.name, 'Main church HDMI');
      expect(controller.outputProfileDraft.scale, .92);
      expect(controller.outputProfileDraft.safeInset, .04);
      expect(controller.preferredDisplayId, 'church-hdmi');
      expect(output.opens, isEmpty);
      expect(output.frames, isEmpty);
    },
  );

  test(
    'draft calibration and profile save leave published text and theme untouched',
    () async {
      expect(await controller.publishSelected(), isTrue);
      final liveBefore = controller.live.frame.toMap();
      final previewBefore = controller.preview!.toMap();
      final framesBefore = output.frames.length;
      controller.preferredDisplayId = 'church-hdmi';
      controller.prepareOutputProfile(
        controller.outputProfileDraft.copyWith(scale: .85, safeInset: .1),
      );
      expect(await repository.getSetting('outputProfiles'), isNull);
      expect(controller.live.frame.toMap(), liveBefore);
      expect(controller.preview!.toMap(), previewBefore);
      await controller.saveOutputProfile();
      expect(controller.live.frame.toMap(), liveBefore);
      expect(controller.preview!.toMap(), previewBefore);
      expect(output.frames, hasLength(framesBefore));
      expect(output.opens, isEmpty);
    },
  );

  test(
    'apply sends the prepared geometry and adopts surviving frame without publishing',
    () async {
      final surviving = OutputFrame(
        revision: 42,
        slide: controller.preview,
        mode: OutputMode.normal,
        frozen: true,
      );
      output.recovery = surviving;
      controller.prepareOutputProfile(
        controller.outputProfileDraft.copyWith(
          displayId: 'church-hdmi',
          scale: .91,
          safeInset: .03,
        ),
      );
      await controller.openOutput();
      expect(output.opens.single, {
        'displayId': 'church-hdmi',
        'fullscreen': true,
        'scale': .91,
        'safeInset': .03,
      });
      expect(
        output.frames,
        isEmpty,
        reason: 'Reattaching must not send startup black.',
      );
      expect(controller.live.frame.toMap(), surviving.toMap());
      expect(controller.appliedOutputProfile, controller.outputProfileDraft);
      expect(controller.outputConfigurationPending, isFalse);
      expect(await repository.getSetting('preferredDisplay'), 'church-hdmi');
      expect(
        await repository.getSetting('activeOutputProfile'),
        controller.selectedOutputProfileId,
      );
      expect(await repository.getSetting('outputProfiles'), isNotNull);
    },
  );

  test(
    'windowed rehearsal is explicit and never enables primary fullscreen',
    () async {
      await controller.openOutput();
      expect(output.opens.single, {
        'displayId': null,
        'fullscreen': false,
        'scale': 1.0,
        'safeInset': 0.0,
      });
      expect(output.frames, isEmpty);
      controller.preferredDisplayId = 'laptop';
      await expectLater(controller.openOutput(), throwsStateError);
      expect(output.opens, hasLength(1));
      expect(controller.preferredDisplayId, 'laptop');
      expect(await repository.getSetting('preferredDisplay'), '');
    },
  );

  test(
    'missing display refuses apply and preserves prepared and saved targets',
    () async {
      await repository.saveSetting('preferredDisplay', 'offline-hdmi');
      await reopenController();
      await expectLater(controller.openOutput(), throwsStateError);
      expect(controller.preferredDisplayId, 'offline-hdmi');
      expect(await repository.getSetting('preferredDisplay'), 'offline-hdmi');
      expect(await repository.getSetting('outputProfiles'), isNull);
      expect(output.opens, isEmpty);
      expect(output.frames, isEmpty);
    },
  );

  test(
    'rejected renderer configuration does not persist the prepared setup',
    () async {
      output.failOpen = true;
      controller.preferredDisplayId = 'church-hdmi';
      await expectLater(controller.openOutput(), throwsStateError);
      expect(controller.preferredDisplayId, 'church-hdmi');
      expect(await repository.getSetting('outputProfiles'), isNull);
      expect(await repository.getSetting('preferredDisplay'), isNull);
      expect(controller.appliedOutputProfile, isNull);
      expect(output.frames, isEmpty);
    },
  );

  test(
    'unidentified native target refuses output without mutating live',
    () async {
      connectedDisplays.last['isOutputEligible'] = false;
      connectedDisplays.last['unavailableReason'] =
          'The target cannot be safely identified.';
      controller.preferredDisplayId = 'church-hdmi';
      final frame = controller.live.frame.toMap();
      await expectLater(
        controller.openOutput(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('safely identified'),
          ),
        ),
      );
      expect(controller.preferredDisplayId, 'church-hdmi');
      expect(output.opens, isEmpty);
      expect(output.frames, isEmpty);
      expect(controller.live.frame.toMap(), frame);
      expect(await repository.getSetting('preferredDisplay'), isNull);
    },
  );

  test(
    'native topology event refreshes monitors without changing the profile or live',
    () async {
      controller.preferredDisplayId = 'church-hdmi';
      expect(await controller.publishSelected(), isTrue);
      final liveBefore = controller.live.frame.toMap();
      final updated = Completer<void>();
      void listener() {
        if (controller.displays.length == 1 && !updated.isCompleted) {
          updated.complete();
        }
      }

      controller.addListener(listener);
      try {
        connectedDisplays = [connectedDisplays.first];
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              'cantivra/display',
              codec.encodeMethodCall(
                MethodCall('displayChanged', {
                  'displays': connectedDisplays,
                  'reason': 'topologyChanged',
                }),
              ),
              null,
            );
        await updated.future.timeout(const Duration(seconds: 4));
        expect(controller.displays.single.id, 'laptop');
        expect(controller.preferredDisplayId, 'church-hdmi');
        expect(controller.live.frame.toMap(), liveBefore);
        expect(output.opens, isEmpty);
      } finally {
        controller.removeListener(listener);
      }
    },
  );

  test(
    'switching prepared profiles retains each profile pending adjustments',
    () async {
      await controller.saveOutputProfile();
      final first = controller.selectedOutputProfileId;
      controller.prepareOutputProfile(
        controller.outputProfileDraft.copyWith(scale: .86),
      );
      await controller.createOutputProfile('Chapel');
      final second = controller.selectedOutputProfileId;
      controller.prepareOutputProfile(
        controller.outputProfileDraft.copyWith(scale: .93),
      );
      await controller.selectOutputProfile(first);
      expect(controller.outputProfileDraft.scale, .86);
      await controller.selectOutputProfile(second);
      expect(controller.outputProfileDraft.scale, .93);
      expect(controller.hasPreparedOutputChanges, isTrue);
      expect(output.opens, isEmpty);
      expect(output.frames, isEmpty);
    },
  );

  test(
    'invalid optional profile data reports an error while the content library loads',
    () async {
      await repository.saveSetting(
        'outputProfiles',
        '{"version":99,"profiles":[]}',
      );
      await reopenController();
      expect(
        controller.error,
        contains('Saved output profiles could not be read'),
      );
      expect(controller.loading, isFalse);
      expect(controller.selected, isNotNull);
      expect(controller.preview, isNotNull);
      expect(controller.results, hasLength(5));
      expect(output.frames, isEmpty);
      expect(
        await repository.getSetting('outputProfiles'),
        '{"version":99,"profiles":[]}',
      );
    },
  );
}
