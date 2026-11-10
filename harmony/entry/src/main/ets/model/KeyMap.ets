import { KeyCode } from '@kit.InputKit';

/**
 * HarmonyOS KeyCode -> canonical SDL/USB-HID scan code.
 * The Rust core keeps its existing Windows-VK / macOS-keycode tables; pages send
 * canonical scan codes so no platform-specific code is duplicated in ArkTS.
 */
const SCAN: Map<number, number> = new Map<number, number>();
SCAN.set(KeyCode.KEYCODE_A, 4);
SCAN.set(KeyCode.KEYCODE_B, 5);
SCAN.set(KeyCode.KEYCODE_C, 6);
SCAN.set(KeyCode.KEYCODE_D, 7);
SCAN.set(KeyCode.KEYCODE_E, 8);
SCAN.set(KeyCode.KEYCODE_F, 9);
SCAN.set(KeyCode.KEYCODE_G, 10);
SCAN.set(KeyCode.KEYCODE_H, 11);
SCAN.set(KeyCode.KEYCODE_I, 12);
SCAN.set(KeyCode.KEYCODE_J, 13);
SCAN.set(KeyCode.KEYCODE_K, 14);
SCAN.set(KeyCode.KEYCODE_L, 15);
SCAN.set(KeyCode.KEYCODE_M, 16);
SCAN.set(KeyCode.KEYCODE_N, 17);
SCAN.set(KeyCode.KEYCODE_O, 18);
SCAN.set(KeyCode.KEYCODE_P, 19);
SCAN.set(KeyCode.KEYCODE_Q, 20);
SCAN.set(KeyCode.KEYCODE_R, 21);
SCAN.set(KeyCode.KEYCODE_S, 22);
SCAN.set(KeyCode.KEYCODE_T, 23);
SCAN.set(KeyCode.KEYCODE_U, 24);
SCAN.set(KeyCode.KEYCODE_V, 25);
SCAN.set(KeyCode.KEYCODE_W, 26);
SCAN.set(KeyCode.KEYCODE_X, 27);
SCAN.set(KeyCode.KEYCODE_Y, 28);
SCAN.set(KeyCode.KEYCODE_Z, 29);
SCAN.set(KeyCode.KEYCODE_1, 30);
SCAN.set(KeyCode.KEYCODE_2, 31);
SCAN.set(KeyCode.KEYCODE_3, 32);
SCAN.set(KeyCode.KEYCODE_4, 33);
SCAN.set(KeyCode.KEYCODE_5, 34);
SCAN.set(KeyCode.KEYCODE_6, 35);
SCAN.set(KeyCode.KEYCODE_7, 36);
SCAN.set(KeyCode.KEYCODE_8, 37);
SCAN.set(KeyCode.KEYCODE_9, 38);
SCAN.set(KeyCode.KEYCODE_0, 39);
// Numpad keys use SDL/USB-HID scan codes 84..99, matching the host VK table.
SCAN.set(KeyCode.KEYCODE_NUMPAD_1, 89);
SCAN.set(KeyCode.KEYCODE_NUMPAD_2, 90);
SCAN.set(KeyCode.KEYCODE_NUMPAD_3, 91);
SCAN.set(KeyCode.KEYCODE_NUMPAD_4, 92);
SCAN.set(KeyCode.KEYCODE_NUMPAD_5, 93);
SCAN.set(KeyCode.KEYCODE_NUMPAD_6, 94);
SCAN.set(KeyCode.KEYCODE_NUMPAD_7, 95);
SCAN.set(KeyCode.KEYCODE_NUMPAD_8, 96);
SCAN.set(KeyCode.KEYCODE_NUMPAD_9, 97);
SCAN.set(KeyCode.KEYCODE_NUMPAD_0, 98);
SCAN.set(KeyCode.KEYCODE_NUMPAD_DOT, 99);
SCAN.set(KeyCode.KEYCODE_NUMPAD_DIVIDE, 84);
SCAN.set(KeyCode.KEYCODE_NUMPAD_MULTIPLY, 85);
SCAN.set(KeyCode.KEYCODE_NUMPAD_SUBTRACT, 86);
SCAN.set(KeyCode.KEYCODE_NUMPAD_ADD, 87);
SCAN.set(KeyCode.KEYCODE_NUMPAD_ENTER, 88);
SCAN.set(KeyCode.KEYCODE_ENTER, 40);
SCAN.set(KeyCode.KEYCODE_ESCAPE, 41);
SCAN.set(KeyCode.KEYCODE_DEL, 42);
SCAN.set(KeyCode.KEYCODE_TAB, 43);
SCAN.set(KeyCode.KEYCODE_SPACE, 44);
SCAN.set(KeyCode.KEYCODE_MINUS, 45);
SCAN.set(KeyCode.KEYCODE_EQUALS, 46);
SCAN.set(KeyCode.KEYCODE_LEFT_BRACKET, 47);
SCAN.set(KeyCode.KEYCODE_RIGHT_BRACKET, 48);
SCAN.set(KeyCode.KEYCODE_BACKSLASH, 49);
SCAN.set(KeyCode.KEYCODE_SEMICOLON, 51);
SCAN.set(KeyCode.KEYCODE_APOSTROPHE, 52);
SCAN.set(KeyCode.KEYCODE_GRAVE, 53);
SCAN.set(KeyCode.KEYCODE_COMMA, 54);
SCAN.set(KeyCode.KEYCODE_PERIOD, 55);
SCAN.set(KeyCode.KEYCODE_SLASH, 56);
SCAN.set(KeyCode.KEYCODE_CAPS_LOCK, 57);
SCAN.set(KeyCode.KEYCODE_F1, 58);
SCAN.set(KeyCode.KEYCODE_F2, 59);
SCAN.set(KeyCode.KEYCODE_F3, 60);
SCAN.set(KeyCode.KEYCODE_F4, 61);
SCAN.set(KeyCode.KEYCODE_F5, 62);
SCAN.set(KeyCode.KEYCODE_F6, 63);
SCAN.set(KeyCode.KEYCODE_F7, 64);
SCAN.set(KeyCode.KEYCODE_F8, 65);
SCAN.set(KeyCode.KEYCODE_F9, 66);
SCAN.set(KeyCode.KEYCODE_F10, 67);
SCAN.set(KeyCode.KEYCODE_F11, 68);
SCAN.set(KeyCode.KEYCODE_F12, 69);
SCAN.set(KeyCode.KEYCODE_SYSRQ, 70);
SCAN.set(KeyCode.KEYCODE_SCROLL_LOCK, 71);
SCAN.set(KeyCode.KEYCODE_BREAK, 72);
SCAN.set(KeyCode.KEYCODE_INSERT, 73);
SCAN.set(KeyCode.KEYCODE_MOVE_HOME, 74);
SCAN.set(KeyCode.KEYCODE_PAGE_UP, 75);
SCAN.set(KeyCode.KEYCODE_FORWARD_DEL, 76);
SCAN.set(KeyCode.KEYCODE_MOVE_END, 77);
SCAN.set(KeyCode.KEYCODE_PAGE_DOWN, 78);
SCAN.set(KeyCode.KEYCODE_DPAD_RIGHT, 79);
SCAN.set(KeyCode.KEYCODE_DPAD_LEFT, 80);
SCAN.set(KeyCode.KEYCODE_DPAD_DOWN, 81);
SCAN.set(KeyCode.KEYCODE_DPAD_UP, 82);
SCAN.set(KeyCode.KEYCODE_NUM_LOCK, 83);
SCAN.set(KeyCode.KEYCODE_CTRL_LEFT, 224);
SCAN.set(KeyCode.KEYCODE_SHIFT_LEFT, 225);
SCAN.set(KeyCode.KEYCODE_ALT_LEFT, 226);
SCAN.set(KeyCode.KEYCODE_META_LEFT, 227);
SCAN.set(KeyCode.KEYCODE_CTRL_RIGHT, 228);
SCAN.set(KeyCode.KEYCODE_SHIFT_RIGHT, 229);
SCAN.set(KeyCode.KEYCODE_ALT_RIGHT, 230);
SCAN.set(KeyCode.KEYCODE_META_RIGHT, 231);


export class KeyMap {
  static scanCode(keyCode: number): number {
    const value = SCAN.get(keyCode);
    return value === undefined ? -1 : value;
  }

  static isModifier(keyCode: number): boolean {
    return keyCode === KeyCode.KEYCODE_CTRL_LEFT || keyCode === KeyCode.KEYCODE_CTRL_RIGHT ||
      keyCode === KeyCode.KEYCODE_SHIFT_LEFT || keyCode === KeyCode.KEYCODE_SHIFT_RIGHT ||
      keyCode === KeyCode.KEYCODE_ALT_LEFT || keyCode === KeyCode.KEYCODE_ALT_RIGHT ||
      keyCode === KeyCode.KEYCODE_META_LEFT || keyCode === KeyCode.KEYCODE_META_RIGHT;
  }

  static isEnter(keyCode: number): boolean {
    return keyCode === KeyCode.KEYCODE_ENTER || keyCode === KeyCode.KEYCODE_NUMPAD_ENTER;
  }

  static isBackspace(keyCode: number): boolean {
    return keyCode === KeyCode.KEYCODE_DEL;
  }
}
