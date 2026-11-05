# Phase 2 and Phase 3 acceptance status

Last updated: 6 November 2026 (IST), version **0.3.4+7**. Native process/recovery checks, 255 Flutter tests, the normal Mac package and the guided direct-Sony functional subset pass verification. That manual session is closed safely; the wider physical matrix remains open. The current eight-hour run is **running, not complete**. The user has authorized finishing locally available work while deferring Windows testing. Implementation, automated verification and physical acceptance remain separate claims. **Phase 4 has not started.**

| Requirement | Current evidence | Status |
| --- | --- | --- |
| Phase 2 controlled output, process survival and recovery | 0.3.4 Mac release: 1,000 transitions, hidden-renderer same-process/session/frame survival, operator/renderer failures, journal/corrupt-storage recovery, native Quit, authenticated IPC/display contracts; all four smoke markers | Passed on available Mac; Windows execution pending |
| Phase 2 display-target identity | Windows source maps active display paths to monitor device instances; unknown/ambiguous/clone mappings fail closed; 15 portable C++ policy checks pass | Policy verified on Mac; Windows API compilation/runtime pending |
| Phase 2 physical HDMI/multi-monitor lifecycle | 0.3.4 direct Sony at reported 4K/30 Hz: black/normal/frozen cable loss, explicit re-arm, physical Fn+F12 while frozen, background, edit/live isolation, bottom Next/Previous and Clear text/Black/Restore states confirmed; normal save-and-Quit closed both processes with integrity `ok` | Guided functional subset passes; wider Mac/Windows physical matrix pending |
| Phase 3 structure, splitting, overflow, drafts/history | 255 automated tests and native font corpus | Passed on available Mac; Windows native fonts/layout pending |
| Phase 3 native fallback/geometry | 18 cases, nine writing-system fixtures, 94 actual-font pages, 36 PNGs; safe text boxes and source conservation | Mac geometry verified; knowledgeable reader review pending |
| Actual operator workload | 10,005 records loaded, 100 verified search queries, 100 edits through actual operator widgets, renderer timing callbacks | Short Mac measurements passed; full performance matrix pending |
| Sustained operation and failure recovery | 0.3.4 isolated run `1793903282052217`; initial 18 font cases, 100 search queries and 100 edits passed; earlier measurements retained below | Eight-hour run running, not complete; final reliability/performance acceptance pending |
| Test isolation/interruption | Captured signed bundle independent of build output; native SIGINT cleanup verification; private capabilities excluded from exports | Passed: `build/qa/native-acceptance-interruption-result.json` |
| Normal desktop build | Normal-main 0.3.4 Mac development ZIP, manifest/hash and nested signature verified; 0.3.4 Windows source verification kit | Mac development package and source handoff verified; Windows executable pending |
| Trusted distribution | Local ad-hoc signing; no Developer ID Application identity | Separate production-distribution gate pending |

## Work finished locally

Version **0.3.4+7** changes the native Mac output role's last-window automatic termination policy. A physical diagnostic repeat proved that AppKit scheduled its deferred last-window check after output was hidden on HDMI loss, then terminated the renderer because the shared policy returned true. The output role now returns false for that check; the operator retains true. Explicit renderer-window close, authenticated shutdown and normal OS Quit still enter the unchanged direct termination path. Opt-in diagnostic stacks remain available. Physical retesting now passes black, normal and frozen cable loss and explicit re-arm on the direct Sony connection, with the same renderer, retained slide revision and preserved freeze state; wider acceptance is still open.

Current Flutter regression: **255 passed** in `build/qa/flutter-tests-phase23-0.3.4-final.log`; 54 Dart files pass formatting, and static analysis is clean. A competing-lock test setup race was corrected without changing production persistence logic or weakening its assertions. Its preceding failure log is retained. The native smoke also passes in `build/qa/native-smoke-0.3.4-console.log`, including hidden-renderer survival with the same process, session and exact captured frame, normal Quit and storage/crash recovery. All four completion markers are present. Its 1,000 navigation samples measured p50 **16.658 ms**, p95 **17.719 ms**, maximum **199.097 ms** to Flutter frame readiness; this is software timing evidence, not full performance or television scanout acceptance.

