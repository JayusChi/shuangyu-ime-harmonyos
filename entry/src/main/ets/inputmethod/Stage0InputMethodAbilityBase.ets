import Want from '@ohos.app.ability.Want';
import { InputMethodExtensionAbility, InputMethodSubtype, inputMethodEngine } from '@kit.IMEKit';
import { InputMethodLifecycleDispatcher } from '../application/InputMethodLifecycleDispatcher';
import { Logger } from '../common/logging/Logger';
import { Configuration, ConfigurationConstant } from '@kit.AbilityKit';
import { getSharedSettingsController } from '../application/SettingsController';
import { HarmonySystemThemeBackend, SystemThemeMonitor } from '../application/SystemThemeMonitor';
import { Action, KeyEvent } from '@kit.InputKit';
import { getSharedKeyboardLayoutPreferenceController } from '../application/KeyboardLayoutPreferenceController';
import { ImeSettings } from '../domain/settings/ImeSettings';
import {
  PhysicalKeySnapshot,
  PhysicalKeyStartupDeferral
} from '../domain/keyboard/PhysicalKeyboardRouting';
import {
  LegacyPhysicalKeyState,
  PhysicalKeyEventChannel,
  PhysicalKeyEventDeduplicator
} from '../domain/keyboard/PhysicalKeyEventCompatibility';

const TAG = 'Stage0InputMethodAbility';
const LOGGER = new Logger(TAG);

export default class Stage0InputMethodAbilityBase extends InputMethodExtensionAbility {
  private imeAbility?: inputMethodEngine.InputMethodAbility;
  private keyboardDelegate?: inputMethodEngine.KeyboardDelegate;
  private readonly lifecycleDispatcher: InputMethodLifecycleDispatcher = new InputMethodLifecycleDispatcher();
  private registered = false;
  private runtimeReady = false;
  private runtimeGeneration = 0;
  private runtimeInitialization?: Promise<void>;
  private systemThemeMonitor?: SystemThemeMonitor;
  private readonly startupPhysicalKeys = new PhysicalKeyStartupDeferral();
  private readonly legacyPhysicalKeys = new LegacyPhysicalKeyState();
  private readonly physicalKeyEvents = new PhysicalKeyEventDeduplicator();

  private readonly onInputStart = (
    keyboardController: inputMethodEngine.KeyboardController,
    inputClient: inputMethodEngine.InputClient
  ): void => {
    this.resetPhysicalKeyCompatibilityState();
    this.runAfterInitialization((): void => {
      this.systemThemeMonitor?.refresh();
      this.lifecycleDispatcher.handleInputStart(keyboardController, inputClient);
    });
  };

  private readonly onInputStop = (): void => {
    this.resetPhysicalKeyCompatibilityState();
    this.runAfterInitialization((): void => this.lifecycleDispatcher.handleInputStop());
  };

  private readonly onKeyboardShow = (): void => {
    this.runAfterInitialization((): void => {
      this.systemThemeMonitor?.refresh();
      this.lifecycleDispatcher.handleKeyboardShow();
    });
  };

  private readonly onKeyboardHide = (): void => {
    this.runAfterInitialization((): void => this.lifecycleDispatcher.handleKeyboardHide());
  };

  private readonly onDiscardTypingText = (): void => {
    this.runAfterInitialization((): void => this.lifecycleDispatcher.handleDiscardTypingText());
  };

  private readonly onCursorContextChange = (x: number, y: number, height: number): void => {
    this.runAfterInitialization((): void => this.lifecycleDispatcher.handleCursorContextChange(x, y, height));
  };

  private readonly onSetSubtype = (subtype: InputMethodSubtype): void => {
    LOGGER.info(`input method subtype selected: id=${subtype.id}, locale=${subtype.locale}`);
  };

  private readonly onPhysicalKeyEvent = (event: KeyEvent): boolean => {
    return this.dispatchPhysicalKeySnapshot(
      this.snapshotPhysicalKeyEvent(event),
      PhysicalKeyEventChannel.MODERN
    );
  };

