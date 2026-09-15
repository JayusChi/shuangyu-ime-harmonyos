import { PairCursorClient, PairCursorPositioner } from './PairCursorPositioner';

const LINE_END_QUERY_UNITS = 4096;
const LINE_END_QUERY_LIMIT = 128;

/** Implements the quick-symbol End action without assuming selection support. */
export class LineEndCursorMover {
  private readonly positioner: PairCursorPositioner = new PairCursorPositioner();

  async move(client: PairCursorClient, stillCurrent: () => boolean): Promise<boolean> {
    try {
      for (let attempt = 0; attempt < LINE_END_QUERY_LIMIT && stillCurrent(); attempt += 1) {
        const cursor = await client.getTextIndexAtCursor();
        if (!Number.isInteger(cursor) || cursor < 0 || !stillCurrent()) {
          return false;
        }
        const after = await client.getBackward(LINE_END_QUERY_UNITS);
        if (!stillCurrent() || await client.getTextIndexAtCursor() !== cursor || !stillCurrent()) {
          return false;
        }
        const boundary = after.search(/[\r\n]/);
        let length = boundary >= 0 ? boundary : after.length;
        const atEnd = boundary >= 0 || after.length < LINE_END_QUERY_UNITS;
        // Do not split a surrogate pair at a query-window boundary.
        const tail = after.charCodeAt(length - 1);
        if (!atEnd && tail >= 0xD800 && tail <= 0xDBFF) {
          length -= 1;
        }
        if (length > 0 && !await this.positioner.advance(
          client, after.substring(0, length), stillCurrent, cursor
        )) {
          return false;
        }
        if (atEnd) {
          return stillCurrent();
        }
      }
    } catch (_err) {
    }
    return false;
  }
}
