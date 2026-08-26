import fs from "node:fs/promises";
import path from "node:path";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const outputDir = process.cwd();
const projectRoot = path.resolve(outputDir, "..", "..");
const sourcePath = path.join(projectRoot, "双羽词库分类", "双羽词库", "5.直通.txt");
const outputPath = path.join(outputDir, "0.5.0_客户44条直通映射确认表.xlsx");

const STATUS_DIRECT = "可直接实现";
const STATUS_CONFIRM = "需要客户确认";
const STATUS_REJECT = "平台不支持/安全拒绝";

const mapping = [
  { line: 2, intent: "复制内容反查编码", proposal: "仅对用户明确粘贴或当前输入内容执行本地反查；不静默读取剪贴板。", status: STATUS_CONFIRM, basis: "需确认反查对象、返回格式，以及是否接受取消自动读剪贴板。", version: "待客户确认" },
  { line: 3, intent: "插入本地日期（yyyy年M月d日）", proposal: "映射到受控 DATE_TIME_TEXT 白名单，每次触发只读取一次本机时间。", status: STATUS_DIRECT, basis: "纯本地文本生成，无网络、文件或系统控制副作用。", version: "审批后纳入" },
  { line: 4, intent: "插入 ISO 日期（yyyy-MM-dd）", proposal: "映射到受控 DATE_TIME_TEXT/DATE_ISO。", status: STATUS_DIRECT, basis: "现有日期白名单协议可承载。", version: "审批后纳入" },
  { line: 5, intent: "插入紧凑日期时间（cttg:yMdHm）", proposal: "新增固定格式 ID；输出示例需由客户冻结后再实现。", status: STATUS_CONFIRM, basis: "cttg 占位符含义与补零规则不明确。", version: "待客户确认" },
  { line: 6, intent: "插入时间和星期（HH:mm ddd）", proposal: "新增固定的“时:分 + 星期”本地格式 ID。", status: STATUS_DIRECT, basis: "可安全实现，但需作为枚举白名单而非解释任意格式串。", version: "审批后纳入" },
  { line: 7, intent: "插入中文时间（H点m分）", proposal: "新增固定中文时间格式 ID。", status: STATUS_DIRECT, basis: "纯本地文本生成，可纳入时间白名单。", version: "审批后纳入" },
  { line: 9, intent: "打开小鹤官网", proposal: "在用户选中候选后，仅打开批准的固定 HTTPS 白名单地址。", status: STATUS_CONFIRM, basis: "需客户确认会离开当前应用，并确认域名白名单与失败提示。", version: "待客户确认" },
  { line: 10, intent: "插入小鹤官网 URL 文本", proposal: "按普通静态文本上屏；若客户要打开网页，改走固定 HTTPS 白名单动作。", status: STATUS_DIRECT, basis: "原记录不是 run()，按静态文本处理最安全且语义稳定。", version: "审批后纳入" },
  { line: 11, intent: "打开小鹤网盘（HTTP）", proposal: "拒绝原 HTTP 地址；客户提供并确认 HTTPS 官方地址后，可作为固定白名单动作。", status: STATUS_REJECT, basis: "明文 HTTP 不满足安全基线，且不能自动升级到未知 HTTPS 地址。", version: "拒绝原样实现" },
  { line: 12, intent: "打开小鹤入门页", proposal: "在用户选中候选后打开固定 HTTPS 白名单地址。", status: STATUS_CONFIRM, basis: "需要客户批准外部跳转及域名白名单。", version: "待客户确认" },
  { line: 13, intent: "打开小鹤入门指定章节", proposal: "在用户选中候选后打开固定 HTTPS 白名单地址并保留锚点。", status: STATUS_CONFIRM, basis: "需要客户确认链接长期稳定及外部跳转口径。", version: "待客户确认" },
  { line: 15, intent: "打开输入法设置", proposal: "打开本应用设置首页，不执行来源字符串。", status: STATUS_DIRECT, basis: "应用内受控路由，目标固定。", version: "审批后纳入" },
  { line: 16, intent: "重载输入法配置", proposal: "限定为重新加载设置、分类和用户词库；失败时保留上一份有效快照。", status: STATUS_CONFIRM, basis: "需客户确认“重载”是否包含主码表、用户词频或仅配置。", version: "待客户确认" },
  { line: 17, intent: "重载输入法配置（备用编码）", proposal: "与上一条共用同一受控重载动作。", status: STATUS_CONFIRM, basis: "两个编码可同义映射，但重载范围需客户冻结。", version: "待客户确认" },
  { line: 18, intent: "静音/系统音量控制", proposal: "不提供全局静音；可改为切换本输入法按键音开关。", status: STATUS_REJECT, basis: "第三方输入法不应模拟系统键码或改变全局媒体状态。", version: "仅考虑安全替代" },
  { line: 20, intent: "显示配置/安装目录", proposal: "不暴露沙箱路径；可改为打开“数据管理/导入导出”页面。", status: STATUS_REJECT, basis: "HarmonyOS 应用沙箱目录不是客户可直接浏览的安装目录。", version: "仅考虑安全替代" },
  { line: 21, intent: "打开用户词库", proposal: "打开应用内“用户词库”管理页，不按路径直接打开沙箱文件。", status: STATUS_DIRECT, basis: "项目已有用户词库管理能力，可用固定应用内路由承载。", version: "审批后纳入" },
  { line: 22, intent: "导入用户词库", proposal: "触发已授权的 IMPORT_USER_LEXICON；通过系统文件选择器选择来源并原子导入。", status: STATUS_DIRECT, basis: "现有受控动作协议已支持，且不绕过系统文件授权。", version: "审批后纳入" },
  { line: 24, intent: "简体/繁体切换", proposal: "若客户确认范围，新增应用内转换开关并只使用随包批准的转换表。", status: STATUS_CONFIRM, basis: "需确认转换作用于候选、上屏文本还是界面；当前转换资源仍未作为产品能力冻结。", version: "待客户确认" },
  { line: 25, intent: "中文/英文标点切换", proposal: "新增输入法内部标点模式枚举，不注入系统按键。", status: STATUS_DIRECT, basis: "可作为本输入法确定性设置实现。", version: "审批后纳入" },
  { line: 26, intent: "全角/半角切换", proposal: "新增固定字符转换模式；由客户给出字母、数字、空格和标点范围。", status: STATUS_CONFIRM, basis: "不同输入法对全半角覆盖范围不一致，必须先冻结规则。", version: "待客户确认" },
  { line: 28, intent: "删除当前行", proposal: "显式触发后读取受限的光标前后文本，只删除当前行并进行会话/边界复核。", status: STATUS_DIRECT, basis: "可复用安全删除执行器；宿主不提供文本查询时应拒绝而非猜测。", version: "审批后纳入" },
  { line: 29, intent: "删除当前行（备用编码）", proposal: "与上一条共用同一受控删行动作。", status: STATUS_DIRECT, basis: "两个编码可同义映射，仍执行边界与会话校验。", version: "审批后纳入" },
  { line: 31, intent: "显示嵌入编码", proposal: "可改为候选栏/预编辑区显示编码提示，不修改宿主正文。", status: STATUS_CONFIRM, basis: "需确认“嵌入”是预编辑显示、候选注音还是直接上屏。", version: "待客户确认" },
  { line: 32, intent: "关闭嵌入编码", proposal: "与上一条共用显示开关。", status: STATUS_CONFIRM, basis: "依赖客户先冻结嵌入编码的显示位置与生命周期。", version: "待客户确认" },
  { line: 34, intent: "将当前内容加入用户词库", proposal: "打开带预填内容的用户词条确认页，用户确认编码、动作和位置后保存。", status: STATUS_CONFIRM, basis: "需确认取词范围、编码生成方式以及是否允许无二次确认。", version: "待客户确认" },
  { line: 37, intent: "智能句号延迟设为 600ms", proposal: "映射到 smartPeriodTimeoutMs=600 的受控设置。", status: STATUS_DIRECT, basis: "现有设置已接受 0–2000ms，并以串行事务持久化。", version: "审批后纳入" },
  { line: 38, intent: "关闭智能句号", proposal: "映射到 smartPeriodTimeoutMs=0。", status: STATUS_DIRECT, basis: "现有设置可直接承载。", version: "审批后纳入" },
  { line: 39, intent: "数字后的标点使用句点", proposal: "新增固定“数字标点”策略；先确认中文/英文模式及小数输入优先级。", status: STATUS_CONFIRM, basis: "必须避免把小数点、网址和连续数字误改。", version: "待客户确认" },
  { line: 40, intent: "关闭数字标点策略", proposal: "恢复默认数字输入行为。", status: STATUS_CONFIRM, basis: "依赖上一条策略范围先冻结。", version: "待客户确认" },
  { line: 42, intent: "自动使用浏览器搜索", proposal: "拒绝无目标、无白名单的自动外部搜索；可改为用户确认后的固定搜索提供方。", status: STATUS_REJECT, basis: "原命令缺少目标和数据边界，可能泄露输入内容并触发未批准外部跳转。", version: "仅考虑安全替代" },
  { line: 43, intent: "用百度搜索当前词", proposal: "仅在用户显式触发后，对当前已确认文本 URL 编码并打开固定 HTTPS 搜索模板。", status: STATUS_CONFIRM, basis: "需确认发送内容范围、隐私提示、搜索提供方及退出当前应用的体验。", version: "待客户确认" },
  { line: 44, intent: "将光标前文本和剪贴板内容发送到汉典", proposal: "拒绝自动拼接剪贴板；可改为只发送用户明确选定/确认的单段文本。", status: STATUS_REJECT, basis: "静默读取并向外部站点发送剪贴板/编辑器内容违反最小数据原则。", version: "仅考虑安全替代" },
  { line: 45, intent: "将光标前文本和剪贴板内容发送到字统", proposal: "拒绝自动拼接剪贴板；可改为只发送用户明确选定/确认的单段文本。", status: STATUS_REJECT, basis: "静默读取并向外部站点发送剪贴板/编辑器内容违反最小数据原则。", version: "仅考虑安全替代" },
  { line: 47, intent: "4 码空码自动清除", proposal: "新增确定性空码清理策略，并保留上一份有效配置。", status: STATUS_CONFIRM, basis: "需确认“空码”的判定时机、是否保留末键及对顶屏的影响。", version: "待客户确认" },
  { line: 48, intent: "12 码空码自动清除", proposal: "与上一条共用阈值设置，阈值限定为批准值。", status: STATUS_CONFIRM, basis: "需确认 12 的用途以及与最大编码长度的关系。", version: "待客户确认" },
  { line: 49, intent: "四码后顶屏", proposal: "新增固定四码顶屏策略并补充空码/第五码回归测试。", status: STATUS_CONFIRM, basis: "需客户给出候选唯一、多候选、空码及标点情况下的精确期望。", version: "待客户确认" },
  { line: 50, intent: "四码唯一候选自动上屏", proposal: "只在四码且唯一候选时自动提交；其余情况保持候选态。", status: STATUS_CONFIRM, basis: "源参数含疑似拼写 ime-aotu，需确认确切语义和与上一条的优先级。", version: "待客户确认" },
  { line: 52, intent: "切换为熟手分类预设", proposal: "映射到固定 category.set 预设，不解析来源参数串。", status: STATUS_CONFIRM, basis: "需客户确认“全码词/全码字/生僻字”的启停集合及 core 必保规则。", version: "待客户确认" },
  { line: 53, intent: "切换为常规分类预设", proposal: "映射到固定 category.set 预设。", status: STATUS_CONFIRM, basis: "需客户确认常规预设的完整分类集合。", version: "待客户确认" },
  { line: 54, intent: "切换为初学分类预设", proposal: "映射到固定 category.set 预设。", status: STATUS_CONFIRM, basis: "源命令括号疑似不完整，且需冻结初学预设的完整分类集合。", version: "待客户确认" },
  { line: 55, intent: "启用二简次选", proposal: "映射到 category.enable(two-key-secondary)。", status: STATUS_DIRECT, basis: "现有直通控制和分类白名单可直接承载。", version: "审批后纳入" },
  { line: 56, intent: "关闭二简次选", proposal: "映射到 category.disable(two-key-secondary)。", status: STATUS_DIRECT, basis: "现有直通控制和分类白名单可直接承载。", version: "审批后纳入" },
  { line: 58, intent: "插入《静夜思》固定多行文本", proposal: "作为受控静态文本一次上屏，保留明确换行。", status: STATUS_DIRECT, basis: "内容固定、无外部副作用；不解释为命令。", version: "审批后纳入" }
];

