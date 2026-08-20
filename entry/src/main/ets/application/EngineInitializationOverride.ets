export interface EngineInitializationOverride {
  schemeId: string;
  candidatePageSize: number;
  codeTableBundlePath: string;
  userLexiconPath?: string;
  codeTableActionFixturePath: string;
  codeTableActionFixtureSha256: string;
  quanpinContextModelPath?: string;
  quanpinContextModelSha256?: string;
}

let currentOverride: EngineInitializationOverride | undefined;

export function setEngineInitializationOverride(value: EngineInitializationOverride): void {
  currentOverride = {
    schemeId: value.schemeId,
    candidatePageSize: value.candidatePageSize,
    codeTableBundlePath: value.codeTableBundlePath,
    userLexiconPath: value.userLexiconPath,
    codeTableActionFixturePath: value.codeTableActionFixturePath,
    codeTableActionFixtureSha256: value.codeTableActionFixtureSha256,
    quanpinContextModelPath: value.quanpinContextModelPath,
    quanpinContextModelSha256: value.quanpinContextModelSha256
  };
}

export function getEngineInitializationOverride(): EngineInitializationOverride | undefined {
  if (!currentOverride) {
    return undefined;
  }
  return {
    schemeId: currentOverride.schemeId,
    candidatePageSize: currentOverride.candidatePageSize,
    codeTableBundlePath: currentOverride.codeTableBundlePath,
    userLexiconPath: currentOverride.userLexiconPath,
    codeTableActionFixturePath: currentOverride.codeTableActionFixturePath,
    codeTableActionFixtureSha256: currentOverride.codeTableActionFixtureSha256,
    quanpinContextModelPath: currentOverride.quanpinContextModelPath,
    quanpinContextModelSha256: currentOverride.quanpinContextModelSha256
  };
}

export function clearEngineInitializationOverride(): void {
  currentOverride = undefined;
}
