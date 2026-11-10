import { tr } from '../model/I18n';
import { SessionSnapshot } from '../model/Models';
import { Metrics, Tokens } from '../model/Tokens';
import { Router } from '../model/Router';
import { ServiceHub } from '../services/ServiceHub';
import { SessionService } from '../services/SessionService';
import { UiProbe } from '../testkit/UiProbe';
import { edgeScrollBar } from '../components/EdgeScrollBar';

@Component
export struct AssistancePage {
  @State connectId: string = '';
  @State verifyCode: string = '';
  @State submitting: boolean = false;
  @State error: string = '';
  @StorageProp('widthVp') widthVp: number = 360;
  @StorageProp('fontScale') fontScale: number = 1;
  scroller: Scroller = new Scroller();
  private service: SessionService | null = null;
  private unsubscribe: (() => void) | null = null;

  aboutToAppear(): void {
    if (!ServiceHub.isReady()) {
      return;
    }
    this.service = ServiceHub.service();
    this.unsubscribe = this.service.onSession((snapshot: SessionSnapshot) => {
      if (this.submitting && snapshot.phase !== 'connecting' && snapshot.error !== null) {
        this.submitting = false;
        this.error = snapshot.error;
      }
    });
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== null) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
  }

  private isValid(): boolean {
    const id = this.connectId.trim();
    const code = this.verifyCode.trim();
    if (id.length === 0 || code.length === 0) {
      return false;
    }
    return !/[\u0000-\u001F\u007F]/.test(id + code);
  }

  private async submit(): Promise<void> {
    if (this.submitting) {
      return;
    }
    if (!this.isValid()) {
      this.error = tr('请输入连接 ID 和验证码，不能包含控制字符');
      return;
    }
    this.error = '';
    this.submitting = true;
    if (this.service !== null) {
      await this.service.joinShare(this.connectId.trim(), this.verifyCode.trim());
      Router.push('session');
    }
    this.submitting = false;
  }

  build() {
    Stack({ alignContent: Alignment.End }) {
      
      Scroll(this.scroller) {
        Row() {
        Column({ space: 16 }) {
          Text(tr('输入对方设备上的连接 ID 和验证码，经对方确认后建立会话。'))
            .fontSize(14)
            .fontColor($r('app.color.secondary_text'))
            .width('100%')

          Column({ space: 8 }) {
            Text(tr('连接 ID'))
              .fontSize(14)
              .fontColor($r('app.color.primary_text'))
              .width('100%')
            TextInput({ text: this.connectId, placeholder: tr('请输入连接 ID') })
              .width('100%')
              .height(48)
              .borderRadius(24)
              .fontSize(16)
              .fontColor($r('app.color.primary_text'))
              .backgroundColor($r('sys.color.comp_background_secondary'))
              .id('assist.connectId')
              .onChange((value: string) => {
                this.connectId = value;
              })
              .onAreaChange((oldValue: Area, newValue: Area) => {
                UiProbe.record('assist.connectId', newValue);
              })
          }
          .width('100%')

          Column({ space: 8 }) {
            Text(tr('验证码'))
              .fontSize(14)
              .fontColor($r('app.color.primary_text'))
              .width('100%')
            TextInput({ text: this.verifyCode, placeholder: tr('请输入验证码') })
                .width('100%')
                .height(48)
                .borderRadius(24)
                .fontSize(16)
                .fontColor($r('app.color.primary_text'))
                .type(InputType.Password)
                .showPasswordIcon(true)
                .backgroundColor($r('sys.color.comp_background_secondary'))
                .id('assist.verifyCode')
                .onChange((value: string) => {
                  this.verifyCode = value;
                })
                .onAreaChange((oldValue: Area, newValue: Area) => {
                  UiProbe.record('assist.verifyCode', newValue);
                })
          }
          .width('100%')

          if (this.error.length > 0) {
            Text(this.error)
              .fontSize(14)
              .fontColor($r('app.color.error_text'))
              .width('100%')
              .id('assist.error')
          }

          Button(this.submitting ? tr('正在连接…') : tr('连接'), { type: ButtonType.Capsule })
            .width('100%')
            .constraintSize({ minHeight: Metrics.buttonHeight(this.fontScale) })
            .fontSize(16)
            .enabled(this.isValid() && !this.submitting)
            .id('assist.connect')
            .onClick(() => {
              this.submit();
            })
            .onAreaChange((oldValue: Area, newValue: Area) => {
              UiProbe.record('assist.connect', newValue, this.submitting ? tr('正在连接…') : tr('连接'),
                this.isValid() && !this.submitting);
            })
        }
        .width('100%')
        .constraintSize({ maxWidth: Tokens.formMax })
        .padding({ left: Metrics.padding(Metrics.mode(this.widthVp)), right: Metrics.padding(Metrics.mode(this.widthVp)), top: 16, bottom: 112 })
        .id('assist.form')
        }.width('100%').justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Top)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off).id('assist.scroll')
      .align(Alignment.Top)
      edgeScrollBar(this.scroller, 'assist.scroll')
    }
    .width('100%')
    .height('100%')
    .id('assist.page')
  }
}