if (mapping.length !== 44) {
  throw new Error(`Expected 44 mappings, got ${mapping.length}`);
}

const sourceText = await fs.readFile(sourcePath, "utf8");
const sourceLines = sourceText.replace(/^\uFEFF/, "").split(/\r?\n/);

function sourceRecord(lineNumber) {
  const raw = sourceLines[lineNumber - 1];
  if (raw === undefined || raw.trim().length === 0) {
    throw new Error(`Missing source line ${lineNumber}`);
  }
  const lastTab = raw.lastIndexOf("\t");
  if (lastTab < 0) {
    throw new Error(`Source line ${lineNumber} has no code separator`);
  }
  return { definition: raw.slice(0, lastTab), code: raw.slice(lastTab + 1).trim() };
}

const rows = mapping.map((item, index) => {
  const source = sourceRecord(item.line);
  return [
    index + 1,
    item.line,
    source.code,
    source.definition,
    item.intent,
    item.proposal,
    item.status,
    item.basis,
    "",
    "",
    "待项目审批",
    item.version
  ];
});

const workbook = Workbook.create();
const overview = workbook.worksheets.add("客户确认总览");
const detail = workbook.worksheets.add("44条逐项映射");
const policy = workbook.worksheets.add("口径与审批");

const colors = {
  navy: "#17365D",
  blue: "#2F75B5",
  paleBlue: "#D9EAF7",
  green: "#E2F0D9",
  greenText: "#276221",
  amber: "#FFF2CC",
  amberText: "#8A5A00",
  red: "#FCE4D6",
  redText: "#9C0006",
  gray: "#F2F2F2",
  border: "#C9D3DF",
  white: "#FFFFFF",
  edit: "#FFF9E6"
};

