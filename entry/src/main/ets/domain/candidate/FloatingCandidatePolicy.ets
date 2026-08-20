import { KeyboardDeviceFormFactor } from '../display/KeyboardAuxiliaryAreaPolicy';
import { CandidatePresentationMode } from '../settings/ImeSettings';

/**
 * Stage 3.8: 候选展示模式规则集中在本文件；持久化 enum 定义在
 * `domain/settings/ImeSettings.ets`。同一枚举，两处一致。
 */
export const DEFAULT_CANDIDATE_PRESENTATION_MODE: CandidatePresentationMode =
  CandidatePresentationMode.AUTO;

/**
 * 能力探针输入。SDK 层的实际能力检查放在 infrastructure，
 * 但决策规则本身必须是纯函数。
 */
export interface FloatingCandidateCapability {
  /** SDK 是否支持 FLAG_CANDIDATE 面板（API 15+）与 cursorContextChange 事件（API 8+）。 */
  sdkSupportsPanel: boolean;
  sdkSupportsCursorEvent: boolean;
  /** 会话是否处于可以创建候选面板的状态：inputStart 完成、编辑器允许候选栏、非密码。 */
  sessionAllowsPanel: boolean;
  /** 本次会话是否已经收到过至少一次有效 cursor 锚点。用于判断宿主是否真的会推送。 */
  hasReceivedCursorAnchor: boolean;
  /** 是否检测到外接物理键盘。当前只能通过 configuration 推断，缺省 false。 */
  hasPhysicalKeyboard: boolean;
  formFactor: KeyboardDeviceFormFactor;
}

/**
 * 完整 SDK 能力、有效会话和可靠锚点是所有独立候选窗的共同门禁。
 * AUTO 继续只为带实体键盘的 Pad/2in1 启用电脑候选窗；显式 FLOATING
 * 则供 Phone/Pad 触屏设置选择“输入框下方”，由控制器使用可与固定键盘
 * 共存的 STATUS_BAR 面板承载。BAR 始终是安全降级入口。
 */
export function resolveEffectivePresentationMode(
  requestedMode: CandidatePresentationMode,
  capability: FloatingCandidateCapability
): CandidatePresentationMode {
  const platformReady = capability.sdkSupportsPanel && capability.sdkSupportsCursorEvent &&
    capability.sessionAllowsPanel && capability.hasReceivedCursorAnchor;
  if (!platformReady || requestedMode === CandidatePresentationMode.BAR) {
    return CandidatePresentationMode.BAR;
  }
  if (requestedMode === CandidatePresentationMode.FLOATING) {
    return CandidatePresentationMode.FLOATING;
  }
  const hardwareCandidateWindow = capability.formFactor === KeyboardDeviceFormFactor.TABLET &&
    capability.hasPhysicalKeyboard;
  return hardwareCandidateWindow ? CandidatePresentationMode.FLOATING : CandidatePresentationMode.BAR;
}
