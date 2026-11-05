// Manual hardware acceptance using the production operator and renderer.
// This entrypoint never opens the normal church library or advances slides.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cantivra/application/operator_bootstrap.dart';
import 'package:cantivra/data/app_repository.dart';
import 'package:cantivra/domain/models.dart';
import 'package:cantivra/platform/app_lifecycle.dart';
import 'package:cantivra/presentation/desktop_output.dart';
import 'package:cantivra/presentation/renderer_runtime.dart';
import 'package:cantivra/presentation/renderer_session.dart';
import 'package:cantivra/ui/operator_startup_app.dart';
import 'package:flutter/material.dart';

void event(String type, Map<String, Object?> data) {
  stdout.writeln(
    'HDMI_EVENT ${jsonEncode({'type': type, 'atUtc': DateTime.now().toUtc().toIso8601String(), ...data})}',
  );
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final renderer = RendererLaunch.parse(args);
  if (renderer != null) {
    await runRenderer(renderer);
    return;
  }
  final targetArgument = args
      .where((value) => value.startsWith('--hdmi-display='))
      .firstOrNull;
  if (targetArgument == null || targetArgument.substring(15).isEmpty) {
    stderr.writeln('Choose the explicit secondary --hdmi-display=<id>.');
    exit(2);
  }
  final targetId = targetArgument.substring(15);
  final temporary = await Directory.systemTemp.createTemp(
    'cantivra-hdmi-manual-',
  );
  final database = File('${temporary.path}/cantivra.sqlite');
  final repo = await AppRepository.open(database.path);
  final now = DateTime.now().toUtc();
  for (final label in ['A', 'B']) {
    await repo.saveContent(
      ContentItem(
        id: 'hdmi-$label',
        title: 'HDMI TEST $label',
        kind: ContentKind.custom,
        sourceText: label == 'A'
            ? 'HDMI TEST A\nThe first test slide.\nThe operator controls stay on the Mac.'
            : 'HDMI TEST B\nThe second test slide.\nSlide changes happen only when requested.',
        modifiedAt: now,
      ),
    );
  }
  await repo.saveService(
    ServicePlan(
      id: 'manual-hdmi',
      title: 'MANUAL HDMI TEST',
      items: [
        for (final label in ['A', 'B'])
          ServiceEntry(
            id: 'hdmi-entry-$label',
            contentId: 'hdmi-$label',
            label: 'HDMI TEST $label',
          ),
      ],
      modifiedAt: now,
    ),
  );
  await repo.saveSetting('activeService', 'manual-hdmi');
  await repo.saveSetting(
    'presentationTheme',
    jsonEncode(
      const PresentationTheme(
        fontFamily: 'Arial',
        fontSize: 88,
        safeMargin: .08,
      ).toMap(),
    ),
  );
  await repo.close();

  final bootstrap = OperatorBootstrap(
    directoryProvider: () async => temporary,
    outputFactory: (sessionPath) => DesktopOutput(
      sessionPath: sessionPath,
      launchRenderer: Platform.isMacOS
          ? (launch) async {
              // Keep diagnostic output independent of operator-owned pipes.
              // Quoted positional arguments preserve paths; tokens stay in env.
              final child = await Process.start(
                '/bin/sh',
                [
                  '-c',
                  r'exec "$@" >> "$CANTIVRA_HDMI_RENDERER_LOG" 2>&1',
                  'cantivra-hdmi-renderer',
                  Platform.resolvedExecutable,
                  rendererRoleArgument,
                  '--cantivra-session-file=${launch.sessionPath}',
                  '--cantivra-session=${launch.sessionId}',
                ],
                mode: ProcessStartMode.detached,
                environment: {
                  rendererTokenEnvironment: launch.token,
                  'CANTIVRA_HDMI_RENDERER_LOG':
                      '${temporary.path}/renderer-diagnostics.log',
                },
              );
              return child.pid;
            }
          : null,
    ),
  );
  DesktopLifecycle.install(() async {
    final approved = await bootstrap.prepareClose();
    if (approved) {
      final repository = bootstrap.workspace?.repository;
      final integrity = await repository?.integrityCheck();
      event('manual_session_closed', {'databaseIntegrity': integrity});
      await repository?.close();
      await stdout.flush();
    }
    return approved;
  });
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          const ColoredBox(
            color: Color(0xff8b4414),
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: DefaultTextStyle(
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 14,
                    color: Colors.white,
                  ),
                  child: Text(
                    'MANUAL HDMI TEST  ·  Temporary library  ·  You control every slide change',
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: OperatorStartupApp(bootstrap: bootstrap)),
        ],
      ),
    ),
  );
  event('private_workspace_created', {'directory': temporary.path});
  await bootstrap.start();
  final controller = bootstrap.workspace;
  if (controller == null) {
    event('startup_failed', {'error': bootstrap.startupError});
    return;
  }
  String? previousState;
  void recordOutputState() {
    final frame = controller.live.frame;
    final snapshot = {
      'revision': frame.revision,
      'mode': frame.mode.name,
      'frozen': frame.frozen,
      'emergency': frame.emergency,
      'backgroundVisible': frame.backgroundVisible,
      'slideId': frame.slide?.id,
      'connectionState': controller.output.state.name,
      'displayId': controller.output.displayId,
    };
    final encoded = jsonEncode(snapshot);
    if (encoded != previousState) {
      previousState = encoded;
      event('operator_output_state', snapshot);
    }
  }

  controller.live.addListener(recordOutputState);
  controller.output.addListener(recordOutputState);
  recordOutputState();
  final target = controller.displays
      .where((display) => display.id == targetId)
      .firstOrNull;
  controller.prepareOutputProfile(
    controller.outputProfileDraft.copyWith(
      name: 'Manual HDMI · ${target?.name ?? 'Selected secondary'}',
      displayId: targetId,
    ),
  );
  if (target == null || target.isPrimary || !target.isOutputEligible) {
    controller.reportError(
      'The requested secondary display is unavailable. Select the intended TV in Settings; no fallback was opened.',
    );
    event('target_unavailable', {'requestedId': targetId});
    return;
  }
  try {
    // The user explicitly requested a hardware test on this exact display.
    // Open black only; Go Live and all later changes remain manual actions.
    await controller.openOutput();
    event('black_output_ready', {
      'displayId': target.id,
      'displayName': target.name,
      'logicalWidth': target.width,
      'logicalHeight': target.height,
      'backingScale': target.scale,
      'rendererPid': controller.output.processId,
      'window': (await controller.output.inspect())['window'],
      'physicalObservation': 'pending_user_confirmation',
    });
  } catch (error) {
    controller.reportError('HDMI test could not open output: $error');
    event('output_open_failed', {'error': '$error'});
  }
}
