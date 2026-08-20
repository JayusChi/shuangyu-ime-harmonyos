import Want from '@ohos.app.ability.Want';
import Stage0InputMethodAbilityBase from './Stage0InputMethodAbilityBase';
import {
  clearEngineInitializationOverride,
  setEngineInitializationOverride
} from '../application/EngineInitializationOverride';
import { Logger } from '../common/logging/Logger';
import { CodeTableFixtureInstaller } from '../infrastructure/resource/CodeTableFixtureInstaller';
import { getSharedEngineCoordinator } from '../application/EngineCoordinator';
import { ImeConnectionService } from '../infrastructure/ime/ImeConnectionService';
import { getSharedInputSessionStore } from '../state/InputSessionStore';
import {
  Stage1167DeviceCommand,
  Stage1167DeviceCommandBus
} from '../infrastructure/Stage1167DeviceCommandBus';

const ACTION_FIXTURE_SHA256 = '05a7653e44fe72c45b1b5b0dc1dc245baaafbc1f4becd5c2ec6c657687c59b63';
const LOGGER = new Logger('Stage1166EditorDebug');
const STAGE1167_USER_RULES =
  '正向切分段\twxq\n' +
  '正向右段\tr\n' +
  '反向合法后段\trst\n' +
  '三码唯一\tpqr\n' +
  '测试\tdzqd#删\n' +
  '用户顶屏\twxyz#固\n' +
  '多候选乙\twxyz\n';

export default class Stage0InputMethodAbility extends Stage0InputMethodAbilityBase {
  private readonly deviceCommandBus: Stage1167DeviceCommandBus = new Stage1167DeviceCommandBus();
  private readonly imeService: ImeConnectionService = new ImeConnectionService();

  onCreate(want: Want): void {
    const installer = new CodeTableFixtureInstaller();
    const fixture = installer.installFixture(this.context);
    const actions = installer.installActionFixture(this.context);
    const userRules = installer.installUserLexicon(this.context, STAGE1167_USER_RULES);
    if (fixture.success && actions.success && userRules.success) {
      setEngineInitializationOverride({
        schemeId: 'code-table-fixture',
        candidatePageSize: 8,
        codeTableBundlePath: fixture.path,
        userLexiconPath: userRules.path,
        codeTableActionFixturePath: actions.path,
        codeTableActionFixtureSha256: ACTION_FIXTURE_SHA256
      });
      LOGGER.info('editor action fixture override ready');
    } else {
      clearEngineInitializationOverride();
      LOGGER.error(
        `editor fixture override unavailable: fixture=${fixture.errorMessage}, actions=${actions.errorMessage}, ` +
        `rules=${userRules.errorMessage}`
      );
    }
    super.onCreate(want);
    this.deviceCommandBus.subscribe((command: Stage1167DeviceCommand): void => {
      this.handleDeviceCommand(command);
    });
  }

  onDestroy(): void {
    this.deviceCommandBus.unsubscribe();
    super.onDestroy();
    clearEngineInitializationOverride();
  }

  private handleDeviceCommand(command: Stage1167DeviceCommand): void {
    const engine = getSharedEngineCoordinator();
    const store = getSharedInputSessionStore();
    if (command === 'ALL_CATEGORIES') {
      const config = engine.getCodeTableCategoryConfig();
      const result = engine.setCodeTableCategories(config.categories.map((item) => item.id));
      store.updateComposition(result);
      this.imeService.setPreviewText(result.preeditText, true, store.getSessionGeneration());
      return;
    }
    if (command === 'CORE_ONLY') {
      const result = engine.setCodeTableCategories(['core']);
      store.updateComposition(result);
      this.imeService.setPreviewText(result.preeditText, true, store.getSessionGeneration());
      return;
    }
    if (command === 'XIAOHE') {
      const result = engine.changeScheme('xiaohe');
      store.updateComposition(result);
      this.imeService.clearPreviewText(store.getSessionGeneration());
      return;
    }
  }
}
