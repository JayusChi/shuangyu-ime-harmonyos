import { describe, expect, it } from '@ohos/hypium';
import { AiAssistController } from '../main/ets/application/AiAssistController';
import { ImeInputService } from '../main/ets/application/ImeInputService';
import { VerifiedTextReplacer } from '../main/ets/application/VerifiedTextReplacer';
import {
  AI_ACTIONS,
  AiAction,
  AiErrorCode,
  AiProviderKind,
  AiProviderPolicy,
  AiProviderResult,
  AiReplacePolicy,
  AiRequest,
  AiRequestState,
  AiSourceOwnership,
  AiSuggestion,
  aiActionLabel
} from '../main/ets/domain/ai/AiContracts';
import { normalizeLocalAssociations } from '../main/ets/domain/ai/LocalAssociationContracts';
import { EditorContext, EditorKind, EnterAction } from '../main/ets/domain/editor/EditorContext';
import { KeyboardMode } from '../main/ets/domain/keyboard/KeyboardAction';
import { copyImeSettings, DEFAULT_IME_SETTINGS, ImeSettings } from '../main/ets/domain/settings/ImeSettings';
import {
  InputMethodCapabilityState,
  InputMethodSecurityMode,
  MicrophonePermissionState,
  resolveAssistAvailability
} from '../main/ets/domain/security/InputMethodCapabilityState';
import { AiProvider } from '../main/ets/infrastructure/ai/AiProvider';
import { CloudAiProvider } from '../main/ets/infrastructure/ai/CloudAiProvider';
import {
  CloudAiTransport,
  CloudAiTransportRequest,
  CloudAiTransportResponse
} from '../main/ets/infrastructure/ai/CloudAiTransport';
import { InputSessionStore } from '../main/ets/state/InputSessionStore';

interface TestSuggestionJson {
  suggestionId: string;
  text: string;
  label: string;
  type: string;
}

interface TestCloudEnvelope {
  protocolVersion: string;
  requestId: string;
  providerType: string;
  providerVersion: string;
  suggestions: TestSuggestionJson[];
}

interface TestOutboundPayload {
  protocolVersion: string;
  requestId: string;
  action: string;
  text: string;
  language: string;
  maxSuggestions: number;
}

function utf8Length(value: string): number {
  let bytes = 0;
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code <= 0x7f) {
      bytes += 1;
    } else if (code <= 0x7ff) {
      bytes += 2;
    } else if (code >= 0xd800 && code <= 0xdbff && index + 1 < value.length &&
      value.charCodeAt(index + 1) >= 0xdc00 && value.charCodeAt(index + 1) <= 0xdfff) {
      bytes += 4;
      index += 1;
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

function cloudEnvelope(
  requestId: string,
  suggestions: TestSuggestionJson[],
  protocolVersion: string = 'ai-input-v1',
  providerType: string = 'cloud'
): string {
  const envelope: TestCloudEnvelope = {
    protocolVersion,
    requestId,
    providerType,
    providerVersion: 'unit-provider-1',
    suggestions
  };
  return JSON.stringify(envelope);
}

function suggestion(id: string, text: string = '建议'): TestSuggestionJson {
  return { suggestionId: id, text, label: '建议', type: 'text' };
}

function response(body: string, statusCode: number = 200): CloudAiTransportResponse {
  return { statusCode, body, bodyBytes: utf8Length(body) };
}

class QueueCloudTransport implements CloudAiTransport {
  responses: CloudAiTransportResponse[] = [];
  lastRequest?: CloudAiTransportRequest;
  canceledRequestIds: string[] = [];
  rejectNext: boolean = false;
  delayMs: number = 0;

  async post(request: CloudAiTransportRequest): Promise<CloudAiTransportResponse> {
    this.lastRequest = request;
    if (this.delayMs > 0) {
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, this.delayMs);
      });
    }
    if (this.rejectNext) {
      this.rejectNext = false;
      throw new Error('synthetic_transport_failure');
    }
    const next = this.responses.shift();
    if (next === undefined) {
      throw new Error('synthetic_missing_response');
    }
    return next;
  }

  cancel(requestId: string): void {
    this.canceledRequestIds.push(requestId);
  }
}

