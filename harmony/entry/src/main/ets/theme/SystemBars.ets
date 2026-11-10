import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

/**
 * Keeps the status and navigation bars transparent so the immersive backdrop
 * reaches the screen edges. Failures are harmless (for example on 2in1 windows
 * that do not own a system bar).
 */
export class SystemBars {
  static apply(context: common.UIAbilityContext, dark: boolean): void {
    if (deviceInfo.deviceType === '2in1') { return; }
    window.getLastWindow(context).then((main: window.Window) => {
      main.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: dark ? '#F1F3F5' : '#182431',
        navigationBarColor: '#00000000',
        navigationBarContentColor: dark ? '#F1F3F5' : '#182431'
      }).catch(() => {
        console.info('system bar styling is not available');
      });
    }).catch(() => {
      console.info('main window is not available');
    });
  }
}
