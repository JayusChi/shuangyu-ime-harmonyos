import { describe, expect, it } from '@ohos/hypium';
import { AiAssistController } from '../main/ets/application/AiAssistController';
import { CommitHistoryManager } from '../main/ets/application/CommitHistoryManager';
import { ImeInputService } from '../main/ets/application/ImeInputService';
import { UndoCommitManager } from '../main/ets/application/UndoCommitManager';
import { VerifiedTextReplacer } from '../main/ets/application/VerifiedTextReplacer';
import { VoiceInputController } from '../main/ets/application/VoiceInputController';
import {
  AiAction,
  AiErrorCode,
  AiProviderKind,
  AiProviderResult,
  AiReplacePolicy,
  AiRequest,
  AiRequestState,
  AiSourceOwnership,
  AiSuggestion
} from '../main/ets/domain/ai/AiContracts';
import { EditorContext, EditorKind, EnterAction } from '../main/ets/domain/editor/EditorContext';
import { KeyboardMode } from '../main/ets/domain/keyboard/KeyboardAction';
import { copyImeSettings, DEFAULT_IME_SETTINGS, ImeSettings } from '../main/ets/domain/settings/ImeSettings';
import {
  InputMethodCapabilityState,
  InputMethodSecurityMode,
  MicrophonePermissionState,
  resolveAssistAvailability
} from '../main/ets/domain/security/InputMethodCapabilityState';
import {
  VoiceErrorCode,
  VoiceSessionState
} from '../main/ets/domain/voice/VoiceContracts';
import { AiProvider } from '../main/ets/infrastructure/ai/AiProvider';
import {
  FakeAiProvider,
  FakeAiScenario
} from './support/FakeAiProvider';
import {
  FakeSpeechProvider,
  FakeSpeechScenario
} from './support/FakeSpeechProvider';
import { InputSessionStore } from '../main/ets/state/InputSessionStore';

function wait(milliseconds: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, milliseconds);
  });
}

function normalEditor(): EditorContext {
  return {
    kind: EditorKind.NORMAL_TEXT,
    preferredKeyboardMode: KeyboardMode.CHINESE,
    enterAction: EnterAction.ENTER,
    isPassword: false,
    isMultiline: false,
    learningAllowed: true,
    textPreviewSupported: true,
    candidateBarVisible: true,
    chineseModeAllowed: true,
    englishModeAllowed: true,
    numberModeAllowed: true,
    phoneModeAllowed: false,
    symbolModeAllowed: true,
    numberDecimalAllowed: false
  };
}

function passwordEditor(): EditorContext {
  const editor = normalEditor();
  editor.kind = EditorKind.PASSWORD;
  editor.isPassword = true;
  editor.learningAllowed = false;
  return editor;
}

function fullCapability(): InputMethodCapabilityState {
  return {
    securityMode: InputMethodSecurityMode.FULL,
    microphonePermission: MicrophonePermissionState.NOT_REQUESTED,
    localAiProviderAvailable: false,
    cloudAiProviderAvailable: true,
    speechProviderAvailable: true,
    detectedAtMs: 1
  };
}

function enabledSettings(): ImeSettings {
  const settings = copyImeSettings(DEFAULT_IME_SETTINGS);
  settings.aiEnabled = true;
  settings.cloudAiEnabled = true;
  settings.cloudAiConsentVersion = 1;
  settings.voiceInputEnabled = true;
  return settings;
}

function activeStore(capability: InputMethodCapabilityState = fullCapability()): InputSessionStore {
  const store = new InputSessionStore();
  store.setInputMethodCapabilityState(capability);
  store.markSessionStarted();
  store.applyEditorContext(normalEditor());
  store.markKeyboardVisible();
  return store;
}

class Ai0FakeImeService implements ImeInputService {
  editorText: string = '';
  replaceAllowed: boolean = true;
  insertAllowed: boolean = true;

