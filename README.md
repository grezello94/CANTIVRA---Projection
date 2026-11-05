# Cantivra

A native, offline-first church presentation application for **macOS and Windows**, built with Flutter and SQLite. This repository contains the working **0.3 desktop foundation**, not the complete production product.

## Run

Use Flutter **3.38.5 / Dart 3.10.4** or a compatible stable SDK. macOS requires Xcode; Windows requires Visual Studio's Desktop development with C++ workload and Windows SDK. The first dependency/build setup needs internet. Essential presentation features run offline afterward.

```sh
flutter pub get
flutter run -d macos
# On Windows:
flutter run -d windows
```

The macOS project uses Swift Package Manager; CocoaPods is not required. Windows must be built on Windows. Keep the complete release bundle together because it includes Flutter and SQLite native libraries. See [build instructions](docs/BUILD.md).

The current Mac development archive is [Cantivra 0.3.4](dist/Cantivra-macOS-0.3.4.zip). Extract it and open `cantivra.app`. Its normal main entrypoint, archive checksum and nested ad-hoc signatures are verified; trusted distribution signing remains pending.

When upgrading from 0.2, close the old operator and presentation windows first. Version 0.3 adds a transactional schema 2 migration; older builds reject the newer database. Keep a library backup from Settings before upgrading a working church library. Incompatible renderer versions are preserved and reported, never silently replaced during a service.

## Use the foundation

1. Open **Services** to choose or create a service. The first launch includes a small sample library and service.
2. Open **Library** or a content category. Search words or word prefixes; choose an item to preview it. Use **+** to add it to the current service. Drag service handles to change order.
3. Edit the source below the thumbnails. Blank lines or a line containing `---` split sections; `[Verse 1]` adds a section label. Larger sections paginate with measured font sizes. Original source is kept, and edits save locally.
4. In **Settings**, select a detected secondary display, then **Open output**. With one screen, choose windowed rehearsal. Set the operating system to extended display mode for HDMI projection.
5. Select a thumbnail and **Go live**. To present a prepared service, select its entry in the left **Running order** before publishing. Library publications contain only the chosen item's slides; Next is unavailable for a one-slide publication. Search, edit, change themes, and navigate the operator workspace without changing the congregation window. Next/previous navigate the captured published sequence, so draft changes cannot slip into it.
6. **Black**, **Clear text**, **Freeze**, **Restore**, **Background**, and **Emergency** act explicitly on output. Emergency blackout overrides freeze. Restore returns to the last published slide. Closing output keeps the workspace available.
7. Use the source editor's **tune** button to open **Structure**, **Layout**, and **History**. Review detected sections, change labels/types, and explicitly apply the suggestion. Place the source cursor between words before opening tools to split there, or merge the selected slide with the next. Original source text stays intact.
8. Adjust vertical/horizontal alignment, line/paragraph spacing and automatic/explicit text direction in Layout. Safe guides appear in preview only. Long drafts prepare incrementally; Go Live captures a complete prepared deck.
9. History previews saved revisions and restores one as a new revision. Undo/redo includes text and structural edits. A journaled correction recovered after a crash appears as a separate editable draft; review it before publishing.

| Shortcut | Action |
| --- | --- |
| Alt + Enter | Publish selected preview slide |
| Alt + Left / Right | Previous / next published slide |
| Alt + B | Black output |
| Alt + R | Restore output |
| F12 | Emergency black, including while frozen |
| Standard platform undo / redo | Undo / redo source text edits |

## Implemented and tested

- Native desktop shell with light/dark appearance, adjustable panel widths, focus mode, working sidebar and editor.
- Dedicated SQLite worker isolate; WAL, transactions, FTS5 prefix search, content revisions, service order, favorites, usage events and persistent settings.
- Local content creation/editing, automatic saves, service creation/duplication/reordering, unplanned items and return to the service.
- Shared measured 1920×1080 slide canvas with safe margins and proportional letterboxing. Source and theme changes recalculate preview only.
- Source-preserving, versioned verse/chorus/refrain/bridge/speaker/paragraph structure, reviewed offline recognition, manual splits/merges and section label/type overrides.
- Grapheme-safe measured pagination with RTL and script-aware line breaking, explicit overflow errors, line/paragraph spacing, vertical alignment and cancellable incremental preparation for long drafts.
- Transactional schema migration, a separate draft recovery journal, bounded per-item undo/redo, and saved-revision preview/restoration without changing live output.
- Separate renderer OS process with authenticated local communication, staged immutable publication, frame readiness acknowledgements, and automatic inspection of surviving output at operator startup. An operator crash does not terminate the renderer.
- Storage-independent startup recovery: a damaged or newer library leaves existing-output controls available, including emergency black. Retry preserves the database and adopts the authoritative renderer frame without publishing.
- Saved output profiles with explicit screen targets, 75–100% uniform scale, 0–12% safe inset, and a separate calibration preview. Changes apply only on Apply/open.
- Real macOS/Windows native display enumeration, primary-display protection, selected-display fullscreen placement, topology status and explicit re-arm after disconnect. Mac native software checks and scoped direct-Sony HDMI checks pass; the wider display matrix and Windows runtime remain unverified.
- Consistent SQLite backups that refuse overwriting an existing file, integrity checks and safe save-error handling.

