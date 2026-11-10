import { tr } from '../model/I18n';
import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { HdsNavigationMenuItemOptions } from '@kit.UIDesignKit';
import { ControlBarPosition, TerminalSnapshot, TerminalSessionInfo } from '../model/Models';
import { ServiceHub } from '../services/ServiceHub';
import { SessionService } from '../services/SessionService';
import { ToolPageShell } from '../components/ToolPageShell';
import { iconResource } from '../model/Icons';
import { edgeScrollBar } from '../components/EdgeScrollBar';
import { sessionFloatingControl } from '../theme/FloatingMaterial';
import { SystemBars } from '../theme/SystemBars';

class TerminalBridge {
  onInput: (text: string) => void = () => {};
  onResize: (columns: number, rows: number) => void = () => {};
  input(text: string): void { if (text.length <= 16384) { this.onInput(text); } }
  resize(columns: number, rows: number): void {
    if (columns > 0 && columns <= 1000 && rows > 0 && rows <= 1000) { this.onResize(columns, rows); }
  }
}

@Component
export struct TerminalPage {
  private sessionsScroller: Scroller = new Scroller();
  @State terminal: TerminalSnapshot = { phase: 'connecting', sessionId: '', output: '', error: null };
  @State sessionListOpen: boolean = false;
  @State controlBarPosition: ControlBarPosition = 'center';
  @State headerInset: number = 0;
  @StorageProp('isDark') isDark: boolean = false;
  private service: SessionService | null = null;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: TerminalBridge = new TerminalBridge();
  private unsubscribe: (() => void) | null = null;
  private unsubscribeData: (() => void) | null = null;
  @State webReady: boolean = false;
  private holdingHandSubscribed: boolean = false;
  private onHoldingHandChanged = (status: motion.HoldingHandStatus): void => {
    const position: ControlBarPosition = status === motion.HoldingHandStatus.LEFT_HAND_HELD ? 'left' :
      status === motion.HoldingHandStatus.RIGHT_HAND_HELD ? 'right' : 'center';
    if (position === this.controlBarPosition) { return; }
    this.getUIContext().animateTo({ duration: 260, curve: Curve.Friction }, () => { this.controlBarPosition = position; });
  };

  aboutToAppear(): void {
    if (!ServiceHub.isReady()) { return; }
    this.service = ServiceHub.service();
    SystemBars.apply(this.getUIContext().getHostContext() as common.UIAbilityContext, true);
    const settings = this.service.settings();
    this.controlBarPosition = settings.smartReachEnabled ? 'center' : settings.controlBarPosition;
    if (settings.smartReachEnabled && deviceInfo.deviceType !== '2in1' && canIUse('SystemCapability.MultimodalAwareness.Motion')) {
      try {
        motion.on('holdingHandChanged', this.onHoldingHandChanged);
        this.holdingHandSubscribed = true;
      } catch (error) { console.info('Holding-hand detection is unavailable; controls stay centered'); }
    }
    this.terminal = this.service.terminalSnapshot();
    this.bridge.onInput = (text: string) => { this.service?.terminalWrite(text); };
    this.bridge.onResize = (columns: number, rows: number) => { this.service?.terminalResize(columns, rows); };
    this.unsubscribe = this.service.onTerminal((snapshot: TerminalSnapshot) => {
      const changed = snapshot.ptyId !== this.terminal.ptyId || (snapshot.phase === 'ready' && this.terminal.phase !== 'ready');
      this.terminal = snapshot;
      if (changed) { this.script('uuReset', snapshot.output); this.fit(); }
    });
    this.unsubscribeData = this.service.onTerminalData((text: string) => { this.script('uuWrite', text); });
    if (this.terminal.phase !== 'ready') { this.service.openTerminal(); }
  }

  aboutToDisappear(): void {
    this.unsubscribe?.(); this.unsubscribeData?.();
    this.webReady = false;
    if (this.holdingHandSubscribed) {
      try { motion.off('holdingHandChanged', this.onHoldingHandChanged); } catch (error) { /* The motion service may have stopped. */ }
      this.holdingHandSubscribed = false;
    }
    SystemBars.apply(this.getUIContext().getHostContext() as common.UIAbilityContext, this.isDark);
    this.bridge.onInput = () => {}; this.bridge.onResize = () => {};
  }

