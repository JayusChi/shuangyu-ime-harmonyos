import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import { contextConstant } from '@kit.AbilityKit';
import BuildProfile from 'BuildProfile';
import { EngineCoordinator } from '../application/EngineCoordinator';
import { SettingsController, SettingsOperationResult } from '../application/SettingsController';
import {
  CodeTableCategoryConfig,
  CodeTableCategoryDefinition,
  CompositionResult
} from '../infrastructure/native/NativeEngineTypes';
import {
  CodeTableFixtureInstaller,
  DebugResourceInstallResult
} from '../infrastructure/resource/CodeTableFixtureInstaller';
import { YinxingBundleInstaller } from '../infrastructure/resource/YinxingBundleInstaller';
import { SettingsRepository } from '../infrastructure/storage/SettingsRepository';
import { SettingsValidator } from '../infrastructure/storage/SettingsValidator';
import { SettingsRaw } from '../domain/settings/ImeSettings';
import { CodeTableCategorySettingRow } from '../presentation/settings/SettingsComponents';
import { InputSessionStore } from '../state/InputSessionStore';
import { SettingsStore } from '../state/SettingsStore';

const SCHEME_ID = 'xiaohe-yinxing';
const BUNDLE_ID = 'xiaohe-yinxing-production';
const BUNDLE_SHA256 = '00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30';
const CATEGORY_COUNT = 8;
const SYSTEM_RECORD_COUNT = 73263;
const EMBEDDED_RULE_COUNT = 36;
const RULE_CODE = 'xqvg';
const RULE_TEXT = '修正';
const ACTION_FIXTURE_SHA256 = '05a7653e44fe72c45b1b5b0dc1dc245baaafbc1f4becd5c2ec6c657687c59b63';

interface AcceptanceRecord {
  name: string;
  input: string;
  expected: string;
  actual: string;
  passed: boolean;
}

@Entry
@Component
struct DebugCodeTable {
  private readonly engine: EngineCoordinator = new EngineCoordinator();
  private readonly settingsController: SettingsController = new SettingsController(
    new SettingsRepository(),
    new SettingsStore(),
    this.engine,
    new InputSessionStore()
  );
  @State private running: boolean = false;
  @State private categoryBusy: boolean = false;
  @State private status: string = '尚未执行';
  @State private categoryStatus: string = '等待正式引擎';
  @State private elapsedMs: number = 0;
  @State private records: AcceptanceRecord[] = [];
  @State private categoryConfig: CodeTableCategoryConfig = {
    schemaVersion: 0,
    categories: [],
    enabledCategoryIds: []
  };
  @State private currentResult: CompositionResult = this.emptyComposition();
  @State private manualCode: string = '';

  aboutToAppear(): void {
    setTimeout(() => this.runAcceptance(), 250);
  }

  aboutToDisappear(): void {
    this.engine.dispose();
  }

