import { describe, expect, it } from '@ohos/hypium';
import {
  CloudAiAccessToken,
  CloudAiTokenBroker,
  ShortLivedCloudAiHeaderProvider
} from '../main/ets/infrastructure/ai/ShortLivedCloudAiHeaderProvider';

const TOKEN: string = 'eyJhbGciOiJFZERTQSJ9.eyJzY29wZSI6ImFpOnN1Z2dlc3QifQ.signature';

class CountingTokenBroker implements CloudAiTokenBroker {
  calls: number = 0;
  token: CloudAiAccessToken;

  constructor(token: CloudAiAccessToken) {
    this.token = token;
  }

  async requestAccessToken(_requestId: string, _consentVersion: number): Promise<CloudAiAccessToken> {
    this.calls += 1;
    return this.token;
  }
}

class DeferredTokenBroker implements CloudAiTokenBroker {
  private resolveToken?: (token: CloudAiAccessToken) => void;

  requestAccessToken(_requestId: string, _consentVersion: number): Promise<CloudAiAccessToken> {
    return new Promise<CloudAiAccessToken>((resolve: (token: CloudAiAccessToken) => void): void => {
      this.resolveToken = resolve;
    });
  }

  complete(token: CloudAiAccessToken): void {
    this.resolveToken?.(token);
  }
}

function accessToken(
  issuedAtEpochSeconds: number = 1000,
  expiresAtEpochSeconds: number = 1100,
  consentVersion: number = 1,
  value: string = TOKEN
): CloudAiAccessToken {
  return { value, issuedAtEpochSeconds, expiresAtEpochSeconds, consentVersion };
}

export default function ai1ProxyReadinessTest() {
  describe('AI-1 production proxy readiness boundaries', () => {
    it('keeps a valid short-lived access token in memory and reuses it', 0, async () => {
      const broker = new CountingTokenBroker(accessToken());
      const provider = new ShortLivedCloudAiHeaderProvider(broker, 1, (): number => 1010);

      const first = await provider.getHeaders('request-001');
      const second = await provider.getHeaders('request-002');

      expect(first.authorization).assertEqual(`Bearer ${TOKEN}`);
      expect(second.authorization).assertEqual(`Bearer ${TOKEN}`);
      expect(broker.calls).assertEqual(1);
      provider.clear();
      await provider.getHeaders('request-003');
      expect(broker.calls).assertEqual(2);
    });

    it('refreshes a token before its remaining lifetime becomes unsafe', 0, async () => {
      let now = 1010;
      const broker = new CountingTokenBroker(accessToken(1000, 1030));
      const provider = new ShortLivedCloudAiHeaderProvider(broker, 1, (): number => now);
      await provider.getHeaders('request-001');
      now = 1020;
      broker.token = accessToken(1020, 1120);
      await provider.getHeaders('request-002');
      expect(broker.calls).assertEqual(2);
    });

    it('rejects wrong-consent, overlong-lifetime and malformed tokens', 0, async () => {
      const invalidTokens: CloudAiAccessToken[] = [
        accessToken(1000, 1100, 2),
        accessToken(1000, 1400),
        accessToken(1000, 1100, 1, 'permanent-api-key')
      ];
      for (let index = 0; index < invalidTokens.length; index += 1) {
        const provider = new ShortLivedCloudAiHeaderProvider(
          new CountingTokenBroker(invalidTokens[index]),
          1,
          (): number => 1010
        );
        let rejected = false;
        try {
          await provider.getHeaders(`request-00${index}`);
        } catch (_err) {
          rejected = true;
        }
        expect(rejected).assertTrue();
      }
    });

    it('ignores a token that arrives after consent is cleared', 0, async () => {
      const broker = new DeferredTokenBroker();
      const provider = new ShortLivedCloudAiHeaderProvider(broker, 1, (): number => 1010);
      const pending = provider.getHeaders('request-deferred');
      provider.clear();
      broker.complete(accessToken());
      let rejected = false;
      try {
        await pending;
      } catch (_err) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });
  });
}
