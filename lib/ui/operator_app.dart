import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/workspace_controller.dart';
import '../domain/models.dart';
import '../presentation/live_controller.dart';
import '../presentation/slide_surface.dart';
import 'workspace_pages.dart';

const accent = Color(0xff8ee3ca);

class CantivraApp extends StatelessWidget {
  const CantivraApp({super.key, required this.controller});
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      title: 'Cantivra',
      debugShowCheckedModeBanner: false,
      themeMode: controller.dark ? ThemeMode.dark : ThemeMode.light,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      builder: (context, child) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f12): () =>
              runWorkspaceAction(controller, controller.live.emergencyStop),
        },
        child: child ?? const SizedBox.shrink(),
      ),
      home: OperatorShell(controller: controller),
    ),
  );

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff398771),
      brightness: brightness,
      primary: dark ? accent : const Color(0xff196e58),
      surface: dark ? const Color(0xff151a22) : const Color(0xfff8f9fb),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xff10141b)
          : const Color(0xffeef1f4),
      fontFamily: 'Roboto',
      visualDensity: VisualDensity.compact,
      textTheme:
          Typography.material2021(
            platform: TargetPlatform.macOS,
            colorScheme: scheme,
          ).black.apply(
            bodyColor: scheme.onSurface,
            displayColor: scheme.onSurface,
            fontFamily: 'Roboto',
          ),
      dividerColor: scheme.outlineVariant.withValues(alpha: .35),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.onSurface.withValues(alpha: .035),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 400),
      ),
    );
  }
}

Future<void> runWorkspaceAction(
  WorkspaceController controller,
  Future<dynamic> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    controller.reportError(e);
  }
}

class OperatorShell extends StatefulWidget {
  const OperatorShell({super.key, required this.controller});
  final WorkspaceController controller;
  @override
  State<OperatorShell> createState() => _OperatorShellState();
}

