import 'dart:convert';
import 'dart:io';
import 'dart:math';

const rendererRoleArgument = '--cantivra-output';
const rendererTokenEnvironment = 'CANTIVRA_RENDERER_TOKEN';

/// The transport framing remains protocol 2. Rendering semantics advance
/// separately so an older process cannot silently ignore a newer layout.
const renderSchemaVersion = 2;

String sessionSecret([int bytes = 32]) {
  final random = Random.secure();
  return List.generate(
    bytes,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

bool secretsMatch(String first, String second) {
  var difference = first.length ^ second.length;
  for (var i = 0; i < first.length; i++) {
    difference |=
        first.codeUnitAt(i) ^ (i < second.length ? second.codeUnitAt(i) : 0);
  }
  return difference == 0;
}

class RendererLaunch {
  const RendererLaunch({
    required this.sessionPath,
    required this.sessionId,
    required this.token,
  });
  final String sessionPath;
  final String sessionId;
  final String token;

  static RendererLaunch? parse(
    List<String> arguments, {
    Map<String, String>? environment,
  }) {
    if (!arguments.contains(rendererRoleArgument)) return null;
    String option(String name) {
      final matches = arguments.where((arg) => arg.startsWith('$name='));
      if (matches.length != 1) {
        throw FormatException('Missing or duplicate renderer option $name.');
      }
      return matches.single.substring(name.length + 1);
    }

    final path = option('--cantivra-session-file');
    final session = option('--cantivra-session');
    final token =
        (environment ?? Platform.environment)[rendererTokenEnvironment] ?? '';
    if (path.isEmpty ||
        path.length > 4096 ||
        !File(path).isAbsolute ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(session) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) {
      throw const FormatException('Invalid renderer launch configuration.');
    }
    return RendererLaunch(sessionPath: path, sessionId: session, token: token);
  }
}

/// The control endpoint belongs to the renderer, so it survives an operator
/// crash. This private local file is a capability, never library/user content.
class RendererSession {
  const RendererSession({
    required this.sessionId,
    required this.token,
    required this.port,
    required this.processId,
    required this.createdAt,
  });
  final String sessionId;
  final String token;
  final int port;
  final int processId;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
    'protocol': 2,
    'session': sessionId,
    'token': token,
    'port': port,
    'pid': processId,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory RendererSession.fromMap(Map<String, Object?> map) {
    final session = map['session'];
    final token = map['token'];
    final port = map['port'];
    final processId = map['pid'];
    if (map['protocol'] != 2 ||
        session is! String ||
        token is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(session) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(token) ||
        port is! int ||
        port < 1 ||
        port > 65535 ||
        processId is! int ||
        processId < 1) {
      throw const FormatException('Invalid renderer session descriptor.');
    }
    return RendererSession(
      sessionId: session,
      token: token,
      port: port,
      processId: processId,
      createdAt: DateTime.parse(map['createdAt']! as String),
    );
  }

  static Future<RendererSession?> read(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    if (await file.length() > 16384) {
      throw const FormatException('Renderer session descriptor is too large.');
    }
    return RendererSession.fromMap(
      Map<String, Object?>.from(jsonDecode(await file.readAsString()) as Map),
    );
  }

  Future<void> write(String path) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temporary = File('$path.$sessionId.tmp');
    await temporary.writeAsString('', flush: true);
    try {
      if (Platform.isMacOS || Platform.isLinux) {
        final result = await Process.run('/bin/chmod', ['600', temporary.path]);
        if (result.exitCode != 0) {
          throw const FileSystemException(
            'Cannot protect renderer session file.',
          );
        }
      }
      await temporary.writeAsString(jsonEncode(toMap()), flush: true);
      await temporary.rename(path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> removeIfCurrent(String path) async {
    try {
      if ((await read(path))?.sessionId == sessionId) await File(path).delete();
    } on FileSystemException {
      /* Already removed or unavailable. Never touch other sessions. */
    }
  }
}
