import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/workspace_controller.dart';
import '../domain/models.dart';
import '../presentation/slide_surface.dart';

Future<void> showContentTools(
  BuildContext context,
  WorkspaceController controller, {
  int? sourceCursor,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      ContentToolsDialog(controller: controller, sourceCursor: sourceCursor),
);

/// Review and layout tools have no reference to the publish transport.
class ContentToolsDialog extends StatefulWidget {
  const ContentToolsDialog({
    super.key,
    required this.controller,
    this.sourceCursor,
  });
  final WorkspaceController controller;
  final int? sourceCursor;

  @override
  State<ContentToolsDialog> createState() => _ContentToolsDialogState();
}

class _ContentToolsDialogState extends State<ContentToolsDialog> {
  WorkspaceController get c => widget.controller;
  late ContentRecognition recognition = c.recognitionSuggestion!;
  late List<ContentSection> reviewed =
      (c.selected!.structure ?? recognition.structure).sections.toList();
  late Future<List<ContentItem>> history = c.versions();
  bool useDetectedKind = true;
  bool guides = true;
  int reviewGeneration = 0;
  String? problem;

  void action(void Function() work) {
    try {
      work();
      setState(() => problem = null);
    } catch (error) {
      setState(() => problem = '$error');
    }
  }

  Future<void> asyncAction(Future<void> Function() work) async {
    try {
      await work();
      if (mounted) setState(() => problem = null);
    } catch (error) {
      if (mounted) setState(() => problem = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: math.min(960, viewport.width - 48),
        height: math.min(760, viewport.height - 64),
        child: DefaultTabController(
          length: 3,
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Prepare content',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              c.selected?.title ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close content tools',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const TabBar(
                  tabs: [
                    Tab(text: 'Structure'),
                    Tab(text: 'Layout'),
                    Tab(text: 'History'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [_structure(), _layout(), _history()],
                  ),
                ),
                if (problem != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      problem!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, size: 16),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Changes prepare the preview. Use Go live when ready.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      TextButton(
                        onPressed: () => asyncAction(() async {
                          final navigator = Navigator.of(context);
                          await c.flushSave();
                          if (mounted) navigator.pop();
                        }),
                        child: const Text('Save and close'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _structure() {
    final current = c.selected!;
    final stale = recognition.structure.originalSource != current.sourceText;
    final cursor = widget.sourceCursor;
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('structure-list'),
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Suggested ${recognition.detectedKind.name} · '
                '${(recognition.confidence * 100).round()}% confidence',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                recognition.needsConfirmation
                    ? 'Review carefully: the structure is uncertain. Your original text is preserved.'
                    : 'Review section labels and types before applying. Your original text is preserved.',
              ),
              const SizedBox(height: 8),
              for (final reason in recognition.reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '• $reason',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Set content type to ${recognition.detectedKind.name}',
                ),
                value: useDetectedKind,
                onChanged: (value) =>
                    setState(() => useDetectedKind = value ?? false),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() {
                      recognition = c.recognitionSuggestion!;
                      reviewed = recognition.structure.sections.toList();
                      reviewGeneration++;
                    }),
                    child: const Text('Detect again'),
                  ),
                  TextButton(
                    onPressed: current.structure == null
                        ? null
                        : () => action(c.resetStructure),
                    child: const Text('Use original layout'),
                  ),
                ],
              ),
              if (stale)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'Source changed. Detect again before applying this suggestion.',
                  ),
                ),
              const SizedBox(height: 20),
              const Text(
                'MANUAL SLIDE BREAKS',
                style: TextStyle(letterSpacing: 1, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('split-at-source-cursor'),
                    onPressed:
                        cursor == null ||
                            cursor <= 0 ||
                            cursor >= current.sourceText.length
                        ? null
                        : () => action(() => c.splitAtSourceOffset(cursor)),
                    icon: const Icon(Icons.vertical_split, size: 17),
                    label: const Text('Split at source cursor'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('merge-next-slide'),
                    onPressed: c.previewIndex + 1 < c.previewSlides.length
                        ? () => action(c.mergeSelectedWithNext)
                        : null,
                    icon: const Icon(Icons.merge, size: 17),
                    label: const Text('Merge selected with next'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Place the source cursor where the next slide should begin, then open these tools. '
                'Merging removes the boundary; long text still paginates to fit the chosen font.',
                style: TextStyle(fontSize: 12),
              ),
              if (current.structure case final structure?) ...[
                const SizedBox(height: 8),
                Text(
                  '${structure.splitOffsets.length} manual splits · '
                  '${structure.mergedBreaks.length} merged boundaries saved',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
              const SizedBox(height: 20),
              for (var index = 0; index < reviewed.length; index++)
                _sectionReview(index, reviewed[index]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const ValueKey('apply-reviewed-structure'),
              onPressed: stale || reviewed.isEmpty
                  ? null
                  : () => action(() {
                      c.applyStructure(
                        recognition.structure.copyWith(
                          sections: reviewed,
                          splitOffsets: c.selected!.structure?.splitOffsets,
                          mergedBreaks: c.selected!.structure?.mergedBreaks,
                        ),
                        detectedKind: useDetectedKind
                            ? recognition.detectedKind
                            : null,
                      );
                    }),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Apply reviewed structure'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionReview(int index, ContentSection section) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  key: ValueKey('review-label-${section.id}-$reviewGeneration'),
                  initialValue: section.label,
                  decoration: InputDecoration(
                    labelText: 'Section ${index + 1} label',
                  ),
                  onChanged: (label) =>
                      reviewed[index] = reviewed[index].copyWith(label: label),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<SectionKind>(
                  key: ValueKey(
                    'review-type-${section.id}-${section.kind.name}-$reviewGeneration',
                  ),
                  initialValue: section.kind,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: SectionKind.values
                      .map(
                        (kind) => DropdownMenuItem(
                          value: kind,
                          child: Text(kind.name),
                        ),
                      )
                      .toList(),
                  onChanged: (kind) {
                    if (kind != null) {
                      setState(
                        () => reviewed[index] = reviewed[index].copyWith(
                          kind: kind,
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(
            section.text,
            maxLines: 6,
            style: const TextStyle(height: 1.5),
          ),
        ],
      ),
    ),
  );

  Widget _layout() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        'Readable text layout',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      ),
      const SizedBox(height: 8),
      const Text(
        'Layout is measured at the selected font size. Long passages continue on additional slides.',
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 24,
        runSpacing: 18,
        children: [
          SizedBox(
            width: 250,
            child: DropdownButtonFormField<String>(
              key: ValueKey('vertical-${c.theme.verticalAlignment}'),
              initialValue: c.theme.verticalAlignment,
              decoration: const InputDecoration(
                labelText: 'Vertical alignment',
              ),
              items: const [
                DropdownMenuItem(value: 'top', child: Text('Top')),
                DropdownMenuItem(value: 'center', child: Text('Center')),
                DropdownMenuItem(value: 'bottom', child: Text('Bottom')),
              ],
              onChanged: (value) {
                if (value != null) {
                  asyncAction(
                    () => c.applyTheme(
                      c.theme.copyWith(verticalAlignment: value),
                    ),
                  );
                }
              },
            ),
          ),
          SizedBox(
            width: 250,
            child: DropdownButtonFormField<String>(
              key: ValueKey('direction-${c.theme.textDirection}'),
              initialValue: c.theme.textDirection,
              decoration: const InputDecoration(labelText: 'Text direction'),
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('Automatic')),
                DropdownMenuItem(value: 'ltr', child: Text('Left to right')),
                DropdownMenuItem(value: 'rtl', child: Text('Right to left')),
              ],
              onChanged: (value) {
                if (value != null) {
                  asyncAction(
                    () => c.applyTheme(c.theme.copyWith(textDirection: value)),
                  );
                }
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      const Text('Horizontal alignment'),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'left',
              icon: Icon(Icons.format_align_left),
              label: Text('Left'),
            ),
            ButtonSegment(
              value: 'center',
              icon: Icon(Icons.format_align_center),
              label: Text('Center'),
            ),
            ButtonSegment(
              value: 'right',
              icon: Icon(Icons.format_align_right),
              label: Text('Right'),
            ),
          ],
          selected: {c.theme.alignment},
          onSelectionChanged: (values) => asyncAction(
            () => c.applyTheme(c.theme.copyWith(alignment: values.first)),
          ),
        ),
      ),
      const SizedBox(height: 20),
      Text('Line spacing · ${c.theme.lineHeight.toStringAsFixed(2)}'),
      Slider(
        key: const ValueKey('line-height'),
        min: 1,
        max: 2,
        divisions: 20,
        value: c.theme.lineHeight,
        onChanged: (value) => asyncAction(
          () => c.applyTheme(c.theme.copyWith(lineHeight: value)),
        ),
      ),
      Text(
        'Paragraph spacing · ${c.theme.paragraphSpacing.round()} px at 1080p',
      ),
      Slider(
        key: const ValueKey('paragraph-spacing'),
        min: 0,
        max: 80,
        divisions: 16,
        value: c.theme.paragraphSpacing,
        onChanged: (value) => asyncAction(
          () => c.applyTheme(c.theme.copyWith(paragraphSpacing: value)),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Show safe-area guides in this preview'),
        value: guides,
        onChanged: (value) => setState(() => guides = value),
      ),
      AspectRatio(
        aspectRatio: 16 / 9,
        child: SlideSurface(slide: c.preview, safeGuides: guides),
      ),
      if (c.layoutError != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            c.layoutError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );

  Widget _history() => FutureBuilder<List<ContentItem>>(
    future: history,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: Text('History could not load: ${snapshot.error}'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final versions = snapshot.data!;
      if (versions.isEmpty) {
        return const Center(
          child: Text('Save content to create its first revision.'),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: versions.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'Restore a revision into the draft. Existing history and the live output are preserved.',
              ),
            );
          }
          final version = versions[index - 1];
          return Card(
            child: ExpansionTile(
              title: Text(version.title),
              subtitle: Text(
                '${_timestamp(version.modifiedAt)} · ${version.kind.name}',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(version.sourceText, maxLines: 8),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => asyncAction(() async {
                    final navigator = Navigator.of(context);
                    await c.restoreVersion(version);
                    if (mounted) navigator.pop();
                  }),
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('Restore to draft'),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  String _timestamp(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}
