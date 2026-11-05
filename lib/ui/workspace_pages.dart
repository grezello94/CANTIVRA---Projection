import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/workspace_controller.dart';
import '../domain/models.dart';
import '../presentation/slide_surface.dart';
import 'content_tools.dart';
import 'operator_app.dart';

class LibraryBrowser extends StatelessWidget {
  const LibraryBrowser({super.key, required this.controller});
  final WorkspaceController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface.withValues(alpha: .5),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 19, 17, 13),
            child: Row(
              children: [
                Text(
                  c.query.isEmpty ? 'CONTENT LIBRARY' : 'SEARCH RESULTS',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.3,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  '${c.results.length}',
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: c.results.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No matching content. Try another word or create an item.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: c.results.length,
                    itemBuilder: (context, index) {
                      final item = c.results[index];
                      final selected = c.selected?.id == item.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Material(
                          color: selected
                              ? scheme.primary.withValues(alpha: .09)
                              : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                            side: BorderSide(
                              color: selected
                                  ? scheme.primary.withValues(alpha: .25)
                                  : Colors.transparent,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(7),
                            onTap: () => runWorkspaceAction(
                              c,
                              () => c.selectContent(item),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 13, 5, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: selected
                                                ? scheme.primary
                                                : scheme.onSurface,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: item.favorite
                                            ? 'Remove favorite'
                                            : 'Favorite',
                                        onPressed: () => runWorkspaceAction(
                                          c,
                                          () => c.toggleFavorite(item),
                                        ),
                                        icon: Icon(
                                          item.favorite
                                              ? Icons.star_rounded
                                              : Icons.star_outline_rounded,
                                          size: 17,
                                          color: item.favorite
                                              ? const Color(0xffd9b872)
                                              : scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        '${item.kind.name.toUpperCase()} · ${item.language}',
                                        style: TextStyle(
                                          fontSize: 8,
                                          letterSpacing: .4,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        tooltip: 'Add to current service',
                                        onPressed: c.service == null
                                            ? null
                                            : () => runWorkspaceAction(
                                                c,
                                                () => c.addToService(item),
                                              ),
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                          size: 17,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Select to preview. Use + to add to your service.',
              style: TextStyle(
                fontSize: 10,
                height: 1.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ServiceBrowser extends StatelessWidget {
  const ServiceBrowser({super.key, required this.controller});
  final WorkspaceController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    if (c.query.isNotEmpty) return LibraryBrowser(controller: c);
    final plan = c.service;
    return ColoredBox(
      color: scheme.surface.withValues(alpha: .5),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 19, 10, 12),
            child: Row(
              children: [
                Text(
                  'RUNNING ORDER',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'Service actions',
                  icon: const Icon(Icons.more_horiz, size: 18),
                  onSelected: (value) async {
                    if (value == 'duplicate') {
                      final title = await askName(
                        context,
                        title: 'Duplicate service',
                        hint: 'Name the new service',
                      );
                      if (title != null) {
                        unawaited(
                          runWorkspaceAction(
                            c,
                            () => c.createService(title, duplicate: true),
                          ),
                        );
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'duplicate',
                      enabled: plan != null,
                      child: const Text('Duplicate service'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 0, 13, 17),
            child: DropdownButtonFormField<String>(
              key: ValueKey('service-${plan?.id}'),
              initialValue: plan?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
              ),
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 11,
                color: scheme.onSurface,
              ),
              hint: const Text('Choose a service'),
              items: c.services
                  .map(
                    (s) => DropdownMenuItem(
                      value: s.id,
                      child: Text(s.title, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (id) {
                if (id != null) {
                  runWorkspaceAction(
                    c,
                    () => c.chooseService(
                      c.services.firstWhere((s) => s.id == id),
                    ),
                  );
                }
              },
            ),
          ),
          Expanded(
            child: plan == null || plan.items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Build your service by adding content from the library.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: plan.items.length,
                    onReorder: (old, next) =>
                        runWorkspaceAction(c, () => c.reorder(old, next)),
                    itemBuilder: (context, index) {
                      final entry = plan.items[index];
                      final item = c.contentFor(entry.contentId);
                      final selected = c.selectedEntryId == entry.id;
                      return Padding(
                        key: ValueKey(entry.id),
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Material(
                          color: selected
                              ? scheme.primary.withValues(alpha: .1)
                              : scheme.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                            side: BorderSide(
                              color: selected
                                  ? scheme.primary.withValues(alpha: .25)
                                  : scheme.outlineVariant.withValues(
                                      alpha: .16,
                                    ),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(7),
                            onTap: item == null
                                ? null
                                : () => runWorkspaceAction(
                                    c,
                                    () => c.selectContent(
                                      item,
                                      entryId: entry.id,
                                    ),
                                  ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 8,
                              ),
                              child: Row(
                                children: [
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.grab,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: 7,
                                        ),
                                        child: Icon(
                                          Icons.drag_indicator,
                                          size: 15,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${index + 1}'.padLeft(2, '0'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: selected
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item?.title ?? entry.label,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          item?.kind.name.toUpperCase() ??
                                              'MISSING CONTENT',
                                          style: TextStyle(
                                            fontSize: 8,
                                            letterSpacing: .8,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 180,
                                    ),
                                    icon: Icon(
                                      Icons.more_vert,
                                      size: 15,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    onSelected: (_) async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text(
                                            'Remove from service?',
                                          ),
                                          content: Text(
                                            'Remove “${item?.title ?? entry.label}” from this running order? The library item is kept.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('Cancel'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('Remove'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed == true) {
                                        unawaited(
                                          runWorkspaceAction(
                                            c,
                                            () => c.removeEntry(entry.id),
                                          ),
                                        );
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                        value: 'remove',
                                        child: Text('Remove from service'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                OutlinedButton.icon(
                  onPressed: () => c.navigate(WorkspacePage.library),
                  icon: const Icon(Icons.add, size: 15),
                  label: const Text(
                    'Add service item',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Drag the handles to reorder.\nYour plan saves automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SourceEditor extends StatefulWidget {
  const SourceEditor({super.key, required this.controller});
  final WorkspaceController controller;
  @override
  State<SourceEditor> createState() => _SourceEditorState();
}

class _SourceEditorState extends State<SourceEditor> {
  late final source = TextEditingController(
    text: widget.controller.selected!.sourceText,
  );
  late final title = TextEditingController(
    text: widget.controller.selected!.title,
  );
  @override
  void didUpdateWidget(covariant SourceEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(source, widget.controller.selected!.sourceText);
    _sync(title, widget.controller.selected!.title);
  }

  void _sync(TextEditingController controller, String text) {
    if (controller.text == text) return;
    final offset = controller.selection.extentOffset.clamp(0, text.length);
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  @override
  void dispose() {
    source.dispose();
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final scheme = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): c.undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): c.undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            c.redo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): c.redo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): c.redo,
      },
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 6, 8, 3),
              child: Row(
                children: [
                  const Icon(Icons.edit_note_outlined, size: 16),
                  const SizedBox(width: 6),
                  const Text(
                    'SOURCE EDITOR',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    c.recoveredDraftIds.contains(c.selected!.id)
                        ? 'Recovered draft'
                        : c.saved
                        ? 'Saved locally'
                        : 'Saving…',
                    style: TextStyle(fontSize: 9, color: scheme.primary),
                  ),
                  const SizedBox(width: 7),
                  IconButton(
                    tooltip: 'Undo source edit',
                    onPressed: c.canUndo ? c.undo : null,
                    icon: const Icon(Icons.undo, size: 15),
                  ),
                  IconButton(
                    tooltip: 'Redo source edit',
                    onPressed: c.canRedo ? c.redo : null,
                    icon: const Icon(Icons.redo, size: 15),
                  ),
                  IconButton(
                    key: const ValueKey('content-tools'),
                    tooltip: 'Content structure, layout and history',
                    onPressed: () => showContentTools(
                      context,
                      c,
                      sourceCursor: source.selection.isValid
                          ? source.selection.extentOffset
                          : null,
                    ),
                    icon: const Icon(Icons.tune, size: 16),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: title,
                      style: const TextStyle(fontSize: 11),
                      decoration: const InputDecoration(
                        hintText: 'Content title',
                        isDense: true,
                        contentPadding: EdgeInsets.all(9),
                      ),
                      onChanged: (value) => c.edit(title: value),
                    ),
                  ),
                  const SizedBox(width: 9),
                  DropdownButton<ContentKind>(
                    value: c.selected!.kind,
                    underline: const SizedBox(),
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 10,
                      color: scheme.onSurface,
                    ),
                    items: ContentKind.values
                        .map(
                          (kind) => DropdownMenuItem(
                            value: kind,
                            child: Text(kind.name),
                          ),
                        )
                        .toList(),
                    onChanged: (kind) => c.edit(kind: kind),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                child: TextField(
                  key: const ValueKey('source-text'),
                  controller: source,
                  expands: true,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    fontFamily: 'Menlo',
                    fontSize: 11,
                    height: 1.5,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.all(9),
                  ),
                  onChanged: (text) => c.edit(sourceText: text),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Draft only · blank line or --- creates a slide · [Verse 1] labels a section',
                      style: TextStyle(
                        fontSize: 8,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkspacePages extends StatelessWidget {
  const WorkspacePages({super.key, required this.controller});
  final WorkspaceController controller;
  @override
  Widget build(BuildContext context) => switch (controller.page) {
    WorkspacePage.themes => _ThemePage(controller: controller),
    WorkspacePage.settings => _SettingsPage(controller: controller),
    _ => const _MediaPage(),
  };
}

class _ThemePage extends StatelessWidget {
  const _ThemePage({required this.controller});
  final WorkspaceController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const Text(
          'A setting for every moment',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a starting point, then make it your own. Changes update preview; publish explicitly to change live output.',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 26),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: builtInThemes
              .map(
                (theme) => InkWell(
                  onTap: () => runWorkspaceAction(c, () => c.applyTheme(theme)),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 228,
                    height: 157,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: c.theme.id == theme.id
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: c.theme.id == theme.id ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Color(theme.backgroundColor),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                'Let us worship\ntogether.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: theme.fontFamily,
                                  color: Color(theme.textColor),
                                  fontSize: 21,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: Text(
                            theme.name,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 30),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Refine the presentation',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      key: ValueKey(c.theme.fontFamily),
                      initialValue: c.theme.fontFamily,
                      decoration: const InputDecoration(
                        labelText: 'Font family',
                      ),
                      items: ['Georgia', 'Arial', 'Times New Roman', 'Verdana']
                          .map(
                            (font) => DropdownMenuItem(
                              value: font,
                              child: Text(font),
                            ),
                          )
                          .toList(),
                      onChanged: (font) {
                        if (font != null) {
                          runWorkspaceAction(
                            c,
                            () => c.applyTheme(
                              c.theme.copyWith(fontFamily: font),
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Text size · ${c.theme.fontSize.round()} px at 1080p',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Slider(
                      value: c.theme.fontSize,
                      min: 32,
                      max: 140,
                      divisions: 54,
                      onChanged: (size) => runWorkspaceAction(
                        c,
                        () => c.applyTheme(c.theme.copyWith(fontSize: size)),
                      ),
                    ),
                    Text(
                      'Safe margins · ${(c.theme.safeMargin * 100).round()}%',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Slider(
                      value: c.theme.safeMargin,
                      min: .03,
                      max: .2,
                      divisions: 17,
                      onChanged: (margin) => runWorkspaceAction(
                        c,
                        () =>
                            c.applyTheme(c.theme.copyWith(safeMargin: margin)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'left',
                          icon: Icon(Icons.format_align_left),
                        ),
                        ButtonSegment(
                          value: 'center',
                          icon: Icon(Icons.format_align_center),
                        ),
                        ButtonSegment(
                          value: 'right',
                          icon: Icon(Icons.format_align_right),
                        ),
                      ],
                      selected: {c.theme.alignment},
                      onSelectionChanged: (value) => runWorkspaceAction(
                        c,
                        () => c.applyTheme(
                          c.theme.copyWith(alignment: value.first),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PREVIEW · SAFE AREA',
                      style: TextStyle(fontSize: 10, letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 12),
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: SlideSurface(slide: c.preview, safeGuides: true),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      'This theme is saved for the workspace and used when publishing your service. Published slides keep their captured theme until you publish again.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.7,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (c.layoutError != null)
                      Text(
                        c.layoutError!,
                        style: TextStyle(color: scheme.error),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.controller});
  final WorkspaceController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        _OutputSettings(controller: c),
        const SizedBox(height: 20),
        _SettingsCard(
          title: 'Your data stays here',
          subtitle:
              'SQLite content, service plans, revisions, and preferences are stored on this computer.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                c.dataDirectory,
                style: TextStyle(
                  fontFamily: 'Menlo',
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => runWorkspaceAction(c, c.backup),
                    icon: const Icon(Icons.backup_outlined, size: 18),
                    label: const Text('Create local backup'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => runWorkspaceAction(c, () async {
                      final result = await c.repository.integrityCheck();
                      c.showMessage('Database integrity check: $result');
                    }),
                    icon: const Icon(Icons.verified_user_outlined, size: 17),
                    label: const Text('Check database integrity'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Backups are consistent SQLite snapshots in the backups folder. Guided restore and automatic backup retention are scheduled for the data-safety milestone.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SettingsCard(
          title: 'Operator appearance',
          subtitle:
              'Presentation themes are separate from the operator interface.',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Dark interface', style: TextStyle(fontSize: 13)),
            value: c.dark,
            onChanged: (_) => runWorkspaceAction(c, c.toggleDark),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Foundation release · Native macOS and Windows source · Hardware validation is required before live-service deployment.',
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _OutputSettings extends StatelessWidget {
  const _OutputSettings({required this.controller});
  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    final draft = c.outputProfileDraft;
    final secondary = c.displays
        .where((display) => !display.isPrimary && display.isOutputEligible)
        .toList();
    final targetAvailable =
        draft.isRehearsal ||
        secondary.any((display) => display.id == draft.displayId);
    final currentDisplay = c.displays
        .where((display) => display.id == c.output.displayId)
        .firstOrNull;
    final currentTarget = c.output.displayId == null
        ? 'Windowed rehearsal'
        : currentDisplay?.name ?? 'Remembered display · disconnected';

    return _SettingsCard(
      title: 'Presentation displays',
      subtitle:
          'Save a setup for each room. Prepare your changes here, then apply the output when you are ready.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'CONNECTED DISPLAYS',
                  style: TextStyle(fontSize: 10, letterSpacing: 1.1),
                ),
              ),
              TextButton.icon(
                onPressed: () => runWorkspaceAction(c, c.refreshDisplays),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (c.displays.isEmpty)
            Text(
              'No displays reported. Check the display connection and refresh.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final display in c.displays)
                Container(
                  width: 280,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.desktop_windows_outlined,
                        size: 29,
                        color: display.isPrimary
                            ? scheme.onSurfaceVariant
                            : scheme.primary,
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              display.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${(display.width * (Platform.isMacOS ? display.scale : 1)).round()} × ${(display.height * (Platform.isMacOS ? display.scale : 1)).round()} px · ${(display.scale * 100).round()}% DPI',
                              style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              display.isPrimary
                                  ? 'Primary · operator display'
                                  : display.isOutputEligible
                                  ? 'Secondary · presentation available'
                                  : display.unavailableReason ??
                                        'Display identity unavailable',
                              style: TextStyle(
                                fontSize: 10,
                                color: display.isPrimary
                                    ? scheme.onSurfaceVariant
                                    : scheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('output-profile-${c.selectedOutputProfileId}'),
                  initialValue: c.selectedOutputProfileId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Saved output profile',
                  ),
                  items: c.outputProfiles
                      .map(
                        (profile) => DropdownMenuItem(
                          value: profile.id,
                          child: Text(
                            profile.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (id) {
                    if (id != null) {
                      runWorkspaceAction(c, () => c.selectOutputProfile(id));
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final name = await askName(
                    context,
                    title: 'New output profile',
                    hint: 'Main church, chapel, or rehearsal',
                  );
                  if (name != null) {
                    unawaited(
                      runWorkspaceAction(c, () => c.createOutputProfile(name)),
                    );
                  }
                },
                icon: const Icon(Icons.add, size: 17),
                label: const Text('New profile'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextFormField(
            key: ValueKey(
              'output-profile-name-${draft.id}-${c.selectedOutputProfile?.name}',
            ),
            initialValue: draft.name,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Profile name',
              counterText: '',
            ),
            onChanged: (name) => c.prepareOutputProfile(
              c.outputProfileDraft.copyWith(name: name),
            ),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'output-target-${draft.id}-${draft.displayId}-$targetAvailable',
            ),
            initialValue: draft.displayId ?? '__windowed_rehearsal__',
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Prepared presentation destination',
            ),
            items: [
              const DropdownMenuItem(
                value: '__windowed_rehearsal__',
                child: Text('Windowed rehearsal · on this computer'),
              ),
              for (final display in secondary)
                DropdownMenuItem(
                  value: display.id,
                  child: Text(
                    '${display.name} · full screen',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (!targetAvailable)
                DropdownMenuItem(
                  value: draft.displayId,
                  enabled: false,
                  child: const Text(
                    'Remembered display unavailable · reconnect to apply',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) => c.preferredDisplayId =
                id == '__windowed_rehearsal__' ? null : id,
          ),
          const SizedBox(height: 10),
          Text(
            targetAvailable
                ? 'The primary display is reserved for the operator. An HDMI splitter sends identical content to its connected TVs.'
                : 'This profile keeps its original target. Reconnecting never chooses another screen automatically.',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: targetAvailable ? scheme.onSurfaceVariant : scheme.error,
            ),
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final calibration = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Canvas scale · ${(draft.scale * 100).round()}%',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Slider(
                    key: const ValueKey('output-scale'),
                    value: draft.scale,
                    min: .75,
                    max: 1,
                    divisions: 25,
                    label: '${(draft.scale * 100).round()}%',
                    onChanged: (scale) => c.prepareOutputProfile(
                      c.outputProfileDraft.copyWith(scale: scale),
                    ),
                  ),
                  Text(
                    'Safe inset · ${(draft.safeInset * 100).round()}% per edge',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Slider(
                    key: const ValueKey('output-safe-inset'),
                    value: draft.safeInset,
                    min: 0,
                    max: .12,
                    divisions: 12,
                    label: '${(draft.safeInset * 100).round()}%',
                    onChanged: (inset) => c.prepareOutputProfile(
                      c.outputProfileDraft.copyWith(safeInset: inset),
                    ),
                  ),
                  Text(
                    'Calibration keeps the complete 16:9 canvas inside the display. Text formatting stays in Themes.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
              final preview = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PREPARED CANVAS · ${(draft.effectiveScale * 100).round()}%',
                    style: const TextStyle(fontSize: 9, letterSpacing: .9),
                  ),
                  const SizedBox(height: 10),
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ClipRect(
                      child: ColoredBox(
                        color: Colors.black,
                        child: SlideSurface(
                          slide: c.preview,
                          canvasScale: draft.effectiveScale,
                        ),
                      ),
                    ),
                  ),
                ],
              );
              if (constraints.maxWidth < 620) {
                return Column(
                  children: [calibration, const SizedBox(height: 20), preview],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: calibration),
                  const SizedBox(width: 28),
                  SizedBox(width: 260, child: preview),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: draft.name.trim().isEmpty
                    ? null
                    : () => runWorkspaceAction(c, c.saveOutputProfile),
                icon: const Icon(Icons.save_outlined, size: 17),
                label: const Text('Save profile'),
              ),
              FilledButton.icon(
                onPressed:
                    c.output.opening ||
                        draft.name.trim().isEmpty ||
                        !targetAvailable
                    ? null
                    : () => runWorkspaceAction(c, c.openOutput),
                icon: const Icon(Icons.cast_connected, size: 17),
                label: Text(
                  c.output.opening ? 'Opening output…' : 'Apply / open output',
                ),
              ),
              Text(
                c.hasPreparedOutputChanges
                    ? 'Unsaved profile edits'
                    : 'Profile saved',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            c.outputConfigurationPending
                ? 'Prepared changes take effect only when you apply the output.'
                : 'The prepared profile matches the current output.',
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  c.output.connected ? Icons.check_circle_outline : Icons.cast,
                  color: c.output.connected
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                  size: 21,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current output · ${c.output.statusLabel}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        c.output.error ??
                            (c.output.connected
                                ? '$currentTarget · Profile selection and editing leave this output unchanged.'
                                : 'Open a secondary display or a windowed rehearsal when ready.'),
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.5,
                          color: c.output.error == null
                              ? scheme.onSurfaceVariant
                              : scheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: c.output.connected
                      ? () => runWorkspaceAction(c, c.output.close)
                      : null,
                  child: const Text('Close output'),
                ),
              ],
            ),
          ),
          if (c.displayError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                c.displayError!,
                style: TextStyle(fontSize: 11, color: scheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(11),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 25),
        child,
      ],
    ),
  );
}

class _MediaPage extends StatelessWidget {
  const _MediaPage();
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 470),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.perm_media_outlined,
            size: 47,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 22),
          const Text(
            'Media comes in its own milestone',
            style: TextStyle(fontSize: 23),
          ),
          const SizedBox(height: 14),
          Text(
            'The foundation release focuses on dependable text presentation. Images, licensed image search, video playback, and document imports will be added with dedicated rendering and failure-recovery tests.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.8,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Planned · see docs/ROADMAP.md',
            style: TextStyle(fontSize: 11),
          ),
        ],
      ),
    ),
  );
}
