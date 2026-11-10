import { tr } from '../model/I18n';
import { common } from '@kit.AbilityKit';
import {
  ClipboardPolicy,
  DeviceInfo,
  DeviceListPhase,
  DevicesSnapshot,
  FilesSnapshot,
  HostSnapshot,
  LoginPhase,
  LoginSnapshot,
  PortMapRule,
  PortMapSnapshot,
  SessionPhase,
  SessionSnapshot,
  TerminalSnapshot,
  ThemePreference,
  TouchMode,
  VideoQuality
} from '../model/Models';
import { Router } from '../model/Router';
import { Fixtures } from '../testkit/Fixtures';
import { BaseSessionService } from './BaseSessionService';

export type DeviceFixture = 'default' | 'empty' | 'error' | 'long';
export type HostScope = 'pc' | 'tablet' | 'phone';

/**
 * Deterministic test double. It implements the same interface and state shapes as
 * the native service and is only instantiated in debug builds or tests.
 */
export class MockSessionService extends BaseSessionService {
  readonly kind: string = 'mock';

  private deviceFixture: DeviceFixture = 'default';
  private hostScope: HostScope = 'pc';
  private loginTimer: number = -1;
  private connectTimer1: number = -1;
  private connectTimer2: number = -1;
  private terminalTimer: number = -1;
  private hostTimer: number = -1;
  sentInputs: string[] = [];
  sentTexts: string[] = [];
  releaseCount: number = 0;
  connectCount: number = 0;
  attachCount: number = 0;
  detachCount: number = 0;
  audioMuteCalls: number = 0;
  audioMutedForTest: boolean = false;

  async init(context: common.UIAbilityContext): Promise<void> {
    this.publishTouchMode();
    this.login = {
      phase: LoginPhase.WaitingScan,
      statusText: tr('请扫码登录'),
      qrPayload: Fixtures.QR_PAYLOAD,
      pollingActive: true,
      authenticated: true,
      error: null,
      generation: 1
    };
    this.devices = {
      phase: DeviceListPhase.Ready,
      devices: this.sortedDevices(Fixtures.devices()),
      error: null,
      generation: 1
    };
    this.emitLogin();
    this.emitDevices();
    this.host = {
      phase: 'unsupported',
      capabilities: {
        capture: true,
        inputInjection: false,
        background: false,
        inputScope: 'pc',
        reason: tr('需要用户授权后才能控制本机')
      },
      statusText: tr('未开启共享')
    };
    this.emitHost();
  }

  dispose(): void {
    if (this.loginTimer >= 0) {
      clearTimeout(this.loginTimer);
    }
    if (this.connectTimer1 >= 0) {
      clearTimeout(this.connectTimer1);
    }
    if (this.connectTimer2 >= 0) {
      clearTimeout(this.connectTimer2);
    }
    if (this.terminalTimer >= 0) {
      clearTimeout(this.terminalTimer);
    }
    if (this.hostTimer >= 0) {
      clearTimeout(this.hostTimer);
    }
  }

  // ---- snapshot cloning ----------------------------------------------------

  private copyLogin(): LoginSnapshot {
    const value = this.login;
    return {
      phase: value.phase,
      statusText: value.statusText,
      qrPayload: value.qrPayload,
      pollingActive: value.pollingActive,
      authenticated: value.authenticated,
      error: value.error,
      generation: value.generation
    };
  }

  private copyDevices(): DevicesSnapshot {
    const value = this.devices;
    return {
      phase: value.phase,
      devices: value.devices.slice(),
      error: value.error,
      generation: value.generation
    };
  }

  private copySession(): SessionSnapshot {
    const value = this.session;
    return {
      phase: value.phase,
      sessionId: value.sessionId,
      generation: value.generation,
      resourceEpoch: value.resourceEpoch,
      targetId: value.targetId,
      targetName: value.targetName,
      viewOnly: value.viewOnly,
      firstFrameReceived: value.firstFrameReceived,
      error: value.error,
      videoWidth: value.videoWidth,
      videoHeight: value.videoHeight
    };
  }

  private copyFiles(): FilesSnapshot {
    const value = this.files;
    return {
      phase: value.phase,
      path: value.path,
      entries: value.entries.slice(),
      transfers: value.transfers.slice(),
      error: value.error
    };
  }

