# Native desktop builds

Cantivra 0.3 uses Flutter 3.38.5 / Dart 3.10.4, SQLite, and independent operator/renderer OS processes. Essential runtime operation is offline. The renderer's authenticated TCP endpoint binds only to loopback; it is local IPC, not a cloud or LAN presentation receiver.

Close older operator/output processes before upgrading. Schema 2 adds structured content and recovery drafts transactionally; 0.2 cannot reopen a migrated database. Protocol 2 now negotiates rendering schema 2 separately so that an older renderer cannot silently acknowledge unsupported typography. A version mismatch preserves the existing process/frame and requires closing that old output deliberately; it never kills or duplicates it.

## Checks and native process verification

Run from the project root with the pinned SDK:

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze --fatal-infos
flutter test test --reporter expanded
```

On a logged-in native desktop host:

```sh
dart run tool/run_native_smoke.dart macos
# On Windows:
dart run tool/run_native_smoke.dart windows
```

The harness builds its own entrypoint, seals a macOS ad-hoc development signature with release entitlements, launches native executables directly and requires success markers plus successful process exits. It uses temporary test libraries inside the app's permitted data area. It intentionally terminates only its test renderer/operator processes to verify replacement and crash survival. Never point the harness at an actual church library. The `--no-build` developer flag reuses an already built harness; normal verification should use the build step.

The native smoke log is `build/qa/native-smoke-phase2.log`. It covers actual separate-process publishing, 1,000 transitions with search/draft work, renderer replacement, operator SIGKILL with the same frame retained, journal-only correction recovery, freeze/emergency/restore, display guards, structured typography and save-before-quit. These are windowed software tests, not physical HDMI certification.

## Build and package the normal application

macOS needs Xcode and its command-line tools. This project uses Swift Package Manager; CocoaPods and a global Ruby installation are not required.

```sh
flutter run -d macos
dart run tool/package_desktop.dart macos
```

Windows needs Visual Studio's Desktop development with C++ workload and a supported Windows SDK. Build Windows on Windows:

```powershell
flutter doctor -v
flutter run -d windows
dart run tool/package_desktop.dart windows
```

The package helper always rebuilds `lib/main.dart` after any test harness. macOS output is `build/macos/Build/Products/Release/cantivra.app`; Windows x64 output is `build/windows/x64/runner/Release`. The complete bundle/runtime directory is required. The Windows ZIP includes the Release folder; open its `cantivra.exe` after extracting it.

Versioned archives are in `dist`, alongside a SHA-256 file and JSON manifest recording the SDK, lockfile digest, build platform, timestamp, source revision when available and signing status. These commands provide a repeatable development packaging procedure, not a claim of byte-identical archives.

macOS packaging re-seals the generated outer bundle ad-hoc using `Runner/Release.entitlements`, then verifies nested signatures with `codesign --verify --deep --strict` and validates the ZIP. This corrects an observed incremental-build case where Flutter replaced the valid App.framework after the outer bundle's seal was generated. Development signing is not Developer ID distribution, notarization or clean-machine installation approval.

Windows packages are unsigned by default. If the owner explicitly configures `CANTIVRA_SIGN_CERT_SHA1` and has `signtool` plus that certificate available locally, the helper signs/verifies the executable before archiving. Certificate management, trusted timestamps, installer signing and certificate-backed CI are not configured or claimed verified in this workspace. No signing credentials are embedded in the application.

## Process and display behavior

- `--cantivra-output` starts the renderer role of the same executable, which never opens the library. The macOS hidden window explicitly starts Flutter before visibility; otherwise the controller waits for view appearance and cannot receive its own safe-display configuration.
- The renderer owns the loopback server and a private workspace `renderer-session.json` capability file. macOS writes it atomically with mode 0600; Windows relies on the current user's application-support directory ACLs. The token is not logged, put into SQLite, or included in library backups.
- Authentication permits one operator at a time. Reopening the app only inspects/adopts surviving output; it does not publish, relocate or reveal it.
- New/replacement renderers start black. Replacement is explicit. A reachable or potentially alive renderer is not silently duplicated or killed.
- A normal Quit flushes current edits and explicitly shuts down output. A refused/failed save or shutdown keeps the operator open. A forced operator termination leaves the renderer and its last accepted frame alive.
- Native monitor handling runs in the renderer even when the operator is gone. Missing targets and targets that become primary are hidden/disarmed. Replugging never shows output automatically.
- An explicit primary ID is rejected as `PRIMARY_DISPLAY_RESERVED`. A null target is deliberate windowed rehearsal. There is no guessed fallback monitor.
- macOS coordinates use Cocoa points and backing scale. Windows coordinates use physical pixels with PerMonitorV2 DPI awareness. Negative coordinates are valid; do not multiply Win32 monitor geometry by DPI again.
- Available target resolution/DPI changes re-place the existing borderless window. The common canonical canvas is proportionally letterboxed and calibrated through saved scale/inset values.
- Frame preparation validates layout without changing output. Commit ACKs follow frame readiness. A lost ACK is inspected/reconciled or shown as unconfirmed; it is never assumed to mean the old slide remains visible. A newer confirmed emergency cannot be invalidated by a late ordinary error.

A frame ACK does not measure TV scanout or verify an HDMI distribution system. Complete the physical matrix in [QA.md](QA.md) on both operating systems.

## CI and remaining gates

[desktop.yml](../.github/workflows/desktop.yml) configures macOS/Windows locked dependencies, format/analyze/tests and normal application packaging with hashes/manifests. The optional manual `native_smoke` input runs process fault tests where a usable desktop session is available. A workflow file is not evidence that remote CI ran successfully.

Windows compilation/runtime, 1080p/4K HDMI, mixed DPI, sleep/wake, physical unplug/replug, long-service soak and trusted distribution remain open. See [PHASE2_VERIFICATION.md](PHASE2_VERIFICATION.md) for the exact locally observed results.

The remaining native hardware and trusted-signing steps are executable procedures in [PHASE2_ACCEPTANCE.md](PHASE2_ACCEPTANCE.md). Phase 3's implementation design is in [PHASE3_PLAN.md](PHASE3_PLAN.md); [PHASE3_VERIFICATION.md](PHASE3_VERIFICATION.md) records its observed results separately from the historical 0.2 build.

## Native fonts and sustained-operation evidence

```sh
dart run tool/run_native_acceptance.dart macos --duration-seconds=60
# When an eight-hour desktop session is available:
dart run tool/run_native_acceptance.dart macos --duration-seconds=28800
```

Use `windows` on Windows. The harness uses only temporary test libraries, measures actual native-font text boxes, checks source conservation and unchanged live output, exports first/last slide PNGs, and samples both processes' resident memory during navigation/search/autosave. Each run gets its own directory under `build/qa/native-acceptance`; `latest-run.json` records its status. A short run explicitly reports `eightHourSoakCompleted: false`. Windows checks can be orchestrated with `tool/verify_windows.ps1` (or its `-EightHourSoak` switch).

Both native runners validate the compiled Dart AOT fingerprint before accepting `--no-build`. Rebuilding the normal app or a different harness invalidates that shortcut; it fails before launching or touching a real workspace. Always package afterward using the normal package helper.

The sustained-operation runner copies the built harness into its unique run directory before launching it. Its renderer launches from that same copy. You can rebuild the normal app after staging without replacing the running test's code or assets. The staged runtime and private temporary library are removed after a successful run; only report/PNG/event exports remain. Interrupted runs attempt authenticated renderer cleanup, retain partial exported evidence and explicitly report unconfirmed cleanup. On macOS the runner prevents idle system sleep only while the test operator is alive; closing the lid, explicit sleep, restart or quitting the test still interrupts verification.

The sustained workload loads 10,005 records into the operator, verifies 100 representative searches after warmup, and injects repository rejection, invalid draft/frame rejection and repeated control-socket disconnections. Timing storage is bounded; the all-run maximum and over-budget counters retain earlier spikes. A completed duration is separate from meeting performance budgets or physical-display acceptance.

For the Windows machine, use the [Windows handoff](WINDOWS_TESTING.md). Rebuild its source archive from finalized sources using Python 3's standard library:

```sh
python3 tool/package_windows_verification.py
```

The source ZIP excludes generated caches, libraries, renderer capabilities and signing material, and verifies each archived file against its SHA-256 manifest. It is not a compiled Windows app. Optional `--output` chooses a different artifact directory.

The portable Windows display-identity policy can be verified on this Mac without Windows APIs:

```sh
clang++ -std=c++17 -Wall -Wextra -Werror -pedantic tool/windows_display_identity_test.cpp -o /tmp/cantivra-display-identity-test
/tmp/cantivra-display-identity-test
```

Passing these checks does not establish that the Windows API adapter compiles or behaves correctly on hardware.