function cloudProvider(transport: CloudAiTransport): CloudAiProvider {
  return new CloudAiProvider({
    endpoint: 'https://proxy.unit.example.com/v1/ime/suggestions',
    approvedProxyHost: 'proxy.unit.example.com',
    protocolVersion: 'ai-input-v1'
  }, transport);
}

function aiRequest(action: AiAction = AiAction.POLITE): AiRequest {
  return {
    requestId: `request-${action}`,
    sessionId: 'session-1',
    sessionGeneration: 4,
    action,
    sourceText: '仍由输入法拥有的文本',
    sourceOwnership: AiSourceOwnership.LAST_IME_COMMIT,
    locale: 'zh-CN',
    providerPolicy: AiProviderPolicy.CLOUD_ALLOWED,
    deadlineMs: 8000,
    maxSuggestions: 3
  };
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

function fullCapability(): InputMethodCapabilityState {
  return {
    securityMode: InputMethodSecurityMode.FULL,
    microphonePermission: MicrophonePermissionState.NOT_REQUESTED,
    localAiProviderAvailable: true,
    cloudAiProviderAvailable: true,
    speechProviderAvailable: false,
    detectedAtMs: 1
  };
}

function cloudEnabledSettings(): ImeSettings {
  const settings = copyImeSettings(DEFAULT_IME_SETTINGS);
  settings.aiEnabled = true;
  settings.cloudAiEnabled = true;
  settings.cloudAiConsentVersion = 1;
  return settings;
}

function activeStore(): InputSessionStore {
  const store = new InputSessionStore();
  store.setInputMethodCapabilityState(fullCapability());
  store.markSessionStarted();
  store.applyEditorContext(normalEditor());
  store.markKeyboardVisible();
  return store;
}

class Ai1ImeService implements ImeInputService {
  editorText: string = '';

  async insertText(text: string): Promise<boolean> {
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

  async replaceTextBeforeCursorIfMatches(
    sourceText: string,
    replacementText: string,
    stillOwned: () => boolean = (): boolean => true,
    expectedCursorUtf16?: number
  ): Promise<boolean> {
    if (!stillOwned() || !this.editorText.endsWith(sourceText) ||
      (expectedCursorUtf16 !== undefined && expectedCursorUtf16 !== this.editorText.length)) {
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

class CapturingCloudProvider implements AiProvider {
  actions: AiAction[] = [];
  delayMs: number = 0;

  async request(request: AiRequest): Promise<AiProviderResult> {
    this.actions.push(request.action);
    if (this.delayMs > 0) {
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, this.delayMs);
      });
    }
    const item: AiSuggestion = {
      suggestionId: `${request.requestId}-1`,
      requestId: request.requestId,
      text: '云端建议',
      label: '建议',
      providerKind: AiProviderKind.CLOUD,
      replacePolicy: AiReplacePolicy.REPLACE_VERIFIED_SOURCE
    };
    return {
      success: true,
      requestId: request.requestId,
      providerKind: AiProviderKind.CLOUD,
      suggestions: [item],
      errorCode: AiErrorCode.NONE
    };
  }

  cancel(_requestId: string): void {
  }
}

export default function ai1InputTest() {
  describe('AI-1 first AI input', () => {
    it('exposes exactly five labeled user-triggered actions', 0, () => {
      expect(AI_ACTIONS.length).assertEqual(5);
      expect(AI_ACTIONS.join('|')).assertEqual('continue|concise|polite|formal|translate');
      expect(AI_ACTIONS.map((action: AiAction): string => aiActionLabel(action)).join('|'))
        .assertEqual('续写|精简|礼貌|正式|翻译');
    });

    it('keeps local association and cloud AI disabled by default', 0, () => {
      expect(DEFAULT_IME_SETTINGS.aiEnabled).assertFalse();
      expect(DEFAULT_IME_SETTINGS.localAssociationEnabled).assertFalse();
      expect(DEFAULT_IME_SETTINGS.cloudAiEnabled).assertFalse();
      expect(DEFAULT_IME_SETTINGS.cloudAiConsentVersion).assertEqual(0);
    });

    it('normalizes local associations deterministically with hard bounds', 0, () => {
      const overlong = '一'.repeat(49);
      const input = ['继续', '继续', '', overlong, '完成', '下一步', '不会出现'];
      const first = normalizeLocalAssociations(input, 7);
      const second = normalizeLocalAssociations(input, 7);
      expect(JSON.stringify(first)).assertEqual(JSON.stringify(second));
      expect(first.length).assertEqual(3);
      expect(first.map((item): string => item.text).join('|')).assertEqual('继续|完成|下一步');
      expect(first[0].associationId).assertEqual('local-7-1');
      expect(first[0].providerKind).assertEqual(AiProviderKind.LOCAL);
    });

    it('fails cloud AI closed for modes, editor kinds, consent, switches, and provider state', 0, () => {
      const settings = cloudEnabledSettings();
      expect(resolveAssistAvailability(fullCapability(), normalEditor(), settings, true, true).ai.available)
        .assertTrue();
      const capability = fullCapability();
      capability.securityMode = InputMethodSecurityMode.BASIC;
      expect(resolveAssistAvailability(capability, normalEditor(), settings, true, true).ai.available)
        .assertFalse();
      capability.securityMode = InputMethodSecurityMode.UNKNOWN;
      expect(resolveAssistAvailability(capability, normalEditor(), settings, true, true).ai.available)
        .assertFalse();
      capability.securityMode = InputMethodSecurityMode.FULL;
      capability.cloudAiProviderAvailable = false;
      expect(resolveAssistAvailability(capability, normalEditor(), settings, true, true).ai.available)
        .assertFalse();

      const sensitiveKinds: EditorKind[] = [
        EditorKind.PASSWORD, EditorKind.UNKNOWN, EditorKind.NUMBER, EditorKind.PHONE,
        EditorKind.EMAIL, EditorKind.URL
      ];
      sensitiveKinds.forEach((kind: EditorKind): void => {
        const editor = normalEditor();
        editor.kind = kind;
        editor.isPassword = kind === EditorKind.PASSWORD;
        expect(resolveAssistAvailability(fullCapability(), editor, settings, true, true).ai.available)
          .assertFalse();
      });

      const noConsent = cloudEnabledSettings();
      noConsent.cloudAiConsentVersion = 0;
      expect(resolveAssistAvailability(fullCapability(), normalEditor(), noConsent, true, true).ai.available)
        .assertFalse();
      const cloudOff = cloudEnabledSettings();
      cloudOff.cloudAiEnabled = false;
      expect(resolveAssistAvailability(fullCapability(), normalEditor(), cloudOff, true, true).ai.available)
        .assertFalse();
      expect(resolveAssistAvailability(fullCapability(), normalEditor(), settings, false, false).ai.available)
        .assertFalse();
    });

    it('sends only the minimal owned-text proxy protocol and accepts a valid response', 0, async () => {
      const transport = new QueueCloudTransport();
      const request = aiRequest(AiAction.FORMAL);
      transport.responses.push(response(cloudEnvelope(request.requestId, [suggestion('s1', '正式建议')])));
      const result = await cloudProvider(transport).request(request);
      expect(result.success).assertTrue();
      expect(result.providerKind).assertEqual(AiProviderKind.CLOUD);
      expect(result.suggestions.length).assertEqual(1);
      expect(transport.lastRequest?.timeoutMs).assertEqual(8000);
      expect(transport.lastRequest?.maxResponseBytes).assertEqual(65536);
      const payload = JSON.parse(transport.lastRequest?.body ?? '{}') as TestOutboundPayload;
      expect(Object.keys(payload).sort().join('|'))
        .assertEqual('action|language|maxSuggestions|protocolVersion|requestId|text');
      expect(payload.text).assertEqual(request.sourceText);
      expect(payload.action).assertEqual(AiAction.FORMAL);
      expect(payload.maxSuggestions).assertEqual(3);
    });

    it('rejects unapproved, insecure, test, and credential-bearing proxy endpoints', 0, () => {
      const transport = new QueueCloudTransport();
      const endpoints = [
        'http://proxy.unit.example.com/v1/ime',
        'https://localhost/v1/ime',
        'https://proxy.unit.test/v1/ime',
        'https://user:secret@proxy.unit.example.com/v1/ime',
        'https://proxy.unit.example.com:8443/v1/ime'
      ];
      let rejected = 0;
      endpoints.forEach((endpoint: string): void => {
        try {
          new CloudAiProvider({
            endpoint,
            approvedProxyHost: endpoint.indexOf('localhost') >= 0 ? 'localhost' :
              (endpoint.indexOf('.test') >= 0 ? 'proxy.unit.test' : 'proxy.unit.example.com'),
            protocolVersion: 'ai-input-v1'
          }, transport);
        } catch (_err) {
          rejected += 1;
        }
      });
      expect(rejected).assertEqual(endpoints.length);
    });

    it('maps network and HTTP failures to fixed error codes', 0, async () => {
      const request = aiRequest();
      const network = new QueueCloudTransport();
      network.rejectNext = true;
      expect((await cloudProvider(network).request(request)).errorCode).assertEqual(AiErrorCode.NETWORK_ERROR);

      const http = new QueueCloudTransport();
      http.responses.push(response('{}', 503));
      expect((await cloudProvider(http).request(request)).errorCode).assertEqual(AiErrorCode.HTTP_ERROR);
    });

    it('rejects empty, oversized, byte-mismatched, and invalid JSON responses', 0, async () => {
      const request = aiRequest();
      const cases: CloudAiTransportResponse[] = [
        { statusCode: 200, body: '', bodyBytes: 0 },
        { statusCode: 200, body: '{}', bodyBytes: 65537 },
        { statusCode: 200, body: '{}', bodyBytes: 99 },
        response('{bad json')
      ];
      const expected: AiErrorCode[] = [
        AiErrorCode.INVALID_RESPONSE,
        AiErrorCode.RESPONSE_TOO_LARGE,
        AiErrorCode.INVALID_RESPONSE,
        AiErrorCode.INVALID_RESPONSE
      ];
      for (let index = 0; index < cases.length; index += 1) {
        const transport = new QueueCloudTransport();
        transport.responses.push(cases[index]);
        const result = await cloudProvider(transport).request(request);
        expect(result.errorCode).assertEqual(expected[index]);
      }
    });

    it('rejects request mismatch, protocol mismatch, provider mismatch, duplicates, and candidate overflow', 0,
      async () => {
        const request = aiRequest();
        const bodies: string[] = [
          cloudEnvelope('different-request', [suggestion('s1')]),
          cloudEnvelope(request.requestId, [suggestion('s1')], 'ai-input-v2'),
          cloudEnvelope(request.requestId, [suggestion('s1')], 'ai-input-v1', 'vendor'),
          cloudEnvelope(request.requestId, [suggestion('same'), suggestion('same')]),
          cloudEnvelope(request.requestId, [suggestion('1'), suggestion('2'), suggestion('3'), suggestion('4')]),
          cloudEnvelope(request.requestId, [suggestion('long', '长'.repeat(513))]),
          cloudEnvelope(request.requestId, [suggestion('extra-envelope')])
            .replace('"suggestions"', '"unexpected":true,"suggestions"'),
          cloudEnvelope(request.requestId, [suggestion('extra-suggestion')])
            .replace('"type":"text"', '"type":"text","unexpected":true')
        ];
        for (let index = 0; index < bodies.length; index += 1) {
          const transport = new QueueCloudTransport();
          transport.responses.push(response(bodies[index]));
          expect((await cloudProvider(transport).request(request)).errorCode)
            .assertEqual(AiErrorCode.PROTOCOL_ERROR);
        }
      });

    it('returns empty-result for a valid empty suggestion array', 0, async () => {
      const request = aiRequest();
      const transport = new QueueCloudTransport();
      transport.responses.push(response(cloudEnvelope(request.requestId, [])));
      expect((await cloudProvider(transport).request(request)).errorCode).assertEqual(AiErrorCode.EMPTY_RESULT);
    });

    it('cancels and ignores a response that arrives after cancellation', 0, async () => {
      const request = aiRequest();
      const transport = new QueueCloudTransport();
      transport.delayMs = 6;
      transport.responses.push(response(cloudEnvelope(request.requestId, [suggestion('s1')])));
      const provider = cloudProvider(transport);
      const pending = provider.request(request);
      provider.cancel(request.requestId);
      const result = await pending;
      expect(result.errorCode).assertEqual(AiErrorCode.CANCELED);
      expect(transport.canceledRequestIds[0]).assertEqual(request.requestId);
    });

    it('routes all five actions through the cloud-only controller', 0, async () => {
      const store = activeStore();
      const service = new Ai1ImeService();
      service.editorText = '原文';
      const provider = new CapturingCloudProvider();
      const controller = new AiAssistController(
        store,
        (): ImeSettings => cloudEnabledSettings(),
        provider,
        new VerifiedTextReplacer(service, (generation: number): boolean =>
          generation === store.getSessionGeneration()),
        (): string | null => '原文',
        (): void => {},
        50,
        (): Promise<boolean> => Promise.resolve(true)
      );
      for (let index = 0; index < AI_ACTIONS.length; index += 1) {
        await controller.request(AI_ACTIONS[index]);
        expect(store.getSnapshot().aiPresentation.state).assertEqual(AiRequestState.READY);
      }
      expect(provider.actions.join('|')).assertEqual(AI_ACTIONS.join('|'));
    });

    it('invalidates an operation canceled while source ownership is being verified', 0, async () => {
      const store = activeStore();
      const service = new Ai1ImeService();
      service.editorText = '原文';
      const controller = new AiAssistController(
        store,
        (): ImeSettings => cloudEnabledSettings(),
        new CapturingCloudProvider(),
        new VerifiedTextReplacer(service, (): boolean => true),
        (): string | null => '原文',
        (): void => {},
        50,
        async (): Promise<boolean> => {
          await new Promise<void>((resolve: () => void): void => {
            setTimeout(resolve, 5);
          });
          return true;
        }
      );
      const pending = controller.request(AiAction.POLITE);
      controller.invalidateForInput();
      await pending;
      expect(store.getSnapshot().aiPresentation.state).assertEqual(AiRequestState.IDLE);
    });

    it('drops delayed results after source change or cursor movement', 0, async () => {
      const store = activeStore();
      const service = new Ai1ImeService();
      service.editorText = '原文';
      const provider = new CapturingCloudProvider();
      provider.delayMs = 6;
      let owned = true;
      let cursor = 2;
      const controller = new AiAssistController(
        store,
        (): ImeSettings => cloudEnabledSettings(),
        provider,
        new VerifiedTextReplacer(service, (): boolean => true),
        (): string | null => '原文',
        (): void => {},
        50,
        (): Promise<boolean> => Promise.resolve(owned),
        (): Promise<number | undefined> => Promise.resolve(cursor)
      );
      const pending = controller.request(AiAction.POLITE);
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, 2);
      });
      owned = false;
      await pending;
      expect(store.getSnapshot().aiPresentation.state).assertEqual(AiRequestState.IDLE);

      owned = true;
      cursor = 2;
      const cursorPending = controller.request(AiAction.POLITE);
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, 2);
      });
      cursor = 0;
      await cursorPending;
      expect(store.getSnapshot().aiPresentation.state).assertEqual(AiRequestState.IDLE);
      expect(service.editorText).assertEqual('原文');
    });

    it('safely replaces and reverses emoji, combining text, newlines, and paired symbols', 0, async () => {
      const sources: string[] = ['😀', 'e\u0301', '第一行\n第二行', '「成对符号」'];
      for (let index = 0; index < sources.length; index += 1) {
        const service = new Ai1ImeService();
        service.editorText = `前缀${sources[index]}`;
        const replacer = new VerifiedTextReplacer(service, (): boolean => true);
        const replaced = await replacer.replace({
          sessionGeneration: 1,
          sourceText: sources[index],
          replacementText: '替换文本',
          sourceOwnership: AiSourceOwnership.LAST_IME_COMMIT
        });
        expect(replaced.success).assertTrue();
        const undone = await replacer.replace({
          sessionGeneration: 1,
          sourceText: '替换文本',
          replacementText: sources[index],
          sourceOwnership: AiSourceOwnership.LAST_IME_COMMIT
        });
        expect(undone.success).assertTrue();
        expect(service.editorText).assertEqual(`前缀${sources[index]}`);
      }
    });
  });
}
