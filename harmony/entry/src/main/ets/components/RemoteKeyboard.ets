import { KeyCode } from '@kit.InputKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { LengthMetrics } from '@kit.ArkUI';
import { KeyMap } from '../model/KeyMap';
import { tr } from '../model/I18n';
import { iconResource } from '../model/Icons';
import { buttonPressShadow, buttonPressShadowSupported, floatingFeedback, pressedButtonAfterTouch,
  SessionMaterialBackplate, sessionMaterialSupported, sessionKeyboardFrame, sessionMenuMaterial } from '../theme/FloatingMaterial';

export type RemoteKeyboardMode = 'text' | 'computer' | 'shortcuts';
type ShortcutView = 'list' | 'edit' | 'form';

interface ComputerKey {
  label: string;
  code: KeyCode;
  weight: number;
}

export interface Shortcut {
  id: string;
  label: string;
  codes: KeyCode[];
}

interface KeyboardKeyButtonOptions {
  label: string;
  id: string;
  weight: number;
  height: number;
  icon?: Resource;
  selected?: boolean;
  requiresRemote?: boolean;
  action: () => void;
}

function key(label: string, code: KeyCode, weight: number = 1): ComputerKey {
  return { label: label, code: code, weight: weight };
}

const ESCAPE = key('Esc', KeyCode.KEYCODE_ESCAPE, 1.2);
const BACKSPACE = key('退格', KeyCode.KEYCODE_DEL, 1.8);
const TAB = key('Tab', KeyCode.KEYCODE_TAB, 1.6);
const CAPS = key('Caps', KeyCode.KEYCODE_CAPS_LOCK, 1.8);
const ENTER = key('Enter', KeyCode.KEYCODE_ENTER, 2.2);
const SHIFT = key('Shift', KeyCode.KEYCODE_SHIFT_LEFT, 2.2);
const RIGHT_SHIFT = key('Shift', KeyCode.KEYCODE_SHIFT_RIGHT, 2.8);
const FUNCTION_KEYS: ComputerKey[] = [
  key('F1', KeyCode.KEYCODE_F1), key('F2', KeyCode.KEYCODE_F2), key('F3', KeyCode.KEYCODE_F3),
  key('F4', KeyCode.KEYCODE_F4), key('F5', KeyCode.KEYCODE_F5), key('F6', KeyCode.KEYCODE_F6),
  key('F7', KeyCode.KEYCODE_F7), key('F8', KeyCode.KEYCODE_F8), key('F9', KeyCode.KEYCODE_F9),
  key('F10', KeyCode.KEYCODE_F10), key('F11', KeyCode.KEYCODE_F11), key('F12', KeyCode.KEYCODE_F12)
];
const DIGITS: ComputerKey[] = [
  key('1', KeyCode.KEYCODE_1), key('2', KeyCode.KEYCODE_2), key('3', KeyCode.KEYCODE_3),
  key('4', KeyCode.KEYCODE_4), key('5', KeyCode.KEYCODE_5), key('6', KeyCode.KEYCODE_6),
  key('7', KeyCode.KEYCODE_7), key('8', KeyCode.KEYCODE_8), key('9', KeyCode.KEYCODE_9), key('0', KeyCode.KEYCODE_0)
];
const QWERTY: ComputerKey[] = [
  key('Q', KeyCode.KEYCODE_Q), key('W', KeyCode.KEYCODE_W), key('E', KeyCode.KEYCODE_E), key('R', KeyCode.KEYCODE_R),
  key('T', KeyCode.KEYCODE_T), key('Y', KeyCode.KEYCODE_Y), key('U', KeyCode.KEYCODE_U),
  key('I', KeyCode.KEYCODE_I), key('O', KeyCode.KEYCODE_O), key('P', KeyCode.KEYCODE_P)
];
const ASDF: ComputerKey[] = [
  key('A', KeyCode.KEYCODE_A), key('S', KeyCode.KEYCODE_S), key('D', KeyCode.KEYCODE_D),
  key('F', KeyCode.KEYCODE_F), key('G', KeyCode.KEYCODE_G), key('H', KeyCode.KEYCODE_H),
  key('J', KeyCode.KEYCODE_J), key('K', KeyCode.KEYCODE_K), key('L', KeyCode.KEYCODE_L)
];
const ZXCV: ComputerKey[] = [
  key('Z', KeyCode.KEYCODE_Z), key('X', KeyCode.KEYCODE_X), key('C', KeyCode.KEYCODE_C), key('V', KeyCode.KEYCODE_V),
  key('B', KeyCode.KEYCODE_B), key('N', KeyCode.KEYCODE_N), key('M', KeyCode.KEYCODE_M),
  key(',', KeyCode.KEYCODE_COMMA), key('.', KeyCode.KEYCODE_PERIOD), key('/', KeyCode.KEYCODE_SLASH)
];
const GRAVE = key('`', KeyCode.KEYCODE_GRAVE);
const NUMBER_PUNCTUATION: ComputerKey[] = [key('-', KeyCode.KEYCODE_MINUS), key('=', KeyCode.KEYCODE_EQUALS)];
const TOP_PUNCTUATION: ComputerKey[] = [
  key('[', KeyCode.KEYCODE_LEFT_BRACKET), key(']', KeyCode.KEYCODE_RIGHT_BRACKET), key('\\', KeyCode.KEYCODE_BACKSLASH, 1.2)
];
const MIDDLE_PUNCTUATION: ComputerKey[] = [key(';', KeyCode.KEYCODE_SEMICOLON), key("'", KeyCode.KEYCODE_APOSTROPHE)];
const MODIFIERS_AND_SPACE: ComputerKey[] = [
  key('Ctrl', KeyCode.KEYCODE_CTRL_LEFT, 1.4), key('Win', KeyCode.KEYCODE_META_LEFT, 1.4),
  key('Alt', KeyCode.KEYCODE_ALT_LEFT, 1.4), key('Space', KeyCode.KEYCODE_SPACE, 5)
];
const ARROWS: ComputerKey[] = [
  key('←', KeyCode.KEYCODE_DPAD_LEFT), key('↑', KeyCode.KEYCODE_DPAD_UP),
  key('↓', KeyCode.KEYCODE_DPAD_DOWN), key('→', KeyCode.KEYCODE_DPAD_RIGHT)
];
const NAVIGATION_KEYS: ComputerKey[] = [
  key('Ins', KeyCode.KEYCODE_INSERT), key('Del', KeyCode.KEYCODE_FORWARD_DEL),
  key('Home', KeyCode.KEYCODE_MOVE_HOME), key('End', KeyCode.KEYCODE_MOVE_END),
  key('PgUp', KeyCode.KEYCODE_PAGE_UP), key('PgDn', KeyCode.KEYCODE_PAGE_DOWN)
];

