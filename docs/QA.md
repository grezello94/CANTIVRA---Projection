# Verification and release checklist

This document is a test plan and evidence template. Unchecked items are unverified, even when the corresponding code exists. Automated tests cannot establish physical HDMI reliability.

## Verification commands

Run from the repository root using the project's configured Flutter SDK:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build macos --debug
flutter run -d macos
```

On a Windows development host with the Flutter Windows prerequisites:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build windows --debug
flutter run -d windows
```

Debug builds verify compilation and behavior. Performance measurements and packaging checks require profile/release builds. Generated files, build artifacts and user databases are excluded from source control. Test databases must use temporary directories and must never target the real application support database.

## Phase 1 automated scenarios

| Area | Scenario | Required assertion |
| --- | --- | --- |
| Database | Create, close and reopen a library | Saved title, text, kind, tags and ordering remain unchanged. |
| Migrations | Open a new database and reopen it | Schema version is correct; seeding is idempotent and does not replace edits. |
| Search | Query title, body and a partial prefix | Intended results appear; unrelated results do not outrank exact title matches. |
| Search input | Quotes, punctuation, SQL-looking strings, empty input | No query exception or SQL injection; behavior is documented. |
| FTS maintenance | Edit title/body and search old/new terms | New text is searchable and removed text no longer matches. |
| Service | Add and reorder items, reopen database | Position and references are preserved. |
| Service | Remove one service item | Library content remains present. |
| Draft/live | Publish A, select B, edit B | Output snapshot and live cursor still refer to A. |
| Draft/live | Publish A, edit A's text/style | Live values remain unchanged until explicit publish. |
| Navigation | Publish service then change operator selection | Live next/previous follow committed service order. |
| Boundaries | Previous at first / next at last slide | No crash, unexpected wrapping or empty frame. |
| Black/clear | Toggle black and clear-text independently | Black hides everything; clear retains background; live snapshot retained. |
| Freeze | Freeze, edit/select/navigate, restore | Freeze semantics match the UI and the accepted slide is stable. |
| Emergency | Freeze and queue navigation then stop | Black takes precedence; stale work cannot reveal content afterward. |
| Failed output | Simulate rejected/failed transport command | Keep prior live state and expose a useful operator error. |
| Recovery | Close/reopen after saving changes | Persistent content/service restored; output does not auto-publish. |
| UI | Render compact and normal desktop constraints | Primary controls remain usable and no overflow exceptions occur. |
| UI | Switch navigation section and application theme | No implicit publish; readable selection/status remains. |

## Native two-window acceptance test

Perform first on the development display, then on an extended external display:

1. Launch the built desktop app with networking disabled.
2. Create a hymn titled “Acceptance test” with two slides separated using the implemented slide split convention.
3. Add it to a saved service and select its first slide.
4. Open the output window. Verify it is a separate OS window containing only the presentation and initially shows black.
5. Select the intended display and enter full screen. Verify the operator stays on the laptop display.
6. Use Go Live. Verify slide 1 appears in the output window and live monitor reflects the accepted slide.
7. Open another item and edit its text. Verify output still shows slide 1.
8. Return to the live item and correct a word. Verify preview changes while the output retains its old word.
9. Publish the corrected slide. Verify the output changes once to the prepared text.
10. Use next, previous and jump. Verify selected/live identities and sequence boundaries remain consistent.
11. Exercise black, clear text, background visibility, freeze, restore and emergency stop. Verify every control follows its documented behavior.
12. Close the output window, reopen it, and verify safe initial/recovery behavior. Deliberately publish again.
13. Restart the application and verify the created item, edits and service order persist. Verify output does not auto-publish.

Record OS/build, app commit, display setup and pass/fail per step. A screenshot of two windows supports visual inspection but does not substitute for testing state transitions.

## Physical display matrix

Execute on both Windows and macOS; record actual hardware rather than checking an assumed generic “desktop” result.

