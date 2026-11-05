import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/app_repository.dart';
import '../domain/models.dart';
import '../domain/output_profile.dart';
import '../platform/display_bridge.dart';
import '../presentation/desktop_output.dart';
import '../presentation/live_controller.dart';
import '../presentation/slides.dart';

enum WorkspacePage {
  library,
  hymns,
  prayers,
  readings,
  responses,
  media,
  themes,
  services,
  settings,
}

const builtInThemes = [
  PresentationTheme(),
  PresentationTheme(
    id: 'sanctuary',
    name: 'Sanctuary',
    backgroundColor: 0xff18352f,
    textColor: 0xfff6f0de,
  ),
  PresentationTheme(
    id: 'linen',
    name: 'Linen',
    backgroundColor: 0xffeee8dc,
    textColor: 0xff292720,
  ),
  PresentationTheme(
    id: 'vespers',
    name: 'Vespers',
    backgroundColor: 0xff322138,
    textColor: 0xffffecdc,
  ),
];

class WorkspaceController extends ChangeNotifier {
  WorkspaceController({
    required this.repository,
    required this.output,
    required this.dataDirectory,
  }) : live = LiveController(output) {
    live.addListener(_forward);
    output.addListener(_forward);
    _displayChanges = NativeDisplayBridge.changes.listen(
      (_) {
        unawaited(refreshDisplays());
      },
      onError: (Object eventError) {
        if (_disposed) return;
        displayError = 'Display monitoring failed: $eventError';
        error = displayError;
        notifyListeners();
      },
    );
  }
  final AppRepository repository;
  final DesktopOutput output;
  final String dataDirectory;
  final LiveController live;
  WorkspacePage page = WorkspacePage.services;
  bool dark = true;
  bool loading = true;
  bool saved = true;
  bool focusMode = false;
  String? error;
  String? message;
  String query = '';
  List<ContentItem> results = [];
  final Map<String, ContentItem> _content = {};
  List<ServicePlan> services = [];
  ServicePlan? service;
  ContentItem? selected;
  String? selectedEntryId;
  List<PresentationSlide> previewSlides = [];
  int previewIndex = 0;
  PresentationTheme theme = builtInThemes.first;
  List<DisplayInfo> displays = [];
  List<OutputProfile> outputProfiles = const [];
  String _selectedOutputProfileId = 'default-output';
  OutputProfile _outputProfileDraft = const OutputProfile(
    id: 'default-output',
    name: 'Windowed rehearsal',
  );
  final Map<String, OutputProfile> _preparedProfiles = {};
  bool _profilesPersisted = false;
  OutputProfile? appliedOutputProfile;
  late final StreamSubscription<Map<String, Object?>> _displayChanges;
  bool _disposed = false;
  int _displayGeneration = 0;
  String? displayError;
  String? layoutError;
  bool layoutPending = false;
  bool preparingPublication = false;
  int _layoutGeneration = 0;
  int _publicationGeneration = 0;
  Timer? _autosave;
  Timer? _journalTimer;
  Timer? _searchTimer;
  int _searchGeneration = 0;
  Future<void> _saveQueue = Future.value();
  Future<void> _journalQueue = Future.value();
  Future<void> _profileSaveQueue = Future.value();
  final Set<String> _dirtyIds = {};
  final Set<String> _recoveredDraftIds = {};
  final Map<String, List<ContentItem>> _undo = {};
  final Map<String, List<ContentItem>> _redo = {};

  Set<String> get recoveredDraftIds => Set.unmodifiable(_recoveredDraftIds);
  int get recoveredDraftCount => _recoveredDraftIds.length;
  bool get canUndo => _undo[selected?.id]?.isNotEmpty ?? false;
  bool get canRedo => _redo[selected?.id]?.isNotEmpty ?? false;

  ContentRecognition? get recognitionSuggestion {
    final item = selected;
    return item == null
        ? null
        : ContentRecognizer.suggest(item.sourceText, item.kind);
  }

  void _forward() {
    // A live control issued while a deck is being prepared supersedes that
    // pending publication, including an emergency before its ACK arrives.
    if (preparingPublication && live.busy) _publicationGeneration++;
    notifyListeners();
  }

