#include "../windows/runner/display_identity.h"

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

using cantivra::windows::ActiveDisplayPath;
using cantivra::windows::ResolveDisplayIdentity;

namespace {
int checks = 0;

void Check(bool condition, const char* message) {
  ++checks;
  if (!condition) {
    std::cerr << "FAIL: " << message << '\n';
    std::exit(EXIT_FAILURE);
  }
}
}  // namespace

int main() {
  const ActiveDisplayPath first{"display2", "monitor#a", "Church TV", true};
  const ActiveDisplayPath replacement{
      "display2", "monitor#b", "Replacement TV", true};
  const auto original = ResolveDisplayIdentity("display2", {first}, true);
  Check(original.eligible, "unique available physical target is eligible");
  Check(original.id == "windows:monitor:monitor#a", "ID uses device path");
  Check(original.name == "Church TV", "native friendly name preserved");
  Check(original.unavailable_reason.empty(), "valid identity has no error");

  const auto replaced = ResolveDisplayIdentity("display2", {replacement}, true);
  Check(replaced.eligible && replaced.id != original.id,
        "same GDI source cannot reuse another monitor's saved identity");
  auto moved = first;
  moved.source_name = "display5";
  Check(ResolveDisplayIdentity("display5", {moved}, true).id == original.id,
        "same physical device remains identifiable after GDI reassignment");

  const auto cloned = ResolveDisplayIdentity(
      "display2", {first, replacement}, true);
  Check(!cloned.eligible &&
            cloned.unavailable_reason == "display_mapping_ambiguous",
        "cloned GDI source must never select one target implicitly");
  Check(cloned.id.find("windows:unidentified:") == 0,
        "ambiguous diagnostic ID never resembles saved physical identity");

  const auto duplicate = ResolveDisplayIdentity("display2", {first, moved}, true);
  Check(!duplicate.eligible &&
            duplicate.unavailable_reason == "display_mapping_ambiguous",
        "duplicate device path on multiple sources is rejected");

  auto unavailable = first;
  unavailable.available = false;
  const auto removed = ResolveDisplayIdentity("display2", {unavailable}, true);
  Check(!removed.eligible &&
            removed.unavailable_reason == "display_disconnected",
        "active but already unavailable target is rejected");

  auto unnamed = first;
  unnamed.monitor_path.clear();
  Check(!ResolveDisplayIdentity("display2", {unnamed}, true).eligible,
        "missing monitor device path cannot fall back to GDI identity");
  Check(!ResolveDisplayIdentity("display2", {}, true).eligible,
        "source missing from path snapshot is unavailable");
  Check(!ResolveDisplayIdentity("display2", {first}, false).eligible,
        "incomplete/failed path enumeration cannot authorize output");
  Check(!ResolveDisplayIdentity("", {{"", "monitor#a", "Unknown", true}}, true)
             .eligible,
        "missing GDI join key cannot authorize output");

  // Even a disconnected cloned path can represent a transition in progress.
  // Wait for an unambiguous fresh snapshot instead of ignoring that target.
  Check(!ResolveDisplayIdentity("display2", {first, unavailable}, true).eligible,
        "disconnection race cannot disguise a cloned source");
  std::cout << "Windows display identity policy: " << checks
            << " checks passed (portable policy only; Win32 runtime untested).\n";
  return EXIT_SUCCESS;
}
