import { EnterAction } from '../domain/editor/EditorContext';

export function enterActionLabel(action: EnterAction): string {
  switch (action) {
    case EnterAction.SEARCH:
      return '搜索';
    case EnterAction.DONE:
      return '完成';
    case EnterAction.NEXT:
      return '下一项';
    case EnterAction.GO:
      return '前往';
    case EnterAction.SEND:
      return '发送';
    default:
      return '回车';
  }
}

export function enterActionAccessibilityText(action: EnterAction): string {
  switch (action) {
    case EnterAction.SEARCH:
      return '执行搜索';
    case EnterAction.DONE:
      return '完成输入';
    case EnterAction.NEXT:
      return '移动到下一项';
    case EnterAction.GO:
      return '前往';
    case EnterAction.SEND:
      return '发送';
    default:
      return '插入换行';
  }
}
