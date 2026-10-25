import type { Token, Lexed } from './types.ts';
export class FormatError extends Error {
  line: number;
  column: number;
  constructor(line: number, column: number, message: string) { super(message); this.line = line; this.column = column; }
}

export const TYPES = new Set<string>(['int', 'float', 'bool', 'string', 'void']);
const KEYWORDS = new Set([...TYPES, 'if', 'else', 'while', 'for', 'return', 'break', 'continue', 'true', 'false', 'switch', 'case', 'default']);
const DOUBLE_SYMBOLS = new Set(['<=', '>=', '==', '!=', '&&', '||', '+=', '-=', '*=', '/=', '%=']);
const letter = (value: string | undefined): boolean => value !== undefined && /[A-Za-z_]/.test(value);
const digit = (value: string | undefined): boolean => value !== undefined && value >= '0' && value <= '9';

export function tokenize(lines: string[]): Lexed {
  const tokens: Token[] = [], comments: Token[] = [], records: Token[] = [];
  let previousLine = 0;
  const append = (kind: string, value: string, line: number, column: number, comment = false): void => {
    const record: Token = { kind, value, line, column, blank: Math.max(0, line - previousLine - 1),
      comment, index: -1, leading: [], trailing: [] };
    previousLine = line; records.push(record);
    if (comment) comments.push(record);
    else { record.index = tokens.length; record.leading = []; record.trailing = []; tokens.push(record); }
  };
  lines.forEach((source, lineIndex) => {
    let i = 0;
    while (i < source.length) {
      const start = i, line = lineIndex + 1, column = i + 1, character = source[i], pair = source.slice(i, i + 2);
      if (character === ' ') { i++; continue; }
      if (pair === '//') { append('line_comment', source.slice(i).replace(/ +$/, ''), line, column, true); break; }
      if (pair === '/*') {
        const end = source.indexOf('*/', i + 2);
        if (end < 0) throw new FormatError(line, column, 'unterminated comment');
        i = end + 2; append('block_comment', source.slice(start, i), line, column, true); continue;
      }
      if (letter(character)) {
        while (letter(source[i]) || digit(source[i])) i++;
        const value = source.slice(start, i);
        append(KEYWORDS.has(value) ? 'keyword' : 'identifier', value, line, column); continue;
      }
      if (digit(character)) {
        while (digit(source[i])) i++;
        if (source[i] === '.' && digit(source[i + 1])) { i++; while (digit(source[i])) i++; }
        append('number', source.slice(start, i), line, column); continue;
      }
      if (character === '"') {
        i++;
        while (i < source.length && source[i] !== '"') i += source[i] === '\\' ? 2 : 1;
        if (i >= source.length) throw new FormatError(line, column, 'unterminated string');
        i++; append('string', source.slice(start, i), line, column); continue;
      }
      if (DOUBLE_SYMBOLS.has(pair)) { append('symbol', pair, line, column); i += 2; continue; }
      if ('+-*/%<>=!()[]{},;.?:'.includes(character)) { append('symbol', character, line, column); i++; continue; }
      throw new FormatError(line, column, "unexpected character '" + character + "'");
    }
  });
  tokens.push({ kind: 'end', value: '', line: lines.length + 1, column: 1, blank: 0, index: tokens.length, leading: [], trailing: [] });
  return { tokens, comments, records };
}

