import { image } from '@kit.ImageKit';
import { KeyCode, pointer } from '@kit.InputKit';
import { preferences } from '@kit.ArkData';
import { curves, KeyboardAvoidMode, PiPWindow, window } from '@kit.ArkUI';
import { hdsMaterial } from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { util } from '@kit.ArkTS';
import { tr } from '../model/I18n';
import { ControlBarPosition, CoreStats, DeviceInfo, RemoteCursor, SessionPhase, SessionSnapshot,
  TouchMode, VideoResolution } from '../model/Models';
import { Metrics } from '../model/Tokens';
import { Router } from '../model/Router';
import { ServiceHub } from '../services/ServiceHub';
import { SessionService } from '../services/SessionService';
import { SessionToolbar, SessionToolbarAction, SessionToolbarLayout, sessionToolbarLayout } from '../components/SessionToolbar';
import { SessionToolbarEditor } from '../components/SessionToolbarEditor';
import { loadSavedRemoteShortcuts, RemoteKeyboard, RemoteKeyboardMode, Shortcut, WINDOWS_SHOW_DESKTOP } from '../components/RemoteKeyboard';
import { VirtualMouse } from '../components/VirtualMouse';
import { ImmersiveBackdrop } from '../components/ImmersiveBackdrop';
import { iconResource } from '../model/Icons';
import { sessionFloatingControl as floatingControl, sessionMenuMaterial, sessionMenuFrame, floatingFeedback,
  sessionSurfaceControl, sessionMaterialSupported, SessionMaterialBackplate, sessionFloatingIcon,
  buttonPressEdgeLayer, buttonPressShadow, buttonPressShadowSupported, pressedButtonAfterTouch } from '../theme/FloatingMaterial';
import { materialLevel } from '../theme/MaterialPreference';
import { SystemBars } from '../theme/SystemBars';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { KeyMap } from '../model/KeyMap';
import { UiProbe } from '../testkit/UiProbe';
import { VideoViewport } from '../model/VideoViewport';
import { edgeScrollBar } from '../components/EdgeScrollBar';

const TOOLBAR_PREF: string = 'remoteToolbarActions';
const DEFAULT_TOOLBAR: string[] = ['session.rotate', 'session.keyboard', 'session.pip', 'session.showDesktop'];
const HIDE_ALL_TOOLBAR_ACTION: string = 'session.toolbar.hideAll';
const TOOLBAR_MENU_ACTIONS: ToolbarMenuAction[] = [
  { id: 'session.toolbar.audio', menuId: 'session.more.audio', icon: 'volume', label: '音量' },
  { id: 'session.toolbar.picture', menuId: 'session.quality', icon: 'quality', label: '远程画面' },
  { id: 'session.toolbar.input', menuId: 'session.more.input', icon: 'cursor', label: '输入' },
  { id: 'session.toolbar.clipboard', menuId: 'session.more.clipboard', icon: 'clipboard', label: '剪贴板' },
  { id: 'session.toolbar.network', menuId: 'session.more.stats', icon: 'host', label: '网络状态' },
  { id: 'session.toolbar.tools', menuId: 'session.more.tools', icon: 'folder', label: '远程工具' },
  { id: 'session.toolbar.remote', menuId: 'session.more.remote', icon: 'settings', label: '远端操作' }
];
const TOOLBAR_SHORTCUT_PREFIX: string = 'session.shortcut.';
const MAX_TOOLBAR_BUTTONS: number = 6;
const NETWORK_DETAILS_HEIGHT = 64;

interface SessionMenuItem {
  id: string;
  label: string;
  value?: string;
  action: () => void;
  enabled?: boolean;
  selected?: boolean;
  destructive?: boolean;
  volume?: boolean;
  children?: SessionMenuGroup[];
}

interface SessionMenuGroup {
  title: string;
  items: SessionMenuItem[];
}

interface ToolbarMenuAction {
  id: string;
  menuId: string;
  icon: string;
  label: string;
}

@Component
export struct SessionPage {
  @State session: SessionSnapshot = {
    phase: SessionPhase.Connecting,
    sessionId: '',
    generation: 0,
    resourceEpoch: 0,
    targetId: '',
    targetName: '',
    viewOnly: false,
    firstFrameReceived: false,
    error: null,
    videoWidth: 1920,
    videoHeight: 1080
  };
  @StorageProp('decoderMaxFps') maxFps: number = 60;
  @StorageProp('decoderMaxWidth') maxVideoWidth: number = 1920;
  @StorageProp('decoderMaxHeight') maxVideoHeight: number = 1080;
  @StorageProp('decoderChroma444') chroma444: boolean = false;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('hdsMaterialLevel') menuMaterialLevel: hdsMaterial.MaterialLevel = materialLevel();
  @State cleanView: boolean = false;
  @State toolbarButtons: string[] = DEFAULT_TOOLBAR.slice();
  @State toolbarShortcuts: Shortcut[] = [];
  @State toolbarEditorOpen: boolean = false;
  @State toolbarDraft: string[] = [];
  @State toolbarSaving: boolean = false;
  private toolbarStore: preferences.Preferences | null = null;
  @State controlBarPosition: ControlBarPosition = 'center';
  @State keyboardOpen: boolean = false;
  @State keyboardMode: RemoteKeyboardMode = 'text';
  @State keyboardGlobalY: number | null = null;
  @State armedKeyboardKeys: number[] = [];
  @State textValue: string = '';
  @State endDialog: boolean = false;
  @State disconnecting: boolean = false;
  @State audioOn: boolean = true;
  @State volume: number = 100;
  @State networkVisible: boolean = false;
  @State networkStats: CoreStats = { mediaPackets: 0, framesDecoded: 0, framesRendered: 0, audioFrames: 0, rttMs: null };
  private networkTimer: number = -1;
  @StorageProp('remoteTouchMode') touchMode: TouchMode = 'trackpad';
  @State pageWidth: number = 360;
  @State pageHeight: number = 640;
  @State landscape: boolean = false;
  @State rotateEnabled: boolean = false;
  @State orientationPending: boolean = false;
  @State surfaceWidth: number = 328;
  @State surfaceHeight: number = 200;
  @State surfaceId: string = '';
  @State zoomScale: number = 1;
  @State actualSize: boolean = false;
  @State zoomX: number = 0;
  @State zoomY: number = 0;
  private pinchScale: number = 1;
  private pinchAnchorX: number = 0;
  private pinchAnchorY: number = 0;
  private pinching: boolean = false;
  private zoomTouch: boolean = false;
  private zoomMoved: boolean = false;
  private panning: boolean = false;
  private panStartX: number = 0;
  private panStartY: number = 0;
  private orientationTimer: number = -1;
  private surfaceResizeTimer: number = -1;
  @StorageLink('sessionBackRequested') @Watch('onBackRequested') backRequested: number = 0;
  private service: SessionService | null = null;
  private surfaceController: XComponentController = new XComponentController();
  private sessionUnsubscribe: (() => void) | null = null;
  private cursorUnsubscribe: (() => void) | null = null;
  @State cursorPixel: image.PixelMap | null = null;
  private cursorShape: RemoteCursor | null = null;
  private cursorEpoch: number = 0;
  private cursorWindow: number = 0;
  private localPointerHidden: boolean = false;
  @State pointerInside: boolean = false;
  @State cursorX: number = 0.5;
  @State cursorY: number = 0.5;
  private touchScrolling: boolean = false;
  private touchLastX: number = 0;
  private touchLastY: number = 0;
  private touchIgnored: boolean = false;
  private keyboardTimer: number = -1;
  @State menuOpen: boolean = false;
  @State pressedMenuButton: string = '';
  @State pressedMenuItem: string = '';
  private menuTouchId: number | null = null;
  @State menuViewportHeight: number = 640;
  @State menuPath: string[] = [];
  @State toolbarMenuOpen: boolean = false;
  @State toolbarMenuCenterX: number = 0;
  @State actualResolution: string = '';
  @State fingerprintUnlockReady: boolean = false;
  @State fingerprintPasswordSaved: boolean = false;
  @State fingerprintSetupOpen: boolean = false;
  @State fingerprintBusy: boolean = false;
  @State fingerprintPassword: string = '';
  @State menuAnchors: number[] = [];
  @State menuUpwards: boolean[] = [];
  @State virtualMouseVisible: boolean = true;
  @State virtualMouseInitialY: number = -1;
  @State virtualMouseCollapseRequest: number = 0;
  private virtualMouseExpanded: boolean = false;
  @State surfaceGlobalY: number | null = null;
  private controlsGlobalY: number | null = null;
  @State pipSupported: boolean = false;
  private pipController: PiPWindow.PiPController | null = null;
  private pipCreateTask: Promise<void> | null = null;
  private pipState: PiPWindow.PiPState = PiPWindow.PiPState.STOPPED;
  private pipManualStart: boolean = false;
  private pipEpoch: number = 0;
  private pipSize: string = '';
  private pipStopTask: Promise<void> | null = null;
  private menuScrollers: Scroller[] = [new Scroller(), new Scroller(), new Scroller(), new Scroller()];
  private keyboardAvoidMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET;
  private sessionWindow: window.Window | null = null;
  private keepScreenWindow: window.Window | null = null;
  private originalKeepScreenOn: boolean = false;
  private originalOrientation: window.Orientation | null = null;
  private originalNavigationVisible: boolean = false;
  private orientationChanged: boolean = false;
  private active: boolean = false;
  private onSessionWindowSize = (size: window.Size): void => {
    this.menuOpen = false;
    this.landscape = size.width > size.height;
    const previous = this.holdingHandLandscape;
    this.holdingHandLandscape = this.landscape;
    if (previous !== null && previous !== this.landscape) { this.subscribeHoldingHand(); }
  };
  private onSessionWindowEvent = (event: window.WindowEventType): void => {
    if (event === window.WindowEventType.WINDOW_HIDDEN) { this.armedKeyboardKeys = []; }
    if (this.active && event === window.WindowEventType.WINDOW_SHOWN && this.pipState === PiPWindow.PiPState.STARTED) {
      this.pipController?.stopPiP().catch(() => { console.info('Session picture-in-picture window did not stop'); });
    }
  };
  private onPiPState = (state: PiPWindow.PiPState, reason: string): void => {
    console.info('UU_PIP_STATE ' + state);
    this.pipState = state;
    if (state === PiPWindow.PiPState.ABOUT_TO_START || state === PiPWindow.PiPState.STARTED) {
      this.menuOpen = false;
      if (this.keyboardOpen) { this.closeKeyboard(); }
      this.service?.setPiPActive(true).catch((error: Error) => { this.notify(error); });
      if (state === PiPWindow.PiPState.STARTED && this.pipManualStart) {
        this.pipManualStart = false;
        this.backgroundSessionWindow();
      }
    } else if (state === PiPWindow.PiPState.STOPPED || state === PiPWindow.PiPState.ERROR) {
      const manualFailure = this.pipManualStart && state === PiPWindow.PiPState.ERROR;
      this.pipManualStart = false;
      this.service?.setPiPActive(false).catch((error: Error) => { this.notify(error); });
      if (manualFailure) { this.notify(new Error(tr('画中画启动失败，请检查系统画中画设置'))); }
    }
  };
  @State holdingHandSubscribed: boolean = false;
  private holdingHandLandscape: boolean | null = null;
  private onHoldingHandChanged = (status: motion.HoldingHandStatus): void => {
    if (!this.active) { return; }
    console.info('UU_GRIP status=' + status + ' landscape=' + this.landscape);
    const position: ControlBarPosition = status === motion.HoldingHandStatus.LEFT_HAND_HELD ? 'left' :
      status === motion.HoldingHandStatus.RIGHT_HAND_HELD ? 'right' : 'center';
    if (this.landscape && position === 'center') { return; }
    if (position === this.controlBarPosition) { return; }
    this.getUIContext().animateTo({ duration: 260, curve: Curve.Friction }, () => { this.controlBarPosition = position; });
  };

  private unsubscribeHoldingHand(): void {
    if (!this.holdingHandSubscribed) { return; }
    try { motion.off('holdingHandChanged', this.onHoldingHandChanged); }
    catch (error) { console.info('UU_GRIP unsubscribe error=' + (error as BusinessError).code); }
    this.holdingHandSubscribed = false;
  }

  private subscribeHoldingHand(): void {
    this.unsubscribeHoldingHand();
    const settings = this.service?.settings();
    if (settings?.smartReachEnabled !== true || deviceInfo.deviceType === '2in1' ||
      !canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      this.controlBarPosition = settings?.controlBarPosition ?? 'center';
      if (settings?.smartReachEnabled === true) { console.info('UU_GRIP unavailable capability landscape=' + this.landscape); }
      return;
    }
    try {
      motion.on('holdingHandChanged', this.onHoldingHandChanged);
      this.holdingHandSubscribed = true;
      console.info('UU_GRIP subscribed landscape=' + this.landscape);
    } catch (error) {
      this.controlBarPosition = settings.controlBarPosition;
      console.info('UU_GRIP unavailable code=' + (error as BusinessError).code + ' landscape=' + this.landscape);
    }
  }
  private onWindowStatus = (status: window.WindowStatusType): void => {
    this.rotateEnabled = deviceInfo.deviceType !== '2in1' &&
      (status === window.WindowStatusType.FULL_SCREEN || status === window.WindowStatusType.MAXIMIZE);
  };

