import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import '../domain/models.dart';
import 'schema.dart';

class RepositoryException implements Exception {
  const RepositoryException(this.operation, this.message);

  final String operation;
  final String message;

  @override
  String toString() => 'Storage $operation failed: $message';
}

/// A single background isolate owns the connection for its whole lifetime.
/// Every request is serialized there; neither SQLite nor disk IO runs on the
/// operator or presentation isolate. Callers receive immutable domain values.
class AppRepository {
  AppRepository._() {
    _responses.listen(_handleResponse);
  }

  final ReceivePort _responses = ReceivePort();
  final Completer<void> _ready = Completer<void>();
  final Map<int, Completer<Object?>> _pending = {};
  Isolate? _worker;
  SendPort? _commands;
  int _nextRequest = 0;
  bool _closed = false;
  bool _closing = false;

  static Future<AppRepository> open(String path) async {
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'Must not be empty');
    }
    final repository = AppRepository._();
    final startup = repository._ready.future.timeout(
      const Duration(seconds: 20),
    );
    startup.ignore();
    try {
      repository._worker = await Isolate.spawn(
        _databaseWorker,
        <Object>[path, repository._responses.sendPort],
        onError: repository._responses.sendPort,
        onExit: repository._responses.sendPort,
        debugName: 'cantivra-sqlite',
      );
      await startup;
      return repository;
    } catch (_) {
      repository._responses.close();
      repository._worker?.kill(priority: Isolate.immediate);
      rethrow;
    }
  }

  Future<List<ContentItem>> searchContent(
    String query, {
    ContentKind? kind,
  }) async {
    final result = await _request('search', {
      'query': query,
      'kind': kind?.name,
    });
    return _mapList(result).map(ContentItem.fromMap).toList(growable: false);
  }

  Future<ContentItem?> getContent(String id) async {
    final result = await _request('getContent', {'id': id});
    return result == null ? null : ContentItem.fromMap(_map(result));
  }

  /// Saves the original text and a complete revision in one transaction.
  Future<void> saveContent(ContentItem item) async {
    await _request('saveContent', item.toMap());
  }

  /// Writes a recoverable snapshot without publishing it to the library or
  /// creating a stable revision. Older queued edits cannot replace newer ones.
  Future<void> saveDraft(ContentItem item) async {
    await _request('saveDraft', item.toMap());
  }

  Future<List<ContentItem>> drafts() async {
    final result = await _request('drafts');
    return _mapList(result).map(ContentItem.fromMap).toList(growable: false);
  }

  /// Optionally compare the full snapshot so an old discard/save cannot erase
  /// a more recent journal entry written while the operation was pending.
  Future<void> discardDraft(String id, {ContentItem? expected}) async {
    if (expected != null && expected.id != id) {
      throw ArgumentError('The expected draft must have the same content ID.');
    }
    await _request('discardDraft', {
      'id': id,
      'expected': expected == null ? null : jsonEncode(expected.toMap()),
    });
  }

  Future<List<ContentItem>> contentVersions(String id) async {
    final result = await _request('contentVersions', {'id': id});
    return _mapList(result).map(ContentItem.fromMap).toList(growable: false);
  }

  Future<List<ServicePlan>> listServices() async {
    final result = await _request('listServices');
    return _mapList(result).map(ServicePlan.fromMap).toList(growable: false);
  }

  /// Replaces one service's ordering atomically. A missing content reference,
  /// duplicate entry ID, or invalid position rolls back the entire operation.
  Future<void> saveService(ServicePlan plan) async {
    await _request('saveService', plan.toMap());
  }

  Future<void> saveSetting(String key, String value) async {
    await _request('saveSetting', {'key': key, 'value': value});
  }

  Future<String?> getSetting(String key) async =>
      await _request('getSetting', {'key': key}) as String?;

  Future<void> recordPresentation(String contentId) async {
    await _request('recordPresentation', {'id': contentId});
  }

  /// Checks the database, foreign keys, and synchronization of the FTS index.
  Future<String> integrityCheck() async =>
      await _request('integrityCheck') as String;

  /// Produces a consistent standalone SQLite snapshot and refuses all existing
  /// files, including empty files. Never copy only a live WAL database's .db.
  Future<void> backup(String targetPath) async {
    await _request('backup', {'path': targetPath});
  }

  Future<void> close() async {
    if (_closed || _closing) return;
    _closing = true;
    try {
      await _request('close', const {}, true);
    } finally {
      _closed = true;
      _responses.close();
      _worker?.kill();
    }
  }

  Future<Object?> _request(
    String operation, [
    Map<String, Object?> args = const {},
    bool allowClosing = false,
  ]) {
    if (_closed || (_closing && !allowClosing)) {
      return Future.error(StateError('Repository is closed'));
    }
    final id = _nextRequest++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _commands!.send({'id': id, 'operation': operation, 'args': args});
    return completer.future;
  }

  void _handleResponse(Object? message) {
    if (message == null) {
      if (!_closing) _fail('The storage worker stopped unexpectedly');
      return;
    }
    if (message is List) {
      _fail(message.first.toString());
      return;
    }
    final response = _map(message);
    if (response['ready'] == true) {
      _commands = response['port'] as SendPort;
      _ready.complete();
      return;
    }
    if (response['startupError'] != null) {
      _fail(response['startupError']! as String);
      return;
    }
    final completer = _pending.remove(response['id']);
    if (completer == null) return;
    if (response['error'] != null) {
      completer.completeError(
        RepositoryException(
          response['operation']! as String,
          response['error']! as String,
        ),
      );
    } else {
      completer.complete(response['result']);
    }
  }

  void _fail(String message) {
    _closed = true;
    final error = RepositoryException('worker', message);
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
    _responses.close();
  }
}

Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value! as Map);

