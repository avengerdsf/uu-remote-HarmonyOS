import { tr } from '../model/I18n';
import { DeviceInfo, DeviceListPhase, DevicesSnapshot } from '../model/Models';
import { Metrics } from '../model/Tokens';
import { Router } from '../model/Router';
import { ServiceHub } from '../services/ServiceHub';
import { SessionService } from '../services/SessionService';
import { DeviceCard } from '../components/DeviceCard';
import { StatusView } from '../components/StatusView';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { UiProbe } from '../testkit/UiProbe';
import { edgeScrollBar } from '../components/EdgeScrollBar';

const DEVICE_REFRESH_INTERVAL_MS: number = 15000;

@Component
export struct DevicesPage {
  @State devices: DevicesSnapshot = {
    phase: DeviceListPhase.Loading,
    devices: [],
    error: null,
    generation: 0
  };
  @Link query: string;
  @State removeVisible: boolean = false;
  @State operationError: string = '';
  @State wakePending: boolean = false;
  @State infoDevice: DeviceInfo | null = null;
  @StorageProp('widthVp') widthVp: number = 360;
  @StorageProp('fontScale') fontScale: number = 1;
  @StorageProp('route') @Watch('updateDeviceRefresh') route: string = 'devices';
  @StorageProp('deviceListForeground') @Watch('updateDeviceRefresh') foreground: boolean = false;
  private service: SessionService | null = null;
  private unsubscribe: (() => void) | null = null;
  private deviceRefreshTimer: number = -1;
  scroller: Scroller = new Scroller();
  onScroll: (offset: number, atStart: boolean, state: ScrollState) => void = () => {};

  aboutToAppear(): void {
    if (!ServiceHub.isReady()) {
      return;
    }
    this.service = ServiceHub.service();
    this.devices = this.service.devicesSnapshot();
    this.unsubscribe = this.service.onDevices((snapshot: DevicesSnapshot) => {
      this.devices = snapshot;
    });
    this.updateDeviceRefresh();
  }

  aboutToDisappear(): void {
    this.service = null;
    this.updateDeviceRefresh();
    if (this.unsubscribe !== null) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
  }

  private updateDeviceRefresh(): void {
    const service = this.service;
    if (!this.foreground || this.route !== 'devices' || service === null) {
      if (this.deviceRefreshTimer >= 0) {
        clearInterval(this.deviceRefreshTimer);
        this.deviceRefreshTimer = -1;
      }
      return;
    }
    if (this.deviceRefreshTimer >= 0) { return; }
    const refresh = (): void => { service.listDevices(true).catch(() => {}); };
    refresh();
    this.deviceRefreshTimer = setInterval(refresh, DEVICE_REFRESH_INTERVAL_MS);
  }

  private async openTool(device: DeviceInfo, route: string): Promise<void> {
    try {
      await this.service?.selectTarget(device.id);
      Router.push(route);
    } catch (error) { this.operationError = tr('无法选择远端设备'); }
  }

  private async removeDevice(): Promise<void> {
    const device = this.infoDevice;
    this.removeVisible = false;
    if (device === null) { return; }
    try { await this.service?.unbindDevice(device.id, device.shared === true); }
    catch (error) { this.operationError = (error as Error).message; }
  }

  private async wakeDevice(deviceId: string): Promise<void> {
    const service = this.service;
    if (service === null || this.wakePending) { return; }
    this.wakePending = true;
    try {
      await service.wakeDevice(deviceId);
      if (this.service === service) {
        this.getUIContext().getPromptAction().showToast({ message: tr('已发送开机请求，等待设备上线。') });
        service.listDevices(true).catch(() => {});
      }
    } catch (error) {
      if (this.service === service) { this.operationError = (error as Error).message; }
    } finally { this.wakePending = false; }
  }

  private showDeviceInfo(device: DeviceInfo): void {
    const buttons: AlertDialogButtonOptions[] = [{ value: tr('关闭'), action: () => {} }];
    if (device.online && device.capabilities.includes('desktop')) {
      buttons.push({ value: tr('连接'), action: () => {
        if (device.busy === true || device.controlled === true) { this.takeOver(device); }
        else { this.service?.connect(device.id); Router.push('session'); }
      } });
    }
    this.getUIContext().showAlertDialog({
      title: device.name,
      message: `${tr('系统')}：${device.platform}\n${tr('状态')}：${device.statusText}\n${tr('设备 ID')}：${device.id}`,
      buttons: buttons
    });
  }

  private takeOver(device: DeviceInfo): void {
    this.getUIContext().showAlertDialog({ title: tr('接管连接'), message: tr('接管将中断此设备上的其他远控连接，是否继续？'),
      primaryButton: { value: tr('取消'), action: () => {} },
      secondaryButton: { value: tr('接管连接'), action: () => {
        this.service?.connect(device.id, true).then(() => { Router.push('session'); })
          .catch((error: Error) => { this.operationError = error.message; });
      } } });
  }

  private mode(): 'compact' | 'medium' | 'expanded' {
    return Metrics.mode(this.widthVp);
  }

  private bodyWidth(): number {
    return Metrics.bodyWidth(this.widthVp, this.mode());
  }

  private columns(): number {
    return Metrics.columns(this.bodyWidth(), this.mode(), this.fontScale);
  }

  private cardWidth(): number {
    return Metrics.cardWidth(this.bodyWidth(), this.columns());
  }