| Setup | Verify |
| --- | --- |
| Laptop only | Deliberate primary-display rehearsal; returning from full screen is possible. |
| 1920 × 1080 HDMI secondary | Only congregation output appears on the TV; safe margins and aspect ratio correct. |
| 3840 × 2160 HDMI secondary | Identical composition at 4K, clean text, no logical/physical pixel mix-up. |
| Mixed DPI/scaling | 100%/150%/200% Windows and Retina/non-Retina macOS; window lands on intended bounds. |
| Secondary left of primary | Negative screen coordinates do not move the window onto the operator display. |
| Secondary above primary | Vertical origin conversion is correct. |
| Unequal aspect ratio | Uniform letterboxing; no stretching or cropping. |
| HDMI splitter/distribution | All downstream TVs show the same slide and black command. Note hardware/EDID limitations. |
| Display disconnect while live | Operator remains usable; no presentation window migrates visibly onto the operator desktop. |
| Reconnect same display | Status recovers; intentional restoration uses the expected screen. |
| Reconnect different display | Identity mismatch is clear; no blind publish to a guessed screen. |
| Change resolution while live | Text and background retain aspect ratio and safe margins. |
| Change OS scaling while live | No crop, misplaced window or operator-control leak. |
| Sleep/wake and lock/unlock | Correct status and controlled restoration; document OS behavior. |
| macOS Spaces | Test “Displays have separate Spaces” enabled/disabled and operator focus during full screen. |
| Window focus changes | File dialogs, search, settings and editor never appear on output. |

Use a camera or capture card if checking visible flash/flicker. Renderer ACK timing is not a physical-display latency measurement.

## Failure and recovery matrix

- [ ] Start a new operator against a damaged or newer library while its renderer is live. Confirm the same process/frame remains, emergency black is available, Retry does not replace the library, and no new renderer opens.
- [ ] Recover storage, use Retry, and confirm the normal workspace adopts the renderer's latest emergency state without publication.
- [ ] Enter a second correction while the first correction is saving, navigate away, and reopen. Both the content and recoverable draft must retain the latest correction.
- [ ] Enter a correction while native Quit awaits renderer shutdown. Confirm the last valid edit is saved; an invalid/failed save must leave the operator open with a useful error.
- [ ] Repeat native Quit while saving or while a refused request settles. The pending save must not be bypassed. Check macOS shutdown/logout separately, including cancellation while edits cannot save.
- [ ] Dispose an output controller during discovery/handshake/configuration. No late connection, polling or replacement process may be adopted; the existing frame must remain unchanged.
- [ ] Search with an inaccessible/busy database while an accepted slide is live; output stays unchanged.
- [ ] Save failure from read-only directory or simulated disk full; draft remains recoverable and error is visible.
- [ ] Interrupted migration leaves prior database readable; no reset or reseed over user content.
- [ ] Unexpected operator termination after an acknowledged save retains committed records on restart.
- [ ] Corrupt or unknown-version database is preserved and produces an actionable error.
- [ ] Force import worker failure; live snapshot remains unchanged and partial staging is cleaned up.
- [ ] Force invalid output payload/stale revision; renderer rejects it and retains last good slide.
- [ ] Delay older publish response until after a newer command; older state cannot become visible or mark live status incorrectly.
- [ ] Close output window during publication; operator reports lost connection and can deliberately reopen.
- [ ] Disconnect HDMI during a freeze/black state; reconnection never flashes hidden content.
- [ ] Before claiming process isolation: kill operator process and confirm renderer continues its accepted frame.
- [ ] Before claiming media isolation: fail decoding/playback while a slide is live; no operator error UI reaches congregation.

## Layout and theme corpus

Later layout phases require fixtures for:

- Short hymn verses, repeated choruses and verse/refrain alternation.
- Very long reading with paragraphs and sentence punctuation.
- Speaker labels and congregation responses.
- Tamil, Malayalam, Hindi, English and other supported scripts, including combining marks and fallback fonts.
- Long unbroken token, URL, whitespace-only input and empty sections.
- Large font and safe margins leaving less than one line of available height.
- Theme background, opacity, outline, shadow, line/paragraph spacing and vertical alignment.
- Recalculation after font, size, output geometry and safe-margin changes.

Assertions include no lost/duplicated text, legal line breaks, visible overflow reporting, stable manual splits, preview/output equivalence and no live snapshot mutation during draft relayout. Golden images are useful for regressions; geometry assertions must also verify safe bounds.

## Import/export and backup corpus

Add format-specific fixtures only as adapters are implemented:

