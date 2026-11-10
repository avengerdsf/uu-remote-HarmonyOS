import { tr } from '../model/I18n';
import { PortMapRule, PortMapSnapshot } from '../model/Models';
import { ServiceHub } from '../services/ServiceHub';
import { SessionService } from '../services/SessionService';
import { ToolPageShell } from '../components/ToolPageShell';
import { edgeScrollBar } from '../components/EdgeScrollBar';

@Component
export struct PortMapPage {
  private formScroller: Scroller = new Scroller();
  private rulesScroller: Scroller = new Scroller();
  @State listenPort: string = '';
  @State targetHost: string = '127.0.0.1';
  @State targetPort: string = '';
  @State allowLan: boolean = false;
  @State localError: string = '';
  @State portMap: PortMapSnapshot = { phase: 'editing', rule: null, rules: [], statusText: '', error: null, boundAddress: '' };
  @StorageProp('currentWidthBreakpoint') widthBp: WidthBreakpoint = WidthBreakpoint.WIDTH_SM;
  private service: SessionService | null = null;
  private unsubscribe: (() => void) | null = null;

  aboutToAppear(): void {
    if (!ServiceHub.isReady()) { return; }
    this.service = ServiceHub.service();
    this.portMap = this.service.portMapSnapshot();
    this.unsubscribe = this.service.onPortMap((snapshot: PortMapSnapshot) => { this.portMap = snapshot; });
  }
  aboutToDisappear(): void { this.unsubscribe?.(); }

  private rules(): PortMapRule[] { return this.portMap.rules ?? (this.portMap.rule === null ? [] : [this.portMap.rule]); }
  private start(): void {
    if (!/^\d+$/.test(this.listenPort) || Number(this.listenPort) < 1024 || Number(this.listenPort) > 65535) {
      this.localError = tr('本地端口需为 1024 至 65535 的整数'); return;
    }
    if (!/^\d+$/.test(this.targetPort) || Number(this.targetPort) < 1 || Number(this.targetPort) > 65535) {
      this.localError = tr('目标端口需为 1 至 65535 的整数'); return;
    }
    if (this.targetHost.trim().length === 0) { this.localError = tr('请输入远端目标地址'); return; }
    this.localError = '';
    this.service?.startPortMap({ id: Date.now().toString(), listenAddress: this.allowLan ? '0.0.0.0' : '127.0.0.1',
      listenPort: Number(this.listenPort), targetHost: this.targetHost.trim(), targetPort: Number(this.targetPort), allowLan: this.allowLan
    }).catch((error: Error) => { this.localError = error.message; });
  }

  @Builder
  form() {
    Column({ space: 16 }) {
      Text(tr('新建映射')).fontSize(20).fontWeight(FontWeight.Medium).width('100%')
      TextInput({ text: this.listenPort, placeholder: tr('本地端口 · 1024–65535') }).type(InputType.Number)
        .onChange((text: string) => { this.listenPort = text; }).id('portmap.listenPort')
      TextInput({ text: this.targetHost, placeholder: tr('远端目标地址') })
        .onChange((text: string) => { this.targetHost = text; }).id('portmap.targetHost')
      TextInput({ text: this.targetPort, placeholder: tr('目标端口 · 1–65535') }).type(InputType.Number)
        .onChange((text: string) => { this.targetPort = text; }).id('portmap.targetPort')
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(tr('允许局域网连接')).fontSize(16)
          Text(this.allowLan ? tr('监听 0.0.0.0') : tr('仅监听 127.0.0.1')).fontSize(14).fontColor($r('sys.color.font_secondary'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.allowLan }).id('portmap.allowLan')
          .onChange((value: boolean) => { this.allowLan = value; })
      }.width('100%').padding({ top: 4 })
      if (this.localError.length > 0 || this.portMap.error !== null) {
        Text(this.localError.length > 0 ? this.localError : this.portMap.error ?? '')
          .fontSize(14).fontColor($r('app.color.error_text')).width('100%').id('portmap.error')
      }
      Button(this.portMap.phase === 'starting' ? tr('正在启动') : tr('添加映射'), { type: ButtonType.Capsule }).width('100%')
        .enabled(this.portMap.phase !== 'starting').onClick(() => { this.start(); }).id('portmap.start')
    }.width('100%').constraintSize({ maxWidth: 520 }).padding(20).alignItems(HorizontalAlign.Start).id('portmap.form')
  }

  @Builder
  ruleList() {
    Column({ space: 12 }) {
      Text(tr('运行中的映射')).fontSize(20).fontWeight(FontWeight.Medium).width('100%')
        .padding({ left: 20, right: 20 })
      if (this.rules().length === 0) {
        Text(tr('暂无端口映射')).fontSize(16).fontColor($r('sys.color.font_secondary')).padding(24)
      }
      Stack({ alignContent: Alignment.End }) {
      List({ space: 8, scroller: this.rulesScroller }) {
        ForEach(this.rules(), (rule: PortMapRule) => {
          ListItem() {
            Row({ space: 12 }) {
              Column({ space: 6 }) {
                Text(rule.listenAddress + ':' + rule.listenPort).fontSize(16)
                Text('→ ' + rule.targetHost + ':' + rule.targetPort).fontSize(14)
                  .fontColor($r('sys.color.font_secondary')).maxLines(2)
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Button(tr('停止'), { type: ButtonType.Capsule }).id('portmap.stop.' + rule.id)
                .onClick(() => { this.service?.stopPortMap(rule.id); })
            }.width('100%').padding(12)
          }.backgroundColor($r('sys.color.comp_background_secondary')).borderRadius($r('sys.float.corner_radius_level8'))
            .margin({ left: 20, right: 20 })
        }, (rule: PortMapRule) => rule.id)
      }.width('100%').height('100%').scrollBar(BarState.Off)
        .contentEndOffset(20).id('portmap.rules')
        edgeScrollBar(this.rulesScroller, 'portmap.rules')
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  formScroll() {
    Scroll(this.formScroller) { this.form() }.width('100%').height('100%')
      .align(Alignment.Top).scrollBar(BarState.Off).id('portmap.form.scroll')
  }

  build() {
    ToolPageShell({ title: tr('端口映射'), actionLabel: tr('全部停止'), actionId: 'portmap.stop', actionEnabled: this.rules().length > 0,
      scroller: this.rulesScroller, onAction: () => { this.service?.stopPortMap(); } }) {
      Stack() {
      if (this.widthBp >= WidthBreakpoint.WIDTH_LG) {
        Row() {
          Stack({ alignContent: Alignment.End }) {
            this.formScroll()
            edgeScrollBar(this.formScroller, 'portmap.form.scroll')
          }.width('44%').height('100%')
          Column() { this.ruleList() }.layoutWeight(1).height('100%')
        }.width('100%').height('100%')
      } else {
        Column() {
          Stack({ alignContent: Alignment.End }) {
            this.formScroll()
            edgeScrollBar(this.formScroller, 'portmap.form.scroll')
          }.width('100%').height('60%')
          Column() { this.ruleList() }.width('100%').layoutWeight(1)
        }.width('100%').height('100%')
      }
      }.width('100%').height('100%').id('portmap.page')
    }
  }
}
