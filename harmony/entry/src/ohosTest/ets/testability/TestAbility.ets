import { UIAbility } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Hypium } from '@ohos/hypium';
import testsuite from '../test/List.test';

export default class TestAbility extends UIAbility {
  onCreate(): void {
    Hypium.hypiumTest(abilityDelegatorRegistry.getAbilityDelegator(),
      abilityDelegatorRegistry.getArguments(), testsuite);
  }
}
