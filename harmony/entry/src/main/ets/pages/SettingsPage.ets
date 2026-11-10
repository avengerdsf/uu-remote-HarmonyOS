import { tr } from '../model/I18n';
import { Metrics } from '../model/Tokens';
import { BlurStrategy, HdsNavigation, HdsNavDestination, HdsNavigationTitleMode, DividerShowType, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { ComposeListItem, IconType } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ClipboardPolicy, ControlBarPosition, MaterialPreference, SettingsState, ThemePreference, TouchMode, VideoQuality } from '../model/Models';
import { materialLevel } from '../theme/MaterialPreference';
import { ServiceHub } from '../services/ServiceHub';
import { SessionService } from '../services/SessionService';
import { ThemeManager } from '../theme/ThemeManager';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { iconResource } from '../model/Icons';
import { edgeScrollBar } from '../components/EdgeScrollBar';
import { IconView } from '../components/IconView';
import { floatingControl } from '../theme/FloatingMaterial';

// Mobile HDS centers the custom builder in the fixed-height MINI title slot.
const SETTINGS_TITLE_TOP_PADDING: number = deviceInfo.deviceType === '2in1' ?
  Metrics.navigationTopInset : Metrics.navigationTopInset * 2;

interface SettingsGroup {
  id: string;
  title: string;
  icon: string;
}

interface SettingsSelectOptions {
  id: string;
  label: string;
  options: SelectOption[];
  selected: number;
  action: (index: number) => void;
}

const GROUPS: SettingsGroup[] = [
  { id: 'settings.general', title: tr('通用设置'), icon: 'settings' },
  { id: 'settings.video', title: tr('远程画面'), icon: 'quality' },
  { id: 'settings.about', title: tr('关于'), icon: 'more' }
];