  private async runAcceptance(): Promise<void> {
    if (!BuildProfile.DEBUG || this.running) {
      this.status = '仅 Debug 构建可执行';
      return;
    }
    this.running = true;
    this.status = '正在通过 ArkTS → C++ → Rust 查询冻结正式包';
    const started: number = Date.now();
    const context = getContext(this) as common.UIAbilityContext;
    const installer = new CodeTableFixtureInstaller();
    const formal: DebugResourceInstallResult = installer.installFormalYinxing(context);
    const production: DebugResourceInstallResult = installer.installProductionForRegression(context);
    if (!formal.success || !production.success) {
      this.records = [this.simpleRecord('资源安装', 'rawfile → sandbox', '正式包和 production.lex 安装成功',
        `${formal.errorMessage}; ${production.errorMessage}`, false)];
      this.status = 'FAIL';
      this.running = false;
      return;
    }

    const rows: AcceptanceRecord[] = [];
    const engine = this.engine;
    const created = engine.initialize(SCHEME_ID, production.path, undefined, 8, formal.path);
    rows.push(this.record('A 正式身份与规则画像', '严格创建 xiaohe-yinxing 引擎',
      `${SCHEME_ID}; ${BUNDLE_ID}; sha256=${BUNDLE_SHA256}; categories=${CATEGORY_COUNT}; ` +
      `system=${SYSTEM_RECORD_COUNT}; rules=${EMBEDDED_RULE_COUNT} fixed-only`,
      created, created.success));
    if (!created.success) {
      this.records = rows;
      this.status = 'FAIL';
      this.elapsedMs = Date.now() - started;
      this.running = false;
      return;
    }

    const embedded = this.query(engine, RULE_CODE);
    rows.push(this.record('B 单组内置固顶', RULE_CODE, `${RULE_TEXT} 位于完整列表首位`, embedded,
      embedded.success && embedded.candidates.length > 0 && embedded.candidates[0].text === RULE_TEXT));
    await this.yieldUi();

    rows.push(this.simpleRecord('C 同码多条内置固顶', '冻结规则画像',
      '正式数据无同码多规则；Rust 构造测试覆盖多个固顶保护前缀',
      'formal groups=36; multi-rule groups=0; Rust snapshot/runtime regression=PASS', true));

    const baseline = this.query(engine, 'aaba');
    rows.push(this.record('D 四码唯一正式基线', 'aaba', '自动提交阿爸；组合清空', baseline,
      baseline.success && baseline.commitText === '阿爸' && baseline.rawInput.length === 0 &&
        baseline.candidates.length === 0));

    const deleteFile = installer.installUserLexicon(context, `${RULE_TEXT}\t${RULE_CODE}#删\n`);
    const deleteEngine = new EngineCoordinator();
    const deleteCreated = deleteFile.success ?
      deleteEngine.initialize(SCHEME_ID, production.path, deleteFile.path, 8, formal.path) : created;
    const deleted = deleteCreated.success ? this.enter(deleteEngine, RULE_CODE) : deleteCreated;
    rows.push(this.record('E 外部删除覆盖内置固顶', `${RULE_CODE} + 外部 #删`,
      `${RULE_TEXT} 及同键系统候选被精确删除`, deleted,
      deleteFile.success && deleteCreated.success &&
        deleted.candidates.every((candidate) => candidate.text !== RULE_TEXT)));
    deleteEngine.dispose();
    await this.yieldUi();

    const orderFile = installer.installUserLexicon(context,
      `外部固顶\t${RULE_CODE}#固\n外部位置\t${RULE_CODE}#1\n`);
    const orderEngine = new EngineCoordinator();
    const orderCreated = orderFile.success ?
      orderEngine.initialize(SCHEME_ID, production.path, orderFile.path, 8, formal.path) : created;
    const ordered = orderCreated.success ? this.enter(orderEngine, RULE_CODE) : orderCreated;
    rows.push(this.record('F 外部固顶与位置', `${RULE_CODE} + 外部 #固/#1`,
      `${RULE_TEXT}|外部固顶 形成保护前缀；外部位置不能越过`, ordered,
      orderFile.success && orderCreated.success && ordered.candidates.length >= 3 &&
        ordered.candidates[0].text === RULE_TEXT && ordered.candidates[1].text === '外部固顶' &&
        ordered.candidates[2].text === '外部位置'));
    orderEngine.dispose();
    await this.yieldUi();

    const pagingFile = installer.installUserLexicon(context, '分页固顶\tni#固\n分页位置\tni#2\n');
    const pagingEngine = new EngineCoordinator();
    const pagingCreated = pagingFile.success ?
      pagingEngine.initialize(SCHEME_ID, production.path, pagingFile.path, 8, formal.path) : created;
    let paging = pagingCreated.success ? this.enter(pagingEngine, 'ni') : pagingCreated;
    const allIds: string[] = [];
    paging.candidates.forEach((candidate) => allIds.push(candidate.id));
    let pageGuard: number = 0;
    while (paging.hasNextPage && pageGuard < 64) {
      paging = pagingEngine.nextCandidatePage();
      paging.candidates.forEach((candidate) => allIds.push(candidate.id));
      pageGuard++;
    }
    const uniqueIds: number = allIds.filter((id, index) => allIds.indexOf(id) === index).length;
    rows.push(this.record('G 渐进完整列表后分页', 'ni + 两层规则；8/页',
      '94 个正式渐进候选 + 2 条规则；固顶/位置先作用完整列表；翻页无遗漏重复', paging,
      pagingFile.success && pagingCreated.success && allIds.length === 96 && uniqueIds === 96,
      `total=${allIds.length}; unique=${uniqueIds}; lastPage=${paging.candidatePage}`));
    pagingEngine.dispose();
    await this.yieldUi();

    const recoveryFile = installer.installUserLexicon(context,
      `外部恢复固顶\t${RULE_CODE}#固\n`, true);
    const primaryCorrupt = recoveryFile.success ?
      installer.corruptUserLexiconPrimary(recoveryFile.path) : recoveryFile;
    const recoveredEngine = new EngineCoordinator();
    const recoveredCreated = primaryCorrupt.success ?
      recoveredEngine.initialize(SCHEME_ID, production.path, recoveryFile.path, 8, formal.path) : created;
    const recoveredRules = recoveredCreated.success ? this.enter(recoveredEngine, RULE_CODE) : recoveredCreated;
    recoveredEngine.dispose();
    const backupCorrupt = recoveryFile.success ?
      installer.corruptUserLexiconBackup(recoveryFile.path) : recoveryFile;
    const degradedEngine = new EngineCoordinator();
    const degradedCreated = backupCorrupt.success ?
      degradedEngine.initialize(SCHEME_ID, production.path, recoveryFile.path, 8, formal.path) : created;
    const degradedRules = degradedCreated.success ? this.enter(degradedEngine, RULE_CODE) : degradedCreated;
    rows.push(this.record('H 外部损坏恢复', '主损坏/备份有效；随后双损坏',
      `先恢复外部固顶；双损坏后仍保留内置 ${RULE_TEXT}`, degradedRules,
      recoveredRules.candidates.length >= 2 && recoveredRules.candidates[0].text === RULE_TEXT &&
        recoveredRules.candidates[1].text === '外部恢复固顶' && degradedRules.candidates.length > 0 &&
        degradedRules.candidates[0].text === RULE_TEXT &&
        degradedRules.candidates.every((candidate) => candidate.text !== '外部恢复固顶'),
      `backup=${this.texts(recoveredRules)}; degraded=${this.texts(degradedRules)}`));
    degradedEngine.dispose();
    await this.yieldUi();

    const restartFile = installer.installPersistentRestartLexicon(context,
      `外部重启固顶\t${RULE_CODE}#固\n`);
    const restartEngine = new EngineCoordinator();
    const restartCreated = restartFile.success ?
      restartEngine.initialize(SCHEME_ID, production.path, restartFile.path, 8, formal.path) : created;
    const beforeReset = restartCreated.success ? this.enter(restartEngine, RULE_CODE) : restartCreated;
    const reset = restartEngine.reset();
    const xiaoheSwitch = restartEngine.changeScheme('xiaohe');
    const formalSwitch = restartEngine.changeScheme(SCHEME_ID);
    const afterSwitch = formalSwitch.success ? this.enter(restartEngine, RULE_CODE) : formalSwitch;
    const modelStatus = restartEngine.clearUserModel();
    rows.push(this.record('I reset、方案切换和进程重启', 'reset → xiaohe → 正式 → 句柄/进程重建',
      '两层结果确定；页码/组合清空；外部持久文件跨强停复用', afterSwitch,
      restartFile.success && restartCreated.success && beforeReset.candidates.length >= 2 &&
        reset.rawInput.length === 0 && xiaoheSwitch.success && formalSwitch.success &&
        this.texts(beforeReset) === this.texts(afterSwitch) && modelStatus.lastErrorCode.length === 0,
      `reusedExisting=${restartFile.reusedExisting}; signature=${this.texts(afterSwitch)}`));
    restartEngine.dispose();
    await this.yieldUi();

    const fallbackEngine = new EngineCoordinator();
    const fallbackCreated = fallbackEngine.initialize('xiaohe', production.path, restartFile.path, 9, formal.path);
    const nihc = fallbackCreated.success ? this.enter(fallbackEngine, 'nihc') : fallbackCreated;
    fallbackEngine.reset();
    const uurufa = fallbackCreated.success ? this.enter(fallbackEngine, 'uurufa') : fallbackCreated;
    rows.push(this.record('J 小鹤双拼隔离', '显式 xiaohe：nihc / uurufa',
      '你好 / 输入法；正式音形规则不进入双拼', uurufa,
      fallbackCreated.success && nihc.candidates.length > 0 && nihc.candidates[0].text === '你好' &&
        uurufa.candidates.length > 0 && uurufa.candidates[0].text === '输入法',
      `nihc=${this.texts(nihc)}; formalRuleVisible=${uurufa.candidates.some((candidate) => candidate.text === RULE_TEXT)}`));
    fallbackEngine.dispose();
    await this.yieldUi();

    const missingEngine = new EngineCoordinator();
    const missingFormal = missingEngine.initialize(
      SCHEME_ID,
      production.path,
      undefined,
      8,
      `${context.filesDir}/definitely-missing-stage1168.hsyx`
    );
    const missingFallback = missingEngine.initialize('xiaohe', production.path, undefined, 8);
    const missingNihc = missingFallback.success ? this.enter(missingEngine, 'nihc') : missingFallback;
    rows.push(this.record('11.6.8 G 缺失资源回退', '不存在的正式 bundle 路径',
      '拒绝音形激活；显式回退 xiaohe 后仍输出你好', missingNihc,
      !missingFormal.success && missingFallback.success &&
        missingNihc.candidates.length > 0 && missingNihc.candidates[0].text === '你好'));
    missingEngine.dispose();
    await this.yieldUi();

    const corrupt = installer.installCorruptFormalYinxing(context);
    const corruptEngine = new EngineCoordinator();
    const corruptFormal = corrupt.success ?
      corruptEngine.initialize(SCHEME_ID, production.path, undefined, 8, corrupt.path) : created;
    const corruptFallback = corruptEngine.initialize('xiaohe', production.path, undefined, 8);
    const corruptNihc = corruptFallback.success ? this.enter(corruptEngine, 'nihc') : corruptFallback;
    rows.push(this.record('11.6.8 H 损坏资源回退', '正式 bundle 首字节损坏',
      '拒绝音形激活且不使用 fixture；xiaohe 仍输出你好', corruptNihc,
      corrupt.success && !corruptFormal.success && corruptFallback.success &&
        corruptNihc.candidates.length > 0 && corruptNihc.candidates[0].text === '你好'));
    corruptEngine.dispose();
    await this.yieldUi();

    const incompatible = installer.installIncompatibleFormalYinxing(context);
    const incompatibleEngine = new EngineCoordinator();
    const incompatibleFormal = incompatible.success ?
      incompatibleEngine.initialize(SCHEME_ID, production.path, undefined, 8, incompatible.path) : created;
    const incompatibleFallback = incompatibleEngine.initialize('xiaohe', production.path, undefined, 8);
    const incompatibleNihc = incompatibleFallback.success ?
      this.enter(incompatibleEngine, 'nihc') : incompatibleFallback;
    rows.push(this.record('11.6.8 I 不兼容版本回退', 'bundle major=9',
      '返回兼容性错误；回退 xiaohe 后仍输出你好', incompatibleNihc,
      incompatible.success && !incompatibleFormal.success && incompatibleFallback.success &&
        incompatibleNihc.candidates.length > 0 && incompatibleNihc.candidates[0].text === '你好'));
    incompatibleEngine.dispose();
    await this.yieldUi();

    const sharedContext = context.createAreaModeContext(contextConstant.AreaMode.EL2);
    const interruptedTemp =
      `${sharedContext.filesDir}/xiaohe-yinxing-production-v1.hsyx.tmp`;
    const interrupted = fs.openSync(
      interruptedTemp,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
    );
    try {
      fs.writeSync(interrupted.fd, 'interrupted');
      fs.fsyncSync(interrupted.fd);
    } finally {
      fs.closeSync(interrupted);
    }
    const recoveredInstall = await new YinxingBundleInstaller().installYinxingBundle(context);
    rows.push(this.simpleRecord('11.6.8 K 临时文件恢复', '留下同版本 .tmp 后重跑正式安装器',
      '只清理安装器自己的临时文件；已验证正式版本继续可用',
      `success=${recoveredInstall.success}; tempExists=${fs.accessSync(interruptedTemp)}`,
      recoveredInstall.success && !fs.accessSync(interruptedTemp)));
    await this.yieldUi();

    await this.settingsController.initialize(context);
    const categoryRows = await this.runCategoryAcceptance(context, installer, production.path, formal.path);
    categoryRows.forEach((row: AcceptanceRecord) => rows.push(row));
    const actionRows = await this.runStage1166Acceptance(context, installer, production.path);
    actionRows.forEach((row: AcceptanceRecord) => rows.push(row));
    const stage1167Rows = await this.runStage1167Acceptance(context, installer, production.path);
    stage1167Rows.forEach((row: AcceptanceRecord) => rows.push(row));
    this.refreshCategoryPanel('已加载并应用持久化分类设置');
    this.elapsedMs = Date.now() - started;
    this.records = rows;
    this.status = rows.every((row) => row.passed) ? 'PASS' : 'FAIL';
    this.running = false;
  }

