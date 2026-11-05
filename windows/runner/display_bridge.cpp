#include "display_bridge.h"
#include "display_identity.h"

#include <windows.h>
#include <flutter_windows.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <variant>
#include <vector>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using cantivra::windows::ActiveDisplayPath;

std::string Utf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                     static_cast<int>(value.size()), nullptr,
                                     0, nullptr, nullptr);
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      result.data(), size, nullptr, nullptr);
  return result;
}

struct Display {
  HMONITOR monitor;
  MONITORINFOEXW info;
  std::string id;
  std::string name;
  double scale;
  bool identity_eligible = false;
  std::string identity_reason;
  std::string source_name;
};

std::string InvariantName(const std::wstring& value) {
  if (value.empty()) return {};
  // Device paths and GDI join keys are case-insensitive. Normalize before they
  // cross the channel or enter saved profiles, independent of operator locale.
  const int size = LCMapStringEx(LOCALE_NAME_INVARIANT, LCMAP_LOWERCASE,
      value.data(), static_cast<int>(value.size()), nullptr, 0,
      nullptr, nullptr, 0);
  if (size <= 0) return {};
  std::wstring normalized(size, L'\0');
  if (LCMapStringEx(LOCALE_NAME_INVARIANT, LCMAP_LOWERCASE,
      value.data(), static_cast<int>(value.size()), normalized.data(), size,
      nullptr, nullptr, 0) != size) return {};
  return Utf8(normalized);
}

struct DisplayPathSnapshot {
  std::vector<ActiveDisplayPath> paths;
  bool complete = false;
};

DisplayPathSnapshot ActiveDisplayPaths() {
  // Microsoft documents that topology can change between sizing and querying.
  // Retry a bounded number of times; an unstable or unavailable snapshot makes
  // secondary output ineligible instead of guessing from DISPLAY1/2 names.
  // https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-querydisplayconfig
  for (int attempt = 0; attempt < 3; ++attempt) {
    UINT32 path_count = 0;
    UINT32 mode_count = 0;
    if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS,
            &path_count, &mode_count) != ERROR_SUCCESS ||
        path_count == 0 || path_count > 1024 || mode_count > 4096) return {};
    std::vector<DISPLAYCONFIG_PATH_INFO> paths(path_count);
    // QueryDisplayConfig requires non-null arrays even when a count is zero.
    std::vector<DISPLAYCONFIG_MODE_INFO> modes(std::max<UINT32>(mode_count, 1));
    const LONG status = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &path_count,
        paths.data(), &mode_count, modes.data(), nullptr);
    if (status == ERROR_INSUFFICIENT_BUFFER) continue;
    if (status != ERROR_SUCCESS) return {};
    paths.resize(path_count);
    DisplayPathSnapshot snapshot;
    for (const auto& path : paths) {
      if ((path.flags & DISPLAYCONFIG_PATH_ACTIVE) == 0) continue;
      DISPLAYCONFIG_SOURCE_DEVICE_NAME source{};
      source.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
      source.header.size = sizeof(source);
      source.header.adapterId = path.sourceInfo.adapterId;
      source.header.id = path.sourceInfo.id;
      // A missing source might be another clone of a known source, so a partial
      // snapshot must not allow any target to appear falsely unambiguous.
      if (DisplayConfigGetDeviceInfo(&source.header) != ERROR_SUCCESS ||
          source.viewGdiDeviceName[0] == L'\0') return {};
      const auto source_name = InvariantName(source.viewGdiDeviceName);
      if (source_name.empty()) return {};
      DISPLAYCONFIG_TARGET_DEVICE_NAME target{};
      target.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
      target.header.size = sizeof(target);
      target.header.adapterId = path.targetInfo.adapterId;
      target.header.id = path.targetInfo.id;
      const bool named =
          DisplayConfigGetDeviceInfo(&target.header) == ERROR_SUCCESS;
      snapshot.paths.push_back({source_name,
          named ? InvariantName(target.monitorDevicePath) : std::string{},
          named ? Utf8(target.monitorFriendlyDeviceName) : std::string{},
          path.targetInfo.targetAvailable != FALSE});
    }
    snapshot.complete = true;
    return snapshot;
  }
  return {};
}