const COMPUTER_ROWS: ComputerKey[][] = [
  [ESCAPE].concat(FUNCTION_KEYS),
  [GRAVE].concat(DIGITS, NUMBER_PUNCTUATION, [BACKSPACE]),
  [TAB].concat(QWERTY, TOP_PUNCTUATION),
  [CAPS].concat(ASDF, MIDDLE_PUNCTUATION, [ENTER]),
  [SHIFT].concat(ZXCV, [RIGHT_SHIFT]),
  MODIFIERS_AND_SPACE.concat(ARROWS),
  NAVIGATION_KEYS
];

const LETTER_ROWS: ComputerKey[][] = [
  QWERTY, ASDF, ZXCV, [ESCAPE, TAB, CAPS, SHIFT, BACKSPACE, ENTER],
  MODIFIERS_AND_SPACE
];
const EXTRA_ROWS: ComputerKey[][] = [
  FUNCTION_KEYS.slice(0, 6), FUNCTION_KEYS.slice(6), DIGITS,
  [GRAVE].concat(NUMBER_PUNCTUATION, TOP_PUNCTUATION, MIDDLE_PUNCTUATION),
  NAVIGATION_KEYS, [RIGHT_SHIFT].concat(ARROWS)
];
const PAGE_INDICATOR_SPACE: number = 20;
const PAGED_WIDTH: number = 600;
const SHORTCUTS_PREF: string = 'remoteKeyboardShortcuts';
const HIDDEN_SHORTCUTS_PREF: string = 'remoteKeyboardHiddenShortcuts';
const SHORTCUT_KEYS: ComputerKey[] = COMPUTER_ROWS.flat();
const SHORTCUT_EDITOR_CHROME: number = 88;

