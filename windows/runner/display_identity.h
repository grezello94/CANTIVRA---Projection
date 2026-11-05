#ifndef RUNNER_DISPLAY_IDENTITY_H_
#define RUNNER_DISPLAY_IDENTITY_H_

#include <algorithm>
#include <string>
#include <vector>

// Platform-independent policy. Win32 supplies invariant-case source names and
// monitor device paths. A GDI source name is only a join key, never a persisted
// identity: Windows may assign it to another monitor after a topology change.
namespace cantivra {
namespace windows {

struct ActiveDisplayPath {
  std::string source_name;
  std::string monitor_path;
  std::string monitor_name;
  bool available;
};

struct DisplayIdentity {
  std::string id;
  std::string name;
  std::string unavailable_reason;
  bool eligible = false;
};

inline DisplayIdentity ResolveDisplayIdentity(
    const std::string& source_name,
    const std::vector<ActiveDisplayPath>& paths,
    bool complete_snapshot) {
  DisplayIdentity identity{
      "windows:unidentified:" + source_name, {},
      "display_identity_unavailable", false};
  if (!complete_snapshot || source_name.empty()) return identity;

  const ActiveDisplayPath* selected = nullptr;
  for (const auto& path : paths) {
    if (path.source_name != source_name) continue;
    // A cloned source fans out to multiple targets. Choosing only one would
    // incorrectly imply that the window can be restricted to that monitor.
    if (selected) {
      identity.unavailable_reason = "display_mapping_ambiguous";
      return identity;
    }
    selected = &path;
  }
  if (!selected) return identity;
  identity.name = selected->monitor_name;
  if (!selected->available) {
    identity.unavailable_reason = "display_disconnected";
    return identity;
  }
  if (selected->monitor_path.empty()) return identity;

  const auto matches = std::count_if(paths.begin(), paths.end(),
      [selected](const ActiveDisplayPath& path) {
        return path.monitor_path == selected->monitor_path;
      });
  if (matches != 1) {
    identity.unavailable_reason = "display_mapping_ambiguous";
    return identity;
  }
  // Device paths identify Windows monitor device instances. They are stronger
  // than DISPLAY1/2, but are not a claim of unique EDID/hardware serial numbers.
  identity.id = "windows:monitor:" + selected->monitor_path;
  identity.unavailable_reason.clear();
  identity.eligible = true;
  return identity;
}

}  // namespace windows
}  // namespace cantivra

#endif  // RUNNER_DISPLAY_IDENTITY_H_
