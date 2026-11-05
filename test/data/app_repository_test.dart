import 'dart:convert';
import 'dart:io';

import 'package:cantivra/data/app_repository.dart';
import 'package:cantivra/data/schema.dart';
import 'package:cantivra/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory temporary;
  late AppRepository repository;
  late String path;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cantivra-storage-test-');
    path = '${temporary.path}/library.sqlite';
    repository = await AppRepository.open(path);
  });

  tearDown(() async {
    await repository.close();
    await temporary.delete(recursive: true);
  });

  ContentItem item({
    String id = 'test-content',
    String title = 'Pilgrim Song',
    String text = 'We gather beside the mountain in gratitude.',
    ContentKind kind = ContentKind.hymn,
  }) => ContentItem(
    id: id,
    title: title,
    kind: kind,
    sourceText: text,
    tags: ['pilgrimage', 'fellowshiptoken'],
    modifiedAt: DateTime.utc(2026, 11, 4),
  );

  test('creates a healthy database with a usable service only once', () async {
    final content = await repository.searchContent('');
    final services = await repository.listServices();
    expect(content, hasLength(5));
    expect(services, hasLength(1));
    expect(services.single.items, hasLength(5));
    expect(await repository.integrityCheck(), 'ok');
    await repository.close();
    repository = await AppRepository.open(path);
    expect(await repository.searchContent(''), hasLength(content.length));
    expect(await repository.listServices(), hasLength(1));
  });

  test(
    'persists metadata, exact original text, and settings across reopen',
    () async {
      final original = item(
        text: 'Verse 1\n  Spacing stays.\n\nAll: Amen!\n',
      ).copyWith(language: 'Malayalam', favorite: true);
      await repository.saveContent(original);
      await repository.saveSetting('preferredDisplay', 'HDMI-2');
      await repository.close();
      repository = await AppRepository.open(path);
      expect(
        (await repository.getContent(original.id))!.toMap(),
        original.toMap(),
      );
      expect(await repository.getSetting('preferredDisplay'), 'HDMI-2');
      expect(await repository.getSetting('missing'), isNull);
      expect(await repository.getContent('missing'), isNull);
    },
  );

  test(
    'FTS searches title, lyrics, tags, prefixes, accents and kind',
    () async {
      await repository.saveContent(item());
      await repository.saveContent(item(id: 'other', kind: ContentKind.prayer));
      for (final query in ['pilg', 'moun', 'fellow', 'gather beside']) {
        expect(
          await repository.searchContent(query),
          hasLength(2),
          reason: query,
        );
      }
      expect(
        await repository.searchContent('mount', kind: ContentKind.prayer),
        hasLength(1),
      );
      expect(
        await repository.searchContent('', kind: ContentKind.prayer),
        hasLength(2),
      );
      await repository.saveContent(
        item(id: 'accent', title: 'Église', text: 'प्रार्थना'),
      );
      expect((await repository.searchContent('egl')).single.id, 'accent');
      expect((await repository.searchContent('प्रार्थना')).single.id, 'accent');
    },
  );

  test(
    'literal symbols and attempted FTS/SQL syntax cannot damage search',
    () async {
      for (final query in [
        '!!!',
        '"',
        '*',
        '" OR 1=1 --',
        'NEAR(foo, bar)',
        "'; DROP TABLE content;--",
      ]) {
        await repository.searchContent(query);
      }
      expect(await repository.searchContent('!!!'), isEmpty);
      expect(await repository.searchContent(''), hasLength(5));
      expect(await repository.integrityCheck(), 'ok');
    },
  );

  test(
    'atomic content edit keeps complete revisions and refreshes FTS',
    () async {
      final original = item(text: 'Oldword unique');
      await repository.saveContent(original);
      final revised = original.copyWith(
        sourceText: 'Newword corrected',
        modifiedAt: DateTime.utc(2026, 11, 5),
      );
      await repository.saveContent(revised);
      expect(await repository.searchContent('oldword'), isEmpty);
      expect((await repository.searchContent('newword')).single.id, revised.id);
      final revisions = await repository.contentVersions(original.id);
      expect(revisions.map((item) => item.sourceText), [
        revised.sourceText,
        original.sourceText,
      ]);
      expect(await repository.integrityCheck(), 'ok');
    },
  );

  test(
    'invalid edit rolls back without losing content or its revisions',
    () async {
      final original = item();
      await repository.saveContent(original);
      await expectLater(
        repository.saveContent(original.copyWith(title: '  ')),
        throwsA(isA<RepositoryException>()),
      );
      expect((await repository.getContent(original.id))!.title, original.title);
      expect(await repository.contentVersions(original.id), hasLength(1));
      expect(await repository.searchContent('pilgrim'), hasLength(1));
    },
  );

  test(
    'service reordering and duplicate content entries survive reopen',
    () async {
      final service = (await repository.listServices()).single;
      final reversed = service.items.reversed.toList();
      reversed.add(
        reversed.first.copyWith(id: 'repeat-entry', label: 'Repeat'),
      );
      final changed = service.copyWith(
        title: 'Evening Prayer',
        items: reversed,
      );
      await repository.saveService(changed);
      await repository.close();
      repository = await AppRepository.open(path);
      expect((await repository.listServices()).single.toMap(), changed.toMap());
    },
  );

  test(
    'invalid service references roll back title and complete running order',
    () async {
      final service = (await repository.listServices()).single;
      final invalid = service.copyWith(
        title: 'This must roll back',
        items: [
          service.items.first,
          const ServiceEntry(
            id: 'invalid',
            contentId: 'does-not-exist',
            label: 'Broken',
          ),
        ],
      );
      await expectLater(
        repository.saveService(invalid),
        throwsA(isA<RepositoryException>()),
      );
      expect((await repository.listServices()).single.toMap(), service.toMap());
      await expectLater(
        repository.saveService(
          service.copyWith(items: [service.items.first, service.items.first]),
        ),
        throwsA(isA<RepositoryException>()),
      );
      expect((await repository.listServices()).single.toMap(), service.toMap());
      expect(await repository.integrityCheck(), 'ok');
    },
  );

  test('requests are serialized and errors leave worker usable', () async {
    final writes = List.generate(
      30,
      (index) => repository.saveSetting('queued-$index', '$index'),
    );
    await Future.wait(writes);
    final values = await Future.wait(
      List.generate(30, (index) => repository.getSetting('queued-$index')),
    );
    expect(values, List.generate(30, (index) => '$index'));
    await expectLater(
      repository.recordPresentation('missing-content'),
      throwsA(isA<RepositoryException>()),
    );
    await repository.recordPresentation('sample-amazing-grace');
    expect(await repository.integrityCheck(), 'ok');
  });

  test(
    'backup is standalone, complete, verified and never overwrites a file',
    () async {
      await repository.saveContent(item());
      await repository.saveSetting('backup-test', 'retained');
      final backupPath = '${temporary.path}/backups/manual.sqlite';
      await repository.backup(backupPath);
      final backup = await AppRepository.open(backupPath);
      try {
        expect(
          (await backup.getContent('test-content'))!.title,
          'Pilgrim Song',
        );
        expect(await backup.getSetting('backup-test'), 'retained');
        expect(await backup.contentVersions('test-content'), hasLength(1));
        expect(await backup.integrityCheck(), 'ok');
      } finally {
        await backup.close();
      }
      final bytes = await File(backupPath).readAsBytes();
      await expectLater(
        repository.backup(backupPath),
        throwsA(isA<RepositoryException>()),
      );
      expect(await File(backupPath).readAsBytes(), bytes);
      final emptyPath = '${temporary.path}/empty.sqlite';
      await File(emptyPath).create();
      await expectLater(
        repository.backup(emptyPath),
        throwsA(isA<RepositoryException>()),
      );
      expect(await File(emptyPath).length(), 0);
    },
  );

  test('close is idempotent and later operations fail immediately', () async {
    await repository.close();
    await repository.close();
    await expectLater(repository.searchContent(''), throwsStateError);
  });

  test('a newer schema is rejected without changing the database', () async {
    await repository.close();
    final direct = sqlite3.open(path);
    direct.execute('PRAGMA user_version = 999');
    direct.close();
    await expectLater(
      AppRepository.open(path),
      throwsA(isA<RepositoryException>()),
    );
    final check = sqlite3.open(path);
    expect(check.select('PRAGMA user_version').first.values.first, 999);
    check.execute('PRAGMA user_version = $schemaVersion');
    check.close();
    repository = await AppRepository.open(path);
    expect(await repository.integrityCheck(), 'ok');
  });

  test('startup file errors are reported without hanging', () async {
    final file = File('${temporary.path}/not-a-directory');
    await file.writeAsString('occupied');
    await expectLater(
      AppRepository.open('${file.path}/library.sqlite'),
      throwsA(isA<RepositoryException>()),
    );
    expect(await repository.integrityCheck(), 'ok');
  });

  test(
    'migrates v1 transactionally without rewriting original content or history',
    () async {
      final legacyPath = '${temporary.path}/legacy.sqlite';
      final original = item(text: 'Verse 1\r\n  Exact original spacing.\r\n');
      final legacy = sqlite3.open(legacyPath);
      legacy.execute(schemaV1);
      legacy.execute('PRAGMA user_version = 1');
      legacy.execute(
        'INSERT INTO content(id,title,kind,source_text,language,tags,favorite,created_at,modified_at) '
        'VALUES (?,?,?,?,?,?,?,?,?)',
        [
          original.id,
          original.title,
          original.kind.name,
          original.sourceText,
          original.language,
          '[]',
          0,
          original.modifiedAt.toIso8601String(),
          original.modifiedAt.toIso8601String(),
        ],
      );
      legacy.execute(
        "INSERT INTO settings(key,value) VALUES ('preserved','yes')",
      );
      legacy.execute(
        'INSERT INTO content_versions(content_id,snapshot_json,saved_at) VALUES (?,?,?)',
        [
          original.id,
          jsonEncode(original.toMap()),
          original.modifiedAt.toIso8601String(),
        ],
      );
      legacy.execute(
        'INSERT INTO services(id,title,modified_at) VALUES (?,?,?)',
        [
          'legacy-service',
          'An existing service',
          original.modifiedAt.toIso8601String(),
        ],
      );
      legacy.execute(
        'INSERT INTO service_items(id,service_id,content_id,label,position) VALUES (?,?,?,?,?)',
        ['legacy-entry', 'legacy-service', original.id, 'Opening hymn', 0],
      );
      legacy.close();
      final migrated = await AppRepository.open(legacyPath);
      try {
        expect(
          (await migrated.getContent(original.id))!.sourceText,
          original.sourceText,
        );
        expect((await migrated.getContent(original.id))!.structure, isNull);
        expect(await migrated.getSetting('preserved'), 'yes');
        expect(
          (await migrated.contentVersions(original.id)).single.toMap(),
          original.toMap(),
        );
        expect(
          (await migrated.listServices()).single.items.single.contentId,
          original.id,
        );
        expect(await migrated.searchContent('exact'), hasLength(1));
        expect(await migrated.drafts(), isEmpty);
        expect(await migrated.integrityCheck(), 'ok');
      } finally {
        await migrated.close();
      }
      final check = sqlite3.open(legacyPath);
      expect(
        check.select('PRAGMA user_version').single.values.first,
        schemaVersion,
      );
      expect(
        check.select('SELECT created_at FROM content').single['created_at'],
        original.modifiedAt.toIso8601String(),
      );
      check.close();
    },
  );

  test(
    'failed migration rolls back columns and leaves the original v1 data',
    () async {
      final legacyPath = '${temporary.path}/invalid-migration.sqlite';
      final legacy = sqlite3.open(legacyPath);
      legacy.execute(schemaV1);
      legacy.execute('CREATE TABLE content_drafts (conflict TEXT)');
      legacy.execute('PRAGMA user_version = 1');
      legacy.execute(
        "INSERT INTO settings(key,value) VALUES ('original','retained')",
      );
      legacy.close();
      await expectLater(
        AppRepository.open(legacyPath),
        throwsA(isA<RepositoryException>()),
      );
      final check = sqlite3.open(legacyPath);
      expect(check.select('PRAGMA user_version').single.values.first, 1);
      expect(
        check.select('PRAGMA table_info(content)').map((row) => row['name']),
        isNot(contains('structure_json')),
      );
      expect(
        check.select('SELECT value FROM settings').single['value'],
        'retained',
      );
      check.close();
    },
  );

  test(
    'recovery journals incomplete text independently across restart',
    () async {
      final original = item();
      await repository.saveContent(original);
      final draft = original.copyWith(
        title: '',
        sourceText: 'An incomplete correction.',
        modifiedAt: original.modifiedAt.add(const Duration(seconds: 1)),
      );
      await repository.saveDraft(draft);
      await repository.close();
      repository = await AppRepository.open(path);
      expect((await repository.drafts()).single.toMap(), draft.toMap());
      expect(
        (await repository.getContent(original.id))!.toMap(),
        original.toMap(),
      );
      expect(await repository.contentVersions(original.id), hasLength(1));
      expect(await repository.searchContent('incomplete'), isEmpty);
      expect(await repository.integrityCheck(), 'ok');
    },
  );

  test('saving an older edit cannot clear a newer recovery snapshot', () async {
    final original = item();
    await repository.saveContent(original);
    final older = original.copyWith(
      sourceText: 'Older correction',
      modifiedAt: original.modifiedAt.add(const Duration(microseconds: 1)),
    );
    final newer = original.copyWith(
      sourceText: 'Newer correction',
      modifiedAt: original.modifiedAt.add(const Duration(microseconds: 2)),
    );
    await repository.saveDraft(newer);
    await repository.saveContent(older);
    await repository.saveDraft(older);
    await repository.discardDraft(original.id, expected: older);
    expect((await repository.drafts()).single.toMap(), newer.toMap());
    expect(
      (await repository.getContent(original.id))!.sourceText,
      older.sourceText,
    );
    await repository.saveContent(newer);
    expect(await repository.drafts(), isEmpty);
    await repository.saveDraft(older);
    expect(
      await repository.drafts(),
      isEmpty,
      reason: 'An old delayed journal must not resurrect a saved draft.',
    );
  });

  test(
    'journal errors never discard a previously recoverable snapshot',
    () async {
      final original = item();
      await repository.saveContent(original);
      final draft = original.copyWith(
        sourceText: 'Recover me',
        modifiedAt: original.modifiedAt.add(const Duration(seconds: 1)),
      );
      await repository.saveDraft(draft);
      await expectLater(
        repository.saveContent(draft.copyWith(title: ' ')),
        throwsA(isA<RepositoryException>()),
      );
      expect((await repository.drafts()).single.toMap(), draft.toMap());
      await expectLater(
        repository.saveDraft(draft.copyWith(id: 'not-found')),
        throwsA(isA<RepositoryException>()),
      );
      expect((await repository.drafts()).single.toMap(), draft.toMap());
      await repository.discardDraft(original.id, expected: draft);
      expect(await repository.drafts(), isEmpty);
      expect(
        (await repository.getContent(original.id))!.toMap(),
        original.toMap(),
      );
    },
  );

  test('domain lists cannot be mutated behind a prepared snapshot', () {
    final mutableTags = ['original'];
    final content = item().copyWith(tags: mutableTags);
    mutableTags.add('later');
    expect(content.tags, ['original']);
    expect(() => content.tags.add('forbidden'), throwsUnsupportedError);
    final entries = <ServiceEntry>[];
    final plan = ServicePlan(
      id: 'immutable',
      title: 'Test',
      items: entries,
      modifiedAt: DateTime.utc(2026),
    );
    entries.add(
      const ServiceEntry(id: 'entry', contentId: 'item', label: 'Test'),
    );
    expect(plan.items, isEmpty);
    expect(
      PresentationTheme.fromMap(const PresentationTheme().toMap()).toMap(),
      const PresentationTheme().toMap(),
    );
    expect(ContentItem.fromMap(content.toMap()).toMap(), content.toMap());
    expect(ServicePlan.fromMap(plan.toMap()).toMap(), plan.toMap());
  });
}