  private copyTerminal(): TerminalSnapshot {
    const value = this.terminal;
    return {
      phase: value.phase,
      sessionId: value.sessionId,
      output: value.output,
      error: value.error
    };
  }

  private copyPortMap(): PortMapSnapshot {
    const value = this.portMap;
    return {
      phase: value.phase,
      rule: value.rule,
      rules: value.rules,
      statusText: value.statusText,
      error: value.error,
      boundAddress: value.boundAddress
    };
  }

  private copyHost(): HostSnapshot {
    const value = this.host;
    return {
      phase: value.phase,
      capabilities: {
        capture: value.capabilities.capture,
        inputInjection: value.capabilities.inputInjection,
        background: value.capabilities.background,
        inputScope: value.capabilities.inputScope,
        reason: value.capabilities.reason
      },
      statusText: value.statusText
    };
  }

  // ---- test controls -------------------------------------------------------

  setDeviceFixture(fixture: DeviceFixture): void {
    this.deviceFixture = fixture;
    this.listDevices();
  }

  setHostScope(scope: HostScope): void {
    this.hostScope = scope;
    this.host = this.hostForScope(scope, false);
    this.emitHost();
  }

  emitFirstFrame(): void {
    if (this.session.phase !== SessionPhase.WaitingFirstFrame &&
      this.session.phase !== SessionPhase.Negotiating && this.session.phase !== SessionPhase.Connecting) {
      return;
    }
    const session = this.copySession();
    session.phase = SessionPhase.Playing;
    session.firstFrameReceived = true;
    this.session = session;
    const devices = this.copyDevices();
    devices.devices = this.devices.devices.map((d: DeviceInfo) => {
      d.busy = false;
      return d;
    });
    this.devices = devices;
    this.emitSession();
    this.emitDevices();
  }

  emitLoginExpired(): void {
    this.login = {
      phase: LoginPhase.Expired,
      statusText: tr('二维码已过期'),
      qrPayload: null,
      pollingActive: false,
      authenticated: false,
      error: null,
      generation: this.login.generation + 1
    };
    this.emitLogin();
  }

  emitLoginQueryFailed(): void {
    this.login = {
      phase: LoginPhase.QueryFailed,
      statusText: tr('暂时无法查询扫码状态'),
      qrPayload: Fixtures.QR_PAYLOAD,
      pollingActive: false,
      authenticated: false,
      error: null,
      generation: this.login.generation + 1
    };
    this.emitLogin();
  }

  emitLoginScanned(): void {
    const login = this.copyLogin();
    login.phase = LoginPhase.WaitingConfirm;
    login.statusText = tr('请在手机上确认');
    login.pollingActive = true;
    this.login = login;
    this.emitLogin();
  }

  emitPortMapBackgroundRestricted(): void {
    const portMap = this.copyPortMap();
    portMap.phase = 'backgroundRestricted';
    portMap.statusText = tr('已暂停，返回前台后可重新启动');
    this.portMap = portMap;
    this.emitPortMap();
  }

  // ---- login ---------------------------------------------------------------

  async loginStart(): Promise<void> {
    if (this.loginTimer >= 0) {
      clearTimeout(this.loginTimer);
    }
    this.login = {
      phase: LoginPhase.LoadingQr,
      statusText: tr('正在生成二维码…'),
      qrPayload: null,
      pollingActive: true,
      authenticated: false,
      error: null,
      generation: this.login.generation + 1
    };
    this.emitLogin();
    this.loginTimer = setTimeout(() => {
      const login = this.copyLogin();
      login.phase = LoginPhase.WaitingScan;
      login.statusText = tr('请扫码登录');
      login.qrPayload = Fixtures.QR_PAYLOAD;
      login.pollingActive = true;
      this.login = login;
      this.emitLogin();
    }, 200);
  }

  async loginCancel(): Promise<void> {
    if (this.loginTimer >= 0) {
      clearTimeout(this.loginTimer);
      this.loginTimer = -1;
    }
    const login = this.copyLogin();
    login.phase = LoginPhase.Failed;
    login.statusText = tr('已取消登录');
    login.pollingActive = false;
    this.login = login;
    this.emitLogin();
  }

