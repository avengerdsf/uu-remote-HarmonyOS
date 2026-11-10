import { tr } from '../model/I18n';
import { BlurStrategy, HdsNavigation, HdsNavigationTitleMode, HdsNavigationMenuItemOptions, DividerShowType, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { Router } from '../model/Router';
import { Metrics } from '../model/Tokens';
import { iconResource } from '../model/Icons';
import { ImmersiveBackdrop } from './ImmersiveBackdrop';
import { materialLevel } from '../theme/MaterialPreference';
import { floatingControl, sessionTitleFloatingControl } from '../theme/FloatingMaterial';

@Component
export struct ToolPageShell {
  @StorageProp('hdsMaterialLevel') materialLevel: hdsMaterial.MaterialLevel = materialLevel();
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop menus: HdsNavigationMenuItemOptions[] = [];
  @BuilderParam content: () => void;
  @Prop actionLabel: string = '';
  @Prop actionEnabled: boolean = true;
  @Prop actionId: string = 'tool.action';
  @Prop darkIcons: boolean = false;
  @Prop alwaysBlur: boolean = false;
  @StorageProp('isDark') isDark: boolean = false;
  scroller: Scroller | null = null;
  onAction: () => void = () => {};
  onBack: () => void = () => { Router.back(); };

  @Builder
  titleContent() {
    Column() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle }) {
        Image(iconResource('back', this.darkIcons || this.isDark, false)).width(24).height(24).objectFit(ImageFit.Contain)
          .draggable(false).accessibilityLevel('no')
      }
        .width(48).height(48).attributeModifier(this.darkIcons ? sessionTitleFloatingControl : floatingControl)
        .id('tool.back').accessibilityText(tr('返回')).onClick(this.onBack)
      Column({ space: 2 }) {
        Text(this.title).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary'))
          .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).id('tool.title')
        if (this.subtitle.length > 0) {
          Text(this.subtitle).fontSize(12).fontColor($r('sys.color.font_secondary'))
            .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).id('tool.subtitle')
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.actionLabel.length > 0) {
        Button(this.actionLabel, { type: ButtonType.Capsule }).height(48).padding({ left: 16, right: 16 })
          .fontSize(14).attributeModifier(this.darkIcons ? sessionTitleFloatingControl : floatingControl).fontColor($r('sys.color.font_primary'))
          .enabled(this.actionEnabled).id(this.actionId).onClick(this.onAction)
      }
      ForEach(this.menus, (item: HdsNavigationMenuItemOptions) => {
        Button({ type: ButtonType.Circle }) {
          Image(item.content?.icon as Resource).width(24).height(24).objectFit(ImageFit.Contain)
            .draggable(false).accessibilityLevel('no')
        }.width(48).height(48).attributeModifier(this.darkIcons ? sessionTitleFloatingControl : floatingControl)
          .id(item.content?.componentId ?? '').accessibilityText((item.content?.label ?? '') as string)
          .enabled(item.content?.isEnabled !== false).onClick(() => { item.content?.action?.(); })
      }, (item: HdsNavigationMenuItemOptions) => item.content?.componentId ?? '')
    }.width('100%').height(Metrics.navigationTitleHeight).padding({ left: 16, right: 16 }).id('tool.header.controls')
    }.width('100%').padding({ top: Metrics.navigationTopInset })
  }

  build() {
    Stack() {
      ImmersiveBackdrop({ session: this.darkIcons })
      HdsNavigation() { this.content() }
        .titleBar({
          enableComponentSafeArea: true,
          content: {
            stackBuilder: () => this.titleContent(),
            divider: { showType: DividerShowType.OFF }
          },
          style: {
            blurStrategy: BlurStrategy.ENABLE,
            scrollEffectOpts: { enableScrollEffect: !this.alwaysBlur, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
            originalStyle: { backgroundStyle: { backgroundColor: Color.Transparent, blurRadius: 12 } },
            systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: this.materialLevel
          } }
        })
        .titleMode(HdsNavigationTitleMode.MINI)
        .bindToScrollable(this.scroller === null ? [] : [this.scroller])
        .hideBackButton(true)
        .mode(NavigationMode.Stack)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
        .width('100%').height('100%')
    }
    .width('100%').height('100%').id('tool.page.shell')
  }
}
