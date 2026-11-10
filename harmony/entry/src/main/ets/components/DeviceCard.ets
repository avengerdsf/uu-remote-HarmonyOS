import { tr } from '../model/I18n';
import { DeviceInfo } from '../model/Models';
import { Metrics } from '../model/Tokens';
import { IconView } from './IconView';
import { UiProbe } from '../testkit/UiProbe';
import { floatingFeedback } from '../theme/FloatingMaterial';

@Component
export struct DeviceCard {
  @Prop device: DeviceInfo = { id: '', name: '', platform: '', online: false, statusText: '', capabilities: [], connectLabel: tr('连接') };
  @Prop cardWidth: number = 328;
  @Prop wakePending: boolean = false;
  @StorageProp('fontScale') fontScale: number = 1;
  onConnect: (deviceId: string) => void = () => {};
  onWake: (deviceId: string) => void = () => {};
  onTakeover: (device: DeviceInfo) => void = () => {};
  onMore: (device: DeviceInfo) => void = () => {};
  onTool: (device: DeviceInfo, route: string) => void = () => {};
  onRemove: (device: DeviceInfo) => void = () => {};

  private deviceIcon(): string {
    switch (this.device.platform.toLowerCase()) {
      case 'android':
      case 'ios':
      case '移动设备':
      case 'mobile device':
        return 'device_phone';
      case '电视':
      case 'tv':
        return 'device_tv';
      default:
        return 'devices';
    }
  }

  private canWake(): boolean {
    return !this.device.online && this.device.capabilities.includes('wake');
  }

  @Builder
  actions() {
    Menu() {
      MenuItem({ content: tr('设备信息') }).onClick(() => { this.onMore(this.device); })
      if (this.device.capabilities.includes('files')) {
        MenuItemGroup({ header: tr('远程工具') }) {
          MenuItem({ content: tr('文件管理') }).enabled(this.device.online)
            .onClick(() => { this.onTool(this.device, 'files'); })
          MenuItem({ content: tr('终端') }).enabled(this.device.online)
            .onClick(() => { this.onTool(this.device, 'terminal'); })
          MenuItem({ content: tr('端口映射') }).enabled(this.device.online)
            .onClick(() => { this.onTool(this.device, 'portmap'); })
        }
      }
      if (this.device.capabilities.includes('desktop')) {
        MenuItem({ content: this.device.shared === true ? tr('移除共享设备') : tr('解绑设备') })
          .contentFontColor($r('app.color.error_text'))
          .onClick(() => { this.onRemove(this.device); })
      }
    }
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        IconView({ iconKey: this.deviceIcon(), sizeVp: 32, allowImageDrag: false,
          imageId: 'device.' + this.device.id + '.icon' })
        Column({ space: 4 }) {
          Text(this.device.name).fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary')).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(this.device.platform).fontSize(14).fontColor($r('sys.color.font_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          IconView({ iconKey: 'more', sizeVp: 24, allowImageDrag: false })
        }
          .width(48).height(48).backgroundColor(Color.Transparent).attributeModifier(floatingFeedback)
          .id('device.' + this.device.id + '.more').accessibilityText(tr('更多操作'))
          .bindMenu(this.actions)
      }.width('100%')
      Text(this.device.statusText).fontSize(14)
        .fontColor(this.device.online ? $r('app.color.success_text') : $r('sys.color.font_secondary'))
        .id('device.' + this.device.id + '.status')
        .width('100%')
      Button(this.canWake() ? tr('远程开机') : this.device.connectLabel, { type: ButtonType.Capsule })
        .width('100%').constraintSize({ minHeight: Metrics.buttonHeight(this.fontScale) })
        .fontSize(16).enabled(this.canWake() ? !this.wakePending : this.device.online && this.device.capabilities.includes('desktop'))
        .id('device.' + this.device.id + '.connect')
        .onClick(() => {
          if (this.canWake()) { this.onWake(this.device.id); }
          else if (this.device.busy === true || this.device.controlled === true) { this.onTakeover(this.device); }
          else { this.onConnect(this.device.id); }
        })
    }
    .width(this.cardWidth).padding(16).alignItems(HorizontalAlign.Start)
    .backgroundColor($r('sys.color.comp_background_secondary')).borderRadius($r('sys.float.corner_radius_level8'))
    .hoverEffect(HoverEffect.Highlight)
    .bindContextMenu(this.actions, ResponseType.RightClick)
    .bindContextMenu(this.actions, ResponseType.LongPress)
    .id('device.' + this.device.id + '.card')
    .onAreaChange((oldValue: Area, newValue: Area) => {
      UiProbe.record('device.' + this.device.id + '.card', newValue, this.device.name, this.device.online);
    })
  }
}