- TXT with UTF-8 BOM, CRLF/LF, non-Latin text and large paragraphs.
- OpenLyrics with namespaces, verse ordering, repeated chorus references and metadata.
- PDF with embedded/nonembedded fonts, scanned pages, portrait/landscape and large images.
- PPTX with text, images, gradients, grouped shapes, missing fonts, transitions and unsupported embedded content. Mark faithful/editable capability independently.
- Packages with duplicate IDs, conflicting versions, missing assets, invalid manifests and path traversal attempts.
- Round-trip a library/service with themes and media; compare supported fields, hashes and references.
- Create backup during edits, validate integrity, restore to a fresh directory and compare record counts and asset checksums.
- Reject malformed/unsupported backup without changing the current library.

## Performance procedure

1. Use a profile/release build, note exact commit, SDK, OS, CPU/GPU, RAM and displays.
2. Seed 10,000 deterministic text records including short and long multilingual content.
3. Run 100 title/body/prefix/phrase queries. Report median/p95/max and distinguish debounce from actual query time.
4. Capture 1,000 prepared slide commands, renderer acceptance times and Flutter frame timings. Repeat while searching and saving drafts.
5. Compare 1080p and 4K output and watch for visible black frames during rapid navigation.
6. Record combined process memory after startup, after warm caches and every 30 minutes during an eight-hour service simulation.
7. Introduce failed imports, display changes and worker exceptions during the soak.
8. Compare with the architecture budgets and explain deviations; do not declare a target met from a single favorable sample.

## Session evidence

Populate this section only with observed results:

| Date / build | Host | Check | Result / limitation |
| --- | --- | --- | --- |
| 2026-11-04, repository inspection | macOS 26.5.2 | Initial workspace/tool discovery | Empty workspace; Flutter/Dart/Xcode/Clang available; Windows hardware execution not available from this host. |
| 2026-11-04, Phase 1 development | macOS 26.5.2, Flutter test runner | `flutter test test/presentation --reporter expanded` | 27 tests passed. Covers draft/live text and theme separation, captured service navigation, ACK failures, freeze/restore/emergency ordering, frame validation, measured pagination and canvas modes. No physical display claim. |
| 2026-11-04, Phase 1 development | macOS 26.5.2, Flutter widget runner with bundled Roboto and mocked native output | `flutter test test/widget_test.dart --reporter expanded` | 6 tests passed. All 9 sidebar pages render without overflow at 1440 × 900 and 1180 × 760. Real temporary SQLite supports the new-content dialog, search and add-to-service flow; source/theme changes remain in preview until explicit publication; output controls work through the real controller. Screenshot artifact: `build/qa/operator-1440x900.png`. Native hardware and exact output-font fidelity are separate tests. |
| 2026-11-04, Phase 1 development | macOS 26.5.2, real temporary SQLite files | Repository tests | Storage agent observed 14 functional tests passed for persistence, FTS maintenance, versions, transactional rollback, service ordering, settings, backup, integrity and safe startup failure. |
| 2026-11-04, Phase 1 development | macOS 26.5.2, Flutter test runner | `test/data/search_performance_test.dart` local microbenchmark | Storage agent observed 2,000 generated records plus 5 samples; 50 warmed searches p50 0.11 ms / p95 0.16 ms. Caller-isolate heartbeat progressed during work. This does not validate the 10,000-record Windows/macOS release budget. |

## Release sign-off

Before a live-service production release, attach automated results, native build logs, display matrix results, backup/restore results, performance measurements and volunteer workflow observations. Record remaining defects and their operational consequences. No feature should be marked complete solely because it has a button, a model type or a successful compile.


The consolidated final Phase 1 run passed **72 tests**, static analysis, formatting, macOS native build, and the release native process smoke. See [VERIFICATION.md](VERIFICATION.md) for exact scope, timings, artifacts, shutdown results and outstanding platform/hardware gates.

## Phase 2 observed results — 5 November 2026

Cantivra **0.2.0+2** passed **158 automated tests**, formatting and static analysis on the macOS host. The sandboxed release native smoke passed separate-process publication, frame ordering, editing isolation, explicit profile application, renderer replacement, save-before-quit and normal renderer shutdown. Forced operator termination left the renderer visible with the same frozen frame; a new operator reconnected and controlled it while keeping the saved draft separate.

