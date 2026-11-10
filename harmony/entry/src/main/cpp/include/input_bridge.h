#ifndef UU_INPUT_BRIDGE_H
#define UU_INPUT_BRIDGE_H

#include <cstdint>

/*
 * Optional HarmonyOS host input adapter. Controller builds never inject input;
 * PC host control requires the API20+ user consent flow and must return false
 * when that flow is unavailable. This translation unit deliberately keeps the
 * controller package honest instead of shipping an unusable switch.
 */
class InputBridge {
public:
    static bool Capabilities(bool* capture, bool* injection);
    static int32_t RequestInjection();
    static int32_t InjectKey(int32_t keyCode, bool down);
    static int32_t InjectMouse(int32_t action, double x, double y, int32_t button);
};

#endif