function shortcut(id: string, label: string, codes: KeyCode[]): Shortcut {
  return { id: id, label: label, codes: codes };
}

export const WINDOWS_SHOW_DESKTOP: KeyCode[] = [KeyCode.KEYCODE_META_LEFT, KeyCode.KEYCODE_D];

const WINDOWS_SHORTCUTS: Shortcut[][] = [
  [shortcut('task-manager', 'Ctrl+Shift+Esc', [KeyCode.KEYCODE_CTRL_LEFT, KeyCode.KEYCODE_SHIFT_LEFT, KeyCode.KEYCODE_ESCAPE]),
    shortcut('show-desktop', 'Win+D', WINDOWS_SHOW_DESKTOP),
    shortcut('explorer', 'Win+E', [KeyCode.KEYCODE_META_LEFT, KeyCode.KEYCODE_E])],
  [shortcut('lock', 'Win+L', [KeyCode.KEYCODE_META_LEFT, KeyCode.KEYCODE_L]),
    shortcut('run', 'Win+R', [KeyCode.KEYCODE_META_LEFT, KeyCode.KEYCODE_R]),
    shortcut('task-view', 'Win+Tab', [KeyCode.KEYCODE_META_LEFT, KeyCode.KEYCODE_TAB])]
];

function isMacPlatform(platform: string): boolean {
  return platform.toLowerCase() === 'macos';
}

function keyLabel(item: ComputerKey, mac: boolean): string {
  if (item.code === KeyCode.KEYCODE_DEL) { return tr(item.label); }
  if (!mac) { return item.label; }
  if (item.code === KeyCode.KEYCODE_META_LEFT) { return 'Cmd'; }
  return item.code === KeyCode.KEYCODE_ALT_LEFT ? 'Opt' : item.label;
}

function shortcutLabel(codes: KeyCode[], mac: boolean): string {
  return codes.map((code: KeyCode): string => {
    const item = SHORTCUT_KEYS.find((key: ComputerKey) => key.code === code);
    return item === undefined ? '' : keyLabel(item, mac);
  }).join('+');
}

function shortcutSignature(codes: KeyCode[]): string {
  const modifiers: number[] = [];
  const keys: number[] = [];
  for (const code of codes) {
    const scan = KeyMap.scanCode(code);
    if (KeyMap.isModifier(code)) { modifiers.push(scan); }
    else { keys.push(scan); }
  }
  return modifiers.sort((a: number, b: number) => a - b).concat(keys.sort((a: number, b: number) => a - b)).join('-');
}

function customShortcutId(codes: KeyCode[]): string {
  return 'custom-' + shortcutSignature(codes);
}

function customShortcut(codes: KeyCode[], mac: boolean): Shortcut {
  return shortcut(customShortcutId(codes), shortcutLabel(codes, mac), codes);
}

function decodeSavedChords(stored: string): KeyCode[][] | null {
  const codes = JSON.parse(stored) as KeyCode[][];
  if (!Array.isArray(codes)) { return null; }
  const loaded: KeyCode[][] = [];
  const seen = new Set<string>();
  for (const chord of codes) {
    if (!Array.isArray(chord) || chord.length === 0 || new Set(chord).size !== chord.length ||
      !chord.every((code: KeyCode) => SHORTCUT_KEYS.some((item: ComputerKey) => item.code === code))) { continue; }
    const signature = shortcutSignature(chord);
    if (seen.has(signature)) { continue; }
    seen.add(signature);
    loaded.push(chord);
  }
  return loaded;
}

