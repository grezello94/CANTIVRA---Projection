# Guided manual HDMI test

The manual harness uses the real operator workspace, SQLite persistence and separate presentation renderer. It creates its own temporary library with clearly labelled A/B slides. It never opens the church library, advances slides automatically or treats a native acknowledgement as proof of what appeared on the TV.

The user must connect the intended TV/monitor in extended-desktop mode. Choose its actual secondary display ID. On the Mac, connected displays and their IDs can be read with `system_profiler SPDisplaysDataType -json` from an environment with desktop access; a sandboxed command can return an incomplete list.

```sh
dart run tool/run_manual_hdmi.dart macos --hdmi-display=<secondary-display-id>
```

This builds a release harness, seals its development signature, captures a separate runtime under `build/qa/manual-hdmi/<run-id>/runtime`, and starts a workspace with an orange **MANUAL HDMI TEST** bar. Opening this explicitly selected output starts black; all later slide changes are manual. A missing, primary or ineligible target is rejected without guessing another screen. Test windows marked **ISOLATED ACCEPTANCE** belong to the separate automated endurance workload and should not be used for these steps.

Native events are retained in the manual run's `session.log`. `status.json` records the process state and deliberately keeps `physicalAcceptancePassed` false. Record the TV observations separately in `manual-results.json`, including the resolution, refresh rate, hardware and any failures. Successful launch or exit alone cannot pass physical acceptance.

The build folder contains a test entrypoint after the manual command. Rebuild the normal application before delivering it, following [BUILD.md](BUILD.md). For the current 0.3.4 handoff, the normal `lib/main.dart` app has been rebuilt after testing and verified as `dist/Cantivra-macOS-0.3.4.zip`; the working build is also the normal app. Captured test runtimes remain independent.

## Guided sequence

1. Confirm the TV starts black and the orange-bar operator window stays on the laptop.
2. Open **Services**, choose **MANUAL HDMI TEST** in the service dropdown, and select **HDMI TEST A** in the left **Running order** before clicking **Go live**. With the two single-slide fixtures, the live counter should read **1 / 2**. Check all text is readable and proportionate, with no operator controls on the TV. A Library publication contains only that item's slides; publishing a one-slide Library item intentionally leaves Next unavailable.
3. Change “The first test slide.” to “The corrected test slide.” in Source Editor without publishing. The Mac preview should update; the TV must retain the original text.
4. Explicitly Go live again. Only then should the corrected text appear on the TV.
5. Exercise next/previous between A and B. Check the selected draft and published service sequence remain distinct.
6. Check black, clear text, background, freeze, restore and F12 emergency, including emergency while frozen. Report unexpected flashes or intermediate frames.
7. Unplug/replug HDMI while live. Confirm no presentation window appears on the laptop and reconnect alone does not reveal the slide. Use **Settings → Apply / open output** to re-arm intentionally.
8. Repeat loss/reconnect while black and frozen. Continue the operator/renderer failure, display arrangement, resolution/DPI, power/session and save/Quit matrix in [PHASE2_ACCEPTANCE.md](PHASE2_ACCEPTANCE.md).

Do not mark later steps passed from earlier success. One direct TV connection does not certify the church splitter, another resolution/refresh rate, another monitor or Windows.

## Guided session — 5–6 November 2026 (IST)

Current retest version: **0.3.4+7**; manual entrypoint `tool/manual_hdmi.dart`. Earlier observations below used 0.3.3+6. Mac: Apple M1, macOS 26.5.2. Direct connection to **SONY TV *30**. The OS reports a 3840 × 2160 pixel mode at 30 Hz, 1920 × 1080 logical points, 2× backing scale, with mirroring off. These are reported mode values, not a measurement of TV scanout.

Earlier 0.3.3 evidence: `build/qa/manual-hdmi/1793899913803607/manual-results.json` and `session.log`. Initial black/operator separation, readable output and editing isolation have user reports. The response text reported by the user matches the native live item; some later checks used that sample response rather than the planned A/B fixtures. Frozen emergency using the on-screen button has both user confirmation and native revision evidence (35 frozen → 36 emergency black). The current A/B, physical keyboard and background observations are recorded below rather than inferred from that earlier run.

The first cable-loss test found a failure: the operator survived and no presentation window was reported on the laptop, but renderer PID 81526 exited after disarming. Its last frame was emergency black; a requested normal-slide Restore was not recorded before unplug. `renderer-os-log.json` records AppKit `terminate:` and approval at the failure time, rather than a crash stack. The first temporary library remains preserved; its normal Quit passed integrity `ok`.

The diagnostic repeat at `build/qa/manual-hdmi/1793901602552743` confirmed the cause on 0.3.3+6: AppKit scheduled its deferred last-window check after hiding the disconnected output, and `applicationShouldTerminateAfterLastWindowClosed` returned true for renderer PID 82500. The preserved `renderer-diagnostics.log` contains that native stack, followed by normal termination; `diagnostic-result.json` records the failure and required retest. `MainFlutterWindow.close` appeared during termination cleanup, rather than initiating the cable-loss shutdown.

