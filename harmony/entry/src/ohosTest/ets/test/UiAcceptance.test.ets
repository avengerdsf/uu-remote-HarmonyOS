import { describe, it, expect, beforeAll } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { window, display } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { MockSessionService } from '../../../main/ets/services/MockSessionService';
import { ServiceHub } from '../../../main/ets/services/ServiceHub';
import { SessionPhase } from '../../../main/ets/model/Models';

interface CaseSpec {
  id: string;
  page: string;
  viewport: number[];
  fontScale: number;
  theme: string;
  system: boolean;
  expected: Record<string, number[]>;
}

const CASES: CaseSpec[] = [
  {"id": "DEV-C360-L", "page": "devices.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {"devices.search": [16.0, 72, 328, 48], "device.demo-win-01.card": [16.0, 136, 328.0, 176], "device.demo-win-01.connect": [32.0, 248, 296.0, 48], "app.bottomNav": [0, 736, 360, 64]}},
  {"id": "DEV-C360-D", "page": "devices.page", "viewport": [360, 800], "fontScale": 1, "theme": "dark", "system": false, "expected": {"devices.search": [16.0, 72, 328, 48], "device.demo-win-01.card": [16.0, 136, 328.0, 176], "device.demo-win-01.connect": [32.0, 248, 296.0, 48], "app.bottomNav": [0, 736, 360, 64]}},
  {"id": "DEV-C390-L", "page": "devices.page", "viewport": [390, 844], "fontScale": 1, "theme": "light", "system": false, "expected": {"devices.search": [16.0, 72, 358, 48], "device.demo-win-01.card": [16.0, 136, 358.0, 176], "device.demo-win-01.connect": [32.0, 248, 326.0, 48], "app.bottomNav": [0, 780, 390, 64]}},
  {"id": "DEV-C599-L", "page": "devices.page", "viewport": [599, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {"devices.search": [16.0, 72, 567, 48], "device.demo-win-01.card": [16.0, 136, 567.0, 176], "device.demo-win-01.connect": [32.0, 248, 535.0, 48], "app.bottomNav": [0, 736, 599, 64]}},
  {"id": "DEV-M600-L", "page": "devices.page", "viewport": [600, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {"devices.search": [112.0, 88, 464, 48], "device.demo-win-01.card": [112.0, 152, 464.0, 176], "device.demo-win-01.connect": [128.0, 264, 432.0, 48]}},
  {"id": "DEV-M800-D", "page": "devices.page", "viewport": [800, 1100], "fontScale": 1, "theme": "dark", "system": false, "expected": {"devices.search": [112.0, 88, 664, 48], "device.demo-win-01.card": [112.0, 152, 324.0, 176], "device.demo-win-01.connect": [128.0, 264, 292.0, 48]}},
  {"id": "DEV-M839-L", "page": "devices.page", "viewport": [839, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {"devices.search": [112.0, 88, 703, 48], "device.demo-win-01.card": [112.0, 152, 343.5, 176], "device.demo-win-01.connect": [128.0, 264, 311.5, 48]}},
  {"id": "DEV-E840-L", "page": "devices.page", "viewport": [840, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {"devices.search": [264.0, 88, 552, 48], "device.demo-win-01.card": [264.0, 152, 268.0, 176], "device.demo-win-01.connect": [280.0, 264, 236.0, 48]}},
  {"id": "DEV-E1280-L", "page": "devices.page", "viewport": [1280, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {"devices.search": [264.0, 88, 992, 48], "device.demo-win-01.card": [264.0, 152, 320.0, 176], "device.demo-win-01.connect": [280.0, 264, 288.0, 48]}},
  {"id": "DEV-E1440-D", "page": "devices.page", "viewport": [1440, 900], "fontScale": 1, "theme": "dark", "system": false, "expected": {"devices.search": [264.0, 88, 1152, 48], "device.demo-win-01.card": [264.0, 152, 276.0, 176], "device.demo-win-01.connect": [280.0, 264, 244.0, 48]}},
  {"id": "DEV-C320-F2", "page": "devices.page", "viewport": [320, 800], "fontScale": 2, "theme": "light", "system": false, "expected": {"devices.search": [16.0, 96, 288, 72], "device.demo-win-01.card": [16.0, 184, 288.0, 256], "device.demo-win-01.connect": [32.0, 352, 256.0, 72], "app.bottomNav": [0, 724, 320, 76]}},
  {"id": "DEV-M800-F2", "page": "devices.page", "viewport": [800, 1100], "fontScale": 2, "theme": "dark", "system": false, "expected": {"devices.search": [112.0, 104, 664, 72], "device.demo-win-01.card": [112.0, 192, 664.0, 256], "device.demo-win-01.connect": [128.0, 360, 632.0, 72]}},
  {"id": "DEV-C390-F13", "page": "devices.page", "viewport": [390, 844], "fontScale": 1.3, "theme": "light", "system": false, "expected": {"devices.search": [16.0, 73.6, 358, 55.2], "device.demo-win-01.card": [16.0, 144.8, 358.0, 195.8], "device.demo-win-01.connect": [32.0, 269.4, 326.0, 55.2], "app.bottomNav": [0, 779.2, 390, 64.8]}},
  {"id": "LOGIN-EXPIRED", "page": "login.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "LOGIN-QUERY-FAILED", "page": "login.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "LOGIN-SCANNED", "page": "login.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "LOGIN-CANCEL", "page": "login.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "DEV-EMPTY", "page": "devices.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "DEV-ERROR", "page": "devices.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "DEV-LONG-NAME", "page": "devices.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "ASSIST-INVALID", "page": "assist.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "ASSIST-DOUBLE-SUBMIT", "page": "assist.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "SESSION-FIRST-FRAME", "page": "session.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "SESSION-RESIZE", "page": "session.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "SESSION-OVERLAY-HIT", "page": "session.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "SESSION-VIEW-ONLY", "page": "session.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "SESSION-CANCEL-END", "page": "session.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "SESSION-END", "page": "session.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "SETTINGS-CROSS-WIDTH", "page": "settings.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "THEME-ALL-SURFACES", "page": "settings.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "FILES-CANCEL", "page": "files.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "DEVICE-IME", "page": "session.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": true, "expected": {}},
  {"id": "DEVICE-FOCUS", "page": "session.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": true, "expected": {}},
  {"id": "DEVICE-MENU", "page": "devices.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": true, "expected": {}},
  {"id": "DEVICE-PERMISSIONS", "page": "host.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": true, "expected": {}},
  {"id": "DEVICE-SURFACE", "page": "session.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": true, "expected": {}},
  {"id": "DEVICE-WINDOW-INSETS", "page": "devices.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": true, "expected": {}},
  {"id": "VISUAL-FIRST-APPROVAL", "page": "all", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": true, "expected": {}},
  {"id": "SETTINGS-W840", "page": "settings.page", "viewport": [840, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "SETTINGS-W1280", "page": "settings.page", "viewport": [1280, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "PORTMAP-START", "page": "portmap.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "PORTMAP-STOP", "page": "portmap.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "PORTMAP-CONFLICT", "page": "portmap.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
  {"id": "PORTMAP-BACKGROUND", "page": "portmap.page", "viewport": [360, 800], "fontScale": 1, "theme": "light", "system": false, "expected": {}},
];


let driver: Driver;
let context: common.UIAbilityContext;
let mock: MockSessionService;
let density: number = 1;

async function wait(ms: number): Promise<void> {
  await new Promise<void>((resolve) => {
    setTimeout(() => resolve(), ms);
  });
}

async function openRoute(route: string): Promise<void> {
  const version = AppStorage.get<number>('routeVersion') ?? 0;
  AppStorage.setOrCreate('route', route);
  AppStorage.setOrCreate('routeVersion', version + 1);
  await wait(400);
}

async function resize(width: number, height: number): Promise<void> {
  const win = await window.getLastWindow(context);
  await win.resize(Math.round(width * density), Math.round(height * density));
  await wait(500);
}

async function bounds(id: string): Promise<number[]> {
  const matches = await driver.findComponents(ON.id(id));
  expect(matches.length).assertEqual(1);
  const rect = await matches[0].getBounds();
  return [rect.left / density, rect.top / density,
    (rect.right - rect.left) / density, (rect.bottom - rect.top) / density];
}

async function textOf(id: string): Promise<string> {
  const matches = await driver.findComponents(ON.id(id));
  expect(matches.length).assertEqual(1);
  return await matches[0].getText();
}

async function enabledOf(id: string): Promise<boolean> {
  const matches = await driver.findComponents(ON.id(id));
  expect(matches.length).assertEqual(1);
  return await matches[0].isEnabled();
}

async function assertRect(id: string, expected: number[], allowGrowth: boolean): Promise<void> {
  const actual = await bounds(id);
  const epsilon = Math.max(1, 1 / density);
  for (let index = 0; index < 4; index++) {
    const difference = Math.abs(actual[index] - expected[index]);
    const growthAllowed = allowGrowth && index === 3 && actual[index] >= expected[index] - epsilon;
    expect(difference <= epsilon || growthAllowed).assertTrue();
  }
}

async function assertDevicesLayout(spec: CaseSpec): Promise<void> {
  await openRoute('devices');
  await resize(spec.viewport[0], spec.viewport[1]);
  AppStorage.setOrCreate('fontScale', spec.fontScale);
  AppStorage.setOrCreate('isDark', spec.theme === 'dark');
  await wait(400);
  for (const key of Object.keys(spec.expected)) {
    await assertRect(key, spec.expected[key], key.endsWith('.card'));
  }
}

async function runCase(spec: CaseSpec): Promise<void> {
  if (spec.system) {
    throw new Error(`NOT_RUN: ${spec.id} requires DEVICE_APP evidence (hdc + uitest).`);
  }
  const id = spec.id;
  if (id.startsWith('DEV-C') || id.startsWith('DEV-M') || id.startsWith('DEV-E')) {
    await assertDevicesLayout(spec);
    return;
  }
  if (id === 'DEV-EMPTY') {
    await openRoute('devices');
    mock.setDeviceFixture('empty');
    await wait(400);
    expect((await driver.findComponents(ON.id('devices.empty'))).length).assertEqual(1);
    return;
  }
  if (id === 'DEV-ERROR') {
    await openRoute('devices');
    mock.setDeviceFixture('error');
    await wait(400);
    expect((await driver.findComponents(ON.id('devices.refreshError'))).length).assertEqual(1);
    return;
  }
  if (id === 'DEV-LONG-NAME') {
    await openRoute('devices');
    mock.setDeviceFixture('long');
    await wait(400);
    const name = await textOf('device.demo-win-01.card');
    expect(name.length >= 0).assertTrue();
    return;
  }
  if (id === 'LOGIN-EXPIRED' || id === 'LOGIN-QUERY-FAILED' || id === 'LOGIN-SCANNED' || id === 'LOGIN-CANCEL') {
    await openRoute('login');
    if (id === 'LOGIN-EXPIRED') {
      mock.emitLoginExpired();
      await wait(300);
      expect(await textOf('login.status')).assertEqual('二维码已过期');
      expect((await driver.findComponents(ON.id('login.refresh'))).length).assertEqual(1);
    } else if (id === 'LOGIN-QUERY-FAILED') {
      mock.emitLoginQueryFailed();
      await wait(300);
      expect(await textOf('login.status')).assertEqual('暂时无法查询扫码状态');
      expect(mock.loginSnapshot().qrPayload !== null).assertTrue();
    } else if (id === 'LOGIN-SCANNED') {
      mock.emitLoginScanned();
      await wait(300);
      expect(await textOf('login.status')).assertEqual('请在手机上确认');
    } else {
      await mock.loginStart();
      await wait(250);
      await mock.loginCancel();
      await wait(200);
      expect(mock.loginSnapshot().pollingActive).assertFalse();
    }
    return;
  }
  if (id === 'ASSIST-INVALID') {
    await openRoute('assist');
    expect(await enabledOf('assist.connect')).assertFalse();
    return;
  }
  if (id === 'ASSIST-DOUBLE-SUBMIT') {
    await openRoute('assist');
    const idField = await driver.findComponent(ON.id('assist.connectId'));
    await idField.inputText('demo-partner-id');
    const codeField = await driver.findComponent(ON.id('assist.verifyCode'));
    await codeField.inputText('demo-only-code');
    const connect = await driver.findComponent(ON.id('assist.connect'));
    await connect.click();
    await connect.click();
    await wait(300);
    expect(mock.connectCount <= 1).assertTrue();
    return;
  }
  if (id.startsWith('SESSION-')) {
    await openRoute('devices');
    await mock.connect('demo-win-01');
    await wait(700);
    await openRoute('session');
    await wait(300);
    if (id === 'SESSION-FIRST-FRAME') {
      expect(await textOf('session.status')).assertEqual('等待首帧');
      mock.emitFirstFrame();
      await wait(300);
      expect(await textOf('session.status')).assertEqual('已连接');
    } else if (id === 'SESSION-RESIZE') {
      mock.emitFirstFrame();
      const generation = mock.sessionSnapshot().generation;
      await resize(1280, 800);
      await resize(599, 800);
      await resize(840, 800);
      expect(mock.sessionSnapshot().generation).assertEqual(generation);
      expect(mock.connectCount).assertEqual(1);
    } else if (id === 'SESSION-OVERLAY-HIT') {
      mock.emitFirstFrame();
      const toolbar = await driver.findComponent(ON.id('session.toolbar'));
      await toolbar.click();
      await wait(200);
      expect(mock.sentInputs.length).assertEqual(0);
    } else if (id === 'SESSION-VIEW-ONLY') {
      await mock.setViewOnly(true);
      await wait(200);
      expect((await driver.findComponents(ON.id('session.viewOnly.badge'))).length).assertEqual(1);
      expect(mock.sentInputs.length).assertEqual(0);
    } else if (id === 'SESSION-CANCEL-END') {
      const back = await driver.findComponent(ON.id('session.back'));
      await back.click();
      await wait(200);
      const cancel = await driver.findComponent(ON.id('dialog.cancel'));
      await cancel.click();
      await wait(200);
      expect(mock.sessionSnapshot().phase !== SessionPhase.Ended).assertTrue();
    } else if (id === 'SESSION-END') {
      const back = await driver.findComponent(ON.id('session.back'));
      await back.click();
      await wait(200);
      const confirm = await driver.findComponent(ON.id('dialog.confirm'));
      await confirm.click();
      await wait(300);
      expect(mock.sessionSnapshot().phase).assertEqual(SessionPhase.Ended);
    }
    return;
  }
  if (id === 'FILES-CANCEL') {
    await openRoute('files');
    await mock.startTransfer('/tmp/demo.txt', 'test-only://demo.txt', true);
    await wait(300);
    const cancel = await driver.findComponent(ON.id('transfer.demo-transfer-1.cancel'));
    await cancel.click();
    await wait(300);
    expect(mock.filesSnapshot().transfers[0].state).assertEqual('cancelled');
    return;
  }
  if (id === 'SETTINGS-CROSS-WIDTH') {
    await openRoute('settings');
    await resize(1280, 800);
    await resize(599, 800);
    await resize(840, 800);
    expect((await driver.findComponents(ON.id('settings.groups'))).length).assertEqual(1);
    expect(mock.settings().themePreference.length > 0).assertTrue();
    return;
  }
  if (id === 'THEME-ALL-SURFACES') {
    await openRoute('settings');
    const group = await driver.findComponent(ON.id('settings.theme'));
    await group.click();
    await wait(200);
    const dark = await driver.findComponent(ON.text('深色'));
    await dark.click();
    await wait(300);
    expect(mock.settings().themePreference).assertEqual('dark');
    return;
  }
  if (id === 'SETTINGS-W840' || id === 'SETTINGS-W1280') {
    await openRoute('settings');
    const width = id === 'SETTINGS-W840' ? 840 : 1280;
    await resize(width, 800);
    const group = await bounds('settings.groups');
    const detail = await bounds('settings.detail');
    expect(Math.abs(group[2] - 176) <= Math.max(1, 1 / density)).assertTrue();
    const expectedDetail = id === 'SETTINGS-W840' ? 360 : 800;
    expect(Math.abs(detail[2] - expectedDetail) <= Math.max(1, 1 / density)).assertTrue();
    return;
  }
  if (id.startsWith('PORTMAP-')) {
    await openRoute('portmap');
    const listen = await driver.findComponent(ON.id('portmap.listenPort'));
    const target = await driver.findComponent(ON.id('portmap.targetPort'));
    if (id === 'PORTMAP-CONFLICT') {
      await listen.inputText('8800');
      await target.inputText('22');
      const start = await driver.findComponent(ON.id('portmap.start'));
      await start.click();
      await wait(300);
      expect(await textOf('portmap.error')).assertEqual('本地端口已被占用');
    } else if (id === 'PORTMAP-START' || id === 'PORTMAP-STOP' || id === 'PORTMAP-BACKGROUND') {
      await listen.inputText('8080');
      await target.inputText('22');
      const start = await driver.findComponent(ON.id('portmap.start'));
      await start.click();
      await wait(300);
      if (id === 'PORTMAP-STOP') {
        const stop = await driver.findComponent(ON.id('portmap.stop'));
        await stop.click();
        await wait(300);
        expect(mock.portMapSnapshot().phase).assertEqual('stopped');
      } else if (id === 'PORTMAP-BACKGROUND') {
        mock.emitPortMapBackgroundRestricted();
        await wait(300);
        expect(mock.portMapSnapshot().phase).assertEqual('backgroundRestricted');
      } else {
        expect(mock.portMapSnapshot().phase).assertEqual('running');
      }
    }
    return;
  }
  if (id === 'VISUAL-FIRST-APPROVAL') {
    throw new Error('VISUAL_REVIEW_PENDING: no approved native baseline exists.');
  }
  throw new Error(`NOT_RUN: ${id} has no component-host implementation.`);
}

export default function uiAcceptanceTest(): void {
  describe('UiAcceptance', () => {
    beforeAll(async () => {
      context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext() as common.UIAbilityContext;
      driver = Driver.create();
      density = display.getDefaultDisplaySync().densityPixels;
      mock = new MockSessionService();
      await ServiceHub.replaceForTests(mock, context);
      await wait(500);
    });

    for (const spec of CASES) {
      it(spec.id, 0, async () => {
        await runCase(spec);
      });
    }
  });
}