  aboutToAppear(): void {
    if (!ServiceHub.isReady()) {
      return;
    }
    this.service = ServiceHub.service();
    this.active = true;
    this.pipSupported = canIUse('SystemCapability.Window.SessionManager') && PiPWindow.isPiPEnabled();
    SystemBars.apply(this.getUIContext().getHostContext() as common.UIAbilityContext, true);
    const settings = this.service.settings();
    this.controlBarPosition = settings.smartReachEnabled ? 'center' : settings.controlBarPosition;
    this.subscribeHoldingHand();
    this.keyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.session = this.service.sessionSnapshot();
    this.loadToolbar(this.getUIContext().getHostContext() as common.UIAbilityContext);
    window.getLastWindow(this.getUIContext().getHostContext() as common.UIAbilityContext).then((win: window.Window) => {
      if (!this.active) { return; }
      this.sessionWindow = win;
      win.on('windowEvent', this.onSessionWindowEvent);
      this.cursorWindow = win.getWindowProperties().id;
      if (this.service?.settings().keepScreenOn === true) {
        this.keepScreenWindow = win;
        this.originalKeepScreenOn = win.getWindowProperties().isKeepScreenOn;
        win.setWindowKeepScreenOn(true).then(() => {
          if (!this.active) { win.setWindowKeepScreenOn(this.originalKeepScreenOn).catch(() => {}); }
        }).catch((error: Error) => { if (this.active) { this.notify(error); } });
      }
      if (deviceInfo.deviceType !== '2in1') {
        const navigation = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        this.originalNavigationVisible = [navigation.topRect, navigation.bottomRect, navigation.leftRect, navigation.rightRect]
          .some((area: window.Rect) => area.width > 0 && area.height > 0);
        if (this.originalNavigationVisible) {
          win.setSpecificSystemBarEnabled('navigationIndicator', false, false)
            .catch(() => { console.info('Navigation indicator visibility is managed by the system'); });
        }
        const rect = win.getWindowProperties().windowRect;
        this.onSessionWindowSize({ width: rect.width, height: rect.height });
        win.on('windowSizeChange', this.onSessionWindowSize);
        this.originalOrientation = win.getPreferredOrientation();
        this.onWindowStatus(win.getWindowStatus());
        win.on('windowStatusDidChange', this.onWindowStatus);
      }
    }).catch(() => {});
    this.cursorUnsubscribe = this.service.onCursor((cursor: RemoteCursor | null) => { this.decodeCursor(cursor); });
    this.decodeCursor(this.service.cursorSnapshot());
    this.audioOn = !this.service.audioMuted();
    this.volume = this.service.audioVolume();
    this.refreshActualResolution();
    this.refreshFingerprintUnlock();
    this.sessionUnsubscribe = this.service.onSession((snapshot: SessionSnapshot) => {
      const previousError = this.session.error;
      const previousCursorInVideo = this.cursorInVideo();
      const unlockScopeChanged = snapshot.generation !== this.session.generation || snapshot.targetId !== this.session.targetId ||
        snapshot.viewOnly !== this.session.viewOnly || snapshot.remoteUnlock?.supported !== this.session.remoteUnlock?.supported;
      this.session = snapshot;
      this.refreshActualResolution();
      if (unlockScopeChanged) { this.closeFingerprintSetup(); this.refreshFingerprintUnlock(); }
      if (previousCursorInVideo !== this.cursorInVideo()) { this.applyCursor(); }
      if (snapshot.viewOnly && this.keyboardOpen) { this.closeKeyboard(); }
      this.preparePiP();
      if (snapshot.phase === SessionPhase.Ended) {
        if (!this.disconnecting) { Router.backTo('devices'); }
      } else if (snapshot.error !== null && snapshot.error !== previousError) {
        this.notify(new Error(snapshot.error));
      }
    });
  }

  aboutToDisappear(): void {
    this.active = false;
    this.closeFingerprintSetup();
    this.stopSessionPiP();
    SystemBars.apply(this.getUIContext().getHostContext() as common.UIAbilityContext, this.isDark);
    this.unsubscribeHoldingHand();
    this.holdingHandLandscape = null;
    this.keepScreenWindow?.setWindowKeepScreenOn(this.originalKeepScreenOn).catch(() => {});
    const win = this.sessionWindow;
    win?.off('windowEvent', this.onSessionWindowEvent);
    if (win !== null && deviceInfo.deviceType !== '2in1') {
      win.off('windowSizeChange', this.onSessionWindowSize);
      win.off('windowStatusDidChange', this.onWindowStatus);
      if (this.originalNavigationVisible) {
        win.setSpecificSystemBarEnabled('navigationIndicator', true, false).catch(() => {});
      }
      if (this.orientationChanged && this.originalOrientation !== null) {
        win.setPreferredOrientation(this.originalOrientation).catch(() => {});
      }
    }
    this.getUIContext().setKeyboardAvoidMode(this.keyboardAvoidMode);
    clearTimeout(this.keyboardTimer);
    clearTimeout(this.orientationTimer);
    clearTimeout(this.surfaceResizeTimer);
    clearInterval(this.networkTimer);
    this.menuOpen = false;
    this.cursorUnsubscribe?.(); this.cursorEpoch++; this.pointerInside = false; this.applyCursor();
    this.cursorPixel?.release(); this.cursorPixel = null;
    this.service?.releaseAllInput();
    if (this.sessionUnsubscribe !== null) {
      this.sessionUnsubscribe();
      this.sessionUnsubscribe = null;
    }
  }

  private async preparePiP(): Promise<void> {
    if (!this.active || !this.pipSupported || !this.session.firstFrameReceived || this.surfaceId.length === 0) { return; }
    if (this.pipController !== null) {
      const size = this.session.videoWidth + 'x' + this.session.videoHeight;
      if (size !== this.pipSize) {
        this.pipController.updateContentSize(this.session.videoWidth, this.session.videoHeight);
        this.pipSize = size;
      }
      return;
    }
    if (this.pipCreateTask === null) {
      const epoch = ++this.pipEpoch;
      this.pipCreateTask = this.createSessionPiP(epoch).finally(() => {
        if (epoch === this.pipEpoch) { this.pipCreateTask = null; }
      });
    }
    await this.pipCreateTask;
  }

  private async createSessionPiP(epoch: number): Promise<void> {
    try {
      const controller = await PiPWindow.create({
        context: this.getUIContext().getHostContext() as common.UIAbilityContext,
        componentController: this.surfaceController,
        templateType: PiPWindow.PiPTemplateType.VIDEO_LIVE,
        contentWidth: this.session.videoWidth,
        contentHeight: this.session.videoHeight,
        controlGroups: []
      });
      if (!this.active || epoch !== this.pipEpoch) { return; }
      this.pipController = controller;
      this.pipSize = this.session.videoWidth + 'x' + this.session.videoHeight;
      controller.on('stateChange', (state: PiPWindow.PiPState, reason: string) => {
        if (this.active && epoch === this.pipEpoch) { this.onPiPState(state, reason); }
      });
      controller.setAutoStartEnabled(this.service?.settings().autoStartPiP === true);
    } catch (error) {
      console.info('Session picture-in-picture controller is unavailable');
    }
  }

  private async startSessionPiP(): Promise<void> {
    if (this.pipManualStart || (this.pipState !== PiPWindow.PiPState.STOPPED && this.pipState !== PiPWindow.PiPState.ERROR)) {
      return;
    }
    this.pipManualStart = true;
    this.menuOpen = false;
    try {
      await this.preparePiP();
      if (!this.active || this.disconnecting) { this.pipManualStart = false; return; }
      const controller = this.pipController;
      const win = this.sessionWindow;
      if (controller === null || win === null) { throw new Error('Missing PiP controller or main window'); }
      if (!win.isWindowShowing()) { this.pipManualStart = false; return; }
      await this.service?.setPiPActive(true);
      if (!this.active || this.pipController !== controller) { return; }
      if (!win.isWindowShowing()) {
        this.pipManualStart = false;
        if (this.pipState === PiPWindow.PiPState.STOPPED || this.pipState === PiPWindow.PiPState.ERROR) {
          await this.service?.setPiPActive(false);
        }
        return;
      }
      await controller.startPiP();
    } catch (error) {
      if (!this.active || !this.pipManualStart) { return; }
      this.pipManualStart = false;
      this.pipState = PiPWindow.PiPState.ERROR;
      await this.service?.setPiPActive(false).catch(() => {});
      if (this.active) { this.notify(new Error(tr('画中画启动失败，请检查系统画中画设置'))); }
    }
  }

  private async backgroundSessionWindow(): Promise<void> {
    const win = this.sessionWindow;
    const controller = this.pipController;
    if (win === null || controller === null || !win.isWindowShowing()) { return; }
    try {
      // STARTED means the XComponent has already been transferred to the PiP window.
      if (deviceInfo.deviceType === '2in1') { await win.minimize(); }
      else { await (this.getUIContext().getHostContext() as common.UIAbilityContext).moveAbilityToBackground(); }
    } catch (error) {
      if (!this.active || this.pipController !== controller || !win.isWindowShowing() ||
        this.pipState !== PiPWindow.PiPState.STARTED) { return; }
      await controller.stopPiP().catch(() => {});
      if (this.active) { this.notify(new Error(tr('画中画启动失败，请检查系统画中画设置'))); }
    }
  }

  private stopSessionPiP(): Promise<void> {
    if (this.pipStopTask !== null) { return this.pipStopTask; }
    ++this.pipEpoch;
    this.pipCreateTask = null;
    this.pipState = PiPWindow.PiPState.STOPPED;
    this.pipManualStart = false;
    const controller = this.pipController;
    this.pipController = null;
    this.pipStopTask = (async (): Promise<void> => {
      if (controller !== null) {
        controller.setAutoStartEnabled(false);
        try { await controller.stopPiP(); } catch (error) { /* An idle controller has no window to stop. */ }
        controller.off('stateChange');
      }
      await this.service?.setPiPActive(false);
    })().finally(() => { this.pipStopTask = null; });
    return this.pipStopTask;
  }

  private async decodeCursor(cursor: RemoteCursor | null): Promise<void> {
    const epoch = ++this.cursorEpoch;
    let pixel: image.PixelMap | null = null;
    try {
      if (cursor !== null && cursor.png.length > 0) {
        const bytes = new util.Base64Helper().decodeSync(cursor.png);
        const source = image.createImageSource(bytes.buffer);
        const scale = Math.min(1, 256 / Math.max(cursor.width, cursor.height));
        try { pixel = await source.createPixelMap({ desiredSize: {
          width: Math.max(1, Math.round(cursor.width * scale)), height: Math.max(1, Math.round(cursor.height * scale)) } }); }
        finally { source.release(); }
      }
    } catch (error) { pixel = null; }
    if (epoch !== this.cursorEpoch) { pixel?.release(); return; }
    const previous = this.cursorPixel;
    this.cursorPixel = pixel; this.cursorShape = cursor; this.applyCursor(); previous?.release();
  }

  private cursorInVideo(): boolean {
    return this.session.firstFrameReceived && this.session.remoteCursorInVideo === true;
  }

  private applyCursor(): void {
    if (this.cursorWindow === 0) { return; }
    const shape = this.cursorShape;
    try {
      if (this.pointerInside && this.cursorInVideo()) {
        if (!this.localPointerHidden) {
          pointer.setPointerVisibleSync(false);
          this.localPointerHidden = true;
        }
        return;
      }
      if (this.localPointerHidden) {
        pointer.setPointerVisibleSync(true);
        this.localPointerHidden = false;
      }
      if (this.pointerInside && this.cursorPixel !== null && shape !== null) {
        const scale = Math.min(1, 256 / Math.max(shape.width, shape.height));
        pointer.setCustomCursorSync(this.cursorWindow, this.cursorPixel, Math.round(shape.hotX * scale), Math.round(shape.hotY * scale));
      } else { pointer.setPointerStyleSync(this.cursorWindow, pointer.PointerStyle.DEFAULT); }
    } catch (error) { /* Cursor support differs between device types. */ }
  }

  private cursorSize(): number[] {
    const shape = this.cursorShape;
    if (this.cursorPixel === null || shape === null) { return [24, 24]; }
    const scale = Math.min(1, 48 / Math.max(shape.width, shape.height));
    return [shape.width * scale, shape.height * scale];
  }

  private cursorHotspot(): number[] {
    const shape = this.cursorShape;
    const size = this.cursorSize();
    return this.cursorPixel !== null && shape !== null ?
      [shape.hotX * size[0] / shape.width, shape.hotY * size[1] / shape.height] : [4.56, 4.58];
  }

  private virtualMouseInput(input: string): void {
    const value = JSON.parse(input) as Record<string, string | number>;
    if (value['action'] === 'mouse_move_absolute') {
      this.cursorX = Number(value['abs_x']); this.cursorY = Number(value['abs_y']);
      if (this.pointerInside) { this.pointerInside = false; this.applyCursor(); }
    }
    this.service?.sendInput(input);
  }

  private collapseVirtualMouse(): void {
    if (this.virtualMouseExpanded) {
      this.service?.releaseAllInput();
      this.virtualMouseExpanded = false;
      this.virtualMouseCollapseRequest++;
    }
  }