  confirmLoginForTest(): void {
    const login = this.copyLogin();
    login.phase = LoginPhase.Finalizing;
    login.statusText = tr('已确认，正在完成登录…');
    login.pollingActive = false;
    this.login = login;
    this.emitLogin();
    setTimeout(() => {
      const done = this.copyLogin();
      done.phase = LoginPhase.Authenticated;
      done.statusText = tr('登录成功');
      done.authenticated = true;
      done.qrPayload = null;
      this.login = done;
      this.emitLogin();
      Router.reset('devices');
    }, 200);
  }

  // ---- devices -------------------------------------------------------------

  async selectTarget(deviceId: string): Promise<void> { }
  async unbindDevice(deviceId: string, shared: boolean): Promise<void> {
    this.devices.devices = this.devices.devices.filter((item: DeviceInfo) => item.id !== deviceId);
    this.emitDevices();
  }
  async syncClipboard(receive: boolean): Promise<void> { throw new Error(tr('演示服务不访问系统剪贴板')); }
  async remoteAction(action: string, enabled: boolean): Promise<void> { throw new Error(tr('演示服务不执行远端系统操作')); }
  async mkdir(path: string): Promise<void> { throw new Error(tr('演示服务不修改远端目录')); }

  async listDevices(automatic: boolean = false): Promise<void> {
    if (automatic) { return; }
    const previous = this.devices.devices;
    if (this.deviceFixture === 'error') {
      this.devices = {
        phase: DeviceListPhase.RefreshFailed,
        devices: previous,
        error: tr('刷新失败，请检查网络连接'),
        generation: this.devices.generation + 1
      };
      this.emitDevices();
      return;
    }
    if (this.deviceFixture === 'empty') {
      this.devices = {
        phase: DeviceListPhase.Empty,
        devices: [],
        error: null,
        generation: this.devices.generation + 1
      };
      this.emitDevices();
      return;
    }
    const source = this.deviceFixture === 'long' ? Fixtures.longNameDevices() : Fixtures.devices();
    this.devices = {
      phase: DeviceListPhase.Ready,
      devices: this.sortedDevices(source),
      error: null,
      generation: this.devices.generation + 1
    };
    this.emitDevices();
  }

  private sortedDevices(list: DeviceInfo[]): DeviceInfo[] {
    return list.slice().sort((a: DeviceInfo, b: DeviceInfo) => {
      if (a.online !== b.online) {
        return a.online ? -1 : 1;
      }
      const byName = a.name.localeCompare(b.name);
      return byName !== 0 ? byName : a.id.localeCompare(b.id);
    });
  }

  // ---- session -------------------------------------------------------------

  async connect(deviceId: string): Promise<void> {
    const device = this.devices.devices.find((d: DeviceInfo) => d.id === deviceId);
    if (device === undefined || !device.online) {
      return;
    }
    this.connectCount += 1;
    this.session = {
      phase: SessionPhase.Connecting,
      sessionId: Fixtures.session().sessionId,
      generation: this.session.generation + 1,
      resourceEpoch: this.session.resourceEpoch,
      targetId: device.id,
      targetName: device.name,
      viewOnly: false,
      firstFrameReceived: false,
      error: null,
      videoWidth: 1920,
      videoHeight: 1080
    };
    const devices = this.copyDevices();
    devices.devices = this.devices.devices.map((d: DeviceInfo) => {
      d.busy = d.id === deviceId;
      return d;
    });
    this.devices = devices;
    this.emitSession();
    this.emitDevices();
    if (this.connectTimer1 >= 0) {
      clearTimeout(this.connectTimer1);
    }
    if (this.connectTimer2 >= 0) {
      clearTimeout(this.connectTimer2);
    }
    this.connectTimer1 = setTimeout(() => {
      const session = this.copySession();
      session.phase = SessionPhase.Negotiating;
      this.session = session;
      this.emitSession();
    }, 250);
    this.connectTimer2 = setTimeout(() => {
      const session = this.copySession();
      session.phase = SessionPhase.WaitingFirstFrame;
      this.session = session;
      this.emitSession();
    }, 500);
  }

