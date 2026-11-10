import { i18n } from '@kit.LocalizationKit';
import { tr } from '../model/I18n';
import { RemoteSessionBackground } from './RemoteSessionBackground';
import { applyMaterialPreference } from '../theme/MaterialPreference';
import { common } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import {
  RemoteCursor,
  ClipboardPolicy,
  ControlBarPosition,
  CoreStats,
  CredentialsPayload,
  DeviceInfo,
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
  TerminalSessionInfo,
  ThemePreference,
  MaterialPreference,
  TouchMode,
  TransferInfo,
  VideoQuality,
  RemoteUnlockState, VideoResolution, VideoSyncState
} from '../model/Models';
import { Router } from '../model/Router';
import { BaseSessionService } from './BaseSessionService';
import { CredentialStore } from './CredentialStore';
import { RemoteUnlockCredentials } from './RemoteUnlockCredentials';
// The N-API shared library is built from entry/src/main/cpp and links libuu_core.a.
import nativeCore from 'libuu_core.so';
import BuildProfile from 'BuildProfile';

interface NativeCoreModule {
  create(configJson: string): number;
  command(handle: number, commandJson: string): number;
  poll(handle: number): string;
  destroy(handle: number): void;
  decoderCaps(handle: number): string;
  mediaStats(handle: number): string;
  setAudioVolume(handle: number, volume: number): number;
  version(): string;
}

interface DecoderCaps {
  hevc: boolean;
  maxWidth: number;
  maxHeight: number;
  maxFps: number;
  chroma444: boolean;
  hardware: boolean;
  probed: boolean;
}

interface MediaStats {
  framesDecoded: number; framesRendered: number; framesSubmitted?: number; framesDropped?: number;
  framesPushed?: number; pushFailures?: number; inputCallbacks?: number; outputCallbacks?: number;
  decoderResets?: number; decoderError?: number; pendingInputs?: number; queuedUnits?: number;
  pictureUnits?: number; configUnits?: number; otherUnits?: number; ptsRegressions?: number;
  renderFailures?: number; lastInputPtsUs?: number; lastOutputPtsUs?: number;
}
interface GenerationEvent { generation?: number; sessionId?: string; }
interface CursorCaptureEvent { generation: number; enabled: boolean; }
interface ResolutionModesEvent { generation: number; modes: VideoResolution[]; }

interface HumanPayload {
  statusText?: string;
  error?: string;
  message?: string;
  devices?: DeviceInfo[];
}

interface EventEnvelope {
  type: string;
  seq?: number;
  data?: string;
}

interface CommandParams {
  user_id?: string;
  device_id?: string;
  client_id?: string;
  system_id?: string;
  token?: string;
  csrf?: string;
  sign_key?: string;
  deviceId?: string;
  targetId?: string;
  password?: string;
  force?: boolean;
  shared?: boolean;
  action?: string;
  connectId?: string;
  verifyCode?: string;
  json?: string;
  text?: string;
  viewOnly?: boolean;
  surfaceId?: string;
  width?: number;
  height?: number;
  path?: string;
  remotePath?: string;
  localPath?: string;
  upload?: boolean;
  transferId?: string;
  mode?: string;
  quality?: string;
  fps?: number;
  trueColor?: boolean;
  enabled?: boolean;
  muted?: boolean;
  profile?: string;
  columns?: number;
  rows?: number;
  ptyId?: number;
  id?: string;
  listenAddress?: string;
  listenPort?: number;
  targetHost?: string;
  targetPort?: number;
  allowLan?: boolean;
  generation?: number;
  hevc?: boolean;
  maxWidth?: number;
  maxHeight?: number;
  maxFps?: number;
  chroma444?: boolean;
}

interface BuildConfig {
  deviceId: string;
  clientId: string;
  systemId: string;
  machineGuid: string;
  locale: string;
  model: string;
  osFullName: string;
  sdkApiVersion: string;
  deviceType: string;
}

interface PendingOperation {
  resolve: () => void;
  reject: (error: Error) => void;
  timer: number;
  requestId?: number;
}
interface OperationResult {
  operation: string;
  success: boolean;
  error?: string;
  generation?: number;
  requestId?: number;
}
interface ClipboardEvent {
  text: string;
  generation: number;
}

interface TerminalListPayload { sessions: TerminalSessionInfo[]; error?: string; }
interface TextPayload {
  ptyId?: number;
  text?: string;
}

interface ErrorPayload {
  message?: string;
}

interface TransferEvent {
  id?: string;
  name?: string;
  state?: string;
  totalBytes?: number;
  transferredBytes?: number;
  localPath?: string;
  remotePath?: string;
  upload?: boolean;
  error?: string;
}

/**
 * Production service. All commands are JSON over the versioned C ABI; media stays
 * on the native Surface path and never becomes an ArkTS pixel array.
 */
export class NativeSessionService extends BaseSessionService {
  readonly kind: string = 'native';

  private module: NativeCoreModule = nativeCore;
  private handle: number = 0;
  private pollTimer: number = -1;
  private lastDeviceListRequest: number = 0;
  private commandSeq: number = 0;
  private unlockAccountId: string = '';
  private fingerprintUnlockPending: boolean = false;
  private lastRenderedNotice: number = 0;
  private attachedSurface: string = '';
  private inputLogged: boolean = false;
  private pendingOperations: Map<string, PendingOperation> = new Map<string, PendingOperation>();
  private disconnectTask: Promise<void> | null = null;
  private remoteClipboard: string | null = null;
  private terminalBuffers: Map<number, string> = new Map<number, string>();
  private context: common.UIAbilityContext | null = null;
  private store: preferences.Preferences | null = null;
  private settingsLoaded: boolean = false;
  private transferPaths: Map<string, string> = new Map<string, string>();
  private transferTargets: Map<string, string> = new Map<string, string>();
  private pendingDownloads: Map<string, string> = new Map<string, string>();
  private credentialWrite: Promise<void> = Promise.resolve();
  private touchModeWrite: Promise<void> = Promise.resolve();
  private backgroundPreferenceWrite: Promise<void> = Promise.resolve();
  private background: RemoteSessionBackground | null = null;
  private audioStarted: boolean = false;
  private foreground: boolean = true;
  private directDeviceId: string = '';
  private backgroundGeneration: number = -1;
  private resumeUntil: number = 0;
  private resumeDeviceId: string = '';
  private reconnectGeneration: number = -1;
  private reconnectRenderedBaseline: number = 0;
  private reconnectCleaning: boolean = false;
  private resumeEpoch: number = 0;

