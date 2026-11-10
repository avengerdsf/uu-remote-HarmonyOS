import { Tokens } from '../model/Tokens';

/**
 * Frosted light-sense panel: translucent tint, background blur, a hairline
 * stroke and a top highlight. `strong` is used for dialogs and menus.
 */
@Component
export struct GlassPanel {
  @Prop radius: Resource = Tokens.glassRadius;
  @Prop contentPadding: number = 0;
  @Prop strong: boolean = false;
  @BuilderParam content: () => void;

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column() {
        this.content()
      }
      .width('100%')
      .padding(this.contentPadding)
      .backgroundColor(this.strong ? $r('app.color.glass_strong') : $r('app.color.glass_tint'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
      .borderRadius(this.radius)
      .border({ width: 1, color: $r('app.color.glass_stroke') })
      .shadow({
        radius: Tokens.shadowRadius,
        color: $r('app.color.glass_shadow'),
        offsetX: 0,
        offsetY: 10
      })

      Row()
        .width('72%')
        .height(1)
        .borderRadius(1)
        .linearGradient({
          angle: 90,
          colors: [
            ['#00FFFFFF', 0.0],
            [$r('app.color.glass_highlight'), 0.5],
            ['#00FFFFFF', 1.0]
          ]
        })
        .margin({ top: 1 })
        .accessibilityLevel('no')
    }
    .width('100%')
  }
}
