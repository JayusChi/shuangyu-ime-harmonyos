import { accessSync, constants } from 'node:fs';
import { loadProductionConfig, loadMountedSecret } from './config.mjs';

try {
  const config = loadProductionConfig();
  accessSync(config.jwksPath, constants.R_OK);
  loadMountedSecret(config.modelAuthTokenFile);
  if (!config.externalTlsTerminated) {
    accessSync(config.tlsCertPath, constants.R_OK);
    accessSync(config.tlsKeyPath, constants.R_OK);
  }
  console.info('AI_PROXY_CONFIG_CHECK=PASS');
} catch {
  console.error('AI_PROXY_CONFIG_CHECK=FAIL');
  process.exitCode = 1;
}
