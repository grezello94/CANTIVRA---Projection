import 'package:flutter/material.dart';

import 'live_controller.dart';
import 'slides.dart';

/// The same canvas is used in thumbnails, preview and the congregation engine.
class SlideSurface extends StatelessWidget {
  const SlideSurface({
    super.key,
    this.slide,
    this.mode = OutputMode.normal,
    this.backgroundVisible = true,
    this.safeGuides = false,
    this.canvasScale = 1,
  });
  final PresentationSlide? slide;
  final OutputMode mode;
  final bool backgroundVisible;
  final bool safeGuides;
  final double canvasScale;

  @override
  Widget build(BuildContext context) {
    final theme = slide?.theme;
    final black = mode == OutputMode.black || slide == null;
    final background = black || !backgroundVisible
        ? Colors.black
        : Color(theme!.backgroundColor);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Transform.scale(
          scale: canvasScale,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 1920,
                height: 1080,
                child: ColoredBox(
                  color: background,
                  child: Stack(
                    children: [
                      if (!black && mode != OutputMode.clear)
                        Positioned.fill(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 1920 * theme!.safeMargin,
                              vertical: 1080 * theme.safeMargin,
                            ),
                            child: Align(
                              alignment: SlideLayout.verticalAlignment(theme),
                              child: SizedBox(
                                width: double.infinity,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final (index, paragraph)
                                        in SlideLayout.paragraphs(
                                          slide!.text,
                                        ).indexed) ...[
                                      if (index > 0)
                                        SizedBox(
                                          height: theme.paragraphSpacing,
                                        ),
                                      Text(
                                        paragraph,
                                        textAlign: SlideLayout.alignment(theme),
                                        textDirection: SlideLayout.direction(
                                          paragraph,
                                          theme,
                                        ),
                                        style: SlideLayout.style(theme),
                                        textScaler: TextScaler.noScaling,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (safeGuides && theme != null)
                        Positioned.fill(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 1920 * theme.safeMargin,
                              vertical: 1080 * theme.safeMargin,
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0x667bd9c2),
                                  width: 3,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
