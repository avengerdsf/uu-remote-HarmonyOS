@Component
export struct StatusView {
  @Prop text: string = '';
  @Prop detail: string = '';
  @Prop loading: boolean = false;
  @Prop actionLabel: string = '';
  onAction: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      if (this.loading) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(96)
            .height(96)
            .borderRadius(48)
            .radialGradient({
              center: ['50%', '50%'],
              radius: '50%',
              colors: [[$r('app.color.glow_primary'), 0.0], ['#00FFFFFF', 1.0]]
            })
            .opacity(0.7)
            .accessibilityLevel('no')
          LoadingProgress()
            .width(48)
            .height(48)
            .color($r('app.color.primary'))
        }
        .width(96)
        .height(96)
      }
      Text(this.text)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .textAlign(TextAlign.Center)
      if (this.detail.length > 0) {
        Text(this.detail)
          .fontSize(14)
          .fontColor($r('app.color.secondary_text'))
          .textAlign(TextAlign.Center)
          .maxLines(3)
      }
      if (this.actionLabel.length > 0) {
        Button(this.actionLabel, { type: ButtonType.Capsule })
          .height(48)
          .fontSize(16)
          .fontColor($r('app.color.on_primary'))
          .backgroundColor($r('app.color.primary'))
          .padding({ left: 24, right: 24 })
          .shadow({
            radius: 18,
            color: $r('app.color.glow_primary'),
            offsetX: 0,
            offsetY: 6
          })
          .onClick(() => {
            this.onAction();
          })
      }
    }
    .width('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
