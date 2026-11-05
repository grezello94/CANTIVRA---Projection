import 'package:characters/characters.dart';
import 'package:flutter/painting.dart';

import '../domain/models.dart';

const canvasSize = Size(1920, 1080);

class LayoutCancelled implements Exception {
  const LayoutCancelled();
}

class PresentationSlide {
  const PresentationSlide({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.label,
    required this.text,
    required this.theme,
    this.sourceStart,
    this.sourceEnd,
  });

  final String id;
  final String sourceId;
  final String title;
  final String label;
  final String text;
  final PresentationTheme theme;
  final int? sourceStart;
  final int? sourceEnd;

  Map<String, Object?> toMap() => {
    'id': id,
    'sourceId': sourceId,
    'title': title,
    'label': label,
    'text': text,
    'theme': theme.toMap(),
    'sourceStart': sourceStart,
    'sourceEnd': sourceEnd,
  };

  factory PresentationSlide.fromMap(Map<String, Object?> map) =>
      PresentationSlide(
        id: map['id']! as String,
        sourceId: map['sourceId']! as String,
        title: map['title']! as String,
        label: map['label']! as String,
        text: map['text']! as String,
        theme: PresentationTheme.fromMap(
          Map<String, Object?>.from(map['theme']! as Map),
        ),
        sourceStart: map['sourceStart'] as int?,
        sourceEnd: map['sourceEnd'] as int?,
      );
}

/// Measurement and output share typography, spacing, direction and canvas size.
class SlideLayout {
  static TextStyle style(PresentationTheme theme) => TextStyle(
    fontFamily: theme.fontFamily,
    fontSize: theme.fontSize,
    height: theme.lineHeight,
    color: Color(theme.textColor),
    fontWeight: FontWeight.w400,
  );

  static TextAlign alignment(PresentationTheme theme) =>
      switch (theme.alignment) {
        'left' => TextAlign.left,
        'right' => TextAlign.right,
        _ => TextAlign.center,
      };

  static Alignment verticalAlignment(PresentationTheme theme) =>
      switch (theme.verticalAlignment) {
        'top' => Alignment.topCenter,
        'bottom' => Alignment.bottomCenter,
        _ => Alignment.center,
      };

  /// First strong character sets direction unless explicitly overridden.
  static TextDirection direction(String text, PresentationTheme theme) {
    if (theme.textDirection == 'rtl') return TextDirection.rtl;
    if (theme.textDirection == 'ltr') return TextDirection.ltr;
    final letter = RegExp(r'\p{L}', unicode: true);
    for (final rune in text.runes) {
      if (!letter.hasMatch(String.fromCharCode(rune))) continue;
      if ((rune >= 0x590 && rune <= 0x8ff) ||
          (rune >= 0xfb1d && rune <= 0xfdff) ||
          (rune >= 0xfe70 && rune <= 0xfefc) ||
          (rune >= 0x10800 && rune <= 0x10fff) ||
          (rune >= 0x1e800 && rune <= 0x1eeff)) {
        return TextDirection.rtl;
      }
      return TextDirection.ltr;
    }
    return TextDirection.ltr;
  }

  static List<String> paragraphs(String text) =>
      text.split(RegExp(r'(?:\r?\n[ \t]*){2,}'));

  static bool fits(String text, PresentationTheme theme) {
    validateTheme(theme);
    final maxWidth = canvasSize.width * (1 - 2 * theme.safeMargin);
    final parts = paragraphs(text);
    var height = theme.paragraphSpacing * (parts.length - 1);
    var fitsWidth = true;
    for (final paragraph in parts) {
      final painter = TextPainter(
        text: TextSpan(text: paragraph, style: style(theme)),
        textDirection: direction(paragraph, theme),
        textAlign: alignment(theme),
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: maxWidth);
      height += painter.height;
      fitsWidth =
          fitsWidth &&
          painter.computeLineMetrics().every(
            (line) => line.width <= maxWidth + .1,
          );
      painter.dispose();
    }
    return fitsWidth &&
        height <= canvasSize.height * (1 - 2 * theme.safeMargin) + .1;
  }

  static void validateTheme(PresentationTheme theme) {
    if (!theme.fontSize.isFinite ||
        theme.fontSize < 32 ||
        theme.fontSize > 140 ||
        !theme.safeMargin.isFinite ||
        theme.safeMargin < .03 ||
        theme.safeMargin > .2 ||
        !theme.lineHeight.isFinite ||
        theme.lineHeight < 1 ||
        theme.lineHeight > 2 ||
        !theme.paragraphSpacing.isFinite ||
        theme.paragraphSpacing < 0 ||
        theme.paragraphSpacing > 80 ||
        !{'left', 'center', 'right'}.contains(theme.alignment) ||
        !{'top', 'center', 'bottom'}.contains(theme.verticalAlignment) ||
        !{'auto', 'ltr', 'rtl'}.contains(theme.textDirection)) {
      throw const FormatException(
        'Font, spacing, alignment or safe margins are outside supported bounds.',
      );
    }
  }

