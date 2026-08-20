/**
 * Stage 3.8: 浮动候选窗位置计算。所有单位统一为 px，坐标系为屏幕绝对像素。
 * 该模块是纯函数，禁止依赖 ArkUI、window、display 或 Extension API。
 */

export interface CursorRectPx {
  /** 光标 x（屏幕绝对坐标）。 */
  x: number;
  /** 光标顶端 y（屏幕绝对坐标）。 */
  y: number;
  /** 光标高度；`cursorContextChange` 只给一个数值，宽度按 0 处理。 */
  height: number;
}

export interface WindowRectPx {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

export interface SafeInsetsPx {
  top: number;
  bottom: number;
  left: number;
  right: number;
}

export interface CandidateWindowSizePx {
  widthPx: number;
  heightPx: number;
}

export enum FloatingCandidatePlacement {
  BELOW = 'below',
  ABOVE = 'above'
}

export interface FloatingCandidatePositionPx {
  x: number;
  y: number;
  widthPx: number;
  heightPx: number;
  placement: FloatingCandidatePlacement;
}

export interface FloatingCandidatePositionInput {
  cursorRect: CursorRectPx;
  hostWindowRect: WindowRectPx;
  candidateWindowSize: CandidateWindowSizePx;
  safeInsets: SafeInsetsPx;
  /** 光标与候选窗上下之间的间隙，单位 px。 */
  preferredGapPx: number;
}

function clamp(value: number, min: number, max: number): number {
  if (max < min) {
    return min;
  }
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}

/**
 * §8.1 垂直位置：优先光标下方，下方不足移到上方，两侧都不足则限制高度置于可用区。
 * §8.2 水平位置：默认左边与光标左边对齐；右侧越界靠右，左侧越界靠左；最终硬夹紧。
 * §8.4 输入无效光标 rect 时，调用侧应先做 `isCursorRectUsable` 判断，
 *   本函数不再降级——参数已保证 finite。
 */
export function computeFloatingCandidatePosition(
  input: FloatingCandidatePositionInput
): FloatingCandidatePositionPx {
  const hostLeft = input.hostWindowRect.left + Math.max(0, input.safeInsets.left);
  const hostRight = input.hostWindowRect.right - Math.max(0, input.safeInsets.right);
  const hostTop = input.hostWindowRect.top + Math.max(0, input.safeInsets.top);
  const hostBottom = input.hostWindowRect.bottom - Math.max(0, input.safeInsets.bottom);

  const availableWidth = Math.max(0, hostRight - hostLeft);
  const availableHeight = Math.max(0, hostBottom - hostTop);

  const candidateWidth = clamp(input.candidateWindowSize.widthPx, 0, availableWidth);
  const requestedHeight = clamp(input.candidateWindowSize.heightPx, 0, availableHeight);

  const cursorBottom = input.cursorRect.y + Math.max(0, input.cursorRect.height);
  const gap = Math.max(0, input.preferredGapPx);
  const spaceBelow = Math.max(0, hostBottom - (cursorBottom + gap));
  const spaceAbove = Math.max(0, (input.cursorRect.y - gap) - hostTop);

  let placement: FloatingCandidatePlacement;
  let candidateHeight: number;
  let candidateY: number;

  if (requestedHeight <= spaceBelow) {
    placement = FloatingCandidatePlacement.BELOW;
    candidateHeight = requestedHeight;
    candidateY = cursorBottom + gap;
  } else if (requestedHeight <= spaceAbove) {
    placement = FloatingCandidatePlacement.ABOVE;
    candidateHeight = requestedHeight;
    candidateY = input.cursorRect.y - gap - candidateHeight;
  } else if (spaceBelow >= spaceAbove) {
    placement = FloatingCandidatePlacement.BELOW;
    candidateHeight = Math.min(requestedHeight, spaceBelow);
    candidateY = cursorBottom + gap;
  } else {
    placement = FloatingCandidatePlacement.ABOVE;
    candidateHeight = Math.min(requestedHeight, spaceAbove);
    candidateY = input.cursorRect.y - gap - candidateHeight;
  }

  candidateY = clamp(candidateY, hostTop, Math.max(hostTop, hostBottom - candidateHeight));

  let candidateX = input.cursorRect.x;
  if (candidateX + candidateWidth > hostRight) {
    candidateX = hostRight - candidateWidth;
  }
  if (candidateX < hostLeft) {
    candidateX = hostLeft;
  }
  candidateX = clamp(candidateX, hostLeft, Math.max(hostLeft, hostRight - candidateWidth));

  return {
    x: candidateX,
    y: candidateY,
    widthPx: candidateWidth,
    heightPx: candidateHeight,
    placement
  };
}

/**
 * `cursorContextChange` 可能在极端情况下推送负 height 或 NaN。位置计算前调用侧
 * 必须先校验；不合法时应回退顶部候选栏，而不是移动窗口到旧位置。
 */
export function isCursorRectUsable(rect: CursorRectPx): boolean {
  return Number.isFinite(rect.x) && Number.isFinite(rect.y) &&
    Number.isFinite(rect.height) && rect.height >= 0;
}
