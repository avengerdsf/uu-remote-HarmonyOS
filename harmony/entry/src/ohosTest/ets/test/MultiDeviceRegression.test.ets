import { describe, it, expect, beforeAll, afterAll } from '@ohos/hypium';
import { abilityDelegatorRegistry, DisplayRotation, Driver, MouseButton as TestMouseButton, ON, ResizeDirection, WindowMode } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ComponentContent, display, LayeredDrawableDescriptor, PiPWindow, uiMaterial, uiObserver, window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { KeyCode } from '@kit.InputKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hdsDrawable, hdsMaterial } from '@kit.UIDesignKit';
import { MockSessionService } from '../../../main/ets/services/MockSessionService';
import { NativeSessionService } from '../../../main/ets/services/NativeSessionService';
import { ServiceHub } from '../../../main/ets/services/ServiceHub';
import { Router } from '../../../main/ets/model/Router';
import { ControlBarPosition, DeviceInfo, DevicesSnapshot, MaterialPreference, PortMapRule, RemoteCursor, SessionSnapshot,
  ThemePreference, VideoResolution } from '../../../main/ets/model/Models';
import { Fixtures } from '../../../main/ets/testkit/Fixtures';
import { UiProbe } from '../../../main/ets/testkit/UiProbe';
import { ThemeManager } from '../../../main/ets/theme/ThemeManager';
import { VideoViewport } from '../../../main/ets/model/VideoViewport';
import { sessionFloatingControl as floatingControl, sessionMenuMaterial, floatingFeedback } from '../../../main/ets/theme/FloatingMaterial';
import { iconResource } from '../../../main/ets/model/Icons';
import { VirtualMouse } from '../../../main/ets/components/VirtualMouse';

@Builder
function floatingFeedbackSample() {
  WithTheme({ colorMode: ThemeColorMode.DARK }) {
    Column({ space: 24 }) {
      Button({ type: ButtonType.Circle }) {
        Image(iconResource('mouse', true, false)).width(24).height(24)
          .fillColor($r('sys.color.icon_primary'))
      }.width(48).height(48).attributeModifier(floatingControl).id('feedback.control')
        .onClick(() => { AppStorage.setOrCreate('feedbackClicks', (AppStorage.get<number>('feedbackClicks') ?? 0) + 1); })
      Button({ type: ButtonType.Circle }) {
        Image(iconResource('keyboard', true, false)).width(24).height(24)
          .fillColor($r('sys.color.icon_primary'))
      }.width(48).height(48).attributeModifier(floatingControl).enabled(false).id('feedback.disabled')
        .onClick(() => { AppStorage.setOrCreate('feedbackClicks', 999); })
      Button({ type: ButtonType.Normal }) {
        Text('菜单项').fontColor($r('sys.color.font_primary'))
      }.width(208).height(48).backgroundColor('#A61C1D20').borderRadius(12)
        .attributeModifier(floatingFeedback).id('feedback.menu')
    }.width(280).height(280).justifyContent(FlexAlign.Center)
      .backgroundColor('#486A93').borderRadius(24).id('feedback.sample')
  }
}

@Builder
function virtualMouseMaterialSample() {
  WithTheme({ colorMode: ThemeColorMode.DARK }) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        ForEach([0, 1, 2, 3, 4, 5, 6, 7], (row: number) => {
          Text('Aa 123 字幕 Aa 123 字幕').width('100%').height(50).fontSize(20)
            .fontColor(row % 2 === 0 ? Color.Black : Color.White)
            .backgroundColor(row % 2 === 0 ? '#F3D64F' : '#307AD6')
        }, (row: number) => row.toString())
      }.width('100%').height('100%')
      VirtualMouse({ pageWidth: 320, pageHeight: 400 })
    }.width(320).height(400).id('material.mouse.sample')
  }
}

@Builder
function controlMaterialSample(background: string) {
  Stack({ alignContent: Alignment.TopStart }) {
    Column() {
      ForEach([0, 1, 2, 3, 4, 5, 6, 7], (row: number) => {
        Text('Aa 123 字幕 Aa 123 字幕').width('100%').height(48).fontSize(20)
          .fontColor(row % 2 === 0 ? Color.Black : Color.White)
          .backgroundColor(background === 'color' ? (row % 2 === 0 ? '#F3D64F' : '#307AD6') :
            background === 'split' ? (row % 2 === 0 ? Color.White : Color.Black) : background)
      }, (row: number) => row.toString())
    }.width('100%').height('100%')
    ForEach([false, true], (dark: boolean) => {
      WithTheme({ colorMode: ThemeColorMode.DARK }) {
        Stack({ alignContent: Alignment.TopStart }) {
        Row({ space: 8 }) {
          ForEach(['back', 'keyboard', 'rotate', 'more', 'mouse'], (icon: string) => {
            Button({ type: ButtonType.Circle }) {
              Image(iconResource(icon, dark, false)).width(24).height(24)
                .fillColor($r('sys.color.icon_primary')).objectFit(ImageFit.Contain)
                .id('material.icon.' + (dark ? 'dark.' : 'light.') + icon)
            }.width(48).height(48).attributeModifier(floatingControl)
              .id('material.control.' + (dark ? 'dark.' : 'light.') + icon)
          }, (icon: string) => icon)
        }.position({ x: 24, y: dark ? 248 : 24 })
        Column({ space: 2 }) {
          Text('远程设备').fontSize(16).fontColor($r('sys.color.font_primary'))
          Text('已连接').fontSize(12).fontColor($r('sys.color.font_secondary'))
        }.width(176).height(56).borderRadius(28).attributeModifier(floatingControl)
          .position({ x: 24, y: dark ? 312 : 88 })
        }.width('100%').height('100%')
      }
    }, (dark: boolean) => dark.toString())
  }.width(320).height(384).id('material.controls')
}

@Builder
function menuMaterialSample() {
  WithTheme({ colorMode: ThemeColorMode.DARK }) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        ForEach([0, 1, 2, 3, 4, 5, 6, 7], (row: number) => {
          Text('Aa 123 字幕 Aa 123 字幕').width('100%').height(48).fontSize(20)
            .fontColor(row % 2 === 0 ? Color.Black : Color.White)
            .backgroundColor(row % 2 === 0 ? '#F3D64F' : '#307AD6')
        }, (row: number) => row.toString())
      }.width('100%').height('100%')
      Column() {
        Column() {
          ForEach(['输入', '远程画面', '工具', '远端操作'], (label: string) => {
            Text(label).width('100%').height(48).fontSize(16).fontColor($r('sys.color.font_primary'))
          }, (label: string) => label)
        }.width('100%').height('100%')
          .blur(3, { grayscale: [0, 0] }, { disableSystemAdaptation: true })
      }.width(244).height(320).padding(16).borderRadius($r('sys.float.corner_radius_level8'))
        .backgroundColor(Color.Transparent).attributeModifier(sessionMenuMaterial)
        .position({ x: 32, y: 32 }).id('material.probe.parent')
      Column() {
        ForEach(['输入', '触控板', '只读模式', '隐藏工具条'], (label: string) => {
          Text(label).width('100%').height(48).fontSize(16).fontColor($r('sys.color.font_primary'))
            
        }, (label: string) => label)
      }.width(256).height(208).padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .borderRadius($r('sys.float.corner_radius_level8'))
        .backgroundColor(Color.Transparent).attributeModifier(sessionMenuMaterial)
        .position({ x: 26, y: 88 }).id('material.probe.child')
    }.width(320).height(384).id('material.probe')
  }
}

@Builder
function menuContrastSample(background: string) {
  WithTheme({ colorMode: ThemeColorMode.DARK }) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        ForEach([0, 1, 2, 3, 4, 5, 6, 7], (row: number) => {
          Text('Aa 123 字幕 Aa 123 字幕').width('100%').height(48).fontSize(20)
            .fontColor(row % 2 === 0 ? Color.Black : Color.White)
            .backgroundColor(background === 'mixed' ? (row < 4 ? '#60B3F0' : '#111111') : background)
        }, (row: number) => row.toString())
      }.width('100%').height('100%')
      Column() {
        Text('远程画面').fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary'))
          .height(48).width('100%').id('contrast.title')
        Row() {
          Text('画质').fontSize(16).fontColor($r('sys.color.font_primary'))
            .layoutWeight(1).id('contrast.label')
          Text('自动').fontSize(14).fontColor($r('sys.color.font_secondary')).id('contrast.value')
        }.height(48).width('100%')
        Row() {
          Text('高清 2M').fontSize(16).fontColor($r('sys.color.font_primary'))
            .layoutWeight(1).id('contrast.selected')
          Image(iconResource('check', true, false)).width(16).height(16)
            .fillColor($r('sys.color.icon_primary')).id('contrast.check')
        }.height(48).width('100%').padding({ left: 8, right: 8 }).borderRadius(12)
          .backgroundColor($r('app.color.session_selection'))
        Button({ type: ButtonType.Normal }) {
          Text('发送本机剪贴板').fontSize(16).fontColor($r('sys.color.font_primary'))
            .id('contrast.disabled')
        }.height(48).width('100%').backgroundColor(Color.Transparent).enabled(false)
        Text('结束连接').fontSize(16).fontColor($r('app.color.session_error'))
          .foregroundColor($r('app.color.session_error'))
          .backgroundColor($r('app.color.session_error_background')).borderRadius(12)
          .height(48).width('100%').id('contrast.destructive')
      }.width(256).padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .borderRadius($r('sys.float.corner_radius_level8')).attributeModifier(sessionMenuMaterial)
        .position({ x: 32, y: 64 }).id('contrast.menu')
    }.width(320).height(384).id('contrast.sample')
  }
}

class RegressionSessionService extends MockSessionService {
  terminalInputs: string[] = [];
  connectionForces: boolean[] = [];
  sentRemoteSettings: string[] = [];
  wakeRequests: string[] = [];
  private finishWakeRequest: (() => void) | null = null;
  nextDeviceOnline: boolean | null = null;
  private disconnectWait: Promise<void> | null = null;
  private disconnectResume: (() => void) | null = null;
  private disconnectFails: boolean = false;

  async connect(deviceId: string, force: boolean = false): Promise<void> {
    this.connectionForces.push(force);
    await super.connect(deviceId);
  }

  async remoteAction(action: string, enabled: boolean): Promise<void> {
    if (action === 'hostMute' || action === 'autoLock') {
      this.sentRemoteSettings.push(`${action}:${enabled}`);
      return;
    }
    await super.remoteAction(action, enabled);
  }

  async wakeDevice(deviceId: string): Promise<void> {
    this.wakeRequests.push(deviceId);
    await new Promise<void>((resolve) => { this.finishWakeRequest = resolve; });
  }

  completeWakeRequest(): void {
    this.finishWakeRequest?.();
    this.finishWakeRequest = null;
  }

  showWakeDevices(): void {
    const devices: DeviceInfo[] = [
      { id: 'wake-supported', name: '支持开机的电脑', platform: 'Windows', online: false,
        statusText: '离线', capabilities: ['desktop', 'wake'], connectLabel: '设备离线' },
      { id: 'wake-unavailable', name: '离线电脑', platform: 'Windows', online: false,
        statusText: '离线', capabilities: ['desktop'], connectLabel: '设备离线' },
      { id: 'wake-online', name: '在线电脑', platform: 'Windows', online: true,
        statusText: '在线', capabilities: ['desktop', 'wake'], connectLabel: '连接' }
    ];
    this.devices = { phase: this.devices.phase, devices: devices, error: null, generation: this.devices.generation + 1 };
    this.emitDevices();
  }

  async listDevices(automatic: boolean = false): Promise<void> {
    if (!automatic) { await super.listDevices(); return; }
    const online = this.nextDeviceOnline;
    if (online === null) { return; }
    this.nextDeviceOnline = null;
    const snapshot = JSON.parse(JSON.stringify(this.devices)) as DevicesSnapshot;
    const device = snapshot.devices.find((item: DeviceInfo) => item.id === 'demo-win-01');
    if (device === undefined) { return; }
    device.online = online;
    device.statusText = online ? '在线 · 可连接' : '离线';
    snapshot.generation++;
    this.devices = snapshot;
    this.emitDevices();
  }

  setDeviceBusy(busy: boolean | undefined): void {
    const device = this.devices.devices.find((item: DeviceInfo) => item.id === 'demo-win-01');
    if (device !== undefined) { device.busy = busy; }
    this.emitDevices();
  }

  setDeviceControlled(controlled: boolean | undefined, statusText: string): void {
    const snapshot = JSON.parse(JSON.stringify(this.devices)) as DevicesSnapshot;
    const device = snapshot.devices.find((item: DeviceInfo) => item.id === 'demo-win-01');
    if (device !== undefined) { device.controlled = controlled; device.statusText = statusText; }
    this.devices = snapshot;
    this.emitDevices();
  }

  holdDisconnect(fails: boolean): void {
    this.disconnectFails = fails;
    this.disconnectWait = new Promise<void>((resolve) => { this.disconnectResume = resolve; });
  }

  finishDisconnect(): void { this.disconnectResume?.(); this.disconnectResume = null; }

  async disconnect(): Promise<void> {
    const wait = this.disconnectWait;
    const fails = this.disconnectFails;
    this.disconnectWait = null;
    this.disconnectFails = false;
    await super.disconnect();
    if (wait !== null) {
      await wait;
      if (fails) { throw new Error('信令清理超时，远端会话释放尚未确认'); }
    }
  }

  setRemoteCursor(cursor: RemoteCursor | null): void { this.cursor = cursor; this.emitCursor(); }

  fingerprintPrompts: number = 0;
  fingerprintSupported: boolean = false;
  fingerprintSaved: boolean = true;

  setRemoteLock(locked: boolean, supported: boolean): void {
    const snapshot = JSON.parse(JSON.stringify(this.session)) as SessionSnapshot;
    snapshot.remoteUnlock = { generation: snapshot.generation, locked: locked, supported: supported };
    this.session = snapshot;
    this.emitSession();
  }

  fingerprintUnlockAvailable(): boolean { return this.fingerprintSupported; }
  async hasFingerprintUnlockPassword(): Promise<boolean> { return this.fingerprintSaved; }
  async fingerprintUnlock(): Promise<void> {
    this.fingerprintPrompts++;
    this.setRemoteLock(false, true);
  }

  setRemoteCursorInVideo(enabled: boolean): void {
    const snapshot = JSON.parse(JSON.stringify(this.session)) as SessionSnapshot;
    snapshot.remoteCursorInVideo = enabled;
    this.session = snapshot;
    this.emitSession();
  }

  async terminalWrite(text: string): Promise<void> {
    this.terminalInputs.push(text);
    await super.terminalWrite(text);
  }

  fillTerminalSessions(): void {
    this.terminal = { phase: 'ready', sessionId: 'spacing', output: '', error: null,
      sessions: [{ sessionId: 1, shell: 'sh', state: 'running' }] };
    this.emitTerminal();
  }

  fillDeviceList(): void {
    const devices: DeviceInfo[] = [];
    const source = Fixtures.devices();
    for (let index = 0; index < 24; index++) {
      const item = source[index % source.length];
      devices.push({ id: item.id + '-' + index, name: item.name + ' ' + index, platform: item.platform,
        online: item.online, statusText: item.statusText, capabilities: item.capabilities, connectLabel: item.connectLabel });
    }
    this.devices = { phase: this.devices.phase, devices: devices, error: null, generation: this.devices.generation + 1 };
    this.emitDevices();
  }

  showGroupedDevice(): void {
    this.devices = { phase: this.devices.phase, error: null, generation: this.devices.generation + 1,
      devices: [{ id: 'account-phone', name: 'Android fixture', platform: 'Android', online: true,
        statusText: '在线', capabilities: [], connectLabel: '不可远控' }] };
    this.emitDevices();
  }

  showPlatformDevices(): void {
    const platforms = ['Windows', 'Android', 'iOS', '电视'];
    this.devices = { phase: this.devices.phase, error: null, generation: this.devices.generation + 1,
      devices: platforms.map((platform: string, index: number): DeviceInfo => ({
        id: 'platform-icon-' + index, name: platform, platform: platform, online: true, statusText: '在线',
        capabilities: index === 0 ? ['desktop'] : [], connectLabel: index === 0 ? '连接' : '不可远控'
      })) };
    this.emitDevices();
  }

  setResolutionFixture(width: number, height: number, modes?: VideoResolution[]): void {
    this.videoSyncState = { fps: 60, quality: 5, chroma: 1, width: width, height: height, resolutionModes: modes };
    this.session = JSON.parse(JSON.stringify(this.session)) as SessionSnapshot;
    this.emitSession();
  }
}

interface ScrollBarInspector {
  $attrs?: Record<string, string>;
}

interface MenuColorRole {
  id: string;
  color: string;
}

@Builder
function textInputInjectionSample() {
  TextInput({ text: '' }).width(360).height(48).id('probe.text.input')
}

function scrollbarVisibility(id: string): string {
  const inspector: ScrollBarInspector = JSON.parse(getInspectorByKey(id + '.scrollbar'));
  return inspector.$attrs?.['visibility'] ?? '';
}

let driver: Driver;
let context: common.UIAbilityContext;
let mock: RegressionSessionService;
async function settle(): Promise<void> { await new Promise<void>((resolve) => { setTimeout(resolve, 700); }); }
async function route(name: string): Promise<void> { Router.reset(name); await settle(); }
async function terminalReady(): Promise<void> {
  for (let index = 0; index < 30; index++) {
    if (await (await driver.findComponent(ON.id('terminal.key.esc'))).isEnabled()) { return; }
    await settle();
  }
  throw new Error('Terminal renderer did not become ready');
}
async function scrollToId(containerId: string, targetId: string, attempts: number = 6): Promise<void> {
  for (let index = 0; index <= attempts; index++) {
    const container = await driver.findComponent(ON.id(containerId));
    const bounds = await container.getBounds();
    const items = await driver.findComponents(ON.id(targetId));
    let above: boolean = false;
    if (items !== null && items.length > 0) {
      const item = await items[0].getBounds();
      if (item.top >= bounds.top && item.bottom <= bounds.bottom) { return; }
      above = item.top < bounds.top;
    }
    if (index === attempts) { throw new Error('Cannot reach component: ' + targetId); }
    const x = Math.round((bounds.left + bounds.right) / 2);
    const height = bounds.bottom - bounds.top;
    await driver.swipe(x, Math.round(bounds.top + height * (above ? 0.25 : 0.7)),
      x, Math.round(bounds.top + height * (above ? 0.7 : 0.25)), 600);
    await settle();
  }
}
async function present(id: string): Promise<void> {
  const items = await driver.findComponents(ON.id(id));
  if (items === null || items.length === 0) { throw new Error('Missing visible component: ' + id); }
  if (items.length !== 1) { throw new Error('Expected one visible component: ' + id + ', found ' + items.length); }
  const rect = await items[0].getBounds();
  expect(rect.right > rect.left && rect.bottom > rect.top).assertTrue();
}
async function absent(id: string): Promise<void> {
  const items = await driver.findComponents(ON.id(id));
  if (items !== null && items.length > 0) { throw new Error('Unexpected visible component: ' + id); }
  expect(items === null || items.length === 0).assertTrue();
}
async function capture(name: string): Promise<void> {
  const path = context.cacheDir + '/three-device-' + name + '.png';
  expect(await driver.screenCap(path)).assertTrue();
  await abilityDelegatorRegistry.getAbilityDelegator().print('UU_UI_CAPTURE ' + path + '\n');
}

async function cursorAlignment(x: number, y: number): Promise<number[]> {
  const ui = (await window.getLastWindow(context)).getUIContext();
  const video = ui.getComponentUtils().getRectangleById('session.video');
  const pointer = ui.getComponentUtils().getRectangleById('session.mouse.pointer');
  await abilityDelegatorRegistry.getAbilityDelegator().print('UU_POINTER_TRANSFORM ' + JSON.stringify({
    position: video.windowOffset, size: video.size, translate: video.translate, scale: video.scale,
    pointer: pointer.windowOffset, target: [x, y] }) + '\n');
  return [video.windowOffset.x + ui.vp2px(video.translate.x) + video.size.width * (1 - video.scale.x) / 2 + video.size.width * video.scale.x * x,
    video.windowOffset.y + ui.vp2px(video.translate.y) + video.size.height * (1 - video.scale.y) / 2 + video.size.height * video.scale.y * y,
    pointer.windowOffset.x + ui.vp2px(4.56), pointer.windowOffset.y + ui.vp2px(4.58)];
}

async function feedbackFrame(name: string): Promise<void> {
  const pixels = await (await window.getLastWindow(context)).snapshot();
  const packer = image.createImagePacker();
  const path = context.cacheDir + '/three-device-feedback-' + name + '.png';
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  try { await packer.packToFile(pixels, file.fd, { format: 'image/png', quality: 100 }); }
  finally { fs.closeSync(file); await packer.release(); await pixels.release(); }
  await abilityDelegatorRegistry.getAbilityDelegator().print('UU_UI_CAPTURE ' + path + '\n');
}
async function floatingTabs(): Promise<void> {
  const density = display.getDefaultDisplaySync().densityPixels;
  const bar = await (await driver.findComponent(ON.type('TabBar'))).getBounds();
  const tabs = await (await driver.findComponent(ON.id('app.bottomNav'))).getBounds();
  const width = (bar.right - bar.left) / density;
  expect(Math.abs(width - 248) < 1).assertTrue();
  expect(Math.abs((bar.bottom - bar.top) / density - 56) < 1).assertTrue();
  const icons = await driver.findComponents(ON.type('Image').within(ON.type('TabBar')));
  const labels = await driver.findComponents(ON.type('Text').within(ON.type('TabBar')));
  expect(icons?.length ?? 0).assertEqual(3);
  expect(labels?.length ?? 0).assertEqual(3);
  for (let index = 0; index < 3; index++) {
    const icon = await icons![index].getBounds();
    const label = await labels![index].getBounds();
    expect(Math.abs((icon.right - icon.left) / density - 24) < 1).assertTrue();
    expect(icon.bottom <= label.top + 1).assertTrue();
    expect(Math.abs((icon.left + icon.right) - (label.left + label.right)) <= 2).assertTrue();
  }
  expect(bar.left > tabs.left + 15 * density && bar.right < tabs.right - 15 * density).assertTrue();
  const gap = (tabs.bottom - bar.bottom) / density;
  const win = await window.getLastWindow(context);
  const avoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
  await abilityDelegatorRegistry.getAbilityDelegator().print('UU_HDS_MATERIAL ' + JSON.stringify({
    deviceType: deviceInfo.deviceType, api: deviceInfo.sdkApiVersion, supported: hdsMaterial.getSystemMaterialTypes(),
    materialType: hdsMaterial.MaterialType.ADAPTIVE,
    materialLevel: hdsMaterial.getSystemMaterialTypes().includes(hdsMaterial.MaterialType.IMMERSIVE)
      ? hdsMaterial.MaterialLevel.ADAPTIVE : hdsMaterial.MaterialLevel.SMOOTH }) + '\n');
  await abilityDelegatorRegistry.getAbilityDelegator().print('UU_FLOATING_MEASUREMENT ' + JSON.stringify({
    bar: bar, tabs: tabs, density: density, gapVp: gap, avoid: avoid }) + '\n');
  const floatingGap = gap - avoid.bottomRect.height / density;
  expect(Math.abs(gap - Math.max(16, avoid.bottomRect.height / density)) < 1).assertTrue();
  await abilityDelegatorRegistry.getAbilityDelegator().print('UU_FLOATING_TABS ' + JSON.stringify({
    widthVp: width, gapVp: gap, systemBottomVp: avoid.bottomRect.height / density, floatingGapVp: floatingGap }) + '\n');
}
async function roundControl(id: string): Promise<void> {
  await present(id);
  const rect = await (await driver.findComponent(ON.id(id))).getBounds();
  expect(Math.abs((rect.right - rect.left) - (rect.bottom - rect.top)) <= 2).assertTrue();
}
async function checkFloatingControlMaterial(id: string, fallbackTint: string, navigationTitle: boolean = false): Promise<void> {
  const attrs = (JSON.parse(getInspectorByKey(id)) as ScrollBarInspector).$attrs;
  const effect = JSON.stringify(attrs?.['backgroundEffect'] ?? '');
  const material = JSON.stringify(attrs?.['systemMaterial'] ?? '');
  await abilityDelegatorRegistry.getAbilityDelegator().print('UU_CONTROL_MATERIAL ' + JSON.stringify({
    id: id, effect: attrs?.['backgroundEffect'], material: attrs?.['systemMaterial'] }) + '\n');
  if (navigationTitle && deviceInfo.apiAvailable('26.0.0') && uiMaterial.isImmersiveMaterialSupported()) {
    expect(material.includes('MaterialType.IMMERSIVE') && material.includes('ImmersiveStyle.THIN')).assertTrue();
    expect(effect.includes('"radius":12')).assertFalse();
  } else {
    expect(material.includes('MaterialType.IMMERSIVE')).assertFalse();
    expect(effect.includes('"radius":12') && effect.includes(fallbackTint)).assertTrue();
  }
}
async function standardIcon(id: string): Promise<void> {
  const icons = await driver.findComponents(ON.type('Image').within(ON.id(id)));
  expect(icons?.length ?? 0).assertEqual(1);
  const rect = await icons![0].getBounds();
  const density = display.getDefaultDisplaySync().densityPixels;
  expect(Math.abs((rect.right - rect.left) / density - 24) < 1).assertTrue();
  expect(Math.abs((rect.bottom - rect.top) / density - 24) < 1).assertTrue();
}

async function inlineSelect(id: string): Promise<void> {
  await revealSetting(id);
  const label = await (await driver.findComponent(ON.id(id + '.label'))).getBounds();
  const select = await (await driver.findComponent(ON.id(id))).getBounds();
  expect(label.right < select.left).assertTrue();
  expect(Math.abs((label.top + label.bottom) - (select.top + select.bottom)) <= 2).assertTrue();
}

async function selectedValue(id: string, value: string): Promise<void> {
  if (id.startsWith('settings.')) { await revealSetting(id); }
  const select = await driver.findComponent(ON.id(id));
  const text = await select.getOriginalText();
  await abilityDelegatorRegistry.getAbilityDelegator().print('UU_SELECT_VALUE ' + JSON.stringify({
    id: id, text: text }) + '\n');
  expect(text).assertEqual(value);
}

async function generalSettings(): Promise<void> {
  await route('portmap'); await route('settings');
  await (await driver.findComponent(ON.id('settings.general'))).click(); await settle();
}

async function revealSetting(id: string): Promise<void> {
  const list = await driver.findComponent(ON.id('settings.detail.scroll'));
  const bounds = await list.getBounds();
  const items = await driver.findComponents(ON.id(id));
  if (items !== null && items.length > 0) {
    const item = await items[0].getBounds();
    if (item.top >= bounds.top && item.bottom <= bounds.bottom) { return; }
  }
  await list.scrollToTop(); await settle();
  await scrollToId('settings.detail.scroll', id);
}

async function controlPosition(position: ControlBarPosition): Promise<void> {
  const page = await (await driver.findComponent(ON.id('session.page'))).getBounds();
  const toolbar = await (await driver.findComponent(ON.id('session.toolbar'))).getBounds();
  const density = display.getDefaultDisplaySync().densityPixels;
  if (position === 'left') { expect(Math.abs((toolbar.left - page.left) / density - 16) < 1).assertTrue(); }
  else if (position === 'right') { expect(Math.abs((page.right - toolbar.right) / density - 16) < 1).assertTrue(); }
  else { expect(Math.abs((page.left + page.right) - (toolbar.left + toolbar.right)) <= 2).assertTrue(); }
}

async function leftSection(id: string, labelLeft: number): Promise<void> {
  await revealSetting(id);
  const header = await (await driver.findComponent(ON.id(id))).getBounds();
  const density = display.getDefaultDisplaySync().densityPixels;
  await abilityDelegatorRegistry.getAbilityDelegator().print('UU_SECTION_BOUNDS ' + JSON.stringify({
    id: id, header: header, labelLeft: labelLeft, density: density }) + '\n');
  await capture(id.replace('settings.section.', 'settings-group-'));
  expect(Math.abs(header.left - labelLeft) <= density).assertTrue();
}

async function keyboardControlsDoNotOverlapHeader(): Promise<void> {
  const input = await (await driver.findComponent(ON.id('session.text.bar'))).getBounds();
  const headers = await driver.findComponents(ON.id('session.header'));
  if (headers !== null && headers.length > 0) {
    const header = await headers[0].getBounds();
    expect(input.top >= header.bottom).assertTrue();
  }
  const send = await (await driver.findComponent(ON.id('session.text.send'))).getBounds();
  const page = await (await driver.findComponent(ON.id('session.page'))).getBounds();
  expect(send.top >= page.top && send.bottom <= page.bottom).assertTrue();
}

async function menuAnchor(id: string = 'session.action.menu'): Promise<number[]> {
  await present(id);
  const ui = (await window.getLastWindow(context)).getUIContext();
  const menu = UiProbe.measure(ui, [id])[0];
  expect(menu.matchCount).assertEqual(1);
  return [menu.bounds[0] + menu.bounds[2], menu.bounds[1] + menu.bounds[3], menu.bounds[2]];
}

async function revealMenuItem(id: string): Promise<number> {
  const ui = (await window.getLastWindow(context)).getUIContext();
  let depth: number = 0;
  for (let level = 1; level <= 3; level++) {
    const body = UiProbe.measure(ui, ['session.menu.items.' + level])[0];
    if (body?.matchCount === 1 && body.bounds[2] > 0 && body.bounds[3] > 0) { depth = level; }
  }
  for (let attempt = 0; attempt <= 8; attempt++) {
    const body = UiProbe.measure(ui, ['session.menu.items.' + depth])[0];
    expect(body?.matchCount).assertEqual(1);
    const item = UiProbe.measure(ui, [id])[0];
    if (item?.matchCount === 1 && item.bounds[2] > 0 && item.bounds[3] > 0 && item.bounds[1] >= body.bounds[1] - 1 &&
      item.bounds[1] + item.bounds[3] <= body.bounds[1] + body.bounds[3] + 1) { break; }
    if (attempt === 8) {
      await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MENU_UNREACHABLE ' + JSON.stringify({ id: id, body: body.bounds, item: item?.bounds }) + '\n');
      await capture('unreachable-menu-item');
      throw new Error('Cannot reach menu item: ' + id);
    }
    const above = item?.matchCount === 1 && item.bounds[1] < body.bounds[1];
    const screen = await (await driver.findComponent(ON.id('session.menu.items.' + depth))).getBounds();
    const x = Math.round((screen.left + screen.right) / 2);
    const y1 = Math.round(screen.top + (screen.bottom - screen.top) * (above ? 0.25 : 0.75));
    const y2 = Math.round(screen.top + (screen.bottom - screen.top) * (above ? 0.75 : 0.25));
    await driver.swipe(x, y1, x, y2, 600); await settle();
  }
  return depth;
}

async function menuClick(id: string): Promise<void> {
  const depth = await revealMenuItem(id);
  const ui = (await window.getLastWindow(context)).getUIContext();
  const trigger = UiProbe.measure(ui, [id])[0];
  const label = UiProbe.measure(ui, [id + '.label'])[0];
  await (await driver.findComponent(ON.id(id))).click(); await settle();
  const headers = await driver.findComponents(ON.id('session.more.back.' + (depth + 1)));
  if (headers !== null && headers.length > 0) {
    const header = UiProbe.measure(ui, ['session.more.back.' + (depth + 1)])[0];
    const child = UiProbe.measure(ui, ['session.action.menu.' + id])[0];
    const title = UiProbe.measure(ui, ['session.more.title.' + (depth + 1)])[0];
    const upward = child.bounds[1] < header.bounds[1] - 1;
    expect(Math.abs(header.bounds[1] - trigger.bounds[1]) <= 1).assertTrue();
    expect(Math.abs(title.bounds[0] - label.bounds[0]) <= 1).assertTrue();
    expect(Math.abs(title.bounds[1] - label.bounds[1]) <= 1).assertTrue();
    const parent = UiProbe.measure(ui, ['session.menu.items.' + depth])[0];
    const original = UiProbe.measure(ui, [id])[0];
    expect(Math.abs(original.bounds[1] - trigger.bounds[1]) <= 1).assertTrue();
    expect(Math.abs(original.bounds[0] - trigger.bounds[0]) <= 1).assertTrue();
    expect(Math.abs(child.bounds[0] - parent.bounds[0] + 6) <= 1).assertTrue();
    expect(Math.abs(child.bounds[2] - parent.bounds[2] - 12) <= 1).assertTrue();
    expect(upward ? Math.abs(child.bounds[1] + child.bounds[3] - trigger.bounds[1] - trigger.bounds[3]) <= 2 :
      Math.abs(child.bounds[1] - trigger.bounds[1]) <= 2).assertTrue();
    const arrowId = 'session.menu.arrow.' + (depth + 1) + (upward ? '.up' : '.down');
    await present(arrowId);
    const arrow = UiProbe.measure(ui, [arrowId])[0];
    expect(Math.abs(arrow.bounds[2] - 16) <= 1 && Math.abs(arrow.bounds[3] - 16) <= 1).assertTrue();
    const body = UiProbe.measure(ui, ['session.menu.items.' + (depth + 1)])[0];
    expect(body.bounds[3] <= 4 * 48 + 3 * 8 + 1).assertTrue();
    await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MENU_DIRECTION ' + JSON.stringify({
      id: id, trigger: trigger.bounds, header: header.bounds, body: body.bounds,
      parent: parent.bounds, child: child.bounds, upward: upward }) + '\n');
  }
}