  private placeVirtualPointer(x: number, y: number, screenX: number, screenY: number): void {
    const rect = this.videoRect();
    const dx = screenX - rect[0] - x * rect[2];
    const dy = screenY - rect[1] - y * rect[3];
    if (Math.abs(dx) > 0.01) { this.zoomX += dx; }
    if (Math.abs(dy) > 0.01) { this.zoomY += dy; }
    this.cursorX = x; this.cursorY = y;
  }

  private placeInitialVirtualMouse(): void {
    if (this.surfaceGlobalY !== null && this.controlsGlobalY !== null && this.surfaceWidth > 0 && this.surfaceHeight > 0) {
      this.virtualMouseInitialY = Math.max(16, this.controlsGlobalY - this.surfaceGlobalY - 8 - 48);
    }
  }

  @Builder
  remotePointer() {
    Stack() {
      Image(this.cursorPixel ?? iconResource('pointer', true, false))
        .width('100%').height('100%').objectFit(ImageFit.Contain)
        .fillColor(this.cursorPixel === null ? $r('sys.color.icon_primary') : undefined)
        .hitTestBehavior(HitTestMode.None).id('session.mouse.pointer')
    }.width(this.cursorSize()[0]).height(this.cursorSize()[1])
      .position({ x: this.videoRect()[0] + this.cursorX * this.videoRect()[2] - this.cursorHotspot()[0],
        y: this.videoRect()[1] + this.cursorY * this.videoRect()[3] - this.cursorHotspot()[1] })
      .accessibilityLevel('no').hitTestBehavior(HitTestMode.None).id('session.cursor')
  }

  onBackRequested(): void {
    if (this.disconnecting) { return; }
    if (this.backRequested > 0) {
      if (this.cleanView) { this.cleanView = false; }
      else if (this.toolbarEditorOpen) { if (!this.toolbarSaving) { this.toolbarEditorOpen = false; } }
      else if (this.fingerprintSetupOpen) { this.closeFingerprintSetup(); }
      else if (this.menuOpen) {
        if (this.menuPath.length > 0) { this.menuBack(); }
        else { this.menuOpen = false; }
      } else if (this.keyboardOpen) { this.closeKeyboard(); }
      else { this.endDialog = true; }
    }
  }

  private enterCleanView(): void {
    this.menuOpen = false;
    if (this.keyboardOpen) { this.closeKeyboard(); }
    this.collapseVirtualMouse();
    this.armedKeyboardKeys = [];
    this.service?.releaseAllInput().catch(() => {});
    this.cleanView = true;
    this.getUIContext().getFocusController().requestFocus('session.surface');
    this.getUIContext().getPromptAction().showToast({ message: tr('使用系统返回或 Esc 恢复控件') });
  }

  private statusText(): string {
    if (this.disconnecting) { return tr('正在断开连接'); }
    if (this.session.error !== null && this.session.phase === SessionPhase.Ended) {
      return this.session.error;
    }
    switch (this.session.phase) {
      case SessionPhase.Connecting:
        return tr('正在连接');
      case SessionPhase.Negotiating:
        return tr('正在协商画面');
      case SessionPhase.WaitingFirstFrame:
        return tr('等待首帧');
      case SessionPhase.Playing:
        return tr('已连接');
      case SessionPhase.Reconnecting:
        return tr('正在重连');
      case SessionPhase.ViewOnly:
        return tr('只读模式');
      case SessionPhase.Ended:
        return tr('连接已结束');
      default:
        return this.session.phase;
    }
  }

  private toolbarLayout(): SessionToolbarLayout {
    const zoomed = this.zoomScale > 1 || Math.abs(this.zoomX) > 0.5 || Math.abs(this.zoomY) > 0.5;
    return sessionToolbarLayout(this.toolbarActions().length, this.pageWidth - Metrics.floatingInset * 2, zoomed);
  }

  private toggleNetworkStats(): void {
    this.getUIContext().animateTo({ curve: curves.responsiveSpringMotion(0.3, 0.86) }, () => {
      this.networkVisible = !this.networkVisible;
    });
    clearInterval(this.networkTimer);
    if (this.networkVisible) {
      this.networkStats = this.service?.stats() ?? this.networkStats;
      this.networkTimer = setInterval(() => { this.networkStats = this.service?.stats() ?? this.networkStats; }, 2000);
    }
  }

  private fittedVideoRect(): number[] {
    const sync = this.service?.videoSync();
    const vw = sync !== undefined && sync.width > 0
      ? sync.width
      : (this.session.videoWidth > 0 ? this.session.videoWidth : 1920);
    const vh = sync !== undefined && sync.height > 0
      ? sync.height
      : (this.session.videoHeight > 0 ? this.session.videoHeight : 1080);
    if (this.actualSize) {
      const width = this.getUIContext().px2vp(vw);
      const height = this.getUIContext().px2vp(vh);
      return [(this.surfaceWidth - width) / 2, (this.surfaceHeight - height) / 2, width, height];
    }
    return VideoViewport.fit(this.surfaceWidth, this.surfaceHeight, vw, vh);
  }

  private positionedVideoRect(): number[] {
    const fit = this.fittedVideoRect();
    fit[1] -= this.keyboardVideoShift(fit);
    return fit;
  }

  private keyboardVideoShift(fit: number[]): number {
    if (!this.keyboardOpen || this.keyboardMode !== 'computer' ||
      this.keyboardGlobalY === null || this.surfaceGlobalY === null) { return 0; }
    const keyboardTop = Math.max(0, this.keyboardGlobalY - this.surfaceGlobalY);
    // Base the shift on the centered view so keyboard avoidance and user panning stay independent.
    const bottom = Math.min(this.surfaceHeight, fit[1] + fit[3] * (1 + this.zoomScale) / 2);
    return Math.max(0, bottom - keyboardTop);
  }

  private videoRect(): number[] {
    return VideoViewport.rect(this.positionedVideoRect(), this.zoomScale, this.zoomX, this.zoomY);
  }

  /** Normalized position inside the visible video rectangle; null in the black bars. */
  private videoPoint(x: number, y: number): number[] | null {
    return VideoViewport.point(this.videoRect(), x, y);
  }

  private moveViewport(x: number, y: number): void {
    const offset = VideoViewport.offset(this.fittedVideoRect(), this.surfaceWidth, this.surfaceHeight, this.zoomScale, x, y);
    this.zoomX = offset[0]; this.zoomY = offset[1];
  }

  private resetViewport(): void {
    this.service?.releaseAllInput();
    this.getUIContext().animateTo({ duration: 180, curve: Curve.Friction }, () => {
      this.zoomScale = 1; this.zoomX = 0; this.zoomY = 0;
    });
  }

  private beginPinch(event: GestureEvent): void {
    this.service?.releaseAllInput();
    this.touchIgnored = true; this.pinching = true; this.panning = false; this.zoomTouch = true; this.zoomMoved = true;
    this.pinchScale = this.zoomScale;
    this.pinchAnchorX = (event.pinchCenterX - this.surfaceWidth / 2 - this.zoomX) / this.zoomScale;
    const shift = this.keyboardVideoShift(this.fittedVideoRect());
    this.pinchAnchorY = (event.pinchCenterY - this.surfaceHeight / 2 + shift - this.zoomY) / this.zoomScale;
  }

  private updatePinch(event: GestureEvent): void {
    this.zoomScale = Math.max(1, Math.min(VideoViewport.maxScale, this.pinchScale * event.scale));
    const shift = this.keyboardVideoShift(this.fittedVideoRect());
    this.moveViewport(event.pinchCenterX - this.surfaceWidth / 2 - this.pinchAnchorX * this.zoomScale,
      event.pinchCenterY - this.surfaceHeight / 2 + shift - this.pinchAnchorY * this.zoomScale);
  }

  private sendTouch(action: string, x: number, y: number, pointers: number): boolean {
    if (this.service === null || this.session.viewOnly) {
      return false;
    }
    const point = this.videoPoint(x, y);
    if (point === null) {
      return false;
    }
    const previous = this.videoPoint(this.touchLastX, this.touchLastY);
    if (action === 'touch_down') { this.touchScrolling = pointers > 1; }
    else if (pointers > 1) { this.touchScrolling = true; }
    if (this.touchMode === 'direct') {
      this.cursorX = point[0]; this.cursorY = point[1];
    } else if (action === 'touch_move' && previous !== null && !this.touchScrolling) {
      this.cursorX = Math.max(0, Math.min(1, this.cursorX + point[0] - previous[0]));
      this.cursorY = Math.max(0, Math.min(1, this.cursorY + point[1] - previous[1]));
    }
    if (this.pointerInside) { this.pointerInside = false; this.applyCursor(); }
    this.touchLastX = x;
    this.touchLastY = y;
    const anchorCursor = this.touchMode === 'direct' || !this.cursorInVideo();
    this.service.sendInput(JSON.stringify({
      action: action,
      abs_x: point[0],
      abs_y: point[1],
      cursor_x: anchorCursor ? this.cursorX : undefined,
      cursor_y: anchorCursor ? this.cursorY : undefined,
      pointers: pointers,
      at_ms: Date.now()
    }));
    return true;
  }

  private canPanViewportWithTouch(): boolean {
    return (this.zoomScale > 1 || this.actualSize) && (this.session.viewOnly || this.touchMode === 'direct');
  }

  private onSurfaceTouch(event: TouchEvent): void {
    if (this.service === null || event.source === SourceType.Mouse) {
      return;
    }
    if (this.menuOpen) {
      if (event.type === TouchType.Down) {
        this.menuOpen = false; this.touchIgnored = true; this.zoomTouch = false;
      }
      return;
    }
    const first = event.touches.length > 0 ? event.touches[0] : null;
    if (event.type === TouchType.Down) { this.collapseVirtualMouse(); }
    if (event.type === TouchType.Down && event.touches.length === 1) {
      this.zoomTouch = this.canPanViewportWithTouch();
      this.zoomMoved = false; this.panning = false;
    }
    if (this.pinching || this.zoomTouch) {
      if (event.touches.length > 1 || event.type === TouchType.Cancel) { this.zoomMoved = true; }
      if (event.type === TouchType.Up && !this.zoomMoved && !this.session.viewOnly) {
        this.sendTouch('touch_down', this.touchLastX, this.touchLastY, 1);
        this.sendTouch('touch_up', this.touchLastX, this.touchLastY, 1);
      } else if (event.type === TouchType.Down && first !== null) {
        this.touchLastX = first.x; this.touchLastY = first.y;
      }
      return;
    }
    if (this.session.viewOnly) { return; }
    if (event.type === TouchType.Down) {
      this.touchIgnored = first === null || !this.sendTouch('touch_down', first.x, first.y, event.touches.length);
    } else if (event.type === TouchType.Move) {
      if (this.touchIgnored || first === null) {
        return;
      }
      this.sendTouch('touch_move', first.x, first.y, event.touches.length);
    } else if (event.type === TouchType.Up) {
      if (this.touchIgnored) {
        this.touchIgnored = false;
        return;
      }
      // The release must always arrive so a drag cannot leave a held button.
      this.sendTouch('touch_up', this.touchLastX, this.touchLastY, 1);
    } else if (event.type === TouchType.Cancel) {
      this.touchIgnored = false;
      this.service.sendInput(JSON.stringify({ action: 'touch_cancel' }));
    }
  }

  private handleMouse(event: MouseEvent): void {
    if (this.menuOpen) {
      if (event.action === MouseAction.Press) { this.menuOpen = false; }
      event.stopPropagation(); return;
    }
    if (event.action === MouseAction.Press) { this.collapseVirtualMouse(); }
    if (this.service === null || this.session.viewOnly) { return; }
    const point = this.videoPoint(event.x, event.y);
    if (this.pointerInside !== (point !== null)) { this.pointerInside = point !== null; this.applyCursor(); }
    if (point !== null) {
      this.cursorX = point[0]; this.cursorY = point[1];
      this.service.sendInput(JSON.stringify({ action: 'mouse_move_absolute', abs_x: point[0], abs_y: point[1] }));
    }
    const button = event.button === MouseButton.Left ? 1 : event.button === MouseButton.Right ? 2 : event.button === MouseButton.Middle ? 4 : 0;
    if (button > 0 && (event.action === MouseAction.Release || (event.action === MouseAction.Press && point !== null))) {
      this.service.sendInput(JSON.stringify({ action: event.action === MouseAction.Press ? 'mouse_press' : 'mouse_release', button: button }));
      if (event.action === MouseAction.Press) {
        try { this.getUIContext().getFocusController().requestFocus('session.video'); }
        catch (error) { this.service.releaseAllInput(); this.notify(error as Error); }
      }
    }
    event.stopPropagation();
  }
  private onAxis(event: AxisEvent): void {
    if (this.service === null || this.session.viewOnly || event.getModifierKeyState?.(['Ctrl']) === true ||
      this.videoPoint(event.x, event.y) === null) { return; }
    const dx = Math.round(event.getHorizontalAxisValue());
    const dy = Math.round(event.getVerticalAxisValue());
    if (dx !== 0 || dy !== 0) { this.service.sendInput(JSON.stringify({ action: 'mouse_scroll', delta_x: dx, delta_y: -dy })); }
  }