std::string IdentityMessage(const std::string& reason) {
  if (reason == "display_mapping_ambiguous") {
    return "Use extended displays so each screen can be identified.";
  }
  if (reason == "display_disconnected") {
    return "This display is disconnecting. Check the connection and refresh displays.";
  }
  return "Windows could not identify this screen. Refresh displays and check the connection.";
}

BOOL CALLBACK CollectDisplay(HMONITOR monitor, HDC, LPRECT, LPARAM argument) {
  MONITORINFOEXW info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(monitor, reinterpret_cast<MONITORINFO*>(&info))) return TRUE;
  DISPLAY_DEVICEW device{};
  device.cb = sizeof(device);
  std::string name = Utf8(info.szDevice);
  if (EnumDisplayDevicesW(info.szDevice, 0, &device, 0)) {
    name = Utf8(device.DeviceString) + " (" + Utf8(info.szDevice) + ")";
  }
  const double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  reinterpret_cast<std::vector<Display>*>(argument)->push_back(
      {monitor, info, {}, name, scale, false, {}, {}});
  return TRUE;
}

std::vector<Display> Displays() {
  std::vector<Display> displays;
  if (!EnumDisplayMonitors(nullptr, nullptr, CollectDisplay,
          reinterpret_cast<LPARAM>(&displays))) return {};
  const auto snapshot = ActiveDisplayPaths();
  for (auto& display : displays) {
    display.source_name = InvariantName(display.info.szDevice);
    const auto identity = cantivra::windows::ResolveDisplayIdentity(
        display.source_name, snapshot.paths, snapshot.complete);
    display.id = identity.id;
    display.identity_eligible = identity.eligible;
    display.identity_reason = identity.unavailable_reason;
    if (!identity.name.empty()) {
      display.name = identity.name + " (" + Utf8(display.info.szDevice) + ")";
    }
  }
  return displays;
}

const Value* Argument(const Map* map, const char* key) {
  if (!map) return nullptr;
  const auto found = map->find(Value(key));
  return found == map->end() ? nullptr : &found->second;
}

