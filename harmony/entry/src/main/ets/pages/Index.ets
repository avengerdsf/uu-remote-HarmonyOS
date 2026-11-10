import { tr } from '../model/I18n';
import { Router } from '../model/Router';
import { ServiceHub } from '../services/ServiceHub';
import { ImmersiveBackdrop } from '../components/ImmersiveBackdrop';
import { LoginPage } from './LoginPage';
import { AppShell } from '../components/AppShell';
import { SessionPage } from './SessionPage';
import { FilesPage } from './FilesPage';
import { TerminalPage } from './TerminalPage';
import { PortMapPage } from './PortMapPage';
import { HostPage } from './HostPage';

@Entry
@Component
struct Index {
  @StorageLink('route') route: string = 'devices';
  @StorageLink('routeVersion') routeVersion: number = 0;
  @StorageLink('sessionBackRequested') sessionBackRequested: number = 0;

  onBackPress(): boolean {
    if (this.route === 'session') {
      this.sessionBackRequested += 1;
      AppStorage.setOrCreate('sessionBackRequested', this.sessionBackRequested);
      return true;
    }
    if (Router.depth() > 1) {
      Router.back();
      return true;
    }
    return false;
  }

  build() {
    Stack() {
      if (!ServiceHub.isReady()) {
        Stack({ alignContent: Alignment.Center }) {
          ImmersiveBackdrop()
          Column({ space: 16 }) {
            if (ServiceHub.hasError()) {
              Text(ServiceHub.error())
                .fontSize(16)
                .fontColor($r('app.color.error_text'))
                .textAlign(TextAlign.Center)
            } else {
              LoadingProgress()
                .width(48)
                .height(48)
                .color($r('app.color.primary'))
              Text(tr('正在启动…'))
                .fontSize(16)
                .fontColor($r('app.color.primary_text'))
            }
          }
          .constraintSize({ maxWidth: 420 })
          .padding(32)
          .backgroundColor($r('app.color.glass_tint'))
          .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
          .border({ width: 1, color: $r('app.color.glass_stroke') })
          .borderRadius($r('sys.float.corner_radius_level8'))
          .shadow({
            radius: 28,
            color: $r('app.color.glass_shadow'),
            offsetX: 0,
            offsetY: 10
          })
          .alignItems(HorizontalAlign.Center)
          .margin(24)
        }
        .width('100%')
        .height('100%')
      } else if (this.route === 'login') {
        LoginPage()
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.Friction }))
      } else if (this.route === 'session') {
        SessionPage()
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.Friction }))
      } else if (this.route === 'files') {
        FilesPage()
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.Friction }))
      } else if (this.route === 'terminal') {
        TerminalPage()
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.Friction }))
      } else if (this.route === 'portmap') {
        PortMapPage()
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.Friction }))
      } else if (this.route === 'host') {
        HostPage()
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.Friction }))
      } else {
        AppShell({ active: this.route })
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.Friction }))
      }
    }
    .width('100%')
    .height('100%')
  }
}