  static List<PresentationSlide> compile(
    ContentItem item,
    PresentationTheme theme,
  ) {
    final slides = <PresentationSlide>[];
    for (final group in _groups(item, theme)) {
      _appendSlides(slides, item, theme, group, _split(group, theme).toList());
    }
    return List.unmodifiable(slides);
  }

  /// Font shaping requires Flutter's UI isolate. Prepare one bounded page at a
  /// time, yielding between pages so editing and emergency controls can run.
  /// Cancellation discards the whole candidate; no partial deck is published.
  static Future<List<PresentationSlide>> compileAsync(
    ContentItem item,
    PresentationTheme theme, {
    bool Function()? isCancelled,
  }) async {
    void checkCancelled() {
      if (isCancelled?.call() == true) throw const LayoutCancelled();
    }

    checkCancelled();
    await Future<void>.delayed(Duration.zero);
    checkCancelled();
    final groups = _groups(item, theme);
    final slides = <PresentationSlide>[];
    await Future<void>.delayed(Duration.zero);
    for (final group in groups) {
      checkCancelled();
      final chunks = <_MappedText>[];
      for (final chunk in _split(group, theme)) {
        checkCancelled();
        chunks.add(chunk);
        await Future<void>.delayed(Duration.zero);
        checkCancelled();
      }
      _appendSlides(slides, item, theme, group, chunks);
    }
    checkCancelled();
    return List.unmodifiable(slides);
  }

  static List<_MappedText> _groups(ContentItem item, PresentationTheme theme) {
    validateTheme(theme);
    if (item.sourceText.length > 50000) {
      throw const FormatException(
        'Items support up to 50,000 characters. Split this content into separate items.',
      );
    }
    final structure = item.structure?.matches(item.sourceText) == true
        ? item.structure!
        : ContentStructure.fromSource(item.sourceText);
    final groups = <List<_MappedText>>[];
    for (final section in structure.sections) {
      final cuts = structure.splitOffsets
          .where((offset) => offset > section.start && offset < section.end)
          .toList();
      final boundaries = [section.start, ...cuts, section.end];
      for (var index = 0; index < boundaries.length - 1; index++) {
        final start = boundaries[index];
        final end = boundaries[index + 1];
        final text = item.sourceText.substring(start, end);
        final piece = _MappedText(
          text,
          List.generate(text.length + 1, (offset) => start + offset),
          section.label,
        ).trimmed();
        if (piece.text.isEmpty) continue;
        final canMerge =
            groups.isNotEmpty &&
            structure.mergedBreaks.contains(start) &&
            !structure.splitOffsets.contains(start);
        if (canMerge) {
          groups.last.add(piece);
        } else {
          groups.add([piece]);
        }
      }
    }
    return groups.map(_MappedText.joinAll).toList();
  }

  static void _appendSlides(
    List<PresentationSlide> slides,
    ContentItem item,
    PresentationTheme theme,
    _MappedText group,
    List<_MappedText> chunks,
  ) {
    final label = group.label.isEmpty
        ? 'Slide ${slides.length + 1}'
        : group.label;
    for (var index = 0; index < chunks.length; index++) {
      final chunk = chunks[index];
      slides.add(
        PresentationSlide(
          id: '${item.id}:${slides.length}',
          sourceId: item.id,
          title: item.title,
          label: chunks.length == 1
              ? label
              : '$label · ${index + 1}/${chunks.length}',
          text: chunk.text,
          theme: theme,
          sourceStart: chunk.offsets.first,
          sourceEnd: chunk.offsets.last,
        ),
      );
    }
  }

