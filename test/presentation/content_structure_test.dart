import 'package:cantivra/domain/models.dart';
import 'package:cantivra/presentation/slides.dart';
import 'package:characters/characters.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

ContentItem item(String source, {ContentStructure? structure}) => ContentItem(
  id: 'fixture',
  title: 'Fixture',
  kind: ContentKind.custom,
  sourceText: source,
  structure: structure,
  modifiedAt: DateTime.utc(2026, 11, 5),
);

String normalized(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'CJK context never permits clipping through an oversized Latin word',
    () {
      expect(
        () => SlideLayout.compile(
          item('中${List.filled(3000, 'word').join()}'),
          const PresentationTheme(),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'recognition finds continuous hymn labels without rewriting CRLF source',
    () {
      const source =
          'Verse 1\r\nSing in peace.\r\nChorus\r\nWe give thanks.\r\nBridge:\r\nAmen.';
      final result = ContentRecognizer.suggest(source, ContentKind.custom);
      expect(result.detectedKind, ContentKind.hymn);
      expect(result.confidence, greaterThan(.8));
      expect(result.structure.sections.map((section) => section.kind), [
        SectionKind.verse,
        SectionKind.chorus,
        SectionKind.bridge,
      ]);
      expect(result.structure.sections.map((section) => section.text), [
        'Sing in peace.',
        'We give thanks.',
        'Amen.',
      ]);
      expect(result.structure.originalSource, source);
      for (final section in result.structure.sections) {
        expect(source.substring(section.start, section.end), section.text);
      }
    },
  );

  test('recognition is a proposal and does not change unaccepted content', () {
    const source = 'Verse 1\nSing in peace.\nChorus\nWe give thanks.';
    final content = item(source);
    final before = SlideLayout.compile(content, const PresentationTheme());
    final suggestion = ContentRecognizer.suggest(source, content.kind);
    expect(content.structure, isNull);
    expect(before.single.text, source);
    final accepted = SlideLayout.compile(
      content.copyWith(structure: suggestion.structure),
      const PresentationTheme(),
    );
    expect(accepted.map((slide) => slide.text), [
      'Sing in peace.',
      'We give thanks.',
    ]);
    expect(content.sourceText, source);
  });

  test(
    'speaker prefixes become explicit sections and preserve original text',
    () {
      const source =
          'Leader: Peace be with you.\nAll: And with your spirit.\nPriest: Let us pray.';
      final result = ContentRecognizer.suggest(source, ContentKind.prayer);
      expect(result.detectedKind, ContentKind.response);
      expect(result.structure.sections.map((section) => section.label), [
        'Leader',
        'All',
        'Priest',
      ]);
      expect(
        result.structure.sections.every(
          (section) => section.kind == SectionKind.speaker,
        ),
        isTrue,
      );
      expect(result.structure.sections.map((section) => section.text), [
        'Peace be with you.',
        'And with your spirit.',
        'Let us pray.',
      ]);
      expect(result.structure.originalSource, source);
    },
  );

  test(
    'scripture references remain visible and low confidence prompts review',
    () {
      const source =
          'John 3:16\nFor God so loved the world.\n\nA second paragraph.';
      final reading = ContentRecognizer.suggest(source, ContentKind.custom);
      expect(reading.detectedKind, ContentKind.reading);
      expect(reading.structure.sections.first.text, startsWith('John 3:16'));
      expect(reading.structure.sections.length, 2);
      final prayer = ContentRecognizer.suggest(
        'Let us pray. Amen.',
        ContentKind.custom,
      );
      expect(prayer.detectedKind, ContentKind.prayer);
      expect(prayer.needsConfirmation, isTrue);
      final plain = ContentRecognizer.suggest(
        'A meeting begins on Sunday.',
        ContentKind.announcement,
      );
      expect(plain.needsConfirmation, isTrue);
      expect(plain.detectedKind, ContentKind.announcement);
    },
  );

  test(
    'repeated text is marked without silently inserting or removing repeats',
    () {
      const source =
          'We give you thanks.\n\nA verse of praise.\n\nWe give you thanks.';
      final result = ContentRecognizer.suggest(source, ContentKind.hymn);
      expect(result.structure.sections.length, 3);
      expect(result.structure.sections.last.kind, SectionKind.refrain);
      expect(
        result.structure.sections.last.text,
        result.structure.sections.first.text,
      );
      expect(result.needsConfirmation, isTrue);
    },
  );

  test('operator section overrides round trip and lists remain immutable', () {
    const source = '[Verse 1]\nPraise.\n\n[Chorus]\nThanks.';
    final original = ContentStructure.fromSource(source);
    final structure = original
        .copyWith(
          sections: [
            original.sections.first.copyWith(
              kind: SectionKind.custom,
              label: 'Opening',
            ),
            original.sections.last,
          ],
        )
        .withSplit(source.indexOf('Thanks'));
    final restored = ContentItem.fromMap(
      item(source, structure: structure).toMap(),
    );
    expect(restored.toMap(), item(source, structure: structure).toMap());
    expect(restored.structure!.sections.first.label, 'Opening');
    expect(restored.structure!.sections.first.kind, SectionKind.custom);
    expect(() => restored.structure!.sections.clear(), throwsUnsupportedError);
    expect(
      () => restored.structure!.splitOffsets.add(3),
      throwsUnsupportedError,
    );
    expect(restored.copyWith(resetStructure: true).structure, isNull);
  });

  test(
    'malformed structure cannot omit source, change text, or cut characters',
    () {
      expect(
        () =>
            ContentStructure(originalSource: 'Never omit this.', sections: []),
        throwsFormatException,
      );
      expect(
        () => ContentStructure(
          originalSource: 'A full sentence.',
          sections: [
            const ContentSection(
              id: 'x',
              kind: SectionKind.custom,
              label: '',
              text: 'full',
              start: 2,
              end: 6,
            ),
          ],
        ),
        throwsFormatException,
      );
      final original = ContentStructure.fromSource('A complete line.');
      final map = original.toMap()..['version'] = 999;
      expect(() => ContentStructure.fromMap(map), throwsFormatException);
      expect(
        () => ContentStructure(
          originalSource: '👍🏽',
          sections: [
            const ContentSection(
              id: 'x',
              kind: SectionKind.custom,
              label: '',
              text: '👍',
              start: 0,
              end: 2,
            ),
          ],
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'stale recognition cannot replace edited source on the next compilation',
    () {
      final old = ContentStructure.fromSource('[Verse]\nOld text.');
      final current = item('The corrected source.', structure: old);
      expect(
        SlideLayout.compile(current, const PresentationTheme()).single.text,
        'The corrected source.',
      );
      expect(current.structure!.originalSource, '[Verse]\nOld text.');
    },
  );

  test(
    'manual split and merge persist as metadata and retain exact source',
    () {
      const source = 'First complete sentence. Second complete sentence.';
      final splitOffset = source.indexOf(' Second');
      final structure = ContentStructure.fromSource(
        source,
      ).withSplit(splitOffset);
      final slides = SlideLayout.compile(
        item(source, structure: structure),
        const PresentationTheme(),
      );
      expect(slides.map((slide) => slide.text), [
        'First complete sentence.',
        'Second complete sentence.',
      ]);
      expect(slides.last.sourceStart, source.indexOf('Second'));
      final merged = structure.withMergedBreak(slides.last.sourceStart!);
      final restored = ContentStructure.fromMap(merged.toMap());
      expect(
        SlideLayout.compile(
          item(source, structure: restored),
          const PresentationTheme(),
        ).single.text,
        source,
      );
      expect(restored.originalSource, source);
      expect(restored.splitOffsets, isEmpty);
    },
  );

  test('manual merge excludes headings and retains mapped source offsets', () {
    const source = '[Verse 1]\nPraise the Lord.\n\n[Chorus]\nGive thanks.';
    final base = ContentStructure.fromSource(source);
    final merged = base.withMergedBreak(base.sections.last.start);
    final slide = SlideLayout.compile(
      item(source, structure: merged),
      const PresentationTheme(),
    ).single;
    expect(slide.text, 'Praise the Lord.\n\nGive thanks.');
    expect(slide.sourceStart, source.indexOf('Praise'));
    expect(slide.sourceEnd, source.length);
    final roundTrip = PresentationSlide.fromMap(slide.toMap());
    expect(roundTrip.toMap(), slide.toMap());
    expect(merged.originalSource, source);
  });

  test(
    'CRLF and boundary manual separators preserve offsets and source exactly',
    () {
      const source = '---\r\nFirst section.\r\n---\r\nSecond section.\r\n---';
      final structure = ContentStructure.fromSource(source);
      final slides = SlideLayout.compile(
        item(source, structure: structure),
        const PresentationTheme(),
      );
      expect(slides.map((slide) => slide.text), [
        'First section.',
        'Second section.',
      ]);
      expect(structure.originalSource, source);
      for (final slide in slides) {
        expect(
          source.substring(slide.sourceStart!, slide.sourceEnd!),
          slide.text,
        );
      }
    },
  );

  test(
    'manual splits reject partial words, combining marks and emoji sequences',
    () {
      for (final fixture in [
        ('complete words', 3),
        ('e\u0301 words', 1),
        ('👍🏽 words', 2),
        ('👨‍👩‍👧‍👦 words', 2),
      ]) {
        final structure = ContentStructure.fromSource(fixture.$1);
        expect(
          () => structure.withSplit(fixture.$2),
          throwsFormatException,
          reason: fixture.$1,
        );
      }
      expect(ContentStructure.fromSource('安寧平和').withSplit(2).splitOffsets, [
        2,
      ]);
      expect(
        ContentStructure.fromSource('complete words').withSplit(9).splitOffsets,
        [9],
      );
    },
  );

  test(
    'CJK text without spaces paginates at whole characters with source conservation',
    () {
      final source = List.filled(80, '願平安與你們同在。讓我們懷著感恩之心一同歌唱。').join();
      final slides = SlideLayout.compile(
        item(source),
        const PresentationTheme(fontSize: 110),
      );
      expect(slides.length, greaterThan(1));
      expect(slides.map((slide) => slide.text).join(), source);
      for (final slide in slides) {
        expect(SlideLayout.fits(slide.text, slide.theme), isTrue);
        expect(
          '、。，．！？：；)]}」』】》〉'.contains(slide.text.characters.first),
          isFalse,
        );
        expect(
          source.substring(slide.sourceStart!, slide.sourceEnd!),
          slide.text,
        );
      }
    },
  );

  test(
    'complex scripts, combining marks and family emoji keep grapheme boundaries',
    () {
      final source = List.filled(
        65,
        'அமைதி அனைவருக்கும். शांति सबके साथ हो। e\u0301 👨‍👩‍👧‍👦 👍🏽',
      ).join(' ');
      final boundaries = <int>{0};
      var offset = 0;
      for (final character in source.characters) {
        offset += character.length;
        boundaries.add(offset);
      }
      final slides = SlideLayout.compile(
        item(source),
        const PresentationTheme(fontSize: 100),
      );
      expect(
        normalized(slides.map((slide) => slide.text).join(' ')),
        normalized(source),
      );
      for (final slide in slides) {
        expect(boundaries, contains(slide.sourceStart));
        expect(boundaries, contains(slide.sourceEnd));
        expect(
          source.substring(slide.sourceStart!, slide.sourceEnd!),
          slide.text,
        );
        expect(SlideLayout.fits(slide.text, slide.theme), isTrue);
      }
    },
  );

  test(
    'unbroken links give an actionable overflow instead of silently cutting a word',
    () {
      final source = 'https://example.org/${'verylongword' * 300}';
      expect(
        () => SlideLayout.compile(item(source), const PresentationTheme()),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('unbroken word or link'),
          ),
        ),
      );
    },
  );

  test(
    'automatic direction uses first strong letter and explicit overrides',
    () {
      const theme = PresentationTheme();
      expect(
        SlideLayout.direction('123 🙂 שלום לכולם', theme),
        TextDirection.rtl,
      );
      expect(SlideLayout.direction('٢٠٢٦ مرحبا بكم', theme), TextDirection.rtl);
      expect(SlideLayout.direction('Peace שלום', theme), TextDirection.ltr);
      expect(
        SlideLayout.direction('שלום', theme.copyWith(textDirection: 'ltr')),
        TextDirection.ltr,
      );
      expect(
        SlideLayout.direction('Peace', theme.copyWith(textDirection: 'rtl')),
        TextDirection.rtl,
      );
    },
  );

  test(
    'Thai unspaced paragraphs preserve all graphemes with shaped line breaks',
    () {
      final source = List.filled(
        80,
        'ขอให้สันติสุขจงอยู่กับท่านทั้งหลาย',
      ).join();
      final boundaries = <int>{0};
      var offset = 0;
      for (final character in source.characters) {
        offset += character.length;
        boundaries.add(offset);
      }
      final slides = SlideLayout.compile(
        item(source),
        const PresentationTheme(fontSize: 110),
      );
      expect(slides.length, greaterThan(1));
      expect(slides.map((slide) => slide.text).join(), source);
      for (final slide in slides) {
        expect(boundaries, contains(slide.sourceStart));
        expect(boundaries, contains(slide.sourceEnd));
        expect(SlideLayout.fits(slide.text, slide.theme), isTrue);
      }
    },
  );

  test('spacing and alignment serialize with backward compatible defaults', () {
    const theme = PresentationTheme(
      verticalAlignment: 'bottom',
      lineHeight: 1.8,
      paragraphSpacing: 72,
      textDirection: 'rtl',
    );
    final restored = PresentationTheme.fromMap(theme.toMap());
    expect(restored.toMap(), theme.toMap());
    final old = PresentationTheme.fromMap({'fontSize': 68});
    expect(old.lineHeight, 1.35);
    expect(old.textDirection, 'auto');
    final text = List.filled(6, 'Praise.').join('\n');
    expect(
      SlideLayout.fits(
        text,
        const PresentationTheme(fontSize: 100, lineHeight: 1),
      ),
      isTrue,
    );
    expect(
      SlideLayout.fits(
        text,
        const PresentationTheme(fontSize: 100, lineHeight: 2),
      ),
      isFalse,
    );
    for (final invalid in [
      const PresentationTheme(lineHeight: .5),
      const PresentationTheme(lineHeight: double.nan),
      const PresentationTheme(paragraphSpacing: -1),
      const PresentationTheme(paragraphSpacing: 81),
      const PresentationTheme(textDirection: 'sideways'),
      const PresentationTheme(verticalAlignment: 'middle'),
      const PresentationTheme(alignment: 'justify'),
    ]) {
      expect(() => SlideLayout.validateTheme(invalid), throwsFormatException);
    }
  });
}