class _OperatorShellState extends State<OperatorShell> {
  final search = TextEditingController();
  double browserWidth = 250;
  double monitorWidth = 300;
  WorkspaceController get c => widget.controller;
  void action(Future<dynamic> Function() work) =>
      unawaited(runWorkspaceAction(c, work));

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, alt: true): () =>
            action(c.publishSelected),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () =>
            action(c.live.next),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () =>
            action(c.live.previous),
        const SingleActivator(LogicalKeyboardKey.keyB, alt: true): () =>
            action(c.live.black),
        const SingleActivator(LogicalKeyboardKey.keyR, alt: true): () =>
            action(c.live.restore),
        const SingleActivator(LogicalKeyboardKey.f12): () =>
            action(c.live.emergencyStop),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (!c.focusMode) _Sidebar(controller: c),
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            height: 79,
                            padding: const EdgeInsets.symmetric(horizontal: 25),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              border: Border(
                                bottom: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _pageTitle,
                                        style: const TextStyle(
                                          fontSize: 23,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -.6,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        c.page == WorkspacePage.services
                                            ? 'Prepare your order. Take each moment live.'
                                            : 'Your church. Your content. Always available offline.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _StatusPill(
                                  label: 'LOCAL WORKSPACE',
                                  color: scheme.primary,
                                  icon: Icons.cloud_off_outlined,
                                ),
                                const SizedBox(width: 14),
                                IconButton(
                                  tooltip: c.focusMode
                                      ? 'Show navigation'
                                      : 'Distraction-free workspace',
                                  onPressed: () => setState(
                                    () => c.focusMode = !c.focusMode,
                                  ),
                                  icon: Icon(
                                    c.focusMode
                                        ? Icons.fullscreen_exit
                                        : Icons.fullscreen,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (_contentPage)
                                  FilledButton.icon(
                                    onPressed: _newContent,
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('New content'),
                                  ),
                                if (c.page == WorkspacePage.services)
                                  FilledButton.icon(
                                    onPressed: _newService,
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('New service'),
                                  ),
                              ],
                            ),
                          ),
                          if (c.error != null ||
                              c.live.error != null ||
                              c.message != null)
                            Container(
                              width: double.infinity,
                              color: (c.error != null || c.live.error != null
                                  ? scheme.errorContainer
                                  : scheme.primaryContainer),
                              padding: const EdgeInsets.fromLTRB(18, 4, 8, 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      c.error ?? c.live.error ?? c.message!,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      c.live.error = null;
                                      c.clearNotice();
                                    },
                                    icon: const Icon(Icons.close, size: 16),
                                  ),
                                ],
                              ),
                            ),
                          if (_contentPage)
                            Container(
                              height: 60,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: search,
                                      onChanged: c.setQuery,
                                      decoration: const InputDecoration(
                                        hintText:
                                            'Search titles, words, or a phrase…',
                                        prefixIcon: Icon(
                                          Icons.search,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    '${c.results.length} items',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  if (c.page == WorkspacePage.services)
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        c.navigate(WorkspacePage.library);
                                      },
                                      icon: const Icon(
                                        Icons.library_add_outlined,
                                        size: 17,
                                      ),
                                      label: const Text('Add from library'),
                                    ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: c.loading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : _contentPage
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (!c.focusMode)
                                        SizedBox(
                                          width: browserWidth,
                                          child:
                                              c.page == WorkspacePage.services
                                              ? ServiceBrowser(controller: c)
                                              : LibraryBrowser(controller: c),
                                        ),
                                      if (!c.focusMode)
                                        _ResizeHandle(
                                          onDelta: (delta) => setState(() {
                                            browserWidth =
                                                (browserWidth + delta).clamp(
                                                  210,
                                                  350,
                                                );
                                          }),
                                        ),
                                      Expanded(
                                        child: _SlideWorkspace(controller: c),
                                      ),
                                      _ResizeHandle(
                                        onDelta: (delta) => setState(() {
                                          monitorWidth = (monitorWidth - delta)
                                              .clamp(260, 420);
                                        }),
                                      ),
                                      SizedBox(
                                        width: monitorWidth,
                                        child: _MonitorPanel(controller: c),
                                      ),
                                    ],
                                  )
                                : WorkspacePages(controller: c),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _TransportBar(controller: c),
              Container(
                height: 27,
                color: scheme.surface,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'Offline ready · SQLite local storage',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Alt + Enter  Go live     Alt + ← / →  Navigate     F12  Emergency black',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 22),
                    const Text(
                      'CANTIVRA  /  0.3',
                      style: TextStyle(fontSize: 10, letterSpacing: 1.2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _contentPage => !{
    WorkspacePage.themes,
    WorkspacePage.settings,
    WorkspacePage.media,
  }.contains(c.page);
  String get _pageTitle => c.page == WorkspacePage.services
      ? 'Service workspace'
      : _title(c.page.name);
  Future<void> _newContent() async {
    final title = await askName(
      context,
      title: 'New content',
      hint: 'A title your team will recognize',
    );
    if (title != null) {
      action(() => c.createContent(title, c.kindFilter ?? ContentKind.custom));
    }
  }

  Future<void> _newService() async {
    final title = await askName(
      context,
      title: 'New service',
      hint: 'e.g. Sunday morning · 9:00',
    );
    if (title != null) action(() => c.createService(title));
  }
}

String _title(String value) => '${value[0].toUpperCase()}${value.substring(1)}';

Future<String?> askName(
  BuildContext context, {
  required String title,
  required String hint,
}) async {
  final input = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: TextField(
          autofocus: true,
          controller: input,
          maxLength: 120,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (input.text.trim().isNotEmpty) {
              Navigator.pop(context, input.text.trim());
            }
          },
          child: const Text('Create'),
        ),
      ],
    ),
  );
  // Dialog route removes its TextField after the reverse transition.
  Future<void>.delayed(const Duration(milliseconds: 300), input.dispose);
  return result;
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.controller});
  final WorkspaceController controller;
  static const icons = [
    Icons.local_library_outlined,
    Icons.music_note_outlined,
    Icons.volunteer_activism_outlined,
    Icons.menu_book_outlined,
    Icons.forum_outlined,
    Icons.perm_media_outlined,
    Icons.palette_outlined,
    Icons.view_list_outlined,
    Icons.tune,
  ];
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 181,
      color: scheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 12, 22),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/logo_mark.png',
                  width: 34,
                  height: 34,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    width: 31,
                    height: 34,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.church_outlined,
                      color: scheme.onPrimary,
                      size: 21,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'cantivra',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.9,
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 23, bottom: 13),
              child: Text(
                'WORKSPACE',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 2,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          for (final page in WorkspacePage.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              child: Material(
                color: controller.page == page
                    ? scheme.primary.withValues(alpha: .12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                child: InkWell(
                  borderRadius: BorderRadius.circular(7),
                  onTap: () => controller.navigate(page),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          icons[page.index],
                          size: 18,
                          color: controller.page == page
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _title(page.name),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: controller.page == page
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: controller.page == page
                                ? scheme.primary
                                : scheme.onSurface,
                          ),
                        ),
                        if (page == WorkspacePage.services) ...[
                          const Spacer(),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              children: [
                const Divider(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 17,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Church workspace',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            'Saved on this computer',
                            style: TextStyle(
                              fontSize: 9,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    IconButton(
                      onPressed: () =>
                          runWorkspaceAction(controller, controller.toggleDark),
                      tooltip: 'Switch light / dark interface',
                      icon: Icon(
                        controller.dark
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                        size: 18,
                      ),
                    ),
                    Text(
                      controller.dark ? 'Dark appearance' : 'Light appearance',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideWorkspace extends StatefulWidget {
  const _SlideWorkspace({required this.controller});
  final WorkspaceController controller;
  @override
  State<_SlideWorkspace> createState() => _SlideWorkspaceState();
}

class _SlideWorkspaceState extends State<_SlideWorkspace> {
  bool editing = true;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final scheme = Theme.of(context).colorScheme;
    if (c.selected == null) {
      return const Center(
        child: Text('Choose content to prepare a presentation.'),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.selected!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${_title(c.selected!.kind.name)}  /  ${c.previewSlides.length} slides  /  ${c.theme.name}',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Show / hide source editor',
                onPressed: () => setState(() => editing = !editing),
                icon: Icon(
                  editing ? Icons.edit_note : Icons.edit_outlined,
                  size: 22,
                ),
              ),
            ],
          ),
          if (c.selectedEntryId == null && c.service != null)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Row(
                children: [
                  Icon(Icons.call_split, size: 14, color: scheme.primary),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Unplanned item · your service order is saved',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                  TextButton(
                    onPressed: () => runWorkspaceAction(c, () async {
                      c.setQuery('', immediate: true);
                      c.navigate(WorkspacePage.services);
                      await c.chooseService(c.service!);
                    }),
                    child: const Text('Return', style: TextStyle(fontSize: 10)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Expanded(
            child: c.layoutPending
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(height: 12),
                        Text('Preparing slide layout…'),
                      ],
                    ),
                  )
                : c.layoutError != null
                ? Center(
                    child: Text(
                      c.layoutError!,
                      style: TextStyle(color: scheme.error),
                    ),
                  )
                : c.previewSlides.isEmpty
                ? const Center(
                    child: Text('Add text below to create your first slide.'),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) => GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: constraints.maxWidth >= 680 ? 3 : 2,
                        crossAxisSpacing: 13,
                        mainAxisSpacing: 13,
                        childAspectRatio: 1.47,
                      ),
                      itemCount: c.previewSlides.length,
                      itemBuilder: (context, index) {
                        final slide = c.previewSlides[index];
                        final selected = c.previewIndex == index;
                        final live =
                            c.live.frame.slide?.id == slide.id &&
                            c.live.frame.slide?.text == slide.text &&
                            identical(c.live.frame.slide?.theme, slide.theme) &&
                            c.live.frame.mode == OutputMode.normal;
                        return InkWell(
                          onTap: () => c.selectSlide(index),
                          borderRadius: BorderRadius.circular(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Container(
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(7),
                                    border: Border.all(
                                      color: selected
                                          ? scheme.primary
                                          : scheme.outlineVariant.withValues(
                                              alpha: .3,
                                            ),
                                      width: selected ? 2 : 1,
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(2),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: SlideSurface(slide: slide),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 7),
                              Row(
                                children: [
                                  Text(
                                    '${index + 1}'.padLeft(2, '0'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: selected
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      slide.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ),
                                  if (live)
                                    const Text(
                                      'LIVE',
                                      style: TextStyle(
                                        color: Color(0xfff38b83),
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
          if (editing) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 225,
              child: SourceEditor(key: ValueKey(c.selected!.id), controller: c),
            ),
          ],
        ],
      ),
    );
  }
}

class _MonitorPanel extends StatelessWidget {
  const _MonitorPanel({required this.controller});
  final WorkspaceController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    final frame = c.live.frame;
    return Container(
      color: scheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(17),
        children: [
          Row(
            children: [
              const Icon(Icons.circle, size: 7, color: Color(0xfff38b83)),
              const SizedBox(width: 7),
              const Text(
                'LIVE OUTPUT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              Text(
                frame.frozen ? 'FROZEN' : frame.mode.name.toUpperCase(),
                style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 13),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: SlideSurface(
                slide: frame.slide,
                mode: frame.mode,
                backgroundVisible: frame.backgroundVisible,
                canvasScale: c.output.canvasScale,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            frame.slide?.title ?? 'Nothing is live yet',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            c.output.connected
                ? 'Confirmed output · revision ${frame.revision}'
                : c.output.statusLabel,
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Divider(),
          ),
          Row(
            children: [
              Icon(Icons.visibility_outlined, size: 15, color: scheme.primary),
              const SizedBox(width: 8),
              const Text(
                'PREVIEW',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              Text(
                '${c.previewIndex + (c.previewSlides.isEmpty ? 0 : 1)} / ${c.previewSlides.length}',
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 13),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: SlideSurface(
                slide: c.preview,
                safeGuides: true,
                canvasScale: c.output.connected
                    ? c.output.canvasScale
                    : c.outputProfileDraft.effectiveScale,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Changes stay here until you go live.',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 15),
          FilledButton.icon(
            onPressed:
                c.preview == null ||
                    c.layoutPending ||
                    c.preparingPublication ||
                    frame.frozen ||
                    c.live.busy
                ? null
                : () => runWorkspaceAction(c, c.publishSelected),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text(
              c.preparingPublication
                  ? 'Preparing presentation…'
                  : 'Go live · selected slide',
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'NEXT IN PREVIEW',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 1.1,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 9),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: c.nextPreview == null
                  ? ColoredBox(
                      color: scheme.onSurface.withValues(alpha: .025),
                      child: Center(
                        child: Text(
                          'End of this item',
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : SlideSurface(
                      slide: c.nextPreview,
                      canvasScale: c.output.connected
                          ? c.output.canvasScale
                          : c.outputProfileDraft.effectiveScale,
                    ),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 9),
          Row(
            children: [
              Icon(
                Icons.monitor,
                size: 16,
                color: c.output.connected
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  c.output.statusLabel,
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: c.output.opening
                ? null
                : () => runWorkspaceAction(c, c.openOutput),
            icon: const Icon(Icons.open_in_new, size: 15),
            label: Text(
              c.output.opening ? 'Opening…' : 'Open presentation output',
            ),
          ),
          TextButton(
            onPressed: () => c.navigate(WorkspacePage.settings),
            child: const Text(
              'Configure displays',
              style: TextStyle(fontSize: 11),
            ),
          ),
          if (c.output.error != null)
            Text(
              c.output.error!,
              style: TextStyle(color: scheme.error, fontSize: 10),
            ),
        ],
      ),
    );
  }
}

class _TransportBar extends StatelessWidget {
  const _TransportBar({required this.controller});
  final WorkspaceController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final live = c.live;
    final scheme = Theme.of(context).colorScheme;
    final enabled = c.output.connected;
    return Container(
      height: 73,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          _StatusPill(
            label: enabled ? 'OUTPUT CONNECTED' : 'OUTPUT CLOSED',
            color: enabled ? scheme.primary : scheme.onSurfaceVariant,
            icon: Icons.cast_connected,
          ),
          const SizedBox(width: 18),
          IconButton(
            tooltip: 'Previous live slide · Alt + Left',
            onPressed:
                enabled && !live.frame.frozen && live.index > 0 && !live.busy
                ? () => runWorkspaceAction(c, live.previous)
                : null,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          Text(
            live.deck.isEmpty
                ? '— / —'
                : '${live.index + 1} / ${live.deck.length}',
            style: const TextStyle(fontSize: 12),
          ),
          IconButton(
            tooltip: 'Next live slide · Alt + Right',
            onPressed:
                enabled &&
                    !live.frame.frozen &&
                    live.index + 1 < live.deck.length &&
                    !live.busy
                ? () => runWorkspaceAction(c, live.next)
                : null,
            icon: const Icon(Icons.skip_next_rounded),
          ),
          const Spacer(),
          _Control(
            icon: Icons.rectangle,
            label: 'Black',
            active: live.frame.mode == OutputMode.black,
            onTap: enabled ? () => runWorkspaceAction(c, live.black) : null,
          ),
          _Control(
            icon: Icons.text_decrease,
            label: 'Clear text',
            active: live.frame.mode == OutputMode.clear,
            onTap: enabled && !live.frame.frozen
                ? () => runWorkspaceAction(c, live.clear)
                : null,
          ),
          _Control(
            icon: Icons.ac_unit,
            label: 'Freeze',
            active: live.frame.frozen,
            onTap: enabled
                ? () => runWorkspaceAction(
                    c,
                    live.frame.frozen ? live.restore : live.freeze,
                  )
                : null,
          ),
          _Control(
            icon: Icons.image_outlined,
            label: 'Background',
            active: !live.frame.backgroundVisible,
            onTap: enabled && !live.frame.frozen
                ? () => runWorkspaceAction(c, live.toggleBackground)
                : null,
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: enabled
                ? () => runWorkspaceAction(c, live.restore)
                : null,
            icon: const Icon(Icons.replay, size: 16),
            label: const Text('Restore', style: TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 16),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff592d32),
              foregroundColor: const Color(0xffffb5b5),
            ),
            onPressed: (enabled || c.output.canControl)
                ? () => runWorkspaceAction(c, live.emergencyStop)
                : null,
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: const Text('Emergency', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

class _Control extends StatelessWidget {
  const _Control({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: active
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
        backgroundColor: active
            ? Theme.of(context).colorScheme.primary.withValues(alpha: .08)
            : Colors.transparent,
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 10)),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.icon,
  });
  final String label;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            letterSpacing: .6,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDelta});
  final ValueChanged<double> onDelta;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) => onDelta(details.delta.dx),
      child: SizedBox(
        width: 5,
        child: Center(
          child: Container(width: 1, color: Theme.of(context).dividerColor),
        ),
      ),
    ),
  );
}
