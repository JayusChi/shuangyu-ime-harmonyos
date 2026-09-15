import { inputMethodEngine } from '@kit.IMEKit';

export interface PairCursorClient {
  getTextIndexAtCursor(): Promise<number>;
  getForward(length: number): Promise<string>;
  getBackward(length: number): Promise<string>;
  selectByRange(range: inputMethodEngine.Range): Promise<void>;
  moveCursor(direction: inputMethodEngine.Direction): Promise<void>;
}

export class HarmonyPairCursorClient implements PairCursorClient {
  private readonly client: inputMethodEngine.InputClient;

  constructor(client: inputMethodEngine.InputClient) {
    this.client = client;
  }

  async getTextIndexAtCursor(): Promise<number> {
    return this.client.getTextIndexAtCursor();
  }

  async getForward(length: number): Promise<string> {
    return this.client.getForward(length);
  }

  async getBackward(length: number): Promise<string> {
    return this.client.getBackward(length);
  }

  async selectByRange(range: inputMethodEngine.Range): Promise<void> {
    await this.client.selectByRange(range);
  }

  async moveCursor(direction: inputMethodEngine.Direction): Promise<void> {
    await this.client.moveCursor(direction);
  }
}

// Editor writes and selection updates may settle after their promises resolve.
const OBSERVATION_ATTEMPTS: number = 12;
const OBSERVATION_INTERVAL_MS: number = 25;

export class PairCursorPositioner {
  /** Advance only across text verified at the current cursor (UTF-16 offsets). */
  async advance(
    client: PairCursorClient,
    right: string,
    stillCurrent: () => boolean,
    expectedStart: number = -1
  ): Promise<boolean> {
    if (right.length === 0 || !stillCurrent()) {
      return false;
    }
    try {
      const before = await client.getForward(16);
      const start = await this.observe(client, expectedStart, before, right, stillCurrent);
      if (start < 0 || !stillCurrent()) {
        return false;
      }
      const target = start + right.length;
      const targetBefore = (before + right).slice(-16);
      try {
        await client.selectByRange({ start: target, end: target });
      } catch (_err) {
        // Rich editors may support directional movement only.
      }
      if (await this.observe(client, target, targetBefore, '', stillCurrent) === target) {
        return true;
      }
      // A resolved selection request is not proof that the editor moved.
      // Fall back only from the unchanged anchor, never from an unknown cursor.
      if (!await this.matches(client, start, before, right, stillCurrent)) {
        return false;
      }
      let advanced = 0;
      while (advanced < right.length) {
        if (!stillCurrent()) {
          return false;
        }
        const head = right.charCodeAt(advanced);
        const tail = right.charCodeAt(advanced + 1);
        advanced += head >= 0xD800 && head <= 0xDBFF && tail >= 0xDC00 && tail <= 0xDFFF ? 2 : 1;
        await client.moveCursor(inputMethodEngine.Direction.CURSOR_RIGHT);
        const expected = start + advanced;
        if (await this.observe(client, expected, (before + right.substring(0, advanced)).slice(-16),
          right.substring(advanced), stillCurrent) !== expected) {
          return false;
        }
      }
      return stillCurrent();
    } catch (_err) {
      return false;
    }
  }

  async position(
    client: PairCursorClient,
    text: string,
    rightLength: number,
    stillCurrent: () => boolean
  ): Promise<boolean> {
    try {
      const end = await this.observe(client, -1, text, '', stillCurrent);
      if (end < 0 || !stillCurrent()) {
        return false;
      }
      const target = end - rightLength;
      const left = text.substring(0, text.length - rightLength);
      const right = text.substring(text.length - rightLength);
      try {
        await client.selectByRange({ start: target, end: target });
      } catch (_err) {
        // Some editors reject collapsed selections but support cursor movement.
      }
      if (await this.observe(client, target, left, right, stillCurrent) === target) {
        return true;
      }
      // Only fall back if the editor still confirms the complete inserted pair
      // before the original end. Never reinsert text or move from an unknown cursor.
      if (!stillCurrent() || !await this.matches(client, end, text, '', stillCurrent)) {
        return false;
      }
      let remaining = right.length;
      while (remaining > 0) {
        if (!stillCurrent()) {
          return false;
        }
        const tail = right.charCodeAt(remaining - 1);
        const head = remaining > 1 ? right.charCodeAt(remaining - 2) : 0;
        remaining -= tail >= 0xDC00 && tail <= 0xDFFF && head >= 0xD800 && head <= 0xDBFF ? 2 : 1;
        await client.moveCursor(inputMethodEngine.Direction.CURSOR_LEFT);
        const expected = target + remaining;
        if (await this.observe(client, expected, left + right.substring(0, remaining),
          right.substring(remaining), stillCurrent) !== expected) {
          return false;
        }
      }
      return stillCurrent();
    } catch (_err) {
      return false;
    }
  }

  private async observe(
    client: PairCursorClient,
    expected: number,
    before: string,
    after: string,
    stillCurrent: () => boolean
  ): Promise<number> {
    let confirmedCursor = -1;
    for (let attempt = 0; attempt < OBSERVATION_ATTEMPTS && stillCurrent(); attempt += 1) {
      const cursor = await client.getTextIndexAtCursor();
      if (Number.isInteger(cursor) && cursor >= before.length &&
        (expected < 0 || cursor === expected) &&
        await this.matches(client, cursor, before, after, stillCurrent)) {
        // Text and cursor queries can briefly describe different render turns.
        // Require agreement across two observations before acting on an anchor.
        if (confirmedCursor === cursor) {
          return cursor;
        }
        confirmedCursor = cursor;
      } else {
        confirmedCursor = -1;
      }
      if (attempt + 1 < OBSERVATION_ATTEMPTS && stillCurrent()) {
        await new Promise<void>((resolve: () => void) => setTimeout(resolve, OBSERVATION_INTERVAL_MS));
      }
    }
    return -1;
  }

  private async matches(
    client: PairCursorClient,
    cursor: number,
    before: string,
    after: string,
    stillCurrent: () => boolean
  ): Promise<boolean> {
    if (!stillCurrent() || await client.getTextIndexAtCursor() !== cursor) {
      return false;
    }
    const observedBefore = await client.getForward(before.length);
    if (!stillCurrent() || observedBefore !== before) {
      return false;
    }
    if (after.length > 0) {
      const observedAfter = await client.getBackward(after.length);
      if (!stillCurrent() || observedAfter !== after) {
        return false;
      }
    }
    return await client.getTextIndexAtCursor() === cursor && stillCurrent();
  }
}