Version 0.3.3 opens the known renderer control endpoint before SQLite. A corrupt or newer library leaves the operator's emergency controls available; retry never resets files, creates a duplicate renderer or publishes. The normal workspace adopts the latest captured output after recovery. Invalid saved themes are isolated with a safe preview default while preserving the saved value for review.

The save queue drains the latest correction before navigation and Quit, including edits made while renderer shutdown is awaiting acknowledgement. Disposal closes pending handshakes without reviving control or health timers. Native Mac testing exposed a pending-termination-loop failure; Quit now keeps the app open while the asynchronous save check runs and re-enters termination only after approval. The final native smoke verifies a refused Quit immediately followed by an accepted save/close, SQLite reopen and renderer exit. The storage-recovery stage passes `STORAGE_RECOVERY_SMOKE_OK` using the actual recovery interface and native processes. Windows now has the equivalent smoke route through `WM_CLOSE`, but it has not executed here.

The Windows adapter now uses monitor device paths instead of reusable GDI output names. Older Windows selections require explicit reselection. Unidentified targets remain visible diagnostically but cannot be applied. A changed live binding disarms output. The actual Windows API adapter has not been compiled on this Mac.

The acceptance harness now loads a 10,005-record operator cache and mounts the actual operator widgets. It measures 100 synthetic edit-to-paint samples and verifies preview text plus unchanged live frames. Renderer timing callbacks record build/raster/total timing and actual view size/DPI. Its sustained workload verifies repository rollback, rejected oversized drafts, rejected renderer preparations and repeated actual TCP disconnect/reconnect. These do not simulate restarting the database worker or physical HDMI loss.

Lifetime timing maxima and over-budget counters survive rollover of the recent 4,096-observation percentile window. Reports distinguish completed duration, functional checks and full performance acceptance. The runner captures its own runtime bundle so normal-app rebuilds cannot replace running test assets. Interruption handling retains partial evidence and attempts authenticated cleanup using only its private test workspace.

Windows handoff tooling now retains separate per-run logs, OS/CPU/GPU/RAM and explicit manual gates. Reproducible source packaging verifies all archived hashes and excludes caches, user libraries, session capabilities and signing material.

Prior 0.3.3 regression evidence: `build/qa/flutter-tests-phase23-0.3.3.log` (**255 passed**); formatting of **52 Dart files** and static analysis pass. Its final native process log is `build/qa/native-smoke-0.3.3-console.log`, with all four completion markers. These results predate the 0.3.4 native policy fix. Failed diagnostic runs are retained separately and do not count as passing verification. The timing/relay and cleanup tests pass. Prior native interruption verification confirms partial evidence retention and removal of only its staged runtime/private workspace. The intentionally interrupted runner records failure; the interruption verification result records success. Cleanup verifies actual process exit, including lost shutdown acknowledgements, and retries only a prior-operator disconnect race. The portable C++ command in [BUILD.md](BUILD.md) passes 15 policy checks; these do not compile the Win32 adapter.

## Historical 0.3.3 Mac measurements

Host: Apple M1, 16 GB RAM, macOS 26.5.2 (25F84), Flutter 3.38.5 / Dart 3.10.4, native release builds. The separate 0.3.2 baseline endurance workload was running concurrently; these are observations from this host rather than isolated hardware certification.

| Measurement | Observed result | Scope |
| --- | --- | --- |
| 100 representative queries at 10,005 records, after 20 warmups | p50 0.752 ms; p95 1.255 ms; max 1.692 ms | Database request through result transfer; expected IDs verified; excludes UI debounce |
| Broad query returning 10,001 records | 69.948 ms | Broad results remain unbounded; later library work remains necessary |
| 100 edits through actual operator widgets | p50 15.611 ms; p95 16.437 ms; max 99.223 ms; 1/100 above 50 ms | Synthetic edit to Flutter build/layout/paint; excludes OS keyboard latency |
| 553 sustained transitions over 65.040 seconds | p50 14.414 ms; p95 18.236 ms; max 188.691 ms; 2/553 above 50 ms | Command to Flutter frame-ready ACK; windowed rehearsal |
| Native renderer timing snapshot | 506 frames; build p95 0.867 ms; raster p95 1.340 ms; total p95 2.498 ms; total max 45.234 ms | 1920 × 1072 physical view at 2× DPI; not physical 1080p/60 Hz acceptance |
| Sampled combined RSS | First/max 348,635,136 bytes; last 233,193,472 bytes | Seven samples after font capture; not peak-allocation or long-term growth proof |
| Separate process-fault smoke, 1,000 transitions | p50 0.673 ms; p95 17.076 ms; max 104.515 ms | Includes covered-window paint-ready behavior; not television/display latency |

