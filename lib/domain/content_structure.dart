import 'package:characters/characters.dart';

import 'models.dart' show ContentKind;

enum SectionKind { verse, chorus, refrain, bridge, speaker, paragraph, custom }

/// A view onto the exact, unmodified source, with optional presentation labels.
/// Offsets use Dart/Flutter UTF-16 text positions, never normalized text offsets.
class ContentSection {
  const ContentSection({
    required this.id,
    required this.kind,
    required this.label,
    required this.text,
    required this.start,
    required this.end,
  });

  final String id;
  final SectionKind kind;
  final String label;
  final String text;
  final int start;
  final int end;

  ContentSection copyWith({SectionKind? kind, String? label}) => ContentSection(
    id: id,
    kind: kind ?? this.kind,
    label: label ?? this.label,
    text: text,
    start: start,
    end: end,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'kind': kind.name,
    'label': label,
    'text': text,
    'start': start,
    'end': end,
  };

  factory ContentSection.fromMap(Map<String, Object?> map) => ContentSection(
    id: map['id']! as String,
    kind: SectionKind.values.byName(map['kind']! as String),
    label: map['label']! as String,
    text: map['text']! as String,
    start: map['start']! as int,
    end: map['end']! as int,
  );
}

/// Structure is valid only for its exact source. Editing source text invalidates
/// the proposal; offsets are never guessed or silently reapplied to new text.
class ContentStructure {
  ContentStructure({
    required this.originalSource,
    required List<ContentSection> sections,
    List<int> splitOffsets = const [],
    List<int> mergedBreaks = const [],
  }) : sections = List.unmodifiable(sections),
       splitOffsets = List.unmodifiable(splitOffsets.toSet().toList()..sort()),
       mergedBreaks = List.unmodifiable(mergedBreaks.toSet().toList()..sort()) {
    _validate();
  }

  static const version = 1;
  final String originalSource;
  final List<ContentSection> sections;
  final List<int> splitOffsets;
  final List<int> mergedBreaks;

  bool matches(String source) => originalSource == source;

  ContentStructure copyWith({
    List<ContentSection>? sections,
    List<int>? splitOffsets,
    List<int>? mergedBreaks,
  }) => ContentStructure(
    originalSource: originalSource,
    sections: sections ?? this.sections,
    splitOffsets: splitOffsets ?? this.splitOffsets,
    mergedBreaks: mergedBreaks ?? this.mergedBreaks,
  );

  ContentStructure withSplit(int offset) => copyWith(
    splitOffsets: [...splitOffsets, offset],
    mergedBreaks: mergedBreaks.where((value) => value != offset).toList(),
  );

  ContentStructure withoutSplit(int offset) => copyWith(
    splitOffsets: splitOffsets.where((value) => value != offset).toList(),
  );

  ContentStructure withMergedBreak(int offset) => copyWith(
    mergedBreaks: [...mergedBreaks, offset],
    splitOffsets: splitOffsets
        .where(
          (value) =>
              value != offset &&
              !(value < offset &&
                  originalSource.substring(value, offset).trim().isEmpty),
        )
        .toList(),
  );

  ContentStructure withoutMergedBreak(int offset) => copyWith(
    mergedBreaks: mergedBreaks.where((value) => value != offset).toList(),
  );

  void _validate() {
    var end = 0;
    final ids = <String>{};
    for (final section in sections) {
      if (section.start < end ||
          section.end <= section.start ||
          section.end > originalSource.length ||
          !ids.add(section.id) ||
          section.text !=
              originalSource.substring(section.start, section.end)) {
        throw const FormatException(
          'Content sections do not match their source.',
        );
      }
      if (!_onlyMarkers(originalSource.substring(end, section.start))) {
        throw const FormatException(
          'Content structure must preserve all source text.',
        );
      }
      end = section.end;
    }
    if (!_onlyMarkers(originalSource.substring(end))) {
      throw const FormatException(
        'Content structure must preserve all source text.',
      );
    }
    final boundaries = <int>{0};
    var offset = 0;
    for (final grapheme in originalSource.characters) {
      offset += grapheme.length;
      boundaries.add(offset);
    }
    for (final value in [...splitOffsets, ...mergedBreaks]) {
      if (value <= 0 ||
          value >= originalSource.length ||
          !boundaries.contains(value)) {
        throw const FormatException(
          'Slide breaks must be inside text at a complete character boundary.',
        );
      }
    }
    for (final section in sections) {
      if (!boundaries.contains(section.start) ||
          !boundaries.contains(section.end)) {
        throw const FormatException(
          'A section cuts through a complete character.',
        );
      }
    }
    for (final value in splitOffsets) {
      final before = originalSource.substring(0, value).characters.last;
      final after = originalSource.substring(value).characters.first;
      final word = RegExp(r'^[\p{L}\p{N}\p{M}]+$', unicode: true);
      final unspaced = RegExp(
        r'[\u2e80-\u9fff\uac00-\ud7af\u0e00-\u0eff\u1780-\u17ff]',
      );
      if (word.hasMatch(before) &&
          word.hasMatch(after) &&
          !unspaced.hasMatch(before) &&
          !unspaced.hasMatch(after)) {
        throw const FormatException(
          'Place a manual split between complete words.',
        );
      }
    }
  }

