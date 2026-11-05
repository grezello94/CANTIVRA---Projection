# Phase 3 verification — Cantivra 0.3.0+3

Observed on 5 November 2026 on an Apple M1 with 16 GB RAM, macOS 26.5.2 (25F84), Flutter 3.38.5, Dart 3.10.4 and Xcode 26.2. Phase 3's core software is implemented and tested on this host. The outstanding Windows, physical display and trusted-distribution gates from Phase 2 remain open; this is a development release.

## Working functionality

- Source-preserving, versioned sections for verse, chorus, refrain, bridge, speaker, paragraph and custom content. Reviewed offline recognition exposes detected type, confidence and reasons; section labels/types are editable before explicit acceptance. Repeated text is suggested as metadata, never inserted into the source.
- Durable manual splits at source cursor positions and merges of adjacent boundaries, independent of original text. Structures retain mapped source offsets and reject omitted body text or invalid character boundaries. Source edits invalidate stale structure; undo can recover it.
- Actual-font pagination without automatic font shrinking, grapheme-safe boundaries, Skia/ICU line breaks for supported unspaced scripts, RTL/explicit direction, vertical/horizontal alignment and line/paragraph spacing. Overflow is an actionable operator error and blocks publication.
- Cancellable incremental layout for long drafts and captured service publication. Progress is visible, stale partial results are discarded, and live controls supersede pending publication. The renderer remains a separate OS process.
- Transactional schema 1→2 migration, a separate recovery journal, per-item undo/redo and revision preview/restoration. Restoring creates a new saved revision after preserving the current correction. Recovered journal text stays separate from committed content and surviving live output.
- Working Structure, Layout and History views accessible through the source editor's tune button. A persistent Apply action, source-controller synchronization after undo/restore and global F12 emergency handling operate at compact desktop sizes.

## Automated and native checks

