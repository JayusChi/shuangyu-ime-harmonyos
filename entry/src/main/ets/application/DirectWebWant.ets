import { Want } from '@kit.AbilityKit';
import { isFlypyWebTarget } from '../domain/direct/FlypyWebTarget';

export function directWebWant(url: string): Want {
  const want: Want = { action: 'ohos.want.action.viewData', uri: url };
  if (isFlypyWebTarget(url)) {
    want.bundleName = 'com.corrosion.shuangyuime';
    want.abilityName = 'FlypyWebAbility';
  }
  return want;
}