function titleBand(sheet, range, text) {
  sheet.getRange(range).merge();
  const cell = sheet.getRange(range.split(":")[0]);
  cell.values = [[text]];
  cell.format = {
    fill: colors.navy,
    font: { bold: true, color: colors.white, size: 18 },
    verticalAlignment: "center",
    horizontalAlignment: "left"
  };
}

// Overview
overview.showGridLines = false;
titleBand(overview, "A1:H1", "0.5.0 客户 44 条“直通”需求确认表");
overview.getRange("A1:H1").format.rowHeight = 34;
overview.getRange("A2:H2").merge();
overview.getRange("A2").values = [["版本：客户确认稿 v1｜来源：5.直通.txt｜生成日期：2026-08-25"]];
overview.getRange("A2").format = { fill: colors.paleBlue, font: { color: colors.navy }, verticalAlignment: "center" };
overview.getRange("A4:H4").merge();
overview.getRange("A4").values = [["重要：表内 $cmd、URL 和路径均仅作为客户需求文本展示，不会被本项目解析或执行。只有客户确认且项目再次审批后的固定白名单动作才会进入实现。"]];
overview.getRange("A4").format = { fill: colors.amber, font: { bold: true, color: colors.amberText }, wrapText: true, verticalAlignment: "center" };
overview.getRange("A4:H4").format.rowHeight = 48;

