import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cantivra/application/workspace_controller.dart';
import 'package:cantivra/data/app_repository.dart';
import 'package:cantivra/domain/models.dart';
import 'package:cantivra/presentation/desktop_output.dart';
import 'package:cantivra/presentation/live_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// Acknowledges the real controller protocol without creating native windows.
/// Native rendering/display behavior has a separate manual verification suite.
class _RecordingOutput extends DesktopOutput {
  final frames = <OutputFrame>[];
  OutputFrame? frameToRecover;
  int recoveryInspections = 0;

  @override
  bool get connected => true;

  @override
  Future<bool> recoverExisting() async {
    recoveryInspections++;
    recoveredFrame = frameToRecover;
    return recoveredFrame != null;
  }

  @override
  Future<int> publish(OutputFrame frame) async {
    frames.add(OutputFrame.fromMap(frame.toMap()));
    return frame.revision;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const displayChannel = MethodChannel('cantivra/display');
  late Directory temporary;
  late AppRepository repository;
  late _RecordingOutput output;
  late WorkspaceController controller;
  late String path;

  Future<void> createController({OutputFrame? frameToRecover}) async {
    repository = await AppRepository.open(path);
    output = _RecordingOutput()..frameToRecover = frameToRecover;
    controller = WorkspaceController(
      repository: repository,
      output: output,
      dataDirectory: temporary.path,
    );
    await controller.initialize();
  }

  Future<void> closeController() async {
    await controller.flushSave();
    // Drain queued persistence and immediate searches before disposing listeners.
    await repository.getSetting('__test_barrier__');
    controller.dispose();
    output.dispose();
    await repository.close();
  }

  Future<void> reopen() async {
    await closeController();
    await createController();
  }

  Future<void> observe(
    void Function() action,
    bool Function() condition,
  ) async {
    final completed = Completer<void>();
    void listener() {
      if (!completed.isCompleted && condition()) completed.complete();
    }

    controller.addListener(listener);
    try {
      action();
      listener();
      await completed.future.timeout(const Duration(seconds: 4));
    } finally {
      controller.removeListener(listener);
    }
  }

  Future<void> search(String query) async {
    final completed = Completer<void>();
    void listener() {
      if (!completed.isCompleted) completed.complete();
    }

    controller.addListener(listener);
    try {
      controller.setQuery(query, immediate: true);
      await completed.future.timeout(const Duration(seconds: 4));
    } finally {
      controller.removeListener(listener);
    }
  }

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(displayChannel, (call) async {
          if (call.method == 'listDisplays') {
            return [
              {
                'id': 'operator',
                'name': 'Laptop',
                'isPrimary': true,
                'x': 0,
                'y': 0,
                'width': 1440,
                'height': 900,
                'scale': 2,
              },
              {
                'id': 'hdmi-church',
                'name': 'Congregation',
                'isPrimary': false,
                'x': 1440,
                'y': 0,
                'width': 1920,
                'height': 1080,
                'scale': 1,
              },
            ];
          }
          return null;
        });
    temporary = await Directory.systemTemp.createTemp(
      'cantivra-workspace-test-',
    );
    path = '${temporary.path}/library.sqlite';
    await createController();
  });

  tearDown(() async {
    await closeController();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(displayChannel, null);
    await temporary.delete(recursive: true);
  });

  test('initialization prepares a service and preview without publishing', () {
    expect(controller.loading, isFalse);
    expect(controller.error, isNull);
    expect(controller.results, hasLength(5));
    expect(controller.services, hasLength(1));
    expect(controller.service!.items, hasLength(5));
    expect(controller.selected!.id, 'sample-welcome');
    expect(controller.selectedEntryId, controller.service!.items.first.id);
    expect(controller.preview, isNotNull);
    expect(controller.displays.map((display) => display.id), [
      'operator',
      'hdmi-church',
    ]);
    expect(controller.live.frame.mode, OutputMode.black);
    expect(output.frames, isEmpty);
  });

  for (final scenario in const {
    'malformed JSON': '{',
    'invalid theme field type': '{"fontSize":"large"}',
    'invalid theme bounds': '{"safeMargin":0.75}',
  }.entries) {
    test(
      'startup contains ${scenario.key} and recovers live without publishing',
      () async {
        expect(await controller.publishSelected(), isTrue);
        final existingFrame = OutputFrame.fromMap(
          controller.live.frame.toMap(),
        );
        await repository.saveSetting('presentationTheme', scenario.value);
        await closeController();
        await createController(frameToRecover: existingFrame);

        expect(controller.loading, isFalse);
        expect(controller.error, contains('Saved presentation theme'));
        expect(controller.theme.toMap(), builtInThemes.first.toMap());
        expect(controller.results, hasLength(5));
        expect(controller.service, isNotNull);
        expect(controller.selected!.id, 'sample-welcome');
        expect(controller.preview, isNotNull);
        expect(output.recoveryInspections, 1);
        expect(controller.live.frame.toMap(), existingFrame.toMap());
        expect(output.frames, isEmpty);
        expect(
          await repository.getSetting('presentationTheme'),
          scenario.value,
          reason: 'Startup must preserve the stored setting for recovery.',
        );

        expect(await controller.live.emergencyStop(), isTrue);
        expect(controller.live.frame.emergency, isTrue);
        expect(output.frames, hasLength(1));
      },
    );
  }

  test(
    'a failed library load still inspects and controls surviving output',
    () async {
      expect(await controller.publishSelected(), isTrue);
      final existingFrame = OutputFrame.fromMap(controller.live.frame.toMap());
      await closeController();
      final damaged = sqlite3.open(path);
      try {
        damaged.execute('DROP TABLE content_drafts');
      } finally {
        damaged.close();
      }
      await createController(frameToRecover: existingFrame);

      expect(controller.loading, isFalse);
      expect(controller.error, contains('Could not load the workspace'));
      expect(controller.error, contains('content_drafts'));
      expect(output.recoveryInspections, 1);
      expect(controller.live.frame.toMap(), existingFrame.toMap());
      expect(output.frames, isEmpty);
      expect(await controller.live.emergencyStop(), isTrue);
      expect(controller.live.frame.emergency, isTrue);
      expect(output.frames, hasLength(1));
    },
  );

  test('an edit updates only preview and autosaves the exact source', () async {
    expect(await controller.publishSelected(), isTrue);
    final published = controller.live.frame.toMap();
    final count = output.frames.length;
    const corrected =
        'Corrected welcome.\n\nSecond slide with preserved source.';
    await observe(
      () =>
          controller.edit(title: 'A Corrected Welcome', sourceText: corrected),
      () => controller.saved,
    );
    expect(controller.previewSlides.first.text, 'Corrected welcome.');
    expect(controller.live.frame.toMap(), published);
    expect(output.frames, hasLength(count));
    final stored = await repository.getContent(controller.selected!.id);
    expect(stored!.sourceText, corrected);
    expect(stored.title, 'A Corrected Welcome');
    await reopen();
    expect(controller.selected!.sourceText, corrected);
    expect(controller.live.frame.mode, OutputMode.black);
    expect(output.frames, isEmpty, reason: 'Recovery must never auto-publish.');
  });

  test(
    'selecting another item flushes its predecessor draft before switching',
    () async {
      final original = controller.selected!;
      controller.edit(
        sourceText: 'A correction saved before selection changes.',
      );
      await controller.selectContent(
        controller.contentFor('sample-amazing-grace')!,
      );
      expect(controller.selected!.id, 'sample-amazing-grace');
      expect(controller.selectedEntryId, isNull);
      expect(
        (await repository.getContent(original.id))!.sourceText,
        'A correction saved before selection changes.',
      );
      expect(controller.saved, isTrue);
      expect(output.frames, isEmpty);
    },
  );

  test(
    'selection waits for a correction made during the pending save',
    () async {
      expect(await controller.publishSelected(), isTrue);
      final liveBefore = controller.live.frame.toMap();
      final framesBefore = output.frames.length;
      final originalId = controller.selected!.id;
      final target = controller.contentFor('sample-amazing-grace')!;
      // Publication queues history and usage writes. The worker processes this
      // read after them, so the test lock cannot race those unrelated writes.
      await repository.getSetting('__test_barrier__');

      // Block the worker's write while allowing the operator event loop to
      // receive another edit. This uses an isolated test database, not a mock.
      // Acquire the lock before editing starts the journal/autosave timers.
      final writer = sqlite3.open(path)..execute('BEGIN IMMEDIATE');
      late Future<void> selection;
      try {
        controller.edit(sourceText: 'First correction waiting to save.');
        selection = controller.selectContent(target);
        await Future<void>.delayed(Duration.zero);
        expect(controller.selected!.id, originalId);
        expect(controller.saved, isFalse);
        controller.edit(sourceText: 'Latest correction during the save.');
      } finally {
        writer.execute('ROLLBACK');
        writer.close();
      }
      await selection;

      expect(controller.selected!.id, target.id);
      expect(controller.saved, isTrue);
      expect(
        (await repository.getContent(originalId))!.sourceText,
        'Latest correction during the save.',
      );
      expect(await repository.drafts(), isEmpty);
      expect(controller.live.frame.toMap(), liveBefore);
      expect(output.frames, hasLength(framesBefore));
    },
  );

  test(
    'overlapping save requests cannot restore an older draft snapshot',
    () async {
      final id = controller.selected!.id;
      controller.edit(sourceText: 'Older queued correction.');
      final first = controller.flushSave();
      final second = controller.flushSave();
      controller.edit(sourceText: 'Latest correction after two save requests.');
      await Future.wait([first, second]);

      expect(controller.saved, isTrue);
      expect(
        (await repository.getContent(id))!.sourceText,
        'Latest correction after two save requests.',
      );
      expect(await repository.drafts(), isEmpty);
      expect(output.frames, isEmpty);
    },
  );

  test(
    'service selection, duplicate, reorder, add and remove persist',
    () async {
      final original = controller.service!;
      await controller.createService('Evening Gathering', duplicate: true);
      final copy = controller.service!;
      expect(copy.id, isNot(original.id));
      expect(
        copy.items.map((entry) => entry.contentId),
        original.items.map((entry) => entry.contentId),
      );
      expect(
        copy.items
            .map((entry) => entry.id)
            .toSet()
            .intersection(original.items.map((entry) => entry.id).toSet()),
        isEmpty,
      );
      await controller.reorder(0, copy.items.length);
      expect(
        controller.service!.items.last.contentId,
        original.items.first.contentId,
      );
      final content = controller.contentFor('sample-amazing-grace')!;
      await controller.addToService(content);
      final added = controller.service!.items.last;
      expect(added.contentId, content.id);
      expect(controller.service!.items, hasLength(original.items.length + 1));
      await controller.selectContent(content, entryId: added.id);
      await controller.removeEntry(added.id);
      expect(controller.selectedEntryId, isNull);
      final expected = controller.service!.toMap();
      await reopen();
      expect(controller.service!.toMap(), expected);
      await controller.chooseService(
        controller.services.singleWhere((plan) => plan.id == original.id),
      );
      expect(controller.service!.toMap(), original.toMap());
      expect(controller.selected!.id, original.items.first.contentId);
      expect(output.frames, isEmpty);
    },
  );

  test(
    'a new empty service accepts repeated content with separate entries',
    () async {
      final content = controller.contentFor('sample-response')!;
      await controller.createService('Flexible order');
      expect(controller.service!.items, isEmpty);
      await controller.addToService(content);
      await controller.addToService(content);
      final entries = controller.service!.items;
      expect(entries.map((entry) => entry.contentId), [content.id, content.id]);
      expect(entries.first.id, isNot(entries.last.id));
      await controller.chooseService(controller.service!);
      expect(controller.selected!.id, content.id);
      expect(controller.selectedEntryId, entries.first.id);
      expect(controller.preview, isNotNull);
    },
  );

  test(
    'search and presenting unplanned content preserve the running order',
    () async {
      final plan = controller.service!;
      final runningOrder = plan.toMap();
      await search('amazing');
      expect(controller.results.single.id, 'sample-amazing-grace');
      await controller.selectContent(controller.results.single);
      expect(controller.selectedEntryId, isNull);
      expect(await controller.publishSelected(), isTrue);
      expect(
        controller.live.deck.every(
          (slide) => slide.sourceId == 'sample-amazing-grace',
        ),
        isTrue,
      );
      expect(controller.service!.toMap(), runningOrder);
      await controller.chooseService(plan);
      expect(controller.selectedEntryId, plan.items.first.id);
      expect(controller.selected!.id, plan.items.first.contentId);
      expect(controller.live.frame.slide!.sourceId, 'sample-amazing-grace');
    },
  );

  test('a service publication captures a stable ordered deck', () async {
    final entries = controller.service!.items;
    final target = entries[1];
    await controller.selectContent(
      controller.contentFor(target.contentId)!,
      entryId: target.id,
    );
    controller.selectSlide(1);
    expect(await controller.publishSelected(), isTrue);
    expect(controller.live.frame.slide!.text, controller.preview!.text);
    final publishedDeck = controller.live.deck
        .map((slide) => slide.toMap())
        .toList();
    final publishedFrame = controller.live.frame.toMap();
    await controller.reorder(0, entries.length);
    controller.edit(
      sourceText: 'An emergency correction waiting for approval.',
    );
    await controller.flushSave();
    expect(
      controller.live.deck.map((slide) => slide.toMap()).toList(),
      publishedDeck,
    );
    expect(controller.live.frame.toMap(), publishedFrame);
  });

  test(
    'theme changes recompile only preview and restore after reopen',
    () async {
      expect(await controller.publishSelected(), isTrue);
      final liveBefore = controller.live.frame.toMap();
      final framesBefore = output.frames.length;
      final theme = builtInThemes[2].copyWith(fontSize: 82, alignment: 'left');
      await controller.applyTheme(theme);
      expect(controller.preview!.theme.toMap(), theme.toMap());
      expect(controller.live.frame.toMap(), liveBefore);
      expect(output.frames, hasLength(framesBefore));
      expect(
        jsonDecode((await repository.getSetting('presentationTheme'))!),
        theme.toMap(),
      );
      await reopen();
      expect(controller.theme.toMap(), theme.toMap());
      expect(controller.preview!.theme.toMap(), theme.toMap());
      expect(output.frames, isEmpty);
    },
  );

  test(
    'navigation filters library and settings changes do not publish',
    () async {
      expect(await controller.publishSelected(), isTrue);
      final liveBefore = controller.live.frame.toMap();
      await observe(
        () => controller.navigate(WorkspacePage.hymns),
        () =>
            controller.results.length == 1 &&
            controller.results.single.kind == ContentKind.hymn,
      );
      expect(controller.page, WorkspacePage.hymns);
      await controller.toggleDark();
      expect(controller.dark, isFalse);
      expect(await repository.getSetting('darkMode'), 'false');
      controller.navigate(WorkspacePage.settings);
      expect(controller.live.frame.toMap(), liveBefore);
      await reopen();
      expect(controller.dark, isFalse);
    },
  );

  test(
    'editing then searching keeps the draft selected and publishes preview text',
    () async {
      const correction =
          'A freshly corrected welcome that must appear on screen.';
      final entryId = controller.selectedEntryId;
      controller.edit(sourceText: correction);
      await search('welcome');
      expect(controller.selected!.sourceText, correction);
      expect(controller.preview!.text, correction);
      expect(controller.selectedEntryId, entryId);
      expect(await controller.publishSelected(), isTrue);
      expect(controller.live.frame.slide!.text, correction);
      await controller.selectContent(
        controller.results.single,
        entryId: entryId,
      );
      expect(controller.selected!.sourceText, correction);
      expect(
        (await repository.getContent(controller.selected!.id))!.sourceText,
        correction,
      );
    },
  );

  test(
    'favoriting a stale library result preserves a pending source edit',
    () async {
      final staleResult = controller.selected!;
      const correction =
          'A correction must survive clicking the favorite button.';
      controller.edit(sourceText: correction);
      await controller.toggleFavorite(staleResult);
      await controller.flushSave();
      expect(controller.selected!.sourceText, correction);
      expect(controller.selected!.favorite, isNot(staleResult.favorite));
      final saved = await repository.getContent(staleResult.id);
      expect(saved!.sourceText, correction);
      expect(saved.favorite, isNot(staleResult.favorite));
    },
  );

  test(
    'backup flushes the pending draft before taking a consistent snapshot',
    () async {
      const correction = 'An emergency edit included in the manual backup.';
      final id = controller.selected!.id;
      controller.edit(sourceText: correction);
      final backupPath = await controller.backup();
      final backup = await AppRepository.open(backupPath);
      try {
        expect((await backup.getContent(id))!.sourceText, correction);
        expect(await backup.integrityCheck(), 'ok');
      } finally {
        await backup.close();
      }
      expect(controller.saved, isTrue);
      expect(output.frames, isEmpty);
    },
  );

  test(
    'failed draft save stops navigation and retains the editable correction',
    () async {
      final original = controller.selected!;
      final target = controller.contentFor('sample-amazing-grace')!;
      const correction = 'A pending correction that cannot be discarded.';
      controller.edit(title: '   ', sourceText: correction);
      await expectLater(controller.selectContent(target), throwsStateError);
      expect(controller.selected!.id, original.id);
      expect(controller.selected!.sourceText, correction);
      expect(controller.saved, isFalse);
      expect(controller.error, contains('Draft could not be saved'));
      expect(
        (await repository.getContent(original.id))!.toMap(),
        original.toMap(),
      );
      controller.edit(title: original.title);
      await controller.flushSave();
      await controller.selectContent(target);
      expect(controller.selected!.id, target.id);
      expect(
        (await repository.getContent(original.id))!.sourceText,
        correction,
      );
    },
  );

  test(
    'invalid theme is rejected before changing preview, persistence or live',
    () async {
      expect(await controller.publishSelected(), isTrue);
      final acceptedTheme = controller.theme.toMap();
      final previewBefore = controller.preview!.toMap();
      final liveBefore = controller.live.frame.toMap();
      await expectLater(
        controller.applyTheme(controller.theme.copyWith(fontSize: 0)),
        throwsFormatException,
      );
      expect(controller.theme.toMap(), acceptedTheme);
      expect(controller.preview!.toMap(), previewBefore);
      expect(controller.live.frame.toMap(), liveBefore);
      expect(await repository.getSetting('presentationTheme'), isNull);
    },
  );

  test(
    'invalid layout blocks publication while retaining the last live frame',
    () async {
      expect(await controller.publishSelected(), isTrue);
      final liveBefore = controller.live.frame.toMap();
      final framesBefore = output.frames.length;
      controller.edit(sourceText: List.filled(50001, 'x').join());
      expect(controller.layoutError, isNotNull);
      expect(controller.previewSlides, isEmpty);
      expect(await controller.publishSelected(), isFalse);
      expect(controller.live.frame.toMap(), liveBefore);
      expect(output.frames, hasLength(framesBefore));
      await controller.flushSave();
      expect(
        (await repository.getContent(controller.selected!.id))!.sourceText,
        hasLength(50001),
      );
    },
  );

  test(
    'display enumeration failure is visible and leaves content usable',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(displayChannel, (call) async {
            throw PlatformException(code: 'DISPLAY_ENUMERATION_FAILED');
          });
      await controller.refreshDisplays();
      expect(controller.error, contains('Display detection failed'));
      expect(controller.selected, isNotNull);
      expect(controller.preview, isNotNull);
      controller.edit(
        sourceText: 'A usable local preview while display detection fails.',
      );
      await controller.flushSave();
      expect(controller.saved, isTrue);
      expect(
        controller.preview!.text,
        'A usable local preview while display detection fails.',
      );
      expect(output.frames, isEmpty);
    },
  );

  test(
    'source and title undo/redo stay independent of the captured live deck',
    () async {
      expect(await controller.publishSelected(), isTrue);
      final original = controller.selected!;
      final live = controller.live.frame.toMap();
      final count = output.frames.length;
      controller.edit(sourceText: 'First edited source');
      controller.edit(title: 'Corrected title');
      expect(controller.canUndo, isTrue);
      expect(controller.canRedo, isFalse);
      controller.undo();
      expect(controller.selected!.title, original.title);
      expect(controller.selected!.sourceText, 'First edited source');
      controller.undo();
      expect(controller.selected!.sourceText, original.sourceText);
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(controller.selected!.sourceText, 'First edited source');
      controller.edit(sourceText: 'A different correction');
      expect(controller.canRedo, isFalse);
      await controller.flushSave();
      expect(controller.live.frame.toMap(), live);
      expect(output.frames, hasLength(count));
    },
  );

  test('undo histories are bounded and belong to each content item', () async {
    final first = controller.selected!;
    for (var i = 0; i < 105; i++) {
      controller.edit(title: 'Correction $i');
    }
    for (var i = 0; i < 100; i++) {
      expect(controller.canUndo, isTrue);
      controller.undo();
    }
    expect(controller.canUndo, isFalse);
    expect(controller.selected!.title, 'Correction 4');
    await controller.selectContent(controller.contentFor('sample-response')!);
    expect(controller.canUndo, isFalse);
    controller.edit(title: 'Response corrected');
    controller.undo();
    expect(controller.selected!.title, 'A Response of Thanksgiving');
    await controller.selectContent(controller.contentFor(first.id)!);
    expect(controller.canRedo, isTrue);
    expect(controller.selected!.title, 'Correction 4');
  });

  test(
    'restart stages journaled draft without committing or publishing it',
    () async {
      final original = controller.selected!;
      controller.edit(
        title: '',
        sourceText: 'A correction recovered after a crash.',
      );
      await controller.flushJournal();
      expect(
        (await repository.drafts()).single.sourceText,
        controller.selected!.sourceText,
      );
      expect(
        (await repository.getContent(original.id))!.sourceText,
        original.sourceText,
      );
      // Simulate operator loss after the durable journal but before autosave.
      controller.dispose();
      output.dispose();
      await repository.close();
      await createController();
      expect(controller.recoveredDraftCount, 1);
      expect(controller.recoveredDraftIds, {original.id});
      expect(controller.selected!.title, '');
      expect(
        controller.selected!.sourceText,
        'A correction recovered after a crash.',
      );
      expect(controller.saved, isFalse);
      expect(controller.message, contains('unsaved draft'));
      expect(output.frames, isEmpty);
      expect(
        (await repository.getContent(original.id))!.sourceText,
        original.sourceText,
      );
      expect(await repository.contentVersions(original.id), hasLength(1));
      controller.edit(title: original.title);
      await controller.flushSave();
      expect(controller.recoveredDraftCount, 0);
      expect(await repository.drafts(), isEmpty);
      expect(
        (await repository.getContent(original.id))!.sourceText,
        'A correction recovered after a crash.',
      );
    },
  );

  test(
    'multiple recovered drafts remain available as selection changes',
    () async {
      final first = controller.selected!;
      final second = controller.contentFor('sample-response')!;
      await repository.saveDraft(
        first.copyWith(
          sourceText: 'First recovered',
          modifiedAt: first.modifiedAt.add(const Duration(days: 1)),
        ),
      );
      await repository.saveDraft(
        second.copyWith(
          sourceText: 'Second recovered',
          modifiedAt: second.modifiedAt.add(const Duration(days: 1)),
        ),
      );
      await reopen();
      expect(controller.recoveredDraftCount, 2);
      final selectedId = controller.selected!.id;
      final other = controller.contentFor(
        selectedId == first.id ? second.id : first.id,
      )!;
      await controller.selectContent(other);
      expect(controller.recoveredDraftCount, 1);
      expect(controller.saved, isFalse);
      expect(controller.selected!.sourceText, contains('recovered'));
      expect(output.frames, isEmpty);
      await controller.flushSave();
      expect(controller.recoveredDraftCount, 0);
    },
  );

  test(
    'restoring a historical revision appends history and can be undone',
    () async {
      final original = controller.selected!;
      controller.edit(sourceText: 'A newer stable correction');
      await controller.flushSave();
      expect(await controller.publishSelected(), isTrue);
      final live = controller.live.frame.toMap();
      final count = output.frames.length;
      expect(await controller.versions(), hasLength(2));
      await controller.restoreVersion(original);
      final versions = await controller.versions();
      expect(versions, hasLength(3));
      expect(versions.first.sourceText, original.sourceText);
      expect(versions.first.modifiedAt.isAfter(versions[1].modifiedAt), isTrue);
      controller.undo();
      expect(controller.selected!.sourceText, 'A newer stable correction');
      expect(controller.live.frame.toMap(), live);
      expect(output.frames, hasLength(count));
      await expectLater(
        controller.restoreVersion(original.copyWith(id: 'other')),
        throwsStateError,
      );
    },
  );

  test(
    'recognition and structural overrides preserve source and live snapshots',
    () async {
      const source =
          'Verse 1\r\nFirst line of the hymn.\r\nSecond line.\r\n\r\nChorus\r\nWe sing together.';
      controller.edit(sourceText: source);
      expect(
        controller.selected!.structure,
        isNull,
        reason: 'Recognition must be explicitly accepted.',
      );
      expect(await controller.publishSelected(), isTrue);
      final live = controller.live.frame.toMap();
      final suggestion = controller.recognitionSuggestion!;
      controller.applyStructure(
        suggestion.structure,
        detectedKind: suggestion.detectedKind,
      );
      expect(controller.selected!.sourceText, source);
      expect(controller.selected!.kind, ContentKind.hymn);
      expect(
        controller.previewSlides.first.label.toLowerCase(),
        contains('verse'),
      );
      final section = controller.selected!.structure!.sections.first;
      controller.updateSection(
        section.id,
        kind: SectionKind.custom,
        label: 'Solo',
      );
      expect(controller.previewSlides.first.label, 'Solo');
      controller.undo();
      expect(
        controller.selected!.structure!.sections.first.label.toLowerCase(),
        contains('verse'),
      );
      controller.redo();
      expect(controller.previewSlides.first.label, 'Solo');
      await controller.flushSave();
      final stored = await repository.getContent(controller.selected!.id);
      expect(
        stored!.structure!.toMap(),
        controller.selected!.structure!.toMap(),
      );
      expect(stored.sourceText, source);
      expect(controller.live.frame.toMap(), live);
      controller.edit(sourceText: '$source\r\nA correction.');
      expect(controller.selected!.structure, isNull);
      expect(
        () => controller.applyStructure(suggestion.structure),
        throwsStateError,
      );
      controller.undo();
      expect(controller.selected!.sourceText, source);
      expect(controller.selected!.structure, isNotNull);
      controller.resetStructure();
      expect(controller.selected!.structure, isNull);
      expect(controller.live.frame.toMap(), live);
    },
  );

  test('manual split and merge edit only structure and respect undo', () async {
    const source = 'First phrase. Second phrase.';
    controller.edit(sourceText: source);
    expect(controller.previewSlides, hasLength(1));
    final split = source.indexOf('Second');
    controller.splitAtSourceOffset(split);
    expect(controller.selected!.sourceText, source);
    expect(controller.selected!.structure!.splitOffsets, [split]);
    expect(controller.previewSlides, hasLength(2));
    controller.selectSlide(0);
    controller.mergeSelectedWithNext();
    expect(controller.previewSlides, hasLength(1));
    expect(controller.selected!.structure!.mergedBreaks, [split]);
    expect(controller.selected!.sourceText, source);
    controller.undo();
    expect(controller.previewSlides, hasLength(2));
    controller.undo();
    expect(controller.previewSlides, hasLength(1));
    await controller.flushSave();
    expect(output.frames, isEmpty);
  });

  test(
    'restoring a version first preserves a pending correction in history',
    () async {
      final original = controller.selected!;
      controller.edit(sourceText: 'An unsaved correction worth preserving.');
      await controller.restoreVersion(original);
      final history = await controller.versions();
      expect(history.map((item) => item.sourceText), [
        original.sourceText,
        'An unsaved correction worth preserving.',
        original.sourceText,
      ]);
      expect(output.frames, isEmpty);
      controller.undo();
      expect(
        controller.selected!.sourceText,
        'An unsaved correction worth preserving.',
      );
    },
  );

  test(
    'long draft layout yields to events and preserves the live frame',
    () async {
      expect(await controller.publishSelected(), isTrue);
      final live = controller.live.frame.toMap();
      final frames = output.frames.length;
      var heartbeatWhilePending = false;
      Timer.run(() {
        heartbeatWhilePending = controller.layoutPending;
      });
      final text = List.filled(
        150,
        'A readable sentence for the next congregation slide.',
      ).join('\n');
      await observe(() {
        controller.edit(sourceText: text);
        expect(controller.layoutPending, isTrue);
        expect(
          controller.previewSlides,
          isEmpty,
          reason:
              'A stale preview must never be published while layout is pending.',
        );
      }, () => !controller.layoutPending && controller.previewSlides.isNotEmpty);
      expect(heartbeatWhilePending, isTrue);
      expect(controller.previewSlides.length, greaterThan(1));
      expect(controller.layoutError, isNull);
      expect(controller.live.frame.toMap(), live);
      expect(output.frames, hasLength(frames));
    },
  );

  test(
    'a cancelled long layout cannot overwrite a newer short correction',
    () async {
      controller.edit(
        sourceText: List.filled(
          100,
          'An older long passage waits for layout.',
        ).join('\n'),
      );
      expect(controller.layoutPending, isTrue);
      controller.edit(sourceText: 'The latest correction.');
      expect(controller.layoutPending, isFalse);
      expect(controller.preview!.text, 'The latest correction.');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.preview!.text, 'The latest correction.');
      expect(controller.layoutPending, isFalse);
      expect(controller.layoutError, isNull);
      expect(output.frames, isEmpty);
    },
  );

  test(
    'explicit publication captures its requested source and theme while preparing',
    () async {
      await controller.selectContent(controller.selected!);
      final text = List.filled(
        90,
        'Captured source before the live request.',
      ).join('\n');
      controller.edit(sourceText: text);
      final capturedTheme = controller.theme.toMap();
      final publication = controller.publishSelected();
      expect(controller.preparingPublication, isTrue);
      expect(
        await controller.publishSelected(),
        isFalse,
        reason: 'A second request cannot overtake a deck being prepared.',
      );
      controller.edit(sourceText: 'A newer draft that has not been published.');
      await controller.applyTheme(builtInThemes[1]);
      expect(await publication, isTrue);
      expect(controller.preparingPublication, isFalse);
      expect(controller.live.frame.slide!.text, contains('Captured source'));
      expect(controller.live.frame.slide!.theme.toMap(), capturedTheme);
      expect(
        controller.live.deck.every(
          (slide) => slide.sourceId == controller.selected!.id,
        ),
        isTrue,
      );
      expect(
        controller.preview!.text,
        'A newer draft that has not been published.',
      );
      expect(controller.preview!.theme.id, builtInThemes[1].id);
    },
  );

  test('an emergency supersedes a deck still being prepared', () async {
    expect(await controller.publishSelected(), isTrue);
    final frames = output.frames.length;
    controller.edit(
      sourceText: List.filled(90, 'A long requested passage.').join('\n'),
    );
    final publication = controller.publishSelected();
    expect(controller.preparingPublication, isTrue);
    expect(await controller.live.emergencyStop(), isTrue);
    expect(await publication, isFalse);
    expect(controller.preparingPublication, isFalse);
    expect(controller.live.frame.mode, OutputMode.black);
    expect(controller.live.frame.emergency, isTrue);
    expect(output.frames, hasLength(frames + 1));
  });
}