  async joinShare(connectId: string, verifyCode: string): Promise<void> {
    const id = connectId.trim();
    const code = verifyCode.trim();
    if (id.length === 0 || code.length === 0 || /[\u0000-\u001F\u007F]/.test(id + code)) {
      const session = this.copySession();
      session.phase = SessionPhase.Ended;
      session.error = tr('请输入对方的设备 ID 和有效验证码');
      this.session = session;
      this.emitSession();
      return;
    }
    this.connectCount += 1;
    this.session = {
      phase: SessionPhase.Connecting,
      sessionId: `demo-assist-${this.connectCount}`,
      generation: this.session.generation + 1,
      resourceEpoch: this.session.resourceEpoch,
      targetId: id,
      targetName: tr('远程协助'),
      viewOnly: false,
      firstFrameReceived: false,
      error: null,
      videoWidth: 1920,
      videoHeight: 1080
    };
    this.emitSession();
    if (this.connectTimer1 >= 0) {
      clearTimeout(this.connectTimer1);
    }
    if (this.connectTimer2 >= 0) {
      clearTimeout(this.connectTimer2);
    }
    this.connectTimer1 = setTimeout(() => {
      const session = this.copySession();
      session.phase = SessionPhase.Negotiating;
      this.session = session;
      this.emitSession();
    }, 250);
    this.connectTimer2 = setTimeout(() => {
      const session = this.copySession();
      session.phase = SessionPhase.WaitingFirstFrame;
      this.session = session;
      this.emitSession();
    }, 500);
  }

  async disconnect(): Promise<void> {
    const session = this.copySession();
    session.phase = SessionPhase.Ended;
    session.firstFrameReceived = false;
    this.session = session;
    const devices = this.copyDevices();
    devices.devices = this.devices.devices.map((d: DeviceInfo) => {
      d.busy = false;
      return d;
    });
    this.devices = devices;
    this.emitSession();
    this.emitDevices();
  }

  async sendInput(json: string): Promise<void> {
    if (!this.inputAllowed()) {
      return;
    }
    this.sentInputs.push(json);
  }

  async sendText(text: string): Promise<void> {
    if (!this.inputAllowed()) {
      return;
    }
    this.sentTexts.push(text);
  }

  async releaseAllInput(): Promise<void> {
    this.releaseCount += 1;
  }

  async setViewOnly(viewOnly: boolean): Promise<void> {
    viewOnly = viewOnly || this.pipActive;
    const session = this.copySession();
    session.viewOnly = viewOnly;
    session.phase = viewOnly ? SessionPhase.ViewOnly :
      (session.firstFrameReceived ? SessionPhase.Playing : session.phase);
    this.session = session;
    this.emitSession();
  }

  private inputAllowed(): boolean {
    return !this.pipActive && !this.session.viewOnly &&
      (this.session.phase === SessionPhase.Playing || this.session.phase === SessionPhase.WaitingFirstFrame);
  }

  async attachSurface(surfaceId: string, width: number, height: number): Promise<void> {
    this.attachCount += 1;
    const session = this.copySession();
    session.resourceEpoch = session.resourceEpoch + 1;
    session.videoWidth = width > 0 ? width : session.videoWidth;
    session.videoHeight = height > 0 ? height : session.videoHeight;
    this.session = session;
    this.emitSession();
  }

  async detachSurface(surfaceId: string): Promise<void> {
    this.detachCount += 1;
    const session = this.copySession();
    session.resourceEpoch = session.resourceEpoch + 1;
    this.session = session;
    this.emitSession();
  }

  // ---- settings ------------------------------------------------------------

  async setTheme(preference: ThemePreference): Promise<void> {
    this.settingsState = {
      themePreference: preference,
      materialPreference: this.settingsState.materialPreference,
      defaultVideoProfile: this.settingsState.defaultVideoProfile,
      defaultVideoQuality: this.settingsState.defaultVideoQuality,
      defaultFrameRate: this.settingsState.defaultFrameRate,
      trueColor: this.settingsState.trueColor,
      touchMode: this.settingsState.touchMode,
      clipboardPolicy: this.settingsState.clipboardPolicy,
      keepScreenOn: this.settingsState.keepScreenOn,
      backgroundRemoteControl: this.settingsState.backgroundRemoteControl,
      autoStartPiP: this.settingsState.autoStartPiP,
      smartReachEnabled: this.settingsState.smartReachEnabled,
      controlBarPosition: this.settingsState.controlBarPosition
    };
    AppStorage.setOrCreate('themePreference', preference);
  }

