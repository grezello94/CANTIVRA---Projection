# Phase 1 verification record

This record describes observed results from the initial development session (4–5 November 2026, Asia/Kolkata). It is not production certification.

## Environment

- MacBook Pro (MacBookPro17,1), Apple M1, 16 GB RAM, arm64.
- macOS 26.5.2 (25F84), Xcode 26.2.
- Flutter 3.38.5 stable, Dart 3.10.4.
- SQLite is bundled through `sqlite3` 3.5.2, resolved in `pubspec.lock`.
- Native window plugin: `desktop_multi_window` 0.3.1.

## Automated results

| Check | Result |
| --- | --- |
| Dart formatting for `lib`, `test`, `tool` | Passed |
| `flutter analyze --no-pub` | Passed, no issues |
| `flutter test test --no-pub --reporter expanded` | **72 tests passed** |
| macOS Swift typecheck and debug native build | Passed |
| Release native smoke runner | Passed, `NATIVE_SMOKE_OK` and native process exit 0 |
| Standard macOS release application build | Passed with `lib/main.dart`; cold-launched successfully using its normal application-support folder |
| Windows source/CI configuration | Implemented; build and runtime not executed on this host |

Test coverage includes:

- 14 real SQLite repository tests and one 2,005-record search benchmark.
- 16 workspace integration tests with real SQLite and a recording output adapter.
- 27 measured layout, output-state and canvas tests.
- 5 native display channel contract tests and 3 asynchronous close contract tests.
- 6 UI tests covering all nine sidebar destinations at 1440×900 and 1180×760, content creation/search/service addition, live/preview isolation and presentation controls.

Regression tests cover stale search results replacing drafts, favorites overwriting newer edits, and failed draft saves allowing unsafe navigation. All passed after fixes.

## Actual native multi-engine exercise

Command:

```sh
dart run tool/run_native_smoke.dart macos
```

The runner builds the release harness, launches its executable directly, captures output into `build/qa/native-smoke.log`, and requires a clean native exit plus the success marker. The harness uses a disposable temporary SQLite library.

Observed working behavior:

1. Native screen enumeration and refusal to convert the operator engine into output.
2. A separately registered congregation Flutter engine/window becomes ready and acknowledges a published slide after rendering.
3. Forty alternating next/previous commands are acknowledged.
4. Source edits and a theme change preserve the actual renderer's published text, theme and revision.
5. Freeze blocks publication; emergency black overrides freeze; restore recovers the prior slide.
6. Unsupported output protocol is rejected, retaining the previous valid frame.
7. A nonexistent display ID is rejected without moving output to another display.
8. Explicit corrected-text publication, clear text, restore and background visibility work.
9. Closing the congregation window leaves the operator available.
10. A refused normal quit leaves both operator and congregation available.
11. An accepted normal quit flushes a pending draft; reopening SQLite verifies the final text, then the native application exits normally.

Local release timing for forty sequential transitions: **p50 16.648 ms, p95 17.223 ms**, measured from command to renderer acknowledgement. This measures neither physical HDMI scanout nor TV processing latency. It is a small local sample, not a cross-platform performance guarantee.

The full test suite also ran the 2,005-row search benchmark while other tests/build work were active. One observed sample was p50 0.48 ms / p95 3.52 ms; a standalone earlier sample was p50 0.11 ms / p95 0.16 ms. Reproduce measurements on target hardware before setting release budgets.

## Artifacts

- Normal application: `build/macos/Build/Products/Release/cantivra.app`.
- Local archive: `dist/Cantivra-macOS-0.1.0.zip`.
- Widget-rendered workspace capture: `build/qa/operator-1440x900.png`.
- Native harness log: `build/qa/native-smoke.log`.

The screenshot uses bundled test fonts and a mocked output adapter. It is a visual layout artifact, not evidence of an HDMI display. The app archive was checked with `unzip -t` and passed. The standard app was cold-launched for four seconds with no startup exception; its normal local database contained five sample content records, one service and schema version 1, with SQLite integrity `ok`. This startup check then stopped the test process; normal quit safety is verified separately by the native harness. The archive is a local development build, without trusted Developer ID distribution or notarization.

## Outstanding release gates

- Windows compilation/runtime and the complete Windows native close/display path.
- Physical extended monitors, HDMI splitter/TVs, hotplug timing, 1080p/4K, resolution changes and mixed DPI on both operating systems.
- Eight-hour soak, larger library/media workloads and clean-machine install testing.
- Renderer process isolation: independent Flutter engines currently share one native process.
- Heavy draft pagination currently runs on the operator isolate and is bounded to 50,000 characters; worst-case editing/layout latency requires further optimization and benchmarking.
- Font portability, full right-to-left/language-specific layout and broad visual rendering fixtures.
- Guided backup restore, automatic backup rotation, destructive-migration preflight backup and recovery UI.
- Media, imports/exports, complete theme authoring, recognition and optional network/AI features described in the roadmap.

The native plugin can emit an early `FlutterEngineSendPlatformMessage` warning while its initial engine attaches, and the SDK reports merged UI/platform threading on macOS. Neither prevented the observed tests, but eliminating startup warnings and assessing their reliability impact remain hardening tasks. No claim of flicker-free physical HDMI operation is made from these automated results.