  private readonly onLegacyPhysicalKeyDown = (event: inputMethodEngine.KeyEvent): boolean => {
    return this.dispatchPhysicalKeySnapshot(
      this.legacyPhysicalKeys.snapshot(event.keyCode, true),
      PhysicalKeyEventChannel.LEGACY
    );
  };

  private readonly onLegacyPhysicalKeyUp = (event: inputMethodEngine.KeyEvent): boolean => {
    return this.dispatchPhysicalKeySnapshot(
      this.legacyPhysicalKeys.snapshot(event.keyCode, false),
      PhysicalKeyEventChannel.LEGACY
    );
  };

  private dispatchPhysicalKeySnapshot(
    snapshot: PhysicalKeySnapshot,
    channel: PhysicalKeyEventChannel
  ): boolean {
    const timestampMs = Date.now();
    const duplicateDecision = this.physicalKeyEvents.findDuplicateDecision(channel, snapshot, timestampMs);
    if (duplicateDecision !== undefined) {
      return duplicateDecision;
    }
    let handled = false;
    if (this.runtimeReady) {
      handled = this.lifecycleDispatcher.handlePhysicalKeySnapshot(snapshot);
    } else if (this.startupPhysicalKeys.shouldDefer(snapshot)) {
      // inputStart is registered before the first hardware key, and all queued
      // callbacks share the same initialization promise. Replaying here keeps
      // their arrival order while returning true synchronously prevents the host
      // editor from committing the cold-start letter a second time.
      this.runAfterInitialization((): void => {
        this.lifecycleDispatcher.handleDeferredPhysicalKeyEvent(snapshot);
      });
      handled = true;
    }
    this.physicalKeyEvents.record(channel, snapshot, handled, timestampMs);
    return handled;
  }

  private snapshotPhysicalKeyEvent(event: KeyEvent): PhysicalKeySnapshot {
    return {
      isDown: event.action === Action.DOWN,
      unicodeChar: event.unicodeChar,
      keyCode: event.key.code,
      ctrlKey: event.ctrlKey,
      altKey: event.altKey,
      logoKey: event.logoKey,
      shiftKey: event.shiftKey
    };
  }

  private resetPhysicalKeyCompatibilityState(): void {
    this.legacyPhysicalKeys.reset();
    this.physicalKeyEvents.reset();
  }

  onCreate(want: Want): void {
    LOGGER.info(`InputMethodExtensionAbility onCreate: process=${this.context.processName}`);
    this.imeAbility = inputMethodEngine.getInputMethodAbility();
    this.keyboardDelegate = inputMethodEngine.getKeyboardDelegate();
    const settingsController = getSharedSettingsController();
    const settingsReady = settingsController.initialize(this.context);
    getSharedKeyboardLayoutPreferenceController().initialize(this.context).catch((err: Object): void => {
      LOGGER.warn(`keyboard layout preference initialization failed: ${JSON.stringify(err)}`);
    });
    settingsController.startCrossRuntimeSync();
    this.systemThemeMonitor = new SystemThemeMonitor(
      new HarmonySystemThemeBackend(this.context),
      (isDark: boolean): void => settingsController.setSystemDarkMode(isDark)
    );
    this.systemThemeMonitor.start();
    this.initializeInputMethodRuntime(settingsReady);
  }

  private initializeInputMethodRuntime(settingsReady: Promise<ImeSettings>): void {
    const imeAbility = this.imeAbility;
    const keyboardDelegate = this.keyboardDelegate;
    if (!imeAbility || !keyboardDelegate) {
      LOGGER.warn('InputMethodExtensionAbility runtime unavailable during initialization');
      return;
    }
    if (this.registered) {
      LOGGER.warn('InputMethodExtensionAbility already registered');
      return;
    }
    const generation = ++this.runtimeGeneration;
    this.runtimeReady = false;
    this.registerInputMethodEvents(imeAbility, keyboardDelegate);
    const initialization = this.lifecycleDispatcher.handleAbilityCreate(imeAbility, this.context, settingsReady);
    this.runtimeInitialization = initialization;
    initialization.then((): void => {
      if (generation !== this.runtimeGeneration || this.imeAbility !== imeAbility) {
        this.lifecycleDispatcher.handleAbilityDestroy();
        return;
      }
      this.runtimeReady = true;
      LOGGER.info('InputMethodExtensionAbility runtime ready');
    }).catch((err: Object): void => {
      LOGGER.error(`InputMethodExtensionAbility initialization failed: ${JSON.stringify(err)}`);
    });
  }

