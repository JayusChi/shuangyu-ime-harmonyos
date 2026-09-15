import { UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { isFlypyWebTarget } from '../domain/direct/FlypyWebTarget';

export default class FlypyWebAbility extends UIAbility {
  private storage: LocalStorage = new LocalStorage();
  private request: number = 0;
  private valid: boolean = false;

  onCreate(want: Want): void { this.accept(want); }
  onNewWant(want: Want): void { this.accept(want); }

  private accept(want: Want): void {
    const url = want.uri ?? '';
    if (!isFlypyWebTarget(url)) {
      if (!this.valid) { this.context.terminateSelf().catch((): void => {}); }
      return;
    }
    this.valid = true;
    this.storage.setOrCreate('flypyWebUrl', url);
    // A repeated lookup of the same character must also reload the visible page.
    this.request += 1;
    this.storage.setOrCreate('flypyWebRequest', this.request);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    if (!this.valid) { return; }
    windowStage.loadContent('pages/FlypyWeb', this.storage, (error): void => {
      if (error.code) { this.context.terminateSelf().catch((): void => {}); }
    });
  }
}