  private onKey(event: KeyEvent): void {
    if (this.cleanView && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      if (event.type === KeyType.Up) { this.cleanView = false; }
      event.stopPropagation();
      return;
    }
    if (this.toolbarEditorOpen) {
      if (!this.toolbarSaving && event.keyCode === KeyCode.KEYCODE_ESCAPE && event.type === KeyType.Up) {
        this.toolbarEditorOpen = false;
      }
      return;
    }
    if (this.fingerprintSetupOpen) {
      if (event.keyCode === KeyCode.KEYCODE_ESCAPE && event.type === KeyType.Up) { this.closeFingerprintSetup(); }
      return;
    }
    if (this.menuOpen) {
      if (event.keyCode === KeyCode.KEYCODE_ESCAPE && event.type === KeyType.Up) {
        if (this.menuPath.length > 0) { this.menuBack(); }
        else { this.menuOpen = false; }
      }
      return;
    }
    if (this.service === null || this.session.viewOnly || (this.keyboardOpen && this.keyboardMode === 'text')) {
      return;
    }
    const scan = KeyMap.scanCode(event.keyCode);
    if (scan < 0) {
      return;
    }
    this.service.sendInput(JSON.stringify({
      action: 'key',
      scan: scan,
      down: event.type === KeyType.Down
    }));
  }

  private sendText(): void {
    if (this.textValue.length === 0 || this.service === null) {
      return;
    }
    this.service.sendText(this.textValue);
    this.textValue = '';
  }

  private closeKeyboard(): void {
    this.keyboardOpen = false;
    this.keyboardMode = 'text';
    this.keyboardGlobalY = null;
    this.armedKeyboardKeys = [];
    clearTimeout(this.keyboardTimer);
    this.getUIContext().getFocusController().requestFocus('session.surface');
    this.refreshToolbarShortcuts();
  }

  private switchKeyboardMode(mode: RemoteKeyboardMode): void {
    if (this.keyboardMode === mode) { return; }
    clearTimeout(this.keyboardTimer);
    this.armedKeyboardKeys = [];
    this.keyboardMode = mode;
    if (mode !== 'text') { this.getUIContext().getFocusController().requestFocus('session.surface'); }
  }

  private chordInputEnabled(): boolean {
    return this.active && !this.menuOpen && !this.disconnecting &&
      !this.session.viewOnly && this.session.firstFrameReceived;
  }

  private keyboardInputEnabled(): boolean { return this.keyboardOpen && this.chordInputEnabled(); }

  private keyboardPanelWidth(): number {
    const available = Math.max(0, this.pageWidth - Metrics.floatingInset * 2);
    if (this.keyboardMode === 'computer') { return available; }
    return Math.min(available, this.keyboardMode === 'text' ? 640 : 720);
  }

  private pressComputerKey(code: number): void {
    if (!this.keyboardInputEnabled()) { return; }
    if (KeyMap.isModifier(code)) {
      this.armedKeyboardKeys = this.armedKeyboardKeys.includes(code) ?
        this.armedKeyboardKeys.filter((key: number) => key !== code) : this.armedKeyboardKeys.concat(code);
      return;
    }
    const chord = this.armedKeyboardKeys.concat(code);
    this.armedKeyboardKeys = [];
    this.sendKeyboardChord(chord);
  }

  private sendKeyboardChord(codes: number[]): void {
    const service = this.service;
    if (service === null || !this.chordInputEnabled()) { return; }
    const scans: number[] = [];
    for (const code of codes) {
      const scan = KeyMap.scanCode(code);
      if (scan < 0) { return; }
      if (!scans.includes(scan)) { scans.push(scan); }
    }
    const pending: Promise<void>[] = [];
    for (const scan of scans) { pending.push(service.sendInput(JSON.stringify({ action: 'key', scan: scan, down: true }))); }
    for (let index = scans.length - 1; index >= 0; index--) {
      pending.push(service.sendInput(JSON.stringify({ action: 'key', scan: scans[index], down: false })));
    }
    Promise.all(pending).catch((error: Error) => {
      service.releaseAllInput().catch(() => {});
      if (this.active && this.service === service) { this.notify(error); }
    });
  }

  private toggleViewOnly(): void {
    this.service?.setViewOnly(!this.session.viewOnly);
  }

  private remotePlatform(): string {
    return this.service?.devicesSnapshot().devices.find((device: DeviceInfo) => device.id === this.session.targetId)?.platform ?? '';
  }

  private async loadToolbar(context: common.UIAbilityContext): Promise<void> {
    try {
      const store = await preferences.getPreferences(context, 'uu_remote_settings');
      const saved = await store.get(TOOLBAR_PREF, '');
      if (!this.active) { return; }
      this.toolbarStore = store;
      if (typeof saved === 'string' && saved.length > 0) {
        const decoded = JSON.parse(saved) as string[];
        if (Array.isArray(decoded)) {
          const ids = Array.from(new Set(decoded.filter((id: string) => typeof id === 'string' &&
            (DEFAULT_TOOLBAR.includes(id) || id === HIDE_ALL_TOOLBAR_ACTION ||
              TOOLBAR_MENU_ACTIONS.some((action: ToolbarMenuAction) => action.id === id) ||
              id.startsWith(TOOLBAR_SHORTCUT_PREFIX + 'custom-')))));
          if (ids.length > 0) { this.toolbarButtons = ids.slice(0, MAX_TOOLBAR_BUTTONS); }
        }
      }
    } catch (_) { /* Start with the default controls if preferences cannot be read. */ }
    await this.refreshToolbarShortcuts();
  }

  private async refreshToolbarShortcuts(): Promise<void> {
    const store = this.toolbarStore;
    if (store === null) { return; }
    try {
      const shortcuts = await loadSavedRemoteShortcuts(store, this.remotePlatform());
      if (this.active) { this.toolbarShortcuts = shortcuts; }
    } catch (_) { /* Keep the built-in controls available. */ }
  }

  private toolbarCatalog(): SessionToolbarAction[] {
    const actions: SessionToolbarAction[] = [
      { id: 'session.rotate', icon: 'rotate', label: tr(this.landscape ? '切换竖屏' : '切换横屏'),
        enabled: this.rotateEnabled && !this.orientationPending },
      { id: 'session.keyboard', icon: 'keyboard', label: tr('键盘'), enabled: !this.session.viewOnly },
      { id: 'session.pip', icon: 'pip', label: tr('画中画'),
        enabled: this.pipSupported && this.session.firstFrameReceived && !this.disconnecting }
    ];
    const platform = this.remotePlatform().toLowerCase();
    if (platform === 'windows' || platform === '云电脑' || platform === 'cloud pc') {
      actions.push({ id: 'session.showDesktop', icon: 'device_tv', label: tr('显示桌面'), enabled: this.chordInputEnabled() });
    }
    for (const item of this.toolbarShortcuts) {
      actions.push({ id: TOOLBAR_SHORTCUT_PREFIX + item.id, icon: 'keyboard', label: item.label, text: item.label,
        enabled: this.chordInputEnabled() });
    }
    actions.push({ id: HIDE_ALL_TOOLBAR_ACTION, icon: 'fullscreen', label: tr('隐藏全部控件'), enabled: !this.disconnecting });
    for (const entry of TOOLBAR_MENU_ACTIONS) {
      actions.push({ id: entry.id, icon: entry.icon, label: tr(entry.label), enabled: !this.disconnecting });
    }
    return actions;
  }

  private toolbarLimit(): number {
    return Math.max(1, Math.min(MAX_TOOLBAR_BUTTONS,
      Math.floor((this.pageWidth - Metrics.floatingInset * 2 + 8) / 56)));
  }

  private toolbarActions(): SessionToolbarAction[] {
    const catalog = this.toolbarCatalog();
    const actions: SessionToolbarAction[] = [];
    for (const id of this.toolbarButtons) {
      const action = catalog.find((item: SessionToolbarAction) => item.id === id);
      if (action !== undefined) { actions.push(action); }
    }
    return (actions.length > 0 ? actions : catalog.filter((action: SessionToolbarAction) => DEFAULT_TOOLBAR.includes(action.id)))
      .slice(0, this.toolbarLimit());
  }

  private activateToolbarAction(id: string): void {
    if (this.menuOpen || this.toolbarCatalog().find((item: SessionToolbarAction) => item.id === id)?.enabled !== true) { return; }
    switch (id) {
      case 'session.rotate': this.toggleOrientation(); break;
      case 'session.keyboard': this.keyboardOpen = true; break;
      case 'session.pip': this.startSessionPiP(); break;
      case 'session.showDesktop': this.sendKeyboardChord(WINDOWS_SHOW_DESKTOP); break;
      case HIDE_ALL_TOOLBAR_ACTION: this.enterCleanView(); break;
      default: {
        const entry = TOOLBAR_MENU_ACTIONS.find((action: ToolbarMenuAction) => action.id === id);
        if (entry !== undefined) {
          const item = this.moreItems().flatMap((group: SessionMenuGroup) => group.items)
            .find((action: SessionMenuItem) => action.id === entry.menuId);
          if (item === undefined || item.enabled === false) { return; }
          if (item.children === undefined) { item.action(); }
          else {
            this.openMenu(true);
            this.selectMenuItem(item, 0, id);
          }
          return;
        }
        const shortcut = this.toolbarShortcuts.find((item: Shortcut) => TOOLBAR_SHORTCUT_PREFIX + item.id === id);
        if (shortcut !== undefined) { this.sendKeyboardChord(shortcut.codes); }
      }
    }
  }

  private async openToolbarEditor(): Promise<void> {
    await this.refreshToolbarShortcuts();
    if (!this.active) { return; }
    const available = this.toolbarCatalog().map((action: SessionToolbarAction) => action.id);
    this.toolbarDraft = this.toolbarButtons.filter((id: string) => available.includes(id));
    if (this.toolbarDraft.length === 0) { this.toolbarDraft = this.toolbarActions().map((action: SessionToolbarAction) => action.id); }
    this.toolbarEditorOpen = true;
  }

  private toggleToolbarDraft(id: string): void {
    if (this.toolbarSaving) { return; }
    if (this.toolbarDraft.includes(id)) {
      if (this.toolbarDraft.length > 1) { this.toolbarDraft = this.toolbarDraft.filter((entry: string) => entry !== id); }
    } else if (this.toolbarDraft.length < this.toolbarLimit()) {
      this.toolbarDraft = this.toolbarDraft.concat(id);
    }
  }

  private moveToolbarDraft(id: string, direction: number): void {
    if (this.toolbarSaving) { return; }
    const index = this.toolbarDraft.indexOf(id);
    const next = index + direction;
    if (index < 0 || next < 0 || next >= this.toolbarDraft.length) { return; }
    const ids = this.toolbarDraft.slice();
    ids[index] = ids[next];
    ids[next] = id;
    this.toolbarDraft = ids;
  }

  private async saveToolbarDraft(): Promise<void> {
    const store = this.toolbarStore;
    if (this.toolbarSaving || this.toolbarDraft.length === 0) { return; }
    if (store === null) { this.notify(new Error(tr('无法保存工具条设置'))); return; }
    this.toolbarSaving = true;
    const ids = this.toolbarDraft.slice();
    try {
      await store.put(TOOLBAR_PREF, JSON.stringify(ids));
      await store.flush();
      this.toolbarButtons = ids;
      this.toolbarEditorOpen = false;
    } catch (_) {
      await store.put(TOOLBAR_PREF, JSON.stringify(this.toolbarButtons)).catch(() => {});
      if (this.active) { this.notify(new Error(tr('无法保存工具条设置'))); }
    }
    finally { this.toolbarSaving = false; }
  }

  private async toggleOrientation(): Promise<void> {
    const win = this.sessionWindow;
    if (win === null || !this.rotateEnabled || this.orientationPending) { return; }
    clearTimeout(this.orientationTimer); this.orientationTimer = -1;
    this.orientationPending = true;
    try {
      if (this.keyboardOpen) { this.closeKeyboard(); }
      const rect = win.getWindowProperties().windowRect;
      await win.setPreferredOrientation(rect.width > rect.height
        ? window.Orientation.USER_ROTATION_PORTRAIT : window.Orientation.USER_ROTATION_LANDSCAPE);
      this.orientationChanged = true;
      if (!this.active && this.originalOrientation !== null) { await win.setPreferredOrientation(this.originalOrientation); }
      if (this.active && this.orientationPending) {
        const wasLandscape = rect.width > rect.height;
        this.orientationTimer = setTimeout(() => {
          if (!this.active) { return; }
          this.orientationTimer = -1;
          this.orientationPending = false;
          const current = win.getWindowProperties().windowRect;
          if ((current.width > current.height) === wasLandscape) {
            this.getUIContext().getPromptAction().showToast({ message: tr('当前窗口不支持切换方向') });
          }
        }, 900);
      }
    } catch (error) { this.orientationPending = false; this.notify(error as Error); }
    finally { if (!this.active || this.orientationTimer < 0) { this.orientationPending = false; } }
  }

  private async toggleInputMode(): Promise<void> {
    if (this.service === null) { return; }
    const mode: TouchMode = this.touchMode === 'trackpad' ? 'direct' : 'trackpad';
    try {
      await this.service.setTouchMode(mode);
      if (this.active) {
        this.getUIContext().getPromptAction().showToast({ message: mode === 'direct' ? tr('直接触控') : tr('触控板') });
      }
    } catch (error) { if (this.active) { this.notify(error as Error); } }
  }

