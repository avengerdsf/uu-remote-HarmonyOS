import { tr } from '../model/I18n';
import { LoginPhase, LoginSnapshot } from '../model/Models';
import { Tokens } from '../model/Tokens';
import { Router } from '../model/Router';
import { ServiceHub } from '../services/ServiceHub';
import { SessionService } from '../services/SessionService';
import { IconView } from '../components/IconView';
import { GlassPanel } from '../components/GlassPanel';
import { ImmersiveBackdrop } from '../components/ImmersiveBackdrop';
import { UiProbe } from '../testkit/UiProbe';
import { edgeScrollBar } from '../components/EdgeScrollBar';
import { common } from '@kit.AbilityKit';
import { LayeredDrawableDescriptor } from '@kit.ArkUI';
import { hdsDrawable } from '@kit.UIDesignKit';
import { image } from '@kit.ImageKit';

@Component
export struct LoginPage {
  private scroller: Scroller = new Scroller();
  @State appIcon: image.PixelMap | null = null;
  @State login: LoginSnapshot = {
    phase: LoginPhase.LoadingQr,
    statusText: '',
    qrPayload: null,
    pollingActive: false,
    authenticated: false,
    error: null,
    generation: 0
  };
  private service: SessionService | null = null;
  private unsubscribe: (() => void) | null = null;

  aboutToAppear(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const icon = context.resourceManager.getDrawableDescriptorByName('app_layered_icon') as LayeredDrawableDescriptor;
      this.appIcon = hdsDrawable.getHdsLayeredIcon(context.abilityInfo.bundleName, icon,
        Math.round(this.getUIContext().vp2px(56)), true);
    } catch (error) { /* Use the rounded start-window icon when themed icons are unavailable. */ }
    if (!ServiceHub.isReady()) {
      return;
    }
    this.service = ServiceHub.service();
    this.login = this.service.loginSnapshot();
    this.unsubscribe = this.service.onLogin((snapshot: LoginSnapshot) => {
      this.login = snapshot;
      if (snapshot.authenticated) {
        Router.reset('devices');
      }
    });
    if (this.login.phase === LoginPhase.LoadingQr && this.login.qrPayload === null) {
      this.service.loginStart();
    }
  }

  aboutToDisappear(): void {
    const icon = this.appIcon;
    this.appIcon = null;
    icon?.release().catch(() => {});
    if (this.unsubscribe !== null) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
    if (this.login.pollingActive && this.service !== null) {
      this.service.loginCancel();
    }
  }

  private canRefresh(): boolean {
    return this.login.phase === LoginPhase.Expired || this.login.phase === LoginPhase.Failed ||
      this.login.phase === LoginPhase.QueryFailed;
  }

  private refreshLabel(): string {
    return this.login.phase === LoginPhase.QueryFailed ? tr('重新获取二维码') : tr('刷新二维码');
  }

  @Builder
  loginBody() {
    Column() {
      Image(this.appIcon ?? $r('app.media.app_icon'))
        .width(56)
        .height(56)
        .clip(true).id('login.appIcon')
        .shadow({
          radius: 20,
          color: $r('app.color.glow_primary'),
          offsetX: 0,
          offsetY: 8
        })
        .margin({ bottom: 16 })

      Text(tr('登录 UU 远程'))
        .fontSize(24)
        .fontColor($r('app.color.primary_text'))
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 8 })
      Text(tr('使用 UU 远程手机应用扫描二维码'))
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 24 })

      Stack() {
        if (this.login.qrPayload !== null && this.login.phase !== LoginPhase.Expired) {
          QRCode(this.login.qrPayload === null ? '' : this.login.qrPayload)
            .width(200)
            .height(200)
            .color(Color.Black)
            .backgroundColor(Color.White)
            .id('login.qr')
        } else {
          Column({ space: 8 }) {
            IconView({ iconKey: 'close', selected: false, sizeVp: 48 })
            Text(this.login.phase === LoginPhase.Expired ? tr('二维码已过期') : tr('二维码暂不可用'))
              .fontSize(14)
              .fontColor($r('app.color.secondary_text'))
          }
          .width(200)
          .height(200)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(Color.White)
          .id('login.qr.placeholder')
        }
      }
      .width(Tokens.qrOuter)
      .height(Tokens.qrOuter)
      .padding(Tokens.qrPadding)
      .backgroundColor(Color.White)
      .borderRadius($r('sys.float.corner_radius_level8'))
      .border({ width: 1, color: $r('app.color.glass_stroke') })
      .shadow({
        radius: 28,
        color: $r('app.color.glass_shadow'),
        offsetX: 0,
        offsetY: 12
      })
      .id('login.qr.outer')

      Row({ space: 8 }) {
        if (this.login.phase === LoginPhase.LoadingQr) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color($r('app.color.primary'))
        }
        Text(this.login.statusText)
          .fontSize(16)
          .fontColor(this.login.phase === LoginPhase.Failed ? $r('app.color.error_text') : $r('app.color.primary_text'))
          .textAlign(TextAlign.Center)
          .id('login.status')
      }
      .constraintSize({ minHeight: 44 })
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.glass_input'))
      .border({ width: 1, color: $r('app.color.glass_stroke') })
      .borderRadius($r('sys.float.corner_radius_level8'))
      .margin({ top: 16 })

      if (this.login.error !== null) {
        Text(this.login.error)
          .fontSize(14)
          .fontColor($r('app.color.error_text'))
          .textAlign(TextAlign.Center)
          .margin({ top: 8 })
          .id('login.error')
      }

      if (this.canRefresh()) {
        Button(this.refreshLabel(), { type: ButtonType.Capsule })
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontColor($r('app.color.on_primary'))
          .backgroundColor($r('app.color.primary'))
          .shadow({
            radius: 18,
            color: $r('app.color.glow_primary'),
            offsetX: 0,
            offsetY: 6
          })
          .margin({ top: 24 })
          .id('login.refresh')
          .onClick(() => {
            this.service?.loginStart();
          })
      }

      Button(tr('取消'), { type: ButtonType.Capsule })
        .width('100%')
        .height(48)
        .fontSize(16)
        .fontColor($r('app.color.primary'))
        .backgroundColor(Color.Transparent)
        .margin({ top: this.canRefresh() ? 8 : 24 })
        .id('login.cancel')
        .onClick(() => {
          this.service?.loginCancel();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Stack() {
      ImmersiveBackdrop()

      Scroll(this.scroller) {
        Column() {
          Column() {
            GlassPanel({ contentPadding: 24 }) {
              this.loginBody()
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: Tokens.loginCardMax })
          .id('login.card')
          .onAreaChange((oldValue: Area, newValue: Area) => {
            UiProbe.record('login.card', newValue);
          })
        }
        .width('100%')
        .padding(16)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off).id('login.scroll')
      edgeScrollBar(this.scroller, 'login.scroll')
    }
    .width('100%')
    .height('100%')
    .id('login.page')
    .alignContent(Alignment.End)
  }
}