async function buttonSpacing(ids: string[], vertical: boolean = false): Promise<void> {
  const ui = (await window.getLastWindow(context)).getUIContext();
  const rows = UiProbe.measure(ui, ids);
  const gaps: number[] = [];
  for (let index = 0; index < rows.length; index++) {
    expect(rows[index].matchCount).assertEqual(1);
    if (index === 0) { continue; }
    const previous = rows[index - 1].bounds;
    const current = rows[index].bounds;
    const gap = vertical ? current[1] - previous[1] - previous[3] : current[0] - previous[0] - previous[2];
    gaps.push(gap);
  }
  await abilityDelegatorRegistry.getAbilityDelegator().print('UU_BUTTON_SPACING ' + JSON.stringify({
    ids: ids, vertical: vertical, gapsVp: gaps }) + '\n');
  for (const gap of gaps) { expect(Math.abs(gap - 8) <= 0.5).assertTrue(); }
}

async function stackMenuFits(expected: number[], id: string): Promise<void> {
  const actual = await menuAnchor(id);
  await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MENU_ANCHOR ' + JSON.stringify({ id: id, expected: expected, actual: actual }) + '\n');
  const ui = (await window.getLastWindow(context)).getUIContext();
  const menu = UiProbe.measure(ui, [id])[0];
  const page = UiProbe.measure(ui, ['session.page'])[0];
  const canvas = UiProbe.measure(ui, ['session.menu.stack'])[0];
  await capture('native-menu-layout');
  expect(Math.abs(actual[2] - expected[2]) <= 1).assertTrue();
  expect(menu.bounds[0] >= page.bounds[0] + 15 && menu.bounds[1] >= page.bounds[1] + 15).assertTrue();
  expect(actual[0] <= page.bounds[0] + page.bounds[2] - 15 && actual[1] <= page.bounds[1] + page.bounds[3] - 15).assertTrue();
  expect(menu.bounds[0] >= canvas.bounds[0] + 15 && menu.bounds[1] >= canvas.bounds[1] + 15).assertTrue();
  expect(actual[0] <= canvas.bounds[0] + canvas.bounds[2] - 15 && actual[1] <= canvas.bounds[1] + canvas.bounds[3] - 15).assertTrue();
}

async function remoteToolbarActions(prefix: string): Promise<void> {
  await mock.listDevices();
  await mock.connect('demo-win-01'); await settle(); await route('session');
  try {
    mock.emitFirstFrame(); await settle();
    await present('session.toolbar');
    await absent('session.inputMode'); await absent('session.quality');
    await roundControl('session.rotate'); await standardIcon('session.rotate');
    await roundControl('session.more'); await roundControl('session.back');
    await present('session.header');
    const header = await (await driver.findComponent(ON.id('session.header'))).getBounds();
    const surface = await (await driver.findComponent(ON.id('session.surface'))).getBounds();
    await abilityDelegatorRegistry.getAbilityDelegator().print('UU_SESSION_OVERLAY ' + JSON.stringify({ header: header, surface: surface }) + '\n');
    const ui = (await window.getLastWindow(context)).getUIContext();
    const native = UiProbe.measure(ui, ['session.page', 'session.header', 'session.surface']);
    await abilityDelegatorRegistry.getAbilityDelegator().print('UU_SESSION_NATIVE ' + JSON.stringify(native) + '\n');
    await capture(prefix + '-floating-header');
    const nativeHeader = native.find((rect) => rect.id === 'session.header');
    const nativeSurface = native.find((rect) => rect.id === 'session.surface');
    expect(nativeHeader?.matchCount).assertEqual(1); expect(nativeSurface?.matchCount).assertEqual(1);
    expect(nativeSurface!.bounds[1] <= nativeHeader!.bounds[1] &&
      nativeSurface!.bounds[1] + nativeSurface!.bounds[3] > nativeHeader!.bounds[1] + nativeHeader!.bounds[3]).assertTrue();
    await (await driver.findComponent(ON.id('session.back'))).click(); await settle();
    expect((await driver.findComponents(ON.text('结束后将断开与远端设备的画面和输入。')))?.length ?? 0).assertEqual(1);
    await (await driver.findComponent(ON.text('继续连接'))).click(); await settle();
    await present('session.toolbar');
    await standardIcon('session.keyboard'); await standardIcon('session.more'); await standardIcon('session.back');
    const density = display.getDefaultDisplaySync().densityPixels;
    const toolbar = await (await driver.findComponent(ON.id('session.toolbar'))).getBounds();
    expect((toolbar.right - toolbar.left) / density <= 210).assertTrue();
    await capture(prefix + '-compact-toolbar');
    const inputCount = mock.sentInputs.length;
    await roundControl('session.keyboard');
    await (await driver.findComponent(ON.id('session.keyboard'))).click(); await settle();
    await present('session.text.input'); await capture(prefix + '-keyboard');
    await keyboardControlsDoNotOverlapHeader();
    const textCount = mock.sentTexts.length;
    const textInput = await driver.findComponent(ON.id('session.text.input'));
    await textInput.clearText();
    await textInput.inputText('UI keyboard check', { paste: true, addition: false }); await settle();
    expect(await (await driver.findComponent(ON.id('session.text.input'))).getText()).assertEqual('UI keyboard check');
    expect(await (await driver.findComponent(ON.id('session.text.send'))).isEnabled()).assertTrue();
    await (await driver.findComponent(ON.id('session.text.send'))).click(); await settle();
    expect(mock.sentTexts.length).assertEqual(textCount + 1);
    expect(mock.sentTexts[textCount]).assertEqual('UI keyboard check');
    await roundControl('session.text.close');
    await (await driver.findComponent(ON.id('session.text.close'))).click(); await settle();
    await absent('session.text.input');
    await present('session.keyboard');
    const mode = mock.settings().touchMode;
    await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
    await present('session.more.input'); await present('session.quality'); await present('session.more.tools');
    await absent('session.more.files'); await absent('session.more.reboot');
    await capture(prefix + '-menu-categories');
    const anchor = await menuAnchor();
    await menuClick("session.more.remote");
    await capture(prefix + '-menu-remote-upward');
    await stackMenuFits(anchor, 'session.action.menu.session.more.remote');
    await revealMenuItem('session.more.reboot'); await present('session.more.reboot');
    await revealMenuItem('session.more.shutdown'); await present('session.more.shutdown');
    await menuClick("session.more.reboot");
    await (await driver.findComponent(ON.text('取消'))).click(); await settle();
    await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
    await menuClick("session.more.input");
    await capture(prefix + '-menu-input');
    await stackMenuFits(anchor, 'session.action.menu.session.more.input');
    await menuClick("session.inputMode");
    expect(mock.settings().touchMode !== mode).assertTrue();
    await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
    await menuClick("session.quality");
    await stackMenuFits(anchor, 'session.action.menu.session.quality'); await capture(prefix + '-quality');
    await menuClick("session.quality.select");
    await stackMenuFits(anchor, 'session.action.menu.session.quality.select');
    await capture(prefix + '-quality-options');
    await menuClick("session.quality.hd");
    expect(mock.settings().defaultVideoQuality).assertEqual('hd');
    await absent('session.action.menu');
    await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
    await menuClick("session.quality");
    await menuClick("session.quality.select");
    await revealMenuItem('session.quality.hd');
    expect(await (await driver.findComponent(ON.id('session.quality.hd'))).isSelected()).assertTrue();
    await capture(prefix + '-quality-selected');
    await driver.pressBack(); await settle();
    await stackMenuFits(anchor, 'session.action.menu.session.quality'); await present('session.resolution.select');
    await menuClick("session.fps.select");
    await stackMenuFits(anchor, 'session.action.menu.session.fps.select');
    await menuClick("session.fps.30");
    expect(mock.settings().defaultFrameRate).assertEqual(30);
    await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
    await menuClick("session.quality");
    await menuClick("session.resolution.select");
    await stackMenuFits(anchor, 'session.action.menu.session.resolution.select'); await capture(prefix + '-resolution-options');
    await menuClick("session.resolution.720p30");
    expect(mock.settings().defaultVideoProfile).assertEqual('720p30');
    await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
    await menuClick("session.quality");
    await menuClick("session.color.select");
    await stackMenuFits(anchor, 'session.action.menu.session.color.select'); await present('session.color.420');
    if (AppStorage.get<boolean>('decoderChroma444') !== true) { await absent('session.color.444'); }
    await menuClick("session.color.420");
    expect(mock.settings().trueColor).assertFalse();
    await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
    await menuClick("session.quality");
    await menuClick("session.resolution.select");
    await revealMenuItem('session.resolution.720p30');
    expect(await (await driver.findComponent(ON.id('session.resolution.720p30'))).isSelected()).assertTrue();
    await (await driver.findComponent(ON.id('session.more.back.2'))).click(); await settle();
    await stackMenuFits(anchor, 'session.action.menu.session.quality');
    await revealMenuItem('session.color.select'); await present('session.color.select');
    await (await driver.findComponent(ON.id('session.more.back.1'))).click(); await settle();
    await stackMenuFits(anchor, 'session.action.menu'); await present('session.more.input');
    await revealMenuItem('session.more.audio');
    expect(await (await driver.findComponent(ON.id('session.more.audio.value'))).getText()).assertEqual(`${mock.audioVolume()}%`);
    await menuClick("session.more.audio");
    await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
    await menuClick("session.more.input");
    await menuClick("session.more.hide");
    await absent('session.toolbar'); await absent('session.toolbar.restore');
    await driver.pressBack(); await settle();
    await present('session.toolbar');
    await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
    await menuClick("session.more.input");
    await menuClick("session.more.viewOnly");
    expect(mock.sessionSnapshot().viewOnly).assertTrue();
    await capture(prefix + '-view-only');
    expect(await (await driver.findComponent(ON.id('session.keyboard'))).isEnabled()).assertFalse();
    await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
    await menuClick("session.more.input");
    expect(await (await driver.findComponent(ON.id('session.inputMode'))).isEnabled()).assertFalse();
    await stackMenuFits(anchor, 'session.action.menu.session.more.input');
    await capture(prefix + '-menu-disabled');
    await menuClick("session.more.viewOnly");
    expect(await (await driver.findComponent(ON.id('session.keyboard'))).isEnabled()).assertTrue();
    await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
    await menuClick("session.more.clipboard");
    await stackMenuFits(anchor, 'session.action.menu.session.more.clipboard');
    await capture(prefix + '-menu-clipboard');
    await menuClick("session.more.clipboard.receive");
    await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
    await menuClick("session.more.remote");
    await stackMenuFits(anchor, 'session.action.menu.session.more.remote');
    await capture(prefix + '-menu-remote');
    await menuClick("session.more.reboot");
    expect((await driver.findComponents(ON.text('确认向远端设备发送此操作？')))?.length ?? 0).assertEqual(1);
    await capture(prefix + '-remote-confirm');
    await (await driver.findComponent(ON.text('取消'))).click(); await settle();
    await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
    await menuClick("session.more.tools");
    await stackMenuFits(anchor, 'session.action.menu.session.more.tools');
    await present('session.more.files'); await capture(prefix + '-toolbar-menu');
    await menuClick("session.more.files");
    await present('files.page');
    const discreteInputs = mock.sentInputs.slice(inputCount).filter((value: string) => {
      return JSON.parse(value).action !== 'mouse_move_absolute';
    });
    expect(discreteInputs.length).assertEqual(0);
  } finally { await mock.disconnect(); await route('devices'); }
}