  Map<String, Object?> toMap() => {
    'version': version,
    'originalSource': originalSource,
    'sections': sections.map((section) => section.toMap()).toList(),
    'splitOffsets': splitOffsets,
    'mergedBreaks': mergedBreaks,
  };

  factory ContentStructure.fromMap(Map<String, Object?> map) {
    if (map['version'] != version) {
      throw const FormatException('Unsupported content structure version.');
    }
    return ContentStructure(
      originalSource: map['originalSource']! as String,
      sections: (map['sections']! as List)
          .map(
            (value) =>
                ContentSection.fromMap(Map<String, Object?>.from(value as Map)),
          )
          .toList(),
      splitOffsets: (map['splitOffsets'] as List?)?.cast<int>() ?? const [],
      mergedBreaks: (map['mergedBreaks'] as List?)?.cast<int>() ?? const [],
    );
  }

  /// Existing bracket headings, blank lines and `---` remain deterministic even
  /// before an operator chooses to accept a recognition proposal.
  factory ContentStructure.fromSource(String source) =>
      ContentStructure(originalSource: source, sections: _parse(source, false));
}

bool _onlyMarkers(String value) {
  final remainder = value
      .replaceAll(RegExp(r'\[[^\]\r\n]+\]'), '')
      .replaceAll(RegExp(r'^[ \t]*---[ \t]*\r?$', multiLine: true), '')
      .replaceAll(
        RegExp(
          r'^[ \t]*(?:verse(?:[ \t]+\d+)?|chorus|refrain|bridge|celebrant|priest|leader|all|congregation|people|reader|deacon|assembly)[ \t]*:?[ \t]*\r?$',
          multiLine: true,
          caseSensitive: false,
        ),
        '',
      );
  return remainder.trim().isEmpty;
}

class ContentRecognition {
  ContentRecognition({
    required this.structure,
    required this.detectedKind,
    required this.confidence,
    required List<String> reasons,
  }) : reasons = List.unmodifiable(reasons);

  final ContentStructure structure;
  final ContentKind detectedKind;
  final double confidence;
  final List<String> reasons;
  bool get needsConfirmation => confidence < .8;

  ContentRecognition copyWith({
    ContentStructure? structure,
    ContentKind? detectedKind,
  }) => ContentRecognition(
    structure: structure ?? this.structure,
    detectedKind: detectedKind ?? this.detectedKind,
    confidence: confidence,
    reasons: reasons,
  );
}

/// Local rules suggest structure without applying or rewriting any source text.
class ContentRecognizer {
  static ContentRecognition suggest(String source, ContentKind kind) {
    final sections = _parse(source, true);
    final reasons = <String>[];
    var detected = kind;
    var confidence = .4;
    if (sections.any(
      (section) => {
        SectionKind.verse,
        SectionKind.chorus,
        SectionKind.refrain,
        SectionKind.bridge,
      }.contains(section.kind),
    )) {
      detected = ContentKind.hymn;
      confidence = .94;
      reasons.add(
        'Explicit verse, chorus, refrain or bridge labels were found.',
      );
    } else if (sections.any((section) => section.kind == SectionKind.speaker)) {
      detected = ContentKind.response;
      confidence = .9;
      reasons.add('Speaker and congregation labels were found.');
    } else if (RegExp(
      r'\b(?:Genesis|Exodus|Psalm|Isaiah|Matthew|Mark|Luke|John|Romans|Corinthians|Revelation)\s+\d+(?::\d+)?',
      caseSensitive: false,
    ).hasMatch(source)) {
      detected = ContentKind.reading;
      confidence = .85;
      reasons.add('A scripture reference was found; paragraphs are preserved.');
    } else if (RegExp(
      r'\b(?:amen|almighty|our father|let us pray)\b',
      caseSensitive: false,
    ).hasMatch(source)) {
      detected = ContentKind.prayer;
      confidence = .68;
      reasons.add('Prayer vocabulary was found; confirm the suggested type.');
    } else {
      reasons.add(
        'No reliable structural labels were found; review paragraphs.',
      );
    }
    final seen = <String>{};
    var repeated = false;
    final repeatedSections = sections.map((section) {
      final key = section.text
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .toLowerCase();
      if (key.length >= 8 &&
          !seen.add(key) &&
          section.kind == SectionKind.paragraph) {
        repeated = true;
        return section.copyWith(
          kind: SectionKind.refrain,
          label: 'Repeated refrain',
        );
      }
      return section;
    }).toList();
    if (repeated) {
      reasons.add(
        'Repeated text was marked as a possible refrain without adding repeats.',
      );
      if (confidence < .7) confidence = .6;
    }
    return ContentRecognition(
      structure: ContentStructure(
        originalSource: source,
        sections: repeatedSections,
      ),
      detectedKind: detected,
      confidence: confidence,
      reasons: reasons,
    );
  }
}

