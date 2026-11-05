import Cocoa
import Darwin
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func close() {
    cantivraHDMIDiagnostic(
      "MainFlutterWindow.close role=\(CommandLine.arguments.contains("--cantivra-output") ? "output" : "operator") visible=\(isVisible)",
      includeStack: true)
    // The operator waits for saved drafts; an output process exits independently.
    NSApp.terminate(self)
  }

  override func awakeFromNib() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let outputRole = arguments.contains("--cantivra-output")
    let project = FlutterDartProject()
    project.dartEntrypointArguments = arguments
    let controller = FlutterViewController(project: project)
    controller.backgroundColor = .black
    backgroundColor = .black
    // The XIB is hidden too: authentication never exposes a guessed screen.
    orderOut(nil)
    if outputRole { NSApp.setActivationPolicy(.accessory) }
    let windowFrame = frame
    contentViewController = controller
    setFrame(windowFrame, display: false)
    RegisterGeneratedPlugins(registry: controller)
    CantivraDisplayPlugin.register(controller: controller, outputCapable: outputRole)
    if !outputRole {
      (NSApp.delegate as? AppDelegate)?.attachOperatorLifecycle(controller: controller)
    }
    // Flutter normally starts in viewWillAppear. This window deliberately
    // remains hidden until Dart selects a safe destination, so start its engine
    // explicitly after channels are registered rather than waiting on visibility.
    controller.engine.run(withEntrypoint: nil)
    super.awakeFromNib()
  }
}

/// Coordinates are Cocoa points (bottom-left origin). Only explicit configure
/// can arm and show the separate renderer process's congregation window.
private final class CantivraDisplayPlugin: NSObject, FlutterPlugin {
  private weak var window: NSWindow?
  private let channel: FlutterMethodChannel
  private let outputCapable: Bool
  private var targetDisplayId: String?
  private var fullScreenOutput = false
  private var armed = false
  private var reason: String?
  private var updatingWindow = false
  private var observers: [NSObjectProtocol] = []

  static func register(with registrar: FlutterPluginRegistrar) {
    install(registrar: registrar, outputCapable: CommandLine.arguments.contains("--cantivra-output"))
  }

  static func register(controller: FlutterViewController, outputCapable: Bool) {
    install(registrar: controller.registrar(forPlugin: "CantivraDisplayPlugin"), outputCapable: outputCapable)
  }

  private static func install(registrar: FlutterPluginRegistrar, outputCapable: Bool) {
    let channel = FlutterMethodChannel(name: "cantivra/display", binaryMessenger: registrar.messenger)
    let plugin = CantivraDisplayPlugin(window: registrar.view?.window, channel: channel, outputCapable: outputCapable)
    registrar.addMethodCallDelegate(plugin, channel: channel)
  }