  static Iterable<_MappedText> _split(
    _MappedText value,
    PresentationTheme theme,
  ) sync* {
    var remaining = value;
    while (remaining.text.isNotEmpty) {
      final boundaries = <int>[];
      var offset = 0;
      for (final grapheme in remaining.text.characters) {
        if (grapheme.length > 256) {
          throw const FormatException(
            'A character contains too many combining marks. Remove repeated invisible marks before preparing slides.',
          );
        }
        offset += grapheme.length;
        boundaries.add(offset);
      }
      // Start with a short prefix and grow only while it fits. Large source
      // paragraphs are never sent to the font engine repeatedly for each page.
      var low = 0;
      var high = boundaries.length - 1;
      var count = 0;
      var probe = boundaries.length < 256 ? boundaries.length - 1 : 255;
      while (true) {
        if (boundaries[probe] > 16384) {
          high = probe - 1;
          break;
        }
        if (!fits(remaining.text.substring(0, boundaries[probe]), theme)) {
          high = probe - 1;
          break;
        }
        count = boundaries[probe];
        low = probe + 1;
        if (probe == boundaries.length - 1) break;
        probe = ((probe + 1) * 2 - 1).clamp(0, boundaries.length - 1);
      }
      if (count == remaining.text.length) {
        yield remaining;
        break;
      }
      while (low <= high) {
        final mid = (low + high) ~/ 2;
        if (boundaries[mid] <= 16384 &&
            fits(remaining.text.substring(0, boundaries[mid]), theme)) {
          count = boundaries[mid];
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }
      if (count >= 16384 - 256 && count < remaining.text.length) {
        throw const FormatException(
          'This section contains too many tightly packed or invisible characters. Add explicit slide breaks or remove repeated invisible characters.',
        );
      }
      if (count == 0) {
        throw const FormatException(
          'A character cannot fit inside the safe area. Choose a smaller font or reduce safe margins.',
        );
      }
      final prefix = remaining.text.substring(0, count);
      final minimum = count ~/ 2;
      var boundary = prefix.lastIndexOf('\n');
      if (boundary < minimum) {
        final sentences = RegExp(r'[.!?।。！？][\s]').allMatches(prefix).toList();
        boundary = sentences.isEmpty ? -1 : sentences.last.end;
      }
      if (boundary < minimum) boundary = prefix.lastIndexOf(RegExp(r'\s'));
      if (boundary <= 0) {
        if (RegExp(
          r'[\u2e80-\u9fff\uac00-\ud7af\u0e00-\u0eff\u1780-\u17ff]',
        ).hasMatch(prefix)) {
          final contextEnd = boundaries.firstWhere(
            (value) => value > count + 256,
            orElse: () => remaining.text.length,
          );
          final context = remaining.text.substring(0, contextEnd);
          final painter = TextPainter(
            text: TextSpan(text: context, style: style(theme)),
            textDirection: direction(remaining.text, theme),
            textAlign: alignment(theme),
            textScaler: TextScaler.noScaling,
          )..layout(maxWidth: canvasSize.width * (1 - 2 * theme.safeMargin));
          // Reuse Skia/ICU line breaking for scripts without word spaces rather
          // than assuming that every code point is a valid linguistic break.
          final line = painter.getLineBoundary(
            TextPosition(offset: count, affinity: TextAffinity.upstream),
          );
          painter.dispose();
          final lineEnd = line.end <= count ? line.end : line.start;
          boundary = boundaries.lastWhere(
            (value) => value <= (lineEnd > 0 ? lineEnd : count),
            orElse: () => count,
          );
          const forbiddenStart = '、。，．！？：；)]}」』】》〉';
          while (boundary > 0 &&
              boundary < remaining.text.length &&
              forbiddenStart.contains(
                remaining.text.substring(boundary).characters.first,
              )) {
            boundary = boundaries.lastWhere(
              (value) => value < boundary,
              orElse: () => 0,
            );
          }
        } else {
          throw const FormatException(
            'An unbroken word or link is too long for one slide. Add a manual break, shorten it, or adjust the font.',
          );
        }
      }
      if (boundary <= 0) {
        throw const FormatException(
          'Text cannot fit safely. Add a manual break or adjust the theme.',
        );
      }
      // A nearby CJK character does not make an emergency line break inside
      // a Latin word/link a legal linguistic boundary.
      final word = RegExp(r'^[\p{L}\p{N}\p{M}]+$', unicode: true);
      final unspaced = RegExp(
        r'[\u2e80-\u9fff\uac00-\ud7af\u0e00-\u0eff\u1780-\u17ff]',
      );
      while (boundary > 0 && boundary < remaining.text.length) {
        final before = remaining.text.substring(0, boundary).characters.last;
        final after = remaining.text.substring(boundary).characters.first;
        if (!word.hasMatch(before) ||
            !word.hasMatch(after) ||
            unspaced.hasMatch(before) ||
            unspaced.hasMatch(after)) {
          break;
        }
        boundary = boundaries.lastWhere(
          (value) => value < boundary,
          orElse: () => 0,
        );
      }
      if (boundary == 0) {
        throw const FormatException(
          'An unbroken word or link is too long for one slide. Add a break between words or adjust the font.',
        );
      }
      yield remaining.slice(0, boundary).trimmed();
      remaining = remaining.slice(boundary, remaining.text.length).trimmed();
    }
  }
}

/// Headings can be omitted on screen, so offsets map explicitly to source.
class _MappedText {
  _MappedText(this.text, this.offsets, this.label);
  final String text;
  final List<int> offsets;
  final String label;

  _MappedText slice(int start, int end) => _MappedText(
    text.substring(start, end),
    offsets.sublist(start, end + 1),
    label,
  );

  _MappedText trimmed() {
    final leading = text.length - text.trimLeft().length;
    final end = text.trimRight().length;
    return slice(leading, end < leading ? leading : end);
  }

  static _MappedText joinAll(List<_MappedText> pieces) {
    if (pieces.length == 1) return pieces.single;
    final text = StringBuffer();
    final offsets = <int>[];
    var label = '';
    for (final piece in pieces) {
      if (offsets.isNotEmpty) {
        text.write('\n\n');
        offsets.add(piece.offsets.first);
      }
      text.write(piece.text);
      offsets.addAll(piece.offsets);
      if (label.isEmpty) label = piece.label;
    }
    return _MappedText(text.toString(), offsets, label);
  }
}
