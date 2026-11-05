import 'dart:async';

import 'package:cantivra/domain/models.dart';
import 'package:cantivra/presentation/live_controller.dart';
import 'package:cantivra/presentation/slides.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeOutput implements OutputTransport {
  @override
  bool connected = true;
  final frames = <OutputFrame>[];
  Future<int> Function(OutputFrame)? handler;

  @override
  Future<int> publish(OutputFrame frame) async {
    frames.add(frame);
    return handler == null ? frame.revision : handler!(frame);
  }
}

PresentationSlide slide(String text, {PresentationTheme? theme}) =>
    PresentationSlide(
      id: text,
      sourceId: 'source-$text',
      title: 'Title $text',
      label: text,
      text: text,
      theme: theme ?? const PresentationTheme(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Explicit live publication', () {
    late FakeOutput output;
    late LiveController live;

    setUp(() {
      output = FakeOutput();
      live = LiveController(output);
    });
    tearDown(() => live.dispose());

    test('starts black with no implicitly published content', () {
      expect(live.frame.mode, OutputMode.black);
      expect(live.frame.slide, isNull);
      expect(live.deck, isEmpty);
      expect(output.frames, isEmpty);
    });

    test(
      'draft text and theme edits stay separate until an explicit publish',
      () async {
        final source = ContentItem(
          id: 'hymn-1',
          title: 'A hymn',
          kind: ContentKind.hymn,
          sourceText: 'The original word.',
          modifiedAt: DateTime.utc(2026),
        );
        const theme = PresentationTheme();
        final first = SlideLayout.compile(source, theme);
        expect(await live.goLive(first, 0), isTrue);

        final draft = source.copyWith(sourceText: 'The corrected word.');
        final draftTheme = theme.copyWith(
          fontSize: 84,
          backgroundColor: 0xff204030,
        );
        final preview = SlideLayout.compile(draft, draftTheme);

        expect(live.frame.slide!.text, 'The original word.');
        expect(live.frame.slide!.theme.fontSize, 68);
        expect(live.frame.slide!.theme.backgroundColor, 0xff10192a);
        expect(output.frames, hasLength(1));
        expect(preview.single.text, 'The corrected word.');

        expect(await live.goLive(preview, 0), isTrue);
        expect(live.frame.slide!.text, 'The corrected word.');
        expect(live.frame.slide!.theme.fontSize, 84);
        expect(output.frames, hasLength(2));
      },
    );

    test(
      'captures its own navigation sequence independently of operator selection',
      () async {
        final operatorDeck = [slide('First'), slide('Second'), slide('Third')];
        expect(await live.goLive(operatorDeck, 0), isTrue);

        operatorDeck
          ..clear()
          ..add(slide('Unplanned draft'));
        expect(await live.next(), isTrue);
        expect(live.frame.slide!.text, 'Second');
        expect(live.index, 1);
        expect(live.deck, hasLength(3));
        expect(await live.previous(), isTrue);
        expect(live.frame.slide!.text, 'First');
        expect(() => live.deck.clear(), throwsUnsupportedError);
      },
    );

    test(
      'navigation respects sequence boundaries and invalid selections',
      () async {
        expect(await live.goLive([], 0), isFalse);
        expect(await live.goLive([slide('First')], -1), isFalse);
        expect(await live.goLive([slide('First')], 1), isFalse);
        expect(output.frames, isEmpty);

        await live.goLive([slide('First'), slide('Last')], 0);
        expect(await live.previous(), isFalse);
        expect(await live.next(), isTrue);
        expect(await live.next(), isFalse);
        expect(live.frame.slide!.text, 'Last');
      },
    );

    test(
      'black, clear, background and restore retain the accepted snapshot',
      () async {
        await live.goLive([slide('Keep this content')], 0);
        final accepted = live.frame.slide;
        await live.clear();
        expect(live.frame.mode, OutputMode.clear);
        expect(live.frame.slide, same(accepted));
        await live.black();
        expect(live.frame.mode, OutputMode.black);
        expect(live.frame.slide, same(accepted));
        await live.toggleBackground();
        expect(live.frame.backgroundVisible, isFalse);
        await live.restore();
        expect(live.frame.mode, OutputMode.normal);
        expect(live.frame.slide, same(accepted));
        expect(live.frame.backgroundVisible, isFalse);
      },
    );

    test(
      'freeze blocks ordinary replacement until explicitly restored',
      () async {
        await live.goLive([slide('First'), slide('Second')], 0);
        await live.freeze();
        expect(live.frame.frozen, isTrue);
        final sent = output.frames.length;
        expect(await live.next(), isFalse);
        expect(await live.previous(), isFalse);
        expect(await live.goLive([slide('Other')], 0), isFalse);
        expect(await live.toggleBackground(), isFalse);
        expect(output.frames, hasLength(sent));
        expect(live.frame.slide!.text, 'First');
        await live.restore();
        expect(live.frame.frozen, isFalse);
        expect(await live.next(), isTrue);
        expect(live.frame.slide!.text, 'Second');
      },
    );

    test(
      'transport failure preserves accepted slide, sequence and cursor',
      () async {
        await live.goLive([slide('First'), slide('Second')], 0);
        final accepted = live.frame;
        output.handler = (_) async => throw StateError('Disconnected');
        expect(await live.next(), isFalse);
        expect(live.frame, same(accepted));
        expect(live.index, 0);
        expect(live.deck.map((entry) => entry.text), ['First', 'Second']);
        expect(live.error, contains('not confirmed'));
        expect(live.busy, isFalse);
      },
    );

    test(
      'incorrect acknowledgement cannot mark an unconfirmed slide live',
      () async {
        await live.goLive([slide('First')], 0);
        final accepted = live.frame;
        output.handler = (frame) async => frame.revision - 1;
        expect(await live.goLive([slide('Unconfirmed')], 0), isFalse);
        expect(live.frame, same(accepted));
        expect(live.deck.single.text, 'First');
        expect(live.error, isNotNull);
      },
    );

    test(
      'normal commands cannot overtake an outstanding publication',
      () async {
        final waiting = Completer<int>();
        output.handler = (_) => waiting.future;
        final publishing = live.goLive([slide('First')], 0);
        expect(live.busy, isTrue);
        expect(await live.goLive([slide('Other')], 0), isFalse);
        expect(output.frames, hasLength(1));
        waiting.complete(output.frames.single.revision);
        expect(await publishing, isTrue);
        expect(live.frame.slide!.text, 'First');
      },
    );

    test(
      'newer emergency ACK wins over a late ordinary publication ACK',
      () async {
        await live.goLive([slide('Accepted')], 0);
        final pending = <int, Completer<int>>{};
        output.handler = (frame) =>
            (pending[frame.revision] = Completer<int>()).future;

        final publish = live.goLive([slide('Must not appear after stop')], 0);
        final publishRevision = output.frames.last.revision;
        final stop = live.emergencyStop();
        final stopRevision = output.frames.last.revision;
        expect(stopRevision, greaterThan(publishRevision));

        pending[stopRevision]!.complete(stopRevision);
        expect(await stop, isTrue);
        pending[publishRevision]!.complete(publishRevision);
        await publish;

        expect(live.frame.revision, stopRevision);
        expect(live.frame.mode, OutputMode.black);
        expect(live.frame.emergency, isTrue);
        expect(live.frame.slide!.text, 'Accepted');
        expect(live.deck.single.text, 'Accepted');
      },
    );

    test(
      'emergency black works while frozen and restore is explicit',
      () async {
        await live.goLive([slide('Visible content')], 0);
        await live.freeze();
        expect(await live.emergencyStop(), isTrue);
        expect(live.frame.mode, OutputMode.black);
        expect(live.frame.emergency, isTrue);
        expect(live.frame.slide!.text, 'Visible content');
        await live.restore();
        expect(live.frame.mode, OutputMode.normal);
        expect(live.frame.emergency, isFalse);
      },
    );
  });

  group('Output frame validation', () {
    test(
      'serializable snapshot retains complete text, theme and output flags',
      () {
        final original = OutputFrame(
          revision: 9,
          slide: slide(
            'A complete snapshot',
            theme: const PresentationTheme(fontSize: 80, safeMargin: .12),
          ),
          mode: OutputMode.clear,
          frozen: true,
          backgroundVisible: false,
        );
        final restored = OutputFrame.fromMap(original.toMap());
        expect(restored.toMap(), original.toMap());
      },
    );

    test(
      'unsupported protocols, negative revisions and oversized text fail',
      () {
        final valid = OutputFrame(revision: 1, slide: slide('A line')).toMap();
        expect(
          () => OutputFrame.fromMap({...valid, 'protocol': 99}),
          throwsFormatException,
        );
        expect(
          () => OutputFrame.fromMap({...valid, 'revision': -1}),
          throwsFormatException,
        );
        expect(
          () => OutputFrame.fromMap(
            OutputFrame(revision: 1, slide: slide('x' * 50001)).toMap(),
          ),
          throwsFormatException,
        );
      },
    );

    test(
      'overflowing candidate is rejected before replacing renderer state',
      () {
        final overflow = OutputFrame(
          revision: 2,
          slide: slide(
            List.filled(
              100,
              'This candidate has far too much text.',
            ).join('\n'),
          ),
        );
        expect(
          () => OutputFrame.fromMap(overflow.toMap()),
          throwsFormatException,
        );
      },
    );
  });
}