  async init(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    this.background = new RemoteSessionBackground(context);
    this.store = await preferences.getPreferences(context, 'uu_remote_settings');
    await this.loadSettings();
    const config = await this.buildConfig(context);
    this.handle = this.module.create(JSON.stringify(config));
    if (this.handle === 0) {
      throw new Error('UU core initialization failed');
    }
    this.pollTimer = setInterval(() => {
      this.pollOnce();
    }, 30);
    await this.sendCommand('init', {});
    await this.applyDecoderCapabilities();
    await this.applyPersistedSettings();
    this.publishTouchMode();
    const stored = await CredentialStore.load();
    if (stored !== null) {
      await this.sendCommand('setCredentials', {
        user_id: stored.userId,
        device_id: stored.deviceId,
        client_id: stored.clientId,
        system_id: stored.systemId,
        token: stored.token,
        csrf: stored.csrf,
        sign_key: ''
      });
      this.publishAccountIdSuffix(stored.userId);
      await this.listDevices();
    } else {
      this.publishAccountIdSuffix('');
      Router.reset('login');
    }
  }

  dispose(): void {
    this.clearBackgroundResume();
    this.background?.update(-1, false, false);
    this.background = null;
    this.publishAccountIdSuffix('');
    this.pendingOperations.forEach((pending: PendingOperation) => {
      clearTimeout(pending.timer);
      pending.reject(new Error(tr('服务已关闭')));
    });
    this.pendingOperations.clear();
    this.remoteClipboard = null;
    this.resetTools();
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
    if (this.handle !== 0) {
      this.module.destroy(this.handle);
      this.handle = 0;
    }
  }

  private publishAccountIdSuffix(userId: string): void {
    const id = typeof userId === 'string' ? userId.trim() : '';
    this.unlockAccountId = id;
    AppStorage.setOrCreate('accountIdSuffix', id.length > 4 ? id.slice(-4) : '');
  }

  private async buildConfig(context: common.UIAbilityContext): Promise<BuildConfig> {
    const store = this.store;
    // device_id is issued by /api/v1/device/windows/init. Never generate a local
    // UUID here: the Rust login service skips registration for non-empty IDs and
    // the cloud then rejects QR generation.
    const deviceId = '';
    let clientId = '';
    let systemId = '';
    let machineGuid = '';
    if (store !== null) {
      clientId = await store.get('clientId', '') as string;
      systemId = await store.get('systemId', '') as string;
      machineGuid = await store.get('machineGuid', '') as string;
    }
    if (clientId.length === 0) {
      clientId = util.generateRandomUUID(false);
    }
    if (systemId.length === 0) {
      systemId = util.generateRandomUUID(false).toUpperCase();
    }
    if (machineGuid.length === 0) {
      machineGuid = util.generateRandomUUID(false).toUpperCase();
    }
    if (store !== null) {
      await store.put('clientId', clientId);
      await store.put('systemId', systemId);
      await store.put('machineGuid', machineGuid);
      await store.flush();
    }
    return {
      deviceId: deviceId,
      clientId: clientId,
      systemId: systemId,
      machineGuid: machineGuid,
      locale: i18n.System.getAppPreferredLanguage(),
      model: deviceInfo.productModel,
      osFullName: deviceInfo.osFullName,
      sdkApiVersion: `${deviceInfo.sdkApiVersion}`,
      deviceType: deviceInfo.deviceType
    };
  }