  async setVideoProfile(profile: string): Promise<void> {
    this.settingsState = {
      themePreference: this.settingsState.themePreference,
      materialPreference: this.settingsState.materialPreference,
      defaultVideoProfile: profile,
      defaultVideoQuality: this.settingsState.defaultVideoQuality,
      defaultFrameRate: this.settingsState.defaultFrameRate,
      trueColor: this.settingsState.trueColor,
      touchMode: this.settingsState.touchMode,
      clipboardPolicy: this.settingsState.clipboardPolicy,
      keepScreenOn: this.settingsState.keepScreenOn,
      backgroundRemoteControl: this.settingsState.backgroundRemoteControl,
      autoStartPiP: this.settingsState.autoStartPiP,
      smartReachEnabled: this.settingsState.smartReachEnabled,
      controlBarPosition: this.settingsState.controlBarPosition
    };
  }

  async setVideoQuality(quality: string): Promise<void> {
    this.settingsState = {
      themePreference: this.settingsState.themePreference,
      materialPreference: this.settingsState.materialPreference,
      defaultVideoProfile: this.settingsState.defaultVideoProfile,
      defaultVideoQuality: quality as VideoQuality,
      defaultFrameRate: this.settingsState.defaultFrameRate,
      trueColor: this.settingsState.trueColor,
      touchMode: this.settingsState.touchMode,
      clipboardPolicy: this.settingsState.clipboardPolicy,
      keepScreenOn: this.settingsState.keepScreenOn,
      backgroundRemoteControl: this.settingsState.backgroundRemoteControl,
      autoStartPiP: this.settingsState.autoStartPiP,
      smartReachEnabled: this.settingsState.smartReachEnabled,
      controlBarPosition: this.settingsState.controlBarPosition
    };
  }

  async setFrameRate(fps: number): Promise<void> {
    this.settingsState = {
      themePreference: this.settingsState.themePreference,
      materialPreference: this.settingsState.materialPreference,
      defaultVideoProfile: this.settingsState.defaultVideoProfile,
      defaultVideoQuality: this.settingsState.defaultVideoQuality,
      defaultFrameRate: fps,
      trueColor: this.settingsState.trueColor,
      touchMode: this.settingsState.touchMode,
      clipboardPolicy: this.settingsState.clipboardPolicy,
      keepScreenOn: this.settingsState.keepScreenOn,
      backgroundRemoteControl: this.settingsState.backgroundRemoteControl,
      autoStartPiP: this.settingsState.autoStartPiP,
      smartReachEnabled: this.settingsState.smartReachEnabled,
      controlBarPosition: this.settingsState.controlBarPosition
    };
  }

  async setTrueColor(enabled: boolean): Promise<void> {
    this.settingsState = {
      themePreference: this.settingsState.themePreference,
      materialPreference: this.settingsState.materialPreference,
      defaultVideoProfile: this.settingsState.defaultVideoProfile,
      defaultVideoQuality: this.settingsState.defaultVideoQuality,
      defaultFrameRate: this.settingsState.defaultFrameRate,
      trueColor: enabled,
      touchMode: this.settingsState.touchMode,
      clipboardPolicy: this.settingsState.clipboardPolicy,
      keepScreenOn: this.settingsState.keepScreenOn,
      backgroundRemoteControl: this.settingsState.backgroundRemoteControl,
      autoStartPiP: this.settingsState.autoStartPiP,
      smartReachEnabled: this.settingsState.smartReachEnabled,
      controlBarPosition: this.settingsState.controlBarPosition
    };
  }

  async setAudioMuted(muted: boolean): Promise<void> {
    this.audioMuteCalls += 1;
    this.audioMutedForTest = muted;
    this.audioMutedState = muted;
  }

  async setTouchMode(mode: TouchMode): Promise<void> {
    this.releaseCount += 1;
    this.settingsState = {
      themePreference: this.settingsState.themePreference,
      materialPreference: this.settingsState.materialPreference,
      defaultVideoProfile: this.settingsState.defaultVideoProfile,
      defaultVideoQuality: this.settingsState.defaultVideoQuality,
      defaultFrameRate: this.settingsState.defaultFrameRate,
      trueColor: this.settingsState.trueColor,
      touchMode: mode,
      clipboardPolicy: this.settingsState.clipboardPolicy,
      keepScreenOn: this.settingsState.keepScreenOn,
      backgroundRemoteControl: this.settingsState.backgroundRemoteControl,
      autoStartPiP: this.settingsState.autoStartPiP,
      smartReachEnabled: this.settingsState.smartReachEnabled,
      controlBarPosition: this.settingsState.controlBarPosition
    };
    this.publishTouchMode();
  }

