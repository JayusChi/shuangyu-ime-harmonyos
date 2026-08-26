import { createServer as createHttpServer } from 'node:http';
import { createServer as createHttpsServer } from 'node:https';
import { readFileSync } from 'node:fs';
import { createAiProxyHandler } from './app.mjs';
import { AiProxyAuditLogger } from './audit.mjs';
import { EdDsaAccessTokenVerifier, FileJwksSource } from './auth.mjs';
import { loadProductionConfig } from './config.mjs';
import { HttpJsonModelProvider } from './provider.mjs';
import { FixedWindowRateLimiter, RequestReplayGuard } from './rate-limit.mjs';

try {
  const config = loadProductionConfig();
  const tokenVerifier = new EdDsaAccessTokenVerifier({
    keySource: new FileJwksSource(config.jwksPath),
    issuer: config.issuer,
    audience: config.audience,
    consentVersion: config.consentVersion,
    maxTokenLifetimeSeconds: config.maxTokenLifetimeSeconds,
    clockSkewSeconds: config.clockSkewSeconds
  });
  const handler = createAiProxyHandler({
    config,
    tokenVerifier,
    provider: new HttpJsonModelProvider({
      endpoint: config.modelGatewayUrl,
      authTokenFile: config.modelAuthTokenFile,
      maxResponseBytes: config.maxProviderResponseBytes
    }),
    rateLimiter: new FixedWindowRateLimiter(config.rateLimitPerMinute),
    replayGuard: new RequestReplayGuard(config.replayWindowMs),
    auditLogger: new AiProxyAuditLogger()
  });
  const server = config.externalTlsTerminated
    ? createHttpServer(handler)
    : createHttpsServer({
      cert: readFileSync(config.tlsCertPath),
      key: readFileSync(config.tlsKeyPath),
      minVersion: 'TLSv1.2'
    }, handler);
  server.requestTimeout = 10_000;
  server.headersTimeout = 5_000;
  server.keepAliveTimeout = 5_000;
  server.maxRequestsPerSocket = 100;
  server.listen(config.port, config.host, () => {
    console.info(JSON.stringify({ event: 'ai_proxy_start', status: 'ready' }));
  });
  const shutdown = () => server.close(() => process.exit(0));
  process.once('SIGINT', shutdown);
  process.once('SIGTERM', shutdown);
} catch {
  console.error(JSON.stringify({ event: 'ai_proxy_start', status: 'config_or_startup_error' }));
  process.exitCode = 1;
}