List<ContentSection> _parse(String source, bool recognize) {
  final output = <ContentSection>[];
  final separator = RegExp(
    r'(?:^|\r?\n)[ \t]*---[ \t]*(?=\r?\n|$)|(?:\r?\n[ \t]*){2,}',
  );
  var start = 0;
  for (final match in separator.allMatches(source)) {
    _parseBlock(source, start, match.start, recognize, output);
    start = match.end;
  }
  _parseBlock(source, start, source.length, recognize, output);
  return output;
}

void _parseBlock(
  String source,
  int start,
  int end,
  bool recognize,
  List<ContentSection> output,
) {
  while (start < end && source.substring(start, start + 1).trim().isEmpty) {
    start++;
  }
  while (end > start && source.substring(end - 1, end).trim().isEmpty) {
    end--;
  }
  if (start == end || source.substring(start, end).trim() == '---') return;
  var label = '';
  var kind = SectionKind.paragraph;
  final content = source.substring(start, end);
  final heading = RegExp(
    r'^\[([^\]\r\n]+)\][ \t]*(?:\r?\n)?',
  ).firstMatch(content);
  if (heading != null && !recognize) {
    label = heading.group(1)!;
    kind = _kindForLabel(label);
    start += heading.end;
  } else if (recognize) {
    // Find line headings and speaker prefixes, including multiple speakers in
    // one paragraph. Each resulting range still points into the original text.
    final labels = RegExp(
      r'^(\[?((?:verse(?:[ \t]+\d+)?|chorus|refrain|bridge|celebrant|priest|leader|all|congregation|people|reader|deacon|assembly))\]?)[ \t]*(?::[ \t]*|(?=\r?$))',
      caseSensitive: false,
      multiLine: true,
    ).allMatches(content).toList();
    if (labels.isNotEmpty) {
      if (labels.first.start > 0) {
        _parseBlock(source, start, start + labels.first.start, false, output);
      }
      for (var index = 0; index < labels.length; index++) {
        final match = labels[index];
        final rangeEnd = index + 1 < labels.length
            ? start + labels[index + 1].start
            : end;
        var textStart = start + match.end;
        while (textStart < rangeEnd &&
            source.substring(textStart, textStart + 1).trim().isEmpty) {
          textStart++;
        }
        var textEnd = rangeEnd;
        while (textEnd > textStart &&
            source.substring(textEnd - 1, textEnd).trim().isEmpty) {
          textEnd--;
        }
        if (textStart < textEnd) {
          final sectionLabel = match.group(2)!;
          output.add(
            ContentSection(
              id: 'section-$textStart',
              kind: _kindForLabel(sectionLabel),
              label: sectionLabel,
              text: source.substring(textStart, textEnd),
              start: textStart,
              end: textEnd,
            ),
          );
        }
      }
      return;
    }
  }
  if (recognize && heading != null) {
    label = heading.group(1)!;
    kind = _kindForLabel(label);
    start += heading.end;
  }
  while (start < end && source.substring(start, start + 1).trim().isEmpty) {
    start++;
  }
  if (start < end) {
    output.add(
      ContentSection(
        id: 'section-$start',
        kind: kind,
        label: label,
        text: source.substring(start, end),
        start: start,
        end: end,
      ),
    );
  }
}

SectionKind _kindForLabel(String label) {
  final normalized = label.toLowerCase().trim();
  if (normalized.startsWith('verse')) return SectionKind.verse;
  if (normalized == 'chorus') return SectionKind.chorus;
  if (normalized == 'refrain') return SectionKind.refrain;
  if (normalized == 'bridge') return SectionKind.bridge;
  if ({
    'celebrant',
    'priest',
    'leader',
    'all',
    'congregation',
    'people',
    'reader',
    'deacon',
    'assembly',
  }.contains(normalized)) {
    return SectionKind.speaker;
  }
  return SectionKind.custom;
}
