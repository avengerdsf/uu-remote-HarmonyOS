import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { ServiceHub } from '../services/ServiceHub';
import { ThemeManager } from '../theme/ThemeManager';
import { SystemBars } from '../theme/SystemBars';
import { ThemePreference } from '../model/Models';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null;
  private onAvoidArea = (options: window.AvoidAreaOptions): void => {
    if (options.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR && this.mainWindow !== null) {
      AppStorage.setOrCreate('navigationIndicatorBottomVp', this.mainWindow.getUIContext().px2vp(options.area.bottomRect.height));
    }
  };
  private onWindowSize = (size: window.Size): void => {
    if (this.mainWindow === null) { return; }
    const ui = this.mainWindow.getUIContext();
    AppStorage.setOrCreate('currentWidthBreakpoint', ui.getWindowWidthBreakpoint());
    AppStorage.setOrCreate('currentHeightBreakpoint', ui.getWindowHeightBreakpoint());
    AppStorage.setOrCreate('windowWidthVp', ui.px2vp(size.width));
    AppStorage.setOrCreate('windowHeightVp', ui.px2vp(size.height));
    const area = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    AppStorage.setOrCreate('navigationIndicatorBottomVp', ui.px2vp(area.bottomRect.height));
  };

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('route', 'devices');
    AppStorage.setOrCreate('deviceListForeground', false);
    AppStorage.setOrCreate('routeVersion', 1);
    AppStorage.setOrCreate('fontScale', 1);
    AppStorage.setOrCreate('navigationIndicatorBottomVp', 0);
    AppStorage.setOrCreate('isDark', false);
    AppStorage.setOrCreate('sessionBackRequested', 0);
    AppStorage.setOrCreate('currentWidthBreakpoint', WidthBreakpoint.WIDTH_SM);
    AppStorage.setOrCreate('currentHeightBreakpoint', HeightBreakpoint.HEIGHT_LG);
  }

  onForeground(): void {
    AppStorage.setOrCreate('deviceListForeground', true);
    if (ServiceHub.isReady()) { ServiceHub.service().setAppForeground(true); }
  }

  onBackground(): void {
    AppStorage.setOrCreate('deviceListForeground', false);
    if (ServiceHub.isReady()) { ServiceHub.service().setAppForeground(false); }
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    const context = this.context;
    this.syncConfiguration(context.config);
    try {
      await ServiceHub.init(context);
    } catch (error) {
      console.error('UU native service initialization failed');
    }
    await windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        console.error(`loadContent failed: ${err.code}`);
        return;
      }
      this.mainWindow = windowStage.getMainWindowSync();
      const rect = this.mainWindow.getWindowProperties().windowRect;
      this.onWindowSize({ width: rect.width, height: rect.height });
      this.mainWindow.on('windowSizeChange', this.onWindowSize);
      this.mainWindow.on('avoidAreaChange', this.onAvoidArea);
    });
    const preference = ServiceHub.isReady() ? ServiceHub.service().settings().themePreference : 'system';
    ThemeManager.apply(context, preference as ThemePreference);
    SystemBars.apply(context, AppStorage.get<boolean>('isDark') ?? false);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    this.syncConfiguration(newConfig);
  }

  onWindowStageDestroy(): void {
    this.mainWindow?.off('windowSizeChange', this.onWindowSize);
    this.mainWindow?.off('avoidAreaChange', this.onAvoidArea);
    this.mainWindow = null;
  }

  onDestroy(): void {
    if (ServiceHub.isReady()) { ServiceHub.service().dispose(); }
  }

  private syncConfiguration(config: Configuration): void {
    const scale = config.fontSizeScale ?? 1;
    AppStorage.setOrCreate('fontScale', scale);
    const dark = config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    AppStorage.setOrCreate('isDark', dark);
  }
}
