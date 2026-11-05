# Phase 2 remaining acceptance procedure

This is an executable handoff; it does not imply every listed check has run. The available development machine is macOS. The 0.3.4 direct Sony 4K/30 Hz functional subset has recorded results in [HDMI_TESTING.md](HDMI_TESTING.md). Windows execution, the wider physical multi-display matrix and trusted distribution remain open. Current software evidence and exact-version endurance status are in [PHASE23_STATUS.md](PHASE23_STATUS.md).

## Evidence to attach

For each run, record date, app version, archive SHA-256, OS version, CPU/GPU/RAM, display models, connection/distribution hardware, resolution/refresh rate, scaling and arrangement. Save the command output, per-scenario results and any camera recording used for flicker inspection. Use a disposable acceptance library, not the church's working library. Never include renderer descriptors or authentication tokens in attachments.

Do not substitute native-channel mocks, a successful compilation or a renderer frame-ready acknowledgement for the physical display observations below. A failed scenario remains an open defect, with its reproducer and operational consequence recorded.

## Windows build and process check

Use a logged-in Windows 10/11 desktop with Flutter 3.38.5 and Visual Studio's Desktop development with C++ workload. From the project directory in PowerShell:

```powershell
$ErrorActionPreference = 'Stop'
flutter doctor -v
if ($LASTEXITCODE -ne 0) { throw 'Flutter prerequisites failed' }
flutter pub get --enforce-lockfile
if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed' }
dart format --output=none --set-exit-if-changed lib test tool
if ($LASTEXITCODE -ne 0) { throw 'Formatting failed' }
flutter analyze --fatal-infos
if ($LASTEXITCODE -ne 0) { throw 'Analysis failed' }
flutter test test --reporter expanded
if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
dart run tool/run_native_smoke.dart windows
if ($LASTEXITCODE -ne 0) { throw 'Native process smoke failed' }
dart run tool/package_desktop.dart windows
if ($LASTEXITCODE -ne 0) { throw 'Normal application packaging failed' }
```

Require `PHASE2_NATIVE_SMOKE_OK` in `build/qa/native-smoke-phase2.log`, successful process exit and no surviving harness renderer. The smoke intentionally kills only its own temporary operator/renderer processes. It checks frame retention after operator termination, reconnect, replacement renderer starting black, explicit restore and emergency ordering. Version 0.3.3 uses the real native Quit/save gate on both platforms, including Windows `WM_CLOSE`; it no longer substitutes direct cleanup for native Windows close. Actual Windows execution and the close-button/Alt+F4/failed-save manual checks in [WINDOWS_TESTING.md](WINDOWS_TESTING.md) remain pending here. Its storage-recovery stage requires `STORAGE_RECOVERY_SMOKE_OK`, exact frame/process retention through corrupt-storage startup, emergency control and explicit retry, followed by saved correction and native Quit. Rebuilding the normal application after the harness prevents shipping the test entrypoint.

Extract the generated ZIP on a separate clean supported Windows account/machine, keeping its entire `Release` folder together. Run `cantivra.exe` without the Flutter SDK or Visual Studio installed. Verify SQLite startup, create/save/reopen, output launch, close and offline operation. Missing Visual C++ runtime or DLL requirements must be fixed in the distributable or documented installer prerequisites before sign-off. A ZIP containing only the EXE is insufficient.

## Physical HDMI acceptance, on both platforms

Start the normal release application with a disposable service containing clearly different slides A and B. In extended-display mode, configure the intended secondary monitor explicitly. Run the following with 1080p and 4K, then repeat on the actual church splitter/distribution hardware.

