import 'content_structure.dart';

export 'content_structure.dart';

/// The locally supported kinds of church content. These do not prescribe a
/// denomination or a fixed service order.
enum ContentKind { hymn, prayer, reading, response, announcement, custom }

class ContentItem {
  ContentItem({
    required this.id,
    required this.title,
    required this.kind,
    required this.sourceText,
    this.language = 'English',
    List<String> tags = const [],
    this.favorite = false,
    this.structure,
    required this.modifiedAt,
  }) : tags = List.unmodifiable(tags);

  final String id;
  final String title;
  final ContentKind kind;
  final String sourceText;
  final String language;
  final List<String> tags;
  final bool favorite;
  final ContentStructure? structure;
  final DateTime modifiedAt;

  ContentItem copyWith({
    String? id,
    String? title,
    ContentKind? kind,
    String? sourceText,
    String? language,
    List<String>? tags,
    bool? favorite,
    ContentStructure? structure,
    bool resetStructure = false,
    DateTime? modifiedAt,
  }) => ContentItem(
    id: id ?? this.id,
    title: title ?? this.title,
    kind: kind ?? this.kind,
    sourceText: sourceText ?? this.sourceText,
    language: language ?? this.language,
    tags: tags ?? this.tags,
    favorite: favorite ?? this.favorite,
    structure: resetStructure ? null : structure ?? this.structure,
    modifiedAt: modifiedAt ?? this.modifiedAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'kind': kind.name,
    'sourceText': sourceText,
    'language': language,
    'tags': tags,
    'favorite': favorite,
    'structure': structure?.toMap(),
    'modifiedAt': modifiedAt.toUtc().toIso8601String(),
  };

  factory ContentItem.fromMap(Map<String, Object?> map) => ContentItem(
    id: map['id']! as String,
    title: map['title']! as String,
    kind: ContentKind.values.byName(map['kind']! as String),
    sourceText: map['sourceText']! as String,
    language: map['language'] as String? ?? 'English',
    tags: (map['tags'] as List?)?.cast<String>() ?? const [],
    favorite: map['favorite'] as bool? ?? false,
    structure: map['structure'] == null
        ? null
        : ContentStructure.fromMap(
            Map<String, Object?>.from(map['structure']! as Map),
          ),
    modifiedAt: DateTime.parse(map['modifiedAt']! as String),
  );
}

class ServiceEntry {
  const ServiceEntry({
    required this.id,
    required this.contentId,
    required this.label,
  });

  final String id;
  final String contentId;
  final String label;

  ServiceEntry copyWith({String? id, String? contentId, String? label}) =>
      ServiceEntry(
        id: id ?? this.id,
        contentId: contentId ?? this.contentId,
        label: label ?? this.label,
      );

  Map<String, Object?> toMap() => {
    'id': id,
    'contentId': contentId,
    'label': label,
  };

  factory ServiceEntry.fromMap(Map<String, Object?> map) => ServiceEntry(
    id: map['id']! as String,
    contentId: map['contentId']! as String,
    label: map['label']! as String,
  );
}

class ServicePlan {
  ServicePlan({
    required this.id,
    required this.title,
    List<ServiceEntry> items = const [],
    required this.modifiedAt,
  }) : items = List.unmodifiable(items);

  final String id;
  final String title;
  final List<ServiceEntry> items;
  final DateTime modifiedAt;

  ServicePlan copyWith({
    String? id,
    String? title,
    List<ServiceEntry>? items,
    DateTime? modifiedAt,
  }) => ServicePlan(
    id: id ?? this.id,
    title: title ?? this.title,
    items: items ?? this.items,
    modifiedAt: modifiedAt ?? this.modifiedAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'items': items.map((entry) => entry.toMap()).toList(),
    'modifiedAt': modifiedAt.toUtc().toIso8601String(),
  };

  factory ServicePlan.fromMap(Map<String, Object?> map) => ServicePlan(
    id: map['id']! as String,
    title: map['title']! as String,
    items: (map['items'] as List)
        .map(
          (entry) =>
              ServiceEntry.fromMap(Map<String, Object?>.from(entry as Map)),
        )
        .toList(),
    modifiedAt: DateTime.parse(map['modifiedAt']! as String),
  );
}

/// Rendered in canonical 1920 × 1080 coordinates and scaled proportionally.
class PresentationTheme {
  const PresentationTheme({
    this.id = 'midnight',
    this.name = 'Midnight',
    this.backgroundColor = 0xff10192a,
    this.textColor = 0xfffaf8f1,
    this.fontSize = 68,
    this.fontFamily = 'Georgia',
    this.safeMargin = .08,
    this.alignment = 'center',
    this.verticalAlignment = 'center',
    this.lineHeight = 1.35,
    this.paragraphSpacing = 24,
    this.textDirection = 'auto',
  });

  final String id;
  final String name;
  final int backgroundColor;
  final int textColor;
  final double fontSize;
  final String fontFamily;
  final double safeMargin;
  final String alignment;
  final String verticalAlignment;
  final double lineHeight;
  final double paragraphSpacing;
  final String textDirection;

  PresentationTheme copyWith({
    String? id,
    String? name,
    int? backgroundColor,
    int? textColor,
    double? fontSize,
    String? fontFamily,
    double? safeMargin,
    String? alignment,
    String? verticalAlignment,
    double? lineHeight,
    double? paragraphSpacing,
    String? textDirection,
  }) => PresentationTheme(
    id: id ?? this.id,
    name: name ?? this.name,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    textColor: textColor ?? this.textColor,
    fontSize: fontSize ?? this.fontSize,
    fontFamily: fontFamily ?? this.fontFamily,
    safeMargin: safeMargin ?? this.safeMargin,
    alignment: alignment ?? this.alignment,
    verticalAlignment: verticalAlignment ?? this.verticalAlignment,
    lineHeight: lineHeight ?? this.lineHeight,
    paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
    textDirection: textDirection ?? this.textDirection,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'backgroundColor': backgroundColor,
    'textColor': textColor,
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'safeMargin': safeMargin,
    'alignment': alignment,
    'verticalAlignment': verticalAlignment,
    'lineHeight': lineHeight,
    'paragraphSpacing': paragraphSpacing,
    'textDirection': textDirection,
  };

  factory PresentationTheme.fromMap(Map<String, Object?> map) =>
      PresentationTheme(
        id: map['id'] as String? ?? 'midnight',
        name: map['name'] as String? ?? 'Midnight',
        backgroundColor: map['backgroundColor'] as int? ?? 0xff10192a,
        textColor: map['textColor'] as int? ?? 0xfffaf8f1,
        fontSize: (map['fontSize'] as num?)?.toDouble() ?? 68,
        fontFamily: map['fontFamily'] as String? ?? 'Georgia',
        safeMargin: (map['safeMargin'] as num?)?.toDouble() ?? .08,
        alignment: map['alignment'] as String? ?? 'center',
        verticalAlignment: map['verticalAlignment'] as String? ?? 'center',
        lineHeight: (map['lineHeight'] as num?)?.toDouble() ?? 1.35,
        paragraphSpacing: (map['paragraphSpacing'] as num?)?.toDouble() ?? 24,
        textDirection: map['textDirection'] as String? ?? 'auto',
      );
}
