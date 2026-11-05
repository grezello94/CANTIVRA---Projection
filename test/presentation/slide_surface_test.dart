import 'package:cantivra/domain/models.dart';
import 'package:cantivra/presentation/live_controller.dart';
import 'package:cantivra/presentation/slide_surface.dart';
import 'package:cantivra/presentation/slides.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const prepared = PresentationSlide(
  id: 'slide-1',
  sourceId: 'hymn-1',
  title: 'A hymn',
  label: 'Verse 1',
  text: 'Peace be with you.',
  theme: PresentationTheme(backgroundColor: 0xff204030),
);

Widget canvas({
  PresentationSlide? slide = prepared,
  OutputMode mode = OutputMode.normal,
  bool backgroundVisible = true,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 640,
        height: 360,
        child: SlideSurface(
          slide: slide,
          mode: mode,
          backgroundVisible: backgroundVisible,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'output canvas renders presentation text without operator controls',
    (tester) async {
      await tester.pumpWidget(canvas());
      expect(find.text(prepared.text), findsOneWidget);
      expect(find.text('Go Live'), findsNothing);
      expect(find.text('Library'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'black hides all presentation content but preserves layout geometry',
    (tester) async {
      await tester.pumpWidget(canvas(mode: OutputMode.black));
      expect(find.text(prepared.text), findsNothing);
      expect(find.byType(AspectRatio), findsOneWidget);
      expect(
        tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
        16 / 9,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('clear text keeps background and background toggle uses black', (
    tester,
  ) async {
    await tester.pumpWidget(canvas(mode: OutputMode.clear));
    expect(find.text(prepared.text), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == const Color(0xff204030),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(canvas(backgroundVisible: false));
    expect(find.text(prepared.text), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == const Color(0xff204030),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('no accepted slide starts with a valid black canvas', (
    tester,
  ) async {
    await tester.pumpWidget(canvas(slide: null));
    expect(find.text(prepared.text), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canonical canvas letterboxes inside a different aspect ratio', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 500,
          height: 500,
          child: SlideSurface(slide: prepared),
        ),
      ),
    );
    final ratio = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(ratio.aspectRatio, 16 / 9);
    expect(find.byType(FittedBox), findsOneWidget);
    expect(
      tester.widget<FittedBox>(find.byType(FittedBox)).fit,
      BoxFit.contain,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rendering shares RTL direction, paragraph spacing and typography',
    (tester) async {
      const theme = PresentationTheme(
        verticalAlignment: 'bottom',
        textDirection: 'auto',
        lineHeight: 1.6,
        paragraphSpacing: 64,
      );
      const slide = PresentationSlide(
        id: 'paragraphs',
        sourceId: 'fixture',
        title: 'Reading',
        label: 'Reading',
        text: 'שלום לכולם\n\nPeace be with you.',
        theme: theme,
      );
      await tester.pumpWidget(canvas(slide: slide));
      final rtl = tester.widget<Text>(find.text('שלום לכולם'));
      final ltr = tester.widget<Text>(find.text('Peace be with you.'));
      expect(rtl.textDirection, TextDirection.rtl);
      expect(ltr.textDirection, TextDirection.ltr);
      expect(rtl.style!.height, theme.lineHeight);
      expect(rtl.textScaler, TextScaler.noScaling);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.height == 64,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Align && widget.alignment == Alignment.bottomCenter,
        ),
        findsOneWidget,
      );
      final topFirst = tester.getTopLeft(find.text('שלום לכולם')).dy;
      final topSecond = tester.getTopLeft(find.text('Peace be with you.')).dy;
      final firstHeight = tester.getSize(find.text('שלום לכולם')).height;
      expect(topSecond - topFirst - firstHeight / 3, closeTo(64 / 3, .1));
      expect(SlideLayout.fits(slide.text, theme), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
