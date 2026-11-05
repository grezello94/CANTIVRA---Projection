# Phase 2 verification — Cantivra 0.2.0+2

Observed on 5 November 2026. The process-isolation and display-profile implementation is working and software-tested on macOS. Phase 2's physical multi-display and Windows acceptance gates remain open; this is a development build, not a production-release sign-off.

## Environment and checks

Host: Apple M1, 16 GB RAM, macOS 26.5.2 (25F84), Xcode 26.2. Toolchain: Flutter 3.38.5, Dart 3.10.4. Tests used temporary libraries; the native smoke creates its own workspaces inside the app sandbox.

| Check | Observed result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed lib test tool` | 35 files checked, no changes required. |
| `flutter analyze --no-pub` | No issues found. |
| `flutter test test --no-pub --reporter expanded` | All 158 tests passed. |
| Release native process smoke | Passed with the sandboxed ad-hoc development signature and release entitlements; final marker `PHASE2_NATIVE_SMOKE_OK`. |
| `dart run tool/package_desktop.dart macos` | Normal `lib/main.dart` application rebuilt and packaged successfully after the smoke harness. |
| `codesign --verify --deep --strict` on packaged app | Passed. Release entitlements include app sandbox and local networking; no debug `get-task-allow`. |
| ZIP integrity and SHA-256 | Passed; manifest, checksum and archive agree. |
| Extra normal-app startup probe | Skipped because an existing Cantivra process was running; it was left untouched. Native execution evidence comes from the isolated release harness. |

The automated suite includes real SQLite persistence/search/backup tests, service navigation, immutable draft/live separation, measured text layout, widget workflows, output-profile persistence, native-channel contract tests, real-loopback transport tests, renderer state and desktop supervision. Important failure cases include authentication rejection, malformed/oversize transport frames, bounded queues, disconnects, stale revisions, lost acknowledgements, emergency ordering, refused shutdown and recovery without implicit publication. Native-channel mocks establish contracts, not physical monitor behavior.

The seven widget tests exercise 1440 × 900 and 1180 × 760 layouts; `build/qa/operator-1440x900.png` is the current operator screenshot.

## Native process evidence

The release harness and runner are [native_smoke.dart](../tool/native_smoke.dart) and [run_native_smoke.dart](../tool/run_native_smoke.dart). The local log is `build/qa/native-smoke-phase2.log`. The successful run exercised:

1. Same-executable launch into a distinct renderer OS process, initially black, with authenticated local control and native window status.
2. Prepared publication acknowledged after renderer frame readiness; 40 next/previous transitions; draft text and theme changes isolated from the accepted frame.
3. Freeze rejection, emergency black, restore, clear text and background visibility.
4. Explicit primary-display and missing-display rejection without fallback; rejected changes retain the captured frame. Uniform scale and safe inset preserve captured text and theme.
5. Forced renderer termination followed by explicit replacement. The replacement starts black; Restore is required to reveal the previously captured slide.
6. Refused quit leaves both processes available. Accepted normal quit closes the renderer and flushes edits that survive reopening the test SQLite database.
7. Forced operator termination while the renderer displays a frozen frame. A separate authenticated probe confirmed the renderer remained visible with the identical captured snapshot.
8. A fresh operator reconnects to that surviving renderer, adopts its frame and freeze state without republishing, recovers a different saved draft independently, and performs emergency black and restore.

For the 40 navigation commands in the final sealed native run, command-to-frame-ready acknowledgement timing was p50 **16.702 ms**, p95 **20.780 ms**. This small local windowed sample is not a TV scanout measurement, a 4K benchmark, or evidence that the full performance/soak budget is met. The SDK logged its merged UI/platform-thread notice; the operator and renderer remained separate OS processes.

## Implemented behavior and recovery boundaries

- The renderer owns the last accepted frame and display lifecycle. Search, editing, settings, profile preparation and unrelated subsystem failures do not commit a replacement frame.
- Startup inspects a surviving renderer without relocating or revealing it. An unavailable or potentially alive session is not silently replaced by a duplicate process.
- Profiles persist a display target or deliberate windowed rehearsal, uniform scale and safe inset. Saving/selecting a profile does not apply it to live output; Apply/open is explicit.
- Native display loss hides and disarms output. Reconnection requires explicit rearming. The Swift implementation compiled and native guards were exercised; actual cable loss and multi-monitor placement still require the hardware matrix.
- Normal Quit saves and shuts down output. Abrupt operator termination leaves output running. Renderer-process failure, graphics-driver failure, OS failure and loss of power remain outside that survival guarantee.
- Reconnection recovers the authoritative last frame, not the entire previous operator's captured service deck. Resume a prepared service sequence through explicit Go Live.
- Native display identifiers can change. An unavailable saved target stays unavailable until the operator deliberately selects a suitable target.
- The renderer descriptor is operational state, separate from SQLite and library backups. It uses an authenticated loopback-only endpoint, a private token and mode 0600 on macOS; this is not a LAN receiver implementation.

## Development package

The normal application archive is `dist/Cantivra-macOS-0.2.0.zip` (19,443,668 bytes). Supporting files are `dist/Cantivra-macOS-0.2.0.zip.sha256` and `dist/Cantivra-macOS-0.2.0.zip.manifest.json`. The manifest records the normal entrypoint, SDK, lockfile digest and ad-hoc signing status. The archive includes the bundled font license.

```text
SHA-256  1845367b462057ec08a00c2ff6318819914cb555348a0092ab7b80fafe9a73cd
```

Extract and open `cantivra.app`, or run the built bundle from `build/macos/Build/Products/Release/cantivra.app`. Source development commands remain in [BUILD.md](BUILD.md).

The signature is a local development signature. Developer ID signing, notarization, clean-machine installation and Windows certificate-backed packaging have not been performed. Packaging scripts and the macOS/Windows CI workflow are implemented; no remote CI execution is claimed.

## Required remaining verification

Use [QA.md](QA.md) to record hardware, OS and per-scenario outcomes before production sign-off:

- Windows compilation and runtime, including separate-process crash/reconnect behavior and packaged runtime dependencies.
- Both platforms: 1080p and 4K HDMI, actual distribution hardware, monitor arrangements, negative coordinates, Retina/mixed DPI and OS scaling changes.
- Physical unplug/replug while live/frozen/black, resolution changes, primary-display changes, sleep/wake and macOS Spaces behavior, including operator absence during display loss.
- Visible flicker/scanout checks, 10,000-record performance measurements, 1,000 transitions under workload, predictable combined memory use and eight-hour soak.
- Trusted distribution signing, installer/clean-system checks, and volunteer workflow review.

Advanced content recognition, expanded layout editing, full library organization, media, document interoperability, automatic rotating backups, AI and network receivers remain later phases. No PDF/PPTX/media compatibility claim is added by this milestone.

## Software closure review in version 0.3 — 5 November 2026

The historical 0.2 results above remain unchanged. The 0.3 review fixed malformed native display arguments silently becoming rehearsal, negotiated renderer-layout compatibility before granting control, and fixed frame acknowledgements when a surviving rehearsal window is covered by a new operator. Hidden-window paint ordering and no-op configuration now have dedicated tests.

The final 0.3 suite passes **210 tests**, clean formatting and static analysis. A sandboxed release run passes 1,000 transitions with search/draft autosave workload, operator termination, retained visible frozen output, new-operator recovery and emergency/restore. Frame-ready ACK timings were p50 16.650 ms, p95 18.025 ms and max 208.859 ms. A journal-only correction also recovered without replacing committed library text. See [PHASE3_VERIFICATION.md](PHASE3_VERIFICATION.md) for exact scope and current package details.

Windows build was attempted locally and rejected because the installed host is macOS; no Windows binary/runtime result is claimed. Local signing inspection found an Apple Development identity but no Developer ID Application identity. Physical HDMI/4K/DPI, Windows execution, eight-hour reliability and trusted distribution remain open, with concrete commands and per-step evidence requirements in [PHASE2_ACCEPTANCE.md](PHASE2_ACCEPTANCE.md). Continued Phase 3 implementation does not convert those checks into passing results.

## Version 0.3.3 startup and Quit checks

The latest suite passes **255 automated tests**, clean formatting and static analysis. The final native Mac release smoke passes 1,000 transitions and all four completion markers, including the new `STORAGE_RECOVERY_SMOKE_OK` scenario. A damaged library no longer removes controls for surviving output. The same renderer/frame is inspected before opening SQLite; emergency control and explicit retry work independently, and no automatic replacement or publication occurs.

Native Quit now refuses the initial attempt while Dart validates/saves, then permits one approved attempt. This avoids the pending-termination-loop failure observed during native testing. A refused Quit followed immediately by another request retains both processes and the exact frame until the accepted save/close. The native test confirms that the final correction persists after SQLite reopen. Late output handshakes cannot revive a disposed controller, and corrections made while shutdown awaits acknowledgement are covered by gated tests.

The Windows source now routes smoke Quit through `WM_CLOSE` rather than substituting direct cleanup. It has not been compiled or run here. The Windows, physical display, shutdown/logout, language-reader and endurance checks remain separate; use the current [Phase 2/3 status](PHASE23_STATUS.md) and [Windows procedure](WINDOWS_TESTING.md). Trusted external signing remains a distribution gate, not a prerequisite for local testing.
