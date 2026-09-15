import { isExternalDirectTarget } from './ExternalDirectTarget';

/** Only the official HTTPS origin is loaded by the app's private web ability. */
export function isFlypyWebTarget(url: string): boolean {
  return isExternalDirectTarget('url.open', url) && /^https:\/\/flypy\.cc(?:[/?#]|$)/.test(url);
}
