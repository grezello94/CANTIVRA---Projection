import 'dart:async';
import 'dart:io';

import 'package:cantivra/application/operator_bootstrap.dart';
import 'package:cantivra/domain/models.dart';
import 'package:cantivra/presentation/desktop_output.dart';
import 'package:cantivra/presentation/live_controller.dart';
import 'package:cantivra/presentation/slides.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

const _survivingFrame = OutputFrame(
  revision: 53,
  mode: OutputMode.normal,
  frozen: true,
  slide: PresentationSlide(
    id: 'live-53',
    sourceId: 'already-live',
    title: 'Surviving presentation',
    label: 'Live',
    text: 'The independent renderer holds this frame.',
    theme: PresentationTheme(),
  ),
);

/// Uses the actual storage worker and controller while replacing only OS output.
class _ExistingOutput extends DesktopOutput {
  bool attached = false;
  bool available = true;
  int inspections = 0;
  int opens = 0;
  int closes = 0;
  bool refuseClose = false;
  bool rejectPublish = false;
  Completer<void>? publishGate;
  Completer<void>? closeGate;
  Completer<void>? closeStarted;
  OutputFrame held = _survivingFrame;
  final frames = <OutputFrame>[];

  @override
  bool get connected => attached;

  @override
  bool get canControl => attached;

  @override
  Future<bool> recoverExisting() async {
    inspections++;
    if (attached || !available) return false;
    attached = true;
    recoveredFrame = held;
    return true;
  }

  @override
  Future<void> open({
    String? targetDisplayId,
    bool fullscreen = false,
    double scale = 1,
    double safeInset = 0,
  }) async {
    opens++;
    throw StateError('Startup must never create or configure an output.');
  }

  @override
  Future<int> publish(OutputFrame frame) async {
    if (!attached || rejectPublish) throw StateError('Output unavailable.');
    frames.add(frame);
    if (!frame.emergency) await publishGate?.future;
    if (frame.revision > held.revision) {
      held = frame;
      recoveredFrame = frame;
    }
    return frame.revision;
  }

  @override
  Future<void> close() async {
    closes++;
    if (closeStarted?.isCompleted == false) closeStarted!.complete();
    await closeGate?.future;
    if (refuseClose) throw StateError('Renderer still running.');
    attached = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const displayChannel = MethodChannel('cantivra/display');
  late Directory directory;
  late _ExistingOutput output;
  OperatorBootstrap? bootstrap;
  late List<String> requestedSessions;
  Future<void> Function()? configureOperator;

  OperatorBootstrap createBootstrap({
    Future<Directory> Function()? directoryProvider,
  }) => bootstrap = OperatorBootstrap(
    directoryProvider: directoryProvider ?? () async => directory,
    outputFactory: (path) {
      requestedSessions.add(path);
      return output;
    },
  );

  Future<List<int>> corruptDatabase() async {
    final bytes = List.generate(256, (index) => (index * 37 + 11) % 256);
    await File('${directory.path}/cantivra.sqlite').writeAsBytes(bytes);
    return bytes;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cantivra-startup-');
    output = _ExistingOutput();
    requestedSessions = [];
    configureOperator = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(displayChannel, (call) async {
          if (call.method == 'configureOperator') {
            await configureOperator?.call();
          }
          if (call.method == 'listDisplays') return <Object?>[];
          return null;
        });
  });

  tearDown(() async {
    await bootstrap?.workspace?.repository.close();
    bootstrap?.dispose();
    bootstrap = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(displayChannel, null);
    await directory.delete(recursive: true);
  });

  test(
    'healthy startup adopts an already attached actual frame without publishing',
    () async {
      final state = createBootstrap();
      await state.start();
      expect(state.loading, isFalse);
      expect(state.startupError, isNull);
      expect(state.workspace, isNotNull);
      expect(state.recoveryLive, isNull);
      expect(state.workspace!.live.frame.toMap(), _survivingFrame.toMap());
      expect(state.workspace!.live.frame.frozen, isTrue);
      expect(output.inspections, greaterThan(1));
      expect(output.opens, 0);
      expect(output.frames, isEmpty);
      expect(requestedSessions, [
        '${directory.path}${Platform.pathSeparator}renderer-session.json',
      ]);
      expect(await state.workspace!.repository.integrityCheck(), 'ok');
    },
  );

  test(
    'a corrupt library retains exact bytes and existing output emergency control',
    () async {
      final original = await corruptDatabase();
      final state = createBootstrap();
      await state.start();
      expect(state.loading, isFalse);
      expect(state.workspace, isNull);
      expect(state.startupError, contains('could not be opened'));
      expect(state.recoveryLive!.frame.toMap(), _survivingFrame.toMap());
      expect(output.frames, isEmpty);
      expect(output.opens, 0);
      expect(
        await File('${directory.path}/cantivra.sqlite').readAsBytes(),
        original,
      );
      expect(
        await state.performOutputAction(
          state.recoveryLive!.emergencyStop,
          emergency: true,
        ),
        isTrue,
      );
      expect(output.held.mode, OutputMode.black);
      expect(output.held.emergency, isTrue);
      expect(output.held.revision, 54);
      expect(output.closes, 0);
    },
  );

