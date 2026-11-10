import { tr } from '../model/I18n';
@Component
export struct ConfirmDialog {
  @Prop @Watch('visibilityChanged') visible: boolean = false;
  @Prop title: string = '';
  @Prop body: string = '';
  @Prop confirmText: string = tr('确定');
  @Prop cancelText: string = tr('取消');
  @Prop destructive: boolean = false;
  onConfirm: () => void = () => {};
  onCancel: () => void = () => {};
  private opened: boolean = false;

  aboutToAppear(): void { this.visibilityChanged(); }

  private visibilityChanged(): void {
    if (!this.visible || this.opened) { return; }
    this.opened = true;
    this.getUIContext().showAlertDialog({
      title: this.title,
      message: this.body,
      autoCancel: true,
      cancel: () => { this.opened = false; this.onCancel(); },
      primaryButton: { value: this.cancelText, action: () => {
        this.opened = false;
        this.onCancel();
      } },
      secondaryButton: { value: this.confirmText,
        fontColor: this.destructive ? $r('sys.color.ohos_id_color_warning') : $r('sys.color.ohos_id_color_emphasize'),
        action: () => { this.opened = false; this.onConfirm(); }
      }
    });
  }

  build() { Column().width(0).height(0).accessibilityLevel('no') }
}