overview.getRange("A6:H6").values = [["记录总数", "", STATUS_DIRECT, "", STATUS_CONFIRM, "", STATUS_REJECT, ""]];
for (const range of ["A6:B6", "C6:D6", "E6:F6", "G6:H6"]) overview.getRange(range).merge();
overview.getRange("A6:H6").format = { fill: colors.blue, font: { bold: true, color: colors.white }, horizontalAlignment: "center", verticalAlignment: "center" };
for (const range of ["A7:B9", "C7:D9", "E7:F9", "G7:H9"]) overview.getRange(range).merge();
overview.getRange("A7").formulas = [["=COUNTA('44条逐项映射'!$A$5:$A$48)"]];
overview.getRange("C7").formulas = [[`=COUNTIF('44条逐项映射'!$G$5:$G$48,"${STATUS_DIRECT}")`]];
overview.getRange("E7").formulas = [[`=COUNTIF('44条逐项映射'!$G$5:$G$48,"${STATUS_CONFIRM}")`]];
overview.getRange("G7").formulas = [[`=COUNTIF('44条逐项映射'!$G$5:$G$48,"${STATUS_REJECT}")`]];
overview.getRange("A7:B9").format = { fill: colors.gray, font: { bold: true, color: colors.navy, size: 22 }, horizontalAlignment: "center", verticalAlignment: "center", borders: { preset: "outside", style: "thin", color: colors.border } };
overview.getRange("C7:D9").format = { fill: colors.green, font: { bold: true, color: colors.greenText, size: 22 }, horizontalAlignment: "center", verticalAlignment: "center", borders: { preset: "outside", style: "thin", color: colors.border } };
overview.getRange("E7:F9").format = { fill: colors.amber, font: { bold: true, color: colors.amberText, size: 22 }, horizontalAlignment: "center", verticalAlignment: "center", borders: { preset: "outside", style: "thin", color: colors.border } };
overview.getRange("G7:H9").format = { fill: colors.red, font: { bold: true, color: colors.redText, size: 22 }, horizontalAlignment: "center", verticalAlignment: "center", borders: { preset: "outside", style: "thin", color: colors.border } };