  init(window: NSWindow?, channel: FlutterMethodChannel, outputCapable: Bool) {
    self.window = window
    self.channel = channel
    self.outputCapable = outputCapable
    reason = outputCapable ? "startup_hidden" : nil
    super.init()
    if outputCapable {
      window?.backgroundColor = .black
      window?.orderOut(nil)
    }
    observers.append(NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.displayChanged(topology: true) })
    for name in [NSWindow.didChangeScreenNotification, NSWindow.didResizeNotification,
                 NSWindow.didMoveNotification, NSWindow.didMiniaturizeNotification,
                 NSWindow.didDeminiaturizeNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
        [weak self] _ in self?.displayChanged(topology: false)
      })
    }
  }

  deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

  private static func displayId(_ screen: NSScreen) -> String {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? ""
  }

  private static func primaryId() -> String { String(CGMainDisplayID()) }

  private static func displays() -> [[String: Any]] {
    NSScreen.screens.map { screen in
      ["id": displayId(screen), "name": screen.localizedName,
       "isPrimary": displayId(screen) == primaryId(),
       "x": screen.frame.origin.x, "y": screen.frame.origin.y,
       "width": screen.frame.width, "height": screen.frame.height,
       "scale": screen.backingScaleFactor]
    }
  }

  private func disarm(_ why: String) {
    cantivraHDMIDiagnostic(
      "disarm begin role=\(outputCapable ? "output" : "operator") reason=\(why) target=\(targetDisplayId ?? "none") visible=\(window?.isVisible ?? false)")
    armed = false
    reason = why
    window?.orderOut(nil)
    cantivraHDMIDiagnostic(
      "disarm end reason=\(why) visible=\(window?.isVisible ?? false)")
  }

  private func displayChanged(topology: Bool) {
    if topology {
      cantivraHDMIDiagnostic(
        "displayChanged enter role=\(outputCapable ? "output" : "operator") updating=\(updatingWindow) armed=\(armed) target=\(targetDisplayId ?? "none") displays=\(NSScreen.screens.map(Self.displayId).joined(separator: ","))")
    }
    guard !updatingWindow else { return }
    updatingWindow = true
    if outputCapable, let targetDisplayId {
      if let target = NSScreen.screens.first(where: { Self.displayId($0) == targetDisplayId }) {
        if targetDisplayId == Self.primaryId() {
          disarm("primary_display_reserved")
        } else if armed && fullScreenOutput {
          // Valid resolution/DPI changes re-place without hiding or focus theft.
          if window?.frame != target.frame {
            window?.setFrame(target.frame, display: true, animate: false)
          }
        } else if armed && !topology && window?.screen.map(Self.displayId) != targetDisplayId {
          disarm("window_moved")
        }
      } else {
        disarm("display_disconnected")
      }
    }
    updatingWindow = false
    emitStatus()
    if topology {
      cantivraHDMIDiagnostic(
        "displayChanged exit armed=\(armed) reason=\(reason ?? "none") visible=\(window?.isVisible ?? false)")
    }
  }

  private func status() -> [String: Any] {
    let actualScreen = window?.screen
    let selected = targetDisplayId.flatMap { id in NSScreen.screens.first { Self.displayId($0) == id } }
    let available: Bool
    if let targetDisplayId {
      available = selected != nil && targetDisplayId != Self.primaryId()
    } else {
      available = !NSScreen.screens.isEmpty
    }
    let frame = window?.frame ?? .zero
    return ["role": outputCapable ? "output" : "operator",
            "visible": (window?.isVisible ?? false) && !(window?.isMiniaturized ?? false),
            "displayId": targetDisplayId as Any? ?? NSNull(),
            "fullscreen": fullScreenOutput, "displayAvailable": available,
            "reason": reason as Any? ?? NSNull(),
            "x": frame.origin.x, "y": frame.origin.y,
            "width": frame.width, "height": frame.height,
            "scale": actualScreen?.backingScaleFactor ?? 1.0]
  }

  private func emitStatus() {
    var payload = status()
    payload["displays"] = Self.displays()
    channel.invokeMethod("displayChanged", arguments: payload)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "isProcessRunning" {
      let value = (call.arguments as? [String: Any])?["pid"] as? NSNumber
      guard let pid = value?.int64Value, pid > 0, pid <= Int64(Int32.max) else { result(false); return }
      // kill(pid, 0) also succeeds for an exited, unreaped child. Such a zombie
      // cannot hold a presentation or accept control and must not block close.
      var info = proc_bsdinfo()
      if proc_pidinfo(pid_t(pid), PROC_PIDTBSDINFO, 0, &info,
                      Int32(MemoryLayout<proc_bsdinfo>.stride)) > 0 {
        result(info.pbi_status != UInt32(SZOMB))
        return
      }
      result(kill(pid_t(pid), 0) == 0 || errno == EPERM)
      return
    }
    guard let window else {
      result(FlutterError(code: "WINDOW_UNAVAILABLE", message: "The native window is unavailable.", details: nil))
      return
    }
    switch call.method {
    case "listDisplays": result(Self.displays())
    case "getOutputStatus": result(status())
    case "requestOperatorClose":
      guard !outputCapable else {
        result(FlutterError(code: "WRONG_WINDOW", message: "A presentation cannot close the operator.", details: nil)); return
      }
      result(nil)
      // Enter the same AppDelegate save acknowledgement as menu Quit and the
      // close button. Respond before termination can destroy the Dart engine.
      RunLoop.main.perform(inModes: [.default, .modalPanel, .eventTracking]) { NSApp.terminate(nil) }
    case "configureOperator":
      guard !outputCapable else {
        result(FlutterError(code: "WRONG_WINDOW", message: "A presentation cannot become the operator window.", details: nil)); return
      }
      updatingWindow = true
      window.title = "Cantivra"
      window.minSize = NSSize(width: 1180, height: 760)
      if let screen = window.screen ?? NSScreen.screens.first {
        let area = screen.visibleFrame
        let size = NSSize(width: min(1440, area.width), height: min(900, area.height))
        window.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                               width: size.width, height: size.height), display: true, animate: false)
      }
      window.makeKeyAndOrderFront(nil)
      updatingWindow = false
      emitStatus()
      result(nil)
    case "configureOutput":
      // A malformed destination must never degrade into primary-screen
      // rehearsal. Validate before changing window or arming state.
      guard let args = call.arguments as? [String: Any],
            let rawFullscreen = args["fullscreen"] as? NSNumber,
            CFGetTypeID(rawFullscreen) == CFBooleanGetTypeID(),
            let destination = args["displayId"] else {
        result(FlutterError(code: "INVALID_OUTPUT_ARGUMENTS", message: "Choose a display ID or explicit windowed rehearsal and a fullscreen flag.", details: nil)); return
      }
      let requestedId: String?
      if destination is NSNull {
        requestedId = nil
      } else if let value = destination as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        requestedId = value
      } else {
        result(FlutterError(code: "INVALID_OUTPUT_ARGUMENTS", message: "The display ID must be a nonempty string or null for rehearsal.", details: nil)); return
      }
      let fullscreen = rawFullscreen.boolValue && requestedId != nil
      guard outputCapable else {
        result(FlutterError(code: "WRONG_WINDOW", message: "The operator window cannot be used as presentation output.", details: nil)); return
      }
      let screen = NSScreen.screens.first { Self.displayId($0) == (requestedId ?? Self.primaryId()) }
      guard let screen else {
        result(FlutterError(code: "DISPLAY_UNAVAILABLE", message: "The selected display is disconnected. Output remains hidden or unchanged.", details: requestedId)); return
      }
      guard requestedId == nil || requestedId != Self.primaryId() else {
        result(FlutterError(code: "PRIMARY_DISPLAY_RESERVED", message: "The primary display is reserved for the operator. Use windowed rehearsal instead.", details: requestedId)); return
      }
      updatingWindow = true
      let frame: NSRect
      if fullscreen {
        frame = screen.frame
      } else {
        let area = screen.visibleFrame
        let width = min(960, area.width * 0.8)
        let height = min(width * 9 / 16 + 28, area.height * 0.8)
        frame = NSRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
      }
      targetDisplayId = requestedId
      fullScreenOutput = fullscreen
      armed = true
      reason = nil
      window.title = "Cantivra — Presentation"
      window.backgroundColor = .black
      window.isOpaque = true
      window.hasShadow = !fullscreen
      window.level = fullscreen ? .screenSaver : .normal
      window.collectionBehavior = [.fullScreenAuxiliary, .stationary]
      let style: NSWindow.StyleMask = fullscreen ? [.borderless] : [.titled, .closable, .resizable, .miniaturizable]
      if window.styleMask != style { window.styleMask = style }
      window.minSize = NSSize(width: 480, height: 270)
      window.setFrame(frame, display: true, animate: false)
      window.orderFront(nil)
      updatingWindow = false
      emitStatus()
      result(nil)
    case "hideOutput":
      guard outputCapable else { result(FlutterError(code: "WRONG_WINDOW", message: "Only presentation windows can be hidden.", details: nil)); return }
      disarm("hidden")
      emitStatus()
      result(nil)
    case "closeOutput":
      guard outputCapable else { result(FlutterError(code: "WRONG_WINDOW", message: "Only presentation windows can be closed by this method.", details: nil)); return }
      disarm("closing")
      emitStatus()
      result(nil)
      DispatchQueue.main.async { [weak window] in window?.close() }
    default: result(FlutterMethodNotImplemented)
    }
  }
}