All 18 native-font cases, 94 measured pages and 36 exported PNGs passed source-conservation/safe-box assertions. Reader review remains necessary. The actual-operator report is `build/qa/native-acceptance/1793898888123031/report.json`, with console `build/qa/native-acceptance-0.3.3-operator.log`. It records zero operator Flutter errors, database integrity `ok` and verified normal shutdown. Its status is deliberately partial software evidence, with eight-hour and full-performance acceptance false. Maximum latency observations above are retained and require profiling in the representative-hardware matrix.

## Current development packages

The current normal `lib/main.dart` application is `dist/Cantivra-macOS-0.3.4.zip`, **19,768,903 bytes**, SHA-256 `fabca088901e4d15a3a9ef3633bf7655170f36991242b74a50fe51ef3d569b22`. Its normal entrypoint, manifest/checksum, ZIP integrity and nested ad-hoc development signatures were verified; package log: `build/qa/package-macos-0.3.4.log`. An independently extracted copy also passed nested strict signature checks and reported build 7. Extract and open `cantivra.app`. It is not Developer ID signed or notarized. The working `build/macos/Build/Products/Release/cantivra.app` is also the normal main application, rebuilt after native testing. The older unversioned app under `dist` is not current.

The earlier `dist/Cantivra-macOS-0.3.3.zip` remains historical: **19,747,458 bytes**, SHA-256 `f9fcb94cbfc734f02e9f14905cd26bf43daee1704e7667fe807c11b8c7a719ce`. It predates the 0.3.4 HDMI fix.

Windows source handoff: `dist/Cantivra-Windows-Verification-0.3.4.zip`, generated from the current sources and documentation with per-file SHA-256 verification. This is not a Windows executable; follow [WINDOWS_TESTING.md](WINDOWS_TESTING.md) to build and verify it on Windows. Its archive checksum and manifest are adjacent to the ZIP. The older 0.3.3 source kit remains historical and predates the HDMI fix.

## Current-version endurance status

An isolated **0.3.4+7** eight-hour run started on **5 November 2026 at 18:28:01 UTC / 23:58 IST**, in `build/qa/native-acceptance/1793903282052217`, with runner PID **84353** and test operator PID **84664**. It is **running, not complete**. Its captured bundle version/build number and native executable/AOT SHA-256 values are recorded in `build/qa/macos-eight-hour-0.3.4-process.json`; console output is `build/qa/macos-eight-hour-0.3.4.log`. Initial checks passed 18 native font cases, 100 search queries and 100 edits. These are partial preparation/workload results, not final duration or performance measurements. Check this exact run's status/report before sign-off.

The 0.3.3 and 0.3.2 runs below were also still running, not complete, at this update. Their captured bundles preserve the older policies; even a completed run cannot certify the 0.3.4 last-window change.

## Historical 0.3.3 eight-hour run

An isolated **0.3.3+6** run started on **5 November 2026 at 17:17 UTC / 22:47 IST**, with run directory `build/qa/native-acceptance/1793899039019237`, runner PID 80285 and test operator PID 80327. Console: `build/qa/macos-eight-hour-0.3.3.log`; process metadata: `build/qa/macos-eight-hour-0.3.3-process.json`. Its captured runtime is independent of subsequent normal-app builds. It was running, not complete, at handoff; inspect that directory's status/report before sign-off. The eight-hour duration begins after corpus and workload preparation.

The older baseline below remains independent. A completed 0.3.2 run does not certify the 0.3.3 startup or shutdown changes, and neither earlier version certifies the 0.3.4 HDMI policy.

## Historical 0.3.2 Mac measurements

Host: Apple M1, 16 GB RAM, macOS 26.5.2 (25F84), Flutter 3.38.5 / Dart 3.10.4, native release builds.