export default function multiDeviceRegression(): void {
  describe('MultiDeviceRegression', () => {
    beforeAll(async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'com.uu.remote.harmony', moduleName: 'entry', abilityName: 'EntryAbility' });
      await settle();
      let readyContext: common.UIAbilityContext | null = null;
      for (let index = 0; index < 20 && readyContext === null; index++) {
        try {
          const ability = await delegator.getCurrentTopAbility();
          if (ability.context.abilityInfo.name === 'EntryAbility') { readyContext = ability.context; }
        } catch (error) { /* The ability can still be starting on a cold launch. */ }
        if (readyContext === null) { await settle(); }
      }
      if (readyContext === null) { throw new Error('EntryAbility did not become ready'); }
      context = readyContext;
      driver = Driver.create();
      for (let index = 0; index < 20 && !ServiceHub.isReady(); index++) { await settle(); }
      expect(ServiceHub.isReady()).assertTrue();
      mock = new RegressionSessionService();
      await ServiceHub.replaceForTests(mock, context);
      await route('portmap');
      await route('devices');
    });
    afterAll(() => { mock?.dispose(); });
    it('application_icon_uses_the_system_layered_mask', 0, async () => {
      const descriptor = context.resourceManager.getDrawableDescriptorByName('app_layered_icon') as LayeredDrawableDescriptor;
      const icon = hdsDrawable.getHdsLayeredIcon(context.abilityInfo.bundleName, descriptor, 128, true);
      expect(icon !== null).assertTrue();
      if (icon === null) { return; }
      try {
        const info = await icon.getImageInfo();
        const buffer = new ArrayBuffer(icon.getPixelBytesNumber());
        await icon.readPixelsToBuffer(buffer);
        const pixels = new Uint8Array(buffer);
        const width = info.size.width; const height = info.size.height;
        for (const offset of [0, width - 1, width * (height - 1), width * height - 1]) {
          expect(pixels[offset * 4 + 3]).assertEqual(0);
        }
        expect(pixels[(Math.floor(height / 2) * width + Math.floor(width / 2)) * 4 + 3]).assertEqual(255);
        await route('login'); await present('login.appIcon');
        await capture('application-icon-rounded');
      } finally { await icon.release(); await route('devices'); }
    });
    it('session_disconnect_waits_for_cleanup_and_keeps_failure_visible', 0, async () => {
      for (const fails of [false, true]) {
        await mock.listDevices(); await mock.connect('demo-win-01'); mock.emitFirstFrame(); await route('session');
        mock.holdDisconnect(fails);
        try {
          await (await driver.findComponent(ON.id('session.back'))).click(); await settle();
          await (await driver.findComponent(ON.text('结束连接'))).click(); await settle();
          await present('session.page');
          mock.finishDisconnect(); await settle();
          if (fails) { await present('session.page'); } else { await absent('session.page'); }
        } finally { mock.finishDisconnect(); await route('devices'); }
      }
    });
    it('floating_feedback_keeps_click_cancel_disabled_and_geometry_consistent', 0, async () => {
      const ui = (await window.getLastWindow(context)).getUIContext();
      const prompt = ui.getPromptAction();
      const content = new ComponentContent(ui, wrapBuilder(floatingFeedbackSample));
      AppStorage.setOrCreate('feedbackClicks', 0);
      await prompt.openCustomDialog(content, { alignment: DialogAlignment.Center, maskColor: Color.Transparent });
      try {
        await settle();
        const control = await driver.findComponent(ON.id('feedback.control'));
        const bounds = await control.getBounds();
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_FEEDBACK_BOUNDS ' + JSON.stringify({
          density: display.getDefaultDisplaySync().densityPixels,
          rects: UiProbe.measure(ui, ['feedback.sample', 'feedback.control', 'feedback.disabled']) }) + '\n');
        await feedbackFrame('idle');
        const pressing = driver.longClick(Math.round((bounds.left + bounds.right) / 2), Math.round((bounds.top + bounds.bottom) / 2));
        try {
          await new Promise<void>((resolve) => { setTimeout(resolve, 250); });
          await feedbackFrame('pressed');
        } finally { await pressing; }
        await settle(); await feedbackFrame('released');
        const released = await control.getBounds();
        expect(Math.abs(released.left - bounds.left) <= 1 && Math.abs(released.right - bounds.right) <= 1).assertTrue();
        expect(Math.abs(released.top - bounds.top) <= 1 && Math.abs(released.bottom - bounds.bottom) <= 1).assertTrue();
        const clicks = AppStorage.get<number>('feedbackClicks') ?? 0;
        await control.click(); await settle();
        expect(AppStorage.get<number>('feedbackClicks')).assertEqual(clicks + 1);
        const x = Math.round((bounds.left + bounds.right) / 2);
        const y = Math.round((bounds.top + bounds.bottom) / 2);
        await driver.swipe(x, y, x + Math.round((bounds.right - bounds.left) * 1.5), y, 600); await settle();
        expect(AppStorage.get<number>('feedbackClicks')).assertEqual(clicks + 1);
        const disabled = await driver.findComponent(ON.id('feedback.disabled'));
        expect(await disabled.isEnabled()).assertFalse(); await disabled.click(); await settle();
        expect(AppStorage.get<number>('feedbackClicks')).assertEqual(clicks + 1);
        await (await driver.findComponent(ON.id('feedback.menu'))).click(); await settle();
        for (const id of ['feedback.control', 'feedback.disabled', 'feedback.menu']) {
          const attrs = (JSON.parse(getInspectorByKey(id)) as ScrollBarInspector).$attrs;
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_FLOATING_FEEDBACK ' + JSON.stringify({
            id: id, clickEffect: attrs?.['clickEffect'], scale: attrs?.['scale'], material: attrs?.['systemMaterial'] }) + '\n');
        }
        await roundControl('feedback.control'); await roundControl('feedback.disabled');
      } finally { await prompt.closeCustomDialog(content); content.dispose(); AppStorage.delete('feedbackClicks'); }
    });
    it('pip_readonly_blocks_all_input_and_restores_previous_state', 0, async () => {
      await mock.listDevices(); await mock.connect('demo-win-01'); mock.emitFirstFrame();
      try {
        for (const original of [false, true]) {
          await mock.setViewOnly(original);
          const inputs = mock.sentInputs.length;
          const texts = mock.sentTexts.length;
          const releases = mock.releaseCount;
          await mock.setPiPActive(true);
          expect(mock.sessionSnapshot().viewOnly).assertTrue();
          expect(mock.releaseCount > releases).assertTrue();
          await mock.setViewOnly(false);
          expect(mock.sessionSnapshot().viewOnly).assertTrue();
          for (const input of ['mouse_move_relative', 'mouse_press', 'mouse_release', 'mouse_scroll', 'kbd_press', 'kbd_release', 'touch_down']) {
            await mock.sendInput(JSON.stringify({ action: input }));
          }
          await mock.sendText('synthetic');
          expect(mock.sentInputs.length).assertEqual(inputs);
          expect(mock.sentTexts.length).assertEqual(texts);
          await mock.setPiPActive(false);
          expect(mock.sessionSnapshot().viewOnly).assertEqual(original);
        }
        await mock.setViewOnly(false);
        await mock.sendInput(JSON.stringify({ action: 'mouse_move_relative', dx: 1, dy: 1 }));
        expect(mock.sentInputs.length > 0).assertTrue();
      } finally { await mock.setPiPActive(false); await mock.disconnect(); await route('devices'); }
    });
    it('more_menu_hides_toolbar_only_when_overlapping', 0, async () => {
      const win = await window.getLastWindow(context);
      const original = win.getPreferredOrientation();
      const smartReach = mock.settings().smartReachEnabled;
      const originalPosition = mock.settings().controlBarPosition;
      const orientations = deviceInfo.deviceType === '2in1' ? [original] :
        [window.Orientation.USER_ROTATION_PORTRAIT, window.Orientation.USER_ROTATION_LANDSCAPE];
      try {
        await mock.setSmartReachEnabled(false); await mock.setControlBarPosition('right');
        for (const orientation of orientations) {
          if (deviceInfo.deviceType !== '2in1') { await win.setPreferredOrientation(orientation); await settle(); }
          await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
          mock.emitFirstFrame(); await settle();
          const ui = win.getUIContext();
          const toolbarBounds = UiProbe.measure(ui, ['session.toolbar'])[0].bounds;
          const toolbar = (JSON.parse(getInspectorByKey('session.toolbar')) as ScrollBarInspector).$attrs;
          expect(Number(toolbar?.['opacity'] ?? 1)).assertEqual(1);
          await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
          await present('session.action.menu');
          const menu = UiProbe.measure(ui, ['session.action.menu'])[0].bounds;
          const overlapping = menu[0] < toolbarBounds[0] + toolbarBounds[2] && menu[0] + menu[2] > toolbarBounds[0] &&
            menu[1] < toolbarBounds[1] + toolbarBounds[3] && menu[1] + menu[3] > toolbarBounds[1];
          const toolbarOpen = (JSON.parse(getInspectorByKey('session.toolbar')) as ScrollBarInspector).$attrs;
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_TOOLBAR_OVERLAP ' + JSON.stringify({
            orientation: orientation, overlapping: overlapping, toolbar: toolbarBounds, menu: menu }) + '\n');
          expect(Number(toolbarOpen?.['opacity'] ?? 1)).assertEqual(overlapping ? 0 : 1);
          expect(await (await driver.findComponent(ON.id('session.keyboard'))).isEnabled()).assertFalse();
          await capture('session-menu-toolbar-' + orientation);
          await driver.pressBack(); await settle();
          await absent('session.action.menu');
          const restored = (JSON.parse(getInspectorByKey('session.toolbar')) as ScrollBarInspector).$attrs;
          expect(Number(restored?.['opacity'] ?? 1)).assertEqual(1);
          expect(await (await driver.findComponent(ON.id('session.keyboard'))).isEnabled()).assertTrue();
          await mock.disconnect(); await route('devices');
        }
      } finally {
        await mock.setSmartReachEnabled(smartReach); await mock.setControlBarPosition(originalPosition);
        await mock.disconnect(); await route('devices');
        if (deviceInfo.deviceType !== '2in1') { await win.setPreferredOrientation(original); }
      }
    });
    it('more_menu_opens_below_the_top_trigger', 0, async () => {
      const win = await window.getLastWindow(context);
      const original = win.getPreferredOrientation();
      const orientations = deviceInfo.deviceType === '2in1' ? [original] :
        [window.Orientation.USER_ROTATION_PORTRAIT, window.Orientation.USER_ROTATION_LANDSCAPE];
      try {
        for (const orientation of orientations) {
          if (deviceInfo.deviceType !== '2in1') { await win.setPreferredOrientation(orientation); await settle(); }
          await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
          mock.emitFirstFrame(); await settle();
          await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
          const ui = win.getUIContext();
          const rects = UiProbe.measure(ui, ['session.page', 'session.action.menu', 'session.more']);
          const page = rects[0].bounds;
          const menu = rects[1].bounds;
          const more = rects[2].bounds;
          expect(Math.abs(menu[1] - more[1] - more[3] - 16) <= 1).assertTrue();
          expect(Math.abs(menu[0] + menu[2] - more[0] - more[2]) <= 1).assertTrue();
          expect(menu[1] + menu[3] <= page[1] + page[3] - 15).assertTrue();
          await driver.pressBack(); await settle();
          await absent('session.action.menu');
          await mock.disconnect(); await route('devices');
        }
      } finally {
        await mock.disconnect(); await route('devices');
        if (deviceInfo.deviceType !== '2in1') { await win.setPreferredOrientation(original); }
      }
    });
    it('session_header_has_one_material_and_only_arrow_returns', 0, async () => {
      const smartReach = mock.settings().smartReachEnabled;
      await mock.setSmartReachEnabled(false);
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.emitFirstFrame(); await settle();
        await present('session.header.capsule');
        await roundControl('session.more'); await standardIcon('session.more');
        await roundControl('session.pip'); await standardIcon('session.pip');
        await buttonSpacing(['session.rotate', 'session.keyboard', 'session.pip']);
        const ui = (await window.getLastWindow(context)).getUIContext();
        const rects = UiProbe.measure(ui, ['session.header.capsule', 'session.back', 'session.title', 'session.status',
          'session.page', 'session.more']);
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_HEADER_GEOMETRY ' + JSON.stringify(rects) + '\n');
        await capture('session-header-capsule');
        const capsule = rects[0].bounds;
        const back = rects[1].bounds;
        const title = rects[2].bounds;
        const status = rects[3].bounds;
        const page = rects[4].bounds;
        const more = rects[5].bounds;
        expect(Math.abs(page[0] + page[2] - more[0] - more[2] - 16) <= 1).assertTrue();
        expect(more[0] - capsule[0] - capsule[2] >= 7).assertTrue();
        expect(Math.abs(more[1] - capsule[1]) <= 1).assertTrue();
        expect(await (await driver.findComponent(ON.id('session.pip'))).isEnabled()).assertEqual(PiPWindow.isPiPEnabled());
        expect(Math.abs(back[1] + back[3] / 2 - capsule[1] - capsule[3] / 2) < 1).assertTrue();
        expect(Math.abs((title[1] + status[1] + status[3]) / 2 - capsule[1] - capsule[3] / 2) < 1).assertTrue();
        await (await driver.findComponent(ON.id('session.title'))).click(); await settle();
        expect((await driver.findComponents(ON.text('继续连接')))?.length ?? 0).assertEqual(0);
        await present('session.page');
        if (canIUse('SystemCapability.UIDesign.HDSComponent.Core')) {
          const arrow = await (await driver.findComponent(ON.id('session.back'))).getBounds();
          const hold = driver.longClick(Math.round((arrow.left + arrow.right) / 2), Math.round((arrow.top + arrow.bottom) / 2));
          try {
            await new Promise<void>((resolve) => { setTimeout(resolve, 250); });
            const glow = UiProbe.measure(ui, ['session.header.press-glow'])[0];
            expect(glow.matchCount).assertEqual(1);
            expect(Math.abs(glow.bounds[2] - capsule[2]) <= 1 && Math.abs(glow.bounds[3] - capsule[3]) <= 1).assertTrue();
            await feedbackFrame('remote-back-capsule-pressed');
          } finally { await hold; }
          await settle();
          expect(getInspectorByKey('session.header.press-glow')).assertEqual('');
          const confirmation = await driver.findComponents(ON.text('继续连接'));
          if (confirmation?.length > 0) { await confirmation[0].click(); await settle(); }
        }
        await (await driver.findComponent(ON.id('session.back'))).click(); await settle();
        await (await driver.findComponent(ON.text('继续连接'))).click();
      } finally { await mock.setSmartReachEnabled(smartReach); await mock.disconnect(); await route('devices'); }
    });
    it('system_pip_manual_and_auto_preserve_single_surface', 0, async () => {
      if (!PiPWindow.isPiPEnabled()) { throw new Error('System PiP is unavailable on this test device'); }
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const ability = await delegator.getCurrentTopAbility();
      const win = await window.getLastWindow(context);
      const original = mock.settings().autoStartPiP;
      const showMainWindow = async (): Promise<void> => {
        if (deviceInfo.deviceType === '2in1') {
          await delegator.startAbility({ bundleName: 'com.uu.remote.harmony', moduleName: 'entry', abilityName: 'EntryAbility' });
        } else {
          await delegator.doAbilityForeground(ability);
        }
      };
      try {
        for (const auto of [false, true]) {
          await mock.setAutoStartPiP(auto);
          await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
          mock.emitFirstFrame(); await settle(); await settle();
          const attached = mock.attachCount;
          const detached = mock.detachCount;
          const generation = mock.sessionSnapshot().generation;
          if (auto) {
            if (deviceInfo.deviceType === '2in1') { await win.minimize(); }
            else { await delegator.doAbilityBackground(ability); }
          } else {
            await (await driver.findComponent(ON.id('session.pip'))).click();
          }
          for (let i = 0; i < 5 && (win.isWindowShowing() || !mock.sessionSnapshot().viewOnly); i++) { await settle(); }
          expect(win.isWindowShowing()).assertFalse();
          expect(mock.sessionSnapshot().viewOnly).assertTrue();
          expect(mock.attachCount).assertEqual(attached);
          expect(mock.detachCount).assertEqual(detached);
          await delegator.print('UU_PIP_ACTIVE ' + JSON.stringify({ auto: auto, readonly: mock.sessionSnapshot().viewOnly, surfaces: attached }) + '\n');
          await capture(auto ? 'session-pip-auto' : 'session-pip-manual');
          await showMainWindow();
          for (let i = 0; i < 5 && (!win.isWindowShowing() || mock.sessionSnapshot().viewOnly); i++) { await settle(); }
          expect(win.isWindowShowing()).assertTrue();
          await present('session.video');
          expect(mock.sessionSnapshot().viewOnly).assertFalse();
          expect(mock.sessionSnapshot().generation).assertEqual(generation);
          expect(mock.attachCount).assertEqual(attached);
          expect(mock.detachCount).assertEqual(detached);
          await mock.disconnect(); await route('devices');
        }
      } finally {
        if (!win.isWindowShowing()) { await showMainWindow(); }
        await mock.setAutoStartPiP(original); await mock.setPiPActive(false); await mock.disconnect(); await route('devices');
      }
    });
    it('video_viewport_preserves_aspect_ratio_clamps_pan_and_maps_input', 0, () => {
      const fit = VideoViewport.fit(360, 640, 1920, 1080);
      expect(fit[2]).assertEqual(360); expect(fit[3]).assertEqual(202.5);
      expect(VideoViewport.point(fit, 180, 100)).assertEqual(null);
      const offset = VideoViewport.offset(fit, 360, 640, 2, 999, 999);
      expect(offset[0]).assertEqual(180); expect(offset[1]).assertEqual(0);
      const rect = VideoViewport.rect(fit, 2, offset[0], offset[1]);
      const point = VideoViewport.point(rect, 180, 320)!;
      expect(point[0]).assertEqual(0.25); expect(point[1]).assertEqual(0.5);
      const reset = VideoViewport.offset(fit, 360, 640, 1, -999, 999);
      expect(reset[0]).assertEqual(0); expect(reset[1]).assertEqual(0);
      const landscape = VideoViewport.fit(800, 360, 1920, 1080);
      expect(landscape[2]).assertEqual(640); expect(landscape[3]).assertEqual(360);
      expect(VideoViewport.point(landscape, 10, 180)).assertEqual(null);
      for (const size of [[360, 640], [800, 360], [1280, 800], [1920, 1080]]) {
        const frame = VideoViewport.fit(size[0], size[1], 2560, 1440);
        for (const scale of [1, 2, 4]) {
          const viewport = VideoViewport.rect(frame, scale, 0, 0);
          for (const position of [[-100, -100], [size[0] / 2, size[1] / 2], [size[0] + 100, size[1] + 100]]) {
            const mapped = VideoViewport.clampPoint(viewport, size[0], size[1], position[0], position[1])!;
            const x = viewport[0] + mapped[0] * viewport[2];
            const y = viewport[1] + mapped[1] * viewport[3];
            expect(mapped[0] >= 0 && mapped[0] <= 1 && mapped[1] >= 0 && mapped[1] <= 1).assertTrue();
            expect(x >= Math.max(0, viewport[0]) && x <= Math.min(size[0], viewport[0] + viewport[2])).assertTrue();
            expect(y >= Math.max(0, viewport[1]) && y <= Math.min(size[1], viewport[1] + viewport[3])).assertTrue();
          }
        }
      }
      expect(VideoViewport.clampPoint([0, 0, 0, 100], 360, 640, 10, 10)).assertEqual(null);
    });
    it('assistance_connection_uses_native_enabled_and_disabled_states', 0, async () => {
      await route('assist');
      expect(await (await driver.findComponent(ON.id('assist.connect'))).isEnabled()).assertFalse();
      await capture('assistance-disabled');
      await (await driver.findComponent(ON.id('assist.connectId'))).inputText('123456789');
      expect(await (await driver.findComponent(ON.id('assist.connect'))).isEnabled()).assertFalse();
      await (await driver.findComponent(ON.id('assist.verifyCode'))).inputText('123456');
      if (deviceInfo.deviceType !== '2in1') { await driver.pressBack(); }
      await settle();
      expect(await (await driver.findComponent(ON.id('assist.connect'))).isEnabled()).assertTrue();
      await capture('assistance-enabled');
      await route('devices');
    });
    it('remote_surface_touch_and_mouse_deliver_complete_input_sequences', 0, async () => {
      const mode = mock.settings().touchMode;
      await mock.setTouchMode('direct');
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.emitFirstFrame(); await settle();
        const video = await (await driver.findComponent(ON.id('session.video'))).getBounds();
        const x = Math.round((video.left + video.right) / 2);
        const y = Math.round((video.top + video.bottom) / 2);
        let count = mock.sentInputs.length;
        await driver.click(x, y); await settle();
        let inputs = mock.sentInputs.slice(count).map((value: string): Record<string, string | number> => JSON.parse(value));
        const touches = inputs.filter((value: Record<string, string | number>) => `${value['action']}`.startsWith('touch_'));
        expect(touches.length).assertEqual(2);
        expect(touches[0]['action']).assertEqual('touch_down');
        expect(touches[1]['action']).assertEqual('touch_up');
        expect(Math.abs(Number(touches[0]['abs_x']) - 0.5) < 0.03).assertTrue();
        expect(Math.abs(Number(touches[0]['abs_y']) - 0.5) < 0.03).assertTrue();
        count = mock.sentInputs.length;
        const distance = Math.round((video.right - video.left) * 0.15);
        await driver.swipe(x - distance, y, x + distance, y, 600); await settle();
        inputs = mock.sentInputs.slice(count).map((value: string): Record<string, string | number> => JSON.parse(value));
        expect(inputs[0]['action']).assertEqual('touch_down');
        expect(inputs.some((value: Record<string, string | number>) => value['action'] === 'touch_move')).assertTrue();
        expect(inputs[inputs.length - 1]['action']).assertEqual('touch_up');
        for (const button of [TestMouseButton.MOUSE_BUTTON_LEFT, TestMouseButton.MOUSE_BUTTON_RIGHT]) {
          count = mock.sentInputs.length;
          await driver.mouseMoveTo({ x: x, y: y });
          await driver.mouseClick({ x: x, y: y }, button); await settle();
          inputs = mock.sentInputs.slice(count).map((value: string): Record<string, string | number> => JSON.parse(value));
          const buttons = inputs.filter((value: Record<string, string | number>) => value['action'] === 'mouse_press' || value['action'] === 'mouse_release');
          expect(buttons.length).assertEqual(2);
          expect(buttons[0]['action']).assertEqual('mouse_press');
          expect(buttons[1]['action']).assertEqual('mouse_release');
          expect(buttons[0]['button']).assertEqual(button === TestMouseButton.MOUSE_BUTTON_LEFT ? 1 : 2);
          expect(buttons[1]['button']).assertEqual(buttons[0]['button']);
        }
        count = mock.sentInputs.length;
        await driver.triggerKey(KeyCode.KEYCODE_A); await settle();
        const keys = mock.sentInputs.slice(count).map((value: string): Record<string, string | number | boolean> => JSON.parse(value))
          .filter((value: Record<string, string | number | boolean>) => value['action'] === 'key');
        expect(keys.length).assertEqual(2);
        expect(keys[0]['scan']).assertEqual(4); expect(keys[1]['scan']).assertEqual(4);
        expect(keys[0]['down']).assertEqual(true); expect(keys[1]['down']).assertEqual(false);
        await mock.setViewOnly(true); await settle(); count = mock.sentInputs.length;
        await driver.click(x, y);
        await driver.mouseClick({ x: x, y: y }, TestMouseButton.MOUSE_BUTTON_LEFT);
        await driver.triggerKey(KeyCode.KEYCODE_A); await settle();
        expect(mock.sentInputs.length).assertEqual(count);
      } finally {
        await mock.disconnect(); await mock.setTouchMode(mode); await route('devices');
      }
    });
    it('remote_cursor_is_visible_and_tracks_direct_and_trackpad_touch', 0, async () => {
      const original = mock.settings().touchMode;
      try {
        for (const mode of ['direct', 'trackpad']) {
          await mock.setTouchMode(mode === 'direct' ? 'direct' : 'trackpad');
          await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
          mock.emitFirstFrame(); await settle(); await present('session.cursor');
          const surface = await (await driver.findComponent(ON.id('session.surface'))).getBounds();
          const video = await (await driver.findComponent(ON.id('session.video'))).getBounds();
          const x = Math.round(video.left + (video.right - video.left) * 0.35);
          const y = Math.round(video.top + (video.bottom - video.top) * 0.45);
          const count = mock.sentInputs.length;
          await driver.swipe(x, y, x + 30, y + 24, 600); await settle();
          const events = mock.sentInputs.slice(count).map((value: string): Record<string, string | number> => JSON.parse(value));
          const inputs = events.filter((value: Record<string, string | number>) => value['action'] === 'touch_move');
          expect(inputs.length > 0).assertTrue();
          const last = inputs[inputs.length - 1];
          const alignment = await cursorAlignment(Number(last['cursor_x']), Number(last['cursor_y']));
          const targetX = alignment[0]; const targetY = alignment[1];
          const tipX = alignment[2]; const tipY = alignment[3];
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_CURSOR_TOUCH ' + JSON.stringify({ mode: mode,
            target: [targetX, targetY], tip: [tipX, tipY], error: [Math.abs(targetX - tipX), Math.abs(targetY - tipY)],
            surface: surface, video: video, sync: mock.videoSync(), layout: UiProbe.measure((await window.getLastWindow(context)).getUIContext(),
              ['session.page', 'session.surface', 'session.video', 'session.mouse.pointer']) }) + '\n');
          expect(Math.abs(targetX - tipX) <= 2 && Math.abs(targetY - tipY) <= 2).assertTrue();
          if (mode === 'direct') {
            expect(last['cursor_x']).assertEqual(last['abs_x']);
            expect(last['cursor_y']).assertEqual(last['abs_y']);
          } else {
            const down = events.find((value: Record<string, string | number>) => value['action'] === 'touch_down');
            expect(down?.['cursor_x']).assertEqual(0.5);
            expect(down?.['cursor_y']).assertEqual(0.5);
            expect(Math.abs(Number(last['cursor_x']) - (0.5 + Number(last['abs_x']) - Number(down?.['abs_x']))) < 0.000001).assertTrue();
            expect(Math.abs(Number(last['cursor_y']) - (0.5 + Number(last['abs_y']) - Number(down?.['abs_y']))) < 0.000001).assertTrue();
            mock.setRemoteCursorInVideo(true); await settle();
            const realCursorStart = mock.sentInputs.length;
            await driver.click(x, y); await settle();
            const realCursorTap = mock.sentInputs.slice(realCursorStart)
              .map((value: string): Record<string, string | number> => JSON.parse(value))
              .find((value: Record<string, string | number>) => value['action'] === 'touch_down');
            expect(realCursorTap !== undefined && realCursorTap['cursor_x'] === undefined && realCursorTap['cursor_y'] === undefined)
              .assertTrue();
            mock.setRemoteCursorInVideo(false); await settle();
          }
          await capture('cursor-' + mode);
          await mock.setViewOnly(true); await settle();
          const readonlyCount = mock.sentInputs.length;
          await driver.swipe(x, y, x + 30, y + 24, 600); await settle();
          expect(mock.sentInputs.length).assertEqual(readonlyCount);
          await mock.disconnect(); await route('devices');
        }
      } finally { await mock.setTouchMode(original); await mock.disconnect(); await route('devices'); }
    });
    it('touch_taps_use_finger_in_direct_mode_and_existing_cursor_in_trackpad_mode', 0, async () => {
      const original = mock.settings().touchMode;
      try {
        for (const mode of ['direct', 'trackpad']) {
          await mock.setTouchMode(mode === 'direct' ? 'direct' : 'trackpad');
          await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
          mock.emitFirstFrame(); await settle();
          for (const zoomed of [false, true]) {
            if (zoomed) {
              await (await driver.findComponent(ON.id('session.gestures'))).pinchOut(2); await settle();
              const surface = await (await driver.findComponent(ON.id('session.gestures'))).getBounds();
              const x = Math.round((surface.left + surface.right) / 2);
              const y = Math.round((surface.top + surface.bottom) / 2);
              const start = mock.sentInputs.length;
              await driver.swipe(x, y, x + 40, y, 600); await settle();
              if (mode === 'trackpad') {
                expect(mock.sentInputs.slice(start).some((input: string) =>
                  (JSON.parse(input) as Record<string, string | number>)['action'] === 'touch_move')).assertTrue();
              }
            }
            const video = await (await driver.findComponent(ON.id('session.video'))).getBounds();
            const surface = await (await driver.findComponent(ON.id('session.surface'))).getBounds();
            const left = Math.max(video.left, surface.left); const right = Math.min(video.right, surface.right);
            const top = Math.max(video.top, surface.top); const bottom = Math.min(video.bottom, surface.bottom);
            for (const point of [[0.28, 0.4], [0.64, 0.58]]) {
              const x = Math.round(left + (right - left) * point[0]);
              const y = Math.round(top + (bottom - top) * point[1]);
              const count = mock.sentInputs.length;
              const before = mode === 'trackpad' ? await (await driver.findComponent(ON.id('session.mouse.pointer'))).getBounds() : null;
              await driver.click(x, y); await settle();
              const touches = mock.sentInputs.slice(count).map((value: string): Record<string, string | number> => JSON.parse(value))
                .filter((value: Record<string, string | number>) => `${value['action']}`.startsWith('touch_'));
              expect(touches.length).assertEqual(2);
              expect(touches[0]['action']).assertEqual('touch_down'); expect(touches[1]['action']).assertEqual('touch_up');
              const pointer = await (await driver.findComponent(ON.id('session.mouse.pointer'))).getBounds();
              const density = display.getDefaultDisplaySync().densityPixels;
              const tipX = pointer.left + 4.56 * density; const tipY = pointer.top + 4.58 * density;
              await abilityDelegatorRegistry.getAbilityDelegator().print('UU_TOUCH_TAP ' + JSON.stringify({
                mode: mode, zoomed: zoomed, finger: [x, y], tip: [tipX, tipY],
                input: [touches[0]['abs_x'], touches[0]['abs_y']],
                cursor: [touches[0]['cursor_x'], touches[0]['cursor_y']] }) + '\n');
              if (mode === 'direct') {
                expect(Math.abs(tipX - x) <= 2 && Math.abs(tipY - y) <= 2).assertTrue();
                expect(touches[0]['cursor_x']).assertEqual(touches[0]['abs_x']);
                expect(touches[0]['cursor_y']).assertEqual(touches[0]['abs_y']);
              } else {
                expect(before !== null && Math.abs(pointer.left - before.left) <= 2 && Math.abs(pointer.top - before.top) <= 2).assertTrue();
                expect(touches[0]['cursor_x']).assertEqual(touches[1]['cursor_x']);
                expect(touches[0]['cursor_y']).assertEqual(touches[1]['cursor_y']);
                if (!zoomed) {
                  expect(touches[0]['cursor_x']).assertEqual(0.5);
                  expect(touches[0]['cursor_y']).assertEqual(0.5);
                }
              }
            }
            await capture('touch-tap-' + mode + (zoomed ? '-zoom' : '-fit'));
          }
          await mock.disconnect(); await route('devices');
        }
      } finally { await mock.setTouchMode(original); await mock.disconnect(); await route('devices'); }
    });
    it('remote_lock_offers_fingerprint_and_waits_for_a_tap', 0, async () => {
      mock.fingerprintSupported = true;
      mock.fingerprintSaved = true;
      const start = mock.fingerprintPrompts;
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.setRemoteLock(true, false); await settle();
        await absent('session.unlock.fingerprint');
        mock.setRemoteLock(true, true); await settle();
        await present('session.unlock.fingerprint');
        await absent('session.unlock.setup');
        expect(mock.fingerprintPrompts).assertEqual(start);
        await feedbackFrame('fingerprint-unlock-button');
        await (await driver.findComponent(ON.id('session.unlock.fingerprint'))).click(); await settle();
        expect(mock.fingerprintPrompts).assertEqual(start + 1);
        await absent('session.unlock.fingerprint');
        await mock.setViewOnly(true);
        mock.setRemoteLock(true, true); await settle();
        await absent('session.unlock.fingerprint');
        mock.fingerprintSaved = false;
        await mock.setViewOnly(false);
        mock.setRemoteLock(true, true); await settle();
        await (await driver.findComponent(ON.id('session.unlock.fingerprint'))).click(); await settle();
        await present('session.unlock.password');
        expect(mock.fingerprintPrompts).assertEqual(start + 1);
        await (await driver.findComponent(ON.id('session.unlock.cancel'))).click(); await settle();
        await absent('session.unlock.setup');
      } finally {
        mock.fingerprintSupported = false;
        mock.setRemoteLock(false, false);
        await mock.setViewOnly(false); await mock.disconnect(); await route('devices');
      }
    });
    it('remote_cursor_uses_received_image_hotspot_and_falls_back_without_blocking_touch', 0, async () => {
      const original = mock.settings().touchMode;
      await mock.setTouchMode('direct');
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.emitFirstFrame(); await settle();
        mock.setRemoteCursor({ generation: mock.sessionSnapshot().generation, width: 32, height: 16, hotX: 6, hotY: 4,
          png: 'iVBORw0KGgoAAAANSUhEUgAAACAAAAAQCAYAAAB3AH1ZAAAAIElEQVR4nGP4P8CAYdQBow4YdcCoA0YdMOqAUQcMtAMAqf/4ahypi/sAAAAASUVORK5CYII=' });
        await settle();
        const video = await (await driver.findComponent(ON.id('session.video'))).getBounds();
        const x = Math.round((video.left + video.right) / 2);
        const y = Math.round((video.top + video.bottom) / 2);
        const density = display.getDefaultDisplaySync().densityPixels;
        await driver.click(x, y); await settle();
        let pointer = await (await driver.findComponent(ON.id('session.mouse.pointer'))).getBounds();
        expect(Math.abs(pointer.right - pointer.left - 32 * density) <= 2).assertTrue();
        expect(Math.abs(pointer.bottom - pointer.top - 16 * density) <= 2).assertTrue();
        expect(Math.abs(pointer.left + 6 * density - x) <= 2 && Math.abs(pointer.top + 4 * density - y) <= 2).assertTrue();
        await capture('cursor-remote-image');
        const count = mock.sentInputs.length;
        await driver.swipe(x, y, x + 30, y + 24, 600); await settle();
        expect(mock.sentInputs.slice(count).some((input: string) =>
          (JSON.parse(input) as Record<string, string | number>)['action'] === 'touch_move')).assertTrue();
        await driver.mouseMoveTo({ x: x, y: y }); await settle(); await absent('session.cursor');
        await driver.click(x, y); await settle(); await present('session.cursor');
        mock.setRemoteCursorInVideo(true); await settle(); await absent('session.cursor');
        const capturedInput = mock.sentInputs.length;
        await driver.click(x, y); await settle(); await absent('session.cursor');
        expect(mock.sentInputs.length).assertLarger(capturedInput);
        mock.setRemoteCursorInVideo(false); await settle(); await present('session.cursor');
        mock.setRemoteCursor({ generation: mock.sessionSnapshot().generation, width: 32, height: 16, hotX: 6, hotY: 4, png: 'invalid' });
        await settle();
        pointer = await (await driver.findComponent(ON.id('session.mouse.pointer'))).getBounds();
        expect(Math.abs(pointer.right - pointer.left - 24 * density) <= 2).assertTrue();
        expect(Math.abs(pointer.left + 4.56 * density - x) <= 2 && Math.abs(pointer.top + 4.58 * density - y) <= 2).assertTrue();
        await capture('cursor-image-fallback');
      } finally { mock.setRemoteCursor(null); await mock.setTouchMode(original); await mock.disconnect(); await route('devices'); }
    });
    it('virtual_mouse_starts_bottom_right_above_controls_and_keeps_dragged_position', 0, async () => {
      const original = mock.settings();
      const smartReach = original.smartReachEnabled;
      const position = original.controlBarPosition;
      const density = display.getDefaultDisplaySync().densityPixels;
      try {
        await mock.setSmartReachEnabled(false);
        for (const controlPosition of ['left', 'center', 'right'] as ControlBarPosition[]) {
          await route('devices'); await mock.listDevices(); await mock.setControlBarPosition(controlPosition);
          await mock.connect('demo-win-01'); await route('session'); mock.emitFirstFrame(); await settle();
          const ui = (await window.getLastWindow(context)).getUIContext();
          const rects = UiProbe.measure(ui, ['session.surface', 'session.mouse.collapsed', 'session.toolbar']);
          const surface = rects[0].bounds;
          const mouse = rects[1].bounds;
          const toolbar = rects[2].bounds;
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MOUSE_INITIAL ' + JSON.stringify({
            position: controlPosition, surface: surface, mouse: mouse, toolbar: toolbar
          }) + '\n');
          expect(Math.abs(surface[0] + surface[2] - mouse[0] - mouse[2] - 16) <= 1).assertTrue();
          expect(Math.abs(toolbar[1] - mouse[1] - mouse[3] - 8) <= 1).assertTrue();
          expect(mouse[0] >= surface[0] && mouse[0] + mouse[2] <= surface[0] + surface[2] &&
            mouse[1] >= surface[1] && mouse[1] + mouse[3] <= surface[1] + surface[3]).assertTrue();
          const target = await (await driver.findComponent(ON.id('session.mouse.collapsed'))).getBounds();
          const x = Math.round((target.left + target.right) / 2);
          const y = Math.round((target.top + target.bottom) / 2);
          const count = mock.sentInputs.length;
          await driver.swipe(x, y, Math.round(x - 40 * density), Math.round(y - 24 * density), 600); await settle();
          const moved = UiProbe.measure(ui, ['session.mouse.collapsed'])[0].bounds;
          expect(moved[0] < mouse[0] - 24).assertTrue();
          expect(mock.sentInputs.length).assertEqual(count);
          await capture('virtual-mouse-bottom-right-' + controlPosition);
          await mock.disconnect(); await route('devices');
        }
      } finally {
        await mock.disconnect(); await route('devices');
        await mock.setSmartReachEnabled(smartReach); await mock.setControlBarPosition(position);
      }
    });
    it('virtual_mouse_buttons_hold_until_release_without_dragging_the_icon', 0, async () => {
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.emitFirstFrame(); await settle();
        await (await driver.findComponent(ON.id('session.mouse.collapsed'))).click(); await settle();
        await present('session.mouse.expanded');
        const ui = (await window.getLastWindow(context)).getUIContext();
        const parts = UiProbe.measure(ui, ['session.mouse.expanded', 'session.mouse.wheel']);
        expect(Math.abs(parts[0].bounds[2] - 112) <= 1 && Math.abs(parts[0].bounds[3] - 144) <= 1).assertTrue();
        expect(Math.abs(parts[1].bounds[2] - 22) <= 1 && Math.abs(parts[1].bounds[3] - 44) <= 1).assertTrue();
        await capture('session-virtual-mouse-wheel');
        for (const button of [1, 2]) {
          const target = await (await driver.findComponent(ON.id('session.mouse.button.' + button))).getBounds();
          const x = Math.round((target.left + target.right) / 2);
          const y = Math.round((target.top + target.bottom) / 2);
          const count = mock.sentInputs.length;
          const buttonActions = (): string => mock.sentInputs.slice(count)
            .map((value: string): Record<string, string | number | boolean> => JSON.parse(value))
            .filter((event: Record<string, string | number | boolean>) => event['button'] === button)
            .map((event: Record<string, string | number | boolean>) => String(event['action'])).join(',');
          const hold = driver.longClick(x, y);
          try {
            await new Promise<void>((resolve) => { setTimeout(resolve, 600); });
            expect(buttonActions()).assertEqual('mouse_press');
          } finally { await hold; }
          await settle();
          expect(buttonActions()).assertEqual('mouse_press,mouse_release');
          const beforeDrag = mock.sentInputs.length;
          await driver.drag(x, y, x + 6, y + 4, 200); await settle();
          expect(mock.sentInputs.slice(beforeDrag)
            .map((value: string): Record<string, string | number | boolean> => JSON.parse(value))
            .filter((event: Record<string, string | number | boolean>) => event['button'] === button)
            .map((event: Record<string, string | number | boolean>) => String(event['action'])).join(','))
            .assertEqual('mouse_press,mouse_release');
        }
        if (canIUse('SystemCapability.UIDesign.HDSComponent.Core')) {
          const collapse = await (await driver.findComponent(ON.id('session.mouse.collapse'))).getBounds();
          const press = driver.longClick(Math.round((collapse.left + collapse.right) / 2),
            Math.round((collapse.top + collapse.bottom) / 2));
          try {
            await new Promise<void>((resolve) => { setTimeout(resolve, 240); });
            const glow = UiProbe.measure(ui, ['session.mouse.expanded.press-glow'])[0].bounds;
            expect(Math.abs(glow[2] - 112) <= 1 && Math.abs(glow[3] - 144) <= 1).assertTrue();
          } finally { await press; }
          await settle();
          expect(getInspectorByKey('session.mouse.expanded.press-glow')).assertEqual('');
        }
      } finally { await mock.disconnect(); await route('devices'); }
    });
    it('virtual_mouse_wheel_expands_on_hold_and_scrolls_in_finger_direction', 0, async () => {
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.emitFirstFrame(); await settle();
        await (await driver.findComponent(ON.id('session.mouse.collapsed'))).click(); await settle();
        const ui = (await window.getLastWindow(context)).getUIContext();
        const initial = UiProbe.measure(ui, ['session.mouse.wheel', 'session.mouse.expanded']);
        expect(Math.abs(initial[0].bounds[2] - 22) <= 1 && Math.abs(initial[0].bounds[3] - 52) <= 1).assertTrue();
        expect(Math.abs(initial[0].bounds[0] - initial[1].bounds[0] - 45) <= 1 &&
          Math.abs(initial[0].bounds[1] - initial[1].bounds[1] - 42) <= 1).assertTrue();
        await feedbackFrame('virtual-wheel-compact');
        for (const direction of [-1, 1]) {
          const wheel = await (await driver.findComponent(ON.id('session.mouse.wheel'))).getBounds();
          const x = Math.round((wheel.left + wheel.right) / 2);
          const y = Math.round((wheel.top + wheel.bottom) / 2);
          const count = mock.sentInputs.length;
          const drag = driver.drag(x, y, x, y + direction * Math.round(ui.vp2px(48)), 200);
          try {
            await new Promise<void>((resolve) => { setTimeout(resolve, 700); });
            const sizes = UiProbe.measure(ui, ['session.mouse.wheel.expanded', 'session.mouse.expanded']);
            expect(Math.abs(sizes[0].bounds[2] - 36) <= 1 && Math.abs(sizes[0].bounds[3] - 60) <= 1).assertTrue();
            expect(Math.abs(sizes[1].bounds[2] - 112) <= 1 && Math.abs(sizes[1].bounds[3] - 144) <= 1).assertTrue();
            if (direction < 0) { await feedbackFrame('virtual-wheel-expanded'); }
          } finally { await drag; }
          await settle();
          await present('session.mouse.wheel');
          const events = mock.sentInputs.slice(count).map((input: string): Record<string, string | number> => JSON.parse(input));
          const ticks = events.filter((event: Record<string, string | number>) => event['action'] === 'mouse_scroll');
          expect(ticks.length).assertLarger(1);
          expect(ticks.every((event: Record<string, string | number>) => Number(event['delta_y']) * direction < 0)).assertTrue();
          expect(events.some((event: Record<string, string | number>) => event['button'] === 4)).assertFalse();
          const after = mock.sentInputs.length;
          await new Promise<void>((resolve) => { setTimeout(resolve, 250); });
          expect(mock.sentInputs.length).assertEqual(after);
        }
      } finally { await mock.disconnect(); await route('devices'); }
    });
    it('virtual_mouse_tip_matches_absolute_remote_position', 0, async () => {
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.emitFirstFrame(); await settle();
        await present('session.mouse.collapsed');
        await (await driver.findComponent(ON.id('session.mouse.collapsed'))).click(); await settle();
        const ui = (await window.getLastWindow(context)).getUIContext();
        const body = ui.getComponentUtils().getRectangleById('session.mouse.expanded');
        const pointer = ui.getComponentUtils().getRectangleById('session.mouse.pointer');
        expect(Math.abs(pointer.windowOffset.x + ui.vp2px(4.56) - body.windowOffset.x + ui.vp2px(12)) <= 2).assertTrue();
        expect(Math.abs(pointer.windowOffset.y + ui.vp2px(4.58) - body.windowOffset.y + ui.vp2px(12)) <= 2).assertTrue();
        const page = await (await driver.findComponent(ON.id('session.page'))).getBounds();
        for (const movement of [[24, -20], [-40, 24], [180, -180], [-240, 240]]) {
          const handle = await (await driver.findComponent(ON.id('session.mouse.drag'))).getBounds();
          const x = Math.round((handle.left + handle.right) / 2);
          const y = Math.round((handle.top + handle.bottom) / 2);
          const count = mock.sentInputs.length;
          await driver.swipe(x, y, Math.max(page.left + 2, Math.min(page.right - 2, x + movement[0])),
            Math.max(page.top + 2, Math.min(page.bottom - 2, y + movement[1])), 600); await settle();
          const inputs = mock.sentInputs.slice(count).map((value: string): Record<string, string | number> => JSON.parse(value));
          expect(inputs.length > 0).assertTrue();
          expect(inputs.every((value: Record<string, string | number>) => value['action'] === 'mouse_move_absolute')).assertTrue();
          const last = inputs[inputs.length - 1];
          const alignment = await cursorAlignment(Number(last['abs_x']), Number(last['abs_y']));
          const actualX = alignment[0]; const actualY = alignment[1];
          const tipX = alignment[2]; const tipY = alignment[3];
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MOUSE_ALIGNMENT ' + JSON.stringify({
            target: [actualX, actualY], tip: [tipX, tipY], error: [Math.abs(actualX - tipX), Math.abs(actualY - tipY)],
            layout: UiProbe.measure((await window.getLastWindow(context)).getUIContext(),
              ['session.page', 'session.surface', 'session.video', 'session.mouse.pointer']) }) + '\n');
          expect(Math.abs(actualX - tipX) <= 2 && Math.abs(actualY - tipY) <= 2).assertTrue();
          if ((await driver.findComponents(ON.id('session.mouse.expanded'))).length > 0) {
            const movedBody = ui.getComponentUtils().getRectangleById('session.mouse.expanded');
            expect(Math.abs(tipX - movedBody.windowOffset.x + ui.vp2px(12)) <= 2).assertTrue();
            expect(Math.abs(tipY - movedBody.windowOffset.y + ui.vp2px(12)) <= 2).assertTrue();
          }
        }
        await capture('virtual-mouse-alignment');
      } finally { await mock.disconnect(); await route('devices'); }
    });
    it('virtual_mouse_moves_remote_pointer_buttons_wheel_and_blocks_readonly_input', 0, async () => {
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.emitFirstFrame(); await settle();
        await roundControl('session.mouse.collapsed');
        await standardIcon('session.mouse.collapsed');
        const mouseIcon = (JSON.parse(getInspectorByKey('session.mouse.icon')) as ScrollBarInspector).$attrs;
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MOUSE_ICON ' + JSON.stringify({
          source: mouseIcon?.['src'], color: mouseIcon?.['fillColor'] }) + '\n');
        expect(String(mouseIcon?.['src'])).assertEqual('resource:///' + iconResource('mouse', true, false).id + '.svg');
        await capture('virtual-mouse-collapsed');
        let bounds = await (await driver.findComponent(ON.id('session.mouse.collapsed'))).getBounds();
        let x = Math.round((bounds.left + bounds.right) / 2);
        let y = Math.round((bounds.top + bounds.bottom) / 2);
        let count = mock.sentInputs.length;
        await driver.swipe(x, y, x - 24, y - 24, 600); await settle();
        expect(mock.sentInputs.length).assertEqual(count);
        await (await driver.findComponent(ON.id('session.mouse.collapsed'))).click(); await settle();
        await capture('virtual-mouse-after-expand');
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MOUSE_EXPAND ' + JSON.stringify(UiProbe.measure(
          (await window.getLastWindow(context)).getUIContext(), ['session.mouse', 'session.mouse.collapsed', 'session.mouse.expanded'])) + '\n');
        await present('session.mouse.expanded');
        const page = await (await driver.findComponent(ON.id('session.page'))).getBounds();
        bounds = await (await driver.findComponent(ON.id('session.mouse.expanded'))).getBounds();
        const density = display.getDefaultDisplaySync().densityPixels;
        expect(Math.abs((bounds.right - bounds.left) / density - 112) <= 1).assertTrue();
        expect(Math.abs((bounds.bottom - bounds.top) / density - 144) <= 1).assertTrue();
        expect(bounds.left >= page.left && bounds.right <= page.right && bounds.top >= page.top && bounds.bottom <= page.bottom).assertTrue();
        await capture('virtual-mouse-expanded');
        for (const button of [1, 2, 4]) {
          const id = button === 4 ? 'session.mouse.wheel' : 'session.mouse.button.' + button;
          const key = await driver.findComponent(ON.id(id));
          if (button !== 4) {
            const keyBounds = await key.getBounds();
            const icons = await driver.findComponents(ON.type('Image').within(ON.id(id)));
            expect(icons?.length ?? 0).assertEqual(1);
            const iconBounds = await icons![0].getBounds();
            expect(Math.abs(iconBounds.left + iconBounds.right - keyBounds.left - keyBounds.right) <= 2).assertTrue();
            expect(Math.abs(iconBounds.top + iconBounds.bottom - keyBounds.top - keyBounds.bottom) <= 2).assertTrue();
          }
          count = mock.sentInputs.length;
          await key.click();
          await settle();
          const inputs = mock.sentInputs.slice(count).map((value: string): Record<string, string | number> => JSON.parse(value));
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MOUSE_TAP ' + JSON.stringify({
            button: button, actions: inputs.map((event: Record<string, string | number>) => event['action']) }) + '\n');
          expect(inputs.length).assertEqual(2);
          expect(inputs[0]['action']).assertEqual('mouse_press'); expect(inputs[0]['button']).assertEqual(button);
          expect(inputs[1]['action']).assertEqual('mouse_release'); expect(inputs[1]['button']).assertEqual(button);
        }
        const leftButton = await (await driver.findComponent(ON.id('session.mouse.button.1'))).getBounds();
        count = mock.sentInputs.length;
        await driver.doubleClick(Math.round((leftButton.left + leftButton.right) / 2),
          Math.round((leftButton.top + leftButton.bottom) / 2));
        await settle();
        const doubleClick = mock.sentInputs.slice(count).map((value: string): Record<string, string | number> => JSON.parse(value));
        const actions = ['mouse_press', 'mouse_release', 'mouse_press', 'mouse_release'];
        expect(doubleClick.length).assertEqual(actions.length);
        for (let i = 0; i < actions.length; i++) {
          expect(doubleClick[i]['action']).assertEqual(actions[i]);
          expect(doubleClick[i]['button']).assertEqual(1);
        }
        await present('session.mouse.expanded');
        let drag = await (await driver.findComponent(ON.id('session.mouse.drag'))).getBounds();
        x = Math.round((drag.left + drag.right) / 2); y = Math.round((drag.top + drag.bottom) / 2);
        count = mock.sentInputs.length;
        await driver.swipe(x, y, x + 32, y - 24, 600); await settle();
        let inputs = mock.sentInputs.slice(count).map((value: string): Record<string, string | number> => JSON.parse(value));
        expect(inputs.length > 0).assertTrue();
        expect(inputs.every((value: Record<string, string | number>) => value['action'] === 'mouse_move_absolute')).assertTrue();
        expect(inputs.every((value: Record<string, string | number>) => Number(value['abs_x']) >= 0 && Number(value['abs_x']) <= 1 &&
          Number(value['abs_y']) >= 0 && Number(value['abs_y']) <= 1)).assertTrue();
        drag = await (await driver.findComponent(ON.id('session.mouse.drag'))).getBounds();
        expect(drag.left > x - (drag.right - drag.left) / 2).assertTrue();
        const wheel = await (await driver.findComponent(ON.id('session.mouse.wheel'))).getBounds();
        x = Math.round((wheel.left + wheel.right) / 2);
        count = mock.sentInputs.length;
        await driver.swipe(x, Math.round(wheel.top + 8), x, Math.round(wheel.bottom - 8), 600); await settle();
        inputs = mock.sentInputs.slice(count).map((value: string): Record<string, string | number> => JSON.parse(value));
        expect(inputs.some((value: Record<string, string | number>) => value['action'] === 'mouse_scroll' && Number(value['delta_y']) < 0)).assertTrue();
        expect(inputs.every((value: Record<string, string | number>) => value['action'] === 'mouse_scroll')).assertTrue();
        count = mock.sentInputs.length;
        const dragKey = await driver.findComponent(ON.id('session.mouse.dragLock'));
        await dragKey.click(); await settle(); expect(await dragKey.isSelected()).assertTrue();
        inputs = mock.sentInputs.slice(count).map((value: string): Record<string, string | number> => JSON.parse(value));
        expect(inputs.length).assertEqual(1); expect(inputs[0]['action']).assertEqual('mouse_press'); expect(inputs[0]['button']).assertEqual(1);
        await capture('virtual-mouse-drag-active');
        drag = await (await driver.findComponent(ON.id('session.mouse.drag'))).getBounds();
        x = Math.round((drag.left + drag.right) / 2); y = Math.round((drag.top + drag.bottom) / 2);
        count = mock.sentInputs.length;
        await driver.swipe(x, y, x - 24, y - 24, 600); await settle();
        inputs = mock.sentInputs.slice(count).map((value: string): Record<string, string | number> => JSON.parse(value));
        expect(inputs.length > 0 && inputs.every((value: Record<string, string | number>) => value['action'] === 'mouse_move_absolute')).assertTrue();
        count = mock.sentInputs.length;
        await (await driver.findComponent(ON.id('session.mouse.dragLock'))).click(); await settle();
        inputs = mock.sentInputs.slice(count).map((value: string): Record<string, string | number> => JSON.parse(value));
        expect(inputs.length).assertEqual(1); expect(inputs[0]['action']).assertEqual('mouse_release'); expect(inputs[0]['button']).assertEqual(1);
        await (await driver.findComponent(ON.id('session.mouse.dragLock'))).click(); await settle();
        const releases = mock.releaseCount;
        await (await driver.findComponent(ON.id('session.mouse.collapse'))).click(); await settle();
        expect(mock.releaseCount > releases).assertTrue();
        await (await driver.findComponent(ON.id('session.mouse.collapsed'))).click(); await settle();
        expect(await (await driver.findComponent(ON.id('session.mouse.dragLock'))).isSelected()).assertFalse();
        await (await driver.findComponent(ON.id('session.mouse.dragLock'))).click(); await settle();
        const readonlyReleases = mock.releaseCount;
        await mock.setViewOnly(true); await settle(); count = mock.sentInputs.length;
        expect(mock.releaseCount > readonlyReleases).assertTrue();
        expect(await (await driver.findComponent(ON.id('session.mouse.dragLock'))).isSelected()).assertFalse();
        for (const id of ['session.mouse.button.1', 'session.mouse.button.2', 'session.mouse.wheel']) {
          const key = await driver.findComponent(ON.id(id)); expect(await key.isEnabled()).assertFalse(); await key.click();
        }
        expect(mock.sentInputs.length).assertEqual(count);
        await (await driver.findComponent(ON.id('session.mouse.collapse'))).click(); await settle();
        await roundControl('session.mouse.collapsed'); await absent('session.mouse.expanded');
        await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
        await menuClick('session.more.input'); await menuClick('session.virtualMouse');
        await absent('session.mouse.collapsed');
      } finally { await mock.disconnect(); await route('devices'); }
    });
    it('virtual_mouse_reaches_all_corners_and_keeps_buttons_inside_with_viewport_pan', 0, async () => {
      try {
        for (const corner of [[0, 0], [1, 0], [0, 1], [1, 1]]) {
          await mock.listDevices(); await mock.connect('demo-win-01'); await route('session'); mock.emitFirstFrame(); await settle();
          await (await driver.findComponent(ON.id('session.mouse.collapsed'))).click(); await settle();
          const surface = await (await driver.findComponent(ON.id('session.surface'))).getBounds();
          let handle = await (await driver.findComponent(ON.id('session.mouse.drag'))).getBounds();
          const density = display.getDefaultDisplaySync().densityPixels;
          const ui = (await window.getLastWindow(context)).getUIContext();
          const video = ui.getComponentUtils().getRectangleById('session.video');
          const initialInputs = mock.sentInputs.map((value: string): Record<string, string | number> => JSON.parse(value))
            .filter((value: Record<string, string | number>) => value['action'] === 'mouse_move_absolute');
          const initial = initialInputs[initialInputs.length - 1];
          const startX = Math.round((handle.left + handle.right) / 2);
          const startY = Math.round((handle.top + handle.bottom) / 2);
          await driver.swipe(startX, startY, Math.round(startX + (0.5 - Number(initial['abs_x'])) * video.size.width),
            Math.round(startY + (0.5 - Number(initial['abs_y'])) * video.size.height), 600); await settle();
          handle = await (await driver.findComponent(ON.id('session.mouse.drag'))).getBounds();
          const before = ui.getComponentUtils().getRectangleById('session.video');
          const count = mock.sentInputs.length;
          await driver.swipe(Math.round((handle.left + handle.right) / 2), Math.round((handle.top + handle.bottom) / 2),
            corner[0] === 0 ? surface.left + 2 : surface.right - 2,
            corner[1] === 0 ? surface.top + 2 : surface.bottom - 2, 600); await settle();
          const inputs = mock.sentInputs.slice(count).map((value: string): Record<string, string | number> => JSON.parse(value))
            .filter((value: Record<string, string | number>) => value['action'] === 'mouse_move_absolute');
          expect(inputs.length > 0).assertTrue();
          const last = inputs[inputs.length - 1];
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MOUSE_CORNER ' + JSON.stringify({
            corner: corner, x: last['abs_x'], y: last['abs_y'] }) + '\n');
          expect(Math.abs(Number(last['abs_x']) - corner[0]) < 0.001).assertTrue();
          expect(Math.abs(Number(last['abs_y']) - corner[1]) < 0.001).assertTrue();
          const alignment = await cursorAlignment(Number(last['abs_x']), Number(last['abs_y']));
          expect(Math.abs(alignment[0] - alignment[2]) <= 2 && Math.abs(alignment[1] - alignment[3]) <= 2).assertTrue();
          await present('session.mouse.expanded');
          const body = await (await driver.findComponent(ON.id('session.mouse.expanded'))).getBounds();
          expect(body.left >= surface.left + 15 * density && body.right <= surface.right - 15 * density &&
            body.top >= surface.top + 15 * density && body.bottom <= surface.bottom - 15 * density).assertTrue();
          const after = ui.getComponentUtils().getRectangleById('session.video');
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MOUSE_EDGE_PAN ' + JSON.stringify({
            corner: corner, surface: surface, body: body, deltaX: after.translate.x - before.translate.x,
            deltaY: after.translate.y - before.translate.y }) + '\n');
          if (corner[0] === 1) { expect(after.translate.x < before.translate.x).assertTrue(); }
          if (corner[1] === 1) { expect(after.translate.y < before.translate.y).assertTrue(); }
          for (const button of [1, 2]) {
            const count = mock.sentInputs.length;
            await (await driver.findComponent(ON.id('session.mouse.button.' + button))).click(); await settle();
            await present('session.mouse.expanded');
            const clicks = mock.sentInputs.slice(count).map((value: string): Record<string, string | number> => JSON.parse(value));
            expect(clicks.length).assertEqual(2);
            expect(clicks[0]['action']).assertEqual('mouse_press'); expect(clicks[0]['button']).assertEqual(button);
            expect(clicks[1]['action']).assertEqual('mouse_release'); expect(clicks[1]['button']).assertEqual(button);
          }
          await capture('virtual-mouse-corner-' + corner[0] + '-' + corner[1]);
          await mock.disconnect(); await route('devices');
        }
      } finally { await mock.disconnect(); await route('devices'); }
    });
    it('surface_touch_and_external_mouse_click_collapse_virtual_mouse', 0, async () => {
      const original = mock.settings().touchMode;
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        await mock.setTouchMode('direct'); mock.emitFirstFrame(); await settle();
        const video = await (await driver.findComponent(ON.id('session.video'))).getBounds();
        const x = Math.round(video.left + (video.right - video.left) * 0.65);
        const y = Math.round(video.top + (video.bottom - video.top) * 0.35);
        for (const source of ['touch', 'mouse', 'touch-drag', 'mouse-drag', 'readonly']) {
          await (await driver.findComponent(ON.id('session.mouse.collapsed'))).click(); await settle();
          if (source.endsWith('-drag')) {
            await (await driver.findComponent(ON.id('session.mouse.dragLock'))).click(); await settle();
            await present('session.mouse.expanded');
          }
          if (source === 'readonly') { await mock.setViewOnly(true); await settle(); }
          const count = mock.sentInputs.length;
          const releases = mock.releaseCount;
          if (source.startsWith('touch')) { await driver.click(x, y); }
          else { await driver.mouseClick({ x: x, y: y }, TestMouseButton.MOUSE_BUTTON_LEFT); }
          await settle(); await absent('session.mouse.expanded'); await present('session.mouse.collapsed');
          if (source.endsWith('-drag')) { expect(mock.releaseCount > releases).assertTrue(); }
          const inputs = mock.sentInputs.slice(count).map((value: string): Record<string, string | number> => JSON.parse(value));
          if (source === 'readonly') { expect(inputs.length).assertEqual(0); }
          else {
            const press = source.startsWith('touch') ? 'touch_down' : 'mouse_press';
            const release = source.startsWith('touch') ? 'touch_up' : 'mouse_release';
            expect(inputs.filter((value: Record<string, string | number>) => value['action'] === press).length).assertEqual(1);
            expect(inputs.filter((value: Record<string, string | number>) => value['action'] === release).length).assertEqual(1);
          }
        }
      } finally { await mock.setViewOnly(false); await mock.setTouchMode(original); await mock.disconnect(); await route('devices'); }
    });
    it('menu_insets_stay_even_and_receding_layers_stay_sharp', 0, async () => {
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.emitFirstFrame(); await settle();
        await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
        await revealMenuItem('session.more.end');
        const panel = await (await driver.findComponent(ON.id('session.action.menu'))).getBounds();
        const end = await (await driver.findComponent(ON.id('session.more.end'))).getBounds();
        const density = display.getDefaultDisplaySync().densityPixels;
        const left = (end.left - panel.left) / density;
        const right = (panel.right - end.right) / density;
        const bottom = (panel.bottom - end.bottom) / density;
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MENU_INSETS ' + JSON.stringify({ left: left, right: right, bottom: bottom, panel: panel, end: end }) + '\n');
        await capture('menu-even-danger-insets');
        expect(left >= 7 && Math.abs(left - right) <= 1 && Math.abs(left - bottom) <= 1).assertTrue();
        await menuClick('session.quality');
        const material: ScrollBarInspector = JSON.parse(getInspectorByKey('session.action.menu'));
        expect(Number.parseFloat(material.$attrs?.['blur'] ?? '0')).assertEqual(0);
        const first: ScrollBarInspector = JSON.parse(getInspectorByKey('session.menu.content.0'));
        const child: ScrollBarInspector = JSON.parse(getInspectorByKey('session.menu.content.1'));
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MENU_BLUR ' + JSON.stringify({ parent: first.$attrs?.['blur'], child: child.$attrs?.['blur'] }) + '\n');
        expect(Number.parseFloat(first.$attrs?.['blur'] ?? '0')).assertEqual(0);
        expect(Number.parseFloat(child.$attrs?.['blur'] ?? '0')).assertEqual(0);
        await capture('menu-parent-sharp');
        await menuClick('session.resolution.select');
        const middle: ScrollBarInspector = JSON.parse(getInspectorByKey('session.menu.content.1'));
        const front: ScrollBarInspector = JSON.parse(getInspectorByKey('session.menu.content.2'));
        expect(Number.parseFloat(middle.$attrs?.['blur'] ?? '0')).assertEqual(0);
        expect(Number.parseFloat(front.$attrs?.['blur'] ?? '0')).assertEqual(0);
        await capture('menu-nested-parent-sharp');
        await driver.pressBack(); await settle(); await driver.pressBack(); await settle();
        const restored: ScrollBarInspector = JSON.parse(getInspectorByKey('session.menu.content.0'));
        expect(Number.parseFloat(restored.$attrs?.['blur'] ?? '0')).assertEqual(0);
        await present('session.more.input');
      } finally { await mock.disconnect(); await route('devices'); }
    });
    it('resolution_menu_uses_reported_modes_and_keeps_showing_actual_stream_size', 0, async () => {
      const profile = mock.settings().defaultVideoProfile;
      const modes: VideoResolution[] = [{ width: 1920, height: 1080 }, { width: 1600, height: 900 }];
      const openResolution = async (): Promise<void> => {
        await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
        await menuClick('session.quality'); await revealMenuItem('session.resolution.select');
      };
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.emitFirstFrame(); mock.setResolutionFixture(1920, 1080, modes); await settle();
        await openResolution();
        expect(await (await driver.findComponent(ON.id('session.resolution.select.value'))).getText()).assertEqual('1920×1080');
        await menuClick('session.resolution.select');
        await present('session.resolution.auto'); await present('session.resolution.window');
        await present('session.resolution.1080p60'); await present('session.resolution.1600x900');
        await absent('session.resolution.720p30');
        await menuClick('session.resolution.1600x900');
        expect(mock.settings().defaultVideoProfile).assertEqual('1600x900');
        await openResolution();
        expect(await (await driver.findComponent(ON.id('session.resolution.select.value'))).getText()).assertEqual('1920×1080');
        mock.setResolutionFixture(1600, 900, modes); await settle();
        expect(await (await driver.findComponent(ON.id('session.resolution.select.value'))).getText()).assertEqual('1600×900');
        await feedbackFrame('reported-resolution');
      } finally {
        mock.setResolutionFixture(0, 0);
        await mock.setVideoProfile(profile); await mock.disconnect(); await route('devices');
      }
    });
    it('session_menu_uses_the_configured_system_material', 0, async () => {
      const original = mock.settings().materialPreference;
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.emitFirstFrame(); await settle();
        await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
        const ui = (await window.getLastWindow(context)).getUIContext();
        const preferences: MaterialPreference[] = ['exquisite', 'gentle', 'smooth', 'system'];
        for (const preference of preferences) {
          await mock.setMaterialPreference(preference); await settle();
          const panel = (JSON.parse(getInspectorByKey('session.action.menu')) as ScrollBarInspector).$attrs;
          const effect = JSON.stringify(panel?.['backgroundEffect'] ?? '');
          if (deviceInfo.apiAvailable('26.0.0') && uiMaterial.isImmersiveMaterialSupported()) {
            const native = (JSON.parse(getInspectorByKey('session.menu.material.0')) as ScrollBarInspector).$attrs;
            const style = AppStorage.get<hdsMaterial.MaterialLevel>('hdsMaterialLevel');
            const expected = style === hdsMaterial.MaterialLevel.SMOOTH ||
              style === hdsMaterial.MaterialLevel.EXQUISITE ? 'THIN' :
              style === hdsMaterial.MaterialLevel.GENTLE ? 'REGULAR' : 'THICK';
            const material = JSON.stringify(native?.['systemMaterial'] ?? '');
            expect(material.includes('MaterialType.IMMERSIVE') && material.includes('ImmersiveStyle.' + expected)).assertTrue();
            if (style === hdsMaterial.MaterialLevel.EXQUISITE) {
              const label = (JSON.parse(getInspectorByKey('session.more.audio.label')) as ScrollBarInspector).$attrs;
              const value = (JSON.parse(getInspectorByKey('session.more.audio.value')) as ScrollBarInspector).$attrs;
              expect(label?.['fontColor']?.length ?? 0).assertLarger(0);
              expect(value?.['fontColor']).assertEqual(label?.['fontColor']);
              await capture('menu-exquisite');
            }
            expect(effect.includes('"radius":40')).assertFalse();
            const rects = UiProbe.measure(ui, ['session.action.menu', 'session.menu.material.0']);
            expect(rects[0].bounds.length).assertEqual(4);
            expect(rects[1].bounds.length).assertEqual(4);
            for (let index = 0; index < 4; index++) {
              expect(Math.abs(rects[0].bounds[index] - rects[1].bounds[index]) <= 1).assertTrue();
            }
          } else {
            expect(effect.includes('"radius":40')).assertTrue();
          }
        }
      } finally { await mock.setMaterialPreference(original); await mock.disconnect(); await route('devices'); }
    });
    it('toolbar_show_desktop_and_saved_shortcut_order_survive_reopening', 0, async () => {
      const store = await preferences.getPreferences(context, 'uu_remote_settings');
      const toolbarPref = 'remoteToolbarActions';
      const chordPref = 'remoteKeyboardShortcuts';
      const previousToolbar = await store.get(toolbarPref, '');
      const previousChords = await store.get(chordPref, '');
      const previousMaterial = mock.settings().materialPreference;
      const previousVolume = mock.audioVolume();
      const hadToolbar = await store.has(toolbarPref);
      const hadChords = await store.has(chordPref);
      const custom = 'session.shortcut.custom-224-14';
      const sentKeys = (start: number): string[] => mock.sentInputs.slice(start).map((value: string): Record<string, string | number | boolean> => JSON.parse(value))
        .filter((value: Record<string, string | number | boolean>) => value['action'] === 'key')
        .map((value: Record<string, string | number | boolean>) => `${value['scan']}:${value['down']}`);
      try {
        await mock.setMaterialPreference('exquisite');
        await mock.setAudioVolume(100);
        await store.delete(toolbarPref);
        await store.put(chordPref, JSON.stringify([[KeyCode.KEYCODE_CTRL_LEFT, KeyCode.KEYCODE_K]]));
        await store.flush();
        await mock.listDevices(); await mock.connect('demo-win-01'); await route('session'); mock.emitFirstFrame(); await settle();
        const first = mock.sentInputs.length;
        await (await driver.findComponent(ON.id('session.showDesktop'))).click(); await settle();
        expect(sentKeys(first)).assertDeepEquals(['227:true', '7:true', '7:false', '227:false']);

        await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
        const entry = await (await driver.findComponent(ON.id('session.more.toolbarEdit'))).getBounds();
        const firstPage = await (await driver.findComponent(ON.id('session.menu.items.0'))).getBounds();
        expect(entry.top >= firstPage.top && entry.bottom <= firstPage.bottom).assertTrue();
        await feedbackFrame('toolbar-entry-first-page');
        await menuClick('session.more.toolbarEdit');
        await present('session.toolbar.editor');
        const editorUi = (await window.getLastWindow(context)).getUIContext();
        const editorRows = UiProbe.measure(editorUi, ['session.toolbar.editor.done', 'session.toolbar.editor.selected.session.rotate']);
        const gap = editorRows[1].bounds[1] - editorRows[0].bounds[1] - editorRows[0].bounds[3];
        expect(gap >= 0 && gap <= 40).assertTrue();
        if (deviceInfo.apiAvailable('26.0.0') && uiMaterial.isImmersiveMaterialSupported()) {
          const surfaces = ['session.toolbar.editor', 'session.toolbar.editor.done',
            'session.toolbar.editor.selected.session.rotate', 'session.toolbar.editor.add.' + custom];
          const material = (id: string): string => JSON.stringify(
            (JSON.parse(getInspectorByKey(id + '.material')) as ScrollBarInspector).$attrs?.['systemMaterial'] ?? '');
          for (const id of surfaces) { expect(material(id).includes('ImmersiveStyle.THIN')).assertTrue(); }
          if (hdsMaterial.getSystemMaterialTypes().includes(hdsMaterial.MaterialType.IMMERSIVE)) {
            await mock.setMaterialPreference('gentle'); await settle();
            for (const id of surfaces) { expect(material(id).includes('ImmersiveStyle.REGULAR')).assertTrue(); }
            await mock.setMaterialPreference('exquisite'); await settle();
          }
        }
        await (await driver.findComponent(ON.id('session.toolbar.editor.add.' + custom))).click(); await settle();
        await (await driver.findComponent(ON.id('session.toolbar.editor.up.' + custom))).click(); await settle();
        await (await driver.findComponent(ON.id('session.toolbar.editor.remove.session.pip'))).click(); await settle();
        for (const id of ['session.toolbar.hideAll', 'session.toolbar.audio']) {
          const addId = 'session.toolbar.editor.add.' + id;
          await scrollToId('session.toolbar.editor.scroll', addId);
          await (await driver.findComponent(ON.id(addId))).click(); await settle();
        }
        await feedbackFrame('customizable-toolbar-editor');
        await (await driver.findComponent(ON.id('session.toolbar.editor.done'))).click(); await settle();
        await absent('session.toolbar.editor'); await absent('session.pip'); await present(custom);
        const shortcutStart = mock.sentInputs.length;
        await (await driver.findComponent(ON.id(custom))).click(); await settle();
        expect(sentKeys(shortcutStart)).assertDeepEquals(['224:true', '14:true', '14:false', '224:false']);

        await mock.disconnect(); await route('devices');
        await mock.connect('demo-win-01'); await route('session'); mock.emitFirstFrame(); await settle();
        await absent('session.pip');
        await (await driver.findComponent(ON.id('session.gestures'))).pinchOut(2); await settle();
        const menuUi = (await window.getLastWindow(context)).getUIContext();
        const actionIds = ['session.rotate', 'session.keyboard', custom, 'session.showDesktop',
          'session.toolbar.hideAll', 'session.toolbar.audio'];
        const zoomFrames = UiProbe.measure(menuUi, ['session.page', 'session.zoom.reset', ...actionIds]);
        const viewport = zoomFrames[0].bounds;
        const scale = zoomFrames[1].bounds;
        for (let index = 2; index < zoomFrames.length; index++) {
          const button = zoomFrames[index].bounds;
          expect(button[0] >= viewport[0] + 15 && button[0] + button[2] <= viewport[0] + viewport[2] - 15).assertTrue();
          expect(Math.abs(button[1] + button[3] / 2 - scale[1] - scale[3] / 2) <= 1).assertTrue();
        }
        const combo = await (await driver.findComponent(ON.id(custom))).getBounds();
        const desktop = await (await driver.findComponent(ON.id('session.showDesktop'))).getBounds();
        expect(combo.right < desktop.left).assertTrue();
        const audioId = 'session.toolbar.audio';
        const audioMenuId = 'session.action.menu.session.more.audio';
        const audioButton = UiProbe.measure(menuUi, [audioId])[0].bounds;
        await (await driver.findComponent(ON.id(audioId))).click(); await settle();
        await present(audioMenuId);
        await absent('session.action.menu');
        const frames = UiProbe.measure(menuUi, ['session.page', audioMenuId]);
        const page = frames[0].bounds;
        const popup = frames[1].bounds;
        const centered = audioButton[0] + (audioButton[2] - popup[2]) / 2;
        const popupLeft = Math.max(page[0] + 16, Math.min(centered, page[0] + page[2] - 16 - popup[2]));
        expect(Math.abs(popup[0] - popupLeft) <= 1).assertTrue();
        expect(Math.abs(audioButton[1] - popup[1] - popup[3] - 8) <= 1).assertTrue();
        const volume = await (await driver.findComponent(ON.id('session.audio.volume'))).getBounds();
        await driver.click(Math.round((volume.left + volume.right) / 2), Math.round((volume.top + volume.bottom) / 2));
        await settle();
        expect(mock.audioVolume() > 0 && mock.audioVolume() < 100).assertTrue();
        await feedbackFrame('toolbar-audio-popup');
        const outsideStart = mock.sentInputs.length;
        await driver.click(Math.round((combo.left + combo.right) / 2), Math.round((combo.top + combo.bottom) / 2));
        await settle();
        await absent(audioMenuId);
        expect(sentKeys(outsideStart)).assertDeepEquals([]);
        await (await driver.findComponent(ON.id(audioId))).click(); await settle();
        await present(audioMenuId);
        await driver.pressBack(); await settle();
        await absent(audioMenuId);
        await (await driver.findComponent(ON.id('session.toolbar.hideAll'))).click(); await settle();
        await absent('session.header'); await absent('session.toolbar'); await absent('session.mouse.collapsed');
        await driver.pressBack(); await settle();
        await present('session.header'); await present('session.toolbar.hideAll');
      } finally {
        await mock.disconnect(); await route('devices');
        await mock.setMaterialPreference(previousMaterial);
        await mock.setAudioVolume(previousVolume);
        if (hadToolbar) { await store.put(toolbarPref, previousToolbar); } else { await store.delete(toolbarPref); }
        if (hadChords) { await store.put(chordPref, previousChords); } else { await store.delete(chordPref); }
        await store.flush();
      }
    });
    it('passive_overlays_and_clean_view_allow_touching_the_picture', 0, async () => {
      const previous = mock.settings().touchMode;
      const taps = (start: number): string[] => mock.sentInputs.slice(start)
        .map((value: string): Record<string, string | number> => JSON.parse(value))
        .filter((value: Record<string, string | number>) => value['action'] === 'touch_down' || value['action'] === 'touch_up')
        .map((value: Record<string, string | number>) => String(value['action']));
      await mock.setTouchMode('direct'); await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.emitFirstFrame(); await settle();
        await (await driver.findComponent(ON.id('session.gestures'))).pinchOut(2); await settle();
        const title = await (await driver.findComponent(ON.id('session.title'))).getBounds();
        const titleStart = mock.sentInputs.length;
        await driver.click(Math.round((title.left + title.right) / 2), Math.round((title.top + title.bottom) / 2)); await settle();
        expect(taps(titleStart)).assertDeepEquals(['touch_down', 'touch_up']);
        const rotate = await (await driver.findComponent(ON.id('session.rotate'))).getBounds();
        const keyboard = await (await driver.findComponent(ON.id('session.keyboard'))).getBounds();
        const gapStart = mock.sentInputs.length;
        await driver.click(Math.round((rotate.right + keyboard.left) / 2), Math.round((rotate.top + rotate.bottom) / 2)); await settle();
        expect(taps(gapStart)).assertDeepEquals(['touch_down', 'touch_up']);

        const more = await (await driver.findComponent(ON.id('session.more'))).getBounds();
        const moreStart = mock.sentInputs.length;
        await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
        expect(taps(moreStart)).assertDeepEquals([]);
        await menuClick('session.more.input'); await menuClick('session.more.hide');
        await absent('session.header'); await absent('session.toolbar');
        await absent('session.toolbar.restore');
        await absent('session.zoom.reset'); await absent('session.mouse.collapsed');
        const clearStart = mock.sentInputs.length;
        await driver.click(Math.round((more.left + more.right) / 2), Math.round((more.top + more.bottom) / 2)); await settle();
        expect(taps(clearStart)).assertDeepEquals(['touch_down', 'touch_up']);
        await driver.pressBack(); await settle();
        await present('session.header'); await present('session.toolbar'); await present('session.zoom.reset');
        await absent('session.action.menu');
      } finally { await mock.setTouchMode(previous); await mock.disconnect(); await route('devices'); }
    });
    it('input_mode_stays_in_sync_between_settings_and_remote_controls', 0, async () => {
      const original = mock.settings().touchMode;
      try {
        await mock.setTouchMode('trackpad');
        await generalSettings();
        await selectedValue('settings.input', '触控板');
        await mock.setTouchMode('direct'); await settle();
        await selectedValue('settings.input', '直接触控');
        await (await driver.findComponent(ON.id('settings.input'))).click(); await settle();
        await (await driver.findComponent(ON.text('触控板'))).click(); await settle();
        expect(mock.settings().touchMode).assertEqual('trackpad');
        await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
        mock.emitFirstFrame(); await settle();
        await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
        await menuClick('session.more.input');
        expect(await (await driver.findComponent(ON.id('session.inputMode.label'))).getText()).assertEqual('触控板');
        await menuClick('session.inputMode');
        expect(mock.settings().touchMode).assertEqual('direct');
        await mock.disconnect(); await generalSettings();
        await selectedValue('settings.input', '直接触控');
      } finally { await mock.setTouchMode(original); await mock.disconnect(); await route('devices'); }
    });
    it('hide_toolbar_keeps_picture_only_until_escape_restores_controls', 0, async () => {
      const position = mock.settings().controlBarPosition;
      const smartReach = mock.settings().smartReachEnabled;
      await mock.setSmartReachEnabled(false); await mock.setControlBarPosition('right');
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.emitFirstFrame(); await settle();
        await (await driver.findComponent(ON.id('session.gestures'))).pinchOut(2); await settle();
        await present('session.zoom.reset');
        await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
        await menuClick('session.more.input'); await menuClick('session.more.hide');
        await absent('session.header'); await absent('session.toolbar'); await absent('session.toolbar.restore');
        await absent('session.zoom.reset'); await absent('session.mouse.collapsed');
        await driver.triggerKey(KeyCode.KEYCODE_ESCAPE); await settle();
        await present('session.header'); await present('session.toolbar'); await present('session.zoom.reset');
      } finally {
        await mock.disconnect(); await route('devices');
        await mock.setControlBarPosition(position); await mock.setSmartReachEnabled(smartReach);
      }
    });
    it('remote_operation_groups_settings_and_confirms_each_change', 0, async () => {
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      const start = mock.sentRemoteSettings.length;
      const openRemote = async (): Promise<void> => {
        await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
        await menuClick('session.more.remote');
      };
      try {
        mock.emitFirstFrame(); await settle();
        await openRemote();
        const entries = ['session.more.mute.select', 'session.more.lock.select', 'session.more.reboot', 'session.more.shutdown'];
        const viewport = await (await driver.findComponent(ON.id('session.menu.items.1'))).getBounds();
        const density = display.getDefaultDisplaySync().densityPixels;
        let previousBottom = viewport.top - 8 * density;
        for (const id of entries) {
          await revealMenuItem(id);
          const row = await (await driver.findComponent(ON.id(id))).getBounds();
          expect(Math.abs((row.bottom - row.top) / density - 48) <= 1).assertTrue();
          expect(row.top >= viewport.top && row.bottom <= viewport.bottom).assertTrue();
          expect(Math.abs((row.top - previousBottom) / density - 8) <= 1).assertTrue();
          previousBottom = row.bottom;
        }
        await absent('session.more.mute'); await absent('session.more.unmute');
        await absent('session.more.lock'); await absent('session.more.unlock');
        expect(await (await driver.findComponent(ON.id('session.more.reboot.label'))).getText()).assertEqual('重启');
        expect(await (await driver.findComponent(ON.id('session.more.shutdown.label'))).getText()).assertEqual('关机');
        await feedbackFrame('remote-operations-grouped');

        await menuClick('session.more.mute.select');
        await buttonSpacing(['session.more.mute', 'session.more.unmute'], true);
        expect(await (await driver.findComponent(ON.id('session.more.mute.label'))).getText()).assertEqual('启用');
        expect(await (await driver.findComponent(ON.id('session.more.unmute.label'))).getText()).assertEqual('停用');
        await feedbackFrame('remote-mute-choices');
        await menuClick('session.more.unmute');
        expect(mock.sentRemoteSettings.length).assertEqual(start);
        await (await driver.findComponent(ON.text('发送'))).click(); await settle();
        expect(mock.sentRemoteSettings.slice(start)).assertDeepEquals(['hostMute:false']);

        await openRemote();
        await menuClick('session.more.lock.select');
        await buttonSpacing(['session.more.lock', 'session.more.unlock'], true);
        expect(await (await driver.findComponent(ON.id('session.more.lock.label'))).getText()).assertEqual('启用');
        expect(await (await driver.findComponent(ON.id('session.more.unlock.label'))).getText()).assertEqual('停用');
        await menuClick('session.more.lock');
        await (await driver.findComponent(ON.text('发送'))).click(); await settle();
        expect(mock.sentRemoteSettings.slice(start)).assertDeepEquals(['hostMute:false', 'autoLock:true']);

        await mock.setViewOnly(true); await settle();
        await openRemote();
        for (const id of ['session.more.mute.select', 'session.more.lock.select']) {
          expect(await (await driver.findComponent(ON.id(id))).isEnabled()).assertFalse();
        }
      } finally { await mock.setViewOnly(false); await mock.disconnect(); await route('devices'); }
    });
    it('action_button_groups_share_eight_vp_gaps', 0, async () => {
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.emitFirstFrame(); await settle();
        await buttonSpacing(['session.rotate', 'session.keyboard', 'session.pip']);
        await (await driver.findComponent(ON.id('session.keyboard'))).click(); await settle();
        await buttonSpacing(['session.text.input', 'session.text.send', 'session.text.close']);
        await (await driver.findComponent(ON.id('session.text.close'))).click(); await settle();
        await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
        await buttonSpacing(['session.more.input', 'session.quality', 'session.more.tools',
          'session.more.clipboard', 'session.more.audio', 'session.more.stats',
          'session.more.remote', 'session.more.end'], true);
        await menuClick('session.more.input');
        await buttonSpacing(['session.inputMode', 'session.virtualMouse', 'session.more.viewOnly', 'session.more.hide'], true);
        await menuClick('session.virtualMouse');
        await absent('session.mouse.collapsed');
        await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
        await menuClick('session.more.input'); await menuClick('session.virtualMouse');
        await (await driver.findComponent(ON.id('session.mouse.collapsed'))).click(); await settle();
        await buttonSpacing(['session.mouse.dragLock', 'session.mouse.collapse']);
        await capture('action-button-spacing');
      } finally { await mock.disconnect(); await route('devices'); }
    });
    it('all_page_headers_share_the_floating_control_top_inset', 0, async () => {
      const ui = (await window.getLastWindow(context)).getUIContext();
      for (const name of ['devices', 'files', 'portmap', 'terminal', 'settings', 'host']) {
        await route(name);
        const headerId = name === 'devices' ? 'app.header.controls' : name === 'settings' ? 'settings.header.controls' :
          name === 'host' ? 'host.header' : 'tool.header.controls';
        const header = UiProbe.measure(ui, [headerId])[0].bounds;
        const rootId = name === 'devices' || name === 'settings' ? 'app.shell' : name === 'host' ? 'host.page' : 'tool.page.shell';
        const root = UiProbe.measure(ui, [rootId])[0].bounds;
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_HEADER_INSET ' + JSON.stringify({ name: name, header: header, root: root }) + '\n');
        expect(Math.abs(header[3] - (name === 'host' ? 80 : 56)) <= 1).assertTrue();
        expect(Math.abs(header[1] - root[1] - (name === 'host' ? 0 : 12)) <= 1).assertTrue();
        if (name !== 'settings') {
          const controlId = name === 'devices' ? 'devices.refresh' : name === 'host' ? 'host.back' : 'tool.back';
          const control = UiProbe.measure(ui, [controlId])[0].bounds;
          expect(Math.abs(control[1] - root[1] - 16) <= 1).assertTrue();
          const side = name === 'devices' ? root[0] + root[2] - control[0] - control[2] : control[0] - root[0];
          expect(Math.abs(side - 16) <= 1).assertTrue();
        }
        if (name === 'settings') {
          await (await driver.findComponent(ON.id('settings.general'))).click(); await settle();
          const detail = UiProbe.measure(ui, ['settings.detail.header.controls'])[0].bounds;
          expect(Math.abs(detail[3] - 56) <= 1).assertTrue();
          if (((await driver.findComponents(ON.id('settings.detail.back')))?.length ?? 0) > 0) {
            const back = UiProbe.measure(ui, ['settings.detail.back'])[0].bounds;
            expect(Math.abs(back[1] - root[1] - 16) <= 1).assertTrue();
          }
        }
        await capture('unified-top-inset-' + name);
      }
      await route('devices');
    });
    it('disconnect_restores_home_background_and_bottom_material', 0, async () => {
      const previousTheme = mock.settings().themePreference;
      const win = await window.getLastWindow(context);
      const tones = async (): Promise<number[]> => {
        const pixels = await win.snapshot();
        try {
          const info = await pixels.getImageInfo();
          expect(info.pixelFormat === image.PixelMapFormat.RGBA_8888 ||
            info.pixelFormat === image.PixelMapFormat.BGRA_8888).assertTrue();
          const buffer = new ArrayBuffer(pixels.getPixelBytesNumber());
          await pixels.readPixelsToBuffer(buffer);
          const bytes = new Uint8Array(buffer);
          const stride = pixels.getBytesNumberPerRow();
          const x = Math.floor(info.size.width * 0.02);
          return [0.5, 0.96].map((height: number) => {
            const offset = Math.floor(info.size.height * height) * stride + x * 4;
            return (bytes[offset] + bytes[offset + 1] + bytes[offset + 2]) / 3;
          });
        } finally { await pixels.release(); }
      };
      try {
        const themes: ThemePreference[] = ['light', 'dark'];
        for (const theme of themes) {
          ThemeManager.apply(context, theme);
          await route('devices'); await mock.listDevices(); await settle();
          const before = await tones();
          await mock.connect('demo-win-01'); await route('session'); mock.emitFirstFrame(); await settle();
          await (await driver.findComponent(ON.id('session.back'))).click(); await settle();
          await (await driver.findComponent(ON.text('结束连接'))).click(); await settle();
          await present('app.shell'); await present('devices.search'); await absent('session.page');
          const after = await tones();
          await feedbackFrame('home-after-disconnect-' + theme);
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_HOME_TONES ' +
            JSON.stringify({ theme: theme, before: before, after: after }) + '\n');
          expect(theme === 'light' ? before[0] > 150 : before[0] < 80).assertTrue();
          expect(Math.abs(before[0] - after[0]) < 20 && Math.abs(before[1] - after[1]) < 20).assertTrue();
        }
      } finally {
        await mock.disconnect();
        ThemeManager.apply(context, previousTheme);
        await route('devices');
      }
    });
    it('remote_toolbar_zoom_expands_in_one_row_and_keeps_header_insets', 0, async () => {
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      const win = await window.getLastWindow(context);
      const originalOrientation = win.getPreferredOrientation();
      const settings = mock.settings();
      const smartReach = settings.smartReachEnabled;
      const originalPosition = settings.controlBarPosition;
      try {
        mock.emitFirstFrame(); await settle();
        const ui = win.getUIContext();
        const orientations = deviceInfo.deviceType === '2in1' ? [originalOrientation] :
          [window.Orientation.USER_ROTATION_PORTRAIT, window.Orientation.USER_ROTATION_LANDSCAPE];
        await mock.setSmartReachEnabled(false);
        for (const orientation of orientations) {
          await win.setPreferredOrientation(orientation); await settle();
          for (const id of ['session.rotate', 'session.keyboard', 'session.pip']) { await roundControl(id); }
          await buttonSpacing(['session.rotate', 'session.keyboard', 'session.pip']);
          const header = UiProbe.measure(ui, ['session.page', 'session.header.capsule', 'session.more']);
          expect(Math.abs(header[1].bounds[1] - header[0].bounds[1] - 16) <= 1).assertTrue();
          expect(Math.abs(header[1].bounds[0] - header[0].bounds[0] - 16) <= 1).assertTrue();
          expect(Math.abs(header[0].bounds[0] + header[0].bounds[2] - header[2].bounds[0] - header[2].bounds[2] - 16) <= 1).assertTrue();
          expect(Math.abs(header[2].bounds[1] - header[1].bounds[1]) <= 1).assertTrue();
          for (const position of ['left', 'center', 'right'] as ControlBarPosition[]) {
            await route('devices'); await mock.setControlBarPosition(position); await route('session');
            mock.emitFirstFrame(); await settle();
            const collapsed = UiProbe.measure(ui, ['session.toolbar'])[0].bounds;
            await (await driver.findComponent(ON.id('session.gestures'))).pinchOut(2); await settle();
            const rects = UiProbe.measure(ui, ['session.zoom.reset', 'session.rotate', 'session.keyboard', 'session.pip', 'session.showDesktop']);
            const visualBounds = [] as number[][];
            const density = display.getDefaultDisplaySync().densityPixels;
            for (const id of ['session.page', 'session.zoom.reset', 'session.rotate', 'session.keyboard', 'session.pip', 'session.showDesktop']) {
              const bound = await (await driver.findComponent(ON.id(id))).getBounds();
              visualBounds.push([bound.left / density, bound.top / density,
                (bound.right - bound.left) / density, (bound.bottom - bound.top) / density]);
            }
            await abilityDelegatorRegistry.getAbilityDelegator().print('UU_THREE_CONTROL_LAYOUT ' + JSON.stringify({
              orientation: orientation, position: position, page: header[0].bounds,
              capsule: header[1].bounds, pip: header[2].bounds, rects: rects,
              route: Router.current(), phase: mock.sessionSnapshot().phase, visualBounds: visualBounds }) + '\n');
            await capture('three-controls-zoom-' + position + '-' + orientation);
            const zoom = rects[0].bounds;
            const expanded = UiProbe.measure(ui, ['session.toolbar'])[0].bounds;
            expect(expanded[2] > collapsed[2]).assertTrue();
            expect(Math.abs(zoom[1] - collapsed[1]) <= 1).assertTrue();
            for (let index = 1; index <= 4; index++) {
              expect(Math.abs(zoom[1] + zoom[3] / 2 - rects[index].bounds[1] - rects[index].bounds[3] / 2) <= 1).assertTrue();
            }
            expect(rects[2].bounds[0] + rects[2].bounds[2] < zoom[0]).assertTrue();
            expect(zoom[0] + zoom[2] < rects[3].bounds[0]).assertTrue();
            expect(Math.abs(zoom[0] + zoom[2] / 2 - expanded[0] - expanded[2] / 2) <= 1).assertTrue();
            expect(Math.abs(header[0].bounds[1] + header[0].bounds[3] - rects[4].bounds[1] - rects[4].bounds[3] - 16) <= 1).assertTrue();
            if (position === 'left') { expect(Math.abs(rects[1].bounds[0] - header[0].bounds[0] - 16) <= 1).assertTrue(); }
            if (position === 'right') { expect(Math.abs(header[0].bounds[0] + header[0].bounds[2] - rects[4].bounds[0] - rects[4].bounds[2] - 16) <= 1).assertTrue(); }
            if (position === 'center') {
              expect(Math.abs(rects[0].bounds[0] + rects[0].bounds[2] / 2 - header[0].bounds[0] - header[0].bounds[2] / 2) <= 1).assertTrue();
            }
          }
          await (await driver.findComponent(ON.id('session.zoom.reset'))).click(); await settle();
        }
      } finally {
        await mock.setSmartReachEnabled(smartReach); await mock.setControlBarPosition(originalPosition);
        await mock.disconnect(); await route('devices');
        await win.setPreferredOrientation(originalOrientation);
      }
    });
    it('remote_picture_pinch_pan_and_reset_reuse_the_video_surface', 0, async () => {
      const touchMode = mock.settings().touchMode;
      await mock.setTouchMode('direct');
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      const smartReach = mock.settings().smartReachEnabled;
      const controlBarPosition = mock.settings().controlBarPosition;
      const materialPreference = mock.settings().materialPreference;
      try {
        await mock.setMaterialPreference('exquisite');
        mock.emitFirstFrame(); await settle();
        const attachments = mock.attachCount;
        const releases = mock.releaseCount;
        await (await driver.findComponent(ON.id('session.gestures'))).pinchOut(2); await settle();
        await present('session.zoom.reset');
        if (deviceInfo.apiAvailable('26.0.0') && uiMaterial.isImmersiveMaterialSupported()) {
          const id = 'session.zoom.reset.material';
          const currentMaterial = (): string => JSON.stringify(
            (JSON.parse(getInspectorByKey(id)) as ScrollBarInspector).$attrs?.['systemMaterial'] ?? '');
          expect(currentMaterial().includes('ImmersiveStyle.THIN')).assertTrue();
          const ui = (await window.getLastWindow(context)).getUIContext();
          const rects = UiProbe.measure(ui, ['session.zoom.reset', id]);
          for (let index = 0; index < 4; index++) {
            expect(Math.abs(rects[0].bounds[index] - rects[1].bounds[index]) <= 1).assertTrue();
          }
          if (hdsMaterial.getSystemMaterialTypes().includes(hdsMaterial.MaterialType.IMMERSIVE)) {
            await mock.setMaterialPreference('gentle'); await settle();
            expect(currentMaterial().includes('ImmersiveStyle.REGULAR')).assertTrue();
            await mock.setMaterialPreference('exquisite'); await settle();
          }
        }
        await feedbackFrame('zoom-material');
        expect(mock.attachCount).assertEqual(attachments);
        expect(mock.releaseCount > releases).assertTrue();
        await capture('session-zoom');
        const surface = await (await driver.findComponent(ON.id('session.gestures'))).getBounds();
        const x = Math.round((surface.left + surface.right) / 2);
        const y = Math.round((surface.top + surface.bottom) / 2);
        const count = mock.sentInputs.length;
        await driver.swipe(x, y, Math.round(x + (surface.right - surface.left) * 0.15), y, 600); await settle();
        expect(mock.sentInputs.length).assertEqual(count);
        await driver.click(x, y); await settle();
        const touches = mock.sentInputs.slice(count).map((value: string): Record<string, string | number> => JSON.parse(value))
          .filter((value: Record<string, string | number>) => value['action'] === 'touch_down');
        expect(touches.length).assertEqual(1);
        expect(Number(touches[0]['abs_x']) < 0.5 && Number(touches[0]['abs_x']) >= 0).assertTrue();
        const doubleTapStart = mock.sentInputs.length;
        await driver.doubleClick(x, y); await settle();
        const doubleTapInputs = mock.sentInputs.slice(doubleTapStart)
          .map((value: string): Record<string, string | number> => JSON.parse(value));
        expect(doubleTapInputs.filter((value: Record<string, string | number>) => value['action'] === 'touch_down').length)
          .assertEqual(2);
        expect(doubleTapInputs.filter((value: Record<string, string | number>) => value['action'] === 'touch_up').length)
          .assertEqual(2);
        await mock.setSmartReachEnabled(false);
        for (const position of ['left', 'center', 'right'] as ControlBarPosition[]) {
          await mock.setControlBarPosition(position); await settle();
          const zoomBounds = await (await driver.findComponent(ON.id('session.zoom.reset'))).getBounds();
          const toolbarBounds = await (await driver.findComponent(ON.id('session.toolbar'))).getBounds();
          const firstButton = await (await driver.findComponent(ON.id('session.rotate'))).getBounds();
          const lastButton = await (await driver.findComponent(ON.id('session.showDesktop'))).getBounds();
          expect(firstButton.right < zoomBounds.left && zoomBounds.right < lastButton.left).assertTrue();
          expect(Math.abs(zoomBounds.left + zoomBounds.right - toolbarBounds.left - toolbarBounds.right) <= 2).assertTrue();
          expect(Math.abs(zoomBounds.top + zoomBounds.bottom - firstButton.top - firstButton.bottom) <= 2).assertTrue();
          await capture('session-zoom-' + position);
        }
        await capture('session-zoom-panned');
        await (await driver.findComponent(ON.id('session.zoom.reset'))).click(); await settle();
        await absent('session.zoom.reset');
        expect(mock.attachCount).assertEqual(attachments);
        await mock.setViewOnly(true); await settle();
        const readOnlyCount = mock.sentInputs.length;
        await (await driver.findComponent(ON.id('session.gestures'))).pinchOut(2); await settle();
        await present('session.zoom.reset');
        await driver.swipe(x, y, x + 50, y, 600); await settle();
        expect(mock.sentInputs.length).assertEqual(readOnlyCount);
        await capture('session-zoom-read-only');
      } finally {
        await mock.setSmartReachEnabled(smartReach); await mock.setControlBarPosition(controlBarPosition);
        await mock.setMaterialPreference(materialPreference);
        await mock.setTouchMode(touchMode);
        await mock.disconnect(); await route('devices');
      }
    });
    it('menu_parent_click_returns_and_outside_click_closes_stack', 0, async () => {
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.emitFirstFrame(); await settle();
        await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
        const parent = await (await driver.findComponent(ON.id('session.more.input'))).getBounds();
        await menuClick('session.more.tools');
        await driver.click(Math.round((parent.left + parent.right) / 2), Math.round((parent.top + parent.bottom) / 2));
        await settle(); await present('session.action.menu'); await absent('session.action.menu.session.more.tools');
        await menuClick('session.more.input');
        const surface = await (await driver.findComponent(ON.id('session.surface'))).getBounds();
        const stack = await (await driver.findComponent(ON.id('session.menu.stack'))).getBounds();
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MENU_OUTSIDE ' + JSON.stringify({ surface: surface, stack: stack }) + '\n');
        await capture('menu-outside-before');
        const outsideX = stack.left - surface.left > surface.right - stack.right ?
          (surface.left + stack.left) / 2 : (stack.right + surface.right) / 2;
        expect(outsideX < stack.left || outsideX > stack.right).assertTrue();
        await driver.click(Math.round(outsideX), Math.round(surface.top + 80));
        await settle(); await capture('menu-outside-after'); await absent('session.action.menu');
      } finally { await mock.disconnect(); await route('devices'); }
    });
    it('navigation_indicator_hides_only_during_remote_session', 0, async () => {
      if (deviceInfo.deviceType === '2in1') { return; }
      const win = await window.getLastWindow(context);
      const orientation = win.getPreferredOrientation();
      const indicator = window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR;
      try {
        for (const sessionOrientation of [window.Orientation.USER_ROTATION_PORTRAIT, window.Orientation.USER_ROTATION_LANDSCAPE]) {
          await route('devices');
          await win.setPreferredOrientation(sessionOrientation); await settle();
          const originalHeight = win.getWindowAvoidArea(indicator).bottomRect.height;
          await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
          mock.emitFirstFrame(); await settle();
          const surface = await (await driver.findComponent(ON.id('session.surface'))).getBounds();
          const rect = win.getWindowProperties().windowRect;
          const hiddenHeight = win.getWindowAvoidArea(indicator).bottomRect.height;
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_NAVIGATION_VISIBILITY ' + JSON.stringify({
            orientation: sessionOrientation, originalHeight: originalHeight, hiddenHeight: hiddenHeight }) + '\n');
          expect(hiddenHeight).assertEqual(0);
          expect(Math.abs(surface.bottom - (rect.top + rect.height)) <= 1).assertTrue();
          const controls = await (await driver.findComponent(ON.id('session.controls'))).getBounds();
          const density = display.getDefaultDisplaySync().densityPixels;
          expect(Math.abs((surface.bottom - controls.bottom) / density - 16) <= 1).assertTrue();
          if (sessionOrientation === window.Orientation.USER_ROTATION_LANDSCAPE) {
            const inputs = mock.sentInputs.length;
            const snapshot = mock.sessionSnapshot();
            const fit = VideoViewport.fit(surface.right - surface.left, surface.bottom - surface.top,
              snapshot.videoWidth, snapshot.videoHeight);
            await capture('landscape-video-navigation-before-click');
            await driver.click(Math.round(surface.left + fit[0] + fit[2] * 0.05), Math.round(surface.top + fit[1] + fit[3] * 0.98));
            await settle();
            expect(mock.sentInputs.slice(inputs).some((item: string) => JSON.parse(item).action === 'touch_down')).assertTrue();
            await capture('landscape-video-navigation-safe');
          }
          await mock.disconnect(); await route('devices');
          expect(win.getWindowAvoidArea(indicator).bottomRect.height).assertEqual(originalHeight);
          await route('settings');
          expect(win.getWindowAvoidArea(indicator).bottomRect.height).assertEqual(originalHeight);
        }
      } finally { await mock.disconnect(); await route('devices'); await win.setPreferredOrientation(orientation); }
    });
    it('remote_picture_menu_expands_down_when_four_options_fit', 0, async () => {
      const win = await window.getLastWindow(context);
      const orientation = win.getPreferredOrientation();
      try {
        if (deviceInfo.deviceType !== '2in1') {
          await win.setPreferredOrientation(window.Orientation.USER_ROTATION_PORTRAIT); await settle();
        }
        await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
        mock.emitFirstFrame(); await settle();
        await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
        const ui = win.getUIContext();
        const canvas = UiProbe.measure(ui, ['session.menu.stack'])[0];
        const trigger = UiProbe.measure(ui, ['session.quality'])[0];
        const below = canvas.bounds[1] + canvas.bounds[3] - 16 - trigger.bounds[1] - trigger.bounds[3];
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MENU_SPACE ' + JSON.stringify({
          canvas: canvas.bounds, trigger: trigger.bounds, below: below, required: 232 }) + '\n');
        expect(below >= 232).assertTrue();
        const anchor = await menuAnchor();
        await menuClick('session.quality'); await capture('menu-remote-picture-direction');
        await present('session.menu.arrow.1.down');
        await stackMenuFits(anchor, 'session.action.menu.session.quality');
        await present('session.display.select'); await present('session.quality.select');
        await present('session.resolution.select'); await present('session.fps.select');
        await absent('session.color.select');
        await revealMenuItem('session.color.select'); await present('session.color.select');
        await capture('menu-remote-picture-fifth-option');
        await revealMenuItem('session.display.select'); await present('session.display.select');
        const quality = UiProbe.measure(ui, ['session.quality.select'])[0];
        const qualityBelow = canvas.bounds[1] + canvas.bounds[3] - 16 - quality.bounds[1] - quality.bounds[3];
        const required = ui.px2vp(Math.round(ui.vp2px(48))) * 4 + ui.px2vp(Math.round(ui.vp2px(8))) * 5;
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_QUALITY_MENU_SPACE ' + JSON.stringify({
          below: qualityBelow, required: required }) + '\n');
        expect(qualityBelow + 0.5 >= required).assertTrue();
        await menuClick('session.quality.select');
        await present('session.menu.arrow.2.down');
        await stackMenuFits(anchor, 'session.action.menu.session.quality.select');
        await capture('menu-quality-options-downward');
      } finally {
        await driver.pressBack(); await settle(); await driver.pressBack(); await settle();
        await mock.disconnect(); await route('devices'); await win.setPreferredOrientation(orientation);
      }
    });
    it('stacked_menus_keep_parent_layers_visible_and_scroll_options', 0, async () => {
      const win = await window.getLastWindow(context);
      const orientation = await win.getPreferredOrientation();
      const orientations = deviceInfo.deviceType === '2in1' ? [orientation] :
        [window.Orientation.USER_ROTATION_PORTRAIT, window.Orientation.USER_ROTATION_LANDSCAPE];
      try {
        for (let index = 0; index < orientations.length; index++) {
          await win.setPreferredOrientation(orientations[index]); await settle();
          await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
          mock.emitFirstFrame(); await settle();
          await buttonSpacing(['session.rotate', 'session.keyboard', 'session.pip']);
          await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
          const anchor = await menuAnchor();
          await capture('stack-' + index + '-root');
          await menuClick('session.more.input');
          await stackMenuFits(anchor, 'session.action.menu.session.more.input');
          await capture('stack-' + index + '-input');
          await driver.pressBack(); await settle();
          await menuClick('session.more.tools');
          await stackMenuFits(anchor, 'session.action.menu.session.more.tools');
          for (const id of ['session.more.files', 'session.more.terminal', 'session.more.portmap']) {
            await revealMenuItem(id); await present(id);
          }
          await capture('stack-' + index + '-tools');
          await driver.pressBack(); await settle();
          await menuClick('session.more.remote');
          await capture('stack-' + index + '-remote');
          await menuClick('session.more.shutdown');
          await (await driver.findComponent(ON.text('取消'))).click(); await settle();
          await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
          await menuClick('session.quality');
          await menuClick('session.resolution.select');
          await capture('stack-' + index + '-resolution');
          await menuClick('session.resolution.720p30');
          expect(mock.settings().defaultVideoProfile).assertEqual('720p30');
          await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
          await menuClick('session.quality');
          await menuClick('session.resolution.select');
          await revealMenuItem('session.resolution.720p30');
          expect(await (await driver.findComponent(ON.id('session.resolution.720p30'))).isSelected()).assertTrue();
          await driver.pressBack(); await settle();
          await present('session.action.menu.session.quality');
          await driver.pressBack(); await settle(); await present('session.action.menu');
          await driver.pressBack(); await settle(); await absent('session.action.menu');
          await mock.disconnect(); await route('devices');
        }
      } finally { await mock.disconnect(); await route('devices'); await win.setPreferredOrientation(orientation); }
    });
    it('virtual_mouse_material_and_drag_state_on_colored_background', 0, async () => {
      const ui = (await window.getLastWindow(context)).getUIContext();
      const prompt = ui.getPromptAction();
      const content = new ComponentContent(ui, wrapBuilder(virtualMouseMaterialSample));
      await prompt.openCustomDialog(content, { alignment: DialogAlignment.Center, maskColor: Color.Transparent });
      try {
        await settle();
        await (await driver.findComponent(ON.id('session.mouse.collapsed'))).click(); await settle();
        await capture('virtual-mouse-colored-background');
        const bounds = UiProbe.measure(ui, ['session.mouse.expanded', 'session.mouse.button.1', 'session.mouse.button.2', 'session.mouse.wheel', 'session.mouse.dragLock']);
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MOUSE_BOUNDS ' + JSON.stringify(bounds) + '\n');
        expect(bounds.length).assertEqual(5);
        expect(Math.abs(bounds[0].bounds[2] - 152) <= 1 && Math.abs(bounds[0].bounds[3] - 216) <= 1).assertTrue();
        expect(Math.abs(bounds[1].bounds[2] - bounds[2].bounds[2]) <= 1).assertTrue();
        for (const id of ['session.mouse.button.1', 'session.mouse.button.2', 'session.mouse.wheel',
          'session.mouse.dragLock', 'session.mouse.collapse']) {
          expect(await (await driver.findComponent(ON.id(id))).getText()).assertEqual('');
        }
        const dragKey = await driver.findComponent(ON.id('session.mouse.dragLock'));
        await buttonSpacing(['session.mouse.dragLock', 'session.mouse.collapse']);
        await dragKey.click(); await settle(); expect(await dragKey.isSelected()).assertTrue();
        await capture('virtual-mouse-colored-drag-active');
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MOUSE_BOUNDS ' + JSON.stringify(bounds) + '\n');
      } finally { await prompt.closeCustomDialog(content); content.dispose(); }
    });
    it('floating_control_material_on_colored_background', 0, async () => {
      const ui = (await window.getLastWindow(context)).getUIContext();
      const prompt = ui.getPromptAction();
      for (const background of ['#FFFFFF', '#16191F', 'split', 'color']) {
        const content = new ComponentContent(ui, wrapBuilder(controlMaterialSample), background);
        await prompt.openCustomDialog(content, { alignment: DialogAlignment.Center, maskColor: Color.Transparent });
        try {
        await settle();
        const ids: string[] = ['material.controls'];
        for (const theme of ['light', 'dark']) {
          for (const icon of ['back', 'keyboard', 'rotate', 'more', 'mouse']) {
            const id = 'material.control.' + theme + '.' + icon;
            await roundControl(id);
            const iconAttrs = (JSON.parse(getInspectorByKey('material.icon.' + theme + '.' + icon)) as ScrollBarInspector).$attrs;
            await abilityDelegatorRegistry.getAbilityDelegator().print('UU_ICON_FOREGROUND ' + JSON.stringify({
              id: id, blendMode: iconAttrs?.['blendMode'], fillColor: iconAttrs?.['fillColor'] }) + '\n');
            expect(Number(iconAttrs?.['blendMode'])).assertEqual(BlendMode.NONE);
            const color = String(iconAttrs?.['fillColor']).toUpperCase();
            expect(/^#[0-9A-F]{2}(000000|FFFFFF)$/.test(color)).assertTrue();
            expect(Number.parseInt(color.slice(1, 3), 16) >= 0xCC).assertTrue();
            ids.push(id);
            await checkFloatingControlMaterial(id, '#B31C1D20');
          }
        }
        await capture('controls-material-' + background.replace('#', ''));
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_CONTROL_MATERIAL_BOUNDS ' +
          JSON.stringify(UiProbe.measure(ui, ids)) + '\n');
        } finally { await prompt.closeCustomDialog(content); content.dispose(); }
      }
    });
    it('stacked_menu_material_keeps_colored_background_visible', 0, async () => {
      const ui = (await window.getLastWindow(context)).getUIContext();
      const content = new ComponentContent(ui, wrapBuilder(menuMaterialSample));
      const prompt = ui.getPromptAction();
      await prompt.openCustomDialog(content, { alignment: DialogAlignment.Center, maskColor: Color.Transparent });
      try {
        await settle(); await present('material.probe.parent'); await present('material.probe.child');
        for (const id of ['material.probe.parent', 'material.probe.child']) {
          const attrs = (JSON.parse(getInspectorByKey(id)) as ScrollBarInspector).$attrs;
          const effect: string = JSON.stringify(attrs?.['backgroundEffect']);
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MENU_MATERIAL ' + JSON.stringify({
            id: id, effect: attrs?.['backgroundEffect'], material: attrs?.['systemMaterial'] }) + '\n');
          expect(effect.includes('"radius":40') && effect.includes('#A61C1D20')).assertTrue();
        }
        await capture('menu-material-colored-background');
        const bounds = UiProbe.measure(ui, ['material.probe', 'material.probe.parent', 'material.probe.child']);
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MENU_MATERIAL_BOUNDS ' + JSON.stringify(bounds) + '\n');
        expect(bounds.length).assertEqual(3);
      } finally { await prompt.closeCustomDialog(content); content.dispose(); }
    });
    it('menu_text_roles_remain_clear_on_light_and_dark_backgrounds', 0, async () => {
      const ui = (await window.getLastWindow(context)).getUIContext();
      const prompt = ui.getPromptAction();
      for (const background of ['#FFFFFF', '#111111', 'mixed']) {
        const content = new ComponentContent(ui, wrapBuilder(menuContrastSample), background);
        await prompt.openCustomDialog(content, { alignment: DialogAlignment.Center, maskColor: Color.Transparent });
        try {
          await settle();
          const ids = ['contrast.sample', 'contrast.menu', 'contrast.title', 'contrast.label', 'contrast.value',
            'contrast.selected', 'contrast.check', 'contrast.disabled', 'contrast.destructive'];
          const roles: MenuColorRole[] = [];
          for (const id of ids.slice(2)) {
            await present(id);
            const attrs = (JSON.parse(getInspectorByKey(id)) as ScrollBarInspector).$attrs;
            const color = attrs?.[id === 'contrast.check' ? 'fillColor' : 'fontColor'];
            expect(color !== undefined && color.length > 0).assertTrue();
            roles.push({ id: id, color: color ?? '' });
          }
          expect(roles[0].color).assertEqual(roles[1].color);
          expect(roles[0].color).assertEqual(roles[3].color);
          expect(roles[0].color.toUpperCase().slice(-6)).assertEqual('FFFFFF');
          expect(roles[4].color.toUpperCase().slice(-6)).assertEqual('FFFFFF');
          expect(roles[0].color === roles[6].color).assertFalse();
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MENU_CONTRAST ' + JSON.stringify({
            background: background, roles: roles, bounds: UiProbe.measure(ui, ids) }) + '\n');
          await capture('menu-contrast-' + (background === '#FFFFFF' ? 'light' : background === 'mixed' ? 'mixed' : 'dark'));
        } finally { await prompt.closeCustomDialog(content); content.dispose(); }
      }
    });
    it('general_material_preference_uses_supported_hds_levels', 0, async () => {
      const original = mock.settings().materialPreference;
      try {
        await route('settings');
        await (await driver.findComponent(ON.id('settings.general'))).click(); await settle();
        await inlineSelect('settings.material');
        await (await driver.findComponent(ON.id('settings.material'))).click(); await settle();
        await (await driver.findComponent(ON.text('柔和'))).click(); await settle();
        await selectedValue('settings.material', '柔和');
        expect(mock.settings().materialPreference).assertEqual('gentle');
        expect(AppStorage.get<hdsMaterial.MaterialLevel>('hdsMaterialLevel')).assertEqual(
          hdsMaterial.getSystemMaterialTypes().includes(hdsMaterial.MaterialType.IMMERSIVE)
            ? hdsMaterial.MaterialLevel.GENTLE : hdsMaterial.MaterialLevel.SMOOTH);
        await capture('settings-material-gentle');
        await (await driver.findComponent(ON.id('settings.material'))).click(); await settle();
        const systemOptions = await driver.findComponents(ON.text('跟随系统'));
        expect((systemOptions?.length ?? 0) >= 2).assertTrue();
        await systemOptions![systemOptions!.length - 1].click(); await settle();
        await selectedValue('settings.material', '跟随系统');
        expect(mock.settings().materialPreference).assertEqual('system');
      } finally { await mock.setMaterialPreference(original); await route('devices'); }
    });
    it('device_refresh_uses_material_and_card_more_has_no_outline', 0, async () => {
      try {
        await route('devices'); await mock.listDevices(); await settle();
        await roundControl('devices.refresh');
        await checkFloatingControlMaterial('devices.refresh', '#33FFFFFF', true);
        await scrollToId('devices.grid', 'device.demo-win-01.more');
        await roundControl('device.demo-win-01.more');
        const moreStyle = (JSON.parse(getInspectorByKey('device.demo-win-01.more')) as ScrollBarInspector).$attrs;
        expect(moreStyle?.['backgroundColor']).assertEqual('#00000000');
        expect(moreStyle?.['outlineWidth']).assertEqual('0.00vp');
        expect(JSON.stringify(moreStyle?.['backgroundEffect'] ?? '').includes('"radius":12')).assertFalse();
      } finally { await route('devices'); }
    });
    it('remote_floating_controls_keep_round_shapes_and_enabled_actions', 0, async () => {
      const originalMaterial = mock.settings().materialPreference;
      await mock.setMaterialPreference('exquisite');
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.emitFirstFrame(); await settle();
        const controls = ['session.back', 'session.keyboard', 'session.rotate', 'session.more'];
        const nativeMaterial = deviceInfo.apiAvailable('26.0.0') && uiMaterial.isImmersiveMaterialSupported();
        for (const id of ['session.keyboard.icon', 'session.rotate.icon', 'session.pip.icon', 'session.more.icon',
          'session.mouse.icon']) {
          const attrs = (JSON.parse(getInspectorByKey(id)) as ScrollBarInspector).$attrs;
          expect(String(attrs?.['draggable'] ?? '')).assertEqual('false');
        }
        const density = display.getDefaultDisplaySync().densityPixels;
        for (const id of controls) {
          await roundControl(id); await standardIcon(id);
          const bounds = await (await driver.findComponent(ON.id(id))).getBounds();
          expect(Math.abs((bounds.right - bounds.left) / density - 48) < 1).assertTrue();
          expect(await (await driver.findComponent(ON.id(id))).isEnabled())
            .assertEqual(id !== 'session.rotate' || deviceInfo.deviceType !== '2in1');
          const attrs = (JSON.parse(getInspectorByKey(id)) as ScrollBarInspector).$attrs;
          expect(attrs?.['type']).assertEqual('ButtonType.Circle');
          if (!nativeMaterial) {
            await checkFloatingControlMaterial(id === 'session.back' ? 'session.header.capsule' : id, '#B31C1D20');
          }
        }
        if (nativeMaterial) {
          const ui = (await window.getLastWindow(context)).getUIContext();
          const surfaces = ['session.header.capsule', 'session.keyboard', 'session.rotate', 'session.more',
            'session.pip', 'session.mouse.collapsed'];
          for (const preference of ['exquisite', 'gentle', 'exquisite'] as MaterialPreference[]) {
            await mock.setMaterialPreference(preference); await settle();
            for (const id of surfaces) {
              const plateId = id === 'session.mouse.collapsed' ? 'session.mouse.material' : id + '.material';
              const inspector = getInspectorByKey(plateId);
              if (!inspector) { throw new Error('Missing native material: ' + plateId); }
              const attrs = (JSON.parse(inspector) as ScrollBarInspector).$attrs;
              const material = JSON.stringify(attrs?.['systemMaterial'] ?? '');
              expect(material.includes('MaterialType.IMMERSIVE') &&
                material.includes(preference === 'exquisite' ? 'ImmersiveStyle.THIN' : 'ImmersiveStyle.REGULAR')).assertTrue();
              const bounds = UiProbe.measure(ui, [id, plateId]);
              expect(bounds[1].matchCount).assertEqual(1);
              for (let index = 0; index < 4; index++) {
                expect(Math.abs(bounds[0].bounds[index] - bounds[1].bounds[index]) <= 1).assertTrue();
              }
            }
          }
          await (await driver.findComponent(ON.id('session.mouse.collapsed'))).click(); await settle();
          const plate = (JSON.parse(getInspectorByKey('session.mouse.expanded.material')) as ScrollBarInspector).$attrs;
          expect(JSON.stringify(plate?.['systemMaterial'] ?? '').includes('ImmersiveStyle.THIN')).assertTrue();
          await (await driver.findComponent(ON.id('session.mouse.collapse'))).click(); await settle();
        }
        if (deviceInfo.apiAvailable('26.0.0')) {
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_REMOTE_MATERIAL ' + JSON.stringify({
            supported: uiMaterial.isImmersiveMaterialSupported(), info: uiMaterial.getMaterialInfo(),
            level: uiMaterial.getGlobalMaterialLevel() }) + '\n');
        }
        if (deviceInfo.deviceType !== '2in1') {
          const keyboardAttrs = (JSON.parse(getInspectorByKey('session.keyboard.icon')) as ScrollBarInspector).$attrs;
          const rotateAttrs = (JSON.parse(getInspectorByKey('session.rotate.icon')) as ScrollBarInspector).$attrs;
          expect(rotateAttrs?.['fillColor'] !== undefined).assertTrue();
          expect(rotateAttrs?.['fillColor']).assertEqual(keyboardAttrs?.['fillColor']);
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_ROTATE_ICON ' + JSON.stringify({
            enabled: await (await driver.findComponent(ON.id('session.rotate'))).isEnabled(),
            keyboardColor: keyboardAttrs?.['fillColor'], rotateColor: rotateAttrs?.['fillColor'],
            keyboardOpacity: keyboardAttrs?.['opacity'], rotateOpacity: rotateAttrs?.['opacity'],
            rotateEnabled: rotateAttrs?.['enabled'], rotateSrc: rotateAttrs?.['src'],
            rotateColorFilter: rotateAttrs?.['colorFilter'], rotateForeground: rotateAttrs?.['foregroundColor'],
            bounds: UiProbe.measure((await window.getLastWindow(context)).getUIContext(),
              ['session.keyboard.icon', 'session.rotate.icon']) }) + '\n');
          expect(rotateAttrs?.['opacity']).assertEqual(keyboardAttrs?.['opacity']);
        }
        await capture('session-native-floating-controls');
        if (nativeMaterial) {
          const more = await (await driver.findComponent(ON.id('session.more'))).getBounds();
          await feedbackFrame('remote-more-idle');
          const pressing = driver.longClick(Math.round((more.left + more.right) / 2),
            Math.round((more.top + more.bottom) / 2));
          try {
            await new Promise<void>((resolve) => { setTimeout(resolve, 120); });
            await feedbackFrame('remote-more-press-start');
            await new Promise<void>((resolve) => { setTimeout(resolve, 120); });
            await feedbackFrame('remote-more-pressed');
          } finally { await pressing; }
          await settle();
          if ((await driver.findComponents(ON.id('session.action.menu')))?.length > 0) {
            await driver.pressBack(); await settle();
          }
          await feedbackFrame('remote-more-released');
        }
        await (await driver.findComponent(ON.id('session.keyboard'))).click(); await settle();
        await present('session.text.input');
        const send = await driver.findComponent(ON.id('session.text.send'));
        expect(await send.isEnabled()).assertFalse();
        const sendAttrs = (JSON.parse(getInspectorByKey('session.text.send')) as ScrollBarInspector).$attrs;
        const closeAttrs = (JSON.parse(getInspectorByKey('session.text.close')) as ScrollBarInspector).$attrs;
        expect(JSON.stringify(sendAttrs?.['backgroundEffect'])).assertEqual(JSON.stringify(closeAttrs?.['backgroundEffect']));
        expect(JSON.stringify(sendAttrs?.['systemMaterial'] ?? '')).assertEqual(JSON.stringify(closeAttrs?.['systemMaterial'] ?? ''));
        await (await driver.findComponent(ON.id('session.text.input'))).inputText('send material', { paste: true, addition: false });
        await settle(); expect(await send.isEnabled()).assertTrue();
        await capture('session-send-unified-material');
        await (await driver.findComponent(ON.id('session.text.close'))).click(); await settle();
        await mock.setViewOnly(true); await settle();
        expect(await (await driver.findComponent(ON.id('session.keyboard'))).isEnabled()).assertFalse();
        expect(await (await driver.findComponent(ON.id('session.more'))).isEnabled()).assertTrue();
        await capture('session-native-floating-controls-disabled');
        await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
        await present('session.action.menu'); await capture('session-native-menu');
        if (nativeMaterial) {
          const item = await (await driver.findComponent(ON.id('session.more.input'))).getBounds();
          await feedbackFrame('remote-menu-idle');
          const pressing = driver.longClick(Math.round((item.left + item.right) / 2),
            Math.round((item.top + item.bottom) / 2));
          try {
            await new Promise<void>((resolve) => { setTimeout(resolve, 240); });
            await feedbackFrame('remote-menu-pressed');
          } finally { await pressing; }
          await settle();
          if ((await driver.findComponents(ON.id('session.action.menu.session.more.input')))?.length > 0) {
            await driver.pressBack(); await settle();
          }
          await feedbackFrame('remote-menu-released');
        }
        await driver.pressBack(); await settle();
        await (await driver.findComponent(ON.id('session.back'))).click(); await settle();
        await (await driver.findComponent(ON.text('继续连接'))).click(); await settle();
        await present('session.toolbar');
      } finally { await mock.setMaterialPreference(originalMaterial); await mock.disconnect(); await route('devices'); }
    });
    it('remote_keyboard_computer_and_shortcuts_send_balanced_key_chords', 0, async () => {
      const original = mock.settings().materialPreference;
      await mock.setMaterialPreference('exquisite');
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.emitFirstFrame(); await settle();
        await (await driver.findComponent(ON.id('session.keyboard'))).click(); await settle();
        await present('session.text.input');
        const nativeMaterial = deviceInfo.apiAvailable('26.0.0') && uiMaterial.isImmersiveMaterialSupported();
        if (nativeMaterial) {
          const ui = (await window.getLastWindow(context)).getUIContext();
          for (const mode of ['text', 'computer', 'shortcuts']) {
            const id = 'session.keyboard.mode.' + mode;
            const material = (JSON.parse(getInspectorByKey(id + '.material')) as ScrollBarInspector).$attrs;
            expect(JSON.stringify(material?.['systemMaterial'] ?? '').includes('ImmersiveStyle.THIN')).assertTrue();
            const bounds = UiProbe.measure(ui, [id, id + '.material']);
            expect(Math.abs(bounds[0].bounds[2] - bounds[1].bounds[2]) <= 1).assertTrue();
            expect(Math.abs(bounds[0].bounds[3] - bounds[1].bounds[3]) <= 1).assertTrue();
          }
        }
        await (await driver.findComponent(ON.id('session.keyboard.mode.computer'))).click(); await settle();
        await present('session.keyboard.computer');
        const ui = (await window.getLastWindow(context)).getUIContext();
        const geometry = UiProbe.measure(ui, ['session.page', 'session.keyboard.computer']);
        expect(Math.abs(geometry[0].bounds[2] - geometry[1].bounds[2] - 32) <= 1).assertTrue();
        if (nativeMaterial) {
          const frame = (JSON.parse(getInspectorByKey('session.keyboard.material')) as ScrollBarInspector).$attrs;
          expect(JSON.stringify(frame?.['systemMaterial'] ?? '').includes('ImmersiveStyle.THIN')).assertTrue();
          const bounds = UiProbe.measure(ui, ['session.keyboard.material'])[0].bounds;
          expect(Math.abs(geometry[1].bounds[2] - bounds[2]) <= 1 && Math.abs(geometry[1].bounds[3] - bounds[3]) <= 1).assertTrue();
        }
        await capture('session-computer-keyboard');
        let count = mock.sentInputs.length;
        const keys = (start: number): string => mock.sentInputs.slice(start)
          .map((value: string): Record<string, string | number | boolean> => JSON.parse(value))
          .filter((event: Record<string, string | number | boolean>) => event['action'] === 'key')
          .map((event: Record<string, string | number | boolean>) =>
            String(event['scan']) + ':' + (event['down'] === true ? 'down' : 'up')).join(',');
        await (await driver.findComponent(ON.id('session.keyboard.key.42'))).click(); await settle();
        expect(keys(count)).assertEqual('42:down,42:up');
        count = mock.sentInputs.length;
        await (await driver.findComponent(ON.id('session.keyboard.key.224'))).click();
        await (await driver.findComponent(ON.id('session.keyboard.key.4'))).click(); await settle();
        expect(keys(count)).assertEqual('224:down,4:down,4:up,224:up');
        count = mock.sentInputs.length;
        await (await driver.findComponent(ON.id('session.keyboard.key.4'))).click(); await settle();
        expect(keys(count)).assertEqual('4:down,4:up');
        if (geometry[1].bounds[2] < 600) {
          const pages = await (await driver.findComponent(ON.id('session.keyboard.computer.pages'))).getBounds();
          const y = Math.round((pages.top + pages.bottom) / 2);
          count = mock.sentInputs.length;
          await driver.swipe(Math.round(pages.right - (pages.right - pages.left) * 0.15), y,
            Math.round(pages.left + (pages.right - pages.left) * 0.15), y, 900); await settle();
          expect(keys(count)).assertEqual('');
          await present('session.keyboard.computer.page.extra');
          await capture('session-computer-keyboard-extra');
        }
        count = mock.sentInputs.length;
        await (await driver.findComponent(ON.id('session.keyboard.key.58'))).click(); await settle();
        expect(keys(count)).assertEqual('58:down,58:up');
        await (await driver.findComponent(ON.id('session.keyboard.mode.shortcuts'))).click(); await settle();
        await present('session.keyboard.shortcuts');
        await capture('session-keyboard-shortcuts');
        count = mock.sentInputs.length;
        await (await driver.findComponent(ON.id('session.keyboard.shortcut.copy'))).click(); await settle();
        expect(keys(count)).assertEqual('224:down,6:down,6:up,224:up');
        await (await driver.findComponent(ON.id('session.keyboard.mode.text'))).click(); await settle();
        await present('session.text.input');
        await (await driver.findComponent(ON.id('session.text.close'))).click(); await settle();
        await absent('session.text.input');
      } finally { await mock.setMaterialPreference(original); await mock.disconnect(); await route('devices'); }
    });
    it('computer_keyboard_shifts_video_at_original_size_and_hides_bottom_controls', 0, async () => {
      const win = await window.getLastWindow(context);
      const orientation = win.getPreferredOrientation();
      const originalTouch = mock.settings().touchMode;
      const ui = win.getUIContext();
      const controls = ['session.rotate', 'session.keyboard', 'session.pip'];
      const measure = (id: string): number[] => UiProbe.measure(ui, [id])[0].bounds;
      const logKeyboardLayout = async (step: string): Promise<void> => {
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_KEYBOARD_LAYOUT ' + JSON.stringify({ step: step,
          geometry: UiProbe.measure(ui, controls.concat(controls.map((id: string) => id + '.icon'),
            ['session.video', 'session.surface', 'session.keyboard.panel'])) }) + '\n');
      };
      const checkToolbar = (size: number, iconSize: number): void => {
        let right = 0;
        for (const id of controls) {
          const bounds = measure(id);
          const icon = measure(id + '.icon');
          expect(Math.abs(bounds[2] - size) <= 1 && Math.abs(bounds[3] - size) <= 1).assertTrue();
          expect(Math.abs(icon[2] - iconSize) <= 1 && Math.abs(icon[3] - iconSize) <= 1).assertTrue();
          expect(Math.abs(icon[0] + icon[2] / 2 - bounds[0] - bounds[2] / 2) <= 1 &&
            Math.abs(icon[1] + icon[3] / 2 - bounds[1] - bounds[3] / 2) <= 1).assertTrue();
          if (right > 0) { expect(Math.abs(bounds[0] - right - 8) <= 1).assertTrue(); }
          right = bounds[0] + bounds[2];
        }
      };
      try {
        if (deviceInfo.deviceType !== '2in1') {
          await win.setPreferredOrientation(window.Orientation.USER_ROTATION_LANDSCAPE); await settle();
        }
        await mock.setTouchMode('direct');
        await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
        mock.emitFirstFrame(); await settle();
        checkToolbar(48, 24);
        const original = measure('session.video');
        await (await driver.findComponent(ON.id('session.keyboard'))).click(); await settle();
        await present('session.text.input');
        await logKeyboardLayout('text');
        await absent('session.toolbar');
        if (measure('session.surface')[3] < 192) { await driver.pressBack(); await settle(); }
        await (await driver.findComponent(ON.id('session.keyboard.mode.computer'))).click(); await settle();
        await present('session.keyboard.computer');
        await absent('session.toolbar');
        await logKeyboardLayout('computer');
        const video = measure('session.video');
        const panel = measure('session.keyboard.panel');
        const surface = measure('session.surface');
        const overlap = Math.max(0, original[1] + original[3] - panel[1]);
        expect(overlap).assertLarger(1);
        expect(Math.abs(video[0] - original[0]) <= 1 && Math.abs(video[1] - original[1] + overlap) <= 1 &&
          Math.abs(video[2] - original[2]) <= 1 && Math.abs(video[3] - original[3]) <= 1).assertTrue();
        const keyboard = measure('session.keyboard.computer');
        if (keyboard[2] >= 600) {
          const lastRow = measure('session.keyboard.key.73');
          expect(lastRow[3] > 0 && lastRow[1] + lastRow[3] <= keyboard[1] + keyboard[3] + 1).assertTrue();
        }
        await feedbackFrame('computer-keyboard-shift-and-hidden-controls');
        const x = video[0] + video[2] * 0.22;
        const y = panel[1] - 8;
        const screen = await (await driver.findComponent(ON.id('session.surface'))).getBounds();
        const start = mock.sentInputs.length;
        await driver.click(Math.round(screen.left + ui.vp2px(x - surface[0])),
          Math.round(screen.top + ui.vp2px(y - surface[1]))); await settle();
        const down = mock.sentInputs.slice(start).map((input: string): Record<string, string | number> => JSON.parse(input))
          .find((input: Record<string, string | number>) => input['action'] === 'touch_down');
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_KEYBOARD_TOUCH ' + JSON.stringify({
          target: [x, y], video: video, surface: surface, input: down }) + '\n');
        expect(down !== undefined && Math.abs(Number(down['abs_x']) - (x - video[0]) / video[2]) <= 0.01 &&
          Math.abs(Number(down['abs_y']) - (y - video[1]) / video[3]) <= 0.01).assertTrue();
        await (await driver.findComponent(ON.id('session.keyboard.mode.shortcuts'))).click(); await settle();
        await absent('session.toolbar');
        expect(Math.abs(measure('session.video')[1] - original[1]) <= 1).assertTrue();
        await (await driver.findComponent(ON.id('session.keyboard.close'))).click(); await settle();
        await absent('session.keyboard.panel');
        checkToolbar(48, 24);
        expect(Math.abs(measure('session.video')[1] - original[1]) <= 1).assertTrue();
      } finally {
        await mock.setTouchMode(originalTouch); await mock.disconnect(); await route('devices');
        if (deviceInfo.deviceType !== '2in1') { await win.setPreferredOrientation(orientation); await settle(); }
      }
    });
    it('remote_keyboard_shortcut_edit_page_adds_edits_and_deletes_persisted_chords', 0, async () => {
      const store = await preferences.getPreferences(context, 'uu_remote_settings');
      const pref = 'remoteKeyboardShortcuts';
      const hadPreference = await store.has(pref);
      const previous = await store.get(pref, '[]');
      const hiddenPref = 'remoteKeyboardHiddenShortcuts';
      const hadHidden = await store.has(hiddenPref);
      const previousHidden = await store.get(hiddenPref, '[]');
      const stored = JSON.parse(typeof previous === 'string' ? previous : '[]') as KeyCode[][];
      const candidates = [KeyCode.KEYCODE_B, KeyCode.KEYCODE_C, KeyCode.KEYCODE_D,
        KeyCode.KEYCODE_E, KeyCode.KEYCODE_F, KeyCode.KEYCODE_G];
      const free = candidates.map((code: KeyCode, index: number): number => index)
        .filter((index: number) => !stored.some((chord: KeyCode[]) => chord.length === 4 &&
          chord.includes(KeyCode.KEYCODE_CTRL_LEFT) && chord.includes(KeyCode.KEYCODE_SHIFT_LEFT) &&
          chord.includes(KeyCode.KEYCODE_A) && chord.includes(candidates[index])));
      expect(free.length).assertLarger(1);
      const addedScan = 5 + free[0];
      const editedScan = 5 + free[1];
      const addedId = 'custom-224-225-4-' + addedScan;
      const editedId = 'custom-224-225-4-' + editedScan;
      try {
        await store.put(hiddenPref, '[]'); await store.flush();
        await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
        mock.emitFirstFrame(); await settle();
        const keyboard = await driver.waitForComponent(ON.id('session.keyboard'), 3000);
        if (!keyboard) { throw new Error('Session keyboard entry did not appear'); }
        expect(await keyboard.isEnabled()).assertTrue();
        await keyboard.click(); await settle();
        const shortcuts = await driver.waitForComponent(ON.id('session.keyboard.mode.shortcuts'), 3000);
        if (!shortcuts) {
          await capture('session-keyboard-shortcut-entry-missing');
          throw new Error('Shortcut mode did not appear after opening the keyboard');
        }
        await shortcuts.click(); await settle();
        await absent('session.keyboard.shortcut.add');
        await (await driver.findComponent(ON.id('session.keyboard.shortcut.edit'))).click(); await settle();
        await present('session.keyboard.shortcut.edit-list');
        await present('session.keyboard.shortcut.delete.copy');
        const editUi = (await window.getLastWindow(context)).getUIContext();
        const editBounds = UiProbe.measure(editUi, ['session.keyboard.shortcut.add',
          'session.keyboard.shortcut.done', 'session.keyboard.shortcut.delete.copy']);
        const add = editBounds[0].bounds;
        const done = editBounds[1].bounds;
        expect(Math.abs(add[1] + add[3] / 2 - done[1] - done[3] / 2) <= 1).assertTrue();
        expect(editBounds[2].bounds[1] - Math.max(add[1] + add[3], done[1] + done[3]) <= 12).assertTrue();
        await (await driver.findComponent(ON.id('session.keyboard.shortcut.add'))).click(); await settle();
        const picking = mock.sentInputs.length;
        for (const scan of [224, 225, 4, addedScan]) {
          await (await driver.findComponent(ON.id('session.keyboard.shortcut.pick.' + scan))).click();
        }
        await settle();
        for (const scan of [224, 225, 4, addedScan]) {
          expect(await (await driver.findComponent(ON.id('session.keyboard.shortcut.pick.' + scan))).isSelected()).assertTrue();
        }
        const preview = await driver.findComponent(ON.id('session.keyboard.shortcut.preview'));
        expect(await preview.getText()).assertEqual('Ctrl+Shift+A+' + String.fromCharCode(66 + free[0]));
        expect(mock.sentInputs.length).assertEqual(picking);
        await feedbackFrame('session-keyboard-shortcut-picker');
        await (await driver.findComponent(ON.id('session.keyboard.shortcut.save'))).click(); await settle();
        await present('session.keyboard.shortcut.delete.' + addedId);
        await feedbackFrame('session-keyboard-shortcut-editor');
        const beforeEdit = mock.sentInputs.length;
        await (await driver.findComponent(ON.id('session.keyboard.shortcut.edit.' + addedId))).click(); await settle();
        expect(mock.sentInputs.length).assertEqual(beforeEdit);
        await (await driver.findComponent(ON.id('session.keyboard.shortcut.pick.' + addedScan))).click();
        await (await driver.findComponent(ON.id('session.keyboard.shortcut.pick.' + editedScan))).click(); await settle();
        expect(await (await driver.findComponent(ON.id('session.keyboard.shortcut.pick.' + addedScan))).isSelected()).assertFalse();
        expect(await (await driver.findComponent(ON.id('session.keyboard.shortcut.pick.' + editedScan))).isSelected()).assertTrue();
        await (await driver.findComponent(ON.id('session.keyboard.shortcut.save'))).click(); await settle();
        await absent('session.keyboard.shortcut.delete.' + addedId);
        await present('session.keyboard.shortcut.delete.' + editedId);
        await (await driver.findComponent(ON.id('session.keyboard.shortcut.done'))).click(); await settle();
        await present('session.keyboard.shortcut.' + editedId);
        const saved = await store.get(pref, '[]');
        const savedChords = JSON.parse(typeof saved === 'string' ? saved : '[]') as KeyCode[][];
        expect(savedChords.some((chord: KeyCode[]) => chord.length === 4 && chord[0] === KeyCode.KEYCODE_CTRL_LEFT &&
          chord[1] === KeyCode.KEYCODE_SHIFT_LEFT && chord[2] === KeyCode.KEYCODE_A && chord[3] === candidates[free[1]])).assertTrue();
        await (await driver.findComponent(ON.id('session.keyboard.mode.text'))).click(); await settle();
        await (await driver.findComponent(ON.id('session.keyboard.mode.shortcuts'))).click(); await settle();
        await present('session.keyboard.shortcut.' + editedId);
        const start = mock.sentInputs.length;
        await (await driver.findComponent(ON.id('session.keyboard.shortcut.' + editedId))).click(); await settle();
        const keys = mock.sentInputs.slice(start).map((value: string): Record<string, string | number | boolean> => JSON.parse(value))
          .filter((event: Record<string, string | number | boolean>) => event['action'] === 'key')
          .map((event: Record<string, string | number | boolean>) =>
            String(event['scan']) + ':' + (event['down'] === true ? 'down' : 'up')).join(',');
        expect(keys).assertEqual('224:down,225:down,4:down,' + editedScan + ':down,' + editedScan + ':up,4:up,225:up,224:up');
        await (await driver.findComponent(ON.id('session.keyboard.shortcut.edit'))).click(); await settle();
        await (await driver.findComponent(ON.id('session.keyboard.shortcut.delete.' + editedId))).click(); await settle();
        await absent('session.keyboard.shortcut.delete.' + editedId);
        await (await driver.findComponent(ON.id('session.keyboard.shortcut.delete.copy'))).click(); await settle();
        await absent('session.keyboard.shortcut.delete.copy');
        await (await driver.findComponent(ON.id('session.keyboard.shortcut.done'))).click(); await settle();
        await absent('session.keyboard.shortcut.' + editedId);
        await absent('session.keyboard.shortcut.copy');
        expect(await store.get(hiddenPref, '[]')).assertEqual('["copy:224-6"]');
        const updated = await store.get(pref, '[]');
        const chords = JSON.parse(typeof updated === 'string' ? updated : '[]') as KeyCode[][];
        expect(chords.some((chord: KeyCode[]) => chord.length === 4 && chord[0] === KeyCode.KEYCODE_CTRL_LEFT &&
          chord[1] === KeyCode.KEYCODE_SHIFT_LEFT && chord[2] === KeyCode.KEYCODE_A && chord[3] === candidates[free[1]])).assertFalse();
      } finally {
        await mock.disconnect(); await route('devices');
        if (hadPreference) { await store.put(pref, previous); }
        else { await store.delete(pref); }
        if (hadHidden) { await store.put(hiddenPref, previousHidden); }
        else { await store.delete(hiddenPref); }
        await store.flush();
      }
    });
    it('remote_more_drag_keeps_actions_idle_and_network_panel_uses_current_material', 0, async () => {
      const original = mock.settings().materialPreference;
      await mock.setMaterialPreference('exquisite');
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.emitFirstFrame(); await settle();
        const ui = (await window.getLastWindow(context)).getUIContext();
        const headerIds = ['session.header.capsule', 'session.back', 'session.more'];
        const collapsed = UiProbe.measure(ui, headerIds);
        await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
        const first = await (await driver.findComponent(ON.id('session.more.input'))).getBounds();
        const third = await (await driver.findComponent(ON.id('session.more.tools'))).getBounds();
        const x = Math.round((first.left + first.right) / 2);
        const y0 = Math.round((first.top + first.bottom) / 2);
        const y1 = Math.round((third.top + third.bottom) / 2);
        const duration = Math.abs(y1 - y0) * 5;
        const drag = driver.swipe(x, y0, x, y1, 200);
        try {
          await new Promise<void>((resolve) => { setTimeout(resolve, Math.round(duration * 0.12)); });
          await feedbackFrame('remote-menu-slide-start');
          await new Promise<void>((resolve) => { setTimeout(resolve, Math.round(duration * 0.42)); });
          await feedbackFrame('remote-menu-slide-move');
        } finally { await drag; }
        await settle();
        await present('session.action.menu');
        await absent('session.action.menu.session.more.input');
        await absent('session.action.menu.session.more.tools');
        await menuClick('session.more.stats');
        await present('session.network.stats');
        const opened = UiProbe.measure(ui, headerIds.concat('session.network.stats'));
        for (let index = 0; index < 3; index++) {
          expect(Math.abs(opened[0].bounds[index] - collapsed[0].bounds[index]) <= 1).assertTrue();
        }
        expect(opened[0].bounds[3]).assertLarger(collapsed[0].bounds[3]);
        expect(opened[3].bounds[1] >= opened[0].bounds[1] + collapsed[0].bounds[3] - 1).assertTrue();
        expect(opened[3].bounds[1] + opened[3].bounds[3] <= opened[0].bounds[1] + opened[0].bounds[3] + 1).assertTrue();
        for (let component = 1; component < 3; component++) {
          for (let index = 0; index < 4; index++) {
            expect(Math.abs(opened[component].bounds[index] - collapsed[component].bounds[index]) <= 1).assertTrue();
          }
        }
        if (deviceInfo.apiAvailable('26.0.0') && uiMaterial.isImmersiveMaterialSupported()) {
          const attrs = (JSON.parse(getInspectorByKey('session.header.capsule.material')) as ScrollBarInspector).$attrs;
          expect(JSON.stringify(attrs?.['systemMaterial'] ?? '').includes('ImmersiveStyle.THIN')).assertTrue();
          const material = UiProbe.measure(ui, ['session.header.capsule.material'])[0].bounds;
          for (let index = 0; index < 4; index++) {
            expect(Math.abs(opened[0].bounds[index] - material[index]) <= 1).assertTrue();
          }
        }
        await capture('session-network-stats-material');
        await (await driver.findComponent(ON.id('session.more'))).click(); await settle();
        await menuClick('session.more.stats');
        await absent('session.network.stats');
        const restored = UiProbe.measure(ui, ['session.header.capsule'])[0].bounds;
        for (let index = 0; index < 4; index++) {
          expect(Math.abs(restored[index] - collapsed[0].bounds[index]) <= 1).assertTrue();
        }
      } finally {
        await mock.setMaterialPreference(original);
        await mock.disconnect(); await route('devices');
      }
    });
    it('native_control_preferences_survive_service_restart', 0, async () => {
      let service = new NativeSessionService();
      await service.init(context);
      const original = service.settings();
      const smartReach = original.smartReachEnabled;
      const position = original.controlBarPosition;
      const material = original.materialPreference;
      const autoPiP = original.autoStartPiP;
      try {
        await service.setSmartReachEnabled(false); await service.setControlBarPosition('right');
        await service.setMaterialPreference('gentle');
        await service.setAutoStartPiP(true);
        const reloaded = new NativeSessionService();
        service.dispose();
        await reloaded.init(context);
        service = reloaded;
        expect(service.settings().smartReachEnabled).assertFalse();
        expect(service.settings().controlBarPosition).assertEqual('right');
        expect(service.settings().materialPreference).assertEqual('gentle');
        expect(service.settings().autoStartPiP).assertTrue();
        await service.setTheme(original.themePreference);
        expect(service.settings().smartReachEnabled).assertFalse();
        expect(service.settings().controlBarPosition).assertEqual('right');
        expect(service.settings().materialPreference).assertEqual('gentle');
      } finally {
        await service.setSmartReachEnabled(smartReach);
        await service.setMaterialPreference(material);
        await service.setControlBarPosition(position);
        await service.setAutoStartPiP(autoPiP);
        service.dispose();
        await route('devices');
      }
    });
    it('device_presence_refreshes_while_idle_and_resumes_in_foreground', 0, async () => {
      const foreground = AppStorage.get<boolean>('deviceListForeground') ?? true;
      const connect = 'device.demo-win-01.connect';
      try {
        AppStorage.setOrCreate('deviceListForeground', false);
        await route('devices'); await mock.listDevices(); await settle();
        expect(await (await driver.findComponent(ON.id(connect))).isEnabled()).assertTrue();
        mock.nextDeviceOnline = false;
        AppStorage.setOrCreate('deviceListForeground', true);
        await settle();
        expect(await (await driver.findComponent(ON.id(connect))).isEnabled()).assertFalse();

        mock.nextDeviceOnline = true;
        await new Promise<void>((resolve) => { setTimeout(resolve, 16000); });
        expect(await (await driver.findComponent(ON.id(connect))).isEnabled()).assertTrue();

        await route('settings');
        AppStorage.setOrCreate('deviceListForeground', false);
        mock.nextDeviceOnline = false;
        AppStorage.setOrCreate('deviceListForeground', true);
        await settle();
        expect(mock.nextDeviceOnline === false).assertTrue();
        await route('devices');
        expect(await (await driver.findComponent(ON.id(connect))).isEnabled()).assertFalse();
      } finally {
        mock.nextDeviceOnline = null;
        AppStorage.setOrCreate('deviceListForeground', foreground);
        await mock.listDevices();
        await route('devices');
      }
    });
    it('device_takeover_is_not_a_permanent_menu_action', 0, async () => {
      try {
        for (const busy of [undefined, false, true]) {
          await route('devices'); await mock.listDevices(); mock.setDeviceBusy(busy); await settle();
          const count = mock.connectionForces.length;
          await (await driver.findComponent(ON.id('device.demo-win-01.more'))).click(); await settle();
          await absent('device.demo-win-01.takeover');
          await (await driver.findComponent(ON.text('设备信息'))).click(); await settle();
          expect((await driver.findComponents(ON.text('接管连接').within(ON.type('Button'))))?.length ?? 0).assertEqual(0);
          await (await driver.findComponent(ON.text('连接').within(ON.type('Button')))).click(); await settle();
          if (busy === true) {
            expect(mock.connectionForces.length).assertEqual(count);
            await (await driver.findComponent(ON.text('取消').within(ON.type('Button')))).click(); await settle();
            expect(mock.connectionForces.length).assertEqual(count);
          } else {
            expect(mock.connectionForces.length).assertEqual(count + 1);
            expect(mock.connectionForces[count]).assertFalse();
            await present('session.page'); await mock.disconnect();
          }
        }
        await route('devices'); await mock.listDevices(); await settle();
        const count = mock.connectionForces.length;
        await (await driver.findComponent(ON.id('device.demo-win-01.connect'))).click(); await settle();
        expect(mock.connectionForces.length).assertEqual(count + 1);
        expect(mock.connectionForces[count]).assertFalse();
        await mock.disconnect(); await route('devices'); await mock.listDevices(); await settle();
        await scrollToId('devices.grid', 'device.demo-mac-01.more');
        await (await driver.findComponent(ON.id('device.demo-mac-01.more'))).click(); await settle();
        await absent('device.demo-mac-01.takeover');
      } finally { await driver.pressBack(); await mock.disconnect(); await route('devices'); }
    });
    it('device_card_uses_confirmed_control_state_without_promoting_busy', 0, async () => {
      await route('devices'); await mock.listDevices(); await settle();
      try {
        for (const busy of [undefined, false, true]) {
          mock.setDeviceBusy(busy);
          const status = busy === true ? '在线 · 使用中' : '在线 · 可连接';
          mock.setDeviceControlled(undefined, status); await settle();
          expect(await (await driver.findComponent(ON.id('device.demo-win-01.status'))).getText()).assertEqual(status);
          expect((await driver.findComponents(ON.text('被控中')))?.length ?? 0).assertEqual(0);
        }
        mock.setDeviceBusy(false);
        mock.setDeviceControlled(true, '被控中'); await settle();
        expect(await (await driver.findComponent(ON.id('device.demo-win-01.status'))).getText()).assertEqual('被控中');
        expect(await (await driver.findComponent(ON.id('device.demo-win-01.connect'))).isEnabled()).assertTrue();
        await (await driver.findComponent(ON.id('device.demo-win-01.more'))).click(); await settle();
        await absent('device.demo-win-01.takeover');
        await (await driver.findComponent(ON.text('设备信息'))).click(); await settle();
        expect((await driver.findComponents(ON.text('系统：Windows\n状态：被控中\n设备 ID：demo-win-01')))?.length ?? 0)
          .assertEqual(1);
        await driver.pressBack(); await settle();
        await mock.listDevices(); await settle();
        expect((await driver.findComponents(ON.text('被控中')))?.length ?? 0).assertEqual(0);
        mock.setDeviceControlled(true, '被控中'); await settle();
        mock.setDeviceControlled(false, '在线 · 可连接'); await settle();
        expect(await (await driver.findComponent(ON.id('device.demo-win-01.status'))).getText()).assertEqual('在线 · 可连接');
        expect(await (await driver.findComponent(ON.id('device.demo-win-01.connect'))).isEnabled()).assertTrue();
      } finally { await mock.listDevices(); await route('devices'); }
    });
    it('occupied_device_connect_button_opens_confirmed_takeover', 0, async () => {
      try {
        for (const controlled of [false, true]) {
          await route('devices'); await mock.listDevices();
          mock.setDeviceBusy(!controlled);
          mock.setDeviceControlled(controlled, controlled ? '被控中' : '在线 · 使用中'); await settle();
          const count = mock.connectionForces.length;
          const connect = await driver.findComponent(ON.id('device.demo-win-01.connect'));
          expect(await connect.isEnabled()).assertTrue();
          await connect.click(); await settle();
          expect(mock.connectionForces.length).assertEqual(count);
          await (await driver.findComponent(ON.text('取消').within(ON.type('Button')))).click(); await settle();
          expect(mock.connectionForces.length).assertEqual(count);
          await (await driver.findComponent(ON.id('device.demo-win-01.connect'))).click(); await settle();
          await (await driver.findComponent(ON.text('接管连接').within(ON.type('Button')))).click(); await settle();
          expect(mock.connectionForces.length).assertEqual(count + 1);
          expect(mock.connectionForces[count]).assertTrue();
          await present('session.page'); await mock.disconnect();
          await route('devices'); await mock.listDevices();
          mock.setDeviceBusy(!controlled);
          mock.setDeviceControlled(controlled, controlled ? '被控中' : '在线 · 使用中'); await settle();
          await (await driver.findComponent(ON.id('device.demo-win-01.more'))).click(); await settle();
          await (await driver.findComponent(ON.text('设备信息'))).click(); await settle();
          await (await driver.findComponent(ON.text('连接').within(ON.type('Button')))).click(); await settle();
          expect(mock.connectionForces.length).assertEqual(count + 1);
          await (await driver.findComponent(ON.text('接管连接').within(ON.type('Button')))).click(); await settle();
          expect(mock.connectionForces.length).assertEqual(count + 2);
          expect(mock.connectionForces[count + 1]).assertTrue();
          await present('session.page'); await mock.disconnect();
        }
      } finally { await mock.disconnect(); await mock.listDevices(); await route('devices'); }
    });
    it('device_information_uses_the_selected_device', 0, async () => {
      await route('devices'); await mock.listDevices(); await settle();
      await scrollToId('devices.grid', 'device.demo-mac-01.more');
      await (await driver.findComponent(ON.id('device.demo-mac-01.more'))).click(); await settle();
      await (await driver.findComponent(ON.text('设备信息'))).click(); await settle();
      const details = await driver.findComponents(ON.text('系统：macOS\n状态：离线\n设备 ID：demo-mac-01'));
      const closes = await driver.findComponents(ON.text('关闭'));
      await abilityDelegatorRegistry.getAbilityDelegator().print('UU_DEVICE_DIALOG ' + JSON.stringify({
        messageCount: details?.length ?? 0, closeCount: closes?.length ?? 0 }) + '\n');
      await capture('offline-device-info');
      try {
        expect(details?.length ?? 0).assertEqual(1);
        expect(closes?.length ?? 0).assertEqual(1);
      } finally { await driver.pressBack(); await settle(); }
      await scrollToId('devices.grid', 'device.demo-win-01.more');
      await (await driver.findComponent(ON.id('device.demo-win-01.more'))).click(); await settle();
      await (await driver.findComponent(ON.text('设备信息'))).click(); await settle();
      try {
        expect((await driver.findComponents(ON.text('系统：Windows\n状态：在线 · 可连接\n设备 ID：demo-win-01')))?.length ?? 0).assertEqual(1);
        expect((await driver.findComponents(ON.text('关闭')))?.length ?? 0).assertEqual(1);
        await capture('online-device-info');
      } finally { await driver.pressBack(); await settle(); }
    });
    it('account_device_without_control_is_visible_but_has_no_remote_actions', 0, async () => {
      await route('devices'); await mock.listDevices(); mock.showGroupedDevice(); await settle();
      try {
        await present('device.account-phone.card');
        const button = await driver.findComponent(ON.id('device.account-phone.connect'));
        expect(await button.isEnabled()).assertFalse();
        expect(await button.getText()).assertEqual('不可远控');
        const grid = (JSON.parse(getInspectorByKey('devices.grid')) as ScrollBarInspector).$attrs;
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_DEVICE_GRID_EDGE ' +
          JSON.stringify({ effect: grid?.['edgeEffect'], options: grid?.['edgeEffectOptions'] }) + '\n');
        expect(grid?.['edgeEffect']).assertEqual('EdgeEffect.Spring');
        expect(JSON.stringify(grid?.['edgeEffectOptions'] ?? '').includes('"alwaysEnabled":true')).assertTrue();
        await (await driver.findComponent(ON.id('device.account-phone.more'))).click(); await settle();
        expect((await driver.findComponents(ON.text('文件管理')))?.length ?? 0).assertEqual(0);
        expect((await driver.findComponents(ON.text('解绑设备')))?.length ?? 0).assertEqual(0);
        await (await driver.findComponent(ON.text('设备信息'))).click(); await settle();
        const details = await driver.findComponents(ON.text('系统：Android\n状态：在线\n设备 ID：account-phone'));
        expect(details?.length ?? 0).assertEqual(1);
        expect((await driver.findComponents(ON.text('连接')))?.length ?? 0).assertEqual(0);
        await driver.pressBack(); await settle();
      } finally { await mock.listDevices(); await route('devices'); }
    });
    it('eligible_offline_device_offers_wake_without_claiming_it_is_online', 0, async () => {
      const start = mock.wakeRequests.length;
      await route('devices'); await mock.listDevices(); mock.showWakeDevices(); await settle();
      try {
        const wake = await driver.findComponent(ON.id('device.wake-supported.connect'));
        const unavailable = await driver.findComponent(ON.id('device.wake-unavailable.connect'));
        const online = await driver.findComponent(ON.id('device.wake-online.connect'));
        expect(await wake.getText()).assertEqual('远程开机');
        expect(await wake.isEnabled()).assertTrue();
        expect(await unavailable.isEnabled()).assertFalse();
        expect(await online.getText()).assertEqual('连接');
        await feedbackFrame('remote-wake-entry');
        await wake.click(); await settle();
        expect(mock.wakeRequests.slice(start)).assertDeepEquals(['wake-supported']);
        expect(await (await driver.findComponent(ON.id('device.wake-supported.connect'))).isEnabled()).assertFalse();
        expect(await (await driver.findComponent(ON.id('device.wake-supported.status'))).getText()).assertEqual('离线');
        await absent('session.page');
      } finally { mock.completeWakeRequest(); await settle(); await mock.listDevices(); }
    });
    it('device_cards_use_platform_icons_at_the_existing_size', 0, async () => {
      await route('devices'); await mock.listDevices(); mock.showPlatformDevices(); await settle();
      try {
        const ui = (await window.getLastWindow(context)).getUIContext();
        const dark = AppStorage.get<boolean>('isDark') === true;
        const phone = dark ? $r('app.media.device_phone_dark') : $r('app.media.device_phone_light');
        const tv = dark ? $r('app.media.device_tv_dark') : $r('app.media.device_tv_light');
        const expected = [iconResource('devices', dark, false), phone, phone, tv];
        for (let index = 0; index < expected.length; index++) {
          const id = 'device.platform-icon-' + index + '.icon';
          const icon = (JSON.parse(getInspectorByKey(id)) as ScrollBarInspector).$attrs;
          expect(String(icon?.['src'])).assertEqual('resource:///' + expected[index].id + '.svg');
          const bounds = UiProbe.measure(ui, [id])[0].bounds;
          expect(Math.abs(bounds[2] - 32) <= 1 && Math.abs(bounds[3] - 32) <= 1).assertTrue();
        }
        await feedbackFrame('device-platform-icons');
      } finally { await mock.listDevices(); await route('devices'); }
    });
    it('native_shell_and_device_cards', 0, async () => {
      await route('devices');
      await present('app.shell'); await present('app.bottomNav'); await present('devices.search');
      expect(await (await driver.findComponent(ON.id('app.title'))).getText()).assertEqual('设备');
      await present('device.demo-win-01.card');
      const search = await (await driver.findComponent(ON.id('devices.search'))).getBounds();
      const first = await (await driver.findComponent(ON.id('device.demo-win-01.card'))).getBounds();
      const gridBounds = await (await driver.findComponent(ON.id('devices.grid'))).getBounds();
      await abilityDelegatorRegistry.getAbilityDelegator().print('UU_SEARCH_CARD_BOUNDS ' + JSON.stringify({
        search: search, first: first, grid: gridBounds }) + '\n');
      expect(Math.abs(search.left - first.left) <= 2).assertTrue();
      expect(Math.abs(search.right - (gridBounds.left + gridBounds.right - first.left)) <= 2).assertTrue();
      const grid = await driver.findComponent(ON.id('devices.grid'));
      await scrollToId('devices.grid', 'device.demo-mac-01.connect');
      const offline = await driver.findComponent(ON.id('device.demo-mac-01.connect'));
      expect(await offline.isEnabled()).assertFalse();
      await grid.scrollToTop();
      await settle();
      await floatingTabs(); await roundControl('devices.refresh');
      await capture('devices');
    });
    it('settings_account_card_shows_the_masked_account_above_preferences', 0, async () => {
      const previous = AppStorage.get<string>('accountIdSuffix') ?? '';
      AppStorage.setOrCreate('accountIdSuffix', '4826');
      try {
        await route('settings');
        await present('settings.account.card');
        const ui = (await window.getLastWindow(context)).getUIContext();
        expect(UiProbe.measure(ui, ['settings.account.avatar'])[0].bounds.length).assertEqual(4);
        const account = await (await driver.findComponent(ON.id('settings.account.card'))).getBounds();
        const preferences = await (await driver.findComponent(ON.id('settings.general'))).getBounds();
        expect(account.bottom <= preferences.top).assertTrue();
        const detail = await driver.findComponent(ON.text('账号尾号 4826'));
        expect(await detail.getText()).assertEqual('账号尾号 4826');
        await capture('settings-account-avatar');
      } finally {
        AppStorage.setOrCreate('accountIdSuffix', previous);
        await route('devices');
      }
    });
    it('native_tab_switch_and_settings_navigation', 0, async () => {
      await route('devices');
      const assist = await driver.findComponent(ON.text('远程协助').within(ON.type('TabBar')));
      await assist.click(); await settle();
      await present('assist.page');
      const form = await (await driver.findComponent(ON.id('assist.form'))).getBounds();
      const page = await (await driver.findComponent(ON.id('assist.page'))).getBounds();
      await abilityDelegatorRegistry.getAbilityDelegator().print('UU_ASSIST_BOUNDS ' + JSON.stringify({ form: form, page: page }) + '\n');
      const assistWindow = await window.getLastWindow(context);
      const assistUtils = assistWindow.getUIContext().getComponentUtils();
      const formLayout = assistUtils.getRectangleById('assist.form');
      const pageLayout = assistUtils.getRectangleById('assist.page');
      await abilityDelegatorRegistry.getAbilityDelegator().print('UU_ASSIST_LAYOUT ' + JSON.stringify({
        page: [pageLayout.windowOffset.x, pageLayout.size.width],
        form: [formLayout.windowOffset.x, formLayout.size.width]
      }) + '\n');
      await capture('assistance');
      expect(form.top <= page.top + 2).assertTrue();
      // UiTest visible bounds can be clipped by the tablet's system sidebar handle.
      expect(Math.abs(2 * formLayout.windowOffset.x + formLayout.size.width -
        2 * pageLayout.windowOffset.x - pageLayout.size.width) <= 2).assertTrue();
      const id = await (await driver.findComponent(ON.id('assist.connectId'))).getBounds();
      const code = await (await driver.findComponent(ON.id('assist.verifyCode'))).getBounds();
      const connect = await (await driver.findComponent(ON.id('assist.connect'))).getBounds();
      expect(id.bottom < code.top && code.bottom < connect.top).assertTrue();
      expect(id.left === code.left && id.right === code.right).assertTrue();
      await capture('assistance');
      const settings = await driver.findComponent(ON.text('设置').within(ON.type('TabBar')));
      await settings.click(); await settle();
      await present('settings.groups');
      await floatingTabs(); await capture('settings-root');
      const video = await driver.findComponent(ON.id('settings.video'));
      await video.click(); await settle();
      await scrollToId('settings.detail.scroll', 'settings.resolution');
      await present('settings.resolution');
      await capture('settings');
    });
    it('tab_labels_highlight_the_visible_page', 0, async () => {
      await route('devices'); await mock.listDevices(); await settle();
      const names: string[] = ['设备', '远程协助', '设置'];
      const win = await window.getLastWindow(context);
      try {
        for (const selected of [1, 2, 0]) {
          await (await driver.findComponent(ON.text(names[selected]).within(ON.type('TabBar')))).click();
          await settle();
          const shell = win.getUIContext().getComponentUtils().getRectangleById('app.shell');
          const screen = await (await driver.findComponent(ON.id('app.shell'))).getBounds();
          const dx = screen.left - shell.windowOffset.x;
          const dy = screen.top - shell.windowOffset.y;
          const pixels = await win.snapshot();
          const counts: number[] = [];
          const iconCounts: number[] = [];
          try {
            const info = await pixels.getImageInfo();
            expect(info.pixelFormat === image.PixelMapFormat.RGBA_8888 ||
              info.pixelFormat === image.PixelMapFormat.BGRA_8888).assertTrue();
            const buffer = new ArrayBuffer(pixels.getPixelBytesNumber());
            await pixels.readPixelsToBuffer(buffer);
            const bytes = new Uint8Array(buffer);
            const stride = bytes.length / info.size.height;
            const icons = await driver.findComponents(ON.type('Image').within(ON.type('TabBar')));
            expect(icons?.length ?? 0).assertEqual(names.length);
            for (const name of names) {
              const component = await driver.findComponent(ON.text(name).within(ON.type('TabBar')));
              if (component === null) {
                await capture('tab-label-missing');
                throw new Error('Missing tab label: ' + name + ', selected=' + selected + ', route=' + Router.current());
              }
              const bounds = [await component.getBounds(), await icons![names.indexOf(name)].getBounds()];
              for (let part = 0; part < bounds.length; part++) {
                const rect = bounds[part];
                let count = 0;
                for (let y = Math.max(0, Math.ceil(rect.top - dy)); y < Math.min(info.size.height, rect.bottom - dy); y++) {
                  for (let x = Math.max(0, Math.ceil(rect.left - dx)); x < Math.min(info.size.width, rect.right - dx); x++) {
                    const offset = y * stride + x * 4;
                    const high = Math.max(bytes[offset], bytes[offset + 1], bytes[offset + 2]);
                    const low = Math.min(bytes[offset], bytes[offset + 1], bytes[offset + 2]);
                    if (high - low > 70 && bytes[offset + 3] > 32) { count++; }
                  }
                }
                if (part === 0) { counts.push(count); } else { iconCounts.push(count); }
              }
            }
          } finally { await pixels.release(); }
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_TAB_LABEL_COLORS ' + JSON.stringify({
            selected: selected, coloredPixels: counts, iconColoredPixels: iconCounts }) + '\n');
          await capture('tab-selection-' + selected);
          if (iconCounts[selected] <= 4) {
            const path = context.cacheDir + '/three-device-tab-icons.json';
            const treeFile = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
            try { fs.writeSync(treeFile.fd, JSON.stringify(getInspectorTree())); } finally { fs.closeSync(treeFile); }
            await abilityDelegatorRegistry.getAbilityDelegator().print('UU_TAB_MISSING_ICON_TREE ' + path + '\n');
          }
          for (let index = 0; index < names.length; index++) {
            expect(counts[index] > 4).assertEqual(index === selected);
            expect(iconCounts[index] > 4).assertEqual(index === selected);
          }
        }
      } finally { await route('devices'); }
    });
    it('tab_switch_renders_intermediate_content_frames', 0, async () => {
      await route('devices'); await mock.listDevices(); await settle();
      const win = await window.getLastWindow(context);
      const tab = await driver.findComponent(ON.text('远程协助').within(ON.type('TabBar')));
      const frames: image.PixelMap[] = [await win.snapshot()];
      const times: number[] = [0];
      const hashes: number[] = [];
      const started = Date.now();
      try {
        const clicking = tab.click();
        for (let index = 0; index < 4; index++) {
          await new Promise<void>((resolve) => { setTimeout(resolve, 40); });
          frames.push(await win.snapshot()); times.push(Date.now() - started);
        }
        await clicking; await settle();
        frames.push(await win.snapshot()); times.push(Date.now() - started);
        for (let index = 0; index < frames.length; index++) {
          const info = await frames[index].getImageInfo();
          const buffer = new ArrayBuffer(frames[index].getPixelBytesNumber());
          await frames[index].readPixelsToBuffer(buffer);
          const bytes = new Uint8Array(buffer);
          const stride = bytes.length / info.size.height;
          let hash = 2166136261;
          for (let offset = Math.floor(info.size.height / 4) * stride;
            offset < Math.floor(info.size.height * 3 / 4) * stride; offset += 64) {
            hash = Math.imul(hash ^ bytes[offset], 16777619) >>> 0;
          }
          hashes.push(hash);
          const path = context.cacheDir + '/three-device-animation-tab-' + index + '.png';
          const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
          const packer = image.createImagePacker();
          try { await packer.packToFile(frames[index], file.fd, { format: 'image/png', quality: 100 }); }
          finally { fs.closeSync(file); await packer.release(); }
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_UI_CAPTURE ' + path + '\n');
        }
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_TAB_ANIMATION ' + JSON.stringify({ times: times, hashes: hashes }) + '\n');
        expect(hashes[0] !== hashes[hashes.length - 1]).assertTrue();
        expect(hashes.slice(1, -1).some((hash: number) => hash !== hashes[0] && hash !== hashes[hashes.length - 1])).assertTrue();
        await present('assist.page');
        expect(Router.current()).assertEqual('assist');
        const tabs: ScrollBarInspector = JSON.parse(getInspectorByKey('app.bottomNav'));
        expect(tabs.$attrs?.['index']).assertEqual('1');
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_TAB_SELECTION ' + JSON.stringify({
          index: tabs.$attrs?.['index'], duration: tabs.$attrs?.['animationDuration'] }) + '\n');
      } finally { for (const pixels of frames) { await pixels.release(); } await route('devices'); }
    });
    it('virtual_mouse_expansion_and_collapse_render_intermediate_frames', 0, async () => {
      await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
      try {
        mock.emitFirstFrame(); await settle();
        const win = await window.getLastWindow(context);
        for (const action of ['session.mouse.collapsed', 'session.mouse.collapse']) {
          const frames: image.PixelMap[] = [await win.snapshot()];
          const hashes: number[] = [];
          const times: number[] = [0];
          try {
            const control = await driver.findComponent(ON.id(action));
            const before = win.getUIContext().getComponentUtils().getRectangleById(action);
            const started = Date.now();
            const clicking = control.click();
            for (let index = 0; index < 10; index++) {
              await new Promise<void>((resolve) => { setTimeout(resolve, 16); });
              frames.push(await win.snapshot()); times.push(Date.now() - started);
            }
            await clicking; await settle(); frames.push(await win.snapshot()); times.push(Date.now() - started);
            const destination = action === 'session.mouse.collapsed' ? 'session.mouse.expanded' : 'session.mouse.collapsed';
            const after = win.getUIContext().getComponentUtils().getRectangleById(destination);
            for (let index = 0; index < frames.length; index++) {
              const info = await frames[index].getImageInfo();
              const buffer = new ArrayBuffer(frames[index].getPixelBytesNumber());
              await frames[index].readPixelsToBuffer(buffer);
              const bytes = new Uint8Array(buffer);
              const stride = bytes.length / info.size.height;
              const left = Math.max(0, Math.floor(Math.min(before.windowOffset.x, after.windowOffset.x)) - 24);
              const right = Math.min(info.size.width, Math.ceil(Math.max(before.windowOffset.x + before.size.width,
                after.windowOffset.x + after.size.width)) + 24);
              const top = Math.max(0, Math.floor(Math.min(before.windowOffset.y, after.windowOffset.y)) - 24);
              const bottom = Math.min(info.size.height, Math.ceil(Math.max(before.windowOffset.y + before.size.height,
                after.windowOffset.y + after.size.height)) + 24);
              expect(right > left && bottom > top).assertTrue();
              let hash = 2166136261;
              for (let y = top; y < bottom; y += 4) {
                for (let x = left; x < right; x += 4) {
                  const offset = y * stride + x * 4;
                  for (let channel = 0; channel < 3; channel++) {
                    hash = Math.imul(hash ^ bytes[offset + channel], 16777619) >>> 0;
                  }
                }
              }
              hashes.push(hash);
              const path = context.cacheDir + '/three-device-mouse-animation-' + action.split('.').pop() + '-' + index + '.png';
              const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
              const packer = image.createImagePacker();
              try { await packer.packToFile(frames[index], file.fd, { format: 'image/png', quality: 100 }); }
              finally { fs.closeSync(file); await packer.release(); }
              await abilityDelegatorRegistry.getAbilityDelegator().print('UU_UI_CAPTURE ' + path + '\n');
            }
            await abilityDelegatorRegistry.getAbilityDelegator().print('UU_MOUSE_ANIMATION ' + JSON.stringify({
              action: action, times: times, hashes: hashes }) + '\n');
            expect(hashes[0] !== hashes[hashes.length - 1]).assertTrue();
            expect(hashes.slice(1, -1).some((hash: number) => hash !== hashes[0] && hash !== hashes[hashes.length - 1])).assertTrue();
          } finally { for (const pixels of frames) { await pixels.release(); } }
        }
        await present('session.mouse.collapsed'); await absent('session.mouse.expanded');
      } finally { await mock.disconnect(); await route('devices'); }
    });
    it('native_text_input_injection_preserves_spaces', 0, async () => {
      await route('devices');
      const ui = (await window.getLastWindow(context)).getUIContext();
      const prompt = ui.getPromptAction();
      const content = new ComponentContent(ui, wrapBuilder(textInputInjectionSample));
      await prompt.openCustomDialog(content, { alignment: DialogAlignment.Center, maskColor: Color.Transparent });
      try {
        await settle();
        const input = await driver.findComponent(ON.id('probe.text.input'));
        await input.inputText('UI keyboard check'); await settle();
        const typed = await input.getText();
        await input.clearText(); await settle();
        await input.inputText('UI keyboard check', { paste: true, addition: false }); await settle();
        const pasted = await input.getText();
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_TEXT_INJECTION ' + JSON.stringify({
          typedLength: typed.length, pastedLength: pasted.length,
          typedMatches: typed === 'UI keyboard check', pastedMatches: pasted === 'UI keyboard check' }) + '\n');
        expect(typed).assertEqual('UI keyboard check'); expect(pasted).assertEqual('UI keyboard check');
      } finally { await prompt.closeCustomDialog(content); content.dispose(); }
    });
    it('display_preferences_keep_the_selected_tab_and_detail', 0, async () => {
      const theme = mock.settings().themePreference;
      const material = mock.settings().materialPreference;
      try {
        await route('portmap');
        await mock.setTheme('light'); ThemeManager.apply(context, 'light');
        await mock.setMaterialPreference('system');
        await route('devices');
        await (await driver.findComponent(ON.text('设置').within(ON.type('TabBar')))).click(); await settle();
        await (await driver.findComponent(ON.id('settings.general'))).click(); await settle();
        for (const appearance of ['深色', '浅色', '跟随系统']) {
          await (await driver.findComponent(ON.id('settings.theme'))).click(); await settle();
          await (await driver.findComponent(ON.text(appearance).within(ON.type('Menu')))).click(); await settle();
          expect(Router.current()).assertEqual('settings');
          await present('settings.detail'); await selectedValue('settings.theme', appearance);
          expect(await (await driver.findComponent(ON.id('settings.detail.title'))).getText()).assertEqual('通用设置');
        }
        for (const level of ['柔和', '流畅', '精致', '跟随系统']) {
          await (await driver.findComponent(ON.id('settings.material'))).click(); await settle();
          await (await driver.findComponent(ON.text(level).within(ON.type('Menu')))).click(); await settle();
          expect(Router.current()).assertEqual('settings');
          await present('settings.detail'); await selectedValue('settings.material', level);
        }
        for (const id of ['app.bottomNav', 'app.nav.devices', 'app.nav.assist', 'app.nav.settings']) {
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_DISPLAY_TAB ' + getInspectorByKey(id) + '\n');
        }
        await capture('display-preferences-stay');
      } finally {
        await mock.setTheme(theme); ThemeManager.apply(context, theme);
        await mock.setMaterialPreference(material); await route('devices');
      }
    });
    it('settings_inline_values_and_detail_navigation', 0, async () => {
      const original = mock.settings();
      const keepScreenOn = original.keepScreenOn;
      const maxFps = AppStorage.get<number>('decoderMaxFps') ?? 60;
      try {
        AppStorage.setOrCreate('decoderMaxFps', 0);
        await route('portmap'); await route('settings');
        await (await driver.findComponent(ON.id('settings.video'))).click(); await settle();
        await revealSetting('settings.fps');
        expect(await (await driver.findComponent(ON.id('settings.fps'))).isEnabled()).assertFalse();
        await route('portmap');
        AppStorage.setOrCreate('decoderMaxFps', 60);
        await generalSettings();
        await inlineSelect('settings.theme'); await inlineSelect('settings.input'); await inlineSelect('settings.files');
        await revealSetting('settings.keepScreenOn');
        const keep = await driver.findComponent(ON.type('Toggle').within(ON.id('settings.keepScreenOn')));
        await keep.click(); await settle();
        expect(mock.settings().keepScreenOn).assertEqual(!keepScreenOn);
        await revealSetting('settings.theme');
        await (await driver.findComponent(ON.id('settings.theme'))).click(); await settle();
        await (await driver.findComponent(ON.text('浅色'))).click(); await settle();
        expect(mock.settings().themePreference).assertEqual('light');
        expect(AppStorage.get<boolean>('isDark')).assertFalse();
        await selectedValue('settings.theme', '浅色');
        await capture('settings-theme-light');
        await (await driver.findComponent(ON.id('settings.theme'))).click(); await settle();
        await (await driver.findComponent(ON.text('深色'))).click(); await settle();
        expect(mock.settings().themePreference).assertEqual('dark');
        expect(AppStorage.get<boolean>('isDark')).assertTrue();
        await selectedValue('settings.theme', '深色');
        await capture('settings-theme-dark');
        if (deviceInfo.deviceType === 'phone') {
          await present('settings.detail');
          expect(await (await driver.findComponent(ON.id('settings.detail.title'))).getText()).assertEqual('通用设置');
        }
        await route('portmap'); await route('settings');
        await (await driver.findComponent(ON.id('settings.video'))).click(); await settle();
        await inlineSelect('settings.quality'); await inlineSelect('settings.fps');
        await inlineSelect('settings.color'); await inlineSelect('settings.resolution');
        await revealSetting('settings.quality');
        await (await driver.findComponent(ON.id('settings.quality'))).click(); await settle();
        await (await driver.findComponent(ON.text('高清 2M'))).click(); await settle();
        expect(mock.settings().defaultVideoQuality).assertEqual('hd');
        await revealSetting('settings.fps');
        await (await driver.findComponent(ON.id('settings.fps'))).click(); await settle();
        await (await driver.findComponent(ON.text('30 帧'))).click(); await settle();
        expect(mock.settings().defaultFrameRate).assertEqual(30);
        await revealSetting('settings.color');
        await (await driver.findComponent(ON.id('settings.color'))).click(); await settle();
        await (await driver.findComponent(ON.text('4:2:0'))).click(); await settle();
        expect(mock.settings().trueColor).assertFalse();
        await scrollToId('settings.detail.scroll', 'settings.resolution');
        await (await driver.findComponent(ON.id('settings.resolution'))).click(); await settle();
        await (await driver.findComponent(ON.text('720p · 1280×720'))).click(); await settle();
        expect(mock.settings().defaultVideoProfile).assertEqual('720p30');
        await selectedValue('settings.quality', '高清 2M');
        await selectedValue('settings.fps', '30 帧');
        await selectedValue('settings.resolution', '720p · 1280×720');
        await capture('settings-video-selected');
        await generalSettings();
        await revealSetting('settings.input');
        await (await driver.findComponent(ON.id('settings.input'))).click(); await settle();
        await (await driver.findComponent(ON.text('直接触控'))).click(); await settle();
        expect(mock.settings().touchMode).assertEqual('direct');
        await selectedValue('settings.input', '直接触控');
        await capture('settings-input');
        await generalSettings();
        await scrollToId('settings.detail.scroll', 'settings.files');
        await (await driver.findComponent(ON.id('settings.files'))).click(); await settle();
        await (await driver.findComponent(ON.text('手动发送'))).click(); await settle();
        expect(mock.settings().clipboardPolicy).assertEqual('manual');
        await capture('settings-clipboard');
        await route('portmap'); await route('settings');
        await scrollToId('settings.groups', 'settings.logout');
        await present('settings.logout');
        const logout = await (await driver.findComponent(ON.id('settings.logout'))).getBounds();
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_LOGOUT_BOUNDS ' + JSON.stringify(logout) + '\n');
        await capture('settings-logout');
        await (await driver.findComponent(ON.id('settings.logout'))).click(); await settle();
        expect((await driver.findComponents(ON.text('退出后将结束本账号所属的会话并删除本机保存的登录凭据。')))?.length ?? 0).assertEqual(1);
        await (await driver.findComponent(ON.text('取消'))).click(); await settle();
        await capture('settings-logout-cancelled');
        await scrollToId('settings.groups', 'settings.about');
        await (await driver.findComponent(ON.id('settings.about'))).click(); await settle();
        await present('settings.about.version'); await present('settings.about.license');
        await present('settings.about.unofficial');
        await capture('settings-about');
      } finally {
        await mock.setTheme(original.themePreference); ThemeManager.apply(context, original.themePreference);
        await mock.setVideoQuality(original.defaultVideoQuality); await mock.setFrameRate(original.defaultFrameRate);
        await mock.setVideoProfile(original.defaultVideoProfile); await mock.setTouchMode(original.touchMode);
        await mock.setClipboardPolicy(original.clipboardPolicy);
        await mock.setKeepScreenOn(keepScreenOn);
        await route('portmap');
        AppStorage.setOrCreate('decoderMaxFps', maxFps);
      }
    });
    it('settings_subpage_groups_and_remote_control_position', 0, async () => {
      const original = mock.settings();
      const smartReach = original.smartReachEnabled;
      const position = original.controlBarPosition;
      const material = original.materialPreference;
      try {
        await mock.setSmartReachEnabled(true); await mock.setControlBarPosition('right');
        await generalSettings();
        await present('settings.section.display'); await present('settings.section.input');
        const labelLeft = (await (await driver.findComponent(ON.id('settings.theme.label'))).getBounds()).left;
        await leftSection('settings.section.display', labelLeft); await leftSection('settings.section.input', labelLeft);
        await revealSetting('settings.smartReach');
        await present('settings.section.remote'); await absent('settings.controlBarPosition');
        await leftSection('settings.section.remote', labelLeft);
        await capture('settings-smart-reach');
        await (await driver.findComponent(ON.type('Toggle').within(ON.id('settings.smartReach')))).click(); await settle();
        expect(mock.settings().smartReachEnabled).assertFalse();
        await revealSetting('settings.controlBarPosition'); await inlineSelect('settings.controlBarPosition');
        const positions: ControlBarPosition[] = ['left', 'right', 'center'];
        const labels: string[] = ['左', '右', '居中'];
        for (let index = 0; index < positions.length; index++) {
          if (index > 0) { await generalSettings(); await revealSetting('settings.controlBarPosition'); }
          await (await driver.findComponent(ON.id('settings.controlBarPosition'))).click(); await settle();
          await (await driver.findComponent(ON.text(labels[index]))).click(); await settle();
          expect(mock.settings().controlBarPosition).assertEqual(positions[index]);
          await capture('settings-control-' + positions[index]);
          await mock.listDevices(); await mock.connect('demo-win-01'); await route('session');
          mock.emitFirstFrame(); await settle();
          await controlPosition(positions[index]); await capture('session-control-' + positions[index]);
          await mock.disconnect(); await route('devices');
        }
        await mock.setControlBarPosition('right');
        await mock.setTheme(original.themePreference); await mock.setVideoQuality(original.defaultVideoQuality);
        await mock.setVideoProfile(original.defaultVideoProfile); await mock.setFrameRate(original.defaultFrameRate);
        await mock.setTrueColor(original.trueColor); await mock.setTouchMode(original.touchMode);
        await mock.setClipboardPolicy(original.clipboardPolicy);
        expect(mock.settings().smartReachEnabled).assertFalse();
        expect(mock.settings().controlBarPosition).assertEqual('right');
        await mock.setSmartReachEnabled(true);
        await mock.connect('demo-win-01'); await route('session'); mock.emitFirstFrame(); await settle();
        await controlPosition('center');
        await mock.disconnect(); await route('settings');
        await (await driver.findComponent(ON.id('settings.video'))).click(); await settle();
        await present('settings.section.clarity'); await revealSetting('settings.fps');
        await present('settings.section.motion'); await capture('settings-video-groups');
      } finally {
        await mock.disconnect();
        await mock.setSmartReachEnabled(smartReach); await mock.setControlBarPosition(position);
        await route('devices');
      }
    });
    it('search_collapses_to_round_title_action_and_reopens', 0, async () => {
      await route('devices');
      mock.fillDeviceList(); await settle();
      try {
      expect(await (await driver.findComponent(ON.id('app.title'))).getText()).assertEqual('设备');
      await present('devices.search');
      const grid = await driver.findComponent(ON.id('devices.grid'));
      const bounds = await grid.getBounds();
      const x = Math.round((bounds.left + bounds.right) / 2);
      const height = bounds.bottom - bounds.top;
      await driver.swipe(x, Math.round(bounds.top + height * 0.7), x, Math.round(bounds.top + height * 0.25), 600); await settle();
      await capture('search-scrolled');
      await roundControl('devices.search.open');
      await buttonSpacing(['devices.search.open', 'devices.refresh']);
      await absent('devices.search');
      const anchor = await (await driver.findComponent(ON.id('devices.search.open'))).getBounds();
      const win = await window.getLastWindow(context);
      await abilityDelegatorRegistry.getAbilityDelegator().print('UU_SEARCH_NATIVE ' + JSON.stringify(UiProbe.measure(win.getUIContext(), ['app.shell', 'devices.search.open'])) + '\n');
      await capture('search-collapsed');
      await (await driver.findComponent(ON.id('devices.search.open'))).click(); await settle();
      await present('devices.search');
      const search = await driver.findComponent(ON.id('devices.search'));
      const expanded = await search.getBounds();
      await capture('search-inline');
      const inline = await (await driver.findComponent(ON.id('devices.search.inline'))).getBounds();
      await abilityDelegatorRegistry.getAbilityDelegator().print('UU_SEARCH_BOUNDS ' + JSON.stringify({ anchor: anchor, expanded: expanded, inline: inline }) + '\n');
      expect(Math.abs(expanded.top - anchor.top) <= 2).assertTrue();
      expect(Math.abs(expanded.right - anchor.right) <= 2).assertTrue();
      expect(expanded.left < anchor.left - 80).assertTrue();
      await absent('devices.search.open');
      await capture('search-inline');
      let scrollBounds = await (await driver.findComponent(ON.id('devices.grid'))).getBounds();
      let scrollX = Math.round((scrollBounds.left + scrollBounds.right) / 2);
      await driver.swipe(scrollX, Math.round(scrollBounds.top + (scrollBounds.bottom - scrollBounds.top) * 0.7),
        scrollX, Math.round(scrollBounds.top + (scrollBounds.bottom - scrollBounds.top) * 0.3), 600); await settle();
      await absent('devices.search'); await present('devices.search.open'); await capture('search-dismissed-scroll');
      await (await driver.findComponent(ON.id('devices.search.open'))).click(); await settle();
      const reopened = await driver.findComponent(ON.id('devices.search'));
      await reopened.inputText('Windows', { paste: true }); await settle();
      await abilityDelegatorRegistry.getAbilityDelegator().print('UU_SEARCH_QUERY_AFTER_INPUT ' +
        getInspectorByKey('devices.search') + '\n');
      await reopened.click(); await settle();
      await present('devices.search'); await absent('devices.search.open');
      scrollBounds = await (await driver.findComponent(ON.id('devices.grid'))).getBounds();
      const gutter = 8 * display.getDefaultDisplaySync().densityPixels;
      await driver.click(Math.round(scrollBounds.right - gutter), Math.round(scrollBounds.top + gutter)); await settle();
      await capture('search-outside-result');
      await absent('devices.search'); await present('devices.search.open'); await capture('search-dismissed-outside');
      await (await driver.findComponent(ON.id('devices.search.open'))).click(); await settle();
      await capture('search-reopened-query');
      await capture('search-expanded');
      if (deviceInfo.deviceType !== '2in1') { await driver.pressBack(); }
      await (await driver.findComponent(ON.id('devices.grid'))).scrollToTop(); await settle();
      await abilityDelegatorRegistry.getAbilityDelegator().print('UU_SEARCH_QUERY_AFTER_SCROLL ' +
        getInspectorByKey('devices.search') + '\n');
      await present('device.demo-win-01-0.card');
      await present('device.demo-win-01-3.card');
      await absent('device.demo-linux-01-1.card');
      await absent('device.demo-mac-01-2.card');
      await (await driver.findComponent(ON.id('devices.search'))).inputText('no-matching-ui-device', { paste: true }); await settle();
      const empty = await driver.findComponents(ON.text('没有匹配的设备'));
      expect(empty !== null && empty.length === 1).assertTrue();
      const field = await (await driver.findComponent(ON.id('devices.search'))).getBounds();
      const density = display.getDefaultDisplaySync().densityPixels;
      await driver.click(Math.round(field.right - 20 * density), Math.round((field.top + field.bottom) / 2));
      await settle(); await capture('search-cleared');
      if (deviceInfo.deviceType !== '2in1') { await driver.pressBack(); }
      await settle();
      await (await driver.findComponent(ON.id('devices.grid'))).scrollToTop(); await settle();
      await present('devices.search');
      await present('device.demo-linux-01-1.card');
      } finally {
        const searches = await driver.findComponents(ON.id('devices.search'));
        if (searches !== null && searches.length > 0) { await searches[0].clearText(); }
        await route('portmap');
        await mock.listDevices();
      }
    });
    it('scrollbars_follow_the_page_edge_and_auto_hide', 0, async () => {
      await route('devices'); mock.fillDeviceList(); await settle();
      const ui = (await window.getLastWindow(context)).getUIContext();
      const moving: string[] = [];
      const timers: number[] = [];
      const onScroll = (event: uiObserver.ScrollEventInfo): void => {
        if (event.scrollEvent === uiObserver.ScrollEventType.SCROLL_START) {
          timers.push(setTimeout(() => { moving.push(scrollbarVisibility('devices.grid')); }, 60));
        }
      };
      ui.getUIObserver().on('scrollEvent', { id: 'devices.grid' }, onScroll);
      try {
        const initial = scrollbarVisibility('devices.grid');
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_SCROLLBAR_INITIAL ' + initial + '\n');
        expect(initial).assertEqual('Visibility.Hidden');
        const grid = await (await driver.findComponent(ON.id('devices.grid'))).getBounds();
        const x = Math.round((grid.left + grid.right) / 2);
        const height = grid.bottom - grid.top;
        await driver.swipe(x, Math.round(grid.top + height * 0.7), x, Math.round(grid.top + height * 0.3), 6000);
        await capture('scrollbar-moving');
        const win = await window.getLastWindow(context);
        const measured = UiProbe.measure(win.getUIContext(), ['devices.grid', 'devices.grid.scrollbar']);
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_SCROLLBAR_BOUNDS ' + JSON.stringify(measured) + '\n');
        await new Promise<void>((resolve) => { setTimeout(resolve, 3500); });
        await capture('scrollbar-idle');
        const idle = scrollbarVisibility('devices.grid');
        await abilityDelegatorRegistry.getAbilityDelegator().print('UU_SCROLLBAR_VISIBILITY ' + JSON.stringify({ moving: moving, idle: idle }) + '\n');
        expect(moving.includes('Visibility.Visible')).assertTrue();
        expect(idle).assertEqual('Visibility.Hidden');
        await generalSettings();
        expect(scrollbarVisibility('settings.detail.scroll')).assertEqual('Visibility.Hidden');
        await route('portmap');
        expect(scrollbarVisibility('portmap.form.scroll')).assertEqual('Visibility.Hidden');
      } finally {
        ui.getUIObserver().off('scrollEvent', { id: 'devices.grid' }, onScroll);
        timers.forEach((timer: number) => { clearTimeout(timer); });
        await mock.listDevices(); await route('devices');
      }
    });
    it('file_tools_fit_the_window', 0, async () => {
      await mock.selectTarget('demo-win-01'); await route('files');
      await present('files.page'); await present('files.path'); await present('files.list');
      await roundControl('files.upload'); await roundControl('files.mkdir'); await roundControl('files.refresh');
      await buttonSpacing(['files.upload', 'files.mkdir', 'files.refresh']);
      await (await driver.findComponent(ON.id('files.mkdir'))).click(); await settle();
      await present('files.createFolder');
      await (await driver.findComponent(ON.id('files.mkdir'))).click(); await settle();
      await capture('files');
    });
    it('file_transfer_scroll_has_one_visible_identity_and_bounded_layout', 0, async () => {
      await mock.selectTarget('demo-win-01');
      await mock.startTransfer(':/synthetic-transfer.txt', 'mock://transfer', false);
      await route('files');
      const scroll = await driver.findComponents(ON.id('files.transfers.scroll'));
      expect(scroll.length).assertEqual(1);
      const ui = (await window.getLastWindow(context)).getUIContext();
      const pageRect = await (await driver.findComponent(ON.id('files.page'))).getBounds();
      const transferRect = await scroll[0].getBounds();
      const page = [ui.px2vp(pageRect.left), ui.px2vp(pageRect.top),
        ui.px2vp(pageRect.right - pageRect.left), ui.px2vp(pageRect.bottom - pageRect.top)];
      const transfers = [ui.px2vp(transferRect.left), ui.px2vp(transferRect.top),
        ui.px2vp(transferRect.right - transferRect.left), ui.px2vp(transferRect.bottom - transferRect.top)];
      const bp = AppStorage.get<WidthBreakpoint>('currentWidthBreakpoint') ?? WidthBreakpoint.WIDTH_SM;
      await abilityDelegatorRegistry.getAbilityDelegator().print('UU_TRANSFER_SCROLL ' + JSON.stringify({
        breakpoint: bp, page: page, transfers: transfers, matches: scroll.length }) + '\n');
      await capture('file-transfers');
      expect(transfers[2] > 0 && transfers[3] > 0).assertTrue();
      expect(transfers[0] >= page[0] - 1 && transfers[1] >= page[1] - 1).assertTrue();
      expect(transfers[0] + transfers[2] <= page[0] + page[2] + 1).assertTrue();
      expect(transfers[1] + transfers[3] <= page[1] + page[3] + 1).assertTrue();
      if (bp >= WidthBreakpoint.WIDTH_LG) { expect(Math.abs(transfers[2] - 320) <= 1).assertTrue(); }
      else { expect(transfers[3] <= 201).assertTrue(); }
      expect(scrollbarVisibility('files.transfers.scroll')).assertEqual('Visibility.Hidden');
    });
    it('remote_toolbar_buttons_perform_their_actions', 0, async () => {
      await remoteToolbarActions('session');
    });
    it('local_terminal_and_keyboard_controls', 0, async () => {
      await route('terminal'); await terminalReady();
      await present('terminal.page'); await present('terminal.viewport');
      let output: string = '';
      for (let index = 0; index < 150; index++) { output += 'Mock terminal scrollback ' + index + '\r\n'; }
      await mock.terminalWrite(output); await settle();
      await capture('terminal');
      const viewport = await (await driver.findComponent(ON.id('terminal.viewport'))).getBounds();
      const x = Math.round((viewport.left + viewport.right) / 2);
      const height = viewport.bottom - viewport.top;
      if (deviceInfo.deviceType === '2in1') {
        await driver.mouseScroll({ x: x, y: Math.round(viewport.top + height / 2) }, false, 8);
      } else {
        await driver.swipe(x, Math.round(viewport.top + height * 0.3), x, Math.round(viewport.top + height * 0.7), 6000);
      }
      await capture('terminal-scrollbar-moving');
      await new Promise<void>((resolve) => { setTimeout(resolve, 3500); });
      await capture('terminal-scrollbar-idle');
      await roundControl('terminal.new'); await roundControl('terminal.sessions'); await roundControl('terminal.close');
      await buttonSpacing(['terminal.new', 'terminal.sessions', 'terminal.close']);
      mock.fillTerminalSessions(); await settle();
      await (await driver.findComponent(ON.id('terminal.sessions'))).click(); await settle();
      await buttonSpacing(['terminal.attach.1', 'terminal.kill.1']);
      const ui = (await window.getLastWindow(context)).getUIContext();
      const listBounds = UiProbe.measure(ui, ['terminal.sessionList'])[0].bounds;
      const backBounds = UiProbe.measure(ui, ['tool.back'])[0].bounds;
      await abilityDelegatorRegistry.getAbilityDelegator().print('UU_TERMINAL_SESSIONS ' + JSON.stringify({
        list: listBounds, back: backBounds, panel: UiProbe.measure(ui, ['terminal.sessions.panel'])[0].bounds }) + '\n');
      expect(Math.abs(listBounds[1] - backBounds[1] - backBounds[3] - 12) <= 1).assertTrue();
      await capture('terminal-session-button-spacing');
      await (await driver.findComponent(ON.id('terminal.sessions'))).click(); await settle();
    });
    it('tool_form_is_centered_and_stop_all_is_in_the_title_bar', 0, async () => {
      await route('portmap');
      const ui = (await window.getLastWindow(context)).getUIContext();
      const title = UiProbe.measure(ui, ['tool.title'])[0].bounds;
      const stop = UiProbe.measure(ui, ['portmap.stop'])[0].bounds;
      expect(Math.abs((title[1] + title[3] / 2) - (stop[1] + stop[3] / 2)) <= 1).assertTrue();
      expect(await (await driver.findComponent(ON.id('portmap.stop'))).isEnabled()).assertFalse();
      const form = UiProbe.measure(ui, ['portmap.form'])[0].bounds;
      const viewport = UiProbe.measure(ui, ['portmap.form.scroll'])[0].bounds;
      expect(form[2] <= 520).assertTrue();
      expect(Math.abs((form[0] + form[2] / 2) - (viewport[0] + viewport[2] / 2)) <= 1).assertTrue();
      const rule: PortMapRule = { id: 'title-stop', listenAddress: '127.0.0.1', listenPort: 18082,
        targetHost: 'localhost', targetPort: 80, allowLan: false };
      await mock.startPortMap(rule); await settle();
      expect(await (await driver.findComponent(ON.id('portmap.stop'))).isEnabled()).assertTrue();
      await capture('portmap-centered-title-action');
      await (await driver.findComponent(ON.id('portmap.stop'))).click(); await settle();
      expect(mock.portMapSnapshot().rules?.length).assertEqual(0);
    });
    it('terminal_header_blurs_the_content_behind_it', 0, async () => {
      await route('terminal');
      await terminalReady();
      const ui = (await window.getLastWindow(context)).getUIContext();
      const rects = UiProbe.measure(ui, ['tool.back', 'tool.title', 'terminal.viewport']);
      await abilityDelegatorRegistry.getAbilityDelegator().print('UU_TERMINAL_HEADER ' + JSON.stringify(rects) + '\n');
      await capture('terminal-header-ready');
      const back = rects[0].bounds;
      const viewport = rects[2].bounds;
      expect(viewport[1] <= back[1]).assertTrue();
      const page = UiProbe.measure(ui, ['terminal.page'])[0].bounds;
      const win = await window.getLastWindow(context);
      const bottomAvoid = Math.max(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).bottomRect.height,
        win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height);
      const expectedBottom = ui.px2vp(win.getWindowProperties().windowRect.height - bottomAvoid);
      expect(Math.abs(viewport[1] + viewport[3] - expectedBottom) <= 1).assertTrue();
      await abilityDelegatorRegistry.getAbilityDelegator().print('UU_TERMINAL_PAGE ' + JSON.stringify({
        page: page, viewport: viewport, controls: UiProbe.measure(ui, ['terminal.controls'])[0].bounds,
        expectedBottom: expectedBottom }) + '\n');
      expect(await (await driver.findComponent(ON.id('terminal.key.esc'))).isEnabled()).assertTrue();
      let output: string = '';
      for (let index = 0; index < 150; index++) {
        output += '\u001b[' + (index % 2 === 0 ? '44' : '42') + 'mHeader scrollback ' + index + '  Aa 123\u001b[0m\r\n';
      }
      await mock.terminalWrite(output);
      await settle();
      await capture('terminal-header-immersive');
      const bounds = await (await driver.findComponent(ON.id('terminal.viewport'))).getBounds();
      const x = Math.round((bounds.left + bounds.right) / 2);
      const height = bounds.bottom - bounds.top;
      if (deviceInfo.deviceType === '2in1') {
        await driver.mouseScroll({ x: x, y: Math.round(bounds.top + height / 2) }, false, 8);
      } else {
        await driver.swipe(x, Math.round(bounds.top + height * 0.3), x, Math.round(bounds.top + height * 0.7), 6000);
      }
      await settle();
      await capture('terminal-header-scrolled');
    });
    it('terminal_shortcuts_float_and_follow_control_preferences', 0, async () => {
      const settings = mock.settings();
      const smartReach = settings.smartReachEnabled;
      const original = settings.controlBarPosition;
      const ids = ['terminal.key.esc', 'terminal.key.tab', 'terminal.key.interrupt', 'terminal.key.up', 'terminal.key.down'];
      try {
        await mock.setSmartReachEnabled(false);
        for (const position of ['left', 'center', 'right'] as ControlBarPosition[]) {
          await route('devices'); await mock.setControlBarPosition(position); await route('terminal'); await terminalReady();
          const ui = (await window.getLastWindow(context)).getUIContext();
          const page = UiProbe.measure(ui, ['terminal.canvas'])[0].bounds;
          const controls = UiProbe.measure(ui, ['terminal.controls'])[0].bounds;
          expect(Math.abs(page[1] + page[3] - controls[1] - controls[3] - 16) <= 1).assertTrue();
          if (position === 'left') { expect(Math.abs(controls[0] - page[0] - 16) <= 1).assertTrue(); }
          else if (position === 'right') { expect(Math.abs(page[0] + page[2] - controls[0] - controls[2] - 16) <= 1).assertTrue(); }
          else { expect(Math.abs((controls[0] + controls[2] / 2) - (page[0] + page[2] / 2)) <= 1).assertTrue(); }
          await buttonSpacing(ids);
          for (const id of ids) { await present(id); }
          await roundControl(ids[0]); await roundControl(ids[1]); await roundControl(ids[3]); await roundControl(ids[4]);
          mock.terminalInputs = [];
          for (const id of ids) { await (await driver.findComponent(ON.id(id))).click(); await settle(); }
          expect(mock.terminalInputs.join('|')).assertEqual(['\u001b', '\t', '\u0003', '\u001b[A', '\u001b[B'].join('|'));
          await capture('terminal-floating-' + position);
        }
        await route('devices'); await mock.setSmartReachEnabled(true); await mock.setControlBarPosition('right');
        await route('terminal'); await terminalReady();
        const ui = (await window.getLastWindow(context)).getUIContext();
        const page = UiProbe.measure(ui, ['terminal.canvas'])[0].bounds;
        const controls = UiProbe.measure(ui, ['terminal.controls'])[0].bounds;
        expect(Math.abs((controls[0] + controls[2] / 2) - (page[0] + page[2] / 2)) <= 1).assertTrue();
      } finally {
        await route('devices'); await mock.setSmartReachEnabled(smartReach); await mock.setControlBarPosition(original);
      }
    });
    it('port_mapping_keeps_independent_rules', 0, async () => {
      const a: PortMapRule = { id: 'regression-a', listenAddress: '127.0.0.1', listenPort: 18080, targetHost: 'localhost', targetPort: 80, allowLan: false };
      const b: PortMapRule = { id: 'regression-b', listenAddress: '127.0.0.1', listenPort: 18081, targetHost: 'localhost', targetPort: 81, allowLan: false };
      await mock.startPortMap(a); await mock.startPortMap(b); await route('portmap');
      expect(mock.portMapSnapshot().rules?.length).assertEqual(2);
      await present('portmap.page'); await present('portmap.stop.regression-a'); await capture('portmap');
      await mock.stopPortMap('regression-a');
      expect(mock.portMapSnapshot().rules?.length).assertEqual(1);
      expect(mock.portMapSnapshot().rules?.[0].id).assertEqual('regression-b');
      await mock.stopPortMap();
    });
    it('session_keeps_screen_on_and_restores_window_setting', 0, async () => {
      await route('devices');
      const win = await window.getLastWindow(context);
      const original = win.getWindowProperties().isKeepScreenOn;
      const preference = mock.settings().keepScreenOn;
      try {
        await win.setWindowKeepScreenOn(false);
        await mock.setKeepScreenOn(true); await mock.connect('demo-win-01');
        await route('session'); mock.emitFirstFrame(); await settle();
        expect(win.getWindowProperties().isKeepScreenOn).assertTrue();
        await route('files'); await settle();
        expect(win.getWindowProperties().isKeepScreenOn).assertFalse();
      } finally {
        await route('devices'); mock.disconnect(); await mock.setKeepScreenOn(preference);
        await win.setWindowKeepScreenOn(original);
      }
    });
    if (deviceInfo.deviceType === '2in1') {
      it('pc_window_resize_reflows_layout', 0, async () => {
        const win = await driver.findWindow({ bundleName: 'com.uu.remote.harmony' });
        const density = display.getDefaultDisplaySync().densityPixels;
        if (await win.getWindowMode() !== WindowMode.FLOATING) { await win.resume(); }
        await win.resize(Math.round(1100 * density), Math.round(760 * density), ResizeDirection.RIGHT_DOWN); await route('devices');
        const wide = await win.getBounds();
        expect(Math.abs((wide.right - wide.left) / density - 1100) < 3).assertTrue();
        await present('devices.search'); await capture('pc-wide');
        await floatingTabs();
        await route('settings');
        await present('settings.groups'); await present('settings.detail.scroll'); await capture('pc-settings-split');
        const groups = await (await driver.findComponent(ON.id('settings.groups'))).getBounds();
        const detail = await (await driver.findComponent(ON.id('settings.detail.scroll'))).getBounds();
        expect(detail.left >= groups.right).assertTrue();
        await route('devices'); mock.fillDeviceList(); await settle();
        const grid = await (await driver.findComponent(ON.id('devices.grid'))).getBounds();
        await driver.swipe(Math.round((grid.left + grid.right) / 2), Math.round(grid.top + (grid.bottom - grid.top) * 0.7),
          Math.round((grid.left + grid.right) / 2), Math.round(grid.top + (grid.bottom - grid.top) * 0.3), 1000); await settle();
        await (await driver.findComponent(ON.id('devices.search.open'))).click(); await settle();
        await win.resize(Math.round(620 * density), Math.round(760 * density), ResizeDirection.RIGHT_DOWN); await settle();
        const narrow = await win.getBounds();
        expect(Math.abs((narrow.right - narrow.left) / density - 620) < 3).assertTrue();
        await present('devices.search'); await capture('pc-narrow');
        const search = await (await driver.findComponent(ON.id('devices.search'))).getBounds();
        const refresh = await (await driver.findComponent(ON.id('devices.refresh'))).getBounds();
        expect(Math.abs(search.top - refresh.top) <= 2).assertTrue();
        expect(search.right < refresh.left && refresh.left - search.right < 20 * density).assertTrue();
        await floatingTabs();
        await mock.listDevices();
      });
      it('pc_session_resize_keeps_dragged_virtual_mouse_in_bounds', 0, async () => {
        const win = await driver.findWindow({ bundleName: 'com.uu.remote.harmony' });
        const original = await win.getBounds();
        const density = display.getDefaultDisplaySync().densityPixels;
        try {
          if (await win.getWindowMode() !== WindowMode.FLOATING) { await win.resume(); }
          await win.resize(Math.round(900 * density), Math.round(700 * density), ResizeDirection.RIGHT_DOWN);
          await mock.listDevices(); await mock.connect('demo-win-01'); await route('session'); mock.emitFirstFrame(); await settle();
          const initial = await (await driver.findComponent(ON.id('session.mouse.collapsed'))).getBounds();
          await driver.swipe(Math.round((initial.left + initial.right) / 2), Math.round((initial.top + initial.bottom) / 2),
            Math.round((initial.left + initial.right) / 2 - 320 * density),
            Math.round((initial.top + initial.bottom) / 2 - 24 * density), 600); await settle();
          const dragged = await (await driver.findComponent(ON.id('session.mouse.collapsed'))).getBounds();
          const originalSurface = await (await driver.findComponent(ON.id('session.surface'))).getBounds();
          await win.resize(Math.round(620 * density), Math.round(500 * density), ResizeDirection.RIGHT_DOWN); await settle();
          const mouse = await (await driver.findComponent(ON.id('session.mouse.collapsed'))).getBounds();
          const surface = await (await driver.findComponent(ON.id('session.surface'))).getBounds();
          expect(Math.abs((mouse.left - surface.left) - (dragged.left - originalSurface.left)) <= 2).assertTrue();
          expect(mouse.left >= surface.left && mouse.right <= surface.right && mouse.top >= surface.top && mouse.bottom <= surface.bottom).assertTrue();
          await capture('pc-session-virtual-mouse-resize');
        } finally {
          await mock.disconnect(); await route('devices');
          await win.resize(original.right - original.left, original.bottom - original.top, ResizeDirection.RIGHT_DOWN); await settle();
        }
      });
    }
    if (deviceInfo.deviceType !== '2in1') {
      it('session_rotation_button_and_orientation_restore', 0, async () => {
        const win = await window.getLastWindow(context);
        const orientation = win.getPreferredOrientation();
        try {
          await win.setPreferredOrientation(window.Orientation.PORTRAIT);
          await mock.connect('demo-win-01'); await route('session'); mock.emitFirstFrame(); await settle();
          const rotate = await driver.findComponent(ON.id('session.rotate'));
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_ROTATION_MEASUREMENT ' + JSON.stringify({
            status: win.getWindowStatus(), preferred: win.getPreferredOrientation(), enabled: await rotate.isEnabled(),
            rect: win.getWindowProperties().windowRect }) + '\n');
          expect(await rotate.isEnabled()).assertTrue();
          const mouseBefore = await (await driver.findComponent(ON.id('session.mouse.collapsed'))).getBounds();
          const density = display.getDefaultDisplaySync().densityPixels;
          await driver.swipe(Math.round((mouseBefore.left + mouseBefore.right) / 2), Math.round((mouseBefore.top + mouseBefore.bottom) / 2),
            Math.round((mouseBefore.left + mouseBefore.right) / 2 - 40 * density),
            Math.round((mouseBefore.top + mouseBefore.bottom) / 2 - 24 * density), 600); await settle();
          const dragged = await (await driver.findComponent(ON.id('session.mouse.collapsed'))).getBounds();
          const originalSurface = await (await driver.findComponent(ON.id('session.surface'))).getBounds();
          await rotate.click(); await settle();
          expect(win.getPreferredOrientation()).assertEqual(window.Orientation.USER_ROTATION_LANDSCAPE);
          let bounds = await (await driver.findComponent(ON.id('session.page'))).getBounds();
          expect(bounds.right - bounds.left > bounds.bottom - bounds.top).assertTrue();
          let mouse = await (await driver.findComponent(ON.id('session.mouse.collapsed'))).getBounds();
          let surface = await (await driver.findComponent(ON.id('session.surface'))).getBounds();
          expect(Math.abs((mouse.left - surface.left) - (dragged.left - originalSurface.left)) <= 2).assertTrue();
          expect(mouse.left >= surface.left && mouse.right <= surface.right && mouse.top >= surface.top && mouse.bottom <= surface.bottom).assertTrue();
          await capture('session-rotate-landscape');
          await (await driver.findComponent(ON.id('session.rotate'))).click(); await settle();
          expect(win.getPreferredOrientation()).assertEqual(window.Orientation.USER_ROTATION_PORTRAIT);
          bounds = await (await driver.findComponent(ON.id('session.page'))).getBounds();
          expect(bounds.right - bounds.left < bounds.bottom - bounds.top).assertTrue();
          mouse = await (await driver.findComponent(ON.id('session.mouse.collapsed'))).getBounds();
          surface = await (await driver.findComponent(ON.id('session.surface'))).getBounds();
          expect(Math.abs((mouse.left - surface.left) - (dragged.left - originalSurface.left)) <= 2).assertTrue();
          await capture('session-rotate-portrait');
          await (await driver.findComponent(ON.id('session.keyboard'))).click(); await settle();
          await present('session.text.input');
          await (await driver.findComponent(ON.id('session.rotate'))).click(); await settle();
          await absent('session.text.input');
          expect(win.getPreferredOrientation()).assertEqual(window.Orientation.USER_ROTATION_LANDSCAPE);
          await route('devices'); await settle();
          expect(win.getPreferredOrientation()).assertEqual(window.Orientation.PORTRAIT);
          bounds = await (await driver.findComponent(ON.id('app.shell'))).getBounds();
          expect(bounds.right - bounds.left < bounds.bottom - bounds.top).assertTrue();
          await capture('session-rotation-restored');
        } finally { await route('devices'); mock.disconnect(); await win.setPreferredOrientation(orientation); await settle(); }
      });
    }
    if (deviceInfo.deviceType === 'phone') {
      it('phone_rotation_preserves_floating_tabs', 0, async () => {
        const win = await window.getLastWindow(context);
        const orientation = await win.getPreferredOrientation();
        const rotation = await driver.getDisplayRotation();
        try {
          const properties = win.getWindowProperties();
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_WINDOW_TARGET ' + JSON.stringify({
            type: properties.type, rect: properties.windowRect,
            preferred: orientation, rotation: rotation, ability: context.abilityInfo.name }) + '\n');
          await win.setPreferredOrientation(window.Orientation.LANDSCAPE);
          await driver.setDisplayRotationEnabled(true); await driver.setDisplayRotation(DisplayRotation.ROTATION_90);
          await route('devices'); await settle();
          const bounds = await (await driver.findComponent(ON.id('app.shell'))).getBounds();
          await abilityDelegatorRegistry.getAbilityDelegator().print('UU_ORIENTATION_RESULT ' + JSON.stringify({
            bounds: bounds, rect: win.getWindowProperties().windowRect, preferred: await win.getPreferredOrientation(),
            rotation: await driver.getDisplayRotation() }) + '\n');
          expect(bounds.right - bounds.left > bounds.bottom - bounds.top).assertTrue();
          await floatingTabs(); await capture('phone-landscape');
          await remoteToolbarActions('landscape');
        } finally {
          await driver.setDisplayRotation(rotation); await win.setPreferredOrientation(orientation); await settle();
        }
      });
    }
  });
}