export async function loadSavedRemoteShortcuts(store: preferences.Preferences, platform: string): Promise<Shortcut[]> {
  const stored = await store.get(SHORTCUTS_PREF, '[]');
  const mac = isMacPlatform(platform);
  return (decodeSavedChords(typeof stored === 'string' ? stored : '[]') ?? [])
    .map((codes: KeyCode[]): Shortcut => customShortcut(codes, mac));
}

@Component
export struct RemoteKeyboard {
  @Prop @Watch('onModeChanged') mode: RemoteKeyboardMode = 'computer';
  @Prop panelWidth: number = 360;
  @Prop panelHeight: number = 260;
  @Prop platform: string = '';
  @Prop armedKeys: number[] = [];
  @Prop inputEnabled: boolean = true;
  @State pressedButton: string = '';
  @State customKeys: KeyCode[][] = [];
  @State hiddenShortcuts: string[] = [];
  @State shortcutView: ShortcutView = 'list';
  @State shortcutDraft: KeyCode[] = [];
  @State shortcutError: string = '';
  @State shortcutSaving: boolean = false;
  private shortcutStore: preferences.Preferences | null = null;
  private shortcutEditingIndex: number = -1;
  private active: boolean = false;
  onKey: (code: number) => void = () => {};
  onShortcut: (codes: number[]) => void = () => {};

  aboutToAppear(): void {
    this.active = true;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.loadCustomShortcuts(context);
  }

  aboutToDisappear(): void { this.active = false; }

  private onModeChanged(): void {
    if (this.mode !== 'shortcuts') { this.shortcutView = 'list'; }
  }