  private script(method: string, text: string): void {
    if (!this.webReady) { return; }
    this.controller.runJavaScript('window.' + method + '(' + JSON.stringify(text) + ')').catch(() => {});
  }
  private fit(): void {
    if (!this.webReady) { return; }
    const ui = this.getUIContext();
    const utils = ui.getComponentUtils();
    const header = utils.getRectangleById('tool.back');
    const viewport = utils.getRectangleById('terminal.viewport');
    const inset = Math.max(0, ui.px2vp(header.windowOffset.y + header.size.height - viewport.windowOffset.y) + 12);
    this.controller.runJavaScript('window.uuSetTopInset(' + inset + ');window.uuFit()').catch(() => {});
  }
  private updateHeaderInset(): void {
    this.fit();
    if (!this.sessionListOpen && this.terminal.error === null) { return; }
    const ui = this.getUIContext();
    const utils = ui.getComponentUtils();
    const header = utils.getRectangleById('tool.back');
    const message = utils.getRectangleById(this.sessionListOpen ? 'terminal.sessionList' : 'terminal.error');
    const inset = Math.max(0, this.headerInset + ui.px2vp(header.windowOffset.y + header.size.height - message.windowOffset.y) + 12);
    if (Math.abs(inset - this.headerInset) > 0.5) { this.headerInset = inset; }
  }
  private menu(): HdsNavigationMenuItemOptions[] {
    return [
      { content: { label: tr('新建终端'), icon: iconResource('terminal', true, false), componentId: 'terminal.new',
        action: () => { this.service?.openTerminal(); } } },
      { content: { label: tr('会话列表'), icon: iconResource('more', true, false), componentId: 'terminal.sessions',
        action: () => { this.sessionListOpen = !this.sessionListOpen; this.service?.terminalSessions(); } } },
      { content: { label: tr('关闭终端'), icon: iconResource('close', true, false), componentId: 'terminal.close',
        action: () => { this.getUIContext().showAlertDialog({ title: tr('关闭终端'), message: tr('确认结束当前远端终端？'),
          primaryButton: { value: tr('取消'), action: () => {} },
          secondaryButton: { value: tr('关闭'), action: () => { this.service?.closeTerminal(); } } }); } } }
    ];
  }
  private controlAlignment(): HorizontalAlign {
    return this.controlBarPosition === 'left' ? HorizontalAlign.Start :
      this.controlBarPosition === 'right' ? HorizontalAlign.End : HorizontalAlign.Center;
  }

