/**
 * Stage 4.1: 顶部候选栏"未上屏"输入码回退提示的纯函数状态。
 *
 * HarmonyOS `inputMethodEngine.InputClient.setPreviewText(text, range)` 自 API 12
 * 起签名固定为 `(string, Range)`，没有为输入法暴露样式接口。系统预编辑的视觉
 * 完全由宿主编辑框自行决定，输入法侧不能可靠地强制下划线或颜色。因此本模块
 * 只描述"键盘顶部候选栏"这一唯一由输入法自绘的展示位，用来在任何宿主上给出
 * 一致的"未上屏"提示：非空的组合编码按双拼两码段展示，并用带下划线的
 * 文本装饰渲染。实际分段完全由当前 Rust 解析器提供，既可表示双拼两码段，
 * 也可表示全拼音节段。
 *
 * 该函数不修改引擎状态，不给引擎传分隔符或下划线字符，也不改变候选查询键。
 * 展示层连接引擎分段时插入的 `'` 和下划线装饰只影响 ArkUI `Text` 组件；
 * `rawInput` / `preeditText` 保持原样。
 */

export enum CompositionPreeditDecoration {
  NONE = 'none',
  UNDERLINE = 'underline'
}

export interface CompositionPreeditView {
  /** 是否需要在候选栏中渲染"未上屏"的输入码显示位。 */
  visible: boolean;
  /** 按当前解析器分段后的展示字符串；空输入时为空。 */
  displayText: string;
  /** 装饰类型；仅当 `visible=true` 时使用。 */
  decoration: CompositionPreeditDecoration;
}

export interface CompositionPreeditInput {
  rawInput: string;
  preeditText: string;
  /** Optional engine-provided display path, used by T9 instead of raw digits. */
  preferredDisplayText?: string;
  /** 引擎生成的原始码展示段；UI 只负责使用 `'` 连接。 */
  displaySegments?: string[];
  /** 引擎解析器给出的显式分词边界，单位为原始字母偏移。 */
  segmentBoundaries?: number[];
  /** 引擎解析器给出的未完成尾码；仅用于保持展示协议输入完整。 */
  pendingCode?: string;
}

/**
 * 将引擎提供的展示段连接为候选栏文本。
 *
 * ArkTS 不按长度解析编码。没有分段数据时原样显示 `rawInput`，确保旧引擎或
 * 异常结果不会被 UI 猜测性改写。末尾显式分词边界由 `rawInput` 保留。
 */
export function formatTwoCodePreedit(
  rawInput: string,
  displaySegments?: string[]
): string {
  if (rawInput.length === 0) {
    return '';
  }
  if (!displaySegments || displaySegments.length === 0) {
    return rawInput;
  }
  let output = displaySegments.join("'");
  if (rawInput.endsWith("'") && !output.endsWith("'")) {
    output += "'";
  }
  return output;
}

/**
 * 计算顶部候选栏预编辑显示位。
 *
 * - `rawInput` 为空时不显示，避免残留旧提示。
 * - 展示内容由引擎 `displaySegments` 生成，不使用展开成全拼的
 *   `preeditText`。
 * - 完整编码按解析器音节段展示，未完成尾码由解析器原样提供。
 * - 只要显示，就应用单下划线装饰。
 */
export function resolveCompositionPreeditView(
  input: CompositionPreeditInput
): CompositionPreeditView {
  if (input.rawInput.length === 0) {
    return {
      visible: false,
      displayText: '',
      decoration: CompositionPreeditDecoration.NONE
    };
  }
  return {
    visible: true,
    displayText: input.preferredDisplayText && input.preferredDisplayText.length > 0
      ? input.preferredDisplayText
      : formatTwoCodePreedit(input.rawInput, input.displaySegments),
    decoration: CompositionPreeditDecoration.UNDERLINE
  };
}