overview.getRange("A11:H11").merge();
overview.getRange("A11").values = [["客户填写说明"]];
overview.getRange("A11").format = { fill: colors.navy, font: { bold: true, color: colors.white }, verticalAlignment: "center" };
const instructions = [
  "1. 请在“44条逐项映射”I 列逐项选择：同意建议实现 / 按原需求实现（请说明） / 不需要 / 待讨论。",
  "2. 若选择“按原需求实现”，请在 J 列补充期望、示例和边界；涉及 URL 的项目请确认域名、数据范围和是否允许跳出当前应用。",
  "3. “可直接实现”表示技术与安全路径明确，不等于已经交付；以 K 列“项目最终结论”和后续验收报告为准。",
  "4. “平台不支持/安全拒绝”表示原行为不能原样实现；客户可确认表内安全替代方案。"
];
instructions.forEach((value, index) => {
  const row = 12 + index;
  overview.getRange(`A${row}:H${row}`).merge();
  overview.getRange(`A${row}`).values = [[value]];
  overview.getRange(`A${row}`).format = { fill: index % 2 === 0 ? colors.gray : colors.white, wrapText: true, verticalAlignment: "center" };
  overview.getRange(`A${row}:H${row}`).format.rowHeight = 32;
});

overview.getRange("A18:H18").merge();
overview.getRange("A18").values = [["客户确认信息"]];
overview.getRange("A18").format = { fill: colors.navy, font: { bold: true, color: colors.white } };
overview.getRange("A19:H22").values = [
  ["客户单位", "", "确认人", "", "确认日期", "", "适用版本", "0.5.x"],
  ["总体结论", "", "", "", "", "", "", ""],
  ["补充说明", "", "", "", "", "", "", ""],
  ["签字/盖章", "", "", "", "", "", "", ""]
];
overview.getRange("A19:A22").format = { fill: colors.paleBlue, font: { bold: true, color: colors.navy } };
overview.getRange("C19").format = { fill: colors.paleBlue, font: { bold: true, color: colors.navy } };
overview.getRange("E19").format = { fill: colors.paleBlue, font: { bold: true, color: colors.navy } };
overview.getRange("G19").format = { fill: colors.paleBlue, font: { bold: true, color: colors.navy } };
overview.getRange("B19:B19").merge();
overview.getRange("D19:D19").merge();
overview.getRange("F19:F19").merge();
overview.getRange("B20:H20").merge();
overview.getRange("B21:H21").merge();
overview.getRange("B22:H22").merge();
overview.getRange("B19:H22").format.fill = colors.edit;
overview.getRange("A19:H22").format.borders = { preset: "all", style: "thin", color: colors.border };
overview.getRange("A1:H22").format.font.name = "Microsoft YaHei";
overview.getRange("A1:H22").format.wrapText = true;
overview.getRange("A:H").format.columnWidth = 16;
overview.freezePanes.freezeRows(2);

