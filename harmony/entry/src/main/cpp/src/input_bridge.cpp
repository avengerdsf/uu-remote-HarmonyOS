#include "input_bridge.h"

#include <hilog/log.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200
#define LOG_TAG "UUCoreInput"

bool InputBridge::Capabilities(bool* capture, bool* injection) {
    if (capture != nullptr) {
        *capture = false;
    }
    if (injection != nullptr) {
        *injection = false;
    }
    // OH_Input_RequestInjection is a PC/2in1-only API20 path. The controller
    // package does not link it; a host build must provide a verified adapter.
    return false;
}

int32_t InputBridge::RequestInjection() {
    OH_LOG_WARN(LOG_APP, "input injection adapter is not built for this package");
    return -1;
}

int32_t InputBridge::InjectKey(int32_t keyCode, bool down) {
    (void)keyCode;
    (void)down;
    return -1;
}

int32_t InputBridge::InjectMouse(int32_t action, double x, double y, int32_t button) {
    (void)action;
    (void)x;
    (void)y;
    (void)button;
    return -1;
}