  async insertText(text: string): Promise<boolean> {
    if (!this.insertAllowed) {
      return false;
    }
    this.editorText += text;
    return true;
  }

  async setPreviewText(_text: string): Promise<boolean> {
    return true;
  }

  async commitPreviewText(text: string): Promise<boolean> {
    return this.insertText(text);
  }

  async finishPreviewText(): Promise<boolean> {
    return true;
  }

  async clearPreviewText(): Promise<boolean> {
    return true;
  }

  async isPreviewTextAttached(): Promise<boolean> {
    return true;
  }

  resetPreviewState(): void {
  }

  async deleteBackward(count: number = 1): Promise<boolean> {
    this.editorText = this.editorText.slice(0, Math.max(0, this.editorText.length - count));
    return true;
  }

  async deleteBackwardIfMatches(text: string): Promise<boolean> {
    if (!this.editorText.endsWith(text)) {
      return false;
    }
    this.editorText = this.editorText.slice(0, this.editorText.length - text.length);
    return true;
  }

  async replaceTextBeforeCursorIfMatches(sourceText: string, replacementText: string): Promise<boolean> {
    if (!this.replaceAllowed || !this.editorText.endsWith(sourceText)) {
      return false;
    }
    this.editorText = `${this.editorText.slice(0, this.editorText.length - sourceText.length)}${replacementText}`;
    return true;
  }

  async sendEnter(): Promise<boolean> {
    return true;
  }

  async hideKeyboard(): Promise<boolean> {
    return true;
  }
}

class PlainTextAiProvider implements AiProvider {
  request(request: AiRequest): Promise<AiProviderResult> {
    const suggestion: AiSuggestion = {
      suggestionId: `${request.requestId}-plain`,
      requestId: request.requestId,
      text: '$cmd open https://example.test <b>hello</b>',
      label: '普通文本',
      providerKind: AiProviderKind.CLOUD,
      replacePolicy: AiReplacePolicy.REPLACE_VERIFIED_SOURCE
    };
    const result: AiProviderResult = {
      success: true,
      requestId: request.requestId,
      providerKind: AiProviderKind.CLOUD,
      suggestions: [suggestion],
      errorCode: AiErrorCode.NONE
    };
    return Promise.resolve(result);
  }

  cancel(_requestId: string): void {
  }
}