| Step | Action | Required observation |
| --- | --- | --- |
| 1 | Open output before publishing. | Secondary starts black; laptop contains operator controls only. |
| 2 | Publish A, then search, edit A to A2, change preview theme and prepare B. | TVs retain A until an explicit presentation action. |
| 3 | Publish A2; rapidly navigate and exercise clear/background/freeze/black/restore/emergency. | Expected captured frame appears without operator UI, stretching, cropping or visible intermediate blank frames. Emergency wins queued navigation. |
| 4 | Unplug HDMI while A is live. | Output hides/disarms; no congregation window becomes visible on the laptop. Accepted snapshot remains recoverable. |
| 5 | Replug the same display. | Output remains hidden/disarmed until explicit Apply/open; reconnection alone never reveals A. |
| 6 | Repeat cable loss/reconnect while frozen and black. | Hidden content never flashes; freeze/black state survives. |
| 7 | Terminate only the operator using OS process tools, leaving the renderer alive. Unplug and reconnect HDMI while the operator is absent. | Renderer itself hides/disarms. New operator reconnects without implicit publication or automatic rearm. |
| 8 | Publish again, terminate only the renderer, then explicitly reopen output. | Operator reports the lost renderer; replacement starts black. Restore is explicit. |
| 9 | Change resolution, refresh rate, OS scaling and which display is primary. | Correct bounds/safe area remain; a selected display becoming primary disarms output. Missing IDs never choose another screen. |
| 10 | Arrange secondary left of and above primary; test mixed DPI. | Correct placement with negative coordinates and no logical/physical pixel mismatch. |
| 11 | Save/edit/select a display profile without applying it. | Live placement, scale and content do not change. Explicit Apply performs the intended change. |
| 12 | Lock/unlock, sleep/wake, switch applications and open file dialogs. On macOS, test both separate-Spaces settings. | Controlled output state and correct focus return; operator dialogs never appear on the TVs. Record OS-imposed behavior. |
| 13 | Close normally with an unsaved correction; restart. | Draft persists, renderer closes on accepted Quit, startup does not republish the draft. |

Repeat the important loss/reconnect cases with a different monitor rather than the original one. An identity mismatch must stay unavailable until deliberately selected. Windows scaling cases include 100%, 150% and 200%; macOS includes Retina and non-Retina. Check profile calibration guides at each output size. Use a camera or capture card for scanout/flicker evidence.

## Sustained operation and performance

Follow the measured procedure in [QA.md](QA.md) and budgets in [ARCHITECTURE.md](ARCHITECTURE.md): a 10,000-record library; 100 varied search queries; 1,000 transitions while searching/editing/saving; combined process-memory sampling; eight hours of operation with injected connection/worker failures. Record median/p95/max, full hardware context and any deviations. The existing small windowed smoke timing is not acceptance for these budgets.

## Trusted release signing

These steps require release credentials supplied by the application owner. They have not run in this workspace. Do not paste private keys, certificate passwords or notarization credentials into source files or logs. The normal package helper currently produces a macOS ad-hoc development signature and optionally uses a configured Windows certificate; those results alone do not establish trusted end-user distribution.