Version **0.3.4+7** now returns false for the output role's last-window automatic termination check. The operator retains its existing save gate; explicit presentation-window close, authenticated shutdown and normal OS Quit retain their direct termination path. Opt-in lifecycle logging remains available with `CANTIVRA_HDMI_DIAGNOSTICS=1` and excludes credentials and Apple event payloads.

The fixed guided session at `build/qa/manual-hdmi/1793902175708487` is now closed. It used operator PID **83215** and renderer PID **83230**. Cable loss while black left that renderer alive and hidden; the user confirmed no presentation window appeared on the Mac. Reconnection remained hidden until explicit Apply. After explicit Go live, the user identified **HDMI TEST A**, matching native revision 1 (`hdmi-A:0`). Unplugging that normal slide at 18:14:36 UTC also preserved the renderer. Reconnect at 18:15:41 UTC kept it hidden, and explicit Apply at 18:16:01 UTC restored A without another Go live or revision change; the user confirmed controls stayed on the Mac throughout.

Frozen A at revision 2 also survived cable loss at 18:17:05 UTC and reconnect at 18:17:08 UTC. Explicit Apply at 18:17:19 UTC restored the same frozen A and renderer PID; the user confirmed Next could not change it. Native diagnostics record the deferred last-window check returning false and the output remaining hidden until re-arm. These observations pass the black, normal and frozen cable-loss cases **only on this direct Sony 4K/30 Hz connection**.

Physical **Fn+F12 while frozen** is now confirmed by the user and native revision 2 frozen → revision 3 emergency black at 18:19:44 UTC. Restore produced revision 4; Background off/on produced revisions 5/6 with matching user observations. The exact A correction was independently verified in SQLite while live remained unchanged at revision 6, and the user confirmed the original words still appeared on the TV before publishing. Presentations then produced A/B/A at revisions 7/8/9 with no reported intermediate flashes.

Bottom-arrow service navigation is now verified separately. The user chose **MANUAL HDMI TEST**, selected A from its Running order and published; the live counter read **1 / 2** with Next enabled. Using only bottom Next then Previous, the TV immediately showed B then corrected A, without another Go live. Native events match revision 10 A at 18:31:36 UTC → revision 11 B at 18:32:08 UTC → revision 12 A at 18:32:16 UTC. The earlier disabled-arrow report is not used as proof of a defect; single-slide Library publications intentionally have no next slide.

The user also confirmed the core Clear text, Black and Restore states. Native evidence records clear at revision 13 (18:32:37 UTC), normal at 14, background toggles at 15/16, black states at 17–21, normal at 22 with background hidden, and normal at 23 with background visible. Extra Black presses and background toggles occurred, so this verifies the observed states rather than an exact four-command-only sequence.

Normal save-and-Quit then closed the manual session at **18:33:23.258613 UTC on 5 November / 00:03:23 IST on 6 November**, recording `manual_session_closed` and database integrity `ok`. The wrapper recorded `manual_session_closed` with exit code 0; both operator PID 83215 and renderer PID 83230 were absent from the process list. The private test database and logs are preserved. The guided direct-Sony functional subset passes; the full physical hardware matrix remains open.

The current native software smoke passes in `build/qa/native-smoke-0.3.4-console.log`, including the new hidden-renderer regression with identical process/session/frame, normal Quit and recovery. All four completion markers are present. Its 1,000 navigation samples measured p50 **16.658 ms**, p95 **17.719 ms** and maximum **199.097 ms** to Flutter frame readiness; these are not physical scanout or full performance acceptance measurements.

All **255 automated Flutter tests** pass in `build/qa/flutter-tests-phase23-0.3.4-final.log`; formatting of 54 Dart files and static analysis pass. A preceding run exposed a race in a test's competing SQLite lock setup. The test now drains queued publication writes and acquires its lock before editing; its original persistence/live assertions remain, with additional pending-selection checks. The failure log is preserved separately.

The isolated **0.3.4+7** eight-hour run is **running, not complete**, at `build/qa/native-acceptance/1793903282052217`. It started on 5 November at **18:28:01 UTC / 23:58 IST**, using runner PID 84353 and test operator PID 84664. Its captured bundle version and native/AOT hashes are retained in `build/qa/macos-eight-hour-0.3.4-process.json`; console output is `build/qa/macos-eight-hour-0.3.4.log`. Initial checks passed 18 font cases, 100 search queries and 100 edits; they are not the final endurance result. The running 0.3.3 and 0.3.2 workloads remain historical for this policy change. No complete HDMI sign-off is claimed. Phase 4 has not started.
