# Windows verification handoff

Windows compilation and runtime testing have not been executed on the available Mac. The Windows verification archive is a source package, not a compiled Windows application. These instructions produce evidence on your Windows machine; successful automation does not close the physical or manual gates below.

## Prepare the machine

Use a logged-in Windows 10/11 x64 desktop. Install Flutter **3.38.5** (Dart **3.10.4**), Git, Visual Studio with **Desktop development with C++**, and a supported Windows SDK. Put Flutter's `bin` directory on PATH. Keep the locked `pubspec.lock` from this project. First dependency resolution needs internet access; the resulting application presents stored content offline.

Extract the entire source archive into a writable local folder. Open PowerShell in the extracted folder containing `pubspec.yaml`. Close any older Cantivra instances before using the normal application against an existing library. Automated harnesses create separate temporary test libraries and must never be pointed at church data.

Check the toolchain:

```powershell
flutter --version
flutter doctor -v
```

Resolve the Windows toolchain issues reported by Flutter. Optional Android, web and other non-Windows targets are not required for this desktop verification.

## Run the automated checks

For the normal short verification:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\verify_windows.ps1
```

`Bypass` applies to this PowerShell process so an extracted local script can run; it does not change the machine's saved execution policy. Organization-enforced restrictions may still apply. Review the included script before executing it.

For the eight-hour run, keep the machine connected to power with a logged-in desktop that will remain awake and available:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tool\verify_windows.ps1 -EightHourSoak
```

Both commands run locked dependency resolution, formatting, static analysis, unit/widget tests, a native process-failure smoke test and a native font/sustained-operation harness. The switch requests **28,800 seconds** of sustained operation; the default requests **60 seconds**. Build and corpus preparation take additional time. Inspect the generated report and elapsed duration before calling a long run complete. An interrupted, failed or short run cannot establish eight-hour acceptance.

The final step rebuilds and packages the normal `lib/main.dart` application. Test entrypoints are never deliverables. If the script fails before packaging, fix the failure and rerun the script; do not distribute whatever executable was left in the build folder. Stop at the first failure and retain its evidence rather than treating later manual observations as a substitute.

Each invocation creates a new directory:

```text
build/qa/windows-verification/<UTC-timestamp>-<unique-suffix>/
```

This retains `windows-verification.log`, `windows-host.json` with OS/CPU/GPU/RAM, `verification-status.json`, and this run's native smoke log when produced. `acceptance-evidence.json` records the native harness's source evidence directory and copied exports. The `native-acceptance` subdirectory contains only allowlisted report/event/PNG exports; session capabilities, databases and executable bundles are excluded. Failures retain the evidence available at the point of failure.

Version 0.3.3 routes the smoke's refused/successful Quit through the actual Windows `WM_CLOSE` gate and verifies that a presentation process cannot invoke operator Quit. This source has not been compiled or executed on Windows here. Require these checks to pass on your machine, then test the actual close button/Alt+F4 and controlled failed-save cases below. The harness also tests corrupt-storage recovery with a real independent renderer and explicit storage retry.

## Complete the Windows manual gates

Use the normal rebuilt release app with a disposable library. Record pass/fail, exact steps and observations in a text file in the evidence directory. Keep failed scenarios open with their error text or recording.

- **Native close and drafts:** make an unsaved correction, immediately close using the window's close button/Alt+F4, reopen and verify the saved correction. Confirm the renderer closes on successful normal Quit. Exercise a controlled save-failure case only against disposable data: the operator must report the failure and remain open, retaining the correction and live frame. If no reproducible save-failure setup is available, record that case as pending.
- **HDMI and monitor lifecycle:** follow every Windows scenario in [PHASE2_ACCEPTANCE.md](PHASE2_ACCEPTANCE.md), including 1080p/4K, 100%/150%/200% scaling, secondary displays to the left/above, unplug/replug, primary changes, renderer/operator termination, sleep/wake and the church's actual splitter/TV system. Record display models, refresh rates, arrangement, connection hardware and visible flicker. Version 0.3.2 saves Windows monitor device paths instead of reusable GDI output names; select the intended screen again for any older saved Windows profile. Confirm that unknown/cloned/ambiguous identities cannot be selected, a replacement device does not reuse the old selection, and a changed binding hides output until an explicit action. Device paths identify Windows device instances; HDMI equipment that emulates the same device identity still needs physical verification. These native changes have not been compiled or run on Windows here.
- **Native fonts and reading:** review the exported Windows PNGs for missing glyphs, clipping, safe-area violations, punctuation and complex-script shaping. Have knowledgeable readers review the languages being used; automated box measurements and text conservation do not certify linguistic correctness.
- **Clean-machine offline launch:** extract the normal `dist/Cantivra-Windows-<version>.zip` on a separate supported Windows account/machine without Flutter or Visual Studio. Keep the complete `Release` directory together. Launch `cantivra.exe`, create/save/reopen content, open output and present with networking disabled. Record any missing DLL or Visual C++ runtime requirement. The source archive is not the package for this test.
- **Trusted external distribution:** owner-controlled code signing, timestamping, expected publisher/trust verification and clean-machine testing remain separate release work. Local testing does not require buying a signing certificate. Follow [PHASE2_ACCEPTANCE.md](PHASE2_ACCEPTANCE.md) when preparing distribution.

## Return the evidence

Send the complete timestamped **Windows verification evidence directory**, the manual-results text, and any failure screenshots/recordings. Include the tested normal package's `.manifest.json` and `.sha256` from `dist` so results can be tied to the exact build. For physical tests, include the display/HDMI hardware details listed above. Review logs for local paths before sharing publicly; do not attach real libraries, `renderer-session.json`, tokens, private keys or certificate passwords.

A successful script closes only its automated checks for that Windows machine and build. Manual Windows close handling, physical HDMI observation, clean-machine launch, reader review and trusted distribution require their own recorded results. macOS physical-display checks also remain separate; Windows results cannot stand in for them.