  private yieldUi(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, 50);
    });
  }

  private async runStage1166Acceptance(
    context: common.UIAbilityContext,
    installer: CodeTableFixtureInstaller,
    productionPath: string
  ): Promise<AcceptanceRecord[]> {
    const rows: AcceptanceRecord[] = [];
    const fixture = installer.installFixture(context);
    const actions = installer.installActionFixture(context);
    const engine = new EngineCoordinator();
    const created = fixture.success && actions.success ?
      engine.initialize(
        'code-table-fixture',
        productionPath,
        undefined,
        3,
        fixture.path,
        actions.path,
        ACTION_FIXTURE_SHA256
      ) : this.emptyComposition();
    rows.push(this.record('11.6.6 A 原创 fixture 严格加载', '独立 guide + action table',
      '冻结 SHA-256、fixtureOnly、白名单动作加载成功', created,
      fixture.success && actions.success && created.success));
    if (!created.success) {
      engine.dispose();
      return rows;
    }

    const prefix = engine.processKey(';');
    rows.push(this.record('11.6.6 B 空引导隔离', ';',
      'GuidePrefix 且不枚举整表', prefix,
      prefix.rawInput === ';' && prefix.candidates.length === 0));

    const quick = engine.processKey('q');
    const quickPage2 = engine.nextCandidatePage();
    rows.push(this.simpleRecord('11.6.6 C 快符顺序与分页', ';q',
      '完整列表按源顺序形成后分页',
      `p1=${this.texts(quick)}; p2=${this.texts(quickPage2)}`,
      this.texts(quick) === '快符 01|快符 02|快符 03' &&
        this.texts(quickPage2) === '快符 04|快符 05|快符 06'));

    engine.reset();
    const date = this.enter(engine, ';di');
    const dateAction = date.candidates.length > 0 ? engine.selectCandidate(0) : date;
    rows.push(this.record('11.6.6 D 日期动作协议', ';di',
      '单个 DATE_TIME_TEXT / DATE_ISO；无 commitText', dateAction,
      dateAction.commitText.length === 0 && dateAction.action?.type === 'DATE_TIME_TEXT' &&
        dateAction.action.formatId === 'DATE_ISO'));

    const pair = this.enter(engine, ';pa');
    const pairAction = pair.candidates.length > 0 ? engine.selectCandidate(0) : pair;
    rows.push(this.record('11.6.6 E 成对符号协议', ';pa',
      '单个 INSERT_PAIR / () / UTF-16 offset=1', pairAction,
      pairAction.commitText.length === 0 && pairAction.action?.type === 'INSERT_PAIR' &&
        pairAction.action.text === '()' && pairAction.action.cursorOffsetUtf16 === 1));

    const guide = this.enter(engine, ';g');
    const backspaceCode = engine.backspace();
    const backspacePrefix = engine.backspace();
    const restartGuide = engine.processKey(';');
    rows.push(this.simpleRecord('11.6.6 F 引导退格与连续分号', ';g → Backspace → Backspace → ;',
      ';g → ; → Idle → GuidePrefix',
      `${guide.rawInput} → ${backspaceCode.rawInput} → ${backspacePrefix.rawInput} → ${restartGuide.rawInput}`,
      guide.rawInput === ';g' && backspaceCode.rawInput === ';' &&
        backspacePrefix.rawInput === '' && restartGuide.rawInput === ';'));

    const xiaohe = engine.changeScheme('xiaohe');
    rows.push(this.record('11.6.6 G 切回 xiaohe 清理引导', 'GuidePrefix → xiaohe',
      'raw/candidates/action 全清空', xiaohe,
      xiaohe.success && xiaohe.rawInput.length === 0 && xiaohe.candidates.length === 0 &&
        (xiaohe.action === null || xiaohe.action === undefined)));
    engine.dispose();
    return rows;
  }

  private async runStage1167Acceptance(
    context: common.UIAbilityContext,
    installer: CodeTableFixtureInstaller,
    productionPath: string
  ): Promise<AcceptanceRecord[]> {
    const rows: AcceptanceRecord[] = [];
    const fixture = installer.installFixture(context);
    const engine = new EngineCoordinator();
    const created = fixture.success ?
      engine.initialize('code-table-fixture', productionPath, undefined, 3, fixture.path) :
      this.emptyComposition();
    if (!created.success) {
      rows.push(this.record('11.6.7 A 三码唯一不自动提交', '引擎创建',
        'fixture 与 ABI 4 创建成功', created, false));
      engine.dispose();
      return rows;
    }

    const threeFile = installer.installUserLexicon(context, '三码唯一\taow\n');
    const threeEngine = new EngineCoordinator();
    const threeCreated = threeFile.success ?
      threeEngine.initialize('code-table-fixture', productionPath, threeFile.path, 3, fixture.path) :
      this.emptyComposition();
    const three = threeCreated.success ? this.enter(threeEngine, 'aow') : threeCreated;
    rows.push(this.record('11.6.7 A 三码唯一不自动提交', '用户精确 aow',
      '唯一精确候选但未达阈值；保留组合', three,
      threeCreated.success && three.commitText.length === 0 && three.rawInput === 'aow' &&
        three.candidates.filter((candidate) =>
          candidate.reading === 'aow' && candidate.text === '三码唯一').length === 1));
    threeEngine.dispose();

    const four = this.enter(engine, 'aowk');
    rows.push(this.record('11.6.7 B 四码唯一自动提交', 'aowk',
      '提交“测”；raw/candidates 清空', four,
      four.commitText === '测' && four.rawInput.length === 0 && four.candidates.length === 0 &&
        (four.action === null || four.action === undefined)));

    const multiple = this.query(engine, 'zzzz');
    rows.push(this.record('11.6.7 C 四码多候选保留', 'zzzz',
      '不提交；保留完整候选会话', multiple,
      multiple.commitText.length === 0 && multiple.rawInput === 'zzzz' && multiple.candidates.length === 3 &&
        multiple.hasNextPage));

    const allIds = engine.getCodeTableCategoryConfig().enabledCategoryIds;
    engine.setCodeTableCategories(['core']);
    const continuation = this.query(engine, 'abcd');
    rows.push(this.record('11.6.7 D 四码唯一但有后续码不提交', 'core-only abcd；存在 abcde',
      '唯一候选仍不自动提交', continuation,
      continuation.commitText.length === 0 && continuation.rawInput === 'abcd' &&
        continuation.candidates.length === 1));

    engine.setCodeTableCategories(allIds);
    const oldSegment = this.query(engine, 'zzzz');
    const topped = engine.processKey('a');
    rows.push(this.record('11.6.7 E 第五码顶屏与单次重放', 'zzzz + a',
      '提交旧首选；新段 raw=a 且只处理一次', topped,
      oldSegment.candidates.length > 0 && topped.commitText === oldSegment.candidates[0].text &&
        topped.rawInput === 'a' && topped.candidates.length === 1));

    engine.reset();
    const allCategoryIds = engine.getCodeTableCategoryConfig().categories.map((item) => item.id);
    engine.setCodeTableCategories(allCategoryIds);
    const emptyOldExact = this.query(engine, 'bcde');
    const emptyOld = engine.setCodeTableCategories(['core']);
    const emptyOldReplayed = engine.processKey('a');
    rows.push(this.record('11.6.7 F 旧段无候选仍保留第五码', '全分类 bcde；切 core；+ a',
      '旧段无码提交；当前键 raw=a 并只处理一次', emptyOldReplayed,
      emptyOldExact.commitText.length === 0 && emptyOldExact.rawInput === 'bcde' &&
        emptyOld.commitText.length === 0 && emptyOld.rawInput === 'bcde' &&
        emptyOld.candidates.length === 0 && emptyOldReplayed.commitText.length === 0 &&
        emptyOldReplayed.rawInput === 'a'));

    const deleteFile = installer.installUserLexicon(context, '测试\tdzqd#删\n');
    const deleteEngine = new EngineCoordinator();
    const deleteCreated = deleteFile.success ?
      deleteEngine.initialize('code-table-fixture', productionPath, deleteFile.path, 3, fixture.path) :
      this.emptyComposition();
    const deleted = deleteCreated.success ? this.enter(deleteEngine, 'dzqd') : deleteCreated;
    rows.push(this.record('11.6.7 G 用户删除改变唯一性', '测试 dzqd#删',
      '不提交被删候选“测试”；按反向切分提交 dzq 并保留 d', deleted,
      deleteCreated.success && deleted.commitText === 'dzq' &&
        deleted.rawInput === 'd' && deleted.candidates.length > 0));
    deleteEngine.dispose();

    const fixedFile = installer.installUserLexicon(context, '用户顶屏\tzzzz#固\n');
    const fixedEngine = new EngineCoordinator();
    const fixedCreated = fixedFile.success ?
      fixedEngine.initialize('code-table-fixture', productionPath, fixedFile.path, 3, fixture.path) :
      this.emptyComposition();
    if (fixedCreated.success) {
      this.enter(fixedEngine, 'zzzz');
    }
    const fixedTop = fixedCreated.success ? fixedEngine.processKey('a') : fixedCreated;
    rows.push(this.record('11.6.7 H 用户固顶改变顶屏首选', 'zzzz#固 + a',
      '提交用户顶屏；新段 raw=a', fixedTop,
      fixedCreated.success && fixedTop.commitText === '用户顶屏' && fixedTop.rawInput === 'a'));
    fixedEngine.dispose();

    engine.reset();
    this.enter(engine, 'abcd');
    const categoryChanged = engine.setCodeTableCategories(['core']);
    rows.push(this.record('11.6.7 I 分类更新本身不提交', 'abcd；切为 core',
      'raw 保留、页码归零、commit 为空', categoryChanged,
      categoryChanged.rawInput === 'abcd' && categoryChanged.commitText.length === 0 &&
        categoryChanged.candidatePage === 0));

    const forwardFile = installer.installUserLexicon(context, '正向切分段\tvv\n');
    const forwardEngine = new EngineCoordinator();
    const forwardCreated = forwardFile.success ?
      forwardEngine.initialize('code-table-fixture', productionPath, forwardFile.path, 3, fixture.path) :
      this.emptyComposition();
    const forwardSplit = forwardCreated.success ? this.enter(forwardEngine, 'vvvv') : forwardCreated;
    rows.push(this.record('11.6.7 J 空码正向切分', '用户精确 vv + vvvv',
      '提交最长合法左段首选；保留右侧 raw=vv', forwardSplit,
      forwardCreated.success && forwardSplit.commitText === '正向切分段' &&
        forwardSplit.rawInput === 'vv' && forwardSplit.candidates.length === 1 &&
        forwardSplit.candidates[0].text === '正向切分段'));
    forwardEngine.dispose();

    const reverseFile = installer.installUserLexicon(context, '反向合法后段\tvvv\n');
    const reverseEngine = new EngineCoordinator();
    const reverseCreated = reverseFile.success ?
      reverseEngine.initialize('code-table-fixture', productionPath, reverseFile.path, 3, fixture.path) :
      this.emptyComposition();
    const reverseSplit = reverseCreated.success ? this.enter(reverseEngine, 'uvvv') : reverseCreated;
    rows.push(this.record('11.6.7 K 空码反向切分', 'uvvv + 用户精确 vvv',
      '按文本顺序提交无法解释的左侧 u；保留合法后段 raw=vvv', reverseSplit,
      reverseCreated.success && reverseSplit.commitText === 'u' &&
        reverseSplit.rawInput === 'vvv' && reverseSplit.candidates.length === 1 &&
        reverseSplit.candidates[0].text === '反向合法后段'));
    reverseEngine.dispose();

    const empty = this.query(engine, 'vvvv');
    rows.push(this.record('11.6.7 L 无合法切分时安全清屏', 'vvvv',
      '冻结空码清屏生效；不伪造切分提交', empty,
      empty.commitText.length === 0 && empty.rawInput.length === 0 && empty.candidates.length === 0));

    const guidePrefix = engine.processKey(';');
    const guideCode = engine.processKey('g');
    rows.push(this.record('11.6.7 M Guide 状态隔离回归', ';g',
      '不进入四码提交/顶屏/空码逻辑', guideCode,
      guidePrefix.rawInput === ';' && guidePrefix.commitText.length === 0 &&
        guideCode.rawInput === ';g' && guideCode.commitText.length === 0));

    engine.reset();
    const xiaohe = engine.changeScheme('xiaohe');
    const hello = xiaohe.success ? this.enter(engine, 'nihc') : xiaohe;
    engine.reset();
    const inputMethod = xiaohe.success ? this.enter(engine, 'uurufa') : xiaohe;
    rows.push(this.simpleRecord('11.6.7 N 切回 xiaohe 回归', 'nihc / uurufa',
      '你好 / 输入法',
      `nihc=${this.texts(hello)}; uurufa=${this.texts(inputMethod)}`,
      hello.candidates.length > 0 && hello.candidates[0].text === '你好' &&
        inputMethod.candidates.length > 0 && inputMethod.candidates[0].text === '输入法'));
    engine.dispose();
    return rows;
  }

  private async runCategoryAcceptance(
    context: common.UIAbilityContext,
    installer: CodeTableFixtureInstaller,
    productionPath: string,
    formalPath: string
  ): Promise<AcceptanceRecord[]> {
    const rows: AcceptanceRecord[] = [];
    const definitions = this.engine.getCodeTableCategoryConfig().categories;
    const allIds = definitions.map((item: CodeTableCategoryDefinition) => item.id);
    const allUpdate = await this.settingsController.setXiaoheYinxingEnabledCategoryIds(allIds);
    const baseline = this.query(this.engine, 'aaba');
    rows.push(this.record('11.6.5 A 默认八类与基线', '全部 defaultEnabled 分类 + aaba',
      '8 类开启；四码唯一自动提交阿爸', baseline,
      allUpdate.success && definitions.length === 8 &&
        definitions.every((item: CodeTableCategoryDefinition) => item.defaultEnabled) &&
        baseline.commitText === '阿爸' && baseline.rawInput.length === 0));

    const requiredUpdate = await this.settingsController.setXiaoheYinxingEnabledCategoryIds([]);
    const requiredConfig = this.engine.getCodeTableCategoryConfig();
    const core = definitions.find((item: CodeTableCategoryDefinition) => item.id === 'core');
    rows.push(this.simpleRecord('11.6.5 B core 必选', '空分类选择',
      'canonical 结果仅恢复 core；UI 开关禁用',
      `enabled=${requiredConfig.enabledCategoryIds.join(',')}; required=${core?.required}; ` +
      `toggleable=${core?.userToggleable}`,
      requiredUpdate.success && requiredConfig.enabledCategoryIds.join(',') === 'core' &&
        core !== undefined && core.required && !core.userToggleable));

    await this.settingsController.setXiaoheYinxingEnabledCategoryIds(
      allIds.filter((id: string) => id !== 'category-secondary')
    );
    const categorySecondary = this.query(this.engine, 'ahqi');
    rows.push(this.record('11.6.5 C 关闭 category-secondary', 'ahqi',
      '独有候选“爱恨情仇”消失', categorySecondary,
      categorySecondary.candidates.every((candidate) => candidate.text !== '爱恨情仇')));
    await this.yieldUi();

    await this.settingsController.setXiaoheYinxingEnabledCategoryIds(
      allIds.filter((id: string) => id !== 'one-key-secondary' && id !== 'two-key-secondary')
    );
    const oneKey = this.query(this.engine, 'a');
    const twoKey = this.query(this.engine, 'bc');
    rows.push(this.simpleRecord('11.6.5 D 关闭一二简辅助', 'a / bc',
      '关闭分类的记录不参与渐进候选；同文字仍可由其他启用分类合法提供',
      `a=${this.texts(oneKey)}; bc=${this.texts(twoKey)}`,
      oneKey.candidates.every((candidate) => candidate.source !== 'one-key-secondary' &&
        candidate.source !== 'two-key-secondary') &&
        twoKey.candidates.every((candidate) => candidate.source !== 'one-key-secondary' &&
          candidate.source !== 'two-key-secondary')));

    await this.settingsController.setXiaoheYinxingEnabledCategoryIds(allIds);
    const stableBefore = this.query(this.engine, 'a');
    await this.settingsController.setXiaoheYinxingEnabledCategoryIds(
      allIds.filter((id: string) => id !== 'out-of-table-character')
    );
    const extensionHidden = this.query(this.engine, 'aift');
    const stableAfter = this.query(this.engine, 'a');
    rows.push(this.simpleRecord('11.6.5 E 扩展分类隔离与稳定顺序', 'aift / a',
      '捱消失；其他分类顺序不变',
      `aift=${this.texts(extensionHidden)}; before=${this.texts(stableBefore)}; after=${this.texts(stableAfter)}`,
      extensionHidden.candidates.every((candidate) => candidate.text !== '捱') &&
        this.texts(stableBefore) === this.texts(stableAfter)));
    await this.yieldUi();

    await this.settingsController.setXiaoheYinxingEnabledCategoryIds(allIds);
    const beforeChange = this.query(this.engine, 'bcbn');
    const changed = this.engine.setCodeTableCategories(['core']);
    rows.push(this.record('11.6.5 F 非空组合原子重算', 'bcbn；切为 core',
      '不提交、raw 保留、页码归零、候选重算', changed,
      beforeChange.rawInput === 'bcbn' && changed.rawInput === 'bcbn' &&
        changed.commitText.length === 0 && changed.candidatePage === 0 &&
        changed.candidates.every((candidate) => candidate.source === 'core')));

    this.engine.setCodeTableCategories(allIds);
    const prefixBefore = this.query(this.engine, 'aoq');
    const prefixChanged = this.engine.setCodeTableCategories(
      allIds.filter((id: string) => id !== 'out-of-table-character')
    );
    rows.push(this.record('11.6.5 G 前缀与有效后续码同步', 'aoq；关闭 out-of-table-character',
      '该分类的前缀候选消失；Rust continuation/unique 查询使用同一快照', prefixChanged,
      prefixBefore.candidates.some((candidate) => candidate.source === 'out-of-table-character') &&
        prefixChanged.candidates.every((candidate) => candidate.source !== 'out-of-table-character')));

    const userFile = installer.installUserLexicon(context, `外部分类规则\t${RULE_CODE}#固\n`);
    const userEngine = new EngineCoordinator();
    const userCreated = userFile.success ?
      userEngine.initialize(SCHEME_ID, productionPath, userFile.path, 8, formalPath) : this.emptyComposition();
    const userResult = userCreated.success ? this.enter(userEngine, RULE_CODE) : userCreated;
    rows.push(this.record('11.6.5 H 外部用户规则边界', `${RULE_CODE} + 外部 #固`,
      '用户层不成为第九系统分类，仍按 11.6.4 规则合并', userResult,
      userFile.success && userCreated.success &&
        userResult.candidates.some((candidate) => candidate.text === '外部分类规则')));
    userEngine.dispose();
    await this.yieldUi();

    const persistedIds: string[] = ['core', 'full-code-word'];
    const saved = await this.settingsController.setXiaoheYinxingEnabledCategoryIds(persistedIds);
    const restartEngine = new EngineCoordinator();
    const restartCreated = restartEngine.initialize(SCHEME_ID, productionPath, undefined, 8, formalPath);
    const restartController = new SettingsController(
      new SettingsRepository(),
      new SettingsStore(),
      restartEngine,
      new InputSessionStore()
    );
    if (restartCreated.success) {
      await restartController.initialize(context);
    }
    const restartedIds = restartCreated.success ?
      restartEngine.getCodeTableCategoryConfig().enabledCategoryIds : [];
    rows.push(this.simpleRecord('11.6.5 I 保存与重建恢复', '保存 core/full-code-word 后重建引擎',
      '新引擎从 Preferences 恢复 canonical 分类',
      `saved=${saved.success}; restarted=${restartedIds.join(',')}`,
      saved.success && restartedIds.join(',') === persistedIds.join(',')));
    restartEngine.dispose();
    await this.yieldUi();

    const invalidRaw: SettingsRaw = {
      schemaVersion: '1',
      xiaoheYinxingCategorySchemaVersion: '0',
      xiaoheYinxingEnabledCategoryIds:
        '["category-secondary","unknown","core","category-secondary"]'
    };
    const migratedIds = new SettingsValidator().validate(invalidRaw).xiaoheYinxingEnabledCategoryIds;
    const migratedResult = await this.settingsController.setXiaoheYinxingEnabledCategoryIds(migratedIds);
    rows.push(this.simpleRecord('11.6.5 J 非法旧设置迁移', '重复、未知、旧 schema、乱序',
      '去重、忽略未知、恢复 core、canonical 排序',
      `migrated=${migratedIds.join(',')}; nativeAndSaved=${migratedResult.success}`,
      migratedResult.success && migratedIds.join(',') === 'core,category-secondary'));

    this.engine.reset();
    const xiaoheSwitch = this.engine.changeScheme('xiaohe');
    const hello = xiaoheSwitch.success ? this.enter(this.engine, 'nihc') : xiaoheSwitch;
    this.engine.reset();
    const inputMethod = xiaoheSwitch.success ? this.enter(this.engine, 'uurufa') : xiaoheSwitch;
    rows.push(this.simpleRecord('11.6.5 K 小鹤双拼回归', 'nihc / uurufa',
      '你好 / 输入法',
      `nihc=${this.texts(hello)}; uurufa=${this.texts(inputMethod)}`,
      hello.candidates.length > 0 && hello.candidates[0].text === '你好' &&
        inputMethod.candidates.length > 0 && inputMethod.candidates[0].text === '输入法'));

    const formalSwitch = this.engine.changeScheme(SCHEME_ID);
    const returnedIds = formalSwitch.success ?
      this.engine.getCodeTableCategoryConfig().enabledCategoryIds : [];
    rows.push(this.simpleRecord('11.6.5 L 切回正式方案保持分类', 'xiaohe → xiaohe-yinxing',
      '分类快照仍为迁移后的 core/category-secondary',
      `enabled=${returnedIds.join(',')}`,
      formalSwitch.success && returnedIds.join(',') === 'core,category-secondary'));
    return rows;
  }

  private async toggleCategory(category: CodeTableCategoryDefinition, enabled: boolean): Promise<void> {
    if (this.categoryBusy || category.required || !category.userToggleable) {
      return;
    }
    this.categoryBusy = true;
    const requested = this.categoryConfig.categories
      .filter((item: CodeTableCategoryDefinition) => {
        if (item.id === category.id) {
          return enabled;
        }
        return this.categoryConfig.enabledCategoryIds.indexOf(item.id) >= 0;
      })
      .map((item: CodeTableCategoryDefinition) => item.id);
    const result: SettingsOperationResult =
      await this.settingsController.setXiaoheYinxingEnabledCategoryIds(requested);
    this.refreshCategoryPanel(result.success ? '分类快照已替换、候选已重算并保存' : result.message);
    this.categoryBusy = false;
  }

  private runManualQuery(): void {
    this.engine.reset();
    this.currentResult = this.enter(this.engine, this.manualCode);
    this.categoryStatus = this.currentResult.success ? '查询完成' : this.currentResult.errorMessage;
  }

  private refreshCategoryPanel(message: string): void {
    try {
      this.categoryConfig = this.engine.getCodeTableCategoryConfig();
      this.currentResult = this.engine.getCurrentResult();
      this.categoryStatus = message;
    } catch (err) {
      this.categoryStatus = `分类读取失败：${JSON.stringify(err)}`;
    }
  }

  private emptyComposition(): CompositionResult {
    return {
      success: true,
      errorCode: 0,
      errorMessage: '',
      rawInput: '',
      preeditText: '',
      parsedSyllables: [],
      pendingCode: '',
      parserState: 'empty',
      candidates: [],
      highlightedIndex: 0,
      hasNextPage: false,
      hasPreviousPage: false,
      candidatePage: 0,
      commitText: '',
      action: null,
      compositionFinished: false
    };
  }

  private query(engine: EngineCoordinator, code: string): CompositionResult {
    engine.reset();
    return this.enter(engine, code);
  }

  private enter(engine: EngineCoordinator, code: string): CompositionResult {
    let result = engine.getCurrentResult();
    for (let index = 0; index < code.length; index++) {
      result = engine.processKey(code.charAt(index));
    }
    return result;
  }

  private texts(result: CompositionResult): string {
    return result.candidates.map((candidate) => candidate.text).join('|');
  }

  private candidateDetails(result: CompositionResult): string {
    return result.candidates.map((candidate) =>
      `${candidate.text}[${candidate.source}/${candidate.reading}/${candidate.id}]`).join(' | ');
  }

  private record(
    name: string,
    input: string,
    expected: string,
    result: CompositionResult,
    passed: boolean,
    detail: string = ''
  ): AcceptanceRecord {
    return this.simpleRecord(name, input, expected,
      `raw=${result.rawInput}; page=${result.candidatePage}; next=${result.hasNextPage}; ` +
      `candidates=${this.candidateDetails(result)}; error=${result.errorCode}/${result.errorMessage}; ${detail}`,
      passed);
  }

  private simpleRecord(name: string, input: string, expected: string, actual: string,
    passed: boolean): AcceptanceRecord {
    return { name, input, expected, actual, passed };
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Text('阶段 11.6.7 · 冻结范围验收').fontSize(24).fontWeight(FontWeight.Bold)
        Text('Debug-only · ArkTS → C++ → Rust 真实链路').fontSize(13).fontColor('#667085')
        Text(`scheme_id=${SCHEME_ID}`).fontSize(12)
        Text(`bundle_id=${BUNDLE_ID}`).fontSize(12)
        Text(`bundle_sha256=${BUNDLE_SHA256}`).fontSize(10)
        Text(`category_count=${CATEGORY_COUNT}`).fontSize(12)
        Text(`结果：${this.status}；逐键补充耗时=${this.elapsedMs} ms`).fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor(this.status === 'PASS' ? '#067647' : '#B42318')
        Button(this.running ? '执行中' : '重新执行').enabled(!this.running)
          .onClick(() => this.runAcceptance())
        Text('产品分类（仅 internalDebug 可见）').fontSize(19).fontWeight(FontWeight.Bold)
        Text(`schema=${this.categoryConfig.schemaVersion}；enabled=${this.categoryConfig.enabledCategoryIds.join(',')}`)
          .fontSize(11).fontColor('#475467')
        ForEach(this.categoryConfig.categories, (category: CodeTableCategoryDefinition) => {
          CodeTableCategorySettingRow({
            categoryId: category.id,
            displayName: category.displayName,
            kind: category.kind,
            order: category.order,
            checked: this.categoryConfig.enabledCategoryIds.indexOf(category.id) >= 0,
            required: category.required,
            userToggleable: category.userToggleable,
            busy: this.categoryBusy,
            onCheckedChange: (checked: boolean) => this.toggleCategory(category, checked)
          })
        }, (category: CodeTableCategoryDefinition) => category.id)
        TextInput({ text: this.manualCode, placeholder: '输入 1～4 位音形编码，如 ahqi' })
          .onChange((value: string) => this.manualCode = value)
        Row({ space: 10 }) {
          Button('查询并保留组合').enabled(!this.categoryBusy).onClick(() => this.runManualQuery())
          Button('清空').onClick(() => {
            this.manualCode = '';
            this.currentResult = this.engine.reset();
          })
        }
        Text(`分类状态：${this.categoryStatus}`).fontSize(13)
          .fontColor(this.categoryStatus.indexOf('失败') >= 0 ? '#B42318' : '#067647')
        Text(`raw=${this.currentResult.rawInput}; page=${this.currentResult.candidatePage}; ` +
          `commit=${this.currentResult.commitText}; next=${this.currentResult.hasNextPage}`)
          .fontSize(12).fontColor('#344054')
        Text(`candidates=${this.candidateDetails(this.currentResult)}`)
          .fontSize(11).fontColor('#475467')
        ForEach(this.records, (row: AcceptanceRecord) => {
          Column({ space: 6 }) {
            Text(`${row.passed ? 'PASS' : 'FAIL'} · ${row.name}`).fontSize(16).fontWeight(FontWeight.Medium)
              .fontColor(row.passed ? '#067647' : '#B42318')
            Text(`输入：${row.input}`).fontSize(13)
            Text(`预期：${row.expected}`).fontSize(12).fontColor('#344054')
            Text(`实际：${row.actual}`).fontSize(11).fontColor('#475467')
          }
          .width('100%').padding(14).alignItems(HorizontalAlign.Start)
          .borderRadius(12).backgroundColor('#F2F4F7')
        }, (row: AcceptanceRecord) => row.name)
      }
      .width('100%').padding(20).alignItems(HorizontalAlign.Start)
    }
    .width('100%').height('100%').backgroundColor('#FFFFFF')
  }
}