class CantivraDisplayPlugin final : public flutter::Plugin {
 public:
  CantivraDisplayPlugin(flutter::PluginRegistrarWindows* registrar,
                        bool output_capable)
      : registrar_(registrar), output_capable_(output_capable) {
    hwnd_ = GetAncestor(registrar->GetView()->GetNativeWindow(), GA_ROOT);
    channel_ = std::make_unique<flutter::MethodChannel<Value>>(
        registrar->messenger(), "cantivra/display",
        &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      HandleMethod(call, std::move(result));
    });
    if (!output_capable_) {
      lifecycle_ = std::make_unique<flutter::MethodChannel<Value>>(
          registrar->messenger(), "cantivra/lifecycle",
          &flutter::StandardMethodCodec::GetInstance());
      close_state_->hwnd = hwnd_;
    }
    delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
        [this](HWND window, UINT message, WPARAM, LPARAM lparam)
            -> std::optional<LRESULT> {
          if (window != hwnd_) return std::nullopt;
          if (message == WM_CLOSE && !output_capable_ && !close_state_->approved) {
            RequestOperatorClose();
            return 0;
          }
          if (message == WM_GETMINMAXINFO && !output_capable_) {
            const double scale = GetDpiForWindow(hwnd_) / 96.0;
            auto limits = reinterpret_cast<MINMAXINFO*>(lparam);
            limits->ptMinTrackSize.x = static_cast<LONG>(1180 * scale);
            limits->ptMinTrackSize.y = static_cast<LONG>(760 * scale);
            return 0;
          }
          if (message == WM_DISPLAYCHANGE || message == WM_DEVICECHANGE ||
              message == WM_DPICHANGED ||
              message == WM_SETTINGCHANGE || message == WM_WINDOWPOSCHANGED ||
              message == WM_SHOWWINDOW || message == WM_SIZE) {
            DisplayChanged(message == WM_DISPLAYCHANGE ||
                message == WM_DEVICECHANGE || message == WM_SETTINGCHANGE);
            // A fullscreen destination uses exact physical monitor bounds, never
            // Windows' suggested rectangle on a possibly different monitor.
            if (output_capable_ && fullscreen_ && message == WM_DPICHANGED) return 0;
          }
          return std::nullopt;
        });
    if (output_capable_) {
      // This independent renderer starts hidden until authenticated Dart chooses
      // a destination. The runner's first-frame callback cannot show it.
      ShowWindow(hwnd_, SW_HIDE);
      reason_ = "startup_hidden";
      SetClassLongPtr(hwnd_, GCLP_HBRBACKGROUND,
                      reinterpret_cast<LONG_PTR>(GetStockObject(BLACK_BRUSH)));
    }
  }

  ~CantivraDisplayPlugin() override {
    close_state_->alive = false;
    registrar_->UnregisterTopLevelWindowProcDelegate(delegate_id_);
  }

 private:
  struct CloseState {
    HWND hwnd = nullptr;
    bool alive = true;
    bool pending = false;
    bool approved = false;
  };

  void RequestOperatorClose() {
    if (close_state_->pending || !lifecycle_) return;
    close_state_->pending = true;
    const auto state = close_state_;
    // The callback state outlives a pending platform reply safely. No blocking
    // wait runs inside WindowProc, so saving can continue on the Dart isolate.
    lifecycle_->InvokeMethod("prepareClose", nullptr,
        std::make_unique<flutter::MethodResultFunctions<Value>>(
            [state](const Value* response) {
              if (!state->alive) return;
              state->pending = false;
              const auto* approved = response ? std::get_if<bool>(response) : nullptr;
              if (approved && *approved && IsWindow(state->hwnd)) {
                state->approved = true;
                if (!PostMessageW(state->hwnd, WM_CLOSE, 0, 0)) {
                  // If the window stays open, a later close must still save any
                  // newer edits instead of reusing an approval for an old draft.
                  state->approved = false;
                }
              }
            },
            [state](const std::string&, const std::string&, const Value*) {
              if (state->alive) state->pending = false;
            },
            [state]() {
              if (state->alive) state->pending = false;
            }));
  }

  void PlaceOnDisplay(const Display& display, bool frame_changed = false) {
    const RECT& bounds = fullscreen_ ? display.info.rcMonitor : display.info.rcWork;
    int width = bounds.right - bounds.left;
    int height = bounds.bottom - bounds.top;
    int x = bounds.left;
    int y = bounds.top;
    if (!fullscreen_) {
      width = std::min(static_cast<int>(960 * display.scale), width * 4 / 5);
      height = std::min(width * 9 / 16 + static_cast<int>(40 * display.scale),
                        height * 4 / 5);
      x = bounds.left + ((bounds.right - bounds.left) - width) / 2;
      y = bounds.top + ((bounds.bottom - bounds.top) - height) / 2;
    }
    RECT current{};
    GetWindowRect(hwnd_, &current);
    if (frame_changed || current.left != x || current.top != y ||
        current.right - current.left != width || current.bottom - current.top != height) {
      SetWindowPos(hwnd_, fullscreen_ ? HWND_TOPMOST : HWND_NOTOPMOST,
                   x, y, width, height,
                   SWP_NOACTIVATE | (frame_changed ? SWP_FRAMECHANGED : 0));
    }
  }

  flutter::EncodableList DisplayList(const std::vector<Display>& displays) const {
    flutter::EncodableList list;
    for (const auto& display : displays) {
      const RECT& r = display.info.rcMonitor;
      const bool primary = (display.info.dwFlags & MONITORINFOF_PRIMARY) != 0;
      list.emplace_back(Map{
          {Value("id"), Value(display.id)}, {Value("name"), Value(display.name)},
          {Value("isPrimary"), Value(primary)},
          {Value("isOutputEligible"), Value(display.identity_eligible && !primary)},
          {Value("unavailableReason"), primary
              ? Value("This display is reserved for the operator.")
              : display.identity_eligible ? Value()
                  : Value(IdentityMessage(display.identity_reason))},
          {Value("x"), Value(static_cast<double>(r.left))},
          {Value("y"), Value(static_cast<double>(r.top))},
          {Value("width"), Value(static_cast<double>(r.right - r.left))},
          {Value("height"), Value(static_cast<double>(r.bottom - r.top))},
          {Value("scale"), Value(display.scale)},
      });
    }
    return list;
  }

  Map Status(const std::vector<Display>& displays) const {
    const auto selected = std::find_if(displays.begin(), displays.end(),
        [this](const Display& d) {
          return target_display_id_.empty()
              ? (d.info.dwFlags & MONITORINFOF_PRIMARY) != 0
              : d.id == target_display_id_ && d.identity_eligible &&
                    (d.info.dwFlags & MONITORINFOF_PRIMARY) == 0;
        });
    RECT r{};
    GetWindowRect(hwnd_, &r);
    const double scale = FlutterDesktopGetDpiForMonitor(
        MonitorFromWindow(hwnd_, MONITOR_DEFAULTTONEAREST)) / 96.0;
    return Map{
        {Value("role"), Value(output_capable_ ? "output" : "operator")},
        {Value("visible"), Value(IsWindowVisible(hwnd_) != FALSE && !IsIconic(hwnd_))},
        {Value("displayId"), target_display_id_.empty() ? Value() : Value(target_display_id_)},
        {Value("fullscreen"), Value(fullscreen_)},
        {Value("displayAvailable"), Value(selected != displays.end())},
        {Value("reason"), reason_.empty() ? Value() : Value(reason_)},
        {Value("x"), Value(static_cast<double>(r.left))},
        {Value("y"), Value(static_cast<double>(r.top))},
        {Value("width"), Value(static_cast<double>(r.right - r.left))},
        {Value("height"), Value(static_cast<double>(r.bottom - r.top))},
        {Value("scale"), Value(scale)},
    };
  }

  void EmitStatus(const std::vector<Display>& displays) {
    // Status and visible choices describe one identity snapshot, including a
    // transient failure. Avoid repeating relatively expensive CCD queries.
    auto status = Status(displays);
    status[Value("displays")] = Value(DisplayList(displays));
    channel_->InvokeMethod("displayChanged", std::make_unique<Value>(status));
  }

  void EmitStatus() { EmitStatus(Displays()); }

  void Disarm(const std::string& reason) {
    armed_ = false;
    reason_ = reason;
    ShowWindow(hwnd_, SW_HIDE);
  }

  void DisplayChanged(bool topology) {
    if (updating_window_) return;
    updating_window_ = true;
    const auto displays = Displays();
    if (output_capable_ && !target_display_id_.empty()) {
      const auto found = std::find_if(displays.begin(), displays.end(),
          [this](const Display& d) { return d.id == target_display_id_; });
      if (found == displays.end()) {
        Disarm("display_disconnected");
      } else if (!found->identity_eligible) {
        Disarm("display_identity_unavailable");
      } else if ((found->info.dwFlags & MONITORINFOF_PRIMARY) != 0) {
        Disarm("primary_display_reserved");
      } else if (armed_ && (found->monitor != armed_monitor_ ||
                            found->source_name != armed_source_name_)) {
        // HMONITOR and GDI bindings are volatile. A saved physical ID can help
        // offer the same target again, but never silently re-arm a new binding.
        Disarm("display_binding_changed");
      } else if (armed_ && fullscreen_) {
        PlaceOnDisplay(*found);
      } else if (armed_ && !topology &&
                 MonitorFromWindow(hwnd_, MONITOR_DEFAULTTONULL) != found->monitor) {
        Disarm("window_moved");
      }
    }
    updating_window_ = false;
    EmitStatus(displays);
  }

  void HandleMethod(const flutter::MethodCall<Value>& call,
                    std::unique_ptr<flutter::MethodResult<Value>> result) {
    const auto& method = call.method_name();
    if (method == "isProcessRunning") {
      const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      int64_t pid = 0;
      if (const auto* value = Argument(args, "pid")) {
        if (const auto* small = std::get_if<int32_t>(value)) pid = *small;
        if (const auto* large = std::get_if<int64_t>(value)) pid = *large;
      }
      if (pid <= 0 || pid > static_cast<int64_t>(MAXDWORD)) { result->Success(Value(false)); return; }
      HANDLE process = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION,
                                    FALSE, static_cast<DWORD>(pid));
      if (!process) {
        result->Success(Value(GetLastError() == ERROR_ACCESS_DENIED));
        return;
      }
      const DWORD wait = WaitForSingleObject(process, 0);
      CloseHandle(process);
      result->Success(Value(wait == WAIT_TIMEOUT || wait == WAIT_FAILED));
      return;
    }
    if (method == "getOutputStatus") {
      result->Success(Value(Status(Displays())));
      return;
    }
    if (method == "listDisplays") {
      result->Success(Value(DisplayList(Displays())));
      return;
    }
    if (method == "requestOperatorClose") {
      if (output_capable_) {
        result->Error("WRONG_WINDOW", "A presentation cannot close the operator.");
        return;
      }
      if (!IsWindow(hwnd_)) {
        result->Error("WINDOW_UNAVAILABLE", "The native window is unavailable.");
        return;
      }
      // Queue the real window-close message; the WindowProc delegate still
      // requires a successful prepareClose reply before allowing destruction.
      if (!PostMessageW(hwnd_, WM_CLOSE, 0, 0)) {
        result->Error("CLOSE_REQUEST_FAILED", "The native close request could not be queued.");
        return;
      }
      result->Success();
      return;
    }
    if (method == "configureOperator") {
      if (output_capable_) {
        result->Error("WRONG_WINDOW", "A presentation cannot become the operator window.");
        return;
      }
      SetWindowTextW(hwnd_, L"Cantivra");
      MONITORINFO monitor{};
      monitor.cbSize = sizeof(monitor);
      GetMonitorInfoW(MonitorFromWindow(hwnd_, MONITOR_DEFAULTTOPRIMARY), &monitor);
      const double scale = GetDpiForWindow(hwnd_) / 96.0;
      const RECT& r = monitor.rcWork;
      const int width = std::min(static_cast<int>(1440 * scale), static_cast<int>(r.right - r.left));
      const int height = std::min(static_cast<int>(900 * scale), static_cast<int>(r.bottom - r.top));
      SetWindowPos(hwnd_, nullptr, r.left + (r.right - r.left - width) / 2,
                   r.top + (r.bottom - r.top - height) / 2, width, height,
                   SWP_NOACTIVATE | SWP_NOZORDER);
      EmitStatus();
      result->Success();
      return;
    }
    if (method == "configureOutput" || method == "hideOutput" || method == "closeOutput") {
      if (method != "configureOutput" && !output_capable_) {
        result->Error("WRONG_WINDOW", "Only a presentation window can perform this operation.");
        return;
      }
      if (method == "hideOutput") {
        updating_window_ = true;
        Disarm("hidden");
        updating_window_ = false;
        EmitStatus();
        result->Success();
        return;
      }
      if (method == "closeOutput") {
        updating_window_ = true;
        Disarm("closing");
        updating_window_ = false;
        EmitStatus();
        result->Success();
        // Defer destruction until the method response has left the engine.
        PostMessageW(hwnd_, WM_CLOSE, 0, 0);
        return;
      }
      const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      const auto* destination = Argument(args, "displayId");
      const auto* fullscreen_value = Argument(args, "fullscreen");
      const auto* fullscreen_flag = fullscreen_value
          ? std::get_if<bool>(fullscreen_value) : nullptr;
      if (!destination || !fullscreen_flag) {
        result->Error("INVALID_OUTPUT_ARGUMENTS", "Choose a display ID or explicit windowed rehearsal and a fullscreen flag.");
        return;
      }
      std::string requested_id;
      bool has_requested_id = false;
      if (const auto* id = std::get_if<std::string>(destination)) {
        if (id->find_first_not_of(" \t\r\n") == std::string::npos) {
          result->Error("INVALID_OUTPUT_ARGUMENTS", "The display ID must be a nonempty string or null for rehearsal.");
          return;
        }
        requested_id = *id;
        has_requested_id = true;
      } else if (!std::holds_alternative<std::monostate>(*destination)) {
        result->Error("INVALID_OUTPUT_ARGUMENTS", "The display ID must be a nonempty string or null for rehearsal.");
        return;
      }
      const bool fullscreen = *fullscreen_flag;
      if (!output_capable_) {
        result->Error("WRONG_WINDOW", "The operator window cannot be used as presentation output.");
        return;
      }
      auto displays = Displays();
      auto found = std::find_if(displays.begin(), displays.end(),
          [&requested_id, has_requested_id](const Display& display) {
            return has_requested_id
                ? display.id == requested_id
                : (display.info.dwFlags & MONITORINFOF_PRIMARY) != 0;
          });
      if (found == displays.end()) {
        result->Error("DISPLAY_UNAVAILABLE", "The selected display is disconnected. Output remains hidden or unchanged.");
        return;
      }
      if (has_requested_id && (found->info.dwFlags & MONITORINFOF_PRIMARY) != 0) {
        result->Error("PRIMARY_DISPLAY_RESERVED", "The primary display is reserved for the operator. Use windowed rehearsal instead.");
        return;
      }
      if (has_requested_id && !found->identity_eligible) {
        result->Error("DISPLAY_IDENTITY_UNAVAILABLE",
            IdentityMessage(found->identity_reason));
        return;
      }
      updating_window_ = true;
      target_display_id_ = requested_id;
      armed_monitor_ = found->monitor;
      armed_source_name_ = found->source_name;
      fullscreen_ = fullscreen && has_requested_id;
      armed_ = true;
      reason_.clear();
      SetWindowTextW(hwnd_, L"Cantivra \u2014 Presentation");
      SetWindowLongPtrW(hwnd_, GWL_STYLE,
                        fullscreen_ ? WS_POPUP : WS_OVERLAPPEDWINDOW);
      PlaceOnDisplay(*found, true);
      ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
      updating_window_ = false;
      EmitStatus(displays);
      result->Success();
      return;
    }
    result->NotImplemented();
  }

  flutter::PluginRegistrarWindows* registrar_;
  bool output_capable_;
  HWND hwnd_ = nullptr;
  int delegate_id_ = -1;
  bool fullscreen_ = false;
  bool armed_ = false;
  bool updating_window_ = false;
  std::string reason_;
  std::string target_display_id_;
  HMONITOR armed_monitor_ = nullptr;
  std::string armed_source_name_;
  std::unique_ptr<flutter::MethodChannel<Value>> channel_;
  std::unique_ptr<flutter::MethodChannel<Value>> lifecycle_;
  std::shared_ptr<CloseState> close_state_ = std::make_shared<CloseState>();
};
}  // namespace

void RegisterCantivraDisplays(flutter::FlutterViewController* controller,
                             bool output_capable) {
  auto registrar = flutter::PluginRegistrarManager::GetInstance()
      ->GetRegistrar<flutter::PluginRegistrarWindows>(
          controller->engine()->GetRegistrarForPlugin("CantivraDisplayPlugin"));
  registrar->AddPlugin(std::make_unique<CantivraDisplayPlugin>(registrar, output_capable));
}