  test(
    'a newer database is rejected without downgrade or loss of output control',
    () async {
      final database = sqlite3.open('${directory.path}/cantivra.sqlite');
      database.execute('PRAGMA user_version = 999');
      database.execute('CREATE TABLE retained(value TEXT)');
      database.execute("INSERT INTO retained VALUES ('future data')");
      database.close();
      final state = createBootstrap();
      await state.start();
      expect(state.workspace, isNull);
      expect(state.startupError, contains('newer'));
      expect(state.recoveryLive!.frame.toMap(), _survivingFrame.toMap());
      final check = sqlite3.open('${directory.path}/cantivra.sqlite');
      expect(check.select('PRAGMA user_version').single.values.single, 999);
      expect(
        check.select('SELECT value FROM retained').single['value'],
        'future data',
      );
      check.close();
      expect(output.frames, isEmpty);
      expect(output.opens, 0);
    },
  );

  test(
    'retry reuses the attached renderer after externally restoring valid storage',
    () async {
      await corruptDatabase();
      final state = createBootstrap();
      await state.start();
      expect(
        await state.performOutputAction(
          state.recoveryLive!.emergencyStop,
          emergency: true,
        ),
        isTrue,
      );
      final held = output.held.toMap();
      // An administrator restores storage outside the app. The application itself
      // never replaces a corrupt file or creates a fresh library over it.
      await File('${directory.path}/cantivra.sqlite').delete();
      await state.retry();
      expect(state.startupError, isNull);
      expect(state.workspace, isNotNull);
      expect(state.workspace!.live.frame.toMap(), held);
      expect(state.recoveryLive, isNull);
      expect(state.output, same(output));
      expect(requestedSessions, hasLength(1));
      expect(output.frames, hasLength(1));
      expect(output.opens, 0);
      expect(output.closes, 0);
    },
  );

  test(
    'startup and retry are single flight and close cannot abandon loading storage',
    () async {
      final gate = Completer<void>();
      var nativeCalls = 0;
      configureOperator = () async {
        nativeCalls++;
        await gate.future;
      };
      final state = createBootstrap();
      final first = state.start();
      final duplicate = state.retry();
      expect(identical(first, duplicate), isTrue);
      expect(await state.prepareClose(), isFalse);
      expect(state.actionError, contains('Wait'));
      expect(output.closes, 0);
      gate.complete();
      await first;
      expect(nativeCalls, 1);
      expect(requestedSessions, hasLength(1));
      expect(state.workspace, isNotNull);
    },
  );

  test(
    'missing storage location never guesses a renderer or resets user files',
    () async {
      final state = createBootstrap(
        directoryProvider: () async {
          throw const FileSystemException('Workspace location unavailable');
        },
      );
      await state.start();
      expect(state.loading, isFalse);
      expect(state.workspace, isNull);
      expect(state.output, isNull);
      expect(state.recoveryLive, isNull);
      expect(state.startupError, contains('location unavailable'));
      expect(requestedSessions, isEmpty);
      expect(output.opens, 0);
      expect(output.frames, isEmpty);
      expect(await state.prepareClose(), isTrue);
    },
  );

  test(
    'operator window failure still permits independent existing-output inspection',
    () async {
      configureOperator = () async {
        throw PlatformException(code: 'OPERATOR_WINDOW_UNAVAILABLE');
      };
      final state = createBootstrap();
      await state.start();
      expect(state.workspace, isNull);
      expect(state.startupError, contains('OPERATOR_WINDOW_UNAVAILABLE'));
      expect(state.recoveryLive!.frame.toMap(), _survivingFrame.toMap());
      expect(
        await state.performOutputAction(
          state.recoveryLive!.emergencyStop,
          emergency: true,
        ),
        isTrue,
      );
      expect(output.opens, 0);
    },
  );

  test(
    'failed emergency reports uncertainty and never claims a changed frame',
    () async {
      await corruptDatabase();
      final state = createBootstrap();
      await state.start();
      output.rejectPublish = true;
      expect(
        await state.performOutputAction(
          state.recoveryLive!.emergencyStop,
          emergency: true,
        ),
        isFalse,
      );
      expect(state.actionError, contains('not confirmed'));
      expect(state.recoveryLive!.frame.toMap(), _survivingFrame.toMap());
      expect(output.held.toMap(), _survivingFrame.toMap());
      expect(output.opens, 0);
    },
  );

