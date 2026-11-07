import type { FormulaToken } from './types.ts';
export class FormulaError extends Error {
  column: number;
  constructor(column: number, message: string) { super(message); this.column = column; }
}

export const GREEK = new Set<string>(('alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi pi rho sigma tau upsilon phi chi psi omega '
  + 'Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega').split(' '));
export const SYMBOL_COMMANDS = new Map<string, {display: string; type: string}>();
for (const name of GREEK) SYMBOL_COMMANDS.set('\\' + name, { display: name, type: 'ordinary' });
for (const [name, display] of [['cdot', '*'], ['times', 'x'], ['pm', '+-'], ['mp', '-+']]) {
  SYMBOL_COMMANDS.set('\\' + name, { display, type: 'binary' });
}
for (const [name, display] of [['leq', '<='], ['geq', '>='], ['neq', '!='], ['approx', '~='], ['to', '->']]) {
  SYMBOL_COMMANDS.set('\\' + name, { display, type: 'relation' });
}
for (const [name, display] of [['infty', 'oo'], ['ldots', '...'], ['cdots', '...'], ['quad', '  '], [',', ' ']]) {
  SYMBOL_COMMANDS.set('\\' + name, { display, type: 'ordinary' });
}
SYMBOL_COMMANDS.set('\\{', { display: '{', type: 'open' });
SYMBOL_COMMANDS.set('\\}', { display: '}', type: 'close' });
for (const name of 'sin cos tan log ln exp det lim max min sum prod int'.split(' ')) {
  SYMBOL_COMMANDS.set('\\' + name, { display: name, type: 'operator' });
}
export const COMMAND_NAMES = new Set<string>(Array.from(SYMBOL_COMMANDS.keys()).map(value => value.slice(1)).filter(value => /^[A-Za-z]+$/.test(value)));
const ACCENTS = new Set('overline hat vec dot tilde overbrace underbrace'.split(' '));
const RAW_COMMANDS = new Set(['text', 'begin', 'end', 'tag', 'label', 'eqref']);
const ENVIRONMENTS = new Set(['matrix', 'pmatrix', 'bmatrix', 'vmatrix', 'cases']);
const CONSTRUCTS = new Set(['frac', 'binom', 'overset', 'underset', 'sqrt', 'left', 'right']);
const letter = (character: string | undefined): boolean => character !== undefined && /[A-Za-z]/.test(character);
const digit = (character: string | undefined): boolean => character !== undefined && character >= '0' && character <= '9';

export function tokenize(line: string): FormulaToken[] {
  const tokens: FormulaToken[] = [];
  let index = 0;
  const append = (kind: string, value: string, column: number): number => tokens.push({ kind, value, column });
  while (index < line.length) {
    const start = index, character = line[index], column = start + 1;
    if (character === ' ') { index++; continue; }
    if (letter(character)) {
      while (letter(line[index])) index++;
      append('identifier', line.slice(start, index), column); continue;
    }
    if (digit(character)) {
      while (digit(line[index])) index++;
      if (line[index] === '.' && digit(line[index + 1])) { index++; while (digit(line[index])) index++; }
      append('number', line.slice(start, index), column); continue;
    }
    if ('+-*/=<>:()[],;.!|\''.includes(character)) { append('symbol', character, column); index++; continue; }
    if ('{}^_&'.includes(character)) { append(character, character, column); index++; continue; }
    if (character !== '\\') throw new FormulaError(column, 'invalid character ' + character);
    index++;
    if (line[index] === '\\') { append('newline', '\\\\', column); index++; continue; }
    if (['{', '}', ','].includes(line[index])) { append('command', '\\' + line[index++], column); continue; }
    const nameStart = index;
    while (letter(line[index])) index++;
    const name = line.slice(nameStart, index);
    if (name === '') throw new FormulaError(column, 'invalid command');
    if (RAW_COMMANDS.has(name)) {
      while (line[index] === ' ') index++;
      if (line[index] !== '{') throw new FormulaError(index + 1, 'expected {');
      const end = line.indexOf('}', index + 1);
      if (end < 0) throw new FormulaError(column, 'unterminated argument');
      const argument = line.slice(index + 1, end); index = end + 1;
      if ((name === 'begin' || name === 'end') && !ENVIRONMENTS.has(argument)) {
        throw new FormulaError(column, `unknown environment "${argument}"`);
      }
      append(name, argument, column);
    } else if (SYMBOL_COMMANDS.has('\\' + name)) append('command', '\\' + name, column);
    else if (ACCENTS.has(name)) append('accent', name, column);
    else if (CONSTRUCTS.has(name)) append(name, name, column);
    else throw new FormulaError(column, 'unknown command \\' + name);
  }
  append('eof', '', line.length + 1);
  return tokens;
}

