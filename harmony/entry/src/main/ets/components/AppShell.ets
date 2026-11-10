import { tr } from '../model/I18n';
import { BlurStrategy, HdsNavigation, HdsNavigationTitleMode,
  HdsTabs, HdsTabsController, DividerShowType, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { Router } from '../model/Router';
import { iconResource } from '../model/Icons';
import { UiProbe } from '../testkit/UiProbe';
import { ImmersiveBackdrop } from './ImmersiveBackdrop';
import { DevicesPage } from '../pages/DevicesPage';
import { AssistancePage } from '../pages/AssistancePage';
import { SettingsPage } from '../pages/SettingsPage';
import { ServiceHub } from '../services/ServiceHub';
import { Metrics } from '../model/Tokens';
import { floatingControl, floatingSearch } from '../theme/FloatingMaterial';
import { materialLevel } from '../theme/MaterialPreference';

const ROUTES: string[] = ['devices', 'assist', 'settings'];
type SearchPresentation = 'top' | 'collapsed' | 'inline';

@Component
export struct AppShell {
  @Prop @Watch('onActiveChanged') active: string = 'devices';
  @State currentTabIndex: number = 0;
  @StorageProp('isDark') isDark: boolean = false;
  @StorageProp('widthVp') widthVp: number = 360;
  @StorageProp('fontScale') fontScale: number = 1;
  @StorageProp('navigationIndicatorBottomVp') navigationIndicatorBottomVp: number = 0;
  @State query: string = '';
  @State searchPresentation: SearchPresentation = 'top';
  @State inlineWidth: number = 40;
  @State inlineRight: number = 0;
  @State inlineTop: number = 0;
  @State inlineHeight: number = 40;
  private searchController: SearchController = new SearchController();
  private searchEditing: boolean = false;
  private searchClosing: boolean = false;
  private searchScrollClosing: boolean = false;
  private focusTimer: number = -1;
  private layoutTimer: number = -1;
  private inlineMenuGap: number = 0;
  private deviceScroller: Scroller = new Scroller();
  private assistScroller: Scroller = new Scroller();
  private settingsScroller: Scroller = new Scroller();
  private tabsController: HdsTabsController = new HdsTabsController();
  @StorageProp('hdsMaterialLevel') materialLevel: hdsMaterial.MaterialLevel = materialLevel();

  aboutToAppear(): void {
    this.currentTabIndex = Math.max(0, ROUTES.indexOf(this.active));
  }

  aboutToDisappear(): void { clearTimeout(this.focusTimer); clearTimeout(this.layoutTimer); }

  private onActiveChanged(): void {
    const index = Math.max(0, ROUTES.indexOf(this.active));
    if (index !== this.currentTabIndex) {
      this.getUIContext().getFocusController().clearFocus();
      this.currentTabIndex = index;
      this.tabsController.changeIndex(index);
    }
  }

  private bottomTab(icon: string, title: string): BottomTabBarStyle {
    return new BottomTabBarStyle($rawfile('tab-icons/' + icon + (this.isDark ? '_dark.svg' : '_light.svg')), tr(title))
      .layoutMode(LayoutMode.VERTICAL).verticalAlign(VerticalAlign.Center)
      .padding({ left: 4, right: 4, top: 0, bottom: 0 })
      .labelStyle({ font: { size: 12, weight: FontWeight.Bold }, maxLines: 1,
        selectedColor: $r('app.color.primary'), unselectedColor: $r('app.color.secondary_text') })
      .iconStyle({ selectedColor: $r('app.color.primary'), unselectedColor: $r('app.color.secondary_text') });
  }

  private showSearch(): void {
    const ui = this.getUIContext();
    if (this.deviceScroller.currentOffset().yOffset <= 0) {
      clearTimeout(this.focusTimer);
      ui.animateTo({ duration: 260, curve: Curve.Friction, onFinish: () => {
        if (this.searchPresentation === 'top') { ui.getFocusController().requestFocus('devices.search'); }
      } }, () => { this.searchPresentation = 'top'; });
      return;
    }
    const anchor = ui.getComponentUtils().getRectangleById('devices.search.open');
    const shell = ui.getComponentUtils().getRectangleById('app.shell');
    const refresh = ui.getComponentUtils().getRectangleById('devices.refresh');
    this.inlineMenuGap = ui.px2vp(refresh.windowOffset.x - anchor.windowOffset.x - anchor.size.width);
    this.inlineRight = ui.px2vp(anchor.windowOffset.x + anchor.size.width - shell.windowOffset.x);
    this.inlineTop = ui.px2vp(anchor.windowOffset.y - shell.windowOffset.y);
    this.inlineHeight = ui.px2vp(anchor.size.height);
    this.inlineWidth = this.inlineHeight;
    this.searchPresentation = 'inline';
    clearTimeout(this.focusTimer);
    this.focusTimer = setTimeout(() => {
      ui.animateTo({ duration: 260, curve: Curve.Friction,
        onFinish: () => {
          if (this.searchPresentation === 'inline' && !this.searchClosing) { ui.getFocusController().requestFocus('devices.search'); }
        } }, () => {
        this.inlineWidth = this.inlineRight - Metrics.padding(Metrics.mode(this.widthVp));
      });
    }, 16);
  }

  private onDeviceScroll(offset: number, atStart: boolean, state: ScrollState): void {
    if (this.searchClosing) {
      if (state !== ScrollState.Idle) { this.searchScrollClosing = true; }
      return;
    }
    if (this.searchPresentation === 'inline' && state !== ScrollState.Idle) {
      this.collapseSearch(true);
      return;
    }
    if (this.searchEditing) { return; }
    if (atStart && this.searchPresentation !== 'top') {
      this.getUIContext().animateTo({ duration: 260, curve: Curve.Friction }, () => { this.searchPresentation = 'top'; });
    } else if (offset > 8 && state !== ScrollState.Idle && this.searchPresentation === 'top') {
      this.getUIContext().animateTo({ duration: 260, curve: Curve.Friction }, () => { this.searchPresentation = 'collapsed'; });
    }
  }

  private collapseSearch(scrolling: boolean = false): void {
    if (this.searchPresentation !== 'inline' || this.searchClosing) { return; }
    this.searchClosing = true;
    this.searchScrollClosing = scrolling;
    clearTimeout(this.focusTimer);
    this.searchController.stopEditing();
    this.getUIContext().animateTo({ duration: 260, curve: Curve.Friction, onFinish: () => {
      if (this.searchPresentation === 'inline') {
        this.searchPresentation = this.searchScrollClosing && this.deviceScroller.currentOffset().yOffset <= 0 ? 'top' : 'collapsed';
      }
      this.searchClosing = false;
    } }, () => { this.inlineWidth = this.inlineHeight; });
  }

  private dismissSearchOutside(x: number, y: number): void {
    if (this.searchPresentation === 'inline' &&
      (x < this.inlineRight - this.inlineWidth || x > this.inlineRight || y < this.inlineTop || y > this.inlineTop + this.inlineHeight)) {
      this.collapseSearch();
    }
  }

  @Builder
  searchField(inline: boolean) {
    Search({ value: this.query, placeholder: tr('搜索设备'), controller: this.searchController })
      .width('100%').height(inline ? this.inlineHeight : Metrics.searchHeight(this.fontScale))
      .borderRadius((inline ? this.inlineHeight : Metrics.searchHeight(this.fontScale)) / 2)
      .attributeModifier(floatingSearch)
      .margin(0)
      .textFont({ size: 16 }).id('devices.search')
      .geometryTransition('devices.search.field')
      .onChange((value: string) => { this.query = value; })
      .onEditChange((editing: boolean) => { this.searchEditing = editing; })
      .onSubmit(() => { this.searchController.stopEditing(); })
  }

  @Builder
  deviceSearch() {
    if (this.active === 'devices' && this.searchPresentation === 'top') {
      Row() {
      Column() {
        this.searchField(false)
      }
      .width(Metrics.bodyWidth(this.widthVp, Metrics.mode(this.widthVp)))
      .padding({ top: 8, bottom: 8 })
      .transition(TransitionEffect.OPACITY)
      }.width('100%').justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  titleContent() {
    Column() {
    Row({ space: 8 }) {
      Text(this.active === 'devices' ? (this.searchPresentation === 'inline' ? '' : tr('设备')) : this.active === 'assist' ? tr('远程协助') : tr('设置'))
        .fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1).id('app.title')
      if (this.active === 'devices') {
        if (this.searchPresentation === 'collapsed') {
          Button({ type: ButtonType.Circle }) {
            Image(iconResource('search', this.isDark, false)).width(24).height(24)
              .objectFit(ImageFit.Contain).draggable(false).accessibilityLevel('no')
          }
            .width(48).height(48).attributeModifier(floatingControl)
            .id('devices.search.open').accessibilityText(tr('搜索设备')).onClick(() => { this.showSearch(); })
        } else if (this.searchPresentation === 'inline') {
          Blank().width(48).height(48)
        }
        Button({ type: ButtonType.Circle }) {
          Image(iconResource('refresh', this.isDark, false)).width(24).height(24)
            .objectFit(ImageFit.Contain).draggable(false).accessibilityLevel('no')
        }
          .width(48).height(48).attributeModifier(floatingControl)
          .id('devices.refresh').accessibilityText(tr('刷新设备列表'))
          .onClick(() => { if (ServiceHub.isReady()) { ServiceHub.service().listDevices(); } })
      }
    }.width('100%').height(Metrics.navigationTitleHeight).padding({ left: 16, right: 16 }).id('app.header.controls')
    }.width('100%').padding({ top: Metrics.navigationTopInset })
  }

  build() {
    // Recreated after a session, the home shell must resolve resources in the app's own color mode.
    WithTheme({ colorMode: this.isDark ? ThemeColorMode.DARK : ThemeColorMode.LIGHT }) {
    Stack() {
      ImmersiveBackdrop()
      HdsNavigation() {
        HdsTabs({ index: this.currentTabIndex, controller: this.tabsController }) {
          TabContent() {
            DevicesPage({ query: $query, scroller: this.deviceScroller,
              onScroll: (offset: number, atStart: boolean, state: ScrollState) => { this.onDeviceScroll(offset, atStart, state); } })
          }.clip(false)
            .tabBar(this.bottomTab('devices', '设备'))
            .id('app.nav.devices')
          TabContent() { AssistancePage({ scroller: this.assistScroller }) }
            .tabBar(this.bottomTab('assist', '远程协助'))
            .id('app.nav.assist')
          TabContent() { SettingsPage({ scroller: this.settingsScroller }) }
            .tabBar(this.bottomTab('settings', '设置'))
            .id('app.nav.settings')
        }
        .barPosition(BarPosition.End)
        .barOverlap(true)
        .barHeight(56)
        .vertical(false)
        .scrollable(false)
        .animationDuration(260)
        .barFloatingStyle({
          barWidth: { smallWidth: 248, mediumWidth: 248, largeWidth: 248 },
          barBottomMargin: Math.max(0, 16 - this.navigationIndicatorBottomVp),
          adaptToHandedness: true,
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: this.materialLevel
          }
        })
        .onChange((index: number) => {
          if (index >= 0 && index < ROUTES.length) { this.currentTabIndex = index; }
          if (index >= 0 && index < ROUTES.length && ROUTES[index] !== this.active) {
            clearTimeout(this.focusTimer);
            this.getUIContext().getFocusController().clearFocus();
            this.searchPresentation = 'top';
            Router.replace(ROUTES[index]);
          }
        })
        .width('100%')
        .height('100%')
        .clip(false)
        .id('app.bottomNav')
      }
      .titleBar({
        enableComponentSafeArea: true,
        content: {
          stackBuilder: () => this.titleContent(),
          divider: { showType: DividerShowType.OFF },
          bottomBuilder: {
            builder: () => this.deviceSearch(),
            height: this.active === 'devices' && this.searchPresentation === 'top' ? Metrics.searchHeight(this.fontScale) + 16 : 0
          }
        },
        style: {
          blurStrategy: BlurStrategy.ENABLE,
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
          originalStyle: { backgroundStyle: { blurRadius: 12 } },
          systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: this.materialLevel
        } }
      })
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideTitleBar(this.active === 'settings')
      .bindToScrollable([this.active === 'devices' ? this.deviceScroller : this.active === 'assist' ? this.assistScroller : this.settingsScroller])
      .hideBackButton(true)
      .mode(NavigationMode.Stack)
      // Keep the title inset inside its builder so the HDS blur can reach the status bar.
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      .width('100%')
      .height('100%')
      if (this.active === 'devices' && this.searchPresentation === 'inline') {
        Column() { this.searchField(true) }
          .width(this.inlineWidth).height(this.inlineHeight)
          .position({ x: this.inlineRight - this.inlineWidth, y: this.inlineTop })
          .transition(TransitionEffect.OPACITY)
          .id('devices.search.inline')
      }
    }
    .width('100%')
    .height('100%')
    .id('app.shell')
    .onTouchIntercept((event: TouchEvent) => {
      if (event.type === TouchType.Down && event.touches.length > 0) {
        this.dismissSearchOutside(event.touches[0].x, event.touches[0].y);
      }
      return HitTestMode.Default;
    })
    .onMouse((event: MouseEvent) => {
      if (event.action === MouseAction.Press) { this.dismissSearchOutside(event.x, event.y); }
    })
    .onAreaChange((oldValue: Area, newValue: Area) => {
      AppStorage.setOrCreate('widthVp', Number.parseFloat('' + newValue.width));
      AppStorage.setOrCreate('heightVp', Number.parseFloat('' + newValue.height));
      UiProbe.record('app.shell', newValue);
      if (this.searchPresentation === 'inline' && oldValue.width !== newValue.width) {
        clearTimeout(this.layoutTimer);
        this.layoutTimer = setTimeout(() => {
          if (this.searchPresentation !== 'inline') { return; }
          const ui = this.getUIContext();
          const refresh = ui.getComponentUtils().getRectangleById('devices.refresh');
          const shell = ui.getComponentUtils().getRectangleById('app.shell');
          this.inlineRight = ui.px2vp(refresh.windowOffset.x - shell.windowOffset.x) - this.inlineMenuGap;
          this.inlineTop = ui.px2vp(refresh.windowOffset.y - shell.windowOffset.y);
          this.inlineHeight = ui.px2vp(refresh.size.height);
          this.inlineWidth = this.inlineRight - Metrics.padding(Metrics.mode(this.widthVp));
        }, 16);
      }
    })
    }
  }
}
