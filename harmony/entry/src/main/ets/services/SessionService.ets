import { common } from '@kit.AbilityKit';
import {
  RemoteCursor,
  ClipboardPolicy,
  ControlBarPosition,
  CoreStats,
  DevicesSnapshot,
  FilesSnapshot,
  HostSnapshot,
  LoginSnapshot,
  PortMapRule,
  PortMapSnapshot,
  SessionSnapshot,
  SettingsState,
  TerminalSnapshot,
  ThemePreference,
  MaterialPreference,
  TouchMode,
  VideoSyncState
} from '../model/Models';

export type CursorListener = (cursor: RemoteCursor | null) => void;
export type LoginListener = (snapshot: LoginSnapshot) => void;
export type DevicesListener = (snapshot: DevicesSnapshot) => void;
export type SessionListener = (snapshot: SessionSnapshot) => void;
export type FilesListener = (snapshot: FilesSnapshot) => void;
export type TerminalDataListener = (text: string) => void;
export type TerminalListener = (snapshot: TerminalSnapshot) => void;
export type PortMapListener = (snapshot: PortMapSnapshot) => void;
export type HostListener = (snapshot: HostSnapshot) => void;

/**
 * The only state owner shared by PC, Pad and Phone. Pages subscribe and send
 * operations; they never keep a second account or session.
 */
export interface SessionService {
  readonly kind: string;

  init(context: common.UIAbilityContext): Promise<void>;
  dispose(): void;

  loginSnapshot(): LoginSnapshot;
  loginStart(): Promise<void>;
  loginCancel(): Promise<void>;
  onLogin(listener: LoginListener): () => void;

  devicesSnapshot(): DevicesSnapshot;
  listDevices(automatic?: boolean): Promise<void>;
  selectTarget(deviceId: string): Promise<void>;
  unbindDevice(deviceId: string, shared: boolean): Promise<void>;
  wakeDevice(deviceId: string): Promise<void>;
  syncClipboard(receive: boolean): Promise<void>;
  remoteAction(action: string, enabled: boolean): Promise<void>;
  mkdir(path: string): Promise<void>;

  onDevices(listener: DevicesListener): () => void;

  sessionSnapshot(): SessionSnapshot;
  connect(deviceId: string, force?: boolean): Promise<void>;
  joinShare(connectId: string, verifyCode: string): Promise<void>;
  disconnect(): Promise<void>;
  onSession(listener: SessionListener): () => void;

  cursorSnapshot(): RemoteCursor | null;
  onCursor(listener: CursorListener): () => void;
  sendInput(json: string): Promise<void>;
  sendText(text: string): Promise<void>;
  releaseAllInput(): Promise<void>;
  setViewOnly(viewOnly: boolean): Promise<void>;
  setPiPActive(active: boolean): Promise<void>;
  attachSurface(surfaceId: string, width: number, height: number): Promise<void>;
  detachSurface(surfaceId: string): Promise<void>;
  resizeViewport(width: number, height: number): Promise<void>;
  fingerprintUnlockAvailable(): boolean;
  hasFingerprintUnlockPassword(): Promise<boolean>;
  saveFingerprintUnlockPassword(password: string): Promise<void>;
  removeFingerprintUnlockPassword(): Promise<void>;
  fingerprintUnlock(): Promise<void>;

  settings(): SettingsState;
  setTheme(preference: ThemePreference): Promise<void>;
  setMaterialPreference(preference: MaterialPreference): Promise<void>;
  setVideoProfile(profile: string): Promise<void>;
  setVideoQuality(quality: string): Promise<void>;
  setFrameRate(fps: number): Promise<void>;
  setTrueColor(enabled: boolean): Promise<void>;
  setTouchMode(mode: TouchMode): Promise<void>;
  setClipboardPolicy(policy: ClipboardPolicy): Promise<void>;
  setKeepScreenOn(enabled: boolean): Promise<void>;
  setBackgroundRemoteControl(enabled: boolean): Promise<void>;
  setAppForeground(foreground: boolean): void;
  setAutoStartPiP(enabled: boolean): Promise<void>;
  setSmartReachEnabled(enabled: boolean): Promise<void>;
  setControlBarPosition(position: ControlBarPosition): Promise<void>;
  setAudioMuted(muted: boolean): Promise<void>;
  setAudioVolume(volume: number): Promise<void>;
  audioVolume(): number;
  audioMuted(): boolean;
  videoSync(): VideoSyncState;

  filesSnapshot(): FilesSnapshot;
  openFiles(path: string): Promise<void>;
  onFiles(listener: FilesListener): () => void;
  startTransfer(remotePath: string, localUri: string, upload: boolean): Promise<void>;
  cancelTransfer(transferId: string): Promise<void>;

  terminalSnapshot(): TerminalSnapshot;
  openTerminal(): Promise<void>;
  terminalSessions(): Promise<void>;
  attachTerminal(id: number): Promise<void>;
  killTerminal(id: number): Promise<void>;
  onTerminalData(listener: TerminalDataListener): () => void;
  terminalWrite(text: string): Promise<void>;
  terminalResize(columns: number, rows: number): Promise<void>;
  closeTerminal(): Promise<void>;
  onTerminal(listener: TerminalListener): () => void;

  portMapSnapshot(): PortMapSnapshot;
  startPortMap(rule: PortMapRule): Promise<void>;
  stopPortMap(id?: string): Promise<void>;
  onPortMap(listener: PortMapListener): () => void;

  hostSnapshot(): HostSnapshot;
  requestCaptureConsent(): Promise<void>;
  requestInputConsent(): Promise<void>;
  stopHost(): Promise<void>;
  onHost(listener: HostListener): () => void;

  logout(): Promise<void>;
  stats(): CoreStats;
}
