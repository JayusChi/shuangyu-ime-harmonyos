/** Prefix ownership is shared by touch and physical convenience composition. */
export function isConvenienceInput(rawInput: string): boolean {
  return rawInput.startsWith('=') || rawInput.startsWith("'");
}