The 40-command native sample measured frame-ready ACK p50 16.702 ms and p95 20.780 ms. This is windowed local timing, not physical HDMI latency or full performance acceptance. The normal macOS application was rebuilt after the harness, development-signed, verified and archived with a SHA-256 manifest. An extra main-app startup probe was skipped to avoid interfering with an existing running app.

See [PHASE2_VERIFICATION.md](PHASE2_VERIFICATION.md) for artifact details, scope and recovery boundaries. The physical display, Windows runtime, trusted distribution and extended soak gates above remain unverified. Historical Phase 1 entries are retained as their original observations.

## Phase 3 observed results — 5 November 2026

Cantivra **0.3.0+3** passed **210 tests**, formatting and static analysis. Its native release harness passed **1,000 transitions** with search/autosave work, structured typography publication, revision restoration and overflow rejection without live mutation, renderer replacement, normal shutdown and operator-crash recovery of a journal-only correction. A native covered-rehearsal-window timeout found during verification was corrected and the complete native run passed afterward.

The full-suite search sample used 10,005 records: targeted query p50 0.94 ms/p95 1.97 ms/max 2.97 ms, broad 10,001-result query 97.09 ms. A 21,839-character fixture prepared incrementally with event-loop progress. Native frame-ready ACK p50 was 16.650 ms, p95 18.025 ms and max 208.859 ms. The maximum spike and unbounded broad results remain relevant performance limitations; physical scanout and long-duration memory/reliability are separate gates.

The widget workflows exercise reviewed section labels/types, manual boundaries, layout changes, saved-version restore, editor synchronization, global F12 while a modal has focus, and unchanged live output until an explicit action. See [PHASE3_VERIFICATION.md](PHASE3_VERIFICATION.md) for logs, artifacts, migration and recovery scope. Execute remaining Windows/HDMI/signing acceptance using [PHASE2_ACCEPTANCE.md](PHASE2_ACCEPTANCE.md).

## Additional native acceptance — version 0.3.1

Actual macOS font rendering passed 18 cases/94 pages with source conservation, safe text-box geometry and stable live output; 36 PNGs were exported. The 60.094-second memory/navigation/search/autosave run passed 514 transitions, explicitly without eight-hour sign-off. Regression checks also cover mixed CJK/Latin overflow, authenticated RSS diagnostics and refusal to run a replaced AOT binary through `--no-build`. Read [PHASE23_STATUS.md](PHASE23_STATUS.md) before proceeding: Windows and physical evidence are still pending and Phase 4 is not started.

## Local completion work — version 0.3.2

The final regression suite passes **223 tests**; formatting of **48 Dart files** and static analysis pass. The native process-fault smoke passes 1,000 transitions plus renderer replacement, operator death/recovery, draft journaling and macOS save-before-close. The Windows identity policy passes 15 compiled portable C++ checks; its actual Win32 API adapter remains uncompiled on this host.

The native acceptance harness now mounts the actual operator UI with a complete 10,005-record cache. Its 65.080-second release run passes 552 transitions, 100 verified searches after warmup, 100 edits through painted operator widgets, rollback/rejected draft/rejected frame checks and four real socket disconnect/reconnect cases. It records zero operator Flutter errors, source conservation across 94 native-font pages, seven RSS observations, final integrity and normal shutdown. Native frame callbacks record actual window size/DPI instead of claiming a physical 1080p benchmark. Exact distributions, tail latency and limitations are in [PHASE23_STATUS.md](PHASE23_STATUS.md).

A native interruption test found and corrected a test-cleanup race. Read-only process status now confirms an already-exited renderer; authenticated shutdown handles a lost ACK, and a prior-operator disconnect race is retried. The repeated interruption check passes: partial evidence remains, its private workspace/runtime are removed, and the deliberately interrupted runner stays marked failed. Evidence: `build/qa/native-acceptance-interruption-result.json`.

An isolated eight-hour run started at 12:48 UTC on 5 November 2026 under `build/qa/native-acceptance/1793882896259914`. It was running at handoff and has not been accepted as complete. Read its status and report after completion. The normal app can be rebuilt while this captured runtime continues. Windows, physical display, reader review and full performance/distribution gates remain open.
