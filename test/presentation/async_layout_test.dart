import 'dart:async';

import 'package:cantivra/domain/models.dart';
import 'package:cantivra/presentation/slides.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

ContentItem fixture(String source, {ContentStructure? structure}) =>
    ContentItem(
      id: 'async-fixture',
      title: 'Async reading',
      kind: ContentKind.reading,
      sourceText: source,
      structure: structure,
      modifiedAt: DateTime.utc(2026, 11, 5),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'incremental and synchronous compilation produce identical immutable decks',
    () async {
      for (final source in [
        '[Verse 1]\r\nSing with joy.\r\n\r\n[Chorus]\r\nLet us give thanks.',
        List.filled(
          80,
          'Peace be with you. அமைதி அனைவருக்கும். शांति सबके साथ हो। 👨‍👩‍👧‍👦',
        ).join(' '),
        List.filled(60, '願平安與你們同在。讓我們懷著感恩之心一同歌唱。').join(),
        List.filled(60, 'ขอให้สันติสุขจงอยู่กับท่านทั้งหลาย').join(),
      ]) {
        final item = fixture(source);
        const theme = PresentationTheme(fontSize: 92, lineHeight: 1.5);
        final sync = SlideLayout.compile(item, theme);
        final incremental = await SlideLayout.compileAsync(item, theme);
        expect(
          incremental.map((slide) => slide.toMap()).toList(),
          sync.map((slide) => slide.toMap()).toList(),
        );
        expect(() => incremental.clear(), throwsUnsupportedError);
      }
    },
  );

  test(
    'manual layout overrides retain identical labels and mapped offsets asynchronously',
    () async {
      const source =
          '[Verse 1]\nSing with joy.\n\n[Chorus]\nGive thanks. Another sentence.';
      final base = ContentStructure.fromSource(source);
      final structure = base
          .withMergedBreak(base.sections.last.start)
          .withSplit(source.indexOf('Another'));
      final item = fixture(source, structure: structure);
      const theme = PresentationTheme();
      final sync = SlideLayout.compile(item, theme);
      final incremental = await SlideLayout.compileAsync(item, theme);
      expect(
        incremental.map((slide) => slide.toMap()).toList(),
        sync.map((slide) => slide.toMap()).toList(),
      );
      expect(item.sourceText, source);
    },
  );

  test(
    'long 20k passage yields to event loop while keeping complete measured text',
    () async {
      final source = List.filled(
        280,
        'Let every heart be glad. We gather in peace and give thanks for each new day.',
      ).join(' ');
      expect(source.length, greaterThan(20000));
      var heartbeats = 0;
      var maxGapMicros = 0;
      final watch = Stopwatch()..start();
      var previous = 0;
      final heartbeat = Timer.periodic(const Duration(milliseconds: 1), (_) {
        heartbeats++;
        final now = watch.elapsedMicroseconds;
        final gap = now - previous;
        if (gap > maxGapMicros) maxGapMicros = gap;
        previous = now;
      });
      try {
        final slides = await SlideLayout.compileAsync(
          fixture(source),
          const PresentationTheme(fontSize: 90),
        );
        watch.stop();
        expect(heartbeats, greaterThan(2));
        expect(slides.length, greaterThan(10));
        expect(
          slides
              .map((slide) => slide.text)
              .join(' ')
              .replaceAll(RegExp(r'\s+'), ' '),
          source,
        );
        expect(
          slides.every((slide) => SlideLayout.fits(slide.text, slide.theme)),
          isTrue,
        );
        debugPrint(
          'LAYOUT_TEST_SAMPLE chars=${source.length} slides=${slides.length} elapsedMs=${watch.elapsedMilliseconds} heartbeatCount=$heartbeats maxGapMs=${(maxGapMicros / 1000).toStringAsFixed(2)}',
        );
      } finally {
        heartbeat.cancel();
      }
    },
  );

  test(
    'cancellation before work never returns a partial candidate deck',
    () async {
      await expectLater(
        SlideLayout.compileAsync(
          fixture('A short reading.'),
          const PresentationTheme(),
          isCancelled: () => true,
        ),
        throwsA(isA<LayoutCancelled>()),
      );
    },
  );

  test(
    'cancellation between pages stops a superseded long compilation',
    () async {
      final source = List.filled(
        280,
        'Let every heart be glad. We gather in peace and give thanks for each new day.',
      ).join(' ');
      var checks = 0;
      await expectLater(
        SlideLayout.compileAsync(
          fixture(source),
          const PresentationTheme(fontSize: 90),
          isCancelled: () => ++checks >= 7,
        ),
        throwsA(isA<LayoutCancelled>()),
      );
      expect(checks, 7);
    },
  );

  test(
    'pathological combining sequences fail before large font shaping work',
    () async {
      final source = 'A${'\u0301' * 20000}';
      expect(
        () => SlideLayout.compile(fixture(source), const PresentationTheme()),
        throwsFormatException,
      );
      await expectLater(
        SlideLayout.compileAsync(fixture(source), const PresentationTheme()),
        throwsFormatException,
      );
    },
  );

  test('excessive invisible runs stop at bounded measurement size', () async {
    final source = '${'\u200b' * 20000}Amen.';
    await expectLater(
      SlideLayout.compileAsync(fixture(source), const PresentationTheme()),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('invisible characters'),
        ),
      ),
    );
  });
}
