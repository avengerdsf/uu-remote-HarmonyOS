#include "gamepad_bridge.h"
#include <GameControllerKit/game_device.h>
#include <GameControllerKit/game_pad.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <mutex>
#include <string>

namespace {
std::mutex mutex;
uu_core* owner = nullptr;
std::string selected;
struct State { uint16_t buttons = 0; int16_t lx = 0, ly = 0, rx = 0, ry = 0; uint8_t lt = 0, rt = 0; } state;

void Send(bool connected) {
    if (owner == nullptr) { return; }
    char command[300];
    if (connected) {
        snprintf(command, sizeof(command),
            "{\"method\":\"gamepadState\",\"params\":{\"state\":{\"buttons\":%u,\"lx\":%d,\"ly\":%d,\"rx\":%d,\"ry\":%d,\"lt\":%u,\"rt\":%u}}}",
            state.buttons, state.lx, state.ly, state.rx, state.ry, state.lt, state.rt);
    } else {
        snprintf(command, sizeof(command), "{\"method\":\"gamepadState\",\"params\":{\"state\":null}}");
    }
    uu_core_command(owner, command);
}

void SelectDevice() {
    GameDevice_AllDeviceInfos* all = nullptr;
    std::string next;
    if (OH_GameDevice_GetAllDeviceInfos(&all) == GAME_CONTROLLER_SUCCESS && all != nullptr) {
        int32_t count = 0, pads = 0;
        OH_GameDevice_AllDeviceInfos_GetCount(all, &count);
        for (int32_t i = 0; i < count; ++i) {
            GameDevice_DeviceInfo* info = nullptr;
            if (OH_GameDevice_AllDeviceInfos_GetDeviceInfo(all, i, &info) != GAME_CONTROLLER_SUCCESS || info == nullptr) { continue; }
            GameDevice_DeviceType type = UNKNOWN;
            if (OH_GameDevice_DeviceInfo_GetDeviceType(info, &type) == GAME_CONTROLLER_SUCCESS && type == GAME_PAD) {
                char* id = nullptr;
                if (OH_GameDevice_DeviceInfo_GetDeviceId(info, &id) == GAME_CONTROLLER_SUCCESS && id != nullptr) {
                    next = id; ++pads;
                }
                free(id);
            }
            OH_GameDevice_DestroyDeviceInfo(&info);
        }
        if (pads != 1) { next.clear(); }
        OH_GameDevice_DestroyAllDeviceInfos(&all);
    }
    std::lock_guard<std::mutex> lock(mutex);
    if (next != selected) { Send(false); state = {}; selected = next; }
}

uint16_t Mask(int32_t key) {
    switch (key) {
        case 2301: return 0x1000; case 2302: return 0x2000;
        case 2304: return 0x4000; case 2305: return 0x8000;
        case 2311: return 0x20; case 2312: return 0x10;
        case 2314: return 0x40; case 2315: return 0x80;
        case 2307: return 0x100; case 2308: return 0x200;
        case 2012: return 1; case 2013: return 2; case 2014: return 4; case 2015: return 8;
        default: return 0;
    }
}

void Button(const GamePad_ButtonEvent* event) {
    char* id = nullptr; int32_t key = 0; GamePad_Button_ActionType action = UP;
    if (OH_GamePad_ButtonEvent_GetDeviceId(event, &id) != GAME_CONTROLLER_SUCCESS) { free(id); return; }
    const bool valid = OH_GamePad_ButtonEvent_GetButtonCode(event, &key) == GAME_CONTROLLER_SUCCESS &&
        OH_GamePad_ButtonEvent_GetButtonAction(event, &action) == GAME_CONTROLLER_SUCCESS;
    std::lock_guard<std::mutex> lock(mutex);
    if (valid && owner != nullptr && id != nullptr && !selected.empty() && selected == id) {
        const auto mask = Mask(key);
        state.buttons = action == DOWN ? state.buttons | mask : state.buttons & ~mask;
        if (key == 2309) { state.lt = action == DOWN ? 255 : 0; }
        if (key == 2310) { state.rt = action == DOWN ? 255 : 0; }
        Send(true);
    }
    free(id);
}

int16_t AxisValue(double value, bool invert = false) {
    if (!std::isfinite(value)) { return 0; }
    return static_cast<int16_t>(std::clamp(std::round((invert ? -value : value) * 32767), -32768.0, 32767.0));
}
uint8_t Trigger(double value) {
    return std::isfinite(value) ? static_cast<uint8_t>(std::round(std::clamp(value, 0.0, 1.0) * 255)) : 0;
}

void Axis(const GamePad_AxisEvent* event) {
    char* id = nullptr; GamePad_AxisSourceType source = LEFT_THUMBSTICK;
    if (OH_GamePad_AxisEvent_GetDeviceId(event, &id) != GAME_CONTROLLER_SUCCESS) { free(id); return; }
    const bool valid = OH_GamePad_AxisEvent_GetAxisSourceType(event, &source) == GAME_CONTROLLER_SUCCESS;
    std::lock_guard<std::mutex> lock(mutex);
    if (valid && owner != nullptr && id != nullptr && !selected.empty() && selected == id) {
        double x = 0, y = 0;
        switch (source) {
            case LEFT_THUMBSTICK:
                OH_GamePad_AxisEvent_GetXAxisValue(event, &x); OH_GamePad_AxisEvent_GetYAxisValue(event, &y);
                state.lx = AxisValue(x); state.ly = AxisValue(y, true); break;
            case RIGHT_THUMBSTICK:
                OH_GamePad_AxisEvent_GetZAxisValue(event, &x); OH_GamePad_AxisEvent_GetRZAxisValue(event, &y);
                state.rx = AxisValue(x); state.ry = AxisValue(y, true); break;
            case LEFT_TRIGGER:
                OH_GamePad_AxisEvent_GetBrakeAxisValue(event, &x); state.lt = Trigger(x); break;
            case RIGHT_TRIGGER:
                OH_GamePad_AxisEvent_GetGasAxisValue(event, &x); state.rt = Trigger(x); break;
            case DPAD:
                OH_GamePad_AxisEvent_GetHatXAxisValue(event, &x); OH_GamePad_AxisEvent_GetHatYAxisValue(event, &y);
                state.buttons = (state.buttons & ~15) | (y < -0.5 ? 1 : y > 0.5 ? 2 : 0) | (x < -0.5 ? 4 : x > 0.5 ? 8 : 0); break;
            default: break;
        }
        Send(true);
    }
    free(id);
}

void Device(const GameDevice_DeviceEvent*) { SelectDevice(); }
#define BUTTONS(X) X(LeftShoulder) X(RightShoulder) X(LeftTrigger) X(RightTrigger) X(ButtonMenu) X(ButtonHome) \
    X(ButtonA) X(ButtonB) X(ButtonX) X(ButtonY) X(Dpad_LeftButton) X(Dpad_RightButton) X(Dpad_UpButton) \
    X(Dpad_DownButton) X(LeftThumbstick) X(RightThumbstick)
#define AXES(X) X(LeftThumbstick) X(RightThumbstick) X(LeftTrigger) X(RightTrigger) X(Dpad)
void Unregister() {
#define OFF_BUTTON(name) OH_GamePad_##name##_UnregisterButtonInputMonitor();
    BUTTONS(OFF_BUTTON)
#undef OFF_BUTTON
#define OFF_AXIS(name) OH_GamePad_##name##_UnregisterAxisInputMonitor();
    AXES(OFF_AXIS)
#undef OFF_AXIS
    OH_GameDevice_UnregisterDeviceMonitor();
}
}

int32_t SetGamepadEnabled(uu_core* core, bool enabled) {
    {
        std::lock_guard<std::mutex> lock(mutex);
        if (owner != nullptr && owner != core) { return enabled ? -1 : 0; }
        if (enabled && owner == core) { return 0; }
        if (!enabled) { Send(false); owner = nullptr; selected.clear(); state = {}; }
        else { owner = core; }
    }
    if (!enabled) { Unregister(); return 0; }
    int32_t error = OH_GameDevice_RegisterDeviceMonitor(Device);
#define ON_BUTTON(name) if (error == 0) { error = OH_GamePad_##name##_RegisterButtonInputMonitor(Button); }
    BUTTONS(ON_BUTTON)
#undef ON_BUTTON
#define ON_AXIS(name) if (error == 0) { error = OH_GamePad_##name##_RegisterAxisInputMonitor(Axis); }
    AXES(ON_AXIS)
#undef ON_AXIS
    if (error != 0) { SetGamepadEnabled(core, false); return error; }
    SelectDevice();
    return 0;
}