For macOS direct distribution, use a Developer ID Application identity, timestamped hardened-runtime signatures for each nested code item and the outer app, then notarize and staple. Apple documents the requirements in [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and the commands in [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

After building the **normal** release app, set `CANTIVRA_SIGN_IDENTITY` to the owner's installed Developer ID Application identity and `CANTIVRA_NOTARY_PROFILE` to their previously configured keychain profile. On this framework-only bundle, run in Bash:

```bash
set -euo pipefail
: "${CANTIVRA_SIGN_IDENTITY:?Configure the release identity}"
: "${CANTIVRA_NOTARY_PROFILE:?Configure the notarization profile}"
CANTIVRA_APP='build/macos/Build/Products/Release/cantivra.app'
while IFS= read -r -d '' CANTIVRA_FRAMEWORK; do
  codesign --force --options runtime --timestamp \
    --sign "$CANTIVRA_SIGN_IDENTITY" "$CANTIVRA_FRAMEWORK"
done < <(find "$CANTIVRA_APP/Contents/Frameworks" -depth -type d -name '*.framework' -print0)
codesign --force --options runtime --timestamp \
  --entitlements macos/Runner/Release.entitlements \
  --sign "$CANTIVRA_SIGN_IDENTITY" "$CANTIVRA_APP"
codesign --verify --deep --strict "$CANTIVRA_APP"
ditto -c -k --sequesterRsrc --keepParent "$CANTIVRA_APP" dist/Cantivra-notarization.zip
xcrun notarytool submit dist/Cantivra-notarization.zip \
  --keychain-profile "$CANTIVRA_NOTARY_PROFILE" --wait
xcrun stapler staple "$CANTIVRA_APP"
xcrun stapler validate "$CANTIVRA_APP"
spctl --assess --type execute --verbose=2 "$CANTIVRA_APP"
ditto -c -k --sequesterRsrc --keepParent "$CANTIVRA_APP" dist/Cantivra-macOS-release-candidate.zip
shasum -a 256 dist/Cantivra-macOS-release-candidate.zip
```

Inspect the notarization result and require **Accepted** before stapling/distributing. If later dependencies add nested executables or dylibs, extend inside-out signing to those code items first. Do not run the ad-hoc package helper on the final signed app. Its development manifest does not describe this separately signed release candidate. Record a new checksum/signing manifest and test the downloaded/quarantined archive on a clean Mac, including offline launch and both-process local IPC with release entitlements.

For Windows, set the owner's certificate thumbprint in `CANTIVRA_SIGN_CERT_SHA1`, put the SDK's `signtool` on PATH and configure `CANTIVRA_TIMESTAMP_URL` with the certificate provider's RFC 3161 endpoint. After the normal release build:

```powershell
$ErrorActionPreference = 'Stop'
if (-not $env:CANTIVRA_SIGN_CERT_SHA1 -or -not $env:CANTIVRA_TIMESTAMP_URL) {
  throw 'Configure the release certificate and timestamp endpoint'
}
$CantivraRelease = 'build/windows/x64/runner/Release'
signtool sign /sha1 $env:CANTIVRA_SIGN_CERT_SHA1 /fd SHA256 `
  /tr $env:CANTIVRA_TIMESTAMP_URL /td SHA256 "$CantivraRelease/cantivra.exe"
if ($LASTEXITCODE -ne 0) { throw 'Signing failed' }
signtool verify /pa /all /tw "$CantivraRelease/cantivra.exe"
if ($LASTEXITCODE -ne 0) { throw 'Signature verification failed' }
Compress-Archive -LiteralPath $CantivraRelease `
  -DestinationPath dist/Cantivra-Windows-release-candidate.zip -Force
Get-FileHash dist/Cantivra-Windows-release-candidate.zip -Algorithm SHA256
```

Microsoft documents SHA-256 signing, RFC 3161 timestamping and application-policy verification in [SignTool](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool). Verify the expected publisher, timestamp and trust chain, then test installation/launch on a clean Windows machine. A successful signature check is not a guarantee of SmartScreen reputation. Record a fresh release manifest after signing rather than reusing the unsigned development manifest.

## Acceptance record

| Gate | Current status | Evidence required to close |
| --- | --- | --- |
| Automated/native macOS software behavior | See current verification report | Passing commands and scoped native log for the exact build. |
| Windows build/runtime/process survival | Not executed here | Windows command logs, native smoke marker and clean-machine results. |
| Physical HDMI/4K/mixed DPI, both platforms | Direct Sony 4K/30 Hz functional subset passed on macOS; wider matrix and Windows pending | Per-step hardware matrix outcomes and failure recordings; see [HDMI_TESTING.md](HDMI_TESTING.md). |
| Sustained reliability/performance | Full matrix not executed here | Dataset, timing distribution, memory samples and eight-hour report. |
| Trusted distribution | Not executed here | Owner-authorized signed/notarized artifacts, checksums and clean-machine results. |

Keep Phase 2's hardware/release acceptance open until the corresponding evidence exists. The user's current instruction is to start Phase 4 only after Phases 2 and 3 are complete. Deferred or running checks do not count as passing results.
