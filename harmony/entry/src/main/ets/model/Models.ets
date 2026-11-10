/**
 * Shared view-state shapes. Pages hold snapshots produced by a SessionService;
 * they never own a second account or session state.
 */

export enum LoginPhase {
  LoadingQr = 'loadingQr',
  WaitingScan = 'waitingScan',
  WaitingConfirm = 'waitingConfirm',
  Finalizing = 'finalizing',
  Expired = 'expired',
  QueryFailed = 'queryFailed',
  Failed = 'failed',
  Authenticated = 'authenticated'
}

export interface LoginSnapshot {
  phase: LoginPhase;
  statusText: string;
  qrPayload: string | null;
  pollingActive: boolean;
  authenticated: boolean;
  error: string | null;
  generation: number;
}

export interface DeviceInfo {
  id: string;
  name: string;
  platform: string;
  online: boolean;
  statusText: string;
  capabilities: string[];
  connectLabel: string;
  busy?: boolean;
  controlled?: boolean;
  shared?: boolean;
}

export enum DeviceListPhase {
  Loading = 'loading',
  Empty = 'empty',
  Ready = 'ready',
  RefreshFailed = 'refreshFailed',
  AuthExpired = 'authExpired'
}

export interface DevicesSnapshot {
  phase: DeviceListPhase;
  devices: DeviceInfo[];
  error: string | null;
  generation: number;
}

export enum SessionPhase {
  Connecting = 'connecting',
  Negotiating = 'negotiating',
  WaitingFirstFrame = 'waitingFirstFrame',
  Playing = 'playing',
  Reconnecting = 'reconnecting',
  ViewOnly = 'viewOnly',
  Ended = 'ended'
}

export interface SessionSnapshot {
  phase: SessionPhase;
  sessionId: string;
  generation: number;
  resourceEpoch: number;
  targetId: string;
  targetName: string;
  viewOnly: boolean;
  firstFrameReceived: boolean;
  error: string | null;
  videoWidth: number;
  videoHeight: number;
  remoteCursorInVideo?: boolean;
  remoteUnlock?: RemoteUnlockState;
}

export interface RemoteUnlockState {
  generation: number;
  locked: boolean;
  supported: boolean;
}

export interface TextInputState {
  composing: boolean;
  commitText: string;
}

export interface TransferInfo {
  id: string;
  name: string;
  state: string;
  totalBytes: number;
  transferredBytes: number;
  localUri: string;
  remotePath: string;
  isMock: boolean;
}

export interface FileEntry {
  name: string;
  path: string;
  isDirectory: boolean;
  sizeBytes: number;
}

export interface FilesSnapshot {
  phase: string;
  path: string;
  entries: FileEntry[];
  transfers: TransferInfo[];
  error: string | null;
}

export interface PortMapRule {
  id: string;
  listenAddress: string;
  listenPort: number;
  targetHost: string;
  targetPort: number;
  allowLan: boolean;
}

export interface PortMapSnapshot {
  rules?: PortMapRule[];
  phase: string;
  rule: PortMapRule | null;
  statusText: string;
  error: string | null;
  boundAddress: string;
}

export type ThemePreference = 'system' | 'light' | 'dark';
export type MaterialPreference = 'system' | 'exquisite' | 'gentle' | 'smooth';
export type TouchMode = 'trackpad' | 'direct';
export type ClipboardPolicy = 'manual' | 'autoForeground';
/** Wire quality presets: 自动 / 原画 20M / 超清 8M / 高清 2M. */
export type VideoQuality = 'auto' | 'original' | 'ultra' | 'hd';
export type ControlBarPosition = 'center' | 'left' | 'right';

export interface SettingsState {
  themePreference: ThemePreference;
  materialPreference: MaterialPreference;
  /** Stream resolution profile; quality and frame rate are separate settings. */
  defaultVideoProfile: string;
  defaultVideoQuality: VideoQuality;
  defaultFrameRate: number;
  trueColor: boolean;
  touchMode: TouchMode;
  clipboardPolicy: ClipboardPolicy;
  keepScreenOn: boolean;
  autoStartPiP: boolean;
  smartReachEnabled: boolean;
  controlBarPosition: ControlBarPosition;
}

/** CaptureSettingSync: what the host actually encodes. */
export interface VideoSyncState {
  fps: number;
  quality: number;
  chroma: number;
  width: number;
  height: number;
  resolutionModes?: VideoResolution[];
}

export interface VideoResolution {
  width: number;
  height: number;
}

export interface HostCapabilities {
  capture: boolean;
  inputInjection: boolean;
  background: boolean;
  inputScope: string;
  reason: string;
}

export interface HostSnapshot {
  phase: 'unsupported' | 'waitingConsent' | 'sharing' | 'controlled' | 'revoked';
  capabilities: HostCapabilities;
  statusText: string;
}

export interface ServiceEvent {
  type: string;
  sessionId?: string;
  generation?: number;
  data?: string;
}

export interface CredentialsPayload {
  userId: string;
  deviceId: string;
  clientId: string;
  systemId: string;
  token: string;
  csrf: string;
}

export interface CoreStats {
  route?: string;
  fps?: number;
  kbps?: number;
  inputCommands?: number;
  inputMessages?: number;
  mediaPackets: number;
  framesDecoded: number;
  framesRendered: number;
  framesSubmitted?: number;
  framesDropped?: number;
  framesPushed?: number;
  pushFailures?: number;
  pictureUnits?: number;
  configUnits?: number;
  otherUnits?: number;
  ptsRegressions?: number;
  renderFailures?: number;
  lastInputPtsUs?: number;
  lastOutputPtsUs?: number;
  inputCallbacks?: number;
  outputCallbacks?: number;
  decoderResets?: number;
  decoderError?: number;
  pendingInputs?: number;
  queuedUnits?: number;
  audioFrames: number;
  rttMs: number | null;
}

export interface TerminalSessionInfo { sessionId: number; shell: string; state: string; }
export interface TerminalSnapshot {
  ptyId?: number;
  sessions?: TerminalSessionInfo[];
  phase: 'connecting' | 'ready' | 'disconnected' | 'failed';
  sessionId: string;
  output: string;
  error: string | null;
}

export interface RemoteCursor { generation: number; png: string; width: number; height: number; hotX: number; hotY: number; }