  private pollOnce(): void {
    if (this.handle === 0) {
      return;
    }
    for (let count = 0; count < 64; count++) {
      const text = this.module.poll(this.handle);
      if (text === undefined || text === null || text.length === 0) { break; }
      try { this.dispatch(JSON.parse(text) as EventEnvelope); } catch (error) { continue; }
    }
    if (this.session.phase !== SessionPhase.Ended && this.session.phase !== SessionPhase.Connecting) {
      try {
      const native = JSON.parse(this.module.mediaStats(this.handle)) as MediaStats;
      this.counters.framesDecoded = native.framesDecoded;
      this.counters.framesRendered = native.framesRendered;
      this.counters.framesSubmitted = native.framesSubmitted;
      this.counters.framesDropped = native.framesDropped;
      this.counters.framesPushed = native.framesPushed;
      this.counters.pushFailures = native.pushFailures;
      this.counters.inputCallbacks = native.inputCallbacks;
      this.counters.outputCallbacks = native.outputCallbacks;
      this.counters.decoderResets = native.decoderResets;
      this.counters.decoderError = native.decoderError;
      this.counters.pendingInputs = native.pendingInputs;
      this.counters.queuedUnits = native.queuedUnits;
      this.counters.pictureUnits = native.pictureUnits;
      this.counters.configUnits = native.configUnits;
      this.counters.otherUnits = native.otherUnits;
      this.counters.ptsRegressions = native.ptsRegressions;
      this.counters.renderFailures = native.renderFailures;
      this.counters.lastInputPtsUs = native.lastInputPtsUs;
      this.counters.lastOutputPtsUs = native.lastOutputPtsUs;
      if (native.framesRendered > 0 && native.framesRendered !== this.reconnectRenderedBaseline &&
        this.session.generation > this.reconnectGeneration &&
        this.attachedSurface.length > 0 && !this.session.firstFrameReceived &&
        Date.now() - this.lastRenderedNotice >= 250) {
        // Surface callbacks can precede installation of the asynchronous session handle.
        this.lastRenderedNotice = Date.now();
        this.sendCommand('videoRendered', { generation: this.session.generation }).catch(() => {});
      }
      } catch (error) { /* A statistics query cannot interrupt event delivery. */ }
    }
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
      videoHeight: value.videoHeight,
      remoteCursorInVideo: value.remoteCursorInVideo,
      remoteUnlock: value.remoteUnlock
    };
  }

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

  private copyTerminal(): TerminalSnapshot {
    const value = this.terminal;
    return {
      phase: value.phase,
      sessionId: value.sessionId,
      output: value.output,
      ptyId: value.ptyId,
      sessions: value.sessions,
      error: value.error
    };
  }

  private copySettings(): SettingsState {
    const value = this.settingsState;
    return {
      themePreference: value.themePreference,
      materialPreference: value.materialPreference,
      defaultVideoProfile: value.defaultVideoProfile,
      defaultVideoQuality: value.defaultVideoQuality,
      defaultFrameRate: value.defaultFrameRate,
      trueColor: value.trueColor,
      touchMode: value.touchMode,
      clipboardPolicy: value.clipboardPolicy,
      keepScreenOn: value.keepScreenOn,
      backgroundRemoteControl: value.backgroundRemoteControl,
      autoStartPiP: value.autoStartPiP,
      smartReachEnabled: value.smartReachEnabled,
      controlBarPosition: value.controlBarPosition
    };
  }

  private filesWith(snapshot: FilesSnapshot, transfers: TransferInfo[],
                    error: string | null): FilesSnapshot {
    return {
      phase: snapshot.phase,
      path: snapshot.path,
      entries: snapshot.entries,
      transfers: transfers,
      error: error
    };
  }

  private dispatch(event: EventEnvelope): void {
    let payload = event.data ?? '';
    if (event.type === 'signalCleanup' || event.type === 'signalRelease') {
      if (BuildProfile.DEBUG) { console.info('UU_SIGNAL_' + event.type + ' ' + payload); }
      return;
    }
    if (!['clipboardText', 'terminalOutput', 'credentials'].includes(event.type)) {
      const human = JSON.parse(payload) as HumanPayload;
      if (typeof human.statusText === 'string') { human.statusText = tr(human.statusText); }
      if (typeof human.error === 'string') { human.error = tr(human.error); }
      if (typeof human.message === 'string') { human.message = tr(human.message); }
      human.devices?.forEach((device: DeviceInfo) => {
        device.statusText = tr(device.statusText);
        device.connectLabel = tr(device.connectLabel);
        device.platform = tr(device.platform);
      });
      payload = JSON.stringify(human);
    }
    if (['filesState', 'transferState', 'terminalState', 'terminalSessions', 'terminalOutput', 'portMapState'].includes(event.type)) {
      const tagged = JSON.parse(payload) as GenerationEvent;
      if (tagged.generation !== this.session.generation) { return; }
    }
    if (event.type === 'operationResult') {
      const result = JSON.parse(payload) as OperationResult;
      const key = result.operation === 'unlockRemote' ? 'unlockRemote.' + result.generation : result.operation;
      const pending = this.pendingOperations.get(key);
      if (pending !== undefined && (pending.requestId === undefined || pending.requestId === result.requestId)) {
        clearTimeout(pending.timer);
        this.pendingOperations.delete(key);
        if (result.success) { pending.resolve(); }
        else { pending.reject(new Error(result.error ?? tr('远端操作失败'))); }
      }
    } else if (event.type === 'remoteUnlockState') {
      const state = JSON.parse(payload) as RemoteUnlockState;
      if (state.generation !== this.session.generation || this.session.phase === SessionPhase.Ended) { return; }
      const session = this.copySession();
      session.remoteUnlock = state;
      this.session = session;
      this.emitSession();
    } else if (event.type === 'remoteCursor') {
      const cursor = JSON.parse(payload) as RemoteCursor;
      if (cursor.generation === this.session.generation) { this.cursor = cursor; this.emitCursor(); }
    } else if (event.type === 'remoteCursorCapture') {
      const capture = JSON.parse(payload) as CursorCaptureEvent;
      if (capture.generation !== this.session.generation || this.session.phase === SessionPhase.Ended) { return; }
      const session = this.copySession();
      session.remoteCursorInVideo = capture.enabled;
      this.session = session;
      this.emitSession();
    } else if (event.type === 'clipboardText') {
      const value = JSON.parse(payload) as ClipboardEvent;
      if (value.generation === this.session.generation) { this.remoteClipboard = value.text; }
    } else if (event.type === 'loginState') {
      const snapshot = JSON.parse(payload) as LoginSnapshot;
      if (snapshot.generation < this.login.generation) { return; }
      if (this.login.authenticated && !snapshot.authenticated) { this.publishAccountIdSuffix(''); }
      this.login = snapshot;
      this.emitLogin();
      if (this.login.authenticated) {
        Router.reset('devices');
      }
    } else if (event.type === 'deviceList') {
      const snapshot = JSON.parse(payload) as DevicesSnapshot;
      if (snapshot.generation < this.devices.generation) { return; }
      this.devices = snapshot;
      this.emitDevices();
    } else if (event.type === 'sessionState') {
      const snapshot = JSON.parse(payload) as SessionSnapshot;
      if (this.reconnectCleaning && snapshot.phase === SessionPhase.Ended) {
        this.reconnectGeneration = Math.max(this.reconnectGeneration, snapshot.generation);
        return;
      }
      if (snapshot.generation <= this.reconnectGeneration) { return; }
      if (snapshot.generation < this.session.generation) { return; }
      if (snapshot.generation === this.session.generation && this.session.phase === SessionPhase.Ended &&
        snapshot.phase !== SessionPhase.Ended) { return; }
      if (snapshot.generation !== this.session.generation) { this.resetTools(); this.audioStarted = false; }
      else if (snapshot.phase !== SessionPhase.Ended) {
        snapshot.remoteCursorInVideo = this.session.remoteCursorInVideo;
        snapshot.remoteUnlock = this.session.remoteUnlock;
      }
      if (BuildProfile.DEBUG && snapshot.phase === SessionPhase.Ended && this.session.phase !== SessionPhase.Ended) {
        const known = ['peer connection closed', 'video track ended', 'remote session released', 'First video frame timed out'];
        const reason = known.find((value: string) => tr(value) === snapshot.error) ?? (snapshot.error === null ? 'normal' : 'other');
        console.info('UU_BG_REMOTE session ended: ' + reason);
      }
      if (this.queueBackgroundResume(snapshot)) { return; }
      this.session = snapshot;
      this.updateBackground();
      this.emitSession();
    } else if (event.type === 'inputError' || event.type === 'videoSettingsError') {
      const value = JSON.parse(payload) as GenerationEvent;
      if (value.generation !== this.session.generation || this.session.phase === SessionPhase.Ended) { return; }
      const error = JSON.parse(payload) as ErrorPayload;
      const session = this.copySession();
      session.error = tr(error.message ?? (event.type === 'inputError' ?
        '远程输入发送失败，请重新连接。' : '画面设置发送失败，请重试。'));
      this.session = session;
      this.emitSession();
    } else if (event.type === 'firstFrame') {
      const value = JSON.parse(payload) as GenerationEvent;
      if (value.generation !== this.session.generation || value.generation <= this.reconnectGeneration ||
        this.session.phase === SessionPhase.Ended) { return; }
      const session = this.copySession();
      session.phase = session.viewOnly ? SessionPhase.ViewOnly : SessionPhase.Playing;
      session.firstFrameReceived = true;
      this.session = session;
      this.updateBackground();
      this.emitSession();
    } else if (event.type === 'audioStarted') {
      const value = JSON.parse(payload) as GenerationEvent;
      if (value.generation === this.session.generation && this.session.phase !== SessionPhase.Ended) {
        this.audioStarted = true;
        this.updateBackground();
      }
    } else if (event.type === 'filesState') {
      const snapshot = JSON.parse(payload) as FilesSnapshot;
      this.files = this.filesWith(snapshot, this.files.transfers, snapshot.error);
      this.emitFiles();
    } else if (event.type === 'transferState') {
      this.applyTransferEvent(JSON.parse(payload) as TransferEvent);
    } else if (event.type === 'terminalState') {
      const next = JSON.parse(payload) as TerminalSnapshot;
      if (next.phase !== 'ready' && next.ptyId !== undefined && next.ptyId !== this.terminal.ptyId) {
        this.terminalBuffers.delete(next.ptyId);
        return;
      }
      if (next.ptyId === undefined) { next.ptyId = this.terminal.ptyId; }
      if (next.phase === 'disconnected' && next.ptyId !== undefined) { this.terminalBuffers.delete(next.ptyId); }
      next.sessions = this.terminal.sessions;
      next.output = this.terminalBuffers.get(next.ptyId ?? 0) ?? '';
      this.terminal = next;
      this.emitTerminal();
    } else if (event.type === 'terminalSessions') {
      const value = JSON.parse(payload) as TerminalListPayload;
      const terminal = this.copyTerminal();
      terminal.sessions = value.sessions;
      terminal.error = value.error ?? null;
      this.terminal = terminal;
      this.emitTerminal();
    } else if (event.type === 'terminalOutput') {
      const value = JSON.parse(payload) as TextPayload;
      const id = value.ptyId ?? 0;
      const text = value.text ?? '';
      if (!this.terminalBuffers.has(id) && this.terminalBuffers.size >= 32) {
        const oldest = Array.from(this.terminalBuffers.keys())[0];
        this.terminalBuffers.delete(oldest);
      }
      this.terminalBuffers.set(id, ((this.terminalBuffers.get(id) ?? '') + text).slice(-512 * 1024));
      if (id === (this.terminal.ptyId ?? 0)) {
        const terminal = this.copyTerminal();
        terminal.output = this.terminalBuffers.get(id) ?? '';
        this.terminal = terminal;
        this.emitTerminalData(text);
      }
    } else if (event.type === 'portMapState') {
      this.portMap = JSON.parse(payload) as PortMapSnapshot;
      this.emitPortMap();
    } else if (event.type === 'hostState') {
      this.host = JSON.parse(payload) as HostSnapshot;
      this.emitHost();
    } else if (event.type === 'credentials') {
      const tagged = JSON.parse(payload) as GenerationEvent;
      if (tagged.generation !== this.login.generation) { return; }
      this.lastDeviceListRequest = 0;
      const credentials = JSON.parse(payload) as CredentialsPayload;
      this.publishAccountIdSuffix(credentials.userId);
      this.credentialWrite = this.credentialWrite.catch(() => {}).then(() => CredentialStore.save(credentials));
    } else if (event.type === 'loginError') {
      const tagged = JSON.parse(payload) as GenerationEvent;
      if (tagged.generation !== this.login.generation) { return; }
      const error = JSON.parse(payload) as ErrorPayload;
      const login = this.copyLogin();
      login.phase = LoginPhase.Failed;
      login.statusText = tr('登录失败');
      login.pollingActive = false;
      login.error = error.message ?? null;
      this.login = login;
      this.emitLogin();
    } else if (event.type === 'stats') {
      const value = JSON.parse(payload) as GenerationEvent;
      if (value.generation !== this.session.generation) { return; }
      const counts = JSON.parse(payload) as CoreStats;
      if (BuildProfile.DEBUG && counts.inputCommands !== this.counters.inputCommands) {
        console.info('UU_INPUT_COUNTS ' + JSON.stringify({ commands: counts.inputCommands, messages: counts.inputMessages }));
      }
      this.counters.mediaPackets = counts.mediaPackets;
      this.counters.audioFrames = counts.audioFrames;
      if (!this.audioStarted && counts.audioFrames > 0 && this.session.phase !== SessionPhase.Ended) {
        this.audioStarted = true;
        this.updateBackground();
      }
      this.counters.rttMs = counts.rttMs;
      this.counters.route = counts.route;
      this.counters.fps = counts.fps;
      this.counters.kbps = counts.kbps;
      this.counters.inputCommands = counts.inputCommands;
      this.counters.inputMessages = counts.inputMessages;
    } else if (event.type === 'videoResolutionModes') {
      const value = JSON.parse(payload) as ResolutionModesEvent;
      if (value.generation !== this.session.generation || this.session.phase === SessionPhase.Ended) { return; }
      this.videoSyncState.resolutionModes = value.modes;
      this.session = this.copySession();
      this.emitSession();
    } else if (event.type === 'videoSettingsSync') {
      const value = JSON.parse(payload) as GenerationEvent;
      if (value.generation !== this.session.generation || this.session.phase === SessionPhase.Ended) { return; }
      const sync = JSON.parse(payload) as VideoSyncState;
      if (sync.width <= 0 || sync.height <= 0) {
        sync.width = this.videoSyncState.width;
        sync.height = this.videoSyncState.height;
      }
      sync.resolutionModes = this.videoSyncState.resolutionModes;
      this.videoSyncState = sync;
      const session = this.copySession();
      if (sync.width > 0 && sync.height > 0) {
        session.videoWidth = sync.width;
        session.videoHeight = sync.height;
      }
      this.session = session;
      this.emitSession();
    }
  }

  private sendCommand(method: string, params: CommandParams): Promise<void> {
    if (this.handle === 0) {
      return Promise.reject(new Error(tr('原生核心已关闭')));
    }
    this.commandSeq += 1;
    const command = JSON.stringify({
      id: this.commandSeq,
      method: method,
      params: params
    });
    if (this.module.command(this.handle, command) !== 0) { return Promise.reject(new Error(tr('原生核心拒绝命令'))); }
    return Promise.resolve();
  }

  // ---- login ---------------------------------------------------------------

  async loginStart(): Promise<void> {
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
    await this.sendCommand('loginStart', {});
  }

  async loginCancel(): Promise<void> {
    this.login.generation++;
    await this.sendCommand('loginCancel', {});
  }

  // ---- devices -------------------------------------------------------------

  private operation(method: string, params: CommandParams, key: string = method): Promise<void> {
    if (this.pendingOperations.has(key)) { return Promise.reject(new Error(tr('同类操作正在进行'))); }
    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pendingOperations.delete(key);
        reject(new Error(tr('远端操作超时')));
      }, 45000);
      this.pendingOperations.set(key, { resolve: resolve, reject: reject, timer: timer,
        requestId: method === 'unlockRemote' ? this.commandSeq + 1 : undefined });
      this.sendCommand(method, params).catch((error: Error) => {
        clearTimeout(timer);
        this.pendingOperations.delete(key);
        reject(error);
      });
    });
  }

  async selectTarget(deviceId: string): Promise<void> {
    this.remoteClipboard = null;
    await this.operation('selectTarget', { deviceId: deviceId });
  }
  async unbindDevice(deviceId: string, shared: boolean): Promise<void> {
    await this.operation('unbindDevice', { deviceId: deviceId, shared: shared });
  }

  async wakeDevice(deviceId: string): Promise<void> {
    await this.operation('wakeDevice', { deviceId: deviceId });
  }
  async syncClipboard(receive: boolean): Promise<void> {
    if (receive) {
      if (this.remoteClipboard === null) { throw new Error(tr('尚未收到远端复制的文本')); }
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.remoteClipboard));
    } else {
      const data = await pasteboard.getSystemPasteboard().getData();
      const text = data.getPrimaryText();
      if (new util.TextEncoder().encodeInto(text).byteLength > 30 * 1024) { throw new Error(tr('剪贴板文本超过 30 KiB')); }
      await this.operation('sendClipboard', { text: text }, 'clipboard');
    }
  }
  async remoteAction(action: string, enabled: boolean): Promise<void> {
    if (action === 'shutdown' || action === 'reboot') { this.clearBackgroundResume(); }
    await this.operation('remoteAction', { action: action, enabled: enabled });
  }
  async mkdir(path: string): Promise<void> { await this.operation('mkdir', { path: path }); }

  async listDevices(automatic: boolean = false): Promise<void> {
    const now = Date.now();
    const elapsed = now - this.lastDeviceListRequest;
    // The native device-list HTTP request times out after 12 seconds.
    if (automatic && elapsed >= 0 && elapsed < 12000) { return; }
    this.lastDeviceListRequest = now;
    await this.sendCommand('listDevices', {});
  }

  // ---- session -------------------------------------------------------------

  private resetVideoSync(): void {
    this.videoSyncState = { fps: 0, quality: 0, chroma: 0, width: 0, height: 0 };
  }

  async connect(deviceId: string, force: boolean = false): Promise<void> {
    this.clearBackgroundResume();
    this.directDeviceId = deviceId;
    this.reconnectRenderedBaseline = 0;
    this.resetVideoSync();
    this.attachedSurface = '';
    this.lastRenderedNotice = 0;
    await this.sendCommand('connect', { deviceId: deviceId, force: force });
  }

  async joinShare(connectId: string, verifyCode: string): Promise<void> {
    this.clearBackgroundResume();
    this.directDeviceId = '';
    this.reconnectRenderedBaseline = 0;
    this.resetVideoSync();
    this.attachedSurface = '';
    this.lastRenderedNotice = 0;
    await this.sendCommand('joinShare', { connectId: connectId, verifyCode: verifyCode });
  }

  async disconnect(): Promise<void> {
    this.clearBackgroundResume();
    this.directDeviceId = '';
    await this.closeSession();
  }

  private closeSession(): Promise<void> {
    if (this.disconnectTask === null) {
      this.disconnectTask = this.operation('disconnect', {}).finally(() => { this.disconnectTask = null; });
    }
    return this.disconnectTask;
  }

  async sendInput(json: string): Promise<void> {
    if (this.pipActive || this.session.phase === SessionPhase.Reconnecting) { return; }
    await this.sendCommand('sendInput', { json: json });
    if (BuildProfile.DEBUG && !this.inputLogged) { this.inputLogged = true; console.info('UU_INPUT_COMMAND_ACCEPTED'); }
  }

  async sendText(text: string): Promise<void> {
    if (this.pipActive || this.session.phase === SessionPhase.Reconnecting) { return; }
    await this.sendCommand('sendText', { text: text });
  }

  async releaseAllInput(): Promise<void> {
    await this.sendCommand('releaseAllInput', {});
  }

  async setViewOnly(viewOnly: boolean): Promise<void> {
    await this.sendCommand('setViewOnly', { viewOnly: viewOnly || this.pipActive });
  }

  async attachSurface(surfaceId: string, width: number, height: number): Promise<void> {
    await this.sendCommand('attachSurface', {
      surfaceId: surfaceId,
      width: Math.round(width),
      height: Math.round(height)
    });
    this.attachedSurface = surfaceId;
  }

  async detachSurface(surfaceId: string): Promise<void> {
    await this.sendCommand('detachSurface', { surfaceId: surfaceId });
    if (this.attachedSurface === surfaceId) {
      this.attachedSurface = '';
    }
  }

  async resizeViewport(width: number, height: number): Promise<void> {
    await this.sendCommand('resizeViewport', { width: Math.round(width), height: Math.round(height) });
  }

  private fingerprintScope(): string | null {
    const targetId = this.session.targetId;
    if (this.unlockAccountId.length === 0 || !this.login.authenticated || targetId.length === 0 ||
      this.session.phase === SessionPhase.Ended || this.session.viewOnly || this.pipActive ||
      this.session.remoteUnlock?.supported !== true || !this.devices.devices.some((device: DeviceInfo) => device.id === targetId)) {
      return null;
    }
    return JSON.stringify([this.unlockAccountId, targetId]);
  }

  fingerprintUnlockAvailable(): boolean {
    return this.fingerprintScope() !== null && RemoteUnlockCredentials.available();
  }

  async hasFingerprintUnlockPassword(): Promise<boolean> {
    const scope = this.fingerprintScope();
    return scope !== null && await RemoteUnlockCredentials.has(scope);
  }

  async saveFingerprintUnlockPassword(password: string): Promise<void> {
    const scope = this.fingerprintScope();
    if (scope === null || !RemoteUnlockCredentials.available()) { throw new Error(tr('当前会话无法使用指纹解锁。')); }
    await RemoteUnlockCredentials.save(scope, password);
  }

  async removeFingerprintUnlockPassword(): Promise<void> {
    const scope = this.fingerprintScope();
    if (scope === null) { throw new Error(tr('当前会话无法使用指纹解锁。')); }
    await RemoteUnlockCredentials.remove(scope);
  }

  async fingerprintUnlock(): Promise<void> {
    const scope = this.fingerprintScope();
    const generation = this.session.generation;
    const targetId = this.session.targetId;
    if (scope === null || this.session.remoteUnlock?.locked !== true || this.fingerprintUnlockPending) {
      throw new Error(tr('当前会话无法使用指纹解锁。'));
    }
    this.fingerprintUnlockPending = true;
    try {
      let password: string | null;
      try { password = await RemoteUnlockCredentials.read(scope, tr('指纹解锁')); }
      catch (_) { throw new Error(tr('无法读取已保存的登录密码。')); }
      if (password === null) { return; }
      if (scope !== this.fingerprintScope() || generation !== this.session.generation ||
        this.session.remoteUnlock?.locked !== true) {
        throw new Error(tr('当前会话无法使用指纹解锁。'));
      }
      await this.operation('unlockRemote', { generation: generation, targetId: targetId, password: password },
        'unlockRemote.' + generation);
    } finally {
      this.fingerprintUnlockPending = false;
    }
  }

  // ---- settings ------------------------------------------------------------

  private async loadSettings(): Promise<void> {
    if (this.store === null) {
      return;
    }
    const theme = await this.store.get('themePreference', 'system') as string;
    const material = await this.store.get('materialPreference', 'system') as string;
    const profile = await this.store.get('defaultVideoProfile', 'auto') as string;
    const quality = await this.store.get('defaultVideoQuality', 'auto') as string;
    const frameRate = await this.store.get('defaultFrameRate', 60) as number;
    const trueColor = await this.store.get('trueColor', false) as boolean;
    const touch = await this.store.get('touchMode', 'trackpad') as string;
    const clipboard = await this.store.get('clipboardPolicy', 'manual') as string;
    const keepScreenOn = await this.store.get('keepScreenOn', false) as boolean;
    const backgroundRemoteControl = await this.store.get('backgroundRemoteControl', true) as boolean;
    const autoStartPiP = await this.store.get('autoStartPiP', false) as boolean;
    const smartReachEnabled = await this.store.get('smartReachEnabled', true) as boolean;
    const position = await this.store.get('controlBarPosition', 'center') as string;
    this.settingsState = {
      themePreference: theme as ThemePreference,
      materialPreference: material === 'exquisite' || material === 'gentle' || material === 'smooth' ? material : 'system',
      defaultVideoProfile: profile,
      defaultVideoQuality: quality as VideoQuality,
      defaultFrameRate: frameRate,
      trueColor: trueColor,
      touchMode: touch === 'direct' ? 'direct' : 'trackpad',
      clipboardPolicy: clipboard as ClipboardPolicy,
      keepScreenOn: keepScreenOn,
      backgroundRemoteControl: backgroundRemoteControl,
      autoStartPiP: autoStartPiP,
      smartReachEnabled: smartReachEnabled,
      controlBarPosition: position === 'left' || position === 'right' ? position : 'center'
    };
    this.settingsLoaded = true;
    applyMaterialPreference(this.settingsState.materialPreference);
  }

  /** Restores the persisted choices into the Rust core before the first connection. */
  /**
   * Feeds the probed AVC decoder ceiling into the shared core before any saved
   * true-color/frame-rate choice is applied. A failed probe stays at the
   * conservative 4:2:0 / 60 fps baseline.
   */
  private async applyDecoderCapabilities(): Promise<void> {
    let maxFps = 60;
    let chroma444 = false;
    let hevc = false;
    let maxWidth = 1920;
    let maxHeight = 1080;
    try {
      const raw = this.module.decoderCaps(this.handle);
      if (raw.length > 0) {
        const caps = JSON.parse(raw) as DecoderCaps;
        if (caps.maxFps > 0) {
          maxFps = caps.maxFps;
        }
        chroma444 = caps.chroma444 === true;
        hevc = caps.hevc === true;
        maxWidth = caps.maxWidth > 0 ? caps.maxWidth : 1920;
        maxHeight = caps.maxHeight > 0 ? caps.maxHeight : 1080;
      }
    } catch (error) {
      maxFps = 60;
      chroma444 = false;
    }
    try {
      const screen = display.getDefaultDisplaySync();
      const refreshRate = Math.round(screen.refreshRate);
      if (refreshRate > 0 && refreshRate < maxFps) {
        maxFps = refreshRate;
      }
    } catch (error) {
      // A display query failure leaves the codec ceiling in place.
    }
    AppStorage.setOrCreate('decoderMaxFps', maxFps);
    AppStorage.setOrCreate('decoderMaxWidth', maxWidth);
    AppStorage.setOrCreate('decoderMaxHeight', maxHeight);
    AppStorage.setOrCreate('decoderChroma444', chroma444);
    await this.sendCommand('setDecoderCaps', { maxFps: maxFps, chroma444: chroma444, hevc: hevc, maxWidth: maxWidth, maxHeight: maxHeight });
  }

  private async applyPersistedSettings(): Promise<void> {
    await this.sendCommand('setVideoSettings', {
      quality: this.settingsState.defaultVideoQuality,
      fps: this.settingsState.defaultFrameRate,
      trueColor: this.settingsState.trueColor,
      profile: this.settingsState.defaultVideoProfile
    });
    await this.sendCommand('setTouchMode', { mode: this.settingsState.touchMode });
  }

  private async persist(key: string, value: string | number | boolean): Promise<void> {
    if (this.store === null) {
      return;
    }
    await this.store.put(key, value);
    await this.store.flush();
  }

  async setTheme(preference: ThemePreference): Promise<void> {
    const settings = this.copySettings();
    settings.themePreference = preference;
    this.settingsState = settings;
    await this.persist('themePreference', preference);
    AppStorage.setOrCreate('themePreference', preference);
  }

  async setVideoProfile(profile: string): Promise<void> {
    const settings = this.copySettings();
    settings.defaultVideoProfile = profile;
    this.settingsState = settings;
    await this.persist('defaultVideoProfile', profile);
    await this.sendCommand('setVideoProfile', { profile: profile });
  }

  async setVideoQuality(quality: string): Promise<void> {
    const settings = this.copySettings();
    settings.defaultVideoQuality = quality as VideoQuality;
    this.settingsState = settings;
    await this.persist('defaultVideoQuality', quality);
    await this.sendCommand('setVideoQuality', { quality: quality });
  }

  async setFrameRate(fps: number): Promise<void> {
    const settings = this.copySettings();
    settings.defaultFrameRate = fps;
    this.settingsState = settings;
    await this.persist('defaultFrameRate', fps);
    await this.sendCommand('setFrameRate', { fps: fps });
  }

  async setTrueColor(enabled: boolean): Promise<void> {
    const settings = this.copySettings();
    settings.trueColor = enabled;
    this.settingsState = settings;
    await this.persist('trueColor', enabled);
    await this.sendCommand('setTrueColor', { enabled: enabled });
  }

  async setAudioMuted(muted: boolean): Promise<void> {
    await this.sendCommand('setAudioMuted', { muted: muted });
    this.audioMutedState = muted;
    this.updateBackground();
  }

  async setAudioVolume(volume: number): Promise<void> {
    if (!Number.isFinite(volume) || volume < 0 || volume > 100) { throw new Error(tr('音量应在 0–100 之间')); }
    if (nativeCore.setAudioVolume(this.handle, Math.round(volume) / 100) !== 0) { throw new Error(tr('音量调整失败')); }
    await super.setAudioVolume(volume);
    this.updateBackground();
  }

  private updateBackground(): void {
    const active = this.settingsState.backgroundRemoteControl && this.session.phase !== SessionPhase.Ended &&
      this.session.generation > this.reconnectGeneration;
    const connected = active && (this.session.phase === SessionPhase.Playing || this.session.phase === SessionPhase.ViewOnly);
    const audioPlaying = active && this.audioStarted && !this.audioMutedState && this.audioVolumeState > 0;
    this.background?.update(active ? this.session.generation : -1, connected, audioPlaying,
      active ? this.session.targetName : '');
  }

  setAppForeground(foreground: boolean): void {
    if (this.foreground === foreground) { return; }
    this.foreground = foreground;
    if (foreground) {
      // The core may report a socket failure only after the app has thawed.
      this.resumeUntil = Date.now() + 15000;
      this.resumeRemoteDevice();
    } else if (this.settingsState.backgroundRemoteControl && Router.current() === 'session' &&
      this.session.phase !== SessionPhase.Ended &&
      this.session.firstFrameReceived && this.session.targetId === this.directDeviceId && this.directDeviceId.length > 0) {
      this.backgroundGeneration = this.session.generation;
    }
  }

  private queueBackgroundResume(snapshot: SessionSnapshot): boolean {
    if (snapshot.phase !== SessionPhase.Ended || snapshot.generation !== this.backgroundGeneration ||
      !this.settingsState.backgroundRemoteControl || Router.current() !== 'session' ||
      (this.foreground && Date.now() > this.resumeUntil) ||
      (snapshot.error !== tr('peer connection closed') && snapshot.error !== tr('video track ended'))) { return false; }
    this.backgroundGeneration = -1;
    this.resumeDeviceId = this.directDeviceId;
    this.reconnectGeneration = snapshot.generation;
    const reconnecting = this.copySession();
    reconnecting.phase = SessionPhase.Reconnecting;
    reconnecting.firstFrameReceived = false;
    reconnecting.error = null;
    this.session = reconnecting;
    this.background?.update(-1, false, false);
    this.emitSession();
    this.resumeRemoteDevice();
    return true;
  }

  private resumeRemoteDevice(): void {
    if (!this.foreground || this.resumeDeviceId.length === 0 || Router.current() !== 'session') { return; }
    const deviceId = this.resumeDeviceId;
    this.resumeDeviceId = '';
    const epoch = ++this.resumeEpoch;
    this.reconnectCleaning = true;
    this.closeSession().catch((error: Error) => {
      // The dead socket cannot acknowledge leave. Local cleanup still completed; rejoin without takeover.
      if (error.message !== tr('信令清理失败，远端会话释放尚未确认') &&
        error.message !== tr('信令清理超时，远端会话释放尚未确认')) { throw error; }
    }).then(() => {
      if (epoch !== this.resumeEpoch) { return; }
      this.reconnectCleaning = false;
      if (!this.foreground) { this.resumeDeviceId = deviceId; return; }
      if (Router.current() !== 'session') { return; }
      this.reconnectRenderedBaseline = this.counters.framesRendered;
      this.resetVideoSync();
      this.lastRenderedNotice = 0;
      console.info('UU_BG_REMOTE reconnect requested');
      return this.sendCommand('connect', { deviceId: deviceId, force: false });
    }).catch((error: Error) => {
      if (epoch !== this.resumeEpoch || this.session.phase !== SessionPhase.Reconnecting) { return; }
      this.reconnectCleaning = false;
      const ended = this.copySession();
      ended.phase = SessionPhase.Ended;
      ended.error = error.message;
      this.session = ended;
      this.emitSession();
    });
  }

  private clearBackgroundResume(): void {
    this.resumeEpoch++;
    this.reconnectCleaning = false;
    this.backgroundGeneration = -1;
    this.resumeDeviceId = '';
    this.reconnectGeneration = -1;
  }

  setTouchMode(mode: TouchMode): Promise<void> {
    const update = this.touchModeWrite.catch(() => {}).then(async () => {
      await this.persist('touchMode', mode);
      await this.sendCommand('setTouchMode', { mode: mode });
      const settings = this.copySettings();
      settings.touchMode = mode;
      this.settingsState = settings;
      this.publishTouchMode();
    });
    this.touchModeWrite = update;
    return update;
  }

  async setClipboardPolicy(policy: ClipboardPolicy): Promise<void> {
    const settings = this.copySettings();
    settings.clipboardPolicy = policy;
    this.settingsState = settings;
    await this.persist('clipboardPolicy', policy);
  }

  async setKeepScreenOn(enabled: boolean): Promise<void> {
    await super.setKeepScreenOn(enabled);
    await this.persist('keepScreenOn', enabled);
  }

  setBackgroundRemoteControl(enabled: boolean): Promise<void> {
    const update = this.backgroundPreferenceWrite.catch(() => {}).then(async () => {
      await this.persist('backgroundRemoteControl', enabled);
      await super.setBackgroundRemoteControl(enabled);
      if (!enabled) { this.clearBackgroundResume(); }
      this.updateBackground();
    });
    this.backgroundPreferenceWrite = update;
    return update;
  }

  async setAutoStartPiP(enabled: boolean): Promise<void> {
    await super.setAutoStartPiP(enabled);
    await this.persist('autoStartPiP', enabled);
  }

  async setMaterialPreference(preference: MaterialPreference): Promise<void> {
    await super.setMaterialPreference(preference);
    await this.persist('materialPreference', preference);
  }

  async setSmartReachEnabled(enabled: boolean): Promise<void> {
    await super.setSmartReachEnabled(enabled);
    await this.persist('smartReachEnabled', enabled);
  }

  async setControlBarPosition(position: ControlBarPosition): Promise<void> {
    await super.setControlBarPosition(position);
    await this.persist('controlBarPosition', position);
  }

  // ---- files ---------------------------------------------------------------

  private applyTransferEvent(event: TransferEvent): void {
    const id = event.id ?? '0';
    if (id === '0') {
      if (event.localPath !== undefined) {
        this.pendingDownloads.delete(event.localPath);
        this.removeCachedFile(event.localPath);
      }
      this.files = this.filesWith(this.files, this.files.transfers, event.error ?? tr('文件传输失败'));
      this.emitFiles();
      return;
    }
    const localPath = event.localPath ?? '';
    if (localPath.length > 0) {
      this.transferPaths.set(id, localPath);
      const target = this.pendingDownloads.get(localPath);
      if (target !== undefined) {
        this.transferTargets.set(id, target);
        this.pendingDownloads.delete(localPath);
      }
    }
    const transfers: TransferInfo[] = this.files.transfers.slice();
    const index = transfers.findIndex((item: TransferInfo) => item.id === id);
    const finalState = event.state ?? 'running';
    const state = finalState === 'completed' && this.transferTargets.has(id) ? 'saving' : finalState;
    if (index >= 0) {
      const current = transfers[index];
      transfers[index] = {
        id: current.id,
        name: current.name,
        state: state,
        totalBytes: event.totalBytes ?? current.totalBytes,
        transferredBytes: event.transferredBytes ?? current.transferredBytes,
        localUri: localPath.length > 0 ? localPath : current.localUri,
        remotePath: event.remotePath ?? current.remotePath,
        isMock: current.isMock
      };
    } else {
      transfers.push({
        id: id,
        name: event.name ?? tr('文件'),
        state: state,
        totalBytes: event.totalBytes ?? 0,
        transferredBytes: event.transferredBytes ?? 0,
        localUri: localPath,
        remotePath: event.remotePath ?? '',
        isMock: false
      });
    }
    this.files = this.filesWith(this.files, transfers, event.error ?? null);
    this.emitFiles();
    if (finalState === 'completed' || finalState === 'failed' || finalState === 'canceled') {
      this.finishTransfer(id, finalState === 'completed');
    }
  }

  private async finishTransfer(id: string, completed: boolean): Promise<void> {
    const local = this.transferPaths.get(id);
    if (local === undefined) { return; }
    const target = this.transferTargets.get(id);
    this.transferPaths.delete(id);
    this.transferTargets.delete(id);
    let state = completed ? 'completed' : '';
    let error: string | null = null;
    try {
      if (completed && target !== undefined) {
        if (fs.statSync(local).isDirectory()) { await fs.copy(fileUri.getUriFromPath(local), target); }
        else { await this.copyFileToUri(local, target); }
      }
    } catch (failure) { state = 'failed'; error = tr('无法保存下载文件到所选位置'); }
    finally { this.removeCachedFile(local); }
    if (state.length > 0) {
      const transfers = this.files.transfers.slice();
      const index = transfers.findIndex((item: TransferInfo) => item.id === id);
      if (index >= 0) { transfers[index].state = state; }
      this.files = this.filesWith(this.files, transfers, error);
      this.emitFiles();
    }
  }

  private async copyFileToUri(source: string, target: string): Promise<void> {
    const src = fs.openSync(source, fs.OpenMode.READ_ONLY);
    try {
      const dst = fs.openSync(target, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        await fs.copyFile(src.fd, dst.fd);
      } finally {
        fs.closeSync(dst);
      }
    } finally {
      fs.closeSync(src);
    }
  }

  private removeCachedFile(path: string): void {
    if (this.context === null || !path.startsWith(this.context.cacheDir + '/uu-')) { return; }
    try {
      if (fs.statSync(path).isDirectory()) { fs.rmdirSync(path); }
      else { fs.unlinkSync(path); }
      const parent = path.substring(0, path.lastIndexOf('/'));
      if (parent.startsWith(this.context.cacheDir + '/uu-transfer-')) { fs.rmdirSync(parent); }
    } catch (error) { /* A canceled transfer may not have created its file yet. */ }
  }

  private resetTools(): void {
    this.cursor = null; this.emitCursor();
    this.remoteClipboard = null;
    this.terminalBuffers.clear();
    this.transferPaths.forEach((path: string) => { this.removeCachedFile(path); });
    this.pendingDownloads.forEach((target: string, path: string) => { this.removeCachedFile(path); });
    this.transferPaths.clear(); this.transferTargets.clear(); this.pendingDownloads.clear();
    this.files = { phase: 'loading', path: ':/', entries: [], transfers: [], error: null };
    this.terminal = { phase: 'disconnected', sessionId: '', output: '', error: null };
    this.portMap = { phase: 'editing', rule: null, rules: [], statusText: '', error: null, boundAddress: '' };
    this.emitFiles(); this.emitTerminal(); this.emitPortMap();
  }

  private safeName(path: string): string {
    const raw = path.split(/[\\/]/).pop() ?? 'file.bin';
    return raw.replace(/[\\/\u0000-\u001f]/g, '_').replace(/^\.+$/, '_') || 'file';
  }

  private async stageUpload(uri: string): Promise<string> {
    const context = this.context;
    if (context === null) {
      throw new Error('context unavailable');
    }
    const path = `${context.cacheDir}/uu-upload-${Date.now()}-${this.safeName(uri)}`;
    try {
      const src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        const dst = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        try { await fs.copyFile(src.fd, dst.fd); }
        finally { fs.closeSync(dst); }
      } finally {
        fs.closeSync(src);
      }
    } catch (error) {
      this.removeCachedFile(path);
      throw error as Error;
    }
    return path;
  }

  private stageDownload(remotePath: string): string {
    const context = this.context;
    if (context === null) {
      throw new Error('context unavailable');
    }
    const root = `${context.cacheDir}/uu-transfer-${Date.now()}`;
    fs.mkdirSync(root);
    return `${root}/${this.safeName(remotePath)}`;
  }

  async openFiles(path: string): Promise<void> {
    await this.sendCommand('openFiles', { path: path });
  }

  async startTransfer(remotePath: string, localUri: string, upload: boolean): Promise<void> {
    let localPath = '';
    try {
      localPath = localUri;
      if (upload) {
        localPath = await this.stageUpload(localUri);
      } else {
        const staged = this.stageDownload(remotePath);
        this.pendingDownloads.set(staged, localUri);
        localPath = staged;
      }
      await this.sendCommand('startTransfer', {
        remotePath: remotePath,
        localPath: localPath,
        upload: upload
      });
    } catch (error) {
      this.pendingDownloads.delete(localPath);
      this.removeCachedFile(localPath);
      this.files = this.filesWith(this.files, this.files.transfers, tr('无法准备本地文件'));
      this.emitFiles();
    }
  }

  async cancelTransfer(transferId: string): Promise<void> {
    await this.sendCommand('cancelTransfer', { transferId: transferId });
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
    await this.sendCommand('openTerminal', {});
  }

  async terminalSessions(): Promise<void> { await this.sendCommand('terminalSessions', {}); }
  async attachTerminal(id: number): Promise<void> { await this.sendCommand('attachTerminal', { ptyId: id }); }
  async killTerminal(id: number): Promise<void> { await this.operation('killTerminal', { ptyId: id }); await this.terminalSessions(); }
  async terminalWrite(text: string): Promise<void> {
    await this.sendCommand('terminalWrite', { text: text });
  }

  async terminalResize(columns: number, rows: number): Promise<void> {
    await this.sendCommand('terminalResize', { columns: columns, rows: rows });
  }

  async closeTerminal(): Promise<void> {
    await this.sendCommand('closeTerminal', {});
  }

  // ---- port mapping --------------------------------------------------------

  async startPortMap(rule: PortMapRule): Promise<void> {
    this.portMap = { phase: 'starting', rule: this.portMap.rule, rules: this.portMap.rules, statusText: '', error: null, boundAddress: '' };
    this.emitPortMap();
    try {
    await this.sendCommand('startPortMap', {
      id: rule.id,
      listenAddress: rule.listenAddress,
      listenPort: rule.listenPort,
      targetHost: rule.targetHost,
      targetPort: rule.targetPort,
      allowLan: rule.allowLan
    });
    } catch (error) {
      this.portMap.phase = (this.portMap.rules?.length ?? 0) > 0 ? 'running' : 'failed';
      this.portMap.error = (error as Error).message;
      this.emitPortMap();
    }
  }

  async stopPortMap(id?: string): Promise<void> {
    await this.sendCommand('stopPortMap', { id: id });
  }

  // ---- host ----------------------------------------------------------------

  async requestCaptureConsent(): Promise<void> {
    await this.sendCommand('requestCaptureConsent', {});
  }

  async requestInputConsent(): Promise<void> {
    await this.sendCommand('requestInputConsent', {});
  }

  async stopHost(): Promise<void> {
    await this.sendCommand('stopHost', {});
  }

  async logout(): Promise<void> {
    this.clearBackgroundResume();
    this.directDeviceId = '';
    this.login.generation++;
    this.devices.generation++;
    await this.sendCommand('logout', {});
    this.publishAccountIdSuffix('');
    await this.credentialWrite.catch(() => {});
    await CredentialStore.clear();
    Router.reset('login');
  }
}