  async setClipboardPolicy(policy: ClipboardPolicy): Promise<void> {
    this.settingsState = {
      themePreference: this.settingsState.themePreference,
      materialPreference: this.settingsState.materialPreference,
      defaultVideoProfile: this.settingsState.defaultVideoProfile,
      defaultVideoQuality: this.settingsState.defaultVideoQuality,
      defaultFrameRate: this.settingsState.defaultFrameRate,
      trueColor: this.settingsState.trueColor,
      touchMode: this.settingsState.touchMode,
      clipboardPolicy: policy,
      keepScreenOn: this.settingsState.keepScreenOn,
      backgroundRemoteControl: this.settingsState.backgroundRemoteControl,
      autoStartPiP: this.settingsState.autoStartPiP,
      smartReachEnabled: this.settingsState.smartReachEnabled,
      controlBarPosition: this.settingsState.controlBarPosition
    };
  }

  // ---- files ---------------------------------------------------------------

  async openFiles(path: string): Promise<void> {
    this.files = {
      phase: 'ready',
      path: path,
      entries: [
        { name: 'demo.txt', path: `${path === '/' ? '' : path}/demo.txt`, isDirectory: false, sizeBytes: 1024 },
        { name: 'logs', path: `${path === '/' ? '' : path}/logs`, isDirectory: true, sizeBytes: 0 }
      ],
      transfers: this.files.transfers,
      error: null
    };
    this.emitFiles();
  }

  async startTransfer(remotePath: string, localUri: string, upload: boolean): Promise<void> {
    const transferId = `demo-transfer-${this.files.transfers.length + 1}`;
    const files = this.copyFiles();
    files.phase = 'transferring';
    files.transfers = this.files.transfers.concat([{
      id: transferId,
      name: remotePath.split('/').pop() ?? 'demo.txt',
      state: 'transferring',
      totalBytes: 1024,
      transferredBytes: 256,
      localUri: localUri,
      remotePath: remotePath,
      isMock: true
    }]);
    this.files = files;
    this.emitFiles();
  }

  async cancelTransfer(transferId: string): Promise<void> {
    const files = this.copyFiles();
    files.transfers = this.files.transfers.map((t) => {
      if (t.id === transferId) {
        t.state = 'cancelled';
      }
      return t;
    });
    this.files = files;
    this.emitFiles();
  }

  // ---- terminal ------------------------------------------------------------

  async openTerminal(): Promise<void> {
    this.terminal = {
      phase: 'connecting',
      sessionId: this.session.sessionId,
      output: '',
      error: null
    };
    this.emitTerminal();
    if (this.terminalTimer >= 0) {
      clearTimeout(this.terminalTimer);
    }
    this.terminalTimer = setTimeout(() => {
      const terminal = this.copyTerminal();
      terminal.phase = 'ready';
      terminal.output = 'demo shell (remote)\r\n$ ';
      this.terminal = terminal;
      this.emitTerminal();
    }, 200);
  }

  async terminalSessions(): Promise<void> { }
  async attachTerminal(id: number): Promise<void> { await this.openTerminal(); }
  async killTerminal(id: number): Promise<void> { await this.closeTerminal(); }
  async terminalWrite(text: string): Promise<void> {
    if (this.terminal.phase !== 'ready') {
      return;
    }
    const terminal = this.copyTerminal();
    terminal.output = this.terminal.output + text;
    this.emitTerminalData(text);
    this.terminal = terminal;
    this.emitTerminal();
  }

  async terminalResize(columns: number, rows: number): Promise<void> {
  }

  async closeTerminal(): Promise<void> {
    const terminal = this.copyTerminal();
    terminal.phase = 'disconnected';
    this.terminal = terminal;
    this.emitTerminal();
  }

  // ---- port mapping --------------------------------------------------------