| Measurement | Observed result | Scope |
| --- | --- | --- |
| 100 representative queries at 10,005 records, after 20 warmups | p50 0.725 ms; p95 1.151 ms; max 1.513 ms | Database request through result transfer, excluding UI debounce; expected IDs verified |
| Broad query returning 10,001 records | 70.082 ms | Broad results remain unbounded; later library work remains necessary |
| 100 ordinary edits through actual operator widgets | p50 15.556 ms; p95 16.220 ms; max 254.951 ms; 2/100 above 50 ms | Synthetic controller edit to Flutter build/layout/paint; excludes OS keyboard latency; occluded-window warm-up can affect tail latency |
| 552 sustained transitions with actual operator UI | p50 14.467 ms; p95 18.481 ms; max 22.858 ms | Command to Flutter frame-ready ACK, windowed rehearsal |
| Native renderer timing snapshot | 550 frames; build p95 0.676 ms; raster p95 0.839 ms; total p95 1.656 ms | 1920 × 1072 physical view at 2× DPI; snapshot precedes final exit; not a physical 1080p/60 Hz test |
| Sampled combined RSS over 65 seconds | First 335,675,392 bytes; last 239,501,312 bytes; maximum sampled 335,675,392 bytes | Includes font-capture caches and actual operator; not peak-allocation or eight-hour growth proof |
| Separate process-fault smoke | 1,000 transitions; p50 16.668 ms; p95 17.375 ms; max 117.453 ms | Also passes replacement, operator death, reattach, journal recovery and macOS native close handling |

The historical application package is `dist/Cantivra-macOS-0.3.2.zip`, ad-hoc development signed with nested code verified and matching SHA-256 manifest. This is not Developer ID/notarized distribution. These measurements and that package predate the 0.3.3 reliability fixes.

The actual-operator report is `build/qa/native-acceptance/1793882150490935/report.json`; console log is `build/qa/native-acceptance-0.3.2-operator.log`. It records zero operator Flutter errors and normal test shutdown. Historical process-fault evidence is `build/qa/native-smoke-0.3.2-console.log`; the shared `native-smoke-phase2.log` now contains the newer run. Earlier results remain historical evidence.

## Eight-hour 0.3.2 baseline

An isolated eight-hour run started on **5 November 2026 at 12:48 UTC / 18:18 IST**, with run directory `build/qa/native-acceptance/1793882896259914` and console `build/qa/macos-eight-hour-0.3.2.log`. It remains a baseline for **0.3.2**, not certification of the newer changes. It ran beyond four hours while this update was being verified and was still **running**, not complete. The run status/report is authoritative when it finishes.

Each run owns `status.json` and `events.ndjson`. `build/qa/native-acceptance/latest-run.json` is a convenience pointer and may refer to a different concurrent run; use the exact run directory for the version under review. Inspect its actual status and report before sign-off. **A running, interrupted, failed or short run is not a completed soak.**

```sh
dart run tool/run_native_acceptance.dart macos --duration-seconds=28800
# On Windows:
dart run tool/run_native_acceptance.dart windows --duration-seconds=28800
```

The sustained duration begins after preparation. The Mac runner prevents idle system sleep while its test operator is alive; keep the Mac powered, logged in and its lid open. Explicit sleep, reboot or quitting interrupts verification. Foreground runs can be stopped with Ctrl+C and are recorded as failures. A completed duration closes only the recorded software scenario: physical scanout, reader review, representative-hardware profiling and long-term memory review remain independent. `eightHourSoftwareAcceptancePassed` stays false while the full performance matrix is unverified.

## Deferred Windows work

Follow [WINDOWS_TESTING.md](WINDOWS_TESTING.md) for prerequisites, short/eight-hour commands and evidence-return instructions. The user has a Windows machine, but it is unavailable in this session.

1. Compile the Win32 adapter and run all Dart/native process/layout checks.
2. Run the updated smoke through actual `WM_CLOSE`, then exercise the close button/Alt+F4 with successful saves and controlled failed-save refusal. Source implementation alone does not prove the Windows gate.
3. Verify device-path selection, unknown/clone rejection, same/different monitor reconnection, primary changes, negative coordinates, 1080p/4K and 100%/150%/200% DPI.
4. Test sleep/wake, renderer/operator failures and the actual church HDMI splitter/TV system, including visible flicker.
5. Review Windows fallback fonts with knowledgeable readers and run the eight-hour scenario.
6. Test the complete release package offline on a clean machine without Flutter/Visual Studio; resolve missing DLL/runtime requirements.
7. Complete owner-controlled signing/timestamping and clean-machine publisher verification for external distribution.