  String newId() => DateTime.now().microsecondsSinceEpoch.toString();

  String get selectedOutputProfileId => _selectedOutputProfileId;
  OutputProfile get outputProfileDraft => _outputProfileDraft;
  OutputProfile? get selectedOutputProfile => outputProfiles
      .where((profile) => profile.id == _selectedOutputProfileId)
      .firstOrNull;
  bool get hasPreparedOutputChanges =>
      !_profilesPersisted || selectedOutputProfile != _outputProfileDraft;
  bool get outputConfigurationPending =>
      !output.connected || appliedOutputProfile != _outputProfileDraft;

  /// Retained for Phase 1 callers. Changing this prepares a profile only.
  String? get preferredDisplayId => _outputProfileDraft.displayId;
  set preferredDisplayId(String? value) =>
      prepareOutputProfile(_outputProfileDraft.copyWith(displayId: value));

  Future<void> initialize() async {
    try {
      results = await repository.searchContent('');
      for (final item in results) {
        _content[item.id] = item;
      }
      // Recovery is staged only in the operator workspace. The stable library,
      // historical revisions and live renderer remain untouched until a save
      // or explicit presentation action is requested.
      for (final draft in await repository.drafts()) {
        final stable = _content[draft.id];
        if (stable == null || !draft.modifiedAt.isAfter(stable.modifiedAt)) {
          continue;
        }
        _content[draft.id] = draft;
        _dirtyIds.add(draft.id);
        _recoveredDraftIds.add(draft.id);
      }
      results = results.map((item) => _content[item.id]!).toList();
      services = await repository.listServices();
      await _loadPresentationTheme();
      dark = await repository.getSetting('darkMode') != 'false';
      final serviceId = await repository.getSetting('activeService');
      service =
          services.where((s) => s.id == serviceId).firstOrNull ??
          services.firstOrNull;
      await _loadOutputProfiles();
      await refreshDisplays();
      if (service?.items.firstOrNull case final entry?) {
        selectedEntryId = entry.id;
        selected = _content[entry.contentId];
      } else {
        selected = results.firstOrNull;
      }
      if (_recoveredDraftIds.isNotEmpty) {
        selected = _content[_recoveredDraftIds.first];
        selectedEntryId = null;
        saved = false;
        message =
            'Recovered ${_recoveredDraftIds.length} unsaved draft(s). Review before publishing.';
      }
      _compile();
    } catch (e) {
      error = 'Could not load the workspace: $e';
    }
    // Library and settings failures must not prevent reconnection to the
    // independent renderer. Inspection never replaces its last good frame.
    try {
      if (await output.recoverExisting() && output.recoveredFrame != null) {
        live.reconcileOutput(output.recoveredFrame!);
        message = _recoveredDraftIds.isEmpty
            ? 'Recovered the existing live output. No content was republished.'
            : 'Recovered the existing live output and ${_recoveredDraftIds.length} separate draft(s). Review before publishing.';
      }
    } catch (recoveryError) {
      final recoveryMessage =
          'Existing output could not be inspected: $recoveryError';
      error = error == null ? recoveryMessage : '$error\n$recoveryMessage';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _loadPresentationTheme() async {
    // A repository failure still belongs to the main startup error path. Only
    // this optional setting's decoding/validation is recoverable here.
    final savedTheme = await repository.getSetting('presentationTheme');
    if (savedTheme == null) return;
    try {
      final restored = PresentationTheme.fromMap(
        Map<String, Object?>.from(jsonDecode(savedTheme) as Map),
      );
      SlideLayout.validateTheme(restored);
      theme = restored;
    } catch (e) {
      // Keep the original setting for diagnosis/recovery. A corrupt preview
      // theme must not prevent library use or inspection of a surviving output.
      error =
          'Saved presentation theme could not be read. Using the default preview theme: $e';
    }
  }

  Future<void> refreshDisplays() async {
    final generation = ++_displayGeneration;
    try {
      final connected = await NativeDisplayBridge.listDisplays();
      if (_disposed || generation != _displayGeneration) return;
      displays = connected;
      displayError = null;
    } catch (e) {
      if (_disposed || generation != _displayGeneration) return;
      displayError = 'Display detection failed: $e';
      error = displayError;
    }
    notifyListeners();
  }

  Future<void> _loadOutputProfiles() async {
    final saved = await repository.getSetting('outputProfiles');
    try {
      if (saved != null) {
        final container = Map<String, Object?>.from(jsonDecode(saved) as Map);
        if (container['version'] != OutputProfile.version) {
          throw const FormatException(
            'Unsupported saved output profiles version.',
          );
        }
        final profiles = (container['profiles'] as List)
            .map(
              (value) => OutputProfile.fromMap(
                Map<String, Object?>.from(value as Map),
              ),
            )
            .toList();
        if (profiles.isEmpty ||
            profiles.map((profile) => profile.id).toSet().length !=
                profiles.length) {
          throw const FormatException(
            'Output profiles must have distinct identifiers.',
          );
        }
        outputProfiles = List.unmodifiable(profiles);
        _profilesPersisted = true;
        final active = await repository.getSetting('activeOutputProfile');
        _outputProfileDraft =
            profiles.where((profile) => profile.id == active).firstOrNull ??
            profiles.first;
      } else {
        // Lazy migration: preserve the old target, including disconnected IDs.
        // Persist only after an explicit profile save or accepted output open.
        final legacy = await repository.getSetting('preferredDisplay');
        final target = legacy == null || legacy.isEmpty ? null : legacy;
        _outputProfileDraft = OutputProfile(
          id: 'default-output',
          name: target == null ? 'Windowed rehearsal' : 'Church screens',
          displayId: target,
        );
        outputProfiles = List.unmodifiable([_outputProfileDraft]);
      }
      _selectedOutputProfileId = _outputProfileDraft.id;
    } catch (e) {
      // A malformed optional profile setting must leave the library usable.
      error = 'Saved output profiles could not be read: $e';
      outputProfiles = List.unmodifiable([_outputProfileDraft]);
    }
  }

  void prepareOutputProfile(OutputProfile profile) {
    profile.validate(allowEmptyName: true);
    if (profile.id != _selectedOutputProfileId) {
      throw StateError('Select this output profile before editing it.');
    }
    _outputProfileDraft = profile;
    _preparedProfiles[profile.id] = profile;
    notifyListeners();
  }

  Future<void> selectOutputProfile(String id) async {
    final profile = outputProfiles
        .where((profile) => profile.id == id)
        .firstOrNull;
    if (profile == null) {
      throw StateError('The selected output profile is unavailable.');
    }
    await repository.saveSetting('activeOutputProfile', id);
    _selectedOutputProfileId = id;
    _outputProfileDraft = _preparedProfiles[id] ?? profile;
    notifyListeners();
  }

  Future<void> createOutputProfile(String name) async {
    final profile = _outputProfileDraft.copyWith(
      id: 'output-${newId()}',
      name: name.trim(),
    );
    profile.validate();
    await _persistOutputProfile(profile);
    _selectedOutputProfileId = profile.id;
    _outputProfileDraft = profile;
    await repository.saveSetting('activeOutputProfile', profile.id);
    message = 'Output profile “${profile.name}” created. Apply it when ready.';
    notifyListeners();
  }

  Future<void> saveOutputProfile() async {
    final profile = _outputProfileDraft.copyWith(
      name: _outputProfileDraft.name.trim(),
    );
    profile.validate();
    await _persistOutputProfile(profile);
    if (_selectedOutputProfileId == profile.id) {
      await repository.saveSetting('activeOutputProfile', profile.id);
    }
    if (_outputProfileDraft.id == profile.id &&
        _outputProfileDraft.copyWith(name: _outputProfileDraft.name.trim()) ==
            profile) {
      _outputProfileDraft = profile;
      _preparedProfiles.remove(profile.id);
    }
    message = 'Profile saved. Apply output to use these display settings.';
    notifyListeners();
  }

  Future<void> _persistOutputProfile(OutputProfile profile) {
    final operation = _profileSaveQueue.then((_) async {
      final profiles = outputProfiles
          .where((saved) => saved.id != profile.id)
          .toList();
      final index = outputProfiles.indexWhere(
        (saved) => saved.id == profile.id,
      );
      profiles.insert(index < 0 ? profiles.length : index, profile);
      await repository.saveSetting(
        'outputProfiles',
        jsonEncode({
          'version': OutputProfile.version,
          'profiles': profiles.map((saved) => saved.toMap()).toList(),
        }),
      );
      outputProfiles = List.unmodifiable(profiles);
      _profilesPersisted = true;
    });
    _profileSaveQueue = operation.catchError((Object _) {});
    return operation;
  }

  ContentItem? contentFor(String id) => _content[id];
  PresentationSlide? get preview =>
      previewSlides.isEmpty ? null : previewSlides[previewIndex];
  PresentationSlide? get nextPreview => previewIndex + 1 < previewSlides.length
      ? previewSlides[previewIndex + 1]
      : null;
  ContentKind? get kindFilter => switch (page) {
    WorkspacePage.hymns => ContentKind.hymn,
    WorkspacePage.prayers => ContentKind.prayer,
    WorkspacePage.readings => ContentKind.reading,
    WorkspacePage.responses => ContentKind.response,
    _ => null,
  };

  void navigate(WorkspacePage next) {
    page = next;
    setQuery(query, immediate: true);
    notifyListeners();
  }

  void setQuery(String text, {bool immediate = false}) {
    query = text;
    _searchTimer?.cancel();
    final generation = ++_searchGeneration;
    Future<void> search() async {
      try {
        final matches = await repository.searchContent(text, kind: kindFilter);
        if (generation != _searchGeneration) return;
        results = matches.map((item) {
          final local = _content[item.id];
          final current =
              local != null && local.modifiedAt.isAfter(item.modifiedAt)
              ? local
              : item;
          _content[item.id] = current;
          return current;
        }).toList();
        notifyListeners();
      } catch (e) {
        error = 'Search failed: $e';
        notifyListeners();
      }
    }

    if (immediate) {
      unawaited(search());
    } else {
      _searchTimer = Timer(const Duration(milliseconds: 120), search);
    }
  }

  Future<void> selectContent(ContentItem item, {String? entryId}) async {
    await flushSave();
    selected = _content[item.id] ?? item;
    saved = !_dirtyIds.contains(selected!.id);
    selectedEntryId = entryId;
    previewIndex = 0;
    _compile();
    notifyListeners();
  }

  void selectSlide(int index) {
    if (index >= 0 && index < previewSlides.length) {
      previewIndex = index;
      notifyListeners();
    }
  }

  void edit({String? title, String? sourceText, ContentKind? kind}) {
    final item = selected;
    if (item == null) return;
    if ((title == null || title == item.title) &&
        (sourceText == null || sourceText == item.sourceText) &&
        (kind == null || kind == item.kind)) {
      return;
    }
    _replaceDraft(
      item.copyWith(
        title: title,
        sourceText: sourceText,
        kind: kind,
        resetStructure: sourceText != null && sourceText != item.sourceText,
      ),
    );
  }

  DateTime _nextModified(ContentItem item) {
    final now = DateTime.now().toUtc();
    return now.isAfter(item.modifiedAt)
        ? now
        : item.modifiedAt.add(const Duration(microseconds: 1));
  }

  void _appendHistory(
    Map<String, List<ContentItem>> history,
    ContentItem item,
  ) {
    final snapshots = history.putIfAbsent(item.id, () => []);
    snapshots.add(item);
    if (snapshots.length > 100) snapshots.removeAt(0);
  }

  void _replaceDraft(ContentItem item, {bool recordUndo = true}) {
    final previous = selected;
    if (previous == null || previous.id != item.id) {
      throw StateError('Select this content before editing it.');
    }
    if (recordUndo) {
      _appendHistory(_undo, previous);
      _redo.remove(item.id);
    }
    selected = item.copyWith(modifiedAt: _nextModified(previous));
    _content[item.id] = selected!;
    _dirtyIds.add(item.id);
    saved = false;
    _compile();
    _journalTimer?.cancel();
    _journalTimer = Timer(
      const Duration(milliseconds: 75),
      () => unawaited(flushJournal().catchError((Object _) {})),
    );
    _autosave?.cancel();
    _autosave = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(flushSave().catchError((Object _) {})),
    );
    notifyListeners();
  }

  void undoEdit() {
    final item = selected;
    if (item == null || !canUndo) return;
    _appendHistory(_redo, item);
    _replaceDraft(_undo[item.id]!.removeLast(), recordUndo: false);
  }

  void redoEdit() {
    final item = selected;
    if (item == null || !canRedo) return;
    _appendHistory(_undo, item);
    _replaceDraft(_redo[item.id]!.removeLast(), recordUndo: false);
  }

  void undo() => undoEdit();
  void redo() => redoEdit();

  Future<List<ContentItem>> versions() async =>
      selected == null ? const [] : repository.contentVersions(selected!.id);

  void applyStructure(ContentStructure structure, {ContentKind? detectedKind}) {
    final item = selected;
    if (item == null) return;
    if (!structure.matches(item.sourceText)) {
      throw StateError(
        'The source changed. Review its current structure before applying.',
      );
    }
    _replaceDraft(item.copyWith(kind: detectedKind, structure: structure));
  }

  void resetStructure() {
    final item = selected;
    if (item == null || item.structure == null) return;
    _replaceDraft(item.copyWith(resetStructure: true));
  }

  /// Recognition is a suggestion only. Accepting it changes the draft's
  /// reversible structure without rewriting even one character of its source.
  void applyRecognition(
    ContentRecognition suggestion, {
    bool useDetectedKind = true,
  }) {
    final item = selected;
    if (item == null) return;
    if (!suggestion.structure.matches(item.sourceText)) {
      throw StateError(
        'The source changed. Review the current recognition suggestion.',
      );
    }
    _replaceDraft(
      item.copyWith(
        kind: useDetectedKind ? suggestion.detectedKind : item.kind,
        structure: suggestion.structure,
      ),
    );
  }

  ContentStructure _structureFor(ContentItem item) =>
      item.structure?.matches(item.sourceText) == true
      ? item.structure!
      : ContentStructure.fromSource(item.sourceText);

  void splitAtSourceOffset(int offset) {
    final item = selected;
    if (item == null) return;
    _replaceDraft(
      item.copyWith(structure: _structureFor(item).withSplit(offset)),
    );
  }

  void mergeSelectedWithNext() {
    final item = selected;
    final next = nextPreview;
    final offset = next?.sourceStart;
    if (item == null || offset == null) return;
    final count = previewSlides.length;
    _replaceDraft(
      item.copyWith(structure: _structureFor(item).withMergedBreak(offset)),
    );
    if (previewSlides.length >= count) {
      message =
          'Sections combined. Text that exceeds the safe area still spans multiple slides.';
    }
  }

  void setSectionKind(String sectionId, SectionKind kind) {
    _updateSection(sectionId, kind: kind);
  }

  void renameSection(String sectionId, String label) {
    _updateSection(sectionId, label: label);
  }

  void updateSection(String id, {SectionKind? kind, String? label}) =>
      _updateSection(id, kind: kind, label: label);

  void _updateSection(String id, {SectionKind? kind, String? label}) {
    final item = selected;
    if (item == null) return;
    final structure = _structureFor(item);
    if (!structure.sections.any((section) => section.id == id)) {
      throw StateError('The section is no longer available.');
    }
    final sections = structure.sections
        .map(
          (section) => section.id == id
              ? ContentSection(
                  id: section.id,
                  kind: kind ?? section.kind,
                  label: label ?? section.label,
                  text: section.text,
                  start: section.start,
                  end: section.end,
                )
              : section,
        )
        .toList();
    _replaceDraft(
      item.copyWith(
        structure: ContentStructure(
          originalSource: structure.originalSource,
          sections: sections,
          splitOffsets: structure.splitOffsets,
          mergedBreaks: structure.mergedBreaks,
        ),
      ),
    );
  }

  /// Restoring is itself a new editable revision. It never deletes history or
  /// changes the captured live deck, and can be undone like any other edit.
  Future<void> restoreVersion(ContentItem version) async {
    if (selected?.id != version.id) {
      throw StateError('Select the content that owns this version first.');
    }
    final current = selected!;
    // Keep the current correction in stable history before changing it. A
    // concurrent edit or selection must be reviewed instead of overwritten.
    await flushSave();
    if (selected?.id != current.id ||
        selected?.modifiedAt != current.modifiedAt) {
      throw StateError(
        'The draft changed while saving. Review the version again.',
      );
    }
    _replaceDraft(version);
    await flushSave();
    message = 'Version restored as a new revision. Publish when ready.';
    notifyListeners();
  }

  Future<void> flushJournal() async {
    _journalTimer?.cancel();
    final snapshots = _dirtyIds.map((id) => _content[id]!).toList();
    final operation = _journalQueue.then((_) async {
      for (final snapshot in snapshots) {
        await repository.saveDraft(snapshot);
      }
    });
    _journalQueue = operation.catchError((Object _) {});
    try {
      await operation;
    } catch (e) {
      error = 'Draft recovery journal could not be saved: $e';
      if (!_disposed) notifyListeners();
      rethrow;
    }
  }

  void _compile() {
    final generation = ++_layoutGeneration;
    final item = selected;
    final preparedTheme = theme;
    if (item != null &&
        item.sourceText.length > 2500 &&
        item.sourceText.length <= 50000) {
      final index = previewIndex;
      layoutPending = true;
      layoutError = null;
      previewSlides = [];
      unawaited(_compileLongDraft(item, preparedTheme, generation, index));
      return;
    }
    layoutPending = false;
    try {
      previewSlides = item == null
          ? []
          : SlideLayout.compile(item, preparedTheme);
      previewIndex = previewSlides.isEmpty
          ? 0
          : previewIndex.clamp(0, previewSlides.length - 1);
      layoutError = null;
    } catch (e) {
      layoutError = '$e';
      previewSlides = [];
      previewIndex = 0;
    }
  }

  Future<void> _compileLongDraft(
    ContentItem item,
    PresentationTheme preparedTheme,
    int generation,
    int requestedIndex,
  ) async {
    try {
      final slides = await SlideLayout.compileAsync(
        item,
        preparedTheme,
        isCancelled: () => _disposed || generation != _layoutGeneration,
      );
      if (_disposed || generation != _layoutGeneration) return;
      previewSlides = slides;
      previewIndex = slides.isEmpty
          ? 0
          : requestedIndex.clamp(0, slides.length - 1);
      layoutError = null;
    } catch (e) {
      if (_disposed || generation != _layoutGeneration) return;
      previewSlides = [];
      previewIndex = 0;
      layoutError = 'Could not prepare the draft layout: $e';
    }
    if (_disposed || generation != _layoutGeneration) return;
    layoutPending = false;
    notifyListeners();
  }

  Future<void> flushSave() async {
    _autosave?.cancel();
    _journalTimer?.cancel();
    final contentId = selected?.id;
    if (contentId == null || !_dirtyIds.contains(contentId)) return _saveQueue;
    Object? failure;
    _saveQueue = _saveQueue.then((_) async {
      try {
        // Take the current draft when this queued operation runs, and drain
        // corrections made during each write before navigation/quit proceeds.
        // A second queued flush must never rewrite an older captured snapshot.
        while (_dirtyIds.contains(contentId)) {
          final snapshot = _content[contentId]!;
          // The database worker serializes journal and commit requests. Saving
          // does not depend on an optional background journal task succeeding.
          await repository.saveDraft(snapshot);
          await repository.saveContent(snapshot);
          if (_content[contentId]?.modifiedAt == snapshot.modifiedAt) {
            _dirtyIds.remove(contentId);
            _recoveredDraftIds.remove(contentId);
          }
        }
        saved = !_dirtyIds.contains(selected?.id);
        message = null;
      } catch (e) {
        error = 'Draft could not be saved: $e';
        failure = e;
      }
      if (!_disposed) notifyListeners();
    });
    await _saveQueue;
    if (failure != null) throw StateError(error!);
  }

  Future<void> createContent(String title, ContentKind kind) async {
    await flushSave();
    final item = ContentItem(
      id: newId(),
      title: title,
      kind: kind,
      sourceText:
          'Enter your text here.\n\nAdd another section, or use a line with --- to split slides.',
      modifiedAt: DateTime.now(),
    );
    await repository.saveContent(item);
    _content[item.id] = item;
    page = WorkspacePage.library;
    query = '';
    setQuery('', immediate: true);
    await selectContent(item);
  }

  Future<void> toggleFavorite(ContentItem item) async {
    await flushSave();
    final current = _content[item.id] ?? item;
    final updated = current.copyWith(
      favorite: !current.favorite,
      modifiedAt: DateTime.now(),
    );
    _content[item.id] = updated;
    if (selected?.id == item.id) selected = updated;
    await repository.saveContent(updated);
    if (_content[item.id]?.modifiedAt == updated.modifiedAt) {
      _dirtyIds.remove(item.id);
      _recoveredDraftIds.remove(item.id);
    }
    saved = !_dirtyIds.contains(selected?.id);
    setQuery(query, immediate: true);
  }

  Future<void> chooseService(ServicePlan plan) async {
    await flushSave();
    service = plan;
    await repository.saveSetting('activeService', plan.id);
    if (plan.items.firstOrNull case final entry?) {
      final item =
          _content[entry.contentId] ??
          await repository.getContent(entry.contentId);
      if (item != null) {
        _content[item.id] = item;
        await selectContent(item, entryId: entry.id);
      }
    } else {
      selectedEntryId = null;
    }
    notifyListeners();
  }

  Future<void> createService(String title, {bool duplicate = false}) async {
    final plan = ServicePlan(
      id: newId(),
      title: title,
      modifiedAt: DateTime.now(),
      items: duplicate
          ? (service?.items ?? [])
                .map((e) => e.copyWith(id: '${newId()}-${e.id}'))
                .toList()
          : [],
    );
    await repository.saveService(plan);
    services = await repository.listServices();
    await chooseService(plan);
    page = WorkspacePage.services;
    notifyListeners();
  }

  Future<void> _saveService(ServicePlan plan) async {
    await repository.saveService(plan);
    service = plan;
    services = await repository.listServices();
    notifyListeners();
  }

  Future<void> addToService(ContentItem item) async {
    final plan = service;
    if (plan == null) throw StateError('Create a service first.');
    await _saveService(
      plan.copyWith(
        items: [
          ...plan.items,
          ServiceEntry(id: newId(), contentId: item.id, label: item.title),
        ],
        modifiedAt: DateTime.now(),
      ),
    );
    message = 'Added “${item.title}” to ${plan.title}.';
    notifyListeners();
  }

  Future<void> removeEntry(String entryId) async {
    final plan = service;
    if (plan == null) return;
    await _saveService(
      plan.copyWith(
        items: plan.items.where((e) => e.id != entryId).toList(),
        modifiedAt: DateTime.now(),
      ),
    );
    if (selectedEntryId == entryId) selectedEntryId = null;
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final plan = service;
    if (plan == null) return;
    final items = plan.items.toList();
    if (newIndex > oldIndex) newIndex--;
    items.insert(newIndex, items.removeAt(oldIndex));
    await _saveService(plan.copyWith(items: items, modifiedAt: DateTime.now()));
  }

  Future<void> applyTheme(PresentationTheme value) async {
    SlideLayout.validateTheme(value);
    theme = value;
    _compile();
    notifyListeners();
    await repository.saveSetting(
      'presentationTheme',
      jsonEncode(value.toMap()),
    );
  }

  Future<void> toggleDark() async {
    dark = !dark;
    notifyListeners();
    await repository.saveSetting('darkMode', '$dark');
  }

  Future<void> openOutput() async {
    final prepared = _outputProfileDraft;
    final profile = _outputProfileDraft.copyWith(
      name: _outputProfileDraft.name.trim(),
    );
    profile.validate();
    await refreshDisplays();
    if (displayError != null) throw StateError(displayError!);
    final target = displays.where((d) => d.id == profile.displayId).firstOrNull;
    if (profile.displayId != null && target?.isOutputEligible == false) {
      throw StateError(
        target?.unavailableReason ??
            'This display cannot be safely identified. Use extended displays, refresh, and select the destination again.',
      );
    }
    if (profile.displayId != null &&
        !displays.any((d) => d.id == profile.displayId && !d.isPrimary)) {
      throw StateError(
        'The profile’s secondary display is unavailable. Its target is remembered. Reconnect it or explicitly choose windowed rehearsal.',
      );
    }
    await output.open(
      targetDisplayId: profile.displayId,
      fullscreen: !profile.isRehearsal,
      scale: profile.scale,
      safeInset: profile.safeInset,
    );
    live.reconcileOutput(
      output.recoveredFrame ?? const OutputFrame(revision: 0),
    );
    appliedOutputProfile = profile;
    await _persistOutputProfile(profile);
    if (_selectedOutputProfileId == profile.id) {
      await repository.saveSetting('activeOutputProfile', profile.id);
    }
    await repository.saveSetting('preferredDisplay', profile.displayId ?? '');
    if (_outputProfileDraft == prepared) {
      _outputProfileDraft = profile;
      _preparedProfiles.remove(profile.id);
    }
    message = profile.isRehearsal
        ? 'Windowed rehearsal is ready.'
        : 'Presentation display is ready.';
    notifyListeners();
  }

  Future<bool> publishSelected() async {
    final requested = selected;
    if (_disposed ||
        preparingPublication ||
        requested == null ||
        layoutError != null) {
      return false;
    }
    final requestedTheme = theme;
    final requestedIndex = previewIndex;
    final requestedEntry = selectedEntryId;
    final plan = requestedEntry == null ? null : service;
    final items = plan == null
        ? <(String?, ContentItem)>[(null, requested)]
        : plan.items
              .map((entry) => (entry.id, _content[entry.contentId]))
              .where((entry) => entry.$2 != null)
              .map((entry) => (entry.$1, entry.$2!))
              .toList();
    if (plan != null && !items.any((entry) => entry.$1 == requestedEntry)) {
      error =
          'The selected service entry changed. Select it again before publishing.';
      notifyListeners();
      return false;
    }
    final generation = ++_publicationGeneration;
    preparingPublication = true;
    notifyListeners();
    try {
      final deck = <PresentationSlide>[];
      var index = requestedIndex;
      for (final (entryId, item) in items) {
        final slides = await SlideLayout.compileAsync(
          item,
          requestedTheme,
          isCancelled: () => _disposed || generation != _publicationGeneration,
        );
        if (_disposed || generation != _publicationGeneration) return false;
        if (entryId == requestedEntry) {
          if (requestedIndex >= slides.length) return false;
          index = deck.length + requestedIndex;
        }
        deck.addAll(slides);
      }
      if (deck.isEmpty) return false;
      if (!output.connected) await openOutput();
      if (_disposed || generation != _publicationGeneration || live.busy) {
        return false;
      }
      final success = await live.goLive(deck, index);
      if (success) {
        // Recovery is deliberately stored as history, never auto-published at boot.
        unawaited(
          repository
              .saveSetting('lastPublished', jsonEncode(live.frame.toMap()))
              .catchError(
                (Object e) => reportError(
                  'Output is live, but local history could not be saved: $e',
                ),
              ),
        );
        unawaited(
          repository
              .recordPresentation(requested.id)
              .catchError(
                (Object e) => reportError(
                  'Output is live, but usage history could not be saved: $e',
                ),
              ),
        );
      }
      return success;
    } catch (e) {
      if (_disposed || generation != _publicationGeneration) return false;
      error = 'Could not prepare the requested presentation: $e';
      notifyListeners();
      return false;
    } finally {
      preparingPublication = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<String> backup() async {
    await flushSave();
    final directory = Directory(
      '$dataDirectory${Platform.pathSeparator}backups',
    );
    await directory.create(recursive: true);
    final path =
        '${directory.path}${Platform.pathSeparator}cantivra-${newId()}.sqlite';
    await repository.backup(path);
    message = 'Backup saved: $path';
    notifyListeners();
    return path;
  }

  void reportError(Object e) {
    error = '$e';
    notifyListeners();
  }

  void showMessage(String value) {
    error = null;
    message = value;
    notifyListeners();
  }

  void clearNotice() {
    error = null;
    message = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _layoutGeneration++;
    _publicationGeneration++;
    unawaited(_displayChanges.cancel());
    _autosave?.cancel();
    _journalTimer?.cancel();
    _searchTimer?.cancel();
    live.removeListener(_forward);
    output.removeListener(_forward);
    live.dispose();
    super.dispose();
  }
}