  private registerInputMethodEvents(
    imeAbility: inputMethodEngine.InputMethodAbility,
    keyboardDelegate: inputMethodEngine.KeyboardDelegate
  ): void {
    imeAbility.on('inputStart', this.onInputStart);
    imeAbility.on('inputStop', this.onInputStop);
    imeAbility.on('keyboardShow', this.onKeyboardShow);
    imeAbility.on('keyboardHide', this.onKeyboardHide);
    imeAbility.on('discardTypingText', this.onDiscardTypingText);
    imeAbility.on('setSubtype', this.onSetSubtype);
    keyboardDelegate.on('cursorContextChange', this.onCursorContextChange);
    keyboardDelegate.on('keyEvent', this.onPhysicalKeyEvent);
    // HarmonyOS PC hosts can still use the API 8 delegate path. Subscribe to
    // both generations so native desktop editors and ArkUI editors share the
    // same physical-key routing implementation.
    keyboardDelegate.on('keyDown', this.onLegacyPhysicalKeyDown);
    keyboardDelegate.on('keyUp', this.onLegacyPhysicalKeyUp);
    this.registered = true;
  }

  private runAfterInitialization(action: () => void): void {
    const generation = this.runtimeGeneration;
    const initialization = this.runtimeInitialization;
    if (!initialization) {
      return;
    }
    initialization.then((): void => {
      if (generation === this.runtimeGeneration && this.runtimeReady) {
        action();
      }
    }).catch((err: Object): void => {
      LOGGER.warn(`queued input method event discarded: ${JSON.stringify(err)}`);
    });
  }

  onDestroy(): void {
    LOGGER.info('InputMethodExtensionAbility onDestroy');
    this.runtimeGeneration += 1;
    this.runtimeReady = false;
    if (this.imeAbility && this.registered) {
      this.imeAbility.off('inputStart', this.onInputStart);
      this.imeAbility.off('inputStop', this.onInputStop);
      this.imeAbility.off('keyboardShow', this.onKeyboardShow);
      this.imeAbility.off('keyboardHide', this.onKeyboardHide);
      this.imeAbility.off('discardTypingText', this.onDiscardTypingText);
      this.imeAbility.off('setSubtype', this.onSetSubtype);
      this.keyboardDelegate?.off('cursorContextChange', this.onCursorContextChange);
      this.keyboardDelegate?.off('keyEvent', this.onPhysicalKeyEvent);
      this.keyboardDelegate?.off('keyDown', this.onLegacyPhysicalKeyDown);
      this.keyboardDelegate?.off('keyUp', this.onLegacyPhysicalKeyUp);
    }
    this.lifecycleDispatcher.handleAbilityDestroy();
    this.systemThemeMonitor?.stop();
    this.systemThemeMonitor = undefined;
    getSharedSettingsController().stopCrossRuntimeSync();
    this.registered = false;
    this.startupPhysicalKeys.reset();
    this.resetPhysicalKeyCompatibilityState();
    this.runtimeInitialization = undefined;
    this.imeAbility = undefined;
    this.keyboardDelegate = undefined;
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    this.runAfterInitialization((): void => {
      this.systemThemeMonitor?.refresh();
      let preferredIsLandscape: boolean | undefined = undefined;
      if (newConfig.direction === ConfigurationConstant.Direction.DIRECTION_HORIZONTAL) {
        preferredIsLandscape = true;
      } else if (newConfig.direction === ConfigurationConstant.Direction.DIRECTION_VERTICAL) {
        preferredIsLandscape = false;
      }
      this.lifecycleDispatcher.handleConfigurationUpdate(preferredIsLandscape);
    });
  }
}