  @Builder
  moreMenu() {
    WithTheme({ colorMode: ThemeColorMode.DARK }) {
      Stack({ alignContent: Alignment.TopStart }) {
        ForEach([0].concat(this.menuPath.map((id: string, index: number) => index + 1))
          .slice(this.toolbarMenuOpen ? 1 : 0), (depth: number) => {
          this.actionMenu(this.menuGroups(depth), depth)
        }, (depth: number) => depth.toString())
      }.width(this.toolbarMenuOpen ? this.pageWidth : this.menuCanvasWidth())
        .height(this.menuAvailableHeight() + 32).id('session.menu.stack')
        .onClick(() => { this.menuOpen = false; })
    }
  }

  private menuGroups(depth: number): SessionMenuGroup[] {
    let groups = this.moreItems();
    for (let level = 0; level < depth; level++) {
      groups = groups.flatMap((group: SessionMenuGroup) => group.items)
        .find((item: SessionMenuItem) => item.id === this.menuPath[level])?.children ?? [];
    }
    return groups;
  }

  private menuParent(depth: number): SessionMenuItem | undefined {
    return this.menuGroups(depth - 1).flatMap((group: SessionMenuGroup) => group.items)
      .find((item: SessionMenuItem) => item.id === this.menuPath[depth - 1]);
  }

  private menuCanvasWidth(): number { return Math.min(320, this.pageWidth - 32); }

  private openMenu(fromToolbar: boolean = false): void {
    const ui = this.getUIContext();
    this.menuViewportHeight = ui.px2vp(ui.getComponentUtils().getRectangleById('session.page').size.height);
    this.service?.releaseAllInput();
    this.armedKeyboardKeys = [];
    this.menuPath = []; this.menuAnchors = []; this.menuUpwards = [];
    this.toolbarMenuOpen = fromToolbar;
    this.pressedMenuButton = '';
    this.clearMenuTouch();
    this.menuOpen = true;
  }

  private clearMenuTouch(): void {
    this.menuTouchId = null;
    this.pressedMenuItem = '';
  }

  private trackMenuTouch(event: TouchEvent, groups: SessionMenuGroup[], depth: number): void {
    if (!this.menuOpen || depth !== this.menuPath.length) { return; }
    if (event.type === TouchType.Cancel || (event.type === TouchType.Up && event.touches.length === 0)) {
      this.clearMenuTouch();
      return;
    }
    const touch = event.type === TouchType.Down && this.menuTouchId === null ? event.changedTouches[0] :
      event.changedTouches.find((point: TouchObject) => point.id === this.menuTouchId);
    if (touch === undefined) { return; }
    if (event.type === TouchType.Up) {
      this.clearMenuTouch();
    } else {
      this.menuTouchId = touch.id;
      this.pressedMenuItem = this.menuItemAt(touch, groups, depth);
    }
  }

  private menuItemAt(touch: TouchObject, groups: SessionMenuGroup[], depth: number): string {
    const ui = this.getUIContext();
    const utils = ui.getComponentUtils();
    const x = ui.vp2px(touch.windowX);
    const y = ui.vp2px(touch.windowY);
    const viewport = utils.getRectangleById('session.menu.items.' + depth);
    if (x < viewport.windowOffset.x || x >= viewport.windowOffset.x + viewport.size.width ||
      y < viewport.windowOffset.y || y >= viewport.windowOffset.y + viewport.size.height) { return ''; }
    for (const group of groups) {
      for (const item of group.items) {
        if (item.enabled === false || item.volume === true) { continue; }
        const row = utils.getRectangleById(item.id);
        if (y >= row.windowOffset.y && y < row.windowOffset.y + row.size.height &&
          x >= row.windowOffset.x && x < row.windowOffset.x + row.size.width) { return item.id; }
      }
    }
    return '';
  }

  private menuAvailableHeight(): number { return Math.max(0, this.menuViewportHeight - 32); }

  private menuUnit(value: number): number {
    const ui = this.getUIContext();
    return ui.px2vp(Math.round(ui.vp2px(value)));
  }

  private menuBodyHeight(depth: number): number {
    const groups = this.menuGroups(depth);
    const desired = this.menuContentHeight(groups, depth === 0 ? Number.MAX_SAFE_INTEGER : 4);
    const available = depth === 0 ? this.menuAvailableHeight() - this.menuTop(0) :
      this.menuUpwards[depth - 1] ? this.menuAnchors[depth - 1] :
        this.menuAvailableHeight() - this.menuAnchors[depth - 1] - this.menuUnit(48);
    return Math.min(desired, Math.max(0, available));
  }

  private menuContentHeight(groups: SessionMenuGroup[], limit: number): number {
    let height = this.menuUnit(8) * 2;
    let remaining = limit;
    for (let index = 0; index < groups.length && remaining > 0; index++) {
      const count = Math.min(groups[index].items.length, remaining);
      if (index > 0) { height += this.menuUnit(8); }
      height += count * this.menuUnit(48) + Math.max(0, count - 1) * this.menuUnit(8);
      remaining -= count;
    }
    return height;
  }

  private menuHeight(depth: number): number { return this.menuBodyHeight(depth) + (depth > 0 ? this.menuUnit(48) : 0); }

  private menuWidth(depth: number): number { return this.menuCanvasWidth() - 64 - (this.menuPath.length - depth) * 12; }

  private menuLeft(depth: number): number {
    if (this.toolbarMenuOpen) {
      const inset = Metrics.floatingInset;
      const width = this.menuWidth(depth);
      return Math.max(inset, Math.min(this.toolbarMenuCenterX - width / 2, this.pageWidth - inset - width));
    }
    return 32 + (this.headerMoreOnLeft() ? -Metrics.floatingInset : Metrics.floatingInset) - depth * 6;
  }

  private menuTop(depth: number): number {
    if (depth === 0) { return Metrics.floatingHeaderHeight - Metrics.floatingInset; }
    return this.menuAnchors[depth - 1] - (this.menuUpwards[depth - 1] ? this.menuBodyHeight(depth) : 0);
  }

  private menuPivot(depth: number): number {
    return depth < this.menuPath.length ? this.menuAnchors[depth] - this.menuTop(depth) + 24 : 0;
  }

  private menuBack(depth: number = this.menuPath.length - 1): void {
    this.clearMenuTouch();
    if (this.toolbarMenuOpen && depth <= 0) { this.menuOpen = false; return; }
    this.getUIContext().animateTo({ curve: curves.responsiveSpringMotion(0.3, 0.86) }, () => {
      this.menuPath = this.menuPath.slice(0, depth);
      this.menuAnchors = this.menuAnchors.slice(0, depth);
      this.menuUpwards = this.menuUpwards.slice(0, depth);
    });
  }

  private selectMenuItem(item: SessionMenuItem, depth: number, toolbarAnchor?: string): void {
    if (depth < this.menuPath.length) { this.menuBack(depth); return; }
    if (item.enabled === false) { return; }
    this.clearMenuTouch();
    if (item.children !== undefined) {
      const ui = this.getUIContext();
      const utils = ui.getComponentUtils();
      const target = utils.getRectangleById(toolbarAnchor ?? item.id);
      const stack = utils.getRectangleById(toolbarAnchor === undefined ? 'session.menu.stack' : 'session.page');
      const top = ui.px2vp(target.windowOffset.y - stack.windowOffset.y) - 16;
      const anchor = toolbarAnchor === undefined ? top : top - this.menuUnit(48) - 8;
      const desired = this.menuContentHeight(item.children, 4);
      const below = this.menuAvailableHeight() - anchor - this.menuUnit(48);
      const upwards = toolbarAnchor !== undefined || (below < desired && anchor > below);
      this.getUIContext().animateTo({ curve: curves.responsiveSpringMotion(0.3, 0.86) }, () => {
        if (toolbarAnchor !== undefined) {
          this.toolbarMenuCenterX = ui.px2vp(target.windowOffset.x - stack.windowOffset.x + target.size.width / 2);
        }
        this.menuAnchors = this.menuAnchors.slice(0, depth).concat(anchor);
        this.menuUpwards = this.menuUpwards.slice(0, depth).concat(upwards);
        this.menuPath = this.menuPath.slice(0, depth).concat(item.id);
      });
    } else { this.menuOpen = false; item.action(); }
  }

  @Builder
  menuHeader(depth: number) {
    Button({ type: ButtonType.Normal, stateEffect: !buttonPressShadowSupported }) {
      Row({ space: 8 }) {
        Text(this.menuParent(depth)?.label ?? '').fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary')).layoutWeight(1)
          .id('session.more.title.' + depth)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Image(iconResource('chevron', true, false)).width(16).height(16)
          .fillColor($r('sys.color.icon_primary')).objectFit(ImageFit.Contain).draggable(false)
          .rotate({ angle: this.menuUpwards[depth - 1] ? -90 : 90 })
          .id('session.menu.arrow.' + depth + (this.menuUpwards[depth - 1] ? '.up' : '.down'))
          .accessibilityLevel('no')
      }.width('100%')
    }.width('calc(100% - 16vp)').height(this.menuUnit(48)).margin({ left: 8, right: 8 })
      .padding({ left: 22, right: 16 }).backgroundColor(Color.Transparent)
      .borderRadius($r('sys.float.corner_radius_level8')).id('session.more.back.' + depth)
      .accessibilityText((this.menuParent(depth)?.label ?? '') + ' · ' + tr('返回'))
      .attributeModifier(floatingFeedback)
      .visualEffect(buttonPressShadow(this.pressedMenuButton === 'back.' + depth))
      .onTouch((event: TouchEvent) => {
        this.pressedMenuButton = pressedButtonAfterTouch(this.pressedMenuButton, 'back.' + depth, event);
      })
      .onClick(() => { this.menuBack(); })
  }

