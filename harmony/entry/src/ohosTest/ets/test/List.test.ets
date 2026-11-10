import multiDeviceRegression from './MultiDeviceRegression.test';
import uiAcceptanceTest from './UiAcceptance.test';
import sessionStability from './SessionStability.test';

export default function testsuite(): void {
  uiAcceptanceTest();
  multiDeviceRegression();
  sessionStability();
}
