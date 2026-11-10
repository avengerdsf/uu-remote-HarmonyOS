import { tr } from '../model/I18n';
import { common } from '@kit.AbilityKit';
import { applyMaterialPreference } from '../theme/MaterialPreference';
import {
  RemoteCursor,
  ClipboardPolicy,
  ControlBarPosition,
  CoreStats,
  DevicesSnapshot,
  DeviceListPhase,
  FilesSnapshot,
  HostSnapshot,
  LoginPhase,
  LoginSnapshot,
  PortMapRule,
  PortMapSnapshot,
  SessionPhase,
  SessionSnapshot,
  SettingsState,
  TerminalSnapshot,
  ThemePreference,
  MaterialPreference,
  TouchMode,
  VideoSyncState
} from '../model/Models';
import {
  CursorListener,
  DevicesListener,
  FilesListener,
  HostListener,
  LoginListener,
  PortMapListener,
  SessionListener,
  SessionService,
  TerminalDataListener,
  TerminalListener
} from './SessionService';

/** Shared snapshot and listener plumbing; no platform behaviour lives here. */
export abstract class BaseSessionService implements SessionService {
  abstract readonly kind: string;

  protected login: LoginSnapshot = {
    phase: LoginPhase.LoadingQr,
    statusText: '',
    qrPayload: null,
    pollingActive: false,
    authenticated: false,
    error: null,
    generation: 0
  };
  protected devices: DevicesSnapshot = {
    phase: DeviceListPhase.Loading,
    devices: [],
    error: null,
    generation: 0
  };
  protected session: SessionSnapshot = {
    phase: SessionPhase.Ended,
    sessionId: '',
    generation: 0,
    resourceEpoch: 0,
    targetId: '',
    targetName: '',
    viewOnly: false,
    firstFrameReceived: false,
    error: null,
    videoWidth: 0,
    videoHeight: 0
  };
  protected settingsState: SettingsState = {
    themePreference: 'system',
    materialPreference: 'system',
    defaultVideoProfile: 'auto',
    defaultVideoQuality: 'auto',
    defaultFrameRate: 60,
    trueColor: false,
    touchMode: 'trackpad',
    clipboardPolicy: 'manual',
    keepScreenOn: false,
    autoStartPiP: false,
    smartReachEnabled: true,
    controlBarPosition: 'center'
  };
  protected videoSyncState: VideoSyncState = {
    fps: 0,
    quality: 0,
    chroma: 0,
    width: 0,
    height: 0
  };
  protected audioMutedState: boolean = false;
  protected audioVolumeState: number = 100;
  protected pipActive: boolean = false;
  private pipViewOnly: boolean = false;
  private pipGeneration: number = -1;
  protected files: FilesSnapshot = {
    phase: 'loading',
    path: ':/',
    entries: [],
    transfers: [],
    error: null
  };
  protected terminal: TerminalSnapshot = {
    phase: 'disconnected',
    sessionId: '',
    output: '',
    error: null
  };
  protected portMap: PortMapSnapshot = {
    phase: 'editing',
    rule: null,
    statusText: '',
    error: null,
    boundAddress: ''
  };
  protected host: HostSnapshot = {
    phase: 'unsupported',
    capabilities: {
      capture: false,
      inputInjection: false,
      background: false,
      inputScope: 'none',
      reason: tr('能力不可用')
    },
    statusText: ''
  };
  protected counters: CoreStats = {
    mediaPackets: 0,
    framesDecoded: 0,
    framesRendered: 0,
    audioFrames: 0,
    rttMs: null
  };

  private loginListeners: LoginListener[] = [];
  private devicesListeners: DevicesListener[] = [];
  private sessionListeners: SessionListener[] = [];
  private filesListeners: FilesListener[] = [];
  protected cursor: RemoteCursor | null = null;
  private cursorListeners: CursorListener[] = [];
  private terminalDataListeners: TerminalDataListener[] = [];
  private terminalListeners: TerminalListener[] = [];
  private portMapListeners: PortMapListener[] = [];
  private hostListeners: HostListener[] = [];

