import 'package:cantivra/domain/models.dart';
import 'package:cantivra/presentation/slides.dart';
import 'package:flutter_test/flutter_test.dart';

ContentItem content(String source) => ContentItem(
  id: 'reading-1',
  title: 'A reading',
  kind: ContentKind.reading,
  sourceText: source,
  modifiedAt: DateTime.utc(2026, 11, 4),
);

String normalized(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Measured slide layout', () {
    test(
      'honors manual splits and section headings without changing source',
      () {
        const source =
            '[Verse 1]\nA quiet first verse.\n\n'
            '[Chorus]\nA shared response.\n---\n[Verse 2]\nThe final verse.';
        final item = content(source);
        final slides = SlideLayout.compile(item, const PresentationTheme());

        expect(slides.map((slide) => slide.text), [
          'A quiet first verse.',
          'A shared response.',
          'The final verse.',
        ]);
        expect(slides.map((slide) => slide.label), [
          'Verse 1',
          'Chorus',
          'Verse 2',
        ]);
        expect(item.sourceText, source);
        expect(slides.map((slide) => slide.id).toSet().length, slides.length);
      },
    );

    test('long reading paginates without losing text or reducing font size', () {
      final source = List.generate(
        45,
        (index) =>
            'Paragraph $index: Let every heart be glad. '
            'We gather in peace and remember the good gifts we have received.',
      ).join(' ');
      const theme = PresentationTheme(fontSize: 76, safeMargin: .1);
      final slides = SlideLayout.compile(content(source), theme);

      expect(slides.length, greaterThan(1));
      expect(
        normalized(slides.map((slide) => slide.text).join(' ')),
        normalized(source),
      );
      for (final slide in slides) {
        expect(slide.text, isNotEmpty);
        expect(slide.theme.fontSize, 76);
        expect(SlideLayout.fits(slide.text, slide.theme), isTrue);
      }
    });

    test('changing size or margins recalculates prepared slides', () {
      final item = content(
        List.filled(
          45,
          'Sing together with joy and lift your hearts in thanksgiving.',
        ).join(' '),
      );
      final compact = SlideLayout.compile(
        item,
        const PresentationTheme(fontSize: 48, safeMargin: .04),
      );
      final spacious = SlideLayout.compile(
        item,
        const PresentationTheme(fontSize: 100, safeMargin: .18),
      );

      expect(spacious.length, greaterThan(compact.length));
      expect(
        spacious.every((slide) => SlideLayout.fits(slide.text, slide.theme)),
        isTrue,
      );
      expect(
        normalized(spacious.map((slide) => slide.text).join(' ')),
        normalized(item.sourceText),
      );
    });

    test('non-Latin text and Unicode scalar values survive pagination', () {
      final source = List.filled(
        70,
        'அமைதி அனைவருக்கும். शांति सबके साथ हो। Peace be with you. 🕊️',
      ).join(' ');
      final slides = SlideLayout.compile(
        content(source),
        const PresentationTheme(fontSize: 90),
      );

      expect(slides.length, greaterThan(1));
      expect(
        normalized(slides.map((slide) => slide.text).join(' ')),
        normalized(source),
      );
      expect(
        slides.every((slide) => SlideLayout.fits(slide.text, slide.theme)),
        isTrue,
      );
    });

    test('empty content produces no accidentally publishable blank slide', () {
      expect(
        SlideLayout.compile(
          content(' \n\n \n---\n '),
          const PresentationTheme(),
        ),
        isEmpty,
      );
    });

    test(
      'published slide values cannot be changed by editing input objects',
      () {
        final item = content('An original line.');
        const theme = PresentationTheme();
        final slides = SlideLayout.compile(item, theme);
        final changed = item.copyWith(sourceText: 'The corrected line.');
        final changedTheme = theme.copyWith(
          fontSize: 95,
          textColor: 0xff00ff00,
        );
        final correctedSlides = SlideLayout.compile(changed, changedTheme);

        expect(slides.single.text, 'An original line.');
        expect(slides.single.theme.fontSize, 68);
        expect(slides.single.theme.textColor, 0xfffaf8f1);
        expect(correctedSlides.single.text, 'The corrected line.');
        expect(correctedSlides.single.theme.fontSize, 95);
        expect(() => slides.clear(), throwsUnsupportedError);
      },
    );

    test('oversized items fail before attempting unbounded layout work', () {
      expect(
        () => SlideLayout.compile(
          content('x' * 50001),
          const PresentationTheme(),
        ),
        throwsFormatException,
      );
    });

    test(
      'invalid geometry is rejected rather than clipped or infinitely shrunk',
      () {
        for (final theme in [
          const PresentationTheme(fontSize: 0),
          const PresentationTheme(fontSize: 141),
          const PresentationTheme(fontSize: double.nan),
          const PresentationTheme(safeMargin: -.1),
          const PresentationTheme(safeMargin: .5),
        ]) {
          expect(
            () => SlideLayout.compile(content('A line.'), theme),
            throwsFormatException,
          );
        }
      },
    );
  });
}
