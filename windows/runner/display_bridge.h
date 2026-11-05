#ifndef RUNNER_DISPLAY_BRIDGE_H_
#define RUNNER_DISPLAY_BRIDGE_H_

namespace flutter {
class FlutterViewController;
}

// Register for the engine in this process with its explicit operator/output role.
void RegisterCantivraDisplays(flutter::FlutterViewController* controller,
                             bool output_capable);

#endif  // RUNNER_DISPLAY_BRIDGE_H_