Windows verification ZIPs are **source**, not compiled Windows executables. They exclude user libraries, caches, renderer capabilities and credentials. Rebuild the versioned kit from finalized sources/docs using `python3 tool/package_windows_verification.py`.

## Other external checks

The guided direct-HDMI functional subset is complete on the Sony connection; the manual session is closed. The user confirmed initial black/operator separation, readable output and preview editing without live changes on the TV. Native events corroborate the earlier on-screen frozen emergency black. During the original cable loss while emergency black, the output hid and the operator remained available, but the renderer then exited through a normal AppKit termination path. A diagnostic repeat at `build/qa/manual-hdmi/1793901602552743` proved the deferred last-window check terminated hidden renderer PID 82500; its `renderer-diagnostics.log` and `diagnostic-result.json` are preserved.

The fixed 0.3.4 retest at `build/qa/manual-hdmi/1793902175708487` passes black, normal and frozen cable loss on this direct Sony 4K/30 Hz connection, using operator PID 83215 and the same surviving renderer PID 83230. Normal A (`hdmi-A:0`, revision 1) was lost at 18:14:36 UTC, reconnected at 18:15:41 UTC and deliberately re-armed at 18:16:01 UTC without changing revision. Frozen A at revision 2 was lost at 18:17:05 UTC, reconnected at 18:17:08 UTC and re-armed at 18:17:19 UTC with freeze preserved. The user confirmed controls stayed on the Mac and Next could not change frozen A. Reconnection alone did not re-arm output.

Physical **Fn+F12 while frozen** is confirmed by the user and revision 2 frozen → revision 3 emergency black at 18:19:44 UTC. Restore at revision 4 and Background off/on at revisions 5/6 match user observations. SQLite independently confirms the exact A correction persisted while live stayed at revision 6; the user saw the original words on the TV until publication. A/B/A presentations at revisions 7/8/9 were reported clean.

Bottom-arrow navigation is confirmed separately: the user selected A from the **MANUAL HDMI TEST** service's Running order, published, and reported counter **1 / 2** with Next enabled. Bottom Next then Previous immediately displayed B then corrected A without another Go live. Native revision 10 A at 18:31:36 UTC → revision 11 B at 18:32:08 UTC → revision 12 A at 18:32:16 UTC corroborates that report. The earlier disabled-arrow observation does not establish a defect; single-slide Library publications intentionally have no next slide.

Clear text, Black and Restore states are now user-confirmed. Native evidence records clear at revision 13 (18:32:37 UTC), normal at 14, background toggles at 15/16, black at 17–21, normal at 22 with background hidden, and normal at 23 with background visible. Extra button presses occurred; these are verified core states rather than an exact four-command-only sequence. Normal save-and-Quit recorded `manual_session_closed` at **18:33:23.258613 UTC on 5 November / 00:03:23 IST on 6 November**, database integrity `ok` and wrapper exit code 0. Both manual operator PID 83215 and renderer PID 83230 exited; the private database and logs are preserved. Normal Quit therefore passes in both the current manual session and native software smoke. Recovery and hidden-renderer survival also pass separately in that smoke. Evidence and remaining steps are in [HDMI_TESTING.md](HDMI_TESTING.md).

These results do not close the full physical acceptance gate. The remaining HDMI/4K/Retina/non-Retina matrix is still necessary **on macOS too**, following [PHASE2_ACCEPTANCE.md](PHASE2_ACCEPTANCE.md), and Windows execution is still deferred. Automated geometry does not certify typographic/linguistic correctness; obtain reader review for the languages actually used. Windows device paths identify device instances, not guaranteed hardware serial numbers; EDID-emulating distribution equipment still needs actual testing.

Developer ID is for trusted external Mac distribution, not essential local presentation. It must be issued through the app owner's Apple Developer account. Follow [MAC_SIGNING_HELP.md](MAC_SIGNING_HELP.md); purchasing a certificate is not required for local testing.
