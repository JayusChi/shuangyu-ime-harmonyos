import {
  HarmonyInputMethodSystemBackend,
  InputMethodDescriptor,
  InputMethodSystemBackend
} from '../infrastructure/ime/InputMethodSwitcher';

export interface InputMethodAppOption {
  name: string;
  id: string;
  label: string;
  current: boolean;
}

// Enumerate IME applications, never keyboard profiles or input-method subtypes.
export class InputMethodAppPicker {
  private readonly backend: InputMethodSystemBackend;
  private generation: number = 0;
  private active: boolean = false;
  private switching: boolean = false;
  private ownerName: string = '';
  private options: InputMethodAppOption[] = [];

  constructor(backend: InputMethodSystemBackend = new HarmonyInputMethodSystemBackend()) {
    this.backend = backend;
  }

  isActive(): boolean {
    return this.active;
  }

  async load(): Promise<InputMethodAppOption[]> {
    const generation = ++this.generation;
    this.active = true;
    this.options = [];
    const current = this.backend.getCurrentInputMethod();
    this.ownerName = current.name;
    const enabled = await this.backend.listEnabledInputMethods();
    if (!this.isCurrent(generation)) {
      return [];
    }
    const applications = new Map<string, InputMethodAppOption>();
    enabled.forEach((method: InputMethodDescriptor): void => {
      if (method.name.length === 0 || method.id.length === 0) {
        return;
      }
      const previous = applications.get(method.name);
      if (!previous || (method.name === current.name && method.id === current.id)) {
        applications.set(method.name, {
          name: method.name,
          id: method.id,
          label: method.label?.trim() || method.name,
          current: method.name === current.name
        });
      }
    });
    this.options = Array.from(applications.values());
    return this.options.slice();
  }

  async select(name: string): Promise<boolean> {
    if (!this.active || this.switching) {
      return false;
    }
    const option = this.options.find((item: InputMethodAppOption): boolean => item.name === name);
    if (!option) {
      return false;
    }
    const generation = this.generation;
    this.switching = true;
    try {
      // Refresh enabled applications before switching, so a disabled or removed IME
      // cannot be selected through a stale dialog. Closing the dialog cancels this wait.
      const enabled = await this.backend.listEnabledInputMethods();
      if (!this.isCurrent(generation) || this.backend.getCurrentInputMethod().name !== this.ownerName) {
        return false;
      }
      const target = enabled.find((item: InputMethodDescriptor): boolean =>
        item.name === option.name && item.id === option.id);
      if (!target) {
        return false;
      }
      // Selecting the current app only dismisses the dialog; preserve its keyboard subtype.
      return target.name === this.ownerName || await this.backend.switchToInputMethod(target);
    } catch (_) {
      return false;
    } finally {
      if (generation === this.generation) {
        this.switching = false;
      }
    }
  }

  close(): void {
    this.active = false;
    this.generation += 1;
    this.switching = false;
    this.options = [];
  }

  private isCurrent(generation: number): boolean {
    return this.active && generation === this.generation;
  }
}