  async startPortMap(rule: PortMapRule): Promise<void> {
    if (rule.listenPort < 1024 || rule.listenPort > 65535) {
      const portMap = this.copyPortMap();
      portMap.phase = 'failed';
      portMap.error = tr('本地端口需在 1024 至 65535 之间');
      this.portMap = portMap;
      this.emitPortMap();
      return;
    }
    if (rule.targetPort < 1 || rule.targetPort > 65535) {
      const portMap = this.copyPortMap();
      portMap.phase = 'failed';
      portMap.error = tr('目标端口需在 1 至 65535 之间');
      this.portMap = portMap;
      this.emitPortMap();
      return;
    }
    if (!rule.allowLan && rule.listenAddress !== '127.0.0.1') {
      const portMap = this.copyPortMap();
      portMap.phase = 'failed';
      portMap.error = tr('未开启局域网连接时只能监听 127.0.0.1');
      this.portMap = portMap;
      this.emitPortMap();
      return;
    }
    if (rule.listenPort === 8800) {
      const portMap = this.copyPortMap();
      portMap.phase = 'portConflict';
      portMap.error = tr('本地端口已被占用');
      this.portMap = portMap;
      this.emitPortMap();
      return;
    }
    this.portMap = {
      phase: 'running',
      rule: rule,
      rules: (this.portMap.rules ?? []).concat([rule]),
      statusText: tr('运行中'),
      error: null,
      boundAddress: `${rule.listenAddress}:${rule.listenPort}`
    };
    this.emitPortMap();
  }

  async stopPortMap(id?: string): Promise<void> {
    const portMap = this.copyPortMap();
    portMap.rules = id === undefined ? [] : (portMap.rules ?? []).filter((rule: PortMapRule) => rule.id !== id);
    portMap.rule = portMap.rules.length > 0 ? portMap.rules[portMap.rules.length - 1] : null;
    portMap.phase = portMap.rules.length > 0 ? 'running' : 'stopped';
    portMap.statusText = tr('已停止');
    portMap.boundAddress = '';
    this.portMap = portMap;
    this.emitPortMap();
  }

  // ---- host ----------------------------------------------------------------

  private hostForScope(scope: HostScope, inputGranted: boolean): HostSnapshot {
    const capture = true;
    const injection = scope === 'pc' && inputGranted;
    const reason = scope === 'pc' ? (injection ? '' : tr('需要用户授权后才能控制本机')) :
      tr('此设备不支持全系统输入控制，仅可共享画面');
    return {
      phase: injection ? 'controlled' : (capture ? 'sharing' : 'unsupported'),
      capabilities: {
        capture: capture,
        inputInjection: injection,
        background: false,
        inputScope: scope,
        reason: reason
      },
      statusText: injection ? tr('已授权控制') : tr('仅共享画面')
    };
  }

  async requestCaptureConsent(): Promise<void> {
    const host = this.copyHost();
    host.phase = 'waitingConsent';
    host.statusText = tr('等待系统授权…');
    this.host = host;
    this.emitHost();
    if (this.hostTimer >= 0) {
      clearTimeout(this.hostTimer);
    }
    this.hostTimer = setTimeout(() => {
      const granted = this.copyHost();
      granted.phase = 'sharing';
      granted.capabilities.capture = true;
      granted.statusText = tr('正在共享画面');
      this.host = granted;
      this.emitHost();
    }, 200);
  }

  async requestInputConsent(): Promise<void> {
    if (this.hostScope !== 'pc') {
      this.host = this.hostForScope(this.hostScope, false);
      this.emitHost();
      return;
    }
    const host = this.copyHost();
    host.phase = 'controlled';
    host.capabilities.inputInjection = true;
    host.capabilities.reason = '';
    host.statusText = tr('已授权控制');
    this.host = host;
    this.emitHost();
  }

  async stopHost(): Promise<void> {
    const host = this.copyHost();
    host.phase = 'revoked';
    host.statusText = tr('已停止共享');
    this.host = host;
    this.emitHost();
  }

  async logout(): Promise<void> {
    const session = this.copySession();
    session.phase = SessionPhase.Ended;
    this.session = session;
    this.login = {
      phase: LoginPhase.LoadingQr,
      statusText: '',
      qrPayload: null,
      pollingActive: false,
      authenticated: false,
      error: null,
      generation: this.login.generation + 1
    };
    this.devices = { phase: DeviceListPhase.Loading, devices: [], error: null, generation: 0 };
    this.emitLogin();
    this.emitDevices();
    Router.reset('login');
  }
}