// Detail sheet
detail.showGridLines = false;
titleBand(detail, "A1:L1", "44 条直通需求逐项映射");
detail.getRange("A2:L2").merge();
detail.getRange("A2").values = [["I、J 列由客户填写；K、L 列由项目组在审批后填写。原始定义仅展示，不执行。"]];
detail.getRange("A2").format = { fill: colors.amber, font: { bold: true, color: colors.amberText }, verticalAlignment: "center" };
detail.getRange("A4:L4").values = [[
  "序号", "来源行", "客户编码", "客户原始定义", "意图解读", "建议安全实现", "初步分类", "主要依据/限制",
  "客户确认", "客户补充说明", "项目最终结论", "计划版本"
]];
detail.getRange("A5:L48").values = rows;
const table = detail.tables.add("A4:L48", true, "DirectMappingTable");
table.style = "TableStyleMedium2";
table.showFilterButton = true;
detail.getRange("A4:L4").format = { fill: colors.navy, font: { bold: true, color: colors.white }, horizontalAlignment: "center", verticalAlignment: "center", wrapText: true };
detail.getRange("A5:C48").format.horizontalAlignment = "center";
detail.getRange("G5:I48").format.horizontalAlignment = "center";
detail.getRange("K5:L48").format.horizontalAlignment = "center";
detail.getRange("D5:L48").format.wrapText = true;
detail.getRange("A5:L48").format.verticalAlignment = "top";
detail.getRange("I5:J48").format.fill = colors.edit;
detail.getRange("K5:L48").format.fill = colors.gray;
detail.getRange("I5:I48").dataValidation = { rule: { type: "list", values: ["同意建议实现", "按原需求实现（请说明）", "不需要", "待讨论"] } };
detail.getRange("K5:K48").dataValidation = { rule: { type: "list", values: ["待项目审批", "批准实现", "拒绝", "已实现"] } };
const statusRange = detail.getRange("G5:G48");
statusRange.conditionalFormats.add("containsText", { text: STATUS_DIRECT, format: { fill: colors.green, font: { color: colors.greenText, bold: true } } });
statusRange.conditionalFormats.add("containsText", { text: STATUS_CONFIRM, format: { fill: colors.amber, font: { color: colors.amberText, bold: true } } });
statusRange.conditionalFormats.add("containsText", { text: STATUS_REJECT, format: { fill: colors.red, font: { color: colors.redText, bold: true } } });
detail.getRange("A1:L48").format.font.name = "Microsoft YaHei";
detail.getRange("A1:L1").format.rowHeight = 34;
detail.getRange("A2:L2").format.rowHeight = 28;
detail.getRange("A4:L4").format.rowHeight = 36;
detail.getRange("A5:L48").format.rowHeight = 58;
const widths = [7, 8, 13, 46, 28, 42, 22, 44, 25, 36, 18, 14];
widths.forEach((width, index) => detail.getRangeByIndexes(0, index, 48, 1).format.columnWidth = width);
detail.freezePanes.freezeRows(4);
detail.freezePanes.freezeColumns(3);

// Policy sheet
policy.showGridLines = false;
titleBand(policy, "A1:H1", "确认口径、安全边界与审批流程");
policy.getRange("A1:H1").format.rowHeight = 34;
policy.getRange("A3:H3").merge();
policy.getRange("A3").values = [["一、三类结论怎么理解"]];
policy.getRange("A3").format = { fill: colors.blue, font: { bold: true, color: colors.white } };
const categoryNotes = [
  [STATUS_DIRECT, "平台和项目受控协议存在明确、安全的实现路径；仍需客户确认需求并由项目组审批后开发。", colors.green],
  [STATUS_CONFIRM, "目标可做，但语义、数据范围、交互或安全替代尚未冻结；客户回复前不进入实现。", colors.amber],
  [STATUS_REJECT, "原行为不能原样交付，例如任意命令执行、明文 HTTP、静默剪贴板外发、全局系统控制或绕过沙箱路径。", colors.red]
];
categoryNotes.forEach((note, index) => {
  const row = 4 + index;
  policy.getRange(`A${row}:B${row}`).merge();
  policy.getRange(`C${row}:H${row}`).merge();
  policy.getRange(`A${row}`).values = [[note[0]]];
  policy.getRange(`C${row}`).values = [[note[1]]];
  policy.getRange(`A${row}:H${row}`).format = { fill: note[2], wrapText: true, verticalAlignment: "center", borders: { preset: "outside", style: "thin", color: colors.border } };
  policy.getRange(`A${row}`).format.font = { bold: true, color: colors.navy };
  policy.getRange(`A${row}:H${row}`).format.rowHeight = 42;
});

