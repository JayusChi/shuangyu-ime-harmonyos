import { Logger } from '../common/logging/Logger';
import { DELETE_REPEAT_CONFIG } from '../presentation/keyboard/design/KeyboardMetrics';

const TAG = 'DeleteRepeatController';
const LOGGER = new Logger(TAG);

/**
 * 删除重复控制器
 * 负责管理长按删除的重复触发逻辑
 */
export class DeleteRepeatController {
  private longPressTimer: number | null = null;
  private repeatTimer: number | null = null;
  private repeatCount: number = 0;
  private isActive: boolean = false;
  private readonly onDelete: () => void;
  private longPressDelayMs: number;

  constructor(onDelete: () => void, longPressDelayMs: number = DELETE_REPEAT_CONFIG.LONG_PRESS_DELAY_MS) {
    this.onDelete = onDelete;
    this.longPressDelayMs = longPressDelayMs;
  }

  setLongPressDelayMs(longPressDelayMs: number): void {
    if (this.longPressDelayMs === longPressDelayMs) {
      return;
    }
    this.stop();
    this.longPressDelayMs = longPressDelayMs;
  }

  /**
   * 开始长按检测
   */
  start(): void {
    // 如果已经激活，不重复启动
    if (this.isActive) {
      LOGGER.debug('delete repeat already active, ignoring start');
      return;
    }

    this.isActive = true;
    this.repeatCount = 0;

    // 设置长按等待计时器
    this.longPressTimer = setTimeout(() => {
      this.longPressTimer = null;
      this.startRepeat();
    }, this.longPressDelayMs);

    LOGGER.debug('delete repeat started');
  }

  /**
   * 停止删除重复
   */
  stop(): void {
    this.clearAllTimers();
    this.isActive = false;
    this.repeatCount = 0;
    LOGGER.debug('delete repeat stopped');
  }

  /**
   * 销毁控制器，清理所有资源
   */
  destroy(): void {
    this.stop();
    LOGGER.debug('delete repeat controller destroyed');
  }

  /**
   * 检查是否正在激活状态
   */
  isActivated(): boolean {
    return this.isActive;
  }

  /**
   * 触发单次删除（短按）
   */
  triggerSingleDelete(): void {
    if (!this.isActive) {
      this.onDelete();
      LOGGER.debug('single delete triggered');
    }
  }

  /**
   * 开始重复删除
   */
  private startRepeat(): void {
    if (!this.isActive) {
      return;
    }

    // 立即执行第一次删除
    this.onDelete();
    this.repeatCount++;

    // 设置重复计时器
    this.scheduleNextRepeat();
  }

  /**
   * 调度下一次重复
   */
  private scheduleNextRepeat(): void {
    if (!this.isActive) {
      return;
    }

    // 根据重复次数决定间隔时间（加速）
    const interval = this.repeatCount >= DELETE_REPEAT_CONFIG.FAST_REPEAT_THRESHOLD
      ? DELETE_REPEAT_CONFIG.FAST_REPEAT_INTERVAL_MS
      : DELETE_REPEAT_CONFIG.REPEAT_INTERVAL_MS;

    this.repeatTimer = setTimeout(() => {
      if (!this.isActive) {
        return;
      }

      this.repeatTimer = null;
      this.onDelete();
      this.repeatCount++;

      // 继续调度下一次
      this.scheduleNextRepeat();
    }, interval);
  }

  /**
   * 清理所有计时器
   */
  private clearAllTimers(): void {
    if (this.longPressTimer !== null) {
      clearTimeout(this.longPressTimer);
      this.longPressTimer = null;
    }

    if (this.repeatTimer !== null) {
      clearTimeout(this.repeatTimer);
      this.repeatTimer = null;
    }
  }
}
