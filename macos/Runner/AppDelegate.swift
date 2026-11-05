import Cocoa
import FlutterMacOS

// Test-session diagnostics are opt-in and never include launch arguments,
// environment contents, renderer credentials, or Apple event payloads.
private let cantivraHDMIDiagnosticsEnabled =
  ProcessInfo.processInfo.environment["CANTIVRA_HDMI_DIAGNOSTICS"] == "1"

func cantivraHDMIDiagnostic(_ message: @autoclosure () -> String, includeStack: Bool = false) {
  guard cantivraHDMIDiagnosticsEnabled else { return }
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  var record: [String: Any] = [
    "atUtc": formatter.string(from: Date()),
    "pid": ProcessInfo.processInfo.processIdentifier,
    "message": message()
  ]
  if includeStack {
    record["stack"] = Array(Thread.callStackSymbols.dropFirst().prefix(10))
  }
  guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
        let json = String(data: data, encoding: .utf8),
        let line = "NATIVE_HDMI_DIAGNOSTIC \(json)\n".data(using: .utf8) else { return }
  FileHandle.standardError.write(line)
}

private func cantivraHDMIAppleEventIdentifiers() -> String {
  guard let event = NSAppleEventManager.shared().currentAppleEvent else { return "none" }
  return "class=0x\(String(event.eventClass, radix: 16)) id=0x\(String(event.eventID, radix: 16))"
}

@main
class AppDelegate: FlutterAppDelegate {
  private var operatorLifecycle: FlutterMethodChannel?
  private var closeRequestInFlight = false
  private var closeApproved = false

  func attachOperatorLifecycle(controller: FlutterViewController) {
    operatorLifecycle = FlutterMethodChannel(
      name: "cantivra/lifecycle", binaryMessenger: controller.engine.binaryMessenger)
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    cantivraHDMIDiagnostic(
      "applicationShouldTerminate role=\(CommandLine.arguments.contains("--cantivra-output") ? "output" : "operator") inFlight=\(closeRequestInFlight) approved=\(closeApproved) appleEvent=\(cantivraHDMIAppleEventIdentifiers())",
      includeStack: true)
    if CommandLine.arguments.contains("--cantivra-output") { return .terminateNow }
    if closeApproved {
      closeApproved = false
      return .terminateNow
    }
    if closeRequestInFlight { return .terminateCancel }
    guard let operatorLifecycle else {
      // No engine/handler can acknowledge that pending data is safe. Refuse
      // rather than silently treating startup failure as permission to exit.
      return .terminateCancel
    }
    closeRequestInFlight = true
    // Cancel this attempt while Dart saves. terminateLater enters AppKit's
    // nested termination loop, which can stall merged Flutter/platform work
    // and make an immediate second Quit bypass the pending acknowledgement.
    // Re-enter termination once, only after the asynchronous save approves it.
    RunLoop.main.perform(inModes: [.default, .modalPanel, .eventTracking]) { [weak self] in
      guard let self else { return }
      operatorLifecycle.invokeMethod("prepareClose", arguments: nil) { [weak self] response in
        guard let self else { return }
        let approved = (response as? Bool) == true
        self.closeRequestInFlight = false
        // A missing Dart handler, FlutterError, false or malformed reply all
        // leave the operator visible. There is no timeout that discards edits.
        guard approved else { return }
        self.closeApproved = true
        RunLoop.main.perform(inModes: [.default, .modalPanel, .eventTracking]) {
          sender.terminate(nil)
        }
      }
    }
    return .terminateCancel
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    let outputRole = CommandLine.arguments.contains("--cantivra-output")
    cantivraHDMIDiagnostic(
      "applicationShouldTerminateAfterLastWindowClosed role=\(outputRole ? "output" : "operator") terminate=\(!outputRole)",
      includeStack: true)
    // AppKit can run this check after a disconnected display is disarmed and
    // its window is hidden. Keep the independent renderer and captured frame
    // alive; explicit window close, authenticated shutdown and OS Quit still
    // enter applicationShouldTerminate directly.
    return !outputRole
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