policy.getRange("A9:H9").merge();
policy.getRange("A9").values = [["二、为什么不能把 44 条原文直接执行"]];
policy.getRange("A9").format = { fill: colors.blue, font: { bold: true, color: colors.white } };
const boundaryNotes = [
  "客户文件中的 $cmd、URL、路径和占位符属于需求输入，不属于项目可执行代码；应用不会解释任意命令字符串。",
  "“#直”候选语义与“执行动作”不同：普通 #直 记录可作为候选文本，但命令/URL 型记录必须经过固定动作 ID、参数白名单和跨层校验。",
  "外部网页仅允许：用户显式触发 + 固定 HTTPS 域名/模板 + 最小数据范围 + URL 编码 + 明确失败提示。",
  "文件仅允许通过系统选择器授权，应用不读取任意绝对路径；剪贴板和编辑器正文不自动发送到第三方。",
  "现有已批准动作（重复、条件撤销、六组成对符号、行末定位、受控方案/分类、授权用户词库导入）继续有效，不因本表自动扩大。"
];
boundaryNotes.forEach((value, index) => {
  const row = 10 + index;
  policy.getRange(`A${row}:H${row}`).merge();
  policy.getRange(`A${row}`).values = [[`${index + 1}. ${value}`]];
  policy.getRange(`A${row}`).format = { fill: index % 2 === 0 ? colors.gray : colors.white, wrapText: true, verticalAlignment: "center" };
  policy.getRange(`A${row}:H${row}`).format.rowHeight = 38;
});

policy.getRange("A17:H17").merge();
policy.getRange("A17").values = [["三、审批流程"]];
policy.getRange("A17").format = { fill: colors.blue, font: { bold: true, color: colors.white } };
const flow = [
  ["1 客户逐项确认", "填写 I/J 列；对“按原需求实现”给出示例、边界和验收标准。"],
  ["2 项目安全/产品审批", "项目组填写 K/L 列，冻结固定动作 ID、参数、权限和失败行为。"],
  ["3 开发与自动化测试", "只实现批准项，补齐 ArkTS、Native/Rust、持久化和回滚测试。"],
  ["4 设备验收", "在 Phone、Pad、2in1 按批准口径逐项复验并形成可追溯证据。"]
];
flow.forEach((item, index) => {
  const row = 18 + index;
  policy.getRange(`A${row}:B${row}`).merge();
  policy.getRange(`C${row}:H${row}`).merge();
  policy.getRange(`A${row}`).values = [[item[0]]];
  policy.getRange(`C${row}`).values = [[item[1]]];
  policy.getRange(`A${row}:B${row}`).format = { fill: colors.paleBlue, font: { bold: true, color: colors.navy }, verticalAlignment: "center" };
  policy.getRange(`C${row}:H${row}`).format = { fill: colors.white, wrapText: true, verticalAlignment: "center" };
  policy.getRange(`A${row}:H${row}`).format.borders = { preset: "outside", style: "thin", color: colors.border };
  policy.getRange(`A${row}:H${row}`).format.rowHeight = 38;
});
policy.getRange("A23:H23").merge();
policy.getRange("A23").values = [["源文件：双羽词库分类/双羽词库/5.直通.txt；本表共引用 44 条非空命令或 URL 记录，来源行号保留在逐项表 B 列。"]];
policy.getRange("A23").format = { fill: colors.gray, font: { italic: true, color: colors.navy }, wrapText: true };
policy.getRange("A1:H23").format.font.name = "Microsoft YaHei";
policy.getRange("A:H").format.columnWidth = 18;
policy.freezePanes.freezeRows(1);

const summaryInspect = await workbook.inspect({
  kind: "table",
  range: "客户确认总览!A1:H15",
  include: "values,formulas",
  tableMaxRows: 15,
  tableMaxCols: 8,
  maxChars: 5000
});
console.log(summaryInspect.ndjson);
const detailInspect = await workbook.inspect({
  kind: "table",
  range: "44条逐项映射!A4:L10",
  include: "values,formulas",
  tableMaxRows: 7,
  tableMaxCols: 12,
  maxChars: 6000
});
console.log(detailInspect.ndjson);
const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 100 },
  summary: "final formula error scan"
});
console.log(errors.ndjson);

for (const [sheetName, range, fileName, scale] of [
  ["客户确认总览", "A1:H22", "preview-overview.png", 1.2],
  ["44条逐项映射", "A1:L48", "preview-detail.png", 0.7],
  ["口径与审批", "A1:H23", "preview-policy.png", 1.0]
]) {
  const preview = await workbook.render({ sheetName, range, scale, format: "png" });
  await fs.writeFile(path.join(outputDir, fileName), new Uint8Array(await preview.arrayBuffer()));
}

const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);
console.log(JSON.stringify({ outputPath, records: rows.length }));
