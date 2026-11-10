import { IconView } from './IconView';

@Component
export struct SettingsRow {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop showChevron: boolean = true;
  @Prop rowEnabled: boolean = true;
  @Prop rowId: string = '';
  onSelect: () => void = () => {};

  build() {
    Row({ space: 12 }) {
      Text(this.label)
        .fontSize(16)
        .fontColor(this.rowEnabled ? $r('app.color.primary_text') : $r('app.color.secondary_text'))
        .layoutWeight(1)
        .maxLines(2)
      Text(this.value)
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
        .maxLines(1)
      if (this.showChevron) {
        IconView({ iconKey: 'chevron', selected: false, sizeVp: 24, allowImageDrag: false })
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.glass_input'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
    .border({ width: 1, color: $r('app.color.glass_stroke') })
    .borderRadius($r('sys.float.corner_radius_level8'))
    .enabled(this.rowEnabled)
    .id(this.rowId)
    .onClick(() => {
      if (this.rowEnabled) {
        this.onSelect();
      }
    })
  }
}