  abstract init(context: common.UIAbilityContext): Promise<void>;
  abstract dispose(): void;
  abstract loginStart(): Promise<void>;
  abstract loginCancel(): Promise<void>;
  abstract listDevices(automatic?: boolean): Promise<void>;
  abstract selectTarget(deviceId: string): Promise<void>;
  abstract unbindDevice(deviceId: string, shared: boolean): Promise<void>;
  async wakeDevice(deviceId: string): Promise<void> { throw new Error(tr('当前设备无法远程开机。')); }
  abstract syncClipboard(receive: boolean): Promise<void>;
  abstract remoteAction(action: string, enabled: boolean): Promise<void>;
  abstract mkdir(path: string): Promise<void>;

  abstract connect(deviceId: string, force?: boolean): Promise<void>;
  abstract joinShare(connectId: string, verifyCode: string): Promise<void>;
  abstract disconnect(): Promise<void>;
  abstract sendInput(json: string): Promise<void>;
  abstract sendText(text: string): Promise<void>;
  abstract releaseAllInput(): Promise<void>;
  abstract setViewOnly(viewOnly: boolean): Promise<void>;
  abstract attachSurface(surfaceId: string, width: number, height: number): Promise<void>;
  abstract detachSurface(surfaceId: string): Promise<void>;
  async resizeViewport(width: number, height: number): Promise<void> {}
  fingerprintUnlockAvailable(): boolean { return false; }
  async hasFingerprintUnlockPassword(): Promise<boolean> { return false; }
  async saveFingerprintUnlockPassword(password: string): Promise<void> {}
  async removeFingerprintUnlockPassword(): Promise<void> {}
  async fingerprintUnlock(): Promise<void> {}
  abstract setTheme(preference: ThemePreference): Promise<void>;
  abstract setVideoProfile(profile: string): Promise<void>;
  abstract setVideoQuality(quality: string): Promise<void>;
  abstract setFrameRate(fps: number): Promise<void>;
  abstract setTrueColor(enabled: boolean): Promise<void>;
  abstract setTouchMode(mode: TouchMode): Promise<void>;
  abstract setClipboardPolicy(policy: ClipboardPolicy): Promise<void>;
  abstract setAudioMuted(muted: boolean): Promise<void>;
  abstract openFiles(path: string): Promise<void>;
  abstract startTransfer(remotePath: string, localUri: string, upload: boolean): Promise<void>;
  abstract cancelTransfer(transferId: string): Promise<void>;
  abstract openTerminal(): Promise<void>;
  abstract terminalSessions(): Promise<void>;
  abstract attachTerminal(id: number): Promise<void>;
  abstract killTerminal(id: number): Promise<void>;
  abstract terminalWrite(text: string): Promise<void>;
  abstract terminalResize(columns: number, rows: number): Promise<void>;
  abstract closeTerminal(): Promise<void>;
  abstract startPortMap(rule: PortMapRule): Promise<void>;
  abstract stopPortMap(id?: string): Promise<void>;
  abstract requestCaptureConsent(): Promise<void>;
  abstract requestInputConsent(): Promise<void>;
  abstract stopHost(): Promise<void>;
  abstract logout(): Promise<void>;

  cursorSnapshot(): RemoteCursor | null { return this.cursor; }
  onCursor(listener: CursorListener): () => void {
    this.cursorListeners.push(listener);
    return () => { this.cursorListeners = this.cursorListeners.filter((item: CursorListener) => item !== listener); };
  }
  protected emitCursor(): void { this.cursorListeners.forEach((listener: CursorListener) => { listener(this.cursor); }); }

  loginSnapshot(): LoginSnapshot {
    return this.login;
  }

  devicesSnapshot(): DevicesSnapshot {
    return this.devices;
  }

  sessionSnapshot(): SessionSnapshot {
    return this.session;
  }

  settings(): SettingsState {
    return this.settingsState;
  }

  protected publishTouchMode(): void {
    AppStorage.setOrCreate<TouchMode>('remoteTouchMode', this.settingsState.touchMode);
  }

  async setMaterialPreference(preference: MaterialPreference): Promise<void> {
    this.settingsState.materialPreference = preference;
    applyMaterialPreference(preference);
  }

  async setKeepScreenOn(enabled: boolean): Promise<void> {
    this.settingsState.keepScreenOn = enabled;
  }

  async setAutoStartPiP(enabled: boolean): Promise<void> {
    this.settingsState.autoStartPiP = enabled;
  }