  private async loadCustomShortcuts(context: common.UIAbilityContext): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, 'uu_remote_settings');
      const stored = await store.get(SHORTCUTS_PREF, '[]');
      const hidden = await store.get(HIDDEN_SHORTCUTS_PREF, '[]');
      if (!this.active) { return; }
      this.shortcutStore = store;
      const loaded = decodeSavedChords(typeof stored === 'string' ? stored : '[]');
      if (loaded === null) { return; }
      this.customKeys = loaded;
      const hiddenIds = JSON.parse(typeof hidden === 'string' ? hidden : '[]') as string[];
      if (Array.isArray(hiddenIds)) {
        this.hiddenShortcuts = hiddenIds.filter((id: string) => typeof id === 'string');
      }
    } catch (_) {
      // Leave built-in shortcuts available when preferences cannot be read.
    }
  }

  private openShortcutEditor(index: number = -1): void {
    if (this.shortcutSaving) { return; }
    this.shortcutEditingIndex = index;
    this.shortcutDraft = this.customKeys[index]?.slice() ?? [];
    this.shortcutError = '';
    this.shortcutView = 'form';
  }

  private pickingShortcut(): boolean {
    return this.mode === 'shortcuts' && this.shortcutView === 'form';
  }

  private computerKeySelected(code: KeyCode): boolean {
    return this.pickingShortcut() ? this.shortcutDraft.includes(code) : this.armedKeys.includes(code);
  }

  private pressComputerKey(code: KeyCode): void {
    if (!this.pickingShortcut()) { this.onKey(code); return; }
    if (this.shortcutSaving) { return; }
    this.shortcutDraft = this.shortcutDraft.includes(code) ?
      this.shortcutDraft.filter((selected: KeyCode) => selected !== code) : this.shortcutDraft.concat(code);
    this.shortcutError = '';
  }

  private orderedDraft(): KeyCode[] {
    return this.shortcutDraft.filter((code: KeyCode) => KeyMap.isModifier(code))
      .concat(this.shortcutDraft.filter((code: KeyCode) => !KeyMap.isModifier(code)));
  }

  private saveShortcut(): void {
    if (this.shortcutSaving || this.shortcutDraft.length === 0) { return; }
    const codes = this.orderedDraft();
    const signature = shortcutSignature(codes);
    if (this.customKeys.some((chord: KeyCode[], index: number) =>
      index !== this.shortcutEditingIndex && shortcutSignature(chord) === signature) ||
      this.presetShortcuts().flat().some((item: Shortcut) => shortcutSignature(item.codes) === signature)) {
      this.shortcutError = tr('这个快捷键已存在');
      return;
    }
    const next = this.shortcutEditingIndex < 0 ? this.customKeys.concat([codes]) :
      this.customKeys.map((chord: KeyCode[], index: number) => index === this.shortcutEditingIndex ? codes : chord);
    this.persistShortcuts(next);
  }

  private customShortcutIndex(id: string): number {
    return this.customKeys.findIndex((chord: KeyCode[]) => customShortcutId(chord) === id);
  }

  private deleteShortcut(item: Shortcut): void {
    if (this.shortcutSaving) { return; }
    const index = this.customShortcutIndex(item.id);
    if (index >= 0) {
      this.persistShortcuts(this.customKeys.filter((chord: KeyCode[], position: number) => position !== index));
    } else {
      const next = this.hiddenShortcuts.concat(this.presetShortcutKey(item));
      this.persistShortcutPreference(HIDDEN_SHORTCUTS_PREF, JSON.stringify(next), JSON.stringify(this.hiddenShortcuts),
        () => { this.hiddenShortcuts = next; });
    }
  }

  private persistShortcuts(next: KeyCode[][]): void {
    this.persistShortcutPreference(SHORTCUTS_PREF, JSON.stringify(next), JSON.stringify(this.customKeys),
      () => { this.customKeys = next; });
  }

  private async persistShortcutPreference(key: string, next: string, previous: string, commit: () => void): Promise<void> {
    const store = this.shortcutStore;
    if (store === null) { this.shortcutError = tr('无法保存快捷键'); return; }
    this.shortcutSaving = true;
    this.shortcutError = '';
    try {
      await store.put(key, next);
      await store.flush();
      if (this.active) {
        commit();
        if (this.mode === 'shortcuts') { this.shortcutView = 'edit'; }
      }
    } catch (_) {
      await store.put(key, previous).catch(() => {});
      if (this.active) { this.shortcutError = tr('无法保存快捷键'); }
    } finally {
      if (this.active) { this.shortcutSaving = false; }
    }
  }

  private presetShortcutKey(item: Shortcut): string {
    return item.id + ':' + shortcutSignature(item.codes);
  }

  private presetShortcuts(): Shortcut[][] {
    const mac = isMacPlatform(this.platform);
    const primary = mac ? KeyCode.KEYCODE_META_LEFT : KeyCode.KEYCODE_CTRL_LEFT;
    const prefix = mac ? 'Cmd+' : 'Ctrl+';
    const common: Shortcut[][] = [
      [shortcut('copy', prefix + 'C', [primary, KeyCode.KEYCODE_C]),
        shortcut('paste', prefix + 'V', [primary, KeyCode.KEYCODE_V]),
        shortcut('cut', prefix + 'X', [primary, KeyCode.KEYCODE_X])],
      [shortcut('select-all', prefix + 'A', [primary, KeyCode.KEYCODE_A]),
        shortcut('undo', prefix + 'Z', [primary, KeyCode.KEYCODE_Z]),
        shortcut('redo', mac ? 'Cmd+Shift+Z' : 'Ctrl+Y', mac ?
          [primary, KeyCode.KEYCODE_SHIFT_LEFT, KeyCode.KEYCODE_Z] : [primary, KeyCode.KEYCODE_Y])]
    ];
    if (mac) {
      common.push([shortcut('switch-app', 'Cmd+Tab', [primary, KeyCode.KEYCODE_TAB]),
        shortcut('close-window', 'Cmd+W', [primary, KeyCode.KEYCODE_W]),
        shortcut('force-quit', 'Cmd+Alt+Esc', [primary, KeyCode.KEYCODE_ALT_LEFT, KeyCode.KEYCODE_ESCAPE])]);
    } else {
      common.push([shortcut('switch-app', 'Alt+Tab', [KeyCode.KEYCODE_ALT_LEFT, KeyCode.KEYCODE_TAB]),
        shortcut('close-window', 'Alt+F4', [KeyCode.KEYCODE_ALT_LEFT, KeyCode.KEYCODE_F4])]);
      if (this.platform.toLowerCase() === 'windows') { common.push(...WINDOWS_SHORTCUTS); }
    }
    return common.map((row: Shortcut[]) =>
      row.filter((item: Shortcut) => !this.hiddenShortcuts.includes(this.presetShortcutKey(item))))
      .filter((row: Shortcut[]) => row.length > 0);
  }

  private customShortcuts(): Shortcut[] {
    const mac = isMacPlatform(this.platform);
    return this.customKeys.map((codes: KeyCode[]): Shortcut => customShortcut(codes, mac));
  }

  private shortcuts(): Shortcut[][] {
    const custom = this.customShortcuts();
    const rows: Shortcut[][] = [];
    for (let index = 0; index < custom.length; index += 3) { rows.push(custom.slice(index, index + 3)); }
    return rows.concat(this.presetShortcuts());
  }

  @Builder
  keyButton($$: KeyboardKeyButtonOptions) {
    Button({ type: ButtonType.Normal, stateEffect: !buttonPressShadowSupported }) {
      if ($$.icon !== undefined) {
        Image($$.icon).width(20).height(20).fillColor($$.selected ? Color.Black : $r('app.color.session_text'))
          .draggable(false).accessibilityLevel('no')
      } else {
        Text($$.label).fontSize(this.panelWidth < 440 && (this.mode === 'computer' || this.pickingShortcut()) ? 11 : 14)
          .fontColor($$.selected ? Color.Black : $r('app.color.session_text')).textAlign(TextAlign.Center).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }
    }.height($$.height).layoutWeight($$.weight).padding(0).borderRadius(8)
      .backgroundColor($$.selected ? $r('app.color.session_text') : $r('app.color.session_glass'))
      .enabled($$.requiresRemote === false || this.inputEnabled).focusOnTouch(false).id($$.id)
      .accessibilityText($$.label).accessibilitySelected($$.selected === true)
      .attributeModifier(floatingFeedback)
      .visualEffect(buttonPressShadow(($$.requiresRemote === false || this.inputEnabled) && this.pressedButton === $$.id))
      .onTouch((event: TouchEvent) => { this.pressedButton = pressedButtonAfterTouch(this.pressedButton, $$.id, event); })
      .onClick(() => { $$.action(); })
  }

  @Builder
  computerKeys(rows: ComputerKey[][], height: number) {
    ForEach(rows, (row: ComputerKey[]) => {
      Row({ space: 3 }) {
        ForEach(row, (item: ComputerKey) => {
          this.keyButton({ label: keyLabel(item, isMacPlatform(this.platform)), weight: item.weight, height: height,
            id: (this.pickingShortcut() ? 'session.keyboard.shortcut.pick.' : 'session.keyboard.key.') + KeyMap.scanCode(item.code),
            icon: item.code === KeyCode.KEYCODE_DEL ? $r('app.media.keyboard_backspace') : undefined,
            selected: this.computerKeySelected(item.code), requiresRemote: !this.pickingShortcut(),
            action: () => { this.pressComputerKey(item.code); } })
        }, (item: ComputerKey) => item.code.toString())
      }.width('100%')
    }, (row: ComputerKey[]) => row[0].code.toString())
  }

  @Builder
  shortcutEditLabel(label: string) {
    Text(label).fontSize(14).fontColor($r('app.color.session_text')).wordBreak(WordBreak.BREAK_WORD)
      .constraintSize({ minHeight: 36, maxWidth: this.panelWidth - 52 })
      .padding({ left: 10, right: 4, top: 6, bottom: 6 })
  }

  @Builder
  shortcutEditChip(item: Shortcut) {
    Row() {
      if (item.id.startsWith('custom-')) {
        Button({ type: ButtonType.Normal, stateEffect: !buttonPressShadowSupported }) {
          this.shortcutEditLabel(item.label)
        }.padding(0).borderRadius(8).backgroundColor(Color.Transparent).focusOnTouch(false)
          .attributeModifier(floatingFeedback).enabled(!this.shortcutSaving)
          .accessibilityText(item.label).id('session.keyboard.shortcut.edit.' + item.id)
          .visualEffect(buttonPressShadow(!this.shortcutSaving && this.pressedButton === item.id))
          .onTouch((event: TouchEvent) => { this.pressedButton = pressedButtonAfterTouch(this.pressedButton, item.id, event); })
          .onClick(() => {
            const index = this.customShortcutIndex(item.id);
            if (index >= 0) { this.openShortcutEditor(index); }
          })
      } else {
        this.shortcutEditLabel(item.label)
      }
      Button({ type: ButtonType.Normal, stateEffect: !buttonPressShadowSupported }) {
        Image(iconResource('close', true, false)).width(15).height(15).draggable(false).accessibilityLevel('no')
      }.width(36).height(36).padding(0).backgroundColor(Color.Transparent).focusOnTouch(false)
        .attributeModifier(floatingFeedback).enabled(!this.shortcutSaving)
        .accessibilityText(tr('删除') + ' ' + item.label).id('session.keyboard.shortcut.delete.' + item.id)
        .onClick(() => { this.deleteShortcut(item); })
    }.borderRadius(8).backgroundColor($r('app.color.session_glass')).flexShrink(0)
  }

  @Builder
  shortcutEditList() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(tr('编辑快捷键')).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.session_text'))
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          this.keyButton({ label: tr('新增快捷键'), icon: $r('app.media.keyboard_add'),
            id: 'session.keyboard.shortcut.add', weight: 1, height: 36,
            requiresRemote: false, action: () => { this.openShortcutEditor(); } })
        }.width(36)
        Row() {
          this.keyButton({ label: tr('完成'), id: 'session.keyboard.shortcut.done', weight: 1, height: 36,
            requiresRemote: false, action: () => { if (!this.shortcutSaving) { this.shortcutView = 'list'; } } })
        }.width(60)
      }.width('100%').id('session.keyboard.shortcut.edit-header')
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start,
        space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(6) } }) {
        ForEach(this.shortcuts().flat(), (item: Shortcut) => {
          this.shortcutEditChip(item)
        }, (item: Shortcut) => item.id)
      }.width('100%').id('session.keyboard.shortcut.edit-items')
      if (this.shortcutError.length > 0) {
        Text(this.shortcutError).fontSize(14).fontColor($r('app.color.session_error'))
      }
    }.width('100%').alignItems(HorizontalAlign.Start).id('session.keyboard.shortcut.edit-list')
  }

  @Builder
  shortcutEditor() {
    Column({ space: 6 }) {
      Text(this.shortcutError.length > 0 ? this.shortcutError :
        this.shortcutDraft.length > 0 ? shortcutLabel(this.orderedDraft(), isMacPlatform(this.platform)) : tr('点按键位组成快捷键'))
        .fontSize(14).fontColor(this.shortcutError.length > 0 ? $r('app.color.session_error') : $r('app.color.session_text'))
        .width('100%').height(28).padding({ left: 8, right: 8 }).textAlign(TextAlign.Center)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).id('session.keyboard.shortcut.preview')
      Scroll() { this.computerKeyboard() }
        .width('100%').scrollBar(BarState.Off).constraintSize({ maxHeight: Math.max(58, this.panelHeight - SHORTCUT_EDITOR_CHROME) })
      Row({ space: 8 }) {
        Button(tr('取消'), { type: ButtonType.Normal }).height(40).layoutWeight(1).borderRadius(8).fontSize(14)
          .backgroundColor($r('app.color.session_glass')).fontColor($r('app.color.session_text'))
          .attributeModifier(floatingFeedback).enabled(!this.shortcutSaving)
          .id('session.keyboard.shortcut.cancel').onClick(() => { this.shortcutView = 'edit'; this.shortcutError = ''; })
        Button(tr('保存快捷键'), { type: ButtonType.Normal }).height(40).layoutWeight(1).borderRadius(8).fontSize(14)
          .backgroundColor($r('app.color.session_selection')).fontColor($r('app.color.session_text'))
          .attributeModifier(floatingFeedback)
          .enabled(this.shortcutDraft.length > 0 && !this.shortcutSaving)
          .id('session.keyboard.shortcut.save').onClick(() => { this.saveShortcut(); })
      }.width('100%').padding({ left: 8, right: 8, bottom: 8 })
    }.width('100%').id('session.keyboard.shortcut.editor')
  }

  @Builder
  shortcutKeys(height: number) {
    ForEach(this.shortcuts(), (row: Shortcut[]) => {
      Row({ space: 3 }) {
        ForEach(row, (item: Shortcut) => {
          this.keyButton({ label: item.label, id: 'session.keyboard.shortcut.' + item.id, weight: 1, height: height,
            action: () => { this.onShortcut(item.codes); } })
        }, (item: Shortcut) => item.id)
      }.width('100%')
    }, (row: Shortcut[]) => row[0].id)
  }

  private keyHeight(rows: number, reserved: number = 0): number {
    const height = this.panelHeight - (this.pickingShortcut() ? SHORTCUT_EDITOR_CHROME : 0);
    return Math.max(22, Math.min(40, Math.floor((height - 16 - reserved - 3 * (rows - 1)) / rows)));
  }

  @Builder
  computerPage(rows: ComputerKey[][], id: string) {
    Column({ space: 3 }) {
      this.computerKeys(rows, this.keyHeight(EXTRA_ROWS.length, PAGE_INDICATOR_SPACE))
    }.width('100%').height('100%').alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Start)
      .padding({ left: 8, right: 8, top: 8, bottom: 8 + PAGE_INDICATOR_SPACE }).id(id)
  }

  @Builder
  pagedComputer() {
    Swiper() {
      this.computerPage(LETTER_ROWS, 'session.keyboard.computer.page.letters')
      this.computerPage(EXTRA_ROWS, 'session.keyboard.computer.page.extra')
    }.width('100%').height(this.keyHeight(EXTRA_ROWS.length, PAGE_INDICATOR_SPACE) * EXTRA_ROWS.length +
      3 * (EXTRA_ROWS.length - 1) + 16 + PAGE_INDICATOR_SPACE)
      .loop(false).indicator(Indicator.dot().bottom(3).color($r('sys.color.font_secondary'))
        .selectedColor($r('app.color.session_text')))
      .id('session.keyboard.computer.pages')
  }

  @Builder
  computerKeyboard() {
    if (this.panelWidth < PAGED_WIDTH) {
      this.pagedComputer()
    } else {
      Column({ space: 3 }) { this.computerKeys(COMPUTER_ROWS, this.keyHeight(COMPUTER_ROWS.length)) }
        .width('100%').padding(8)
    }
  }

  build() {
    Stack() {
      if (sessionMaterialSupported()) {
        SessionMaterialBackplate({ radius: $r('sys.float.corner_radius_level8'), nodeId: 'session.keyboard.material' })
      }
      if (this.pickingShortcut()) {
        this.shortcutEditor()
      } else {
        Scroll() {
          if (this.mode === 'computer') {
            this.computerKeyboard()
          } else {
            Column({ space: 3 }) {
              if (this.shortcutView === 'edit') { this.shortcutEditList() }
              else {
                Row() {
                  this.keyButton({ label: tr('编辑'), id: 'session.keyboard.shortcut.edit', weight: 1, height: 36,
                    requiresRemote: false, action: () => { this.shortcutError = ''; this.shortcutView = 'edit'; } })
                }.width('100%')
                this.shortcutKeys(this.keyHeight(this.presetShortcuts().length))
              }
            }.width('100%').padding(8)
          }
        }.scrollBar(BarState.Off).constraintSize({ maxHeight: this.panelHeight }).width('100%')
      }
    }.width(this.panelWidth).borderRadius($r('sys.float.corner_radius_level8'))
      .attributeModifier(sessionMaterialSupported() ? sessionKeyboardFrame : sessionMenuMaterial)
      .id('session.keyboard.' + this.mode)
      .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }
}
