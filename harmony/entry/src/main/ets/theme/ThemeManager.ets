import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { ThemePreference } from '../model/Models';
import { SystemBars } from './SystemBars';

export class ThemeManager {
  static apply(context: common.UIAbilityContext, preference: ThemePreference): void {
    const applicationContext = context.getApplicationContext();
    let dark = AppStorage.get<boolean>('isDark') ?? false;
    if (preference === 'light') {
      applicationContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      AppStorage.setOrCreate('isDark', false);
      dark = false;
    } else if (preference === 'dark') {
      applicationContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      AppStorage.setOrCreate('isDark', true);
      dark = true;
    } else {
      applicationContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    }
    AppStorage.setOrCreate('themePreference', preference);
    SystemBars.apply(context, dark);
  }
}
