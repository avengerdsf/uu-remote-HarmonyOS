import { tr } from '../model/I18n';
import { Metrics } from '../model/Tokens';
import { HostSnapshot } from '../model/Models';
import { Router } from '../model/Router';
import { ServiceHub } from '../services/ServiceHub';
import { SessionService } from '../services/SessionService';
import { IconView } from '../components/IconView';
import { ImmersiveBackdrop } from '../components/ImmersiveBackdrop';
import { edgeScrollBar } from '../components/EdgeScrollBar';
import { floatingFeedback } from '../theme/FloatingMaterial';

@Component
export struct HostPage {
  private scroller: Scroller = new Scroller();
  @State host: HostSnapshot = {
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
  private service: SessionService | null = null;
  private unsubscribe: (() => void) | null = null;

  aboutToAppear(): void {
    if (!ServiceHub.isReady()) {
      return;
    }
    this.service = ServiceHub.service();
    this.host = this.service.hostSnapshot();
    this.unsubscribe = this.service.onHost((snapshot: HostSnapshot) => {
      this.host = snapshot;
    });
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== null) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
  }

  private statusText(): string {
    if (this.host.statusText.length > 0) {
      return this.host.statusText;
    }
    switch (this.host.phase) {
      case 'waitingConsent':
        return tr('等待用户授权');
      case 'sharing':
        return tr('正在共享画面');
      case 'controlled':
        return tr('已授权控制');
      case 'revoked':
        return tr('授权已撤销');
      default:
        return tr('能力不可用');
    }
  }

  @Builder
  capabilityRow(icon: string, title: string, value: string, detail: string, available: boolean) {
    Row({ space: 12 }) {
      IconView({ iconKey: icon, selected: false, sizeVp: 24 })
      Column({ space: 2 }) {
        Text(title)
          .fontSize(16)
          .fontColor($r('app.color.primary_text'))
        Text(detail)
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
          .maxLines(3)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text(value)
        .fontSize(14)
        .fontColor(available ? $r('app.color.success_text') : $r('app.color.warning_text'))
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .padding(16)
    .backgroundColor($r('app.color.glass_input'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .border({ width: 1, color: $r('app.color.glass_stroke') })
    .borderRadius($r('sys.float.corner_radius_level8'))
  }

  build() {
    Stack() {
      ImmersiveBackdrop()
      Column() {
        Row({ space: 4 }) {
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          IconView({ iconKey: 'back', selected: false, sizeVp: 24, allowImageDrag: false })
        }
        .width(48)
        .height(48)
        .backgroundColor(Color.Transparent)
        .attributeModifier(floatingFeedback)
        .id('host.back')
        .onClick(() => {
          Router.back();
        })
        Text(tr('本机被控能力'))
          .fontSize(16)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(Metrics.floatingHeaderHeight)
      .padding({ left: Metrics.floatingInset, right: Metrics.floatingInset })
      .backgroundColor($r('app.color.chrome_tint'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
      .id('host.header')

      Stack({ alignContent: Alignment.End }) {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          Text(this.statusText())
            .fontSize(20)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
            .id('host.status')

          this.capabilityRow('host', tr('屏幕采集'),
            this.host.capabilities.capture ? tr('可用') : tr('不可用'),
            tr('共享本机屏幕需要系统屏幕采集授权。'), this.host.capabilities.capture)
          this.capabilityRow('cursor', tr('输入控制'),
            this.host.capabilities.inputInjection ? tr('已授权') : tr('未授权'),
            this.host.capabilities.reason, this.host.capabilities.inputInjection)
          this.capabilityRow('more', tr('后台运行'),
            this.host.capabilities.background ? tr('可用') : tr('受限'),
            tr('Pad 与 Phone 进入后台后不保证持续共享。'), this.host.capabilities.background)

          if (this.host.phase === 'sharing' || this.host.phase === 'controlled') {
            Button(tr('停止共享'), { type: ButtonType.Capsule })
              .width('100%')
              .height(48)
              .fontSize(16)
              .fontColor($r('app.color.error_text'))
              .backgroundColor(Color.Transparent)
              .border({ width: 1, color: $r('app.color.error_text') })
              .id('host.stop')
              .onClick(() => {
                this.service?.stopHost();
              })
          } else {
            Button(tr('开启屏幕共享'), { type: ButtonType.Capsule })
              .width('100%')
              .height(48)
              .fontSize(16)
              .fontColor($r('app.color.on_primary'))
              .backgroundColor(this.host.capabilities.capture ? $r('app.color.primary') : $r('app.color.border'))
              .shadow({
                radius: this.host.capabilities.capture ? 18 : 0,
                color: this.host.capabilities.capture ? $r('app.color.glow_primary') : '#00000000',
                offsetX: 0,
                offsetY: 6
              })
              .enabled(this.host.capabilities.capture)
              .id('host.capture')
              .onClick(() => {
                this.service?.requestCaptureConsent();
              })
          }

          Button(this.host.capabilities.inputScope === 'pc' ? tr('申请输入控制授权') : tr('此设备仅可共享画面'), { type: ButtonType.Capsule })
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontColor(this.host.capabilities.inputScope === 'pc' ? $r('app.color.primary') : $r('app.color.secondary_text'))
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: $r('app.color.border') })
            .enabled(this.host.capabilities.inputScope === 'pc' && !this.host.capabilities.inputInjection)
            .id('host.control')
            .onClick(() => {
              this.service?.requestInputConsent();
            })

          Text(tr('屏幕采集授权不等于输入注入授权。普通 Pad 与 Phone 不提供全系统键鼠控制，仅可共享画面。'))
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        }
        .width('100%')
        .padding(16)
      }
      .height('100%')
      .width('100%')
      .scrollBar(BarState.Off).id('host.scroll')
        edgeScrollBar(this.scroller, 'host.scroll')
      }.width('100%').layoutWeight(1)
    }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .id('host.page')
    }
    .width('100%')
    .height('100%')
  }
}
