export interface RawValue { text: string; literals: Set<number> }
export interface Segment extends RawValue { quoted: boolean }
export interface LineError { code: string; message: string }
export interface LogicalLine { line: number; segments: Segment[]; error: LineError | null }

function segment(quoted: boolean): Segment {
  return { quoted, text: '', literals: new Set() };
}

export function logicalLines(text: string): LogicalLine[] {
  const physical = text.split('\n').slice(0, -1);
  const result: LogicalLine[] = [];
  const escapes: Record<string, string> = { '\\': '\\', '"': '"', n: '\n', t: '\t', $: '$' };
  for (let row = 0; row < physical.length; row++) {
    const line = row + 1, segments = [segment(false)];
    let current = segments[0], source = physical[row], position = 0;
    let inside = false, error: LineError | null = null;
    while (position < source.length) {
      const character = source[position];
      if (character === '\\' && position + 1 === source.length) {
        source = physical[++row].replace(/^ +/, '');
        position = 0;
        continue;
      }
      if (!inside && (character === ';' || character === '#')) break;
      if (character === '"') {
        inside = !inside;
        current = segment(inside);
        segments.push(current);
        position++;
      } else if (inside && character === '\\') {
        const escaped = source[position + 1];
        if (Object.hasOwn(escapes, escaped)) {
          if (escaped === '$') current.literals.add(current.text.length);
          current.text += escapes[escaped];
        } else if (error === null) {
          error = { code: 'E_ESCAPE', message: `invalid escape sequence \\${escaped}` };
        }
        position += 2;
      } else {
        current.text += character;
        position++;
      }
    }
    if (inside && error === null) error = { code: 'E_UNTERMINATED', message: 'unterminated string' };
    result.push({ line, segments, error });
  }
  return result;
}
