import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

export class Logger {
  private readonly tag: string;

  constructor(tag: string) {
    this.tag = tag;
  }

  debug(message: string): void {
    hilog.debug(DOMAIN, this.tag, message);
  }

  info(message: string): void {
    hilog.info(DOMAIN, this.tag, message);
  }

  warn(message: string): void {
    hilog.warn(DOMAIN, this.tag, message);
  }

  error(message: string): void {
    hilog.error(DOMAIN, this.tag, message);
  }
}