Iterable<Map<String, Object?>> _mapList(Object? value) =>
    (value! as List).map(_map);

void _databaseWorker(List<Object> startup) {
  final path = startup[0] as String;
  final responses = startup[1] as SendPort;
  Database database;
  try {
    if (path != ':memory:') File(path).parent.createSync(recursive: true);
    database = sqlite3.open(path);
    try {
      database.execute('PRAGMA foreign_keys = ON');
      database.execute('PRAGMA busy_timeout = 5000');
      database.execute('PRAGMA journal_mode = WAL');
      database.execute('PRAGMA synchronous = FULL');
      _migrate(database);
    } catch (_) {
      database.close();
      rethrow;
    }
  } catch (error) {
    responses.send({'startupError': error.toString()});
    return;
  }
  final commands = ReceivePort();
  responses.send({'ready': true, 'port': commands.sendPort});
  commands.listen((Object? message) {
    final request = _map(message);
    final operation = request['operation']! as String;
    try {
      final result = _dispatch(database, operation, _map(request['args']));
      responses.send({'id': request['id'], 'result': result});
      if (operation == 'close') commands.close();
    } catch (error) {
      responses.send({
        'id': request['id'],
        'operation': operation,
        'error': error.toString(),
      });
    }
  });
}

Object? _dispatch(Database db, String operation, Map<String, Object?> args) {
  switch (operation) {
    case 'search':
      return _search(db, args['query']! as String, args['kind'] as String?);
    case 'getContent':
      final rows = db.select('SELECT * FROM content WHERE id = ?', [
        args['id'],
      ]);
      return rows.isEmpty ? null : _contentRow(rows.first);
    case 'saveContent':
      _transaction(db, () => _saveContent(db, ContentItem.fromMap(args)));
      return null;
    case 'saveDraft':
      final item = ContentItem.fromMap(args);
      final stable = db.select('SELECT modified_at FROM content WHERE id = ?', [
        item.id,
      ]);
      if (stable.isEmpty) throw StateError('The draft content does not exist.');
      if (!item.modifiedAt.isAfter(
        DateTime.parse(stable.single['modified_at'] as String),
      )) {
        return null;
      }
      final existing = db.select(
        'SELECT modified_at FROM content_drafts WHERE content_id = ?',
        [item.id],
      );
      if (existing.isNotEmpty &&
          item.modifiedAt.isBefore(
            DateTime.parse(existing.single['modified_at'] as String),
          )) {
        return null;
      }
      db.execute(
        'INSERT INTO content_drafts(content_id,snapshot_json,modified_at,journaled_at) '
        'VALUES (?,?,?,?) ON CONFLICT(content_id) DO UPDATE SET '
        'snapshot_json=excluded.snapshot_json,modified_at=excluded.modified_at,'
        'journaled_at=excluded.journaled_at',
        [
          item.id,
          jsonEncode(item.toMap()),
          item.modifiedAt.toUtc().toIso8601String(),
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
      return null;
    case 'drafts':
      return db
          .select(
            'SELECT snapshot_json FROM content_drafts ORDER BY journaled_at DESC',
          )
          .map((row) => jsonDecode(row['snapshot_json'] as String))
          .toList();
    case 'discardDraft':
      db.execute(
        'DELETE FROM content_drafts WHERE content_id = ? '
        'AND (? IS NULL OR snapshot_json = ?)',
        [args['id'], args['expected'], args['expected']],
      );
      return null;
    case 'contentVersions':
      return db
          .select(
            'SELECT snapshot_json FROM content_versions WHERE content_id = ? '
            'ORDER BY revision DESC',
            [args['id']],
          )
          .map((row) => jsonDecode(row['snapshot_json'] as String))
          .toList();
    case 'listServices':
      return db
          .select('SELECT * FROM services ORDER BY modified_at DESC, id')
          .map((row) => _serviceRow(db, row))
          .toList();
    case 'saveService':
      _transaction(db, () => _saveService(db, ServicePlan.fromMap(args)));
      return null;
    case 'saveSetting':
      db.execute(
        'INSERT INTO settings(key,value) VALUES (?,?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [args['key'], args['value']],
      );
      return null;
    case 'getSetting':
      final rows = db.select('SELECT value FROM settings WHERE key = ?', [
        args['key'],
      ]);
      return rows.isEmpty ? null : rows.first['value'];
    case 'recordPresentation':
      db.execute(
        'INSERT INTO usage_events(content_id,event_type,occurred_at) VALUES (?,?,?)',
        [args['id'], 'presented', DateTime.now().toUtc().toIso8601String()],
      );
      return null;
    case 'integrityCheck':
      final checks = db.select('PRAGMA integrity_check');
      final problems = checks
          .map((row) => row.values.first)
          .where((value) => value != 'ok')
          .toList();
      final foreignKeys = db.select('PRAGMA foreign_key_check');
      if (foreignKeys.isNotEmpty) {
        problems.add('Foreign key violations: ${foreignKeys.length}');
      }
      // rank=1 checks external content against the index, not only its B-tree.
      db.execute(
        "INSERT INTO content_fts(content_fts,rank) VALUES ('integrity-check',1)",
      );
      return problems.isEmpty ? 'ok' : problems.join('\n');
    case 'backup':
      _backup(db, args['path']! as String);
      return null;
    case 'close':
      db.close();
      return null;
    default:
      throw UnsupportedError('Unknown storage operation: $operation');
  }
}

void _migrate(Database db) {
  final version = db.select('PRAGMA user_version').first.values.first as int;
  if (version > schemaVersion) {
    throw StateError(
      'This library requires a newer version of Cantivra. Its schema is $version; this app supports $schemaVersion.',
    );
  }
  if (version == schemaVersion) return;
  _transaction(db, () {
    if (version == 0) {
      db.execute(schemaV1);
    }
    if (version < 2) db.execute(schemaV2);
    if (version == 0) _seed(db);
    db.execute('PRAGMA user_version = $schemaVersion');
  });
}

void _transaction(Database db, void Function() action) {
  db.execute('BEGIN IMMEDIATE');
  try {
    action();
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

void _saveContent(Database db, ContentItem item) {
  final timestamp = item.modifiedAt.toUtc().toIso8601String();
  db.execute(
    'INSERT INTO content(id,title,kind,source_text,language,tags,favorite,created_at,modified_at,structure_json) '
    'VALUES (?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET '
    'title=excluded.title,kind=excluded.kind,source_text=excluded.source_text,'
    'language=excluded.language,tags=excluded.tags,favorite=excluded.favorite,'
    'modified_at=excluded.modified_at,structure_json=excluded.structure_json',
    [
      item.id,
      item.title,
      item.kind.name,
      item.sourceText,
      item.language,
      jsonEncode(item.tags),
      item.favorite ? 1 : 0,
      timestamp,
      timestamp,
      item.structure == null ? null : jsonEncode(item.structure!.toMap()),
    ],
  );
  db.execute(
    'INSERT INTO content_versions(content_id,snapshot_json,saved_at) VALUES (?,?,?)',
    [
      item.id,
      jsonEncode(item.toMap()),
      DateTime.now().toUtc().toIso8601String(),
    ],
  );
  db.execute(
    'DELETE FROM content_drafts WHERE content_id = ? AND snapshot_json = ?',
    [item.id, jsonEncode(item.toMap())],
  );
}

void _saveService(Database db, ServicePlan plan) {
  db.execute(
    'INSERT INTO services(id,title,modified_at) VALUES (?,?,?) '
    'ON CONFLICT(id) DO UPDATE SET title=excluded.title,modified_at=excluded.modified_at',
    [plan.id, plan.title, plan.modifiedAt.toUtc().toIso8601String()],
  );
  db.execute('DELETE FROM service_items WHERE service_id = ?', [plan.id]);
  for (var index = 0; index < plan.items.length; index++) {
    final item = plan.items[index];
    db.execute(
      'INSERT INTO service_items(id,service_id,content_id,label,position) VALUES (?,?,?,?,?)',
      [item.id, plan.id, item.contentId, item.label, index],
    );
  }
}

Map<String, Object?> _contentRow(Row row) => {
  'id': row['id'],
  'title': row['title'],
  'kind': row['kind'],
  'sourceText': row['source_text'],
  'language': row['language'],
  'tags': jsonDecode(row['tags'] as String),
  'favorite': row['favorite'] == 1,
  'modifiedAt': row['modified_at'],
  if (row['structure_json'] != null)
    'structure': jsonDecode(row['structure_json'] as String),
};

Map<String, Object?> _serviceRow(Database db, Row row) => {
  'id': row['id'],
  'title': row['title'],
  'modifiedAt': row['modified_at'],
  'items': db
      .select(
        'SELECT * FROM service_items WHERE service_id = ? ORDER BY position',
        [row['id']],
      )
      .map(
        (entry) => {
          'id': entry['id'],
          'contentId': entry['content_id'],
          'label': entry['label'],
        },
      )
      .toList(),
};

List<Map<String, Object?>> _search(Database db, String query, String? kind) {
  // Treat input as literal search words, never as user-authored FTS grammar.
  // Unicode letters/marks/numbers retain non-English lyrics and references.
  final words = RegExp(
    r'[\p{L}\p{M}\p{N}]+',
    unicode: true,
  ).allMatches(query).map((match) => '"${match.group(0)}"*').take(32).toList();
  if (words.isEmpty) {
    if (query.trim().isNotEmpty) return [];
    return db
        .select(
          'SELECT * FROM content WHERE (? IS NULL OR kind = ?) '
          'ORDER BY favorite DESC, title COLLATE NOCASE, id',
          [kind, kind],
        )
        .map(_contentRow)
        .toList();
  }
  return db
      .select(
        'SELECT content.* FROM content JOIN content_fts ON content_fts.rowid=content.rowid '
        'WHERE content_fts MATCH ? AND (? IS NULL OR content.kind = ?) '
        'ORDER BY bm25(content_fts,8.0,1.0,3.0), content.favorite DESC, content.title COLLATE NOCASE',
        [words.join(' AND '), kind, kind],
      )
      .map(_contentRow)
      .toList();
}

void _backup(Database db, String path) {
  if (path.trim().isEmpty) throw ArgumentError('Backup path must not be empty');
  final target = File(path);
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw StateError('Backup destination already exists; choose a new file');
  }
  target.parent.createSync(recursive: true);
  db.execute('VACUUM INTO ?', [target.absolute.path]);
  // Verify the finished snapshot before reporting success. A failed snapshot
  // remains available for investigation and is never passed off as a backup.
  final snapshot = sqlite3.open(target.absolute.path, mode: OpenMode.readOnly);
  try {
    final result = snapshot.select('PRAGMA integrity_check').first.values.first;
    if (result != 'ok') {
      throw StateError('Backup integrity check failed: $result');
    }
  } finally {
    snapshot.close();
  }
}

void _seed(Database db) {
  final now = DateTime.now().toUtc();
  final items = [
    ContentItem(
      id: 'sample-amazing-grace',
      title: 'Amazing Grace',
      kind: ContentKind.hymn,
      sourceText:
          'Verse 1\nAmazing grace! how sweet the sound,\nThat saved a wretch like me!\nI once was lost, but now am found,\nWas blind, but now I see.\n\nVerse 2\n’Twas grace that taught my heart to fear,\nAnd grace my fears relieved;\nHow precious did that grace appear\nThe hour I first believed.',
      tags: ['grace', 'traditional', 'public domain'],
      favorite: true,
      modifiedAt: now,
    ),
    ContentItem(
      id: 'sample-gathering',
      title: 'A Prayer for Our Gathering',
      kind: ContentKind.prayer,
      sourceText:
          'Leader: We gather in gratitude and hope.\n\nAll: May our hearts be open to love.\n\nLeader: Guide our words and actions today.\n\nAll: Help us to serve one another with joy.',
      tags: ['gathering', 'original'],
      modifiedAt: now,
    ),
    ContentItem(
      id: 'sample-psalm',
      title: 'The Lord Is My Shepherd',
      kind: ContentKind.reading,
      sourceText:
          'Psalm 23:1–3 · King James Version\n\nThe Lord is my shepherd; I shall not want.\n\nHe maketh me to lie down in green pastures: he leadeth me beside the still waters.\n\nHe restoreth my soul: he leadeth me in the paths of righteousness for his name’s sake.',
      tags: ['psalm', 'trust', 'public domain'],
      modifiedAt: now,
    ),
    ContentItem(
      id: 'sample-response',
      title: 'A Response of Thanksgiving',
      kind: ContentKind.response,
      sourceText:
          'Leader: For the gift of this day,\nAll: We give thanks.\n\nLeader: For those who walk beside us,\nAll: We give thanks.\n\nLeader: For the hope we share,\nAll: We give thanks.',
      tags: ['thanksgiving', 'original'],
      modifiedAt: now,
    ),
    ContentItem(
      id: 'sample-welcome',
      title: 'Welcome to Our Community',
      kind: ContentKind.announcement,
      sourceText:
          'Welcome\n\nWe are glad you are here.\nPlease take a moment to prepare your heart.\n\nSilence your phone and join us in worship.',
      tags: ['welcome', 'original'],
      modifiedAt: now,
    ),
  ];
  for (final item in items) {
    _saveContent(db, item);
  }
  _saveService(
    db,
    ServicePlan(
      id: 'sample-sunday',
      title: 'Sunday Gathering',
      modifiedAt: now,
      items: const [
        ServiceEntry(
          id: 'sample-entry-1',
          contentId: 'sample-welcome',
          label: 'Welcome',
        ),
        ServiceEntry(
          id: 'sample-entry-2',
          contentId: 'sample-amazing-grace',
          label: 'Opening hymn',
        ),
        ServiceEntry(
          id: 'sample-entry-3',
          contentId: 'sample-gathering',
          label: 'Gathering prayer',
        ),
        ServiceEntry(
          id: 'sample-entry-4',
          contentId: 'sample-psalm',
          label: 'Reading',
        ),
        ServiceEntry(
          id: 'sample-entry-5',
          contentId: 'sample-response',
          label: 'Thanksgiving',
        ),
      ],
    ),
  );
}