  @Builder
  menuItems(groups: SessionMenuGroup[], depth: number) {
    Stack({ alignContent: Alignment.End }) {
    Scroll(this.menuScrollers[depth]) {
      Column() {
        ForEach(groups, (group: SessionMenuGroup, index: number) => {
          if (index > 0) {
            Stack() {
              Divider().height(this.menuUnit(1)).color($r('app.color.session_glass_stroke'))
            }.width('100%').height(this.menuUnit(8))
          }
          Column({ space: this.menuUnit(8) }) {
          ForEach(group.items, (item: SessionMenuItem) => {
            if (item.volume === true) {
              Slider({ value: this.volume, min: 0, max: 100, step: 1 })
                .width('100%').height(this.menuUnit(48)).padding({ left: 16, right: 16 })
                .showTips(true).id(item.id).accessibilityText(tr('音量'))
                .onChange((value: number) => {
                  this.volume = Math.round(value);
                  this.service?.setAudioVolume(this.volume).catch((error: Error) => { this.notify(error); });
                })
            } else {
            Button({ type: ButtonType.Normal, stateEffect: false }) {
              Row({ space: 8 }) {
                Text(item.label).fontSize(16).layoutWeight(1).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Start)
                  .fontColor(item.destructive ? $r('app.color.session_error') : $r('sys.color.font_primary'))
                  .id(item.id + '.label')
                if (item.value !== undefined) {
                  Text(this.menuValue(item)).fontSize(14)
                    .fontColor(sessionMaterialSupported() &&
                      this.menuMaterialLevel === hdsMaterial.MaterialLevel.EXQUISITE ?
                      $r('sys.color.font_primary') : $r('sys.color.font_secondary'))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 128 })
                    .id(item.id + '.value')
                }
                if (item.children !== undefined || item.selected === true) {
                  Image(iconResource(item.children !== undefined ? 'chevron' : 'check', true, false)).width(16).height(16)
                    .fillColor($r('sys.color.icon_primary')).objectFit(ImageFit.Contain).draggable(false)
                    .id(item.id + '.arrow').accessibilityLevel('no')
                }
              }.width('100%')
            }.width('100%').height(this.menuUnit(48)).padding({ left: 16, right: 16 }).borderRadius(12)
              .backgroundColor(item.destructive ? $r('app.color.session_error_background') :
                item.selected === true ? $r('app.color.session_selection') : Color.Transparent)
              .opacity(this.menuPath[depth] === item.id ? 0 : 1)
              .id(item.id).enabled(item.enabled !== false).accessibilitySelected(item.selected === true)
              .accessibilityText(item.label + (item.value !== undefined ? ' · ' + this.menuValue(item) : ''))
              .attributeModifier(floatingFeedback)
              .visualEffect(buttonPressShadow(item.enabled !== false && this.pressedMenuItem === item.id))
              .outline({
                width: !buttonPressShadowSupported && item.enabled !== false && this.pressedMenuItem === item.id ? 1 : 0,
                color: $r('app.color.session_glass_stroke'),
                radius: 12
              })
              .onClick(() => { this.selectMenuItem(item, depth); })
            }
          }, (item: SessionMenuItem) => item.id)
          }.width('100%')
        }, (group: SessionMenuGroup, index: number) => index + group.title)
      }.width('100%').padding({ left: this.menuUnit(8), right: this.menuUnit(8) })
    }.width('100%').height(Math.max(0, this.menuBodyHeight(depth) - this.menuUnit(8) * 2))
      .margin({ top: this.menuUnit(8), bottom: this.menuUnit(8) }).backgroundColor(Color.Transparent)
      .scrollBar(BarState.Off).clip(true)
      .id('session.menu.items.' + depth)
      .onTouch((event: TouchEvent) => { this.trackMenuTouch(event, groups, depth); })
      edgeScrollBar(this.menuScrollers[depth], 'session.menu.items.' + depth)
    }.width('100%').height(this.menuBodyHeight(depth))
  }

  @Builder
  actionMenu(groups: SessionMenuGroup[], depth: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      if (sessionMaterialSupported()) {
        SessionMaterialBackplate({ radius: $r('sys.float.corner_radius_level8'), nodeId: 'session.menu.material.' + depth })
      }
      Column() {
        if (depth > 0 && !this.menuUpwards[depth - 1]) { this.menuHeader(depth) }
        this.menuItems(groups, depth)
        if (depth > 0 && this.menuUpwards[depth - 1]) { this.menuHeader(depth) }
      }.width('100%').height('100%')
        .id('session.menu.content.' + depth)
    }.width(this.menuWidth(depth)).height(this.menuHeight(depth)).borderRadius($r('sys.float.corner_radius_level8'))
      .backgroundColor(Color.Transparent)
      .attributeModifier(sessionMaterialSupported() ? sessionMenuFrame : sessionMenuMaterial)
      .scale({ x: 1, y: 1 - (this.menuPath.length - depth) * 0.04,
        centerX: 0, centerY: this.menuPivot(depth) })
      .rotate({ x: 1, angle: depth < this.menuPath.length ? -3 : 0,
        centerX: 0, centerY: this.menuPivot(depth), perspective: 800 })
      .id(depth === 0 ? 'session.action.menu' : 'session.action.menu.' + this.menuPath[depth - 1])
      .position({ x: this.menuLeft(depth), y: this.menuTop(depth) + 16 })
      .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
      .onClick(() => {
        if (depth < this.menuPath.length) { this.menuBack(depth); }
      })
      .accessibilityLevel(depth < this.menuPath.length ? 'no-hide-descendants' : 'auto')
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.94, y: 0.94,
        centerX: this.toolbarMenuOpen ? '50%' : 0,
        centerY: depth > 0 && this.menuUpwards[depth - 1] ? '100%' : 0 }))
        .combine(TransitionEffect.translate({ x: depth > 0 && !this.toolbarMenuOpen ? 6 : 0,
          y: depth > 0 ? (this.menuUpwards[depth - 1] ? 8 : -8) : 0 }))
        .animation({ curve: curves.responsiveSpringMotion(0.3, 0.86) }))
  }

  private notify(error: Error): void { this.getUIContext().getPromptAction().showToast({ message: error.message }); }

  private async disconnectSession(): Promise<void> {
    if (this.disconnecting || this.service === null) { return; }
    this.disconnecting = true;
    try {
      await this.service.disconnect();
      if (this.active) { Router.backTo('devices'); }
    } catch (error) {
      if (this.active) { this.notify(error as Error); }
    } finally { this.disconnecting = false; }
  }
  private clipboard(receive: boolean): void {
    this.service?.syncClipboard(receive).then(() => {
      this.getUIContext().getPromptAction().showToast({ message: receive ? tr('已复制到本机剪贴板') : tr('已发送到远端') });
    }).catch((error: Error) => { this.notify(error); });
  }
  private remote(action: string, title: string, enabled: boolean = false): void {
    this.getUIContext().showAlertDialog({ title: title, message: tr('确认向远端设备发送此操作？'),
      primaryButton: { value: tr('取消'), action: () => {} }, secondaryButton: { value: tr('发送'), action: () => {
        this.service?.remoteAction(action, enabled).then(() => {
          this.getUIContext().getPromptAction().showToast({ message: tr('操作已发送') });
        }).catch((error: Error) => { this.notify(error); });
      } } });
  }

  private moreItems(): SessionMenuGroup[] {
    const enabled = !this.session.viewOnly;
    return [
      { title: '', items: [
        { id: 'session.more.input', label: tr('输入'), action: () => {}, children: [{ title: '', items: [
          { id: 'session.inputMode', label: this.touchMode === 'direct' ? tr('直接触控') : tr('触控板'), enabled: enabled, action: () => { this.toggleInputMode(); } },
          { id: 'session.virtualMouse', label: this.virtualMouseVisible ? tr('隐藏虚拟鼠标') : tr('虚拟鼠标'),
            action: () => { this.virtualMouseVisible = !this.virtualMouseVisible; } },
          { id: 'session.more.viewOnly', label: this.session.viewOnly ? tr('退出只读') : tr('只读模式'), action: () => { this.toggleViewOnly(); } },
          { id: 'session.more.hide', label: tr('隐藏悬浮控件'), action: () => { this.enterCleanView(); } }
        ] }] },
        { id: 'session.quality', label: tr('远程画面'), action: () => {}, children: this.videoItems() },
        { id: 'session.more.toolbarEdit', label: tr('自定义工具条'), action: () => { this.openToolbarEditor(); } },
        { id: 'session.more.tools', label: tr('远程工具'), action: () => {}, children: [{ title: '', items: [
          { id: 'session.more.files', label: tr('文件管理'), action: () => { Router.push('files'); } },
          { id: 'session.more.terminal', label: tr('终端'), action: () => { Router.push('terminal'); } },
          { id: 'session.more.portmap', label: tr('端口映射'), action: () => { Router.push('portmap'); } }
        ] }] },
        { id: 'session.more.clipboard', label: tr('剪贴板'), action: () => {}, children: [{ title: '', items: [
          { id: 'session.more.clipboard.send', label: tr('发送本机剪贴板'), enabled: enabled, action: () => { this.clipboard(false); } },
          { id: 'session.more.clipboard.receive', label: tr('复制远端剪贴板'), action: () => { this.clipboard(true); } }
        ] }] },
        { id: 'session.more.audio', label: tr('声音'), value: this.audioOn ? this.volume + '%' : tr('静音'), action: () => {},
          children: [{ title: '', items: [
            { id: 'session.audio.mute', label: this.audioOn ? tr('关闭声音') : tr('打开声音'), action: () => {
              this.audioOn = !this.audioOn; this.service?.setAudioMuted(!this.audioOn);
            } },
            { id: 'session.audio.volume', label: tr('音量'), volume: true, action: () => {} }
          ] }] },
        { id: 'session.more.stats', label: tr('网络状态'), selected: this.networkVisible,
          action: () => { this.toggleNetworkStats(); } },
        { id: 'session.more.remote', label: tr('远端操作'), action: () => {}, children: [{ title: '', items: [
          { id: 'session.more.mute.select', label: tr('静音运行'), enabled: enabled, action: () => {}, children: [{ title: '', items: [
            { id: 'session.more.mute', label: tr('启用'), enabled: enabled, action: () => { this.remote('hostMute', tr('静音运行'), true); } },
            { id: 'session.more.unmute', label: tr('停用'), enabled: enabled, action: () => { this.remote('hostMute', tr('恢复远端声音'), false); } }
          ] }] },
          { id: 'session.more.lock.select', label: tr('连接结束后锁屏'), enabled: enabled, action: () => {}, children: [{ title: '', items: [
            { id: 'session.more.lock', label: tr('启用'), enabled: enabled, action: () => { this.remote('autoLock', tr('连接结束后锁屏'), true); } },
            { id: 'session.more.unlock', label: tr('停用'), enabled: enabled, action: () => { this.remote('autoLock', tr('取消结束后锁屏'), false); } }
          ] }] },
          ...(this.fingerprintUnlockReady ? [{ id: 'session.more.fingerprint', label: tr('设置指纹解锁'),
            enabled: enabled, action: () => { this.openFingerprintSetup(); } }] as SessionMenuItem[] : []),
          { id: 'session.more.reboot', label: tr('重启'), destructive: true, enabled: enabled, action: () => { this.remote('reboot', tr('重启')); } },
          { id: 'session.more.shutdown', label: tr('关机'), destructive: true, enabled: enabled, action: () => { this.remote('shutdown', tr('关机')); } }
        ] }] }
      ] },
      { title: '', items: [{ id: 'session.more.end', label: tr('结束连接'), destructive: true, action: () => { this.endDialog = true; } }] }
    ];
  }
  private qualityLabel(quality: string): string {
    switch (quality) {
      case 'original':
        return tr('原画 20M');
      case 'ultra':
        return tr('超清 8M');
      case 'hd':
        return tr('高清 2M');
      default:
        return tr('自动');
    }
  }

  private qualityOptions(): string[] {
    return ['auto', 'original', 'ultra', 'hd'];
  }

  private frameRateOptions(): number[] {
    return [144, 90, 60, 30].filter((fps: number) => fps <= this.maxFps);
  }

  private resolutionOptions(): string[] {
    const reported = this.service?.videoSync().resolutionModes;
    const modes: VideoResolution[] = reported !== undefined && reported.length > 0 ? reported : [
      { width: 3840, height: 2160 }, { width: 2560, height: 1440 },
      { width: 1920, height: 1080 }, { width: 1280, height: 720 }
    ];
    const supported = modes.filter((mode: VideoResolution) => mode.width <= this.maxVideoWidth &&
      mode.height <= this.maxVideoHeight && mode.width % 2 === 0 && mode.height % 2 === 0)
      .sort((a: VideoResolution, b: VideoResolution) =>
      b.width * b.height - a.width * a.height);
    return ['auto', 'window'].concat(supported.map((mode: VideoResolution): string => {
      const size = mode.width + 'x' + mode.height;
      switch (size) {
        case '3840x2160': return '2160p60';
        case '2560x1440': return '1440p60';
        case '1920x1080': return '1080p60';
        case '1280x720': return '720p30';
        default: return size;
      }
    }));
  }

  private resolutionLabel(profile: string): string {
    switch (profile) {
      case 'window':
        return tr('跟随当前窗口');
      case '2160p60':
        return '4K · 3840×2160';
      case '1440p60':
        return '2K · 2560×1440';
      case '1080p60':
        return '1080p · 1920×1080';
      case '720p30':
        return '720p · 1280×720';
      default:
        return /^\d+x\d+$/.test(profile) ? profile.replace('x', '×') : tr('跟随被控端');
    }
  }

  private refreshActualResolution(): void {
    const sync = this.service?.videoSync();
    this.actualResolution = sync !== undefined && sync.width > 0 && sync.height > 0 ? sync.width + '×' + sync.height : '';
  }

  private refreshFingerprintUnlock(): void {
    this.fingerprintUnlockReady = false;
    this.fingerprintPasswordSaved = false;
    const service = this.service;
    const generation = this.session.generation;
    if (service === null || this.session.remoteUnlock?.supported !== true || !service.fingerprintUnlockAvailable()) { return; }
    service.hasFingerprintUnlockPassword().then((saved: boolean) => {
      if (this.active && this.session.generation === generation && this.session.remoteUnlock?.supported === true &&
        !this.session.viewOnly) {
        this.fingerprintPasswordSaved = saved;
        this.fingerprintUnlockReady = true;
      }
    }).catch(() => {});
  }

  private openFingerprintSetup(): void {
    if (!this.fingerprintUnlockReady || this.fingerprintBusy) { return; }
    this.service?.releaseAllInput();
    this.fingerprintPassword = '';
    this.fingerprintSetupOpen = true;
  }

  private closeFingerprintSetup(): void {
    this.fingerprintPassword = '';
    this.fingerprintSetupOpen = false;
  }

  private async updateFingerprintPassword(remove: boolean): Promise<void> {
    const service = this.service;
    if (service === null || this.fingerprintBusy || (!remove && this.fingerprintPassword.length === 0)) { return; }
    const generation = this.session.generation;
    const password = this.fingerprintPassword;
    this.fingerprintPassword = '';
    this.fingerprintBusy = true;
    try {
      if (remove) { await service.removeFingerprintUnlockPassword(); }
      else { await service.saveFingerprintUnlockPassword(password); }
      if (this.active && this.session.generation === generation) {
        this.fingerprintPasswordSaved = !remove;
        this.closeFingerprintSetup();
      }
    } catch (error) {
      if (this.active) { this.notify(new Error(tr(remove ? '无法清除登录密码。' : '无法保存登录密码。'))); }
    } finally { this.fingerprintBusy = false; }
  }

  private async fingerprintUnlockTapped(): Promise<void> {
    const service = this.service;
    if (service === null || this.fingerprintBusy || this.session.remoteUnlock?.locked !== true) { return; }
    if (!this.fingerprintPasswordSaved) { this.openFingerprintSetup(); return; }
    this.fingerprintBusy = true;
    try { await service.fingerprintUnlock(); }
    catch (error) { if (this.active) { this.notify(error as Error); } }
    finally { this.fingerprintBusy = false; }
  }

  @Builder
  fingerprintUnlockButton() {
    Button({ type: ButtonType.Capsule, stateEffect: !buttonPressShadowSupported }) {
      Stack() {
        if (sessionMaterialSupported()) {
          SessionMaterialBackplate({ radius: 24, nodeId: 'session.unlock.fingerprint.material' })
        }
        if (buttonPressShadowSupported && this.pressedMenuButton === 'fingerprint') {
          buttonPressEdgeLayer(24, 'session.unlock.fingerprint.press-glow')
        }
        Row({ space: 8 }) {
          Image($r('app.media.remote_unlock_fingerprint')).width(22).height(22)
            .fillColor($r('sys.color.icon_primary')).draggable(false).accessibilityLevel('no')
          Text(tr(this.fingerprintBusy ? '正在解锁…' : this.fingerprintPasswordSaved ? '指纹解锁' : '设置指纹解锁'))
            .fontSize(16).fontColor($r('sys.color.font_primary')).maxLines(1)
        }.justifyContent(FlexAlign.Center)
      }.width('100%').height('100%')
    }.width(Math.min(this.pageWidth - 32, 208)).height(48).padding(0).enabled(!this.fingerprintBusy)
      .attributeModifier(sessionSurfaceControl()).id('session.unlock.fingerprint')
      .visualEffect(buttonPressShadow(this.pressedMenuButton === 'fingerprint', false))
      .onTouch((event: TouchEvent) => {
        this.pressedMenuButton = pressedButtonAfterTouch(this.pressedMenuButton, 'fingerprint', event);
      })
      .onClick(() => { this.fingerprintUnlockTapped(); })
  }

  @Builder
  fingerprintSetup() {
    Stack() {
      Column() {}.width('100%').height('100%').backgroundColor('#88000000')
        .onClick(() => { if (!this.fingerprintBusy) { this.closeFingerprintSetup(); } })
      Stack() {
        if (sessionMaterialSupported()) {
          SessionMaterialBackplate({ radius: $r('sys.float.corner_radius_level8'), nodeId: 'session.unlock.setup.material' })
        }
        Column({ space: 12 }) {
          Text(tr('设置指纹解锁')).fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
          Text(tr('登录密码由本机安全存储保护。')).fontSize(14).fontColor($r('sys.color.font_secondary'))
          TextInput({ text: this.fingerprintPassword, placeholder: tr('被控端登录密码') })
            .type(InputType.Password).showPasswordIcon(false).copyOption(CopyOptions.None).maxLength(256)
            .width('100%').height(48).id('session.unlock.password')
            .onChange((value: string) => { this.fingerprintPassword = value; })
          Row({ space: 8 }) {
            Button(tr('取消'), { type: ButtonType.Capsule }).layoutWeight(1).enabled(!this.fingerprintBusy)
              .id('session.unlock.cancel').onClick(() => { this.closeFingerprintSetup(); })
            Button(tr('保存密码'), { type: ButtonType.Capsule }).layoutWeight(1)
              .enabled(!this.fingerprintBusy && this.fingerprintPassword.length > 0)
              .id('session.unlock.save').onClick(() => { this.updateFingerprintPassword(false); })
          }.width('100%')
          if (this.fingerprintPasswordSaved) {
            Button(tr('清除已保存的密码'), { type: ButtonType.Capsule, role: ButtonRole.ERROR })
              .width('100%').enabled(!this.fingerprintBusy).id('session.unlock.remove')
              .onClick(() => { this.updateFingerprintPassword(true); })
          }
        }.width('100%').padding(16)
      }.width(Math.min(this.pageWidth - 32, 360)).borderRadius($r('sys.float.corner_radius_level8'))
        .attributeModifier(sessionMaterialSupported() ? sessionMenuFrame : sessionMenuMaterial)
    }.width('100%').height('100%').id('session.unlock.setup').hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
  }

  private menuValue(item: SessionMenuItem): string {
    return item.id === 'session.resolution.select' && this.actualResolution.length > 0 ? this.actualResolution : item.value ?? '';
  }

  private videoItems(): SessionMenuGroup[] {
    const settings = this.service?.settings();
    return [{ title: '', items: [
      { id: 'session.display.select', label: tr('显示方式'), value: this.actualSize ? tr('实际大小 1:1') : tr('自适应'),
        action: () => {}, children: [{ title: '', items: [false, true].map((actual: boolean): SessionMenuItem => ({
          id: 'session.display.' + (actual ? 'actual' : 'fit'), label: actual ? tr('实际大小 1:1') : tr('自适应'),
          selected: actual === this.actualSize, action: () => { this.actualSize = actual; this.resetViewport(); }
        })) }] },
      { id: 'session.quality.select', label: tr('画质'), value: this.qualityLabel(settings?.defaultVideoQuality ?? 'auto'),
        action: () => {}, children: [{ title: '', items: this.qualityOptions().map((quality: string): SessionMenuItem => ({
          id: 'session.quality.' + quality, label: this.qualityLabel(quality), selected: quality === settings?.defaultVideoQuality,
          action: () => { this.service?.setVideoQuality(quality).catch((error: Error) => { this.notify(error); }); }
        })) }] },
      { id: 'session.resolution.select', label: tr('分辨率'), value: this.resolutionLabel(settings?.defaultVideoProfile ?? 'auto'),
        action: () => {}, children: [{ title: '', items: this.resolutionOptions().map((profile: string): SessionMenuItem => ({
          id: 'session.resolution.' + profile, label: this.resolutionLabel(profile), selected: profile === settings?.defaultVideoProfile,
          action: () => { this.service?.setVideoProfile(profile).catch((error: Error) => { this.notify(error); }); }
        })) }] },
      { id: 'session.fps.select', label: tr('帧率'), value: (settings?.defaultFrameRate ?? 60) + tr(' 帧'),
        action: () => {}, children: [{ title: '', items: this.frameRateOptions().map((fps: number): SessionMenuItem => ({
          id: 'session.fps.' + fps, label: fps + tr(' 帧'), selected: fps === settings?.defaultFrameRate,
          action: () => { this.service?.setFrameRate(fps).catch((error: Error) => { this.notify(error); }); }
        })) }] },
      { id: 'session.color.select', label: tr('色彩'), value: settings?.trueColor === true && this.chroma444 ? '4:4:4' : '4:2:0',
        action: () => {}, children: [{ title: '', items: (this.chroma444 ? [false, true] : [false]).map((trueColor: boolean): SessionMenuItem => ({
          id: 'session.color.' + (trueColor ? '444' : '420'), label: trueColor ? '4:4:4' : '4:2:0',
          selected: trueColor === (settings?.trueColor === true && this.chroma444),
          action: () => { this.service?.setTrueColor(trueColor).catch((error: Error) => { this.notify(error); }); }
        })) }] }
    ] }];
  }
  @Builder
  floatingHeader() {
    Row() {
      Stack({ alignContent: Alignment.TopStart }) {
        if (sessionMaterialSupported()) {
          SessionMaterialBackplate({ nodeId: 'session.header.capsule.material' })
        }
        if (buttonPressShadowSupported && !this.disconnecting && this.pressedMenuButton === 'header.back') {
          buttonPressEdgeLayer(24, 'session.header.press-glow')
        }
        Row() {
          Button({ type: ButtonType.Circle, stateEffect: false }) {
            Image(iconResource('back', true, false)).width(24).height(24)
              .fillColor($r('sys.color.icon_primary')).objectFit(ImageFit.Contain).draggable(false).accessibilityLevel('no')
          }.width(48).height(48).backgroundColor(Color.Transparent)
            .attributeModifier(floatingFeedback).enabled(!this.disconnecting)
            .onTouch((event: TouchEvent) => {
              this.pressedMenuButton = pressedButtonAfterTouch(this.pressedMenuButton, 'header.back', event);
            })
            .id('session.back').accessibilityText(tr('返回')).onClick(() => { this.endDialog = true; })
          Column({ space: 2 }) {
            Text(this.session.targetName.length > 0 ? this.session.targetName : tr('远程设备'))
              .fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).id('session.title').hitTestBehavior(HitTestMode.None)
            Text(this.statusText()).fontSize(12).fontColor($r('sys.color.font_secondary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).id('session.status').hitTestBehavior(HitTestMode.None)
          }.constraintSize({ maxWidth: Math.min(this.pageWidth - 152, 240) }).height(48).padding({ right: 16 })
            .alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Center).hitTestBehavior(HitTestMode.None)
        }.height(48).hitTestBehavior(HitTestMode.None)
        if (this.networkVisible) {
          Column({ space: 4 }) {
            Text((this.networkStats.fps ?? 0) + ' FPS · ' + Math.round(this.networkStats.kbps ?? 0) + ' kbps')
              .fontColor($r('sys.color.font_primary')).fontSize(12).lineHeight(16)
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).hitTestBehavior(HitTestMode.None)
            Text((this.networkStats.rttMs === null ? '—' : this.networkStats.rttMs + ' ms') + ' · ' +
              (this.networkStats.route ?? '—'))
              .fontColor($r('sys.color.font_secondary')).fontSize(12).lineHeight(16)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).hitTestBehavior(HitTestMode.None)
          }.width(LayoutPolicy.matchParent).height(NETWORK_DETAILS_HEIGHT)
            .padding({ left: 16, right: 16, bottom: 8 }).justifyContent(FlexAlign.Center)
            .position({ x: 0, y: 48 }).id('session.network.stats').hitTestBehavior(HitTestMode.None)
            .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.Friction }))
        }
      }.width(LayoutPolicy.wrapContent).height(48 + (this.networkVisible ? NETWORK_DETAILS_HEIGHT : 0))
        .borderRadius(24).clip(true)
        .attributeModifier(sessionSurfaceControl()).id('session.header.capsule').hitTestBehavior(HitTestMode.None)
      Blank(8).layoutWeight(1).hitTestBehavior(HitTestMode.None)
      Button({ type: ButtonType.Circle, stateEffect: !buttonPressShadowSupported }) {
        sessionFloatingIcon({ icon: 'more', dark: true, id: 'session.more',
          pressed: !this.menuOpen && this.pressedMenuButton === 'trigger' })
      }.width(48).height(48).padding(0).attributeModifier(sessionSurfaceControl())
        .enabled(!this.menuOpen).id('session.more').accessibilityText(tr('更多'))
        .visualEffect(buttonPressShadow(!this.menuOpen && this.pressedMenuButton === 'trigger', false))
        .onTouch((event: TouchEvent) => {
          this.pressedMenuButton = pressedButtonAfterTouch(this.pressedMenuButton, 'trigger', event);
        })
        .onClick(() => { this.openMenu(); })
    }.width('100%').height(Metrics.floatingHeaderHeight + (this.networkVisible ? NETWORK_DETAILS_HEIGHT : 0))
      .alignItems(VerticalAlign.Top)
      .reverse(this.headerMoreOnLeft())
      .padding({ left: Metrics.floatingInset, right: Metrics.floatingInset, top: Metrics.floatingInset })
      .position({ x: 0, y: 0 }).id('session.header')
      .hitTestBehavior(HitTestMode.None)
  }

  private headerMoreOnLeft(): boolean { return this.holdingHandSubscribed && this.controlBarPosition === 'left'; }

  private controlAlignment(): HorizontalAlign {
    return this.controlBarPosition === 'left' ? HorizontalAlign.Start :
      this.controlBarPosition === 'right' ? HorizontalAlign.End : HorizontalAlign.Center;
  }

  private menuOverlapsToolbar(): boolean {
    if (!this.menuOpen) { return false; }
    const inset = Metrics.floatingInset;
    const width = this.toolbarLayout().width;
    const left = this.controlBarPosition === 'left' ? inset :
      this.controlBarPosition === 'right' ? this.pageWidth - inset - width : (this.pageWidth - width) / 2;
    const bottom = this.menuViewportHeight - inset;
    const top = bottom - 48;
    const stackLeft = this.toolbarMenuOpen || this.headerMoreOnLeft() ? 0 : this.pageWidth - this.menuCanvasWidth();
    for (let depth = this.toolbarMenuOpen ? 1 : 0; depth <= this.menuPath.length; depth++) {
      const x = stackLeft + this.menuLeft(depth);
      const y = this.menuTop(depth) + inset;
      if (x < left + width && x + this.menuWidth(depth) > left && y < bottom && y + this.menuHeight(depth) > top) {
        return true;
      }
    }
    return false;
  }

  @Builder
  keyboardModeButton(mode: RemoteKeyboardMode, label: string) {
    Button({ type: ButtonType.Capsule, stateEffect: !buttonPressShadowSupported }) {
      Stack() {
        if (sessionMaterialSupported()) {
          SessionMaterialBackplate({ radius: 20, nodeId: 'session.keyboard.mode.' + mode + '.material' })
          if (this.keyboardMode === mode) {
            Stack() {}
              .width(LayoutPolicy.matchParent).height(LayoutPolicy.matchParent).borderRadius(20)
              .backgroundColor($r('app.color.session_selection')).hitTestBehavior(HitTestMode.None)
          }
        }
        if (buttonPressShadowSupported && this.pressedMenuButton === 'keyboard.mode.' + mode) {
          buttonPressEdgeLayer(20, 'session.keyboard.mode.' + mode + '.press-glow')
        }
        Text(label).fontSize(14).fontColor($r('sys.color.font_primary')).textAlign(TextAlign.Center)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).padding({ left: 4, right: 4 })
      }.width('100%').height('100%')
    }
      .height(40).layoutWeight(1).padding(0)
      .backgroundColor(sessionMaterialSupported() ? Color.Transparent :
        this.keyboardMode === mode ? $r('app.color.session_selection') : $r('app.color.session_glass'))
      .attributeModifier(floatingFeedback).focusOnTouch(false).accessibilitySelected(this.keyboardMode === mode)
      .id('session.keyboard.mode.' + mode).accessibilityText(label)
      .visualEffect(buttonPressShadow(this.pressedMenuButton === 'keyboard.mode.' + mode, false))
      .onTouch((event: TouchEvent) => {
        this.pressedMenuButton = pressedButtonAfterTouch(this.pressedMenuButton, 'keyboard.mode.' + mode, event);
      })
      .onClick(() => { this.switchKeyboardMode(mode); })
  }

  @Builder
  keyboardPanel() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        this.keyboardModeButton('text', tr('文字输入'))
        this.keyboardModeButton('computer', tr('电脑键盘'))
        this.keyboardModeButton('shortcuts', tr('快捷键'))
        if (this.keyboardMode !== 'text') {
          Button({ type: ButtonType.Circle }) {
            Image(iconResource('close', true, false)).width(24).height(24)
              .fillColor($r('sys.color.icon_primary')).objectFit(ImageFit.Contain).draggable(false).accessibilityLevel('no')
          }.width(40).height(40).attributeModifier(floatingControl)
            .id('session.keyboard.close').accessibilityText(tr('关闭键盘')).onClick(() => { this.closeKeyboard(); })
        }
      }.width(Math.min(this.keyboardPanelWidth(), 720))
      if (this.keyboardMode === 'text') {
        this.textBar()
      } else {
        RemoteKeyboard({
          mode: this.keyboardMode,
          panelWidth: this.keyboardPanelWidth(),
          panelHeight: Math.max(72, Math.min(320, this.pageHeight - Metrics.floatingHeaderHeight -
            40 - 3 * Metrics.floatingInset)),
          platform: this.remotePlatform(),
          armedKeys: this.armedKeyboardKeys,
          inputEnabled: this.keyboardInputEnabled(),
          onKey: (code: number) => { this.pressComputerKey(code); },
          onShortcut: (codes: number[]) => { this.sendKeyboardChord(codes); }
        })
      }
    }.width(this.keyboardPanelWidth())
      .id('session.keyboard.panel')
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.keyboardGlobalY = Number.parseFloat(`${newValue.globalPosition.y}`);
      })
  }

  @Builder
  textBar() {
    Row({ space: 8 }) {
      TextInput({ text: this.textValue, placeholder: tr('输入要发送到远端的文字') })
        .layoutWeight(1)
        .height(48)
        .fontSize(16)
        .fontColor($r('app.color.session_text'))
        .backgroundColor($r('app.color.session_glass'))
        .border({ width: 1, color: $r('app.color.session_glass_stroke') })
        .borderRadius($r('sys.float.corner_radius_level8'))
        .id('session.text.input')
        .onAppear(() => {
          this.keyboardTimer = setTimeout(() => {
            if (!this.keyboardOpen || this.keyboardMode !== 'text') { return; }
            try { this.getUIContext().getFocusController().requestFocus('session.text.input'); }
            catch (error) { this.notify(error as Error); }
          }, 100);
        })
        .onChange((value: string) => {
          this.textValue = value;
        })
        .onSubmit((enterKey: EnterKeyType) => {
          this.sendText();
        })
      Button(tr('发送'), { type: ButtonType.Capsule })
        .height(48)
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
        .attributeModifier(floatingControl)
        .enabled(this.textValue.length > 0)
        .id('session.text.send')
        .onClick(() => {
          this.sendText();
        })
      Button({ type: ButtonType.Circle }) {
        Image(iconResource('close', true, false)).width(24).height(24)
          .fillColor($r('sys.color.icon_primary'))
          .objectFit(ImageFit.Contain).draggable(false).accessibilityLevel('no')
      }
        .width(48).height(48).attributeModifier(floatingControl)
        .id('session.text.close').accessibilityText(tr('关闭键盘'))
        .onClick(() => { this.closeKeyboard(); })
    }
    .width(Math.min(this.pageWidth - Metrics.floatingInset * 2, 640))
    .height(48)
    .id('session.text.bar')
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
      .animation({ duration: 180, curve: Curve.Friction }))
  }

  build() {
    WithTheme({ colorMode: ThemeColorMode.DARK }) {
    Stack({ alignContent: Alignment.Bottom }) {
      ImmersiveBackdrop({ session: true })
      Stack() {
        XComponent({
          id: 'session.surface.xcomponent',
          type: XComponentType.SURFACE,
          controller: this.surfaceController
        })
          .width(this.fittedVideoRect()[2])
          .height(this.fittedVideoRect()[3])
          .position({ x: this.fittedVideoRect()[0], y: this.positionedVideoRect()[1] })
          .scale({ x: this.zoomScale, y: this.zoomScale })
          .translate({ x: this.zoomX, y: this.zoomY })
          .id('session.video')
          .focusable(true).defaultFocus(true)
          .onLoad((context?: object) => {
            const id = this.surfaceController.getXComponentSurfaceId();
            if (id.length === 0) {
              return;
            }
            this.surfaceId = id;
            this.service?.attachSurface(id,
              this.getUIContext().vp2px(this.surfaceWidth),
              this.getUIContext().vp2px(this.surfaceHeight));
            this.preparePiP();
          })
          .onDestroy(() => {
            if (this.surfaceId.length > 0) {
              const id = this.surfaceId;
              this.stopSessionPiP().then(() => { this.service?.detachSurface(id); });
              this.surfaceId = '';
            }
          })

        Column()
          .width('100%')
          .height('100%')
          .id('session.gestures')
          .backgroundColor(Color.Transparent)
          .onTouch((event: TouchEvent) => {
            this.onSurfaceTouch(event);
          })
          .onMouse((event: MouseEvent) => { this.handleMouse(event); })
          .onHover((hover: boolean) => { if (!hover) { this.pointerInside = false; this.applyCursor(); } })
          .onAxisEvent((event: AxisEvent) => { this.onAxis(event); })
          .parallelGesture(
            GestureGroup(GestureMode.Parallel,
              PinchGesture({ fingers: 2 })
                .onActionStart((event: GestureEvent) => { this.beginPinch(event); })
                .onActionUpdate((event: GestureEvent) => { this.updatePinch(event); })
                .onActionEnd(() => { this.pinching = false; })
                .onActionCancel(() => { this.pinching = false; }),
              PanGesture({ fingers: 1, distance: 6 })
                .onActionStart((event: GestureEvent) => {
                  if (!this.canPanViewportWithTouch() || this.pinching || event.source === SourceType.Mouse || event.fingerList.length !== 1) { return; }
                  this.zoomMoved = true; this.panning = true;
                  this.panStartX = this.zoomX; this.panStartY = this.zoomY;
                })
                .onActionUpdate((event: GestureEvent) => {
                  if (!this.panning || this.pinching) { return; }
                  this.moveViewport(this.panStartX + event.offsetX, this.panStartY + event.offsetY);
                })
                .onActionEnd(() => { this.panning = false; })
                .onActionCancel(() => { this.panning = false; })
            )
          )

        if (!this.cleanView && this.fingerprintUnlockReady && this.session.remoteUnlock?.locked === true && !this.session.viewOnly &&
          !this.keyboardOpen && !this.menuOpen && !this.fingerprintSetupOpen) {
          this.fingerprintUnlockButton()
        } else if (!this.cleanView && (this.session.phase === SessionPhase.WaitingFirstFrame || this.session.phase === SessionPhase.Negotiating)) {
          Column({ space: 8 }) {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(Color.White)
            Text(tr('等待远端首帧…'))
              .fontSize(14)
              .fontColor(Color.White)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .id('session.waiting')
        }
        if (!this.cleanView && this.virtualMouseVisible && !this.keyboardOpen && this.virtualMouseInitialY >= 0) {
          VirtualMouse({
            pageWidth: this.surfaceWidth, pageHeight: this.surfaceHeight,
            initialY: this.virtualMouseInitialY,
            bottomInset: Math.max(16, this.surfaceHeight - this.virtualMouseInitialY - 48),
            collapseRequest: this.virtualMouseCollapseRequest,
            onExpandedChange: (expanded: boolean) => { this.virtualMouseExpanded = expanded; },
            onPointerPosition: (x: number, y: number, screenX: number, screenY: number) => {
              this.placeVirtualPointer(x, y, screenX, screenY);
            },
            inputEnabled: !this.session.viewOnly && this.session.firstFrameReceived,
            videoRect: this.videoRect(), showPointer: false,
            onInput: (input: string) => { this.virtualMouseInput(input); },
            onRelease: () => { this.service?.releaseAllInput(); }
          })
        }
        if (this.session.firstFrameReceived && !this.pointerInside && !this.cursorInVideo()) { this.remotePointer() }
      }
      .width('100%').height('100%')
      .backgroundColor(Color.Black)
      .clip(true)
      .id('session.surface')
      .onBlur(() => { this.service?.releaseAllInput(); })
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.surfaceWidth = Number.parseFloat(`${newValue.width}`);
        this.surfaceHeight = Number.parseFloat(`${newValue.height}`);
        this.surfaceGlobalY = Number.parseFloat(`${newValue.globalPosition.y}`);
        this.placeInitialVirtualMouse();
        clearTimeout(this.surfaceResizeTimer);
        this.surfaceResizeTimer = setTimeout(() => {
          if (this.active) {
            this.service?.resizeViewport(this.getUIContext().vp2px(this.surfaceWidth), this.getUIContext().vp2px(this.surfaceHeight));
          }
        }, 120);
        this.moveViewport(this.zoomX, this.zoomY);
        UiProbe.record('session.surface', newValue);
      })
      .onKeyEvent((event: KeyEvent) => { this.onKey(event); })
      .focusable(true)
        if (!this.cleanView) {
        Column({ space: 8 }) {
          if (this.keyboardOpen) {
            this.keyboardPanel()
          }
          if (!this.keyboardOpen) {
            Row() {
              SessionToolbar({
                actions: this.toolbarActions(),
                isDark: true,
                menuOpen: $menuOpen,
                menuOverlaps: this.menuOverlapsToolbar(),
                layout: this.toolbarLayout(),
                zoomPercent: Math.round(this.zoomScale * 100),
                onAction: (id: string) => { this.activateToolbarAction(id); },
                onResetZoom: () => { this.resetViewport(); }
              })
            }
            .width(LayoutPolicy.wrapContent).height(48)
            .hitTestBehavior(HitTestMode.None)
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
              .animation({ duration: 180, curve: Curve.Friction }))
          }
        }
        .width('100%')
        .padding({ left: Metrics.floatingInset, right: Metrics.floatingInset })
        .alignItems(this.controlAlignment())
        .margin({ bottom: Metrics.floatingInset }).id('session.controls').hitTestBehavior(HitTestMode.None)
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.controlsGlobalY = Number.parseFloat(`${newValue.globalPosition.y}`);
          this.placeInitialVirtualMouse();
        })

        if (!this.keyboardOpen || this.pageHeight >= Metrics.floatingHeaderHeight + 48 + Metrics.floatingInset) {
          this.floatingHeader()
        }
        }
        if (this.menuOpen) {
          Column() { this.moreMenu() }
            .width('100%').height('100%').alignItems(this.headerMoreOnLeft() ? HorizontalAlign.Start : HorizontalAlign.End)
            .onClick(() => { this.menuOpen = false; })
            .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY).id('session.menu.overlay')
        }
        if (this.fingerprintSetupOpen) { this.fingerprintSetup() }
        if (this.toolbarEditorOpen) {
          Stack() {
            Column() {}.width('100%').height('100%').backgroundColor('#88000000')
              .onClick(() => { if (!this.toolbarSaving) { this.toolbarEditorOpen = false; } })
            SessionToolbarEditor({ available: this.toolbarCatalog(), selected: this.toolbarDraft,
              limit: this.toolbarLimit(), onToggle: (id: string) => { this.toggleToolbarDraft(id); },
              onMove: (id: string, direction: number) => { this.moveToolbarDraft(id, direction); },
              onClose: () => { this.saveToolbarDraft(); }
            }).width(Math.min(this.pageWidth - 32, 400)).height(Math.min(this.pageHeight - 32, 480))
          }.width('100%').height('100%').hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
        }
    ConfirmDialog({
      visible: this.endDialog,
      title: tr('结束远程连接'),
      body: tr('结束后将断开与远端设备的画面和输入。'),
      confirmText: tr('结束连接'),
      cancelText: tr('继续连接'),
      destructive: true,
      onConfirm: () => {
        this.endDialog = false;
        this.disconnectSession();
      },
      onCancel: () => {
        this.endDialog = false;
      }
    })
    }
    .width('100%').height('100%').id('session.page')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.pageWidth = Number.parseFloat(`${newValue.width}`);
      this.pageHeight = Number.parseFloat(`${newValue.height}`);
      const rect = this.sessionWindow?.getWindowProperties().windowRect;
      if (rect !== undefined) {
        const landscape = rect.width > rect.height;
        if (this.orientationPending && landscape !== this.landscape) {
          clearTimeout(this.orientationTimer); this.orientationTimer = -1; this.orientationPending = false;
        }
        this.landscape = landscape;
      }
    })
    }
  }
}
