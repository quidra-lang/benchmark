export function digit(code: number): boolean { return code >= 48 && code <= 57; }
export function letter(code: number): boolean { return (code >= 65 && code <= 90) || (code >= 97 && code <= 122); }
export function word(code: number): boolean { return letter(code) || digit(code) || code === 95; }
export function swapCase(code: number): number { return code >= 65 && code <= 90 ? code + 32 : code - 32; }

export const digits = new Set<number>();
export const words = new Set<number>();
export const spaces = new Set<number>([9, 10, 11, 12, 13, 32]);
for (let code = 0; code < 128; code++) {
  if (digit(code)) digits.add(code);
  if (word(code)) words.add(code);
}

export function complement(set: Set<number>): Set<number> {
  const result = new Set<number>();
  for (let code = 0; code < 128; code++) if (!set.has(code)) result.add(code);
  return result;
}

export function shorthand(character: string): {set: Set<number>; negated: boolean} {
  const lower = character === 'd' || character === 'D' ? 'd' : character === 'w' || character === 'W' ? 'w' : 's';
  const set = lower === 'd' ? digits : lower === 'w' ? words : spaces;
  return {set, negated: character !== lower};
}

export function same(first: number, second: number, flags: string): boolean {
  return first === second || (flags.includes('i') && letter(first) && swapCase(first) === second);
}

export function classMatches(set: Set<number>, negated: boolean, code: number, flags: string): boolean {
  const present = set.has(code) || (flags.includes('i') && letter(code) && set.has(swapCase(code)));
  return present !== negated;
}

export function consumes(instruction: import('./types.ts').Instruction, text: string, position: number, flags: string): boolean {
  if (position >= text.length) return false;
  const code = text.charCodeAt(position);
  if (instruction.op === 'CHAR') return same(code, instruction.character!, flags);
  if (instruction.op === 'ANY') return flags.includes('s') || code !== 10;
  return classMatches(instruction.set!, instruction.negated!, code, flags);
}

export function assertion(kind: string, text: string, position: number, flags: string): boolean {
  if (kind === 'BOL') return position === 0 || (flags.includes('m') && text[position - 1] === '\n');
  if (kind === 'EOL') return position === text.length || (flags.includes('m') && text[position] === '\n');
  const before = position > 0 && word(text.charCodeAt(position - 1));
  const after = position < text.length && word(text.charCodeAt(position));
  return kind === 'WORD' ? before !== after : before === after;
}