@Component
export struct SettingsPage {
  @StorageProp('hdsMaterialLevel') materialLevel: hdsMaterial.MaterialLevel = materialLevel();
  @StorageProp('accountIdSuffix') accountIdSuffix: string = '';
  @StorageProp('remoteTouchMode') touchMode: TouchMode = 'trackpad';
  @State settings: SettingsState = {
    themePreference: 'system',
    materialPreference: 'system',
    defaultVideoProfile: 'auto',
    defaultVideoQuality: 'auto',
    defaultFrameRate: 60,
    trueColor: false,
    touchMode: 'trackpad',
    clipboardPolicy: 'manual',
    keepScreenOn: false,
    autoStartPiP: false,
    smartReachEnabled: true,
    controlBarPosition: 'center'
  };
  @StorageProp('decoderMaxFps') maxFps: number = 60;
  @StorageProp('decoderMaxWidth') maxVideoWidth: number = 1920;
  @StorageProp('decoderChroma444') chroma444: boolean = false;
  @State group: string = 'settings.general';
  @State navigationMode: NavigationMode = NavigationMode.Stack;
  @StorageProp('isDark') isDark: boolean = false;
  private paths: NavPathStack = new NavPathStack();
  @State logoutVisible: boolean = false;
  @StorageProp('widthVp') widthVp: number = 360;
  private service: SessionService | null = null;
  scroller: Scroller = new Scroller();
  private detailScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    if (!ServiceHub.isReady()) {
      return;
    }
    this.service = ServiceHub.service();
    this.settings = this.service.settings();
  }

  private applyTheme(preference: ThemePreference): void {
    this.updateSettings(preference, null, null, null, null, null);
    this.service?.setTheme(preference);
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ThemeManager.apply(context, preference);
  }

  private updateSettings(theme: ThemePreference | null, resolution: string | null,
    quality: string | null, frameRate: number | null, trueColor: boolean | null,
    clipboard: ClipboardPolicy | null): void {
    this.settings = {
      themePreference: theme ?? this.settings.themePreference,
      materialPreference: this.settings.materialPreference,
      defaultVideoProfile: resolution ?? this.settings.defaultVideoProfile,
      defaultVideoQuality: (quality ?? this.settings.defaultVideoQuality) as VideoQuality,
      defaultFrameRate: frameRate ?? this.settings.defaultFrameRate,
      trueColor: trueColor ?? this.settings.trueColor,
      touchMode: this.touchMode,
      clipboardPolicy: clipboard ?? this.settings.clipboardPolicy,
      keepScreenOn: this.settings.keepScreenOn,
      autoStartPiP: this.settings.autoStartPiP,
      smartReachEnabled: this.settings.smartReachEnabled,
      controlBarPosition: this.settings.controlBarPosition
    };
  }

  private resolutionProfiles(): string[] {
    const profiles = ['auto', 'window'].concat((this.maxVideoWidth >= 3840 ? ['2160p60'] : []),
      (this.maxVideoWidth >= 2560 ? ['1440p60'] : []), (this.maxVideoWidth >= 1920 ? ['1080p60'] : []), ['720p30']);
    if (/^\d+x\d+$/.test(this.settings.defaultVideoProfile)) { profiles.push(this.settings.defaultVideoProfile); }
    return profiles;
  }

  private resolutionOptions(): SelectOption[] {
    return this.resolutionProfiles().map((profile: string): SelectOption => {
      if (profile === 'window') { return { value: tr('跟随当前窗口') }; }
      if (profile === '2160p60') { return { value: '4K · 3840×2160' }; }
      if (profile === '1440p60') { return { value: '2K · 2560×1440' }; }
      if (profile === '1080p60') { return { value: '1080p · 1920×1080' }; }
      if (profile === '720p30') { return { value: '720p · 1280×720' }; }
      if (/^\d+x\d+$/.test(profile)) { return { value: profile.replace('x', '×') }; }
      return { value: tr('跟随被控端') };
    });
  }

  private resolutionIndex(): number {
    const index = this.resolutionProfiles().indexOf(this.settings.defaultVideoProfile);
    return index >= 0 ? index : 0;
  }

  private groupById(id: string): SettingsGroup {
    return GROUPS.find((item: SettingsGroup) => item.id === id) ?? GROUPS[0];
  }

  private accountDetail(): string {
    if (this.accountIdSuffix.length > 0) { return `${tr('账号尾号')} ${this.accountIdSuffix}`; }
    return tr(this.service?.loginSnapshot().authenticated === true ? '已登录' : '尚未登录');
  }

  @Builder
  groupColumn() {
    Stack({ alignContent: Alignment.End }) {
    List({ space: 16, scroller: this.scroller }) {
      ListItemGroup({ style: ListItemGroupStyle.CARD }) {
        ListItem() {
          Row({ space: 12 }) {
            Image($r('app.media.account_avatar_placeholder')).width(40).height(40)
              .objectFit(ImageFit.Contain).accessibilityLevel('no').id('settings.account.avatar')
            Column({ space: 4 }) {
              Text(tr('网易账号')).fontSize($r('sys.float.ohos_id_text_size_body1'))
                .fontColor($r('sys.color.font_primary'))
              Text(this.accountDetail()).fontSize($r('sys.float.ohos_id_text_size_body2'))
                .fontColor($r('sys.color.font_secondary'))
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }.width('100%').constraintSize({ minHeight: 64 }).padding({ left: 16, right: 16, top: 8, bottom: 8 })
        }
      }.margin({ left: 16, right: 16 }).borderRadius($r('sys.float.corner_radius_level8')).id('settings.account.card')
      ListItemGroup({ style: ListItemGroupStyle.CARD }) {
      ForEach(GROUPS, (group: SettingsGroup) => {
        ListItem() {
          ComposeListItem({
            contentItem: { iconStyle: IconType.SYSTEM_ICON,
              icon: iconResource(group.icon, this.isDark, this.navigationMode === NavigationMode.Split && this.group === group.id),
              primaryText: group.title },
            operateItem: { arrow: { value: iconResource('chevron', this.isDark, false), action: () => { this.openGroup(group.id); } } }
          })
        }
        .backgroundColor(this.navigationMode === NavigationMode.Split && this.group === group.id ? $r('sys.color.comp_background_tertiary') : Color.Transparent)
        .borderRadius($r('sys.float.corner_radius_level8')).id(group.id)
        .onClick(() => { this.openGroup(group.id); })
      }, (group: SettingsGroup) => group.id)
      }.margin({ left: 16, right: 16 }).borderRadius($r('sys.float.corner_radius_level8'))
      ListItem() {
        Button(tr('退出登录'), { type: ButtonType.Capsule, role: ButtonRole.ERROR })
          .width('100%').height(48).fontSize(16).id('settings.logout')
          .onClick(() => { this.logoutVisible = true; })
      }.margin({ left: 16, right: 16 })
    }.width('100%').height('100%').contentStartOffset(16).contentEndOffset(88)
      .scrollBar(BarState.Off)
      .cachedCount(2, true).clip(false).id('settings.groups')
      edgeScrollBar(this.scroller, 'settings.groups')
    }.width('100%').height('100%')
  }

  private openGroup(id: string): void {
    this.group = id;
    this.paths.replacePath({ name: id });
  }

  @Builder
  sectionHeading(title: string, id: string) {
    Row() {
      Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_secondary')).id(id)
    }.width('100%').justifyContent(FlexAlign.Start).padding({ left: 16, top: 8, bottom: 8 })
  }

  @Builder
  generalDetail() {
      ListItemGroup({ style: ListItemGroupStyle.CARD,
        header: () => { this.sectionHeading(tr('显示'), 'settings.section.display'); } }) {
        this.settingSelect({ id: 'settings.theme', label: tr('外观'),
          options: [{ value: tr('跟随系统') }, { value: tr('浅色') }, { value: tr('深色') }],
          selected: ['system', 'light', 'dark'].indexOf(this.settings.themePreference), action: (index: number) => {
            this.applyTheme((['system', 'light', 'dark'][index] ?? 'system') as ThemePreference);
          } })
        this.settingSelect({ id: 'settings.material', label: tr('沉浸光感'),
          options: [{ value: tr('跟随系统') }, { value: tr('精致') }, { value: tr('柔和') }, { value: tr('流畅') }],
          selected: ['system', 'exquisite', 'gentle', 'smooth'].indexOf(this.settings.materialPreference),
          action: (index: number) => {
            const preference = (['system', 'exquisite', 'gentle', 'smooth'][index] ?? 'system') as MaterialPreference;
            this.settings.materialPreference = preference;
            this.service?.setMaterialPreference(preference);
          } })
      }.margin({ left: 16, right: 16 }).borderRadius($r('sys.float.corner_radius_level8'))
      ListItemGroup({ style: ListItemGroupStyle.CARD,
        header: () => { this.sectionHeading(tr('输入与剪贴板'), 'settings.section.input'); } }) {
        this.settingSelect({ id: 'settings.input', label: tr('输入'),
          options: [{ value: tr('触控板') }, { value: tr('直接触控') }], selected: this.touchMode === 'direct' ? 1 : 0,
          action: (index: number) => {
            const mode: TouchMode = index === 1 ? 'direct' : 'trackpad';
            this.service?.setTouchMode(mode).catch((error: Error) => {
              this.getUIContext().getPromptAction().showToast({ message: error.message });
            });
          } })
        this.settingSelect({ id: 'settings.files', label: tr('剪贴板'), options: [{ value: tr('手动发送') }], selected: 0, action: () => {
          this.updateSettings(null, null, null, null, null, 'manual');
          this.service?.setClipboardPolicy('manual');
        } })
      }.margin({ left: 16, right: 16 }).borderRadius($r('sys.float.corner_radius_level8'))
      ListItemGroup({ style: ListItemGroupStyle.CARD,
        header: () => { this.sectionHeading(tr('远程操控'), 'settings.section.remote'); } }) {
      ListItem() {
        ComposeListItem({ contentItem: { primaryText: tr('远控时保持亮屏') },
          operateItem: { switch: { isCheck: this.settings.keepScreenOn, onChange: (checked: boolean) => {
            this.settings.keepScreenOn = checked;
            this.service?.setKeepScreenOn(checked);
          } } } })
      }.id('settings.keepScreenOn')
      ListItem() {
        ComposeListItem({ contentItem: { primaryText: tr('自动启动画中画') },
          operateItem: { switch: { isCheck: this.settings.autoStartPiP, onChange: (enabled: boolean) => {
            this.settings.autoStartPiP = enabled;
            this.service?.setAutoStartPiP(enabled);
          } } } })
      }.id('settings.autoStartPiP')
      ListItem() {
        ComposeListItem({ contentItem: { primaryText: tr('智感握姿') },
          operateItem: { switch: { isCheck: this.settings.smartReachEnabled, onChange: (enabled: boolean) => {
            this.settings.smartReachEnabled = enabled;
            this.service?.setSmartReachEnabled(enabled);
          } } } })
      }.id('settings.smartReach')
      if (!this.settings.smartReachEnabled) {
        this.settingSelect({ id: 'settings.controlBarPosition', label: tr('底部控件位置'),
          options: [{ value: tr('居中') }, { value: tr('左') }, { value: tr('右') }],
          selected: ['center', 'left', 'right'].indexOf(this.settings.controlBarPosition), action: (index: number) => {
            const position = (['center', 'left', 'right'][index] ?? 'center') as ControlBarPosition;
            this.settings.controlBarPosition = position;
            this.service?.setControlBarPosition(position);
          } })
      }
      }.margin({ left: 16, right: 16 }).borderRadius($r('sys.float.corner_radius_level8'))
  }

  @Builder
  settingSelect($$: SettingsSelectOptions) {
    ListItem() {
      Row({ space: 12 }) {
        Text($$.label).fontSize(16).fontColor($r('sys.color.font_primary')).layoutWeight(1).id($$.id + '.label')
        Select($$.options).selected($$.selected).value($$.options[$$.selected]?.value ?? tr('不可用'))
          .width('60%').height(48).font({ size: 16 }).id($$.id).accessibilityText($$.label)
          .borderRadius($r('sys.float.corner_radius_level8'))
          .enabled($$.options.length > 0)
          .onSelect((index: number) => { $$.action(index); })
      }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
    }
  }

  @Builder
  videoDetail() {
    ListItemGroup({ style: ListItemGroupStyle.CARD,
      header: () => { this.sectionHeading(tr('画面清晰度'), 'settings.section.clarity'); } }) {
      this.settingSelect({ id: 'settings.quality', label: tr('画质'),
        options: [{ value: tr('自动') }, { value: tr('原画 20M') }, { value: tr('超清 8M') }, { value: tr('高清 2M') }],
        selected: ['auto', 'original', 'ultra', 'hd'].indexOf(this.settings.defaultVideoQuality), action: (index: number) => {
          const quality = (['auto', 'original', 'ultra', 'hd'][index] ?? 'auto') as VideoQuality;
          this.updateSettings(null, null, quality, null, null, null);
          this.service?.setVideoQuality(quality);
        } })
      this.settingSelect({ id: 'settings.resolution', label: tr('分辨率'), options: this.resolutionOptions(), selected: this.resolutionIndex(),
        action: (index: number) => {
          const profile = this.resolutionProfiles()[index] ?? 'auto';
          this.updateSettings(null, profile, null, null, null, null);
          this.service?.setVideoProfile(profile);
        } })
    }.margin({ left: 16, right: 16 }).borderRadius($r('sys.float.corner_radius_level8'))
    ListItemGroup({ style: ListItemGroupStyle.CARD,
      header: () => { this.sectionHeading(tr('流畅度与色彩'), 'settings.section.motion'); } }) {
      this.settingSelect({ id: 'settings.fps', label: tr('帧率'),
        options: [144, 90, 60, 30].filter((fps: number) => fps <= this.maxFps).map((fps: number): SelectOption => {
          return { value: fps + tr(' 帧') };
        }), selected: [144, 90, 60, 30].filter((fps: number) => fps <= this.maxFps).indexOf(this.settings.defaultFrameRate),
        action: (index: number) => {
          const fps = [144, 90, 60, 30].filter((fps: number) => fps <= this.maxFps)[index];
          this.updateSettings(null, null, null, fps, null, null);
          this.service?.setFrameRate(fps);
        } })
      this.settingSelect({ id: 'settings.color', label: tr('色彩'),
        options: this.chroma444 ? [{ value: '4:2:0' }, { value: '4:4:4' }] : [{ value: '4:2:0' }],
        selected: this.settings.trueColor && this.chroma444 ? 1 : 0, action: (index: number) => {
          this.updateSettings(null, null, null, null, index === 1, null);
          this.service?.setTrueColor(index === 1);
        } })
    }.margin({ left: 16, right: 16 }).borderRadius($r('sys.float.corner_radius_level8'))
  }
  @Builder
  informationRow(id: string, label: string, value: string) {
    ListItem() { ComposeListItem({ contentItem: { primaryText: label }, operateItem: { text: value } }) }.id(id)
  }

  @Builder
  aboutDetail() {
    ListItemGroup({ style: ListItemGroupStyle.CARD,
      header: () => { this.sectionHeading(tr('应用信息'), 'settings.section.about'); } }) {
      this.informationRow('settings.about.version', tr('版本'), '1.0.0')
      this.informationRow('settings.about.license', tr('许可'), 'GPL-3.0-or-later')
      this.informationRow('settings.about.unofficial', tr('非官方说明'), tr('非网易官方客户端'))
    }.margin({ left: 16, right: 16 }).borderRadius($r('sys.float.corner_radius_level8'))
  }

  @Builder
  detailTitle(name: string) {
    Column() {
    Row({ space: 8 }) {
      if (this.navigationMode !== NavigationMode.Split) {
        Button({ type: ButtonType.Circle }) { IconView({ iconKey: 'back', allowImageDrag: false }) }
          .width(48).height(48).attributeModifier(floatingControl)
          .id('settings.detail.back').accessibilityText(tr('返回')).onClick(() => { this.paths.pop(); })
      }
      Text(this.groupById(name).title).fontSize(20).fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary')).layoutWeight(1).id('settings.detail.title')
    }.width('100%').height(Metrics.navigationTitleHeight).padding({ left: 16, right: 16 }).id('settings.detail.header.controls')
    }.width('100%').padding({ top: SETTINGS_TITLE_TOP_PADDING })
  }

  @Builder
  mainTitle() {
    Column() {
    Row() {
      Text(tr('设置')).fontSize(24).fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary')).layoutWeight(1).id('settings.title')
    }.width('100%').height(Metrics.navigationTitleHeight).padding({ left: 16, right: 16 }).id('settings.header.controls')
    }.width('100%').padding({ top: SETTINGS_TITLE_TOP_PADDING })
  }

  @Builder
  destination(name: string) {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.End }) {
      List({ space: 16, scroller: this.detailScroller }) {
          if (name === 'settings.general') { this.generalDetail() }
          else if (name === 'settings.video') { this.videoDetail() }
          else { this.aboutDetail() }
      }.width('100%').height('100%').contentStartOffset(16).contentEndOffset(104)
        .scrollBar(BarState.Off)
        .clip(false).id('settings.detail.scroll')
        edgeScrollBar(this.detailScroller, 'settings.detail.scroll')
      }.width('100%').height('100%')
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      content: { stackBuilder: () => this.detailTitle(name), divider: { showType: DividerShowType.OFF } },
      style: {
        blurStrategy: BlurStrategy.ENABLE,
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
        originalStyle: { backgroundStyle: { blurRadius: 12 } },
        systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: this.materialLevel
      } }
    })
    .bindToScrollable([this.detailScroller])
    .hideBackButton(true)
    .id('settings.detail')
  }

  build() {
    Stack() {
      HdsNavigation(this.paths) { this.groupColumn() }
        .titleBar({ avoidLayoutSafeArea: true, enableComponentSafeArea: true,
          content: { stackBuilder: () => this.mainTitle(), divider: { showType: DividerShowType.OFF } },
          style: { blurStrategy: BlurStrategy.ENABLE,
            scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
            originalStyle: { backgroundStyle: { blurRadius: 12 } },
            systemMaterialEffect: { materialType: hdsMaterial.MaterialType.ADAPTIVE, materialLevel: this.materialLevel } } })
        .titleMode(HdsNavigationTitleMode.MINI)
        .bindToScrollable([this.scroller])
        .hideBackButton(true)
        .mode(NavigationMode.Auto)
        .navBarWidth('32%')
        .navBarWidthRange({ minWidth: 224, maxWidth: 320 })
        .minContentWidth(320)
        .navDestination(this.destination)
        .onNavigationModeChange((mode: NavigationMode) => {
          this.navigationMode = mode;
          if (mode === NavigationMode.Split && this.paths.size() === 0) {
            this.paths.pushPath({ name: this.group });
          }
        })
        .width('100%').height('100%').id('settings.page')
      ConfirmDialog({
        visible: this.logoutVisible, title: tr('退出登录'),
        body: tr('退出后将结束本账号所属的会话并删除本机保存的登录凭据。'),
        confirmText: tr('退出登录'), cancelText: tr('取消'), destructive: true,
        onConfirm: () => { this.logoutVisible = false; this.service?.logout(); },
        onCancel: () => { this.logoutVisible = false; }
      })
    }.width('100%').height('100%')
  }
}
