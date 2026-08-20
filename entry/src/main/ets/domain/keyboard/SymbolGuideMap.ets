/**
 * 分号符号引导键映射表
 *
 * 当实体键盘无第二候选时，按分号进入符号引导模式，
 * 下一个字母按键查找此映射表，输出对应符号。
 *
 * 映射参考小鹤音形符号引导常见配置。
 */

const SYMBOL_GUIDE_TABLE: Record<string, string> = {
  'a': '……',
  'b': '、',
  'c': 'ˉ',
  'd': '￥',
  'e': '€',
  'f': '·',
  'g': '—',
  'h': '#',
  'i': '》',
  'j': '【',
  'k': '】',
  'l': '「',
  'm': '？',
  'n': '！',
  'o': '（',
  'p': '）',
  'q': '；',
  'r': '《',
  's': '……',
  't': '＆',
  'u': '」',
  'v': '℃',
  'w': '～',
  'x': '：',
  'y': '、',
  'z': '％'
};

/**
 * Look up the symbol for a given guide letter.
 * Returns undefined if the letter has no mapping.
 */
export function resolveSymbolGuide(letter: string): string | undefined {
  if (letter.length !== 1) {
    return undefined;
  }
  const key = letter.toLowerCase();
  return SYMBOL_GUIDE_TABLE[key];
}