  @Builder
  shortcut(label: string, key: string, id: string) {
    Button({ type: label === 'Ctrl+C' ? ButtonType.Capsule : ButtonType.Circle }) {
      Text(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.session_text')).maxLines(1)
    }.width(label === 'Ctrl+C' ? 64 : 48).height(48).padding(0)
      .attributeModifier(sessionFloatingControl).focusOnTouch(false)
      .enabled(this.terminal.phase === 'ready' && this.webReady).id('terminal.key.' + id)
      .onClick(() => { this.service?.terminalWrite(key); })
  }

  @Builder
  arrowShortcut(up: boolean) {
    Button({ type: ButtonType.Circle }) {
      Image(iconResource('chevron', true, false)).width(24).height(24).objectFit(ImageFit.Contain)
        .fillColor($r('app.color.session_text'))
        .rotate({ angle: up ? -90 : 90 }).draggable(false).accessibilityLevel('no')
    }.width(48).height(48).attributeModifier(sessionFloatingControl).focusOnTouch(false)
      .enabled(this.terminal.phase === 'ready' && this.webReady).id(up ? 'terminal.key.up' : 'terminal.key.down')
      .accessibilityText(up ? tr('向上') : tr('向下'))
      .onClick(() => { this.service?.terminalWrite(up ? '\u001b[A' : '\u001b[B'); })
  }

  @Builder
  shortcuts() {
    Row({ space: 8 }) {
      this.shortcut('Esc', '\u001b', 'esc')
      this.shortcut('Tab', '\t', 'tab')
      this.shortcut('Ctrl+C', '\u0003', 'interrupt')
      this.arrowShortcut(true)
      this.arrowShortcut(false)
    }.height(48).id('terminal.controls')
  }
  private kill(item: TerminalSessionInfo): void {
    this.getUIContext().showAlertDialog({ title: tr('结束终端会话'), message: tr('此操作将终止所选终端中的进程。'),
      primaryButton: { value: tr('取消'), action: () => {} },
      secondaryButton: { value: tr('结束'), action: () => {
        this.service?.killTerminal(item.sessionId).catch((error: Error) => {
          this.getUIContext().getPromptAction().showToast({ message: error.message });
        });
      } } });
  }

  build() {
    WithTheme({ colorMode: ThemeColorMode.DARK }) {
    ToolPageShell({ title: tr('远端终端'), darkIcons: true, alwaysBlur: true, subtitle: this.terminal.phase === 'ready' ? tr('已连接') : this.terminal.phase === 'connecting' ? tr('正在连接') : tr('已断开'), menus: this.menu() }) {
      Column() {
        if (this.sessionListOpen) {
          Stack({ alignContent: Alignment.TopEnd }) {
          List({ scroller: this.sessionsScroller }) {
            ForEach(this.terminal.sessions ?? [], (item: TerminalSessionInfo) => {
              ListItem() {
                Row({ space: 12 }) {
                  Text('#' + item.sessionId + ' · ' + item.shell + ' · ' + item.state)
                    .fontSize(14).fontColor($r('app.color.session_text')).layoutWeight(1)
                  Row({ space: 8 }) {
                    Button(tr('连接'), { type: ButtonType.Capsule }).id('terminal.attach.' + item.sessionId)
                      .onClick(() => { this.service?.attachTerminal(item.sessionId); this.sessionListOpen = false; })
                    Button(tr('结束'), { type: ButtonType.Capsule }).id('terminal.kill.' + item.sessionId)
                      .fontColor($r('app.color.error_text')).onClick(() => { this.kill(item); })
                  }
                }.padding(12).width('100%')
              }
            }, (item: TerminalSessionInfo) => '' + item.sessionId)
          }.width('100%').constraintSize({ maxHeight: 200 }).scrollBar(BarState.Off).id('terminal.sessionList')
            edgeScrollBar(this.sessionsScroller, 'terminal.sessionList')
          }.width('100%').height(LayoutPolicy.wrapContent).constraintSize({ maxHeight: 200 })
            .margin({ top: this.headerInset }).id('terminal.sessions.panel')
            .onAreaChange(() => { this.updateHeaderInset(); })
        }
        if (this.terminal.error !== null) {
          Text(this.terminal.error).fontColor($r('app.color.error_text')).fontSize(14).padding(12).width('100%')
            .margin({ top: this.sessionListOpen ? 0 : this.headerInset })
            .id('terminal.error').onAreaChange(() => { this.updateHeaderInset(); })
        }
        Stack({ alignContent: Alignment.Bottom }) {
        Web({ src: $rawfile('terminal/index.html'), controller: this.controller })
          .javaScriptAccess(true).domStorageAccess(false).fileAccess(true).blockNetwork(true)
          .javaScriptProxy({ object: this.bridge, name: 'uuTerminal', methodList: ['input', 'resize'], controller: this.controller })
          .onOverrideUrlLoading((request: WebResourceRequest): boolean => {
            return !request.getRequestUrl().startsWith('resource://rawfile/terminal/');
          })
          .onPageEnd(() => {
            this.webReady = true;
            this.script('uuReset', this.service?.terminalSnapshot().output ?? '');
            this.fit();
            this.controller.runJavaScript('window.uuReady()').catch(() => {});
          })
          .onAreaChange(() => { this.fit(); })
          .width('100%').height('100%').backgroundColor('#101216').id('terminal.viewport')
        Column() { this.shortcuts() }.width('100%').padding({ left: 16, right: 16, bottom: 16 })
          .alignItems(this.controlAlignment()).hitTestBehavior(HitTestMode.None)
        }.layoutWeight(1).width('100%').id('terminal.canvas')
      }.width('100%').height(LayoutPolicy.matchParent).backgroundColor('#101216').id('terminal.page')
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
        .onAreaChange(() => { this.updateHeaderInset(); })
    }
    }
  }
}