  test(
    'retry reconnect and close wait for pending output, while panic supersedes it',
    () async {
      await corruptDatabase();
      final state = createBootstrap();
      await state.start();
      output.publishGate = Completer<void>();
      final pending = state.performOutputAction(state.recoveryLive!.black);
      expect(state.recoveryLive!.busy, isTrue);
      final inspections = output.inspections;
      await state.retry();
      await state.reconnectExisting();
      expect(output.inspections, inspections);
      expect(await state.prepareClose(), isFalse);
      expect(output.closes, 0);
      expect(
        await state.performOutputAction(
          state.recoveryLive!.emergencyStop,
          emergency: true,
        ),
        isTrue,
      );
      expect(state.recoveryLive!.frame.emergency, isTrue);
      expect(state.recoveryLive!.frame.revision, 55);
      output.publishGate!.complete();
      expect(await pending, isTrue);
      expect(state.recoveryLive!.frame.revision, 55);
      expect(output.held.revision, 55);
      expect(output.opens, 0);
    },
  );

  test('reconnect only inspects the exact existing renderer', () async {
    await corruptDatabase();
    output.available = false;
    final state = createBootstrap();
    await state.start();
    expect(output.attached, isFalse);
    output.available = true;
    await state.reconnectExisting();
    expect(state.recoveryLive!.frame.toMap(), _survivingFrame.toMap());
    expect(state.reconnecting, isFalse);
    expect(requestedSessions, hasLength(1));
    expect(output.opens, 0);
    expect(output.frames, isEmpty);
  });

  test(
    'failed output close keeps recovery controls available and permits retry',
    () async {
      await corruptDatabase();
      final state = createBootstrap();
      await state.start();
      output.refuseClose = true;
      expect(await state.prepareClose(), isFalse);
      expect(state.actionError, contains('could not close safely'));
      expect(state.output!.canControl, isTrue);
      expect(state.recoveryLive, isNotNull);
      expect(state.closing, isFalse);
      output.refuseClose = false;
      expect(await state.prepareClose(), isTrue);
      expect(output.closes, 2);
    },
  );

  test(
    'unsavable normal workspace blocks quit before touching the renderer',
    () async {
      final state = createBootstrap();
      await state.start();
      state.workspace!.edit(title: '');
      expect(await state.prepareClose(), isFalse);
      expect(state.workspace!.saved, isFalse);
      expect(state.actionError, contains('could not close safely'));
      expect(output.closes, 0);
      state.workspace!.edit(title: 'A corrected title');
      expect(await state.prepareClose(), isTrue);
      expect(state.workspace!.saved, isTrue);
      expect(output.closes, 1);
    },
  );

  test(
    'quit persists a correction typed while renderer shutdown is pending',
    () async {
      final state = createBootstrap();
      await state.start();
      final controller = state.workspace!;
      final selected = controller.selected!;
      output.closeGate = Completer<void>();
      output.closeStarted = Completer<void>();
      final quit = state.prepareClose();
      await output.closeStarted!.future;
      expect(state.closing, isTrue);
      controller.edit(sourceText: 'A correction made while the output closes.');
      expect(controller.saved, isFalse);
      output.closeGate!.complete();
      expect(await quit, isTrue);
      expect(controller.saved, isTrue);
      expect(
        (await controller.repository.getContent(selected.id))!.sourceText,
        'A correction made while the output closes.',
      );
      expect(await controller.repository.drafts(), isEmpty);
      expect(output.closes, 1);
      expect(output.opens, 0);
    },
  );

  test(
    'an invalid correction during shutdown keeps the operator and recovery draft',
    () async {
      final state = createBootstrap();
      await state.start();
      final controller = state.workspace!;
      final selected = controller.selected!;
      output.closeGate = Completer<void>();
      output.closeStarted = Completer<void>();
      final quit = state.prepareClose();
      await output.closeStarted!.future;
      controller.edit(title: '', sourceText: 'Keep this shutdown correction.');
      output.closeGate!.complete();
      expect(await quit, isFalse);
      expect(controller.saved, isFalse);
      expect(controller.selected!.sourceText, 'Keep this shutdown correction.');
      expect(state.actionError, contains('could not close safely'));
      expect(state.closing, isFalse);
      expect(output.attached, isFalse);
      final draft = (await controller.repository.drafts()).single;
      expect(draft.sourceText, 'Keep this shutdown correction.');
      expect(draft.title, '');
      expect(
        (await controller.repository.getContent(selected.id))!.sourceText,
        selected.sourceText,
      );
      expect(output.opens, 0);
      controller.edit(title: 'Corrected before quitting');
      expect(await state.prepareClose(), isTrue);
      expect(controller.saved, isTrue);
      expect(
        (await controller.repository.getContent(selected.id))!.sourceText,
        'Keep this shutdown correction.',
      );
      expect(output.opens, 0);
    },
  );

  test(
    'disposal disconnects without explicitly closing a surviving renderer',
    () async {
      await corruptDatabase();
      final state = createBootstrap();
      await state.start();
      state.dispose();
      bootstrap = null;
      expect(output.closes, 0);
      expect(output.opens, 0);
      expect(output.held.toMap(), _survivingFrame.toMap());
    },
  );
}
