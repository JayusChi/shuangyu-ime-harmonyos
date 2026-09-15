/** Shared validation for saved shortcuts and OS launches. Targets keep their case. */
export function isExternalDirectTarget(action: string, target: string): boolean {
  if (target.length === 0 || target.length > 2048 || /[\u0000-\u001f\u007f-\u009f\\]/.test(target)) {
    return false;
  }
  if (action === 'directory.open') {
    return target.startsWith('file://docs/') && target.length > 'file://docs/'.length;
  }
  if (action !== 'url.open' || /\s/.test(target)) {
    return false;
  }
  const match = /^https?:\/\/([^/?#]+)/.exec(target);
  return match !== null && match[1].length > 0 && !match[1].includes('@') && !match[1].startsWith(':');
}