export default function ai0FoundationTest() {
  describe('AI-0 capability and lifecycle foundation', () => {
    it('does not notify listeners for equal assist presentation states', 0, () => {
      const store = new InputSessionStore();
      let notifications = 0;
      store.subscribe((): void => {
        notifications += 1;
      });

      store.updateAiPresentation(store.getSnapshot().aiPresentation);
      store.updateVoicePresentation(store.getSnapshot().voicePresentation);
      expect(notifications).assertEqual(0);

      store.updateAiPresentation({
        state: AiRequestState.ACTIONS,
        requestId: '',
        sessionGeneration: 1,
        action: AiAction.POLITE,
        suggestions: [],
        errorCode: AiErrorCode.NONE,
        statusMessage: '选择 AI 动作'
      });
      store.updateAiPresentation({
        state: AiRequestState.ACTIONS,
        requestId: '',
        sessionGeneration: 1,
        action: AiAction.POLITE,
        suggestions: [],
        errorCode: AiErrorCode.NONE,
        statusMessage: '选择 AI 动作'
      });
      expect(notifications).assertEqual(1);

      store.updateVoicePresentation({
        state: VoiceSessionState.LISTENING,
        voiceSessionId: 'voice-1',
        sessionGeneration: 1,
        language: 'zh-CN',
        interimText: '测试',
        finalText: '',
        errorCode: VoiceErrorCode.NONE,
        statusMessage: '正在识别'
      });
      store.updateVoicePresentation({
        state: VoiceSessionState.LISTENING,
        voiceSessionId: 'voice-1',
        sessionGeneration: 1,
        language: 'zh-CN',
        interimText: '测试',
        finalText: '',
        errorCode: VoiceErrorCode.NONE,
        statusMessage: '正在识别'
      });
      expect(notifications).assertEqual(2);
    });

    it('keeps idle input invalidation off the session notification path', 0, () => {
      const store = activeStore();
      const service = new Ai0FakeImeService();
      const aiController = new AiAssistController(
        store,
        (): ImeSettings => enabledSettings(),
        new FakeAiProvider(),
        new VerifiedTextReplacer(service, (): boolean => true),
        (): string | null => null,
        (): void => {}
      );
      const voiceController = new VoiceInputController(
        store,
        (): ImeSettings => enabledSettings(),
        new FakeSpeechProvider(),
        service,
        (): void => {}
      );
      let notifications = 0;
      store.subscribe((): void => {
        notifications += 1;
      });

      aiController.invalidateForInput();
      voiceController.invalidateForInput();

      expect(notifications).assertEqual(0);
      expect(store.getSnapshot().aiPresentation.state).assertEqual(AiRequestState.IDLE);
      expect(store.getSnapshot().voicePresentation.state).assertEqual(VoiceSessionState.IDLE);
    });

    it('blocks cloud AI and voice in basic security mode', 0, () => {
      const capability = fullCapability();
      capability.securityMode = InputMethodSecurityMode.BASIC;
      const availability = resolveAssistAvailability(
        capability,
        normalEditor(),
        enabledSettings(),
        true,
        true
      );
      expect(availability.ai.available).assertFalse();
      expect(availability.voice.available).assertFalse();
    });

    it('blocks AI and voice for password and unknown editors', 0, () => {
      const password = resolveAssistAvailability(
        fullCapability(), passwordEditor(), enabledSettings(), true, true
      );
      expect(password.ai.available).assertFalse();
      expect(password.voice.available).assertFalse();

      const unknown = normalEditor();
      unknown.kind = EditorKind.UNKNOWN;
      const unknownResult = resolveAssistAvailability(
        fullCapability(), unknown, enabledSettings(), true, true
      );
      expect(unknownResult.ai.available).assertFalse();
      expect(unknownResult.voice.available).assertFalse();
    });

    it('blocks both features when settings are off or session is inactive', 0, () => {
      const disabled = resolveAssistAvailability(
        fullCapability(), normalEditor(), copyImeSettings(DEFAULT_IME_SETTINGS), true, true
      );
      expect(disabled.ai.available).assertFalse();
      expect(disabled.voice.available).assertFalse();

      const inactive = resolveAssistAvailability(
        fullCapability(), normalEditor(), enabledSettings(), false, false
      );
      expect(inactive.ai.available).assertFalse();
      expect(inactive.voice.available).assertFalse();
    });

    it('runs deterministic AI suggestions and verified replacement', 0, async () => {
      const store = activeStore();
      const service = new Ai0FakeImeService();
      service.editorText = '原文';
      const provider = new FakeAiProvider();
      provider.setDefaultBehavior({ scenario: FakeAiScenario.SUCCESS, delayMs: 1 });
      const undoManager = new UndoCommitManager(new CommitHistoryManager());
      const replacer = new VerifiedTextReplacer(service, (generation: number): boolean =>
        generation === store.getSessionGeneration());
      const controller = new AiAssistController(
        store,
        (): ImeSettings => enabledSettings(),
        provider,
        replacer,
        (): string | null => '原文',
        (originalText: string, replacementText: string): void =>
          undoManager.recordReplacement(originalText, replacementText),
        50
      );
      await controller.request(AiAction.POLITE);
      const ready = store.getSnapshot().aiPresentation;
      expect(ready.state).assertEqual(AiRequestState.READY);
      expect(ready.suggestions.length).assertEqual(3);
      const applied = await controller.acceptSuggestion(ready.suggestions[0].suggestionId);
      expect(applied).assertTrue();
      expect(service.editorText === '原文').assertFalse();
      expect(store.getSnapshot().aiPresentation.state).assertEqual(AiRequestState.APPLIED);
      const undoState = undoManager.canUndo();
      expect(undoState.replacementOriginalText).assertEqual('原文');
      const reverted = await replacer.replace({
        sessionGeneration: store.getSessionGeneration(),
        sourceText: undoState.lastCommit!,
        replacementText: undoState.replacementOriginalText!,
        sourceOwnership: AiSourceOwnership.LAST_IME_COMMIT
      });
      expect(reverted.success).assertTrue();
      expect(service.editorText).assertEqual('原文');
    });

    it('keeps command-looking model output as inert ordinary text', 0, async () => {
      const store = activeStore();
      const service = new Ai0FakeImeService();
      service.editorText = '原文';
      const controller = new AiAssistController(
        store,
        (): ImeSettings => enabledSettings(),
        new PlainTextAiProvider(),
        new VerifiedTextReplacer(service, (generation: number): boolean =>
          generation === store.getSessionGeneration()),
        (): string | null => '原文',
        (): void => {},
        50
      );
      await controller.request(AiAction.POLITE);
      const suggestion = store.getSnapshot().aiPresentation.suggestions[0];
      expect(suggestion.text).assertContain('$cmd');
      expect(await controller.acceptSuggestion(suggestion.suggestionId)).assertTrue();
      expect(service.editorText).assertEqual('$cmd open https://example.test <b>hello</b>');
    });

    it('does not delete original text when verified replacement fails', 0, async () => {
      const store = activeStore();
      const service = new Ai0FakeImeService();
      service.editorText = '用户原文';
      service.replaceAllowed = false;
      const replacer = new VerifiedTextReplacer(
        service,
        (generation: number): boolean => generation === store.getSessionGeneration()
      );
      const result = await replacer.replace({
        sessionGeneration: store.getSessionGeneration(),
        sourceText: '用户原文',
        replacementText: '建议文本',
        sourceOwnership: AiSourceOwnership.LAST_IME_COMMIT
      });
      expect(result.success).assertFalse();
      expect(service.editorText).assertEqual('用户原文');
    });

    it('times out a non-responsive AI provider and ignores its cancellation completion', 0, async () => {
      const store = activeStore();
      const service = new Ai0FakeImeService();
      service.editorText = '原文';
      const provider = new FakeAiProvider();
      provider.setDefaultBehavior({ scenario: FakeAiScenario.TIMEOUT, delayMs: 0 });
      const controller = new AiAssistController(
        store,
        (): ImeSettings => enabledSettings(),
        provider,
        new VerifiedTextReplacer(service, (): boolean => true),
        (): string | null => '原文',
        (): void => {},
        5
      );
      await controller.request(AiAction.POLITE);
      expect(store.getSnapshot().aiPresentation.errorCode).assertEqual(AiErrorCode.TIMEOUT);
    });

    it('surfaces empty and provider-error AI results without changing editor text', 0, async () => {
      const store = activeStore();
      const service = new Ai0FakeImeService();
      service.editorText = '原文';
      const provider = new FakeAiProvider();
      provider.enqueueBehavior({ scenario: FakeAiScenario.EMPTY, delayMs: 1 });
      provider.enqueueBehavior({ scenario: FakeAiScenario.ERROR, delayMs: 1 });
      const controller = new AiAssistController(
        store,
        (): ImeSettings => enabledSettings(),
        provider,
        new VerifiedTextReplacer(service, (): boolean => true),
        (): string | null => '原文',
        (): void => {},
        50
      );

      await controller.request(AiAction.POLITE);
      expect(store.getSnapshot().aiPresentation.errorCode).assertEqual(AiErrorCode.EMPTY_RESULT);
      expect(service.editorText).assertEqual('原文');
      await controller.request(AiAction.POLITE);
      expect(store.getSnapshot().aiPresentation.errorCode).assertEqual(AiErrorCode.PROVIDER_ERROR);
      expect(service.editorText).assertEqual('原文');
    });

    it('rejects late and out-of-order AI responses after cancellation or a newer request', 0, async () => {
      const store = activeStore();
      const service = new Ai0FakeImeService();
      service.editorText = '原文';
      const provider = new FakeAiProvider();
      provider.enqueueBehavior({ scenario: FakeAiScenario.LATE_SUCCESS, delayMs: 20 });
      provider.enqueueBehavior({ scenario: FakeAiScenario.SUCCESS, delayMs: 2 });
      const controller = new AiAssistController(
        store,
        (): ImeSettings => enabledSettings(),
        provider,
        new VerifiedTextReplacer(service, (generation: number): boolean =>
          generation === store.getSessionGeneration()),
        (): string | null => '原文',
        (): void => {},
        100
      );
      const first = controller.request(AiAction.CONTINUE);
      const second = controller.request(AiAction.FORMAL);
      await second;
      const secondRequestId = store.getSnapshot().aiPresentation.requestId;
      await first;
      expect(store.getSnapshot().aiPresentation.requestId).assertEqual(secondRequestId);
      expect(store.getSnapshot().aiPresentation.action).assertEqual(AiAction.FORMAL);

      provider.setDefaultBehavior({ scenario: FakeAiScenario.LATE_SUCCESS, delayMs: 10 });
      const late = controller.request(AiAction.POLITE);
      controller.invalidateForInput();
      await late;
      expect(store.getSnapshot().aiPresentation.state).assertEqual(AiRequestState.IDLE);
    });

    it('does not publish AI or speech timeouts after session generation changes', 0, async () => {
      const aiStore = activeStore();
      const service = new Ai0FakeImeService();
      service.editorText = '原文';
      const aiProvider = new FakeAiProvider();
      aiProvider.setDefaultBehavior({ scenario: FakeAiScenario.TIMEOUT, delayMs: 0 });
      const aiController = new AiAssistController(
        aiStore,
        (): ImeSettings => enabledSettings(),
        aiProvider,
        new VerifiedTextReplacer(service, (generation: number): boolean =>
          generation === aiStore.getSessionGeneration()),
        (): string | null => '原文',
        (): void => {},
        5
      );
      const aiRequest = aiController.request(AiAction.POLITE);
      aiStore.advanceSessionGeneration();
      aiStore.clearAssistPresentation();
      await aiRequest;
      expect(aiStore.getSnapshot().aiPresentation.state).assertEqual(AiRequestState.IDLE);

      const voiceStore = activeStore();
      const speechProvider = new FakeSpeechProvider();
      speechProvider.setDefaultBehavior({
        scenario: FakeSpeechScenario.TIMEOUT,
        interimDelayMs: 0,
        finalDelayMs: 0
      });
      const voiceController = new VoiceInputController(
        voiceStore,
        (): ImeSettings => enabledSettings(),
        speechProvider,
        service,
        (): void => {},
        5
      );
      expect(voiceController.start()).assertTrue();
      voiceStore.advanceSessionGeneration();
      voiceStore.clearAssistPresentation();
      await wait(8);
      expect(voiceStore.getSnapshot().voicePresentation.state).assertEqual(VoiceSessionState.IDLE);
    });

    it('runs fake speech interim/final confirmation without auto commit', 0, async () => {
      const store = activeStore();
      const service = new Ai0FakeImeService();
      const provider = new FakeSpeechProvider();
      provider.setDefaultBehavior({
        scenario: FakeSpeechScenario.SUCCESS,
        interimDelayMs: 1,
        finalDelayMs: 3
      });
      let recordedLength = 0;
      const controller = new VoiceInputController(
        store,
        (): ImeSettings => enabledSettings(),
        provider,
        service,
        (text: string): void => {
          recordedLength = text.length;
        },
        50
      );
      expect(controller.start()).assertTrue();
      await wait(8);
      expect(store.getSnapshot().voicePresentation.state).assertEqual(VoiceSessionState.RESULT_READY);
      expect(service.editorText).assertEqual('');
      expect(await controller.confirm()).assertTrue();
      expect(service.editorText.length > 0).assertTrue();
      expect(recordedLength > 0).assertTrue();
      expect(store.getSnapshot().voicePresentation.state).assertEqual(VoiceSessionState.COMMITTED);
    });

    it('ignores out-of-order speech interim and callbacks that arrive after cancellation', 0, async () => {
      const store = activeStore();
      const service = new Ai0FakeImeService();
      const provider = new FakeSpeechProvider();
      provider.enqueueBehavior({
        scenario: FakeSpeechScenario.OUT_OF_ORDER,
        interimDelayMs: 1,
        finalDelayMs: 4
      });
      provider.enqueueBehavior({
        scenario: FakeSpeechScenario.LATE_AFTER_CANCEL,
        interimDelayMs: 1,
        finalDelayMs: 4
      });
      const controller = new VoiceInputController(
        store,
        (): ImeSettings => enabledSettings(),
        provider,
        service,
        (): void => {},
        50
      );
      controller.start();
      await wait(8);
      const finalText = store.getSnapshot().voicePresentation.finalText;
      expect(store.getSnapshot().voicePresentation.state).assertEqual(VoiceSessionState.RESULT_READY);
      expect(finalText).assertEqual('这是最终结果');

      controller.start();
      controller.invalidateForInput();
      await wait(8);
      expect(store.getSnapshot().voicePresentation.state).assertEqual(VoiceSessionState.IDLE);
      expect(store.getSnapshot().voicePresentation.finalText).assertEqual('');
    });

    it('times out fake speech and blocks it in basic security mode', 0, async () => {
      const store = activeStore();
      const service = new Ai0FakeImeService();
      const provider = new FakeSpeechProvider();
      provider.setDefaultBehavior({
        scenario: FakeSpeechScenario.TIMEOUT,
        interimDelayMs: 0,
        finalDelayMs: 0
      });
      const controller = new VoiceInputController(
        store,
        (): ImeSettings => enabledSettings(),
        provider,
        service,
        (): void => {},
        5
      );
      expect(controller.start()).assertTrue();
      await wait(8);
      expect(store.getSnapshot().voicePresentation.errorCode).assertEqual(VoiceErrorCode.TIMEOUT);

      const basic = fullCapability();
      basic.securityMode = InputMethodSecurityMode.BASIC;
      store.setInputMethodCapabilityState(basic);
      expect(controller.start()).assertFalse();
      expect(store.getSnapshot().voicePresentation.state).assertEqual(VoiceSessionState.UNAVAILABLE);
    });

    it('surfaces empty and provider-error speech results without auto committing', 0, async () => {
      const store = activeStore();
      const service = new Ai0FakeImeService();
      const provider = new FakeSpeechProvider();
      provider.enqueueBehavior({
        scenario: FakeSpeechScenario.EMPTY,
        interimDelayMs: 1,
        finalDelayMs: 3
      });
      provider.enqueueBehavior({
        scenario: FakeSpeechScenario.ERROR,
        interimDelayMs: 1,
        finalDelayMs: 3
      });
      const controller = new VoiceInputController(
        store,
        (): ImeSettings => enabledSettings(),
        provider,
        service,
        (): void => {},
        50
      );

      expect(controller.start()).assertTrue();
      await wait(6);
      expect(store.getSnapshot().voicePresentation.errorCode).assertEqual(VoiceErrorCode.NO_RESULT);
      expect(service.editorText).assertEqual('');
      expect(controller.start()).assertTrue();
      await wait(4);
      expect(store.getSnapshot().voicePresentation.errorCode).assertEqual(VoiceErrorCode.PROVIDER_ERROR);
      expect(service.editorText).assertEqual('');
    });
  });
}
