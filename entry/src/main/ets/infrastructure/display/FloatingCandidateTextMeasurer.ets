import { UIContext } from '@kit.ArkUI';

/** The panel provides its own font environment after its component exists. */
export class FloatingCandidateTextMeasurer {
  private context?: UIContext;
  private listeners: (() => void)[] = [];

  bind(context: UIContext): void {
    this.context = context;
    this.listeners.slice().forEach((listener: () => void): void => listener());
  }

  unbind(context: UIContext): void {
    if (this.context === context) { this.context = undefined; }
  }

  subscribe(listener: () => void): void { this.listeners.push(listener); }
  unsubscribe(listener: () => void): void {
    this.listeners = this.listeners.filter((item: () => void): boolean => item !== listener);
  }

  widthVp(label: string, fontSize: number, density: number): number {
    if (this.context === undefined) { return Number.NaN; }
    try {
      const size = this.context.getMeasureUtils().measureTextSize({
        textContent: label, fontSize: fontSize, fontWeight: '500'
      });
      return Number(size.width) / Math.max(1, density);
    } catch (_) { return Number.NaN; }
  }
}

const sharedMeasurer = new FloatingCandidateTextMeasurer();
export function getSharedFloatingCandidateTextMeasurer(): FloatingCandidateTextMeasurer { return sharedMeasurer; }