| Check | Observed result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed lib test tool` | 40 Dart files checked, no formatting changes required. |
| `flutter analyze --no-pub` | No issues found. |
| `flutter test test --no-pub --reporter expanded` | **210 tests passed**, final log `build/qa/flutter-tests-phase3.log`. |
| `dart run tool/run_native_smoke.dart macos` | Release build and sandboxed native process tests passed; `NATIVE_SMOKE_OK`, `RECOVERY_SMOKE_OK`, `PHASE2_NATIVE_SMOKE_OK`. |
| Normal desktop package | Rebuilt from `lib/main.dart` after the test harness; development package verification and metadata recorded alongside the archive. |

The full suite covers SQLite persistence, migration preservation/rollback, FTS accuracy, draft/save races, uncommitted recovery, undo bounds, restored revisions, structured source conservation, multilingual pagination, measured paragraph geometry, theme validation, captured service navigation, live/preview separation, transport limits/authentication, rendering-version compatibility, display contracts, lost ACKs, emergency ordering and hidden-window paint readiness. The ten widget tests include actual structure/layout/history interactions with temporary SQLite at 1440 × 900 and 1180 × 760. Test engines use fixture fonts where required; a Unicode fixture is not native font or translation certification.

Visual inspection artifacts are `build/qa/operator-1440x900.png` and `build/qa/content-tools-1180x760.png`. They supplement working interaction assertions rather than replacing them.

## Native failure and recovery evidence

The updated release harness used temporary sandbox libraries and separate native processes. It exercised 1,000 transitions while searching and modifying/autosaving drafts; malformed/missing/primary display rejection; scale and safe inset; freeze/emergency/restore; source structure and explicit typography publication; saved-revision restoration without live changes; overflow refusal with last frame retained; forced renderer replacement starting black; save-before-quit; and normal renderer termination.

The crash fixture deliberately journaled a correction **without committing it**, then cancelled its stable autosave. The runner forcibly terminated only that test operator and authenticated to the surviving renderer, confirming the same visible frozen frame. A fresh operator adopted the frame, recovered the journal-only correction as an unsaved draft, verified that the library's committed text remained unchanged, and controlled emergency black and restore. Final evidence is in `build/qa/native-smoke-phase2.log`.

One earlier native run exposed a timeout when the operator covered the surviving rehearsal window and Flutter stopped scheduling normal frames. The fix skips redundant healthy configuration and completes real Flutter paint barriers using warm-up frames when hidden/vsync-starved. A dedicated hidden-lifecycle test asserts that normal/emergency ACKs follow `CustomPainter.paint` while the lifecycle stays hidden. The final native recovery run passed without moving the rehearsal window or requiring focus theft. No physical scanout guarantee is inferred.

## Recorded performance samples

These are local observations, not cross-platform performance certification. The full-suite run and release harness are distinct measurement modes.

| Measurement | Result | Scope |
| --- | --- | --- |
| FTS, 10,005 records, 20 warmups + 100 varied targeted queries | p50 0.94 ms; p95 1.97 ms; max 2.97 ms | Flutter-test repository calls, exact/prefix/title/multiword accuracy asserted; excludes UI debounce. |
| Broad query returning 10,001 records | 97.09 ms | Current API has no general result limit; quoted terms use AND/prefix semantics, not adjacent-phrase matching. |
| 21,839-character passage, 280 test-font pages | 462 ms total; 281 event-loop heartbeats; largest measured heartbeat gap 18.01 ms | Cooperative page preparation; fixture font and shared test-host load. Not a hard frame-time guarantee. |
| 1,000 native release transitions with search/draft workload | p50 16.650 ms; p95 18.025 ms; max 208.859 ms | Command-to-Flutter-frame-ready ACK, windowed rehearsal. Maximum spike remains relevant to further soak/performance work. |

The native sample does not measure television latency, HDMI distribution, mixed DPI, 4K, sustained memory use or an eight-hour service. Full reliability acceptance remains in [QA.md](QA.md) and [PHASE2_ACCEPTANCE.md](PHASE2_ACCEPTANCE.md).

## Development package and running

The normal app is `build/macos/Build/Products/Release/cantivra.app`. The versioned development archive is `dist/Cantivra-macOS-0.3.0.zip`; its `.sha256` and `.manifest.json` companions record archive integrity, SDK/lockfile metadata, normal entrypoint and ad-hoc signing status. Extract and open `cantivra.app`.

The verified archive contains 19,704,641 bytes. `codesign --verify --deep --strict` and ZIP integrity checks passed. Archive SHA-256:

```text
ed482a677bbed6244f25b8e241f6e988b1532c5b3df2d3d699b6d1d54aac3845
```

Before upgrading from 0.2, close both old operator and output windows and keep a Settings backup of any working church library. Schema 2 migration preserves records transactionally; 0.2 intentionally refuses the newer database. An incompatible surviving renderer is never killed, duplicated or republished automatically. Essential operation remains offline.

## Remaining boundaries

- Windows build execution was attempted on this Mac and the SDK returned `"build windows" only supported on Windows hosts.` Windows runner changes have source/contract review, not native compilation/runtime evidence here.
- No physical HDMI/4K/mixed-DPI or unplug/replug sign-off is claimed. Execute the acceptance matrix on both operating systems, including operator absence during cable loss.
- This host has an Apple Development identity and **no Developer ID Application identity**. The package uses its verified ad-hoc development signature; trusted direct distribution, notarization and clean-machine installation remain open. No identity details or credentials are included in logs.
- Recognition rules currently target English section/speaker labels and conservative scripture/prayer hints. Other Unicode text is retained and can use manual metadata overrides. Native complex-script typography requires font availability and reader review.
- One safe-area text region is supported. Multiple positioned text boxes, font import/enumeration, full theme authoring and additional style effects remain later scope.
- Undo retains 100 edits per item in memory; durable history is saved revisions and the journal. A crash before a journal write is acknowledged can lose recent keystrokes. Automatic rotating backups and full recovery tooling are later work.
- The 50,000-character limit, bounded shaping probes and pathological-character guards remain intentional. Incremental work shares the operator isolate; it does not establish hard real-time behavior. Renderer/GPU/OS/power failures remain outside operator-crash survival.
- No new PDF/PPTX/OpenLyrics/media/AI/network-receiver compatibility is claimed. Six later phases remain, Phases 4–9, with Phase 9 optional; the final production release gate is separate.

## Follow-up in version 0.3.1 — 5 November 2026

The mixed-script overflow review found that CJK context could allow an emergency line break inside an oversized Latin word. Pagination now rejects that unsafe split; its regression test passes. Authenticated renderer diagnostics expose real process RSS for sustained-operation checks. Native harnesses also reject an unknown/replaced AOT binary before `--no-build` can launch it against a real workspace.

The native font corpus passed **18 cases and 94 pages** across English, Tamil, Malayalam, Hindi, Arabic, Hebrew, Chinese, Thai and combining/emoji fixtures at two font sizes. Every actual rendered text box fit its safe area, source text was conserved, and the live frame remained unchanged. Thirty-six native PNGs were exported for review. This uses actual macOS fonts/fallback, distinct from the Flutter test-font fixtures above; Windows and linguistic reader sign-off remain pending.

A 60.094-second sustained run completed **514 transitions** with search and draft autosave. Sampled combined RSS went from 290,291,712 bytes after corpus capture to 186,957,824 bytes at the last sample. Frame-ready ACK p50 was 14.266 ms, p95 15.475 ms and max 28.023 ms, with a deliberate 100 ms interval between transitions. The report explicitly states `eightHourSoakCompleted: false`; this short sample cannot establish long-duration memory stability. Evidence is `build/qa/native-acceptance/report.json` and its PNGs; the final runner additionally writes unique run directories plus `latest-run.json`.

The updated crash/recovery harness also passed 1,000 transitions on the current runtime: p50 16.666 ms, p95 17.098 ms, max 207.782 ms. It retained the frame after operator termination and recovered the journal-only correction. Latest regression results are in `build/qa/flutter-tests-phase23-final.log`. The updated normal package is `dist/Cantivra-macOS-0.3.1.zip`, rebuilt after all harnesses.

The user confirmed that a Windows machine exists but is not available now. Phase 4 remains paused. See [PHASE23_STATUS.md](PHASE23_STATUS.md) for the exact remaining acceptance and [MAC_SIGNING_HELP.md](MAC_SIGNING_HELP.md) for the owner-issued Apple certificate process.

## Version 0.3.2 local follow-through

The current suite passes **223 tests** with 48 formatted Dart files and clean static analysis. A native run now keeps the real operator widgets mounted with all 10,005 records, measures 100 synthetic edits through completed build/layout/paint, and verifies that the congregation frame never changes during these edits. This excludes OS keyboard delivery and physical scanout; its p95 is 16.220 ms, with a 254.951 ms maximum retained in the evidence rather than hidden.

The 65.080-second actual-operator run, its native fonts, repeated socket recovery, rollback/rejected input scenarios, RSS observations and renderer timing scope are recorded in [PHASE23_STATUS.md](PHASE23_STATUS.md). The eight-hour run started separately and remains pending until its actual result is reviewed. [WINDOWS_TESTING.md](WINDOWS_TESTING.md) gives the deferred Windows checklist; physical HDMI checks are still required on the Mac too.

## Version 0.3.3 reliability closure

The suite now passes **255 tests**, with 52 Dart files formatted and no static-analysis issues. Additional tests cover invalid saved themes, recovery when content loading fails, latest-edit save ordering, storage-independent startup, recovery-interface actions, edits during Quit, and disposal during actual loopback handshakes/configuration. Recovery widget interactions run at 1180 × 760 and 800 × 600. The tests preserve deliberately invalid databases rather than resetting them.

The native Mac smoke exposed a pending-termination-loop problem in programmatic Quit. The gate now keeps the app open while the asynchronous save check runs, then allows one explicitly approved termination. The final release smoke passes a refused Quit immediately followed by an accepted Quit, verifies saved text after reopening SQLite, and confirms renderer termination. The new `STORAGE_RECOVERY_SMOKE_OK` stage mounts the actual recovery interface against corrupt storage, preserves the same renderer/frame, performs emergency black, retries failed storage without publication, recovers the workspace and saves a correction through native Quit.

All native process markers passed: `NATIVE_SMOKE_OK`, `STORAGE_RECOVERY_SMOKE_OK`, `RECOVERY_SMOKE_OK`, and `PHASE2_NATIVE_SMOKE_OK`. Evidence is `build/qa/native-smoke-0.3.3-console.log`; automated results are `build/qa/flutter-tests-phase23-0.3.3.log`. Failed diagnostic runs remain separate and are not counted as passing verification. The final smoke includes 1,000 transitions, captured typography/source checks, renderer replacement, operator termination and journal recovery. Its ACK times measure Flutter paint readiness in windowed rehearsal, including covered-window behavior, rather than physical scanout.

Current native font/performance measurements, exact endurance-run versions and development packages are recorded in [PHASE23_STATUS.md](PHASE23_STATUS.md). A run started with 0.3.2 does not certify these 0.3.3 changes. Windows execution, physical display testing and knowledgeable reader review remain open; Phase 4 has not started.
