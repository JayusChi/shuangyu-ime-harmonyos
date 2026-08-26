export interface CurrentLineRange {
  start: number;
  end: number;
}

export function resolveCurrentLineRange(
  cursor: number,
  before: string,
  after: string,
  beforeMayBeTruncated: boolean,
  afterMayBeTruncated: boolean
): CurrentLineRange | undefined {
  if (!Number.isInteger(cursor) || cursor < 0 || before.length > cursor) {
    return undefined;
  }
  const lastLf = before.lastIndexOf('\n');
  const lastCr = before.lastIndexOf('\r');
  const previousBreak = Math.max(lastLf, lastCr);
  if (previousBreak < 0 && beforeMayBeTruncated) {
    return undefined;
  }
  const firstLf = after.indexOf('\n');
  const firstCr = after.indexOf('\r');
  let nextBreak = -1;
  if (firstLf >= 0 && firstCr >= 0) {
    nextBreak = Math.min(firstLf, firstCr);
  } else {
    nextBreak = Math.max(firstLf, firstCr);
  }
  if (nextBreak < 0 && afterMayBeTruncated) {
    return undefined;
  }
  let start = cursor - (before.length - previousBreak - 1);
  let end = cursor + after.length;
  if (nextBreak >= 0) {
    let breakLength = 1;
    if (after.charAt(nextBreak) === '\r' && after.charAt(nextBreak + 1) === '\n') {
      breakLength = 2;
    }
    end = cursor + nextBreak + breakLength;
  } else if (start === end && previousBreak >= 0) {
    start -= previousBreak > 0 && before.charAt(previousBreak) === '\n' &&
      before.charAt(previousBreak - 1) === '\r' ? 2 : 1;
  }
  return start < end ? { start, end } : undefined;
}