  private filtered(): DeviceInfo[] {
    const text = this.query.trim().toLowerCase();
    if (text.length === 0) {
      return this.devices.devices;
    }
    return this.devices.devices.filter((device: DeviceInfo) => {
      return device.name.toLowerCase().includes(text) ||
        device.platform.toLowerCase().includes(text) ||
        device.id.toLowerCase().includes(text);
    });
  }

  private columnsTemplate(): string {
    const count = this.columns();
    const parts: string[] = [];
    for (let i = 0; i < count; i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  @Builder
  deviceGrid() {
    Stack({ alignContent: Alignment.End }) {
    Grid(this.scroller) {
      ForEach(this.filtered(), (device: DeviceInfo) => {
        GridItem() {
          DeviceCard({
            device: device,
            cardWidth: this.cardWidth(),
            wakePending: this.wakePending,
            onWake: (deviceId: string) => { this.wakeDevice(deviceId); },
            onConnect: (deviceId: string) => {
              this.service?.connect(deviceId);
              Router.push('session');
            },
            onTakeover: (device: DeviceInfo) => { this.takeOver(device); },
            onTool: (device: DeviceInfo, route: string) => {
              this.openTool(device, route);
            },
            onRemove: (device: DeviceInfo) => {
              this.infoDevice = device;
              this.removeVisible = true;
            },
            onMore: (selected: DeviceInfo) => {
              this.showDeviceInfo(selected);
            }
          })
        }
      }, (device: DeviceInfo) => `${device.id}:${device.online}:${device.busy}:${device.controlled}:${device.statusText}:${device.connectLabel}:${device.platform}:${device.name}:${device.capabilities.includes('wake')}`)
    }
    .columnsTemplate(this.columnsTemplate())
    .columnsGap(16)
    .rowsGap(16)
    .width('100%')
    .height('100%')
    .padding({ left: (this.widthVp - this.bodyWidth()) / 2, right: (this.widthVp - this.bodyWidth()) / 2 })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .contentEndOffset(88)
    .cachedCount(2, true)
    .clip(false)
    .id('devices.grid')
    .onDidScroll((offset: number, state: ScrollState) => {
      const position = this.scroller.currentOffset().yOffset;
      this.onScroll(position, position <= 0, state);
    })
    .onAreaChange((oldValue: Area, newValue: Area) => {
      UiProbe.record('devices.grid', newValue);
    })
      edgeScrollBar(this.scroller, 'devices.grid')
    }.width('100%').layoutWeight(1)
  }

  @Builder
  pageBody() {
    Column() {
      if (this.devices.phase === DeviceListPhase.Loading) {
        Column() {
          StatusView({ text: tr('正在加载设备…'), loading: true })
        }
        .width('100%')
        .layoutWeight(1)
        .id('devices.loading')
      } else if (this.devices.phase === DeviceListPhase.Empty) {
        Column() {
          StatusView({
            text: tr('暂无设备'),
            detail: tr('请先在目标电脑上登录 UU 远程，然后刷新。'),
            actionLabel: tr('刷新'),
            onAction: () => {
              this.service?.listDevices();
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .id('devices.empty')
      } else if (this.devices.phase === DeviceListPhase.RefreshFailed && this.devices.devices.length === 0) {
        Column() {
          StatusView({
            text: tr('刷新失败'),
            detail: this.devices.error ?? '',
            actionLabel: tr('重试'),
            onAction: () => {
              this.service?.listDevices();
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .id('devices.error')
      } else {
        if (this.devices.phase === DeviceListPhase.RefreshFailed) {
          Row({ space: 8 }) {
            Text(this.devices.error ?? tr('刷新失败'))
              .fontSize(14)
              .fontColor($r('app.color.error_text'))
              .layoutWeight(1)
            Button(tr('重试'), { type: ButtonType.Capsule })
              .height(48)
              .fontSize(14)
              .fontColor($r('app.color.primary'))
              .backgroundColor(Color.Transparent)
              .id('devices.retry')
              .onClick(() => {
                this.service?.listDevices();
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .backgroundColor($r('app.color.glass_input'))
          .border({ width: 1, color: $r('app.color.glass_stroke') })
          .borderRadius($r('sys.float.corner_radius_level8'))
          .margin({ bottom: 8 })
          .id('devices.refreshError')
        }
        if (this.filtered().length === 0) {
          Column() {
            StatusView({ text: tr('没有匹配的设备'), detail: tr('清除搜索条件后重试。') })
          }
          .width('100%')
          .layoutWeight(1)
        } else {
          this.deviceGrid()
        }
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ top: 16 })
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Stack() {
      
        Column() {
          if (this.operationError.length > 0) {
            Text(this.operationError).fontColor($r('app.color.error_text')).padding(12)
          }
          Column() {
            this.pageBody()
          }
          .layoutWeight(1)
          .width('100%')
          .id('devices.scroll')
        }
        .width('100%')
        .height('100%')
      

      ConfirmDialog({
        visible: this.removeVisible,
        title: tr('移除设备'),
        body: tr('确认从账号移除所选设备？'),
        confirmText: tr('移除'), cancelText: tr('取消'), destructive: true,
        onConfirm: () => { this.removeDevice(); },
        onCancel: () => { this.removeVisible = false; }
      })
    }
    .width('100%')
    .height('100%')
    .id('devices.page')
  }
}
