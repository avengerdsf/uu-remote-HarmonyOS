@Component
export struct ImmersiveBackdrop {
  @Prop session: boolean = false;
  build() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(this.session ? $r('app.color.session_background') : $r('sys.color.ohos_id_color_background'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .accessibilityLevel('no')
      .hitTestBehavior(HitTestMode.None)
  }
}
