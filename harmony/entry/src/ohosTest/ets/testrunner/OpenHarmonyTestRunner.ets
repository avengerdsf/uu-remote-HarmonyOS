import { abilityDelegatorRegistry, TestRunner } from '@kit.TestKit';

export default class OpenHarmonyTestRunner implements TestRunner {
  onPrepare(): void {}

  async onRun(): Promise<void> {
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    const args = abilityDelegatorRegistry.getArguments();
    try {
      await delegator.startAbility({ bundleName: args.bundleName, moduleName: 'entry_test', abilityName: 'TestAbility' });
    } catch (error) {
      delegator.finishTest('Application test entry failed', -1, () => {});
    }
  }
}
