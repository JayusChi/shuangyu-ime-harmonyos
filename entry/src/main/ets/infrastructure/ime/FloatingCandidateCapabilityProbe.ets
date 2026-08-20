import deviceInfo from '@ohos.deviceInfo';
import { Logger } from '../../common/logging/Logger';

const TAG = 'FloatingCandidateCapabilityProbe';
const LOGGER = new Logger(TAG);

/** `PanelFlag.FLAG_CANDIDATE` since API 15；`cursorContextChange` since API 8. */
const MIN_PANEL_API: number = 15;
const MIN_CURSOR_EVENT_API: number = 8;
// Computer remediation stage 1 verified the complete API-24 candidate-panel
// lifecycle, while stages 2 and 3 supplied exclusive panel ownership and a
// hardware-input closed loop. Stage 4 therefore enables the verified route A.
const CANDIDATE_PANEL_FORMAL_PATH_ENABLED: boolean = true;

export interface FloatingCandidateSdkCapability {
  sdkApiLevel: number;
  sdkSupportsPanel: boolean;
  sdkSupportsCursorEvent: boolean;
}

/**
 * 静态 SDK 能力：只读取当前设备的 `deviceInfo.sdkApiVersion`，与运行会话无关。
 * 该能力决定是否**有资格**创建 `FLAG_CANDIDATE` 面板和监听 `cursorContextChange`；
 * 是否**实际可用**由会话/宿主锚点决定，另外一层策略负责。
 *
 * 只输出能力，不创建窗口，不订阅事件——避免"能力探测"变成"能力副作用"。
 */
export class FloatingCandidateCapabilityProbe {
  private cached?: FloatingCandidateSdkCapability;

  probe(): FloatingCandidateSdkCapability {
    if (this.cached) {
      return this.cached;
    }
    const apiLevel = this.readSdkApiLevel();
    const capability: FloatingCandidateSdkCapability = {
      sdkApiLevel: apiLevel,
      sdkSupportsPanel: apiLevel >= MIN_PANEL_API && CANDIDATE_PANEL_FORMAL_PATH_ENABLED,
      sdkSupportsCursorEvent: apiLevel >= MIN_CURSOR_EVENT_API
    };
    LOGGER.info(
      `capability probed: sdkApiLevel=${apiLevel}, sdkSupportsPanel=${capability.sdkSupportsPanel}, ` +
        `sdkSupportsCursorEvent=${capability.sdkSupportsCursorEvent}`
    );
    this.cached = capability;
    return capability;
  }

  private readSdkApiLevel(): number {
    try {
      const raw = deviceInfo.sdkApiVersion;
      if (Number.isFinite(raw) && raw > 0) {
        return raw;
      }
    } catch (err) {
      LOGGER.warn(`deviceInfo.sdkApiVersion query failed: ${JSON.stringify(err)}`);
    }
    return 0;
  }
}

let SHARED_PROBE: FloatingCandidateCapabilityProbe | undefined;

export function getSharedFloatingCandidateCapabilityProbe(): FloatingCandidateCapabilityProbe {
  if (!SHARED_PROBE) {
    SHARED_PROBE = new FloatingCandidateCapabilityProbe();
  }
  return SHARED_PROBE;
}