  async setPiPActive(active: boolean): Promise<void> {
    if (this.pipActive === active) { return; }
    if (active) {
      this.pipViewOnly = this.session.viewOnly;
      this.pipGeneration = this.session.generation;
      this.pipActive = true;
      await this.releaseAllInput();
      await this.setViewOnly(true);
    } else {
      this.pipActive = false;
      if (this.pipGeneration === this.session.generation) {
        await this.setViewOnly(this.pipViewOnly);
      }
      this.pipGeneration = -1;
    }
  }

  async setSmartReachEnabled(enabled: boolean): Promise<void> {
    this.settingsState.smartReachEnabled = enabled;
  }

  async setControlBarPosition(position: ControlBarPosition): Promise<void> {
    this.settingsState.controlBarPosition = position;
  }

  videoSync(): VideoSyncState {
    return this.videoSyncState;
  }

  audioMuted(): boolean {
    return this.audioMutedState;
  }

  audioVolume(): number { return this.audioVolumeState; }

  async setAudioVolume(volume: number): Promise<void> {
    if (!Number.isFinite(volume) || volume < 0 || volume > 100) { throw new Error(tr('音量应在 0–100 之间')); }
    this.audioVolumeState = Math.round(volume);
  }

  filesSnapshot(): FilesSnapshot {
    return this.files;
  }

  terminalSnapshot(): TerminalSnapshot {
    return this.terminal;
  }

  portMapSnapshot(): PortMapSnapshot {
    return this.portMap;
  }

  hostSnapshot(): HostSnapshot {
    return this.host;
  }

  stats(): CoreStats {
    return this.counters;
  }

  onLogin(listener: LoginListener): () => void {
    this.loginListeners.push(listener);
    return () => {
      this.loginListeners = this.loginListeners.filter((item: LoginListener) => item !== listener);
    };
  }

  onDevices(listener: DevicesListener): () => void {
    this.devicesListeners.push(listener);
    return () => {
      this.devicesListeners = this.devicesListeners.filter((item: DevicesListener) => item !== listener);
    };
  }

  onSession(listener: SessionListener): () => void {
    this.sessionListeners.push(listener);
    return () => {
      this.sessionListeners = this.sessionListeners.filter((item: SessionListener) => item !== listener);
    };
  }

  onFiles(listener: FilesListener): () => void {
    this.filesListeners.push(listener);
    return () => {
      this.filesListeners = this.filesListeners.filter((item: FilesListener) => item !== listener);
    };
  }

  onTerminalData(listener: TerminalDataListener): () => void {
    this.terminalDataListeners.push(listener);
    return () => { this.terminalDataListeners = this.terminalDataListeners.filter((item: TerminalDataListener) => item !== listener); };
  }
  protected emitTerminalData(text: string): void {
    this.terminalDataListeners.forEach((listener: TerminalDataListener) => { listener(text); });
  }

  onTerminal(listener: TerminalListener): () => void {
    this.terminalListeners.push(listener);
    return () => {
      this.terminalListeners = this.terminalListeners.filter((item: TerminalListener) => item !== listener);
    };
  }

  onPortMap(listener: PortMapListener): () => void {
    this.portMapListeners.push(listener);
    return () => {
      this.portMapListeners = this.portMapListeners.filter((item: PortMapListener) => item !== listener);
    };
  }

  onHost(listener: HostListener): () => void {
    this.hostListeners.push(listener);
    return () => {
      this.hostListeners = this.hostListeners.filter((item: HostListener) => item !== listener);
    };
  }

  protected emitLogin(): void {
    for (const listener of this.loginListeners) {
      listener(this.login);
    }
  }

  protected emitDevices(): void {
    for (const listener of this.devicesListeners) {
      listener(this.devices);
    }
  }

  protected emitSession(): void {
    for (const listener of this.sessionListeners) {
      listener(this.session);
    }
  }

  protected emitFiles(): void {
    for (const listener of this.filesListeners) {
      listener(this.files);
    }
  }

  protected emitTerminal(): void {
    for (const listener of this.terminalListeners) {
      listener(this.terminal);
    }
  }

  protected emitPortMap(): void {
    for (const listener of this.portMapListeners) {
      listener(this.portMap);
    }
  }

  protected emitHost(): void {
    for (const listener of this.hostListeners) {
      listener(this.host);
    }
  }
}