## Verification

```sh
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test test
# Native process fault tests (uses temporary test workspaces):
dart run tool/run_native_smoke.dart macos
# Use windows instead of macos on a Windows host.
dart run tool/package_desktop.dart macos
# On Windows:
dart run tool/package_desktop.dart windows
```

The native smoke harness uses temporary test libraries. It verifies separate-process publishing, editing isolation, frame ordering, display role guards, renderer replacement, native Quit, and surviving output after forcibly terminating its test operator. It also opens the real recovery interface against a deliberately invalid test database, controls the surviving renderer, retries without replacing the corrupt fixture, and verifies save-before-Quit after recovery. Version 0.3.4 also verifies hidden-renderer survival with the same process, session and exact captured frame. All four completion markers pass in `build/qa/native-smoke-0.3.4-console.log`. The normal application was rebuilt and packaged afterward. Windows execution remains pending.

The package helper seals a local macOS development signature, verifies nested code, checks the archive, and records SHA-256 plus SDK/lockfile metadata. Windows packaging keeps all runtime files together; certificate signing is optional and requires an explicitly configured local certificate. See [build instructions](docs/BUILD.md).

## Current boundaries

This is a development foundation. Operator-crash isolation has been verified on macOS; the renderer still depends on its own process, graphics driver and OS. After recovery, the last frame is authoritative; resume a prepared service sequence through an explicit Go Live action. The guided direct-Sony functional subset at reported 4K/30 Hz passes black, normal and frozen unplug/reconnect with deliberate re-arm, physical Fn+F12 while frozen, background toggling, edit/live isolation, bottom-arrow service navigation, Clear text/Black/Restore states and normal save-and-Quit. The manual test session is closed with database integrity `ok` and both test processes exited. The wider HDMI/mixed-DPI/resolution matrix, reader review, full performance/endurance acceptance, signed installation and Windows runtime verification remain release gates. Native display IDs may change across OS topology changes and require reselection.

Phase 4 has not started. Local Phase 2/3 work continues while Windows hardware is unavailable; current evidence and remaining steps are in [PHASE23_STATUS.md](docs/PHASE23_STATUS.md). Follow [WINDOWS_TESTING.md](docs/WINDOWS_TESTING.md) on the Windows test machine. Its script keeps a separate evidence folder for each run, including OS/CPU/GPU/RAM, test logs, native font images and explicit manual gates. Developer ID is for trusted external distribution and is not required for local testing; [MAC_SIGNING_HELP.md](docs/MAC_SIGNING_HELP.md) explains how the app owner obtains it from Apple.

Version 0.3.3 adds independent startup recovery, isolates invalid saved themes, and drains the latest corrections before navigation or Quit, including edits entered while shutdown awaits acknowledgement. Disposed output controllers cannot adopt late connections or restart health polling. The current automated suite passes 255 tests with clean static analysis; native and endurance evidence is recorded by version in the status document.

Version 0.3.4 fixes macOS automatically terminating the hidden renderer after HDMI loss. Its native process and recovery checks pass. The isolated eight-hour 0.3.4 workload is **running, not complete**, in `build/qa/native-acceptance/1793903282052217`; its initial font/search/edit checks are partial evidence. Earlier endurance runs use older captured builds and cannot certify this change.

Windows monitor selection uses device paths instead of reusable GDI output names. Reselect a screen for any older saved Windows profile. Unknown or ambiguous targets are unavailable until safely identified; a saved ID is never replaced with a guessed screen. The identity policy passes portable C++ tests on this Mac, while Windows API compilation and real monitor testing remain pending.

Items have a 50,000-character limit. Long-item font measurement remains on the operator isolate and yields between bounded pages; this is cooperative scheduling, not a hard frame-time guarantee. Native font fallback and typographic quality need reader review on both platforms. Recognition currently targets English section/speaker labels and conservative vocabulary rules; other languages can retain their original Unicode text and use manual structure overrides. Repetition detection suggests metadata and never inserts additional text.

Undo/redo retains up to 100 edits per item in memory; saved revisions and the recovery journal survive restart. Journal writes are scheduled after 75 ms and become durable after the database acknowledges them; a crash before that acknowledgement can lose the latest keystrokes. Full theme authoring, system font enumeration/import, fuzzy search, collections, automatic backup retention, PDF/PPTX/OpenLyrics import/export, media playback, AI and network receivers belong to later milestones. Search currently uses literal ANDed prefix terms; quoted input does not promise adjacent-phrase matching, and broad queries have no general result limit. The Media section states its planned status. No PowerPoint compatibility is claimed.

See the [architecture and database design](docs/ARCHITECTURE.md), [phased roadmap](docs/ROADMAP.md), [QA and hardware checklist](docs/QA.md), [Phase 1 verification record](docs/VERIFICATION.md), [Phase 2 verification](docs/PHASE2_VERIFICATION.md), [remaining platform acceptance procedure](docs/PHASE2_ACCEPTANCE.md), [Phase 3 design](docs/PHASE3_PLAN.md), and [Phase 3 verification](docs/PHASE3_VERIFICATION.md).

Bundled Roboto fonts retain their [Apache 2.0 license](assets/fonts/Roboto_LICENSE.txt). Presentation fonts currently use installed system families.
